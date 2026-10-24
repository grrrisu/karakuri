defmodule Karakuri.Designer.AgentTask do
  alias Karakuri.Designer.Agent, as: DesignerAgent
  alias Karakuri.Designer.Jido
  alias Karakuri.Designer.Registry

  def start(session, registry) do
    session = start_jido_agent(session)

    task =
      Task.Supervisor.async_nolink(Karakuri.Designer.TaskSupervisor, fn ->
        case ask_stream(session) do
          {:ok, %{request: request, events: events}} ->
            session = update_session_events(registry, session, events)

            agent_module().await(request, timeout: 60_000)
            |> persist_result(session, registry)

          {:error, reason} ->
            persist_result({:error, reason}, session, registry)
        end
      end)

    Map.put(session, :agent_task, task)
  end

  defp start_jido_agent(session) do
    if agent_module().mocked?() do
      Map.put(session, :agent_pid, self())
    else
      agent_id = "designer-#{System.unique_integer([:positive])}"
      {:ok, pid} = Jido.start_agent(DesignerAgent, id: agent_id)
      Map.put(session, :agent_pid, pid)
    end
  end

  def ask_stream(session) do
    agent_module().ask_stream(session.agent_pid, generate_prompt(session),
      tool_context: %{session_id: session.id}
    )
  end

  defp update_session_events(registry, session, events) do
    Enum.reduce(events, session, fn event, current ->
      case safe_get_and_update(registry, current.id, fn stored ->
             %{stored | messages: stored.messages ++ [event]}
           end) do
        {:ok, updated} -> updated
        {:error, :not_found} -> current
      end
    end)
  end

  defp persist_result(result, session, registry) do
    status =
      case result do
        {:ok, _} -> :completed
        {:error, _} -> :failed
        _ -> :drafting
      end

    safe_get_and_update(registry, session.id, fn current ->
      %{current | status: status, feedback: result}
    end)
  end

  defp safe_get_and_update(registry, id, changes) do
    Registry.get_and_update(registry, id, changes)
  catch
    :exit, {:noproc, _reason} -> {:error, :not_found}
  end

  defp agent_module do
    Application.get_env(:karakuri, :designer_agent_module, Karakuri.Designer.Agent)
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
end
