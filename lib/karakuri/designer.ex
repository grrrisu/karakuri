defmodule Karakuri.Designer do
  alias Karakuri.Designer.Registry
  alias Karakuri.Designer.Session
  alias Karakuri.Designer.Compiler

  alias Karakuri.Executor
  alias Karakuri.Executor.Workflow
  alias Karakuri.Executor.Execution

  @max_attempts 3

  def start_session(requirement, sample) do
    Registry.create_session(requirement, sample)
  end

  def check_workflow(session_id, json_spec) do
    {:ok, session} = Registry.get_session(session_id)

    session
    |> check_attempts()
    |> save_spec(json_spec)
    |> compile()
    |> test()
    |> save_result()
    |> check_result()
  end

  def submit_workflow(_session_id) do
    # Implementation for submitting the workflow
  end

  def report_impossible(_session_id) do
    # Implementation for reporting an impossible workflow
  end

  # Compile the session into a workflow
  defp compile(%Session{status: :running} = session) do
    {:ok, _} = Compiler.compile(session.spec)
    %Session{session | status: :compiled, workflow: %Workflow{name: "the_answer_to_life"}}
  end

  defp compile(%Session{status: :failed} = session), do: session

  defp test(%Session{status: :compiled} = session) do
    input = %{session.workflow.input => session.sample}
    execution = Executor.execute(session.workflow, input)
    status = if execution.status == :completed, do: :passed, else: :failed
    %Session{session | status: status, execution: execution}
  end

  defp test(%Session{status: :failed} = session), do: session

  defp check_attempts(%Session{attempts: attempts} = session) when attempts >= @max_attempts do
    %Session{session | status: :failed, reason: "max compile attempts reached"}
  end

  defp check_attempts(session), do: session

  defp check_result(session) do
    case session do
      %Session{status: :passed, workflow: _workflow, execution: execution} ->
        %{
          status: "check passed",
          output: execution.output,
          steps: execution_steps(execution)
        }

      %Session{status: :failed, reason: reason, execution: execution, attempts: attempts} ->
        if attempts < @max_attempts do
          %{status: "failed", reason: reason, steps: execution_steps(execution)}
        else
          %{
            status: "failed",
            feedback: "check budget exhausted (#{attempts} checks used)",
            reason: reason,
            attempts: attempts,
            steps: execution_steps(execution)
          }
        end
    end
  end

  defp save_spec(%Session{status: :failed} = session, _), do: session

  defp save_spec(session, json_spec) do
    {:ok, session} =
      Registry.get_and_update(session.id, fn stored ->
        %{
          stored
          | attempts: stored.attempts + 1,
            status: :running,
            spec: json_spec
        }
      end)

    session
  end

  defp save_result(session) do
    {:ok, session} =
      Registry.get_and_update(session.id,
        status: session.status,
        workflow: session.workflow,
        execution: session.execution
      )

    session
  end

  defp execution_steps(nil), do: []

  defp execution_steps(%Execution{steps: steps}) do
    Enum.map(steps, fn step ->
      %{
        name: step.name,
        output: step.output,
        error: step.error |> step_error()
      }
    end)
  end

  defp step_error({error_type, reason}), do: "#{error_type}: #{reason}"
  defp step_error(error), do: error
end
