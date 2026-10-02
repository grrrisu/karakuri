defmodule Karakuri.DesignerTest do
  use ExUnit.Case

  alias Karakuri.Designer
  alias Karakuri.Workflows
  alias Karakuri.Executor

  @prompt "Design a workflow that calculates the answer to life, the universe, and everything."

  test "generates JSON with argument and output references" do
    assert {:ok, json} = Designer.generate(@prompt)
    assert {:ok, definition} = Jason.decode(json)

    assert definition["input"] == "text"
    assert definition["output"] == ["ref", "the_answer", "match"]
    assert [step] = definition["steps"]
    assert step["input"]["text"] == ["args", "text"]
    assert step["input"]["pattern"] == "\\d+"
  end

  test "designs, compiles and runs a workflow from a prompt" do
    {:ok, json} = Designer.generate(@prompt)
    {:ok, workflow} = Workflows.compile(json)
    execution = Executor.execute(workflow, @sample)

    assert execution.status == :completed
    assert execution.output == "42"
  end
end
