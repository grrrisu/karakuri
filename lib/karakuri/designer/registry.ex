defmodule Karakuri.Designer.Registry do
  @moduledoc """
  Holds the designer sessions (`%Karakuri.Designer.Session{}`) in memory, keyed by id.
  """
  use GenServer

  alias Karakuri.Designer.AgentTask
  alias Karakuri.Designer.Session

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    sessions = Keyword.get(opts, :sessions, %{})
    GenServer.start_link(__MODULE__, sessions, name: name)
  end

  @doc "Creates a new session in `:drafting` status with a generated id."
  def create_session(server \\ __MODULE__, requirement, sample) do
    GenServer.call(server, {:create_session, requirement, sample})
  end

  @doc "Returns the session with the given id."
  def get_session(server \\ __MODULE__, id) do
    GenServer.call(server, {:get_session, id})
  end

  @doc "Clears all sessions."
  def clear(server \\ __MODULE__) do
    GenServer.call(server, :clear)
  end

  @doc """
  Finds the session, updates it and returns the updated session.

  `changes` is either a keyword list / map of fields or a function receiving the session.
  """
  def get_and_update(server \\ __MODULE__, id, changes) do
    GenServer.call(server, {:get_and_update, id, changes})
  end

  @impl true
  def init(sessions), do: {:ok, sessions}

  @impl true
  def handle_call({:create_session, requirement, sample}, _from, sessions) do
    session =
      %Session{
        id: Ecto.UUID.generate(),
        requirement: requirement,
        sample: sample,
        status: :drafting
      }
      |> AgentTask.start(self())

    {:reply, {:ok, session}, Map.put(sessions, session.id, session)}
  end

  def handle_call({:get_session, id}, _from, sessions) do
    case Map.fetch(sessions, id) do
      {:ok, session} -> {:reply, {:ok, session}, sessions}
      :error -> {:reply, {:error, :not_found}, sessions}
    end
  end

  def handle_call({:get_and_update, session_id, changes}, _from, sessions) do
    case update_session(sessions, session_id, changes) do
      {:error, reason} -> {:reply, {:error, reason}, sessions}
      {:ok, updated, sessions} -> {:reply, {:ok, updated}, sessions}
    end
  end

  def handle_call(:clear, _from, sessions) do
    shutdown_session_tasks(sessions)
    {:reply, :ok, %{}}
  end

  @impl true
  def terminate(_reason, sessions) do
    shutdown_session_tasks(sessions)
    :ok
  end

  @impl true
  def handle_info({task_ref, _result}, sessions) do
    {:noreply, clear_agent_task(sessions, task_ref)}
  end

  @impl true
  def handle_info({:DOWN, task_ref, :process, _pid, _reason}, sessions) do
    {:noreply, clear_agent_task(sessions, task_ref)}
  end

  defp update_session(sessions, session_id, changes) do
    with {:ok, session} <- Map.fetch(sessions, session_id),
         {:ok, updated} <- apply_changes(session, changes) do
      {:ok, updated, Map.put(sessions, session_id, updated)}
    else
      :error -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp clear_agent_task(sessions, task_ref) do
    session =
      Enum.find_value(sessions, fn
        {session_id, %Session{agent_task: %Task{ref: ^task_ref}}} -> session_id
        _entry -> nil
      end)

    case session do
      nil -> sessions
      session_id -> Map.update!(sessions, session_id, &%{&1 | agent_task: nil})
    end
  end

  defp apply_changes(session, fun) when is_function(fun, 1) do
    case fun.(session) do
      %Session{id: id} = updated when id == session.id -> {:ok, updated}
      _ -> {:error, :invalid_update}
    end
  end

  defp apply_changes(session, changes) when is_list(changes) or is_map(changes) do
    if Enum.any?(changes, fn {key, _} -> key == :id end) do
      {:error, :invalid_update}
    else
      {:ok, struct!(session, changes)}
    end
  rescue
    KeyError -> {:error, :invalid_update}
  end

  defp shutdown_session_tasks(sessions) do
    Enum.each(sessions, fn
      {_id, %Session{agent_task: %Task{} = task}} -> Task.shutdown(task, :brutal_kill)
      _entry -> :ok
    end)
  end
end
