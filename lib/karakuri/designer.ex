defmodule Karakuri.Designer do
  alias Karakuri.Designer.Registry
  alias Karakuri.Designer.Session
  alias Karakuri.Designer.Compiler

  alias Karakuri.Executor
  alias Karakuri.Executor.Workflow

  @max_attempts 3

  def start_session(requirement, sample) do
    Registry.create_session(requirement, sample)
  end

  def check_workflow(session_id, json_spec) do
    {:ok, session} = Registry.get_session(session_id)

    {:ok, session} =
      session
      |> Map.put(:spec, json_spec)
      |> run()
      |> update_session()

    check_result(session)
  end

  def submit_workflow(_session_id) do
    # Implementation for submitting the workflow
  end

  def report_impossible(_session_id) do
    # Implementation for reporting an impossible workflow
  end

  defp check_result(session) do
    case session do
      %Session{status: :completed, workflow: workflow, execution: execution} ->
        {:ok, workflow, execution}

      %Session{status: :failed} = failed_session ->
        {:error, failed_session}

      %Session{status: :impossible} = impossible_session ->
        {:error, impossible_session}

      %Session{status: _wip} = wip_session ->
        {:error, wip_session}
    end
  end

  defp run(%Session{status: status, attempts: n} = session)
       when status in [:completed, :failed, :impossible],
       do: %Session{session | attempts: n + 1}

  defp run(%Session{attempts: n} = session) when n >= @max_attempts,
    do: %Session{session | status: :failed}

  defp run(%Session{status: :drafting} = session),
    do: %Session{session | status: :compiling} |> run()

  defp run(%Session{status: :compiling} = session), do: session |> compile() |> run()
  defp run(%Session{status: :testing} = session), do: session |> test() |> run()

  # Compile the session into a workflow
  defp compile(%Session{} = session) do
    {:ok, _} = Compiler.compile(session.spec)
    %Session{session | status: :testing, workflow: %Workflow{name: "the_answer_to_life"}}
  end

  defp test(%Session{} = session) do
    execution = Executor.execute(session.workflow, session.sample |> Jason.decode!())
    %Session{session | status: execution.status, execution: execution}
  end

  defp update_session(session) do
    Registry.get_and_update(session.id, fn _ -> session end)
  end
end
