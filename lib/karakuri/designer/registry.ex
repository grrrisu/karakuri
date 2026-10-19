defmodule Karakuri.Designer.Registry do
  @moduledoc """
  Holds the designer sessions (`%Karakuri.Designer.Session{}`) in memory, keyed by id.
  """
  use GenServer

  alias Karakuri.Designer.Session

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc "Creates a new session in `:drafting` status with a generated id."
  def create_session(server \\ __MODULE__, requirement, sample) do
    GenServer.call(server, {:create_session, requirement, sample})
  end

  @doc "Returns the session with the given id."
  def get_session(server \\ __MODULE__, id) do
    GenServer.call(server, {:get_session, id})
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
    id = Ecto.UUID.generate()

    session = %Session{id: id, requirement: requirement, sample: sample, status: :drafting}

    {:reply, {:ok, session}, Map.put(sessions, id, session)}
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
end
