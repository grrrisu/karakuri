defmodule Karakuri.Executor.ExecutorTest do
  use ExUnit.Case

  alias Karakuri.Executor
  alias Karakuri.Executor.Workflow
  alias Karakuri.Executor.Workflow.Step
  alias Karakuri.Executor.Tool.Regex, as: RegexTool

  setup do
    step = %Step{name: "one", order: 0, tool: RegexTool, input: %{pattern: ~r/\d+/}}
    workflow = %Workflow{name: "test", steps: [step]}
    {:ok, workflow: workflow}
  end

  test "execute workflow", %{workflow: workflow} do
    execution = Executor.execute(workflow, %{text: "The answer is 42"})
    assert execution.status == :completed
    last_step = List.last(execution.steps)
    assert last_step |> Map.get(:output) == "42"
    assert last_step |> Map.get(:status) == :completed
  end

  test "execute workflow with no match", %{workflow: workflow} do
    execution = Executor.execute(workflow, %{text: "No numbers here"})
    assert execution.status == :failed
    last_step = List.last(execution.steps)
    assert last_step |> Map.get(:error) == "no match"
    assert last_step |> Map.get(:status) == :failed
  end

  test "fails executing workflow", %{workflow: workflow} do
    execution = Executor.execute(workflow, %{text: nil})
    assert execution.status == :failed
    last_step = List.last(execution.steps)
    assert last_step |> Map.get(:error) =~ "no function clause matching in Regex.run/3"
    assert last_step |> Map.get(:status) == :failed
  end
end
