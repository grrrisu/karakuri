defmodule Karakuri.Designer.Registry do
  @moduledoc """
  Holds the designer sessions (`%Karakuri.Designer.Session{}`) in memory, keyed by id.
  """
  use GenServer

  alias Karakuri.Designer.Agent, as: DesignerAgent
  alias Karakuri.Designer.Jido
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
      |> start_agent_task()

    {:reply, {:ok, session}, Map.put(sessions, session.id, session)}
  end

  def handle_call({:get_session, id}, _from, sessions) do
    case Map.fetch(sessions, id) do
      {:ok, session} -> {:reply, {:ok, session}, sessions}
      :error -> {:reply, {:error, :not_found}, sessions}
    end
  end

  def handle_call({:get_and_update, id, changes}, _from, sessions) do
    with {:ok, session} <- Map.fetch(sessions, id),
         {:ok, updated} <- apply_changes(session, changes) do
      {:reply, {:ok, updated}, Map.put(sessions, id, updated)}
    else
      :error -> {:reply, {:error, :not_found}, sessions}
      {:error, _reason} = error -> {:reply, error, sessions}
    end
  end

  def handle_call(:clear, _from, _sessions), do: {:reply, :ok, %{}}

  @impl true
  def handle_info({_ref, session}, sessions) do
    {:noreply,
     update_session(sessions, session.id, fn current ->
       %{current | messages: session.messages, status: session.status, feedback: session.feedback}
     end)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, sessions), do: {:noreply, sessions}

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

  defp start_agent_task(session) do
    session = start_agent(session)

    task =
      Task.Supervisor.async_nolink(Karakuri.Designer.TaskSupervisor, fn ->
        case agent_module().ask_stream(session.agent_pid, generate_prompt(session)) do
          {:ok, %{request: request, events: events}} ->
            session = %{session | messages: events}

            agent_module().await(request, timeout: 60_000)
            |> agent_result(session)

          {:error, reason} ->
            agent_task_finished(session, {:error, reason})
        end
      end)

    Map.put(session, :agent_task, task)
  end

  defp agent_result(response, session) do
    case response do
      {:ok, result} ->
        agent_task_finished(session, {:ok, result})

      {:error, reason} ->
        agent_task_finished(session, {:error, reason})
    end
  end

  defp agent_module do
    Application.get_env(:karakuri, :designer_agent_module, Karakuri.Designer.Agent)
  end

  def start_agent(session) do
    if agent_module().mocked?() do
      Map.put(session, :agent_pid, self())
    else
      agent_id = "designer-#{System.unique_integer([:positive])}"
      {:ok, pid} = Jido.start_agent(DesignerAgent, id: agent_id)
      Map.put(session, :agent_pid, pid)
    end
  end

  def agent_task_finished(session, result) do
    status =
      case result do
        {:ok, _} -> :completed
        {:error, _} -> :failed
        _ -> :drafting
      end

    %{session | status: status, feedback: result}
  end

  defp generate_prompt(session) do
    """
    <requirement>
    #{session.requirement}
    </requirement>
    <sample_input>
    #{session.sample}
    </sample_input>
    """
  end

  defp update_session(sessions, session_id, fun) do
    case Map.fetch(sessions, session_id) do
      {:ok, session} -> Map.put(sessions, session_id, fun.(session))
      :error -> sessions
    end
  end
end
