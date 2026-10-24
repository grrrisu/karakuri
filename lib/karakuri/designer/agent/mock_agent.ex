defmodule Karakuri.Designer.Agent.MockAgent do
  @behaviour Karakuri.Designer.Agent.Behaviour

  alias Karakuri.Designer.Actions.CheckWorkflow

  @result %{mocked: true} |> Jason.encode!()

  # :llm_completed: the agent’s text between tool calls.
  # :tool_started: “checking draft 2…”.
  # :tool_completed: the check result in the timeline.
  # :request_failed

  @impl true
  def ask_stream(_pid, message, opts \\ []) do
    session_id = Keyword.get(opts, :tool_context, %{}) |> Map.get(:session_id)
    request = %{id: "mock-request-#{System.unique_integer([:positive])}", status: :pending}

    # TODO simulate tool calls
    _result = CheckWorkflow.run(%{spec: "the json spec"}, %{session_id: session_id})

    events = [
      %{
        kind: :request_started,
        data: %{query: message, config_fingerprint: "mock-fingerprint"}
      },
      %{
        kind: :llm_started,
        llm_call_id: "mock-call-1",
        data: %{model: "mock:model", message_count: 2, call_id: "mock-call-1"}
      },
      %{
        kind: :request_completed,
        data: %{
          result: @result,
          termination_reason: :final_answer
        }
      }
    ]

    {:ok, %{request: request, events: events}}
  end

  @impl true
  def await(_request, _opts) do
    if Mix.env() == :dev, do: Process.sleep(1_000)
    {:ok, @result}
  end

  @impl true
  def mocked?(), do: true
end
