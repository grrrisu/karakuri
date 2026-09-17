defmodule Karakuri.Executor.ExecutorTest do
  use ExUnit.Case

  alias Karakuri.Executor
  alias Karakuri.Executor.Workflow
  alias Karakuri.Executor.Workflow.Step, as: WorkflowStep
  alias Karakuri.Executor.Execution.Step, as: ExecutionStep
  alias Karakuri.Executor.Tool.Regex, as: RegexTool

  setup do
    step = %WorkflowStep{
      name: "one",
      tool: RegexTool,
      input: %{text: {:args, :text}, pattern: ~r/\d+/}
    }

    workflow = %Workflow{name: "test", steps: [step]}
    {:ok, workflow: workflow}
  end

  describe "extract_input/3" do
    test "extract input with literal value" do
      input = %{text: "literal", var: "a_value"}
      args = %{text: "The answer is 42"}

      assert {:ok, %{text: "literal", var: "a_value"}} ==
               Executor.extract_input(%WorkflowStep{input: input}, [], args)
    end

    test "extract input from args" do
      input = %{text: {:args, :text}, var: "a_value"}
      args = %{text: "The answer is 42"}

      assert {:ok,
              %{
                text: "The answer is 42",
                var: "a_value"
              }} == Executor.extract_input(%WorkflowStep{input: input}, [], args)
    end

    test "extract input from previous step" do
      input = %{text: {:ref, "step1", :match}, var: "a_value"}
      args = %{text: "The answer is 42"}
      steps = [%ExecutionStep{name: "step1", output: %{match: "42"}}]

      assert {:ok, %{text: "42", var: "a_value"}} ==
               Executor.extract_input(%WorkflowStep{input: input}, steps, args)
    end

    test "extract input returns a failed step when the referenced step is not found" do
      input = %{text: {:ref, "nonexistent_step", :match}, var: "a_value"}
      args = %{text: "The answer is 42"}

      assert {:error,
              {:input_error, "** (KeyError) Bad reference: Step nonexistent_step not found"}} ==
               Executor.extract_input(%WorkflowStep{input: input}, [], args)
    end
  end

  describe "execute/2" do
    test "execute workflow", %{workflow: workflow} do
      execution = Executor.execute(workflow, %{text: "The answer is 42"})
      assert execution.status == :completed
      last_step = List.last(execution.steps)
      assert last_step.output.match == "42"
      assert last_step.status == :completed
    end

    test "execute workflow with no match", %{workflow: workflow} do
      execution = Executor.execute(workflow, %{text: "No numbers here"})
      assert execution.status == :failed
      last_step = List.last(execution.steps)
      assert last_step.error == {:tool_result, "no match"}
      assert last_step.status == :failed
    end

    test "fails executing workflow", %{workflow: workflow} do
      execution = Executor.execute(workflow, %{text: nil})
      assert execution.status == :failed
      last_step = List.last(execution.steps)
      assert {:tool_error, _} = last_step.error
      assert last_step.status == :failed
    end

    test "a broken reference results in a failed execution" do
      workflow = %Workflow{
        name: "bad_ref",
        steps: [
          %WorkflowStep{
            name: "one",
            tool: RegexTool,
            input: %{text: {:ref, "unknown", :match}, pattern: ~r/\d+/}
          }
        ]
      }

      execution = Executor.execute(workflow, %{})

      assert execution.status == :failed
      assert [step] = execution.steps
      assert step.status == :failed
    end

    test "process a text over multiple steps" do
      text = """
      Some unrelated "wired crazy stuff" with another number 36.
      I sat at my desk, stared into the garden and thought "42 will do" I typed it out.
      End of story.
      """

      step1 = %WorkflowStep{
        name: "sentence",
        order: 0,
        tool: RegexTool,
        input: %{text: {:args, :text}, pattern: ~r/I sat at my desk[^.]+./}
      }

      step2 = %WorkflowStep{
        name: "quote",
        order: 1,
        tool: RegexTool,
        input: %{text: {:ref, "sentence", :match}, pattern: ~r/\"(.+?)\"/}
      }

      step3 = %WorkflowStep{
        name: "number",
        order: 2,
        tool: RegexTool,
        input: %{text: {:ref, "quote", :match}, pattern: ~r/\d+/}
      }

      workflow = %Workflow{name: "test", steps: [step1, step2, step3]}
      execution = Executor.execute(workflow, %{text: text})

      step_1 = Enum.at(execution.steps, 0)

      assert step_1.status == :completed

      assert step_1.output.match ==
               "I sat at my desk, stared into the garden and thought \"42 will do\" I typed it out."

      step_2 = Enum.at(execution.steps, 1)
      assert step_2.status == :completed
      assert step_2.output.match == "42 will do"

      step_3 = Enum.at(execution.steps, 2)
      assert step_3.status == :completed
      assert step_3.output.match == "42"

      assert execution.status == :completed
    end
  end
end
