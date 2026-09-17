defmodule Karakuri.Executor do
  alias Karakuri.Executor.Execution
  alias Karakuri.Executor.Execution.Step
  alias Karakuri.Executor.Workflow.Step, as: WorkflowStep

  def execute(workflow, %{} = args) do
    {status, steps} =
      Enum.reduce_while(workflow.steps, {:completed, []}, fn step, {_status, executed_steps} ->
        with {:ok, input} <- extract_input(step, executed_steps, args),
             {:ok, current} <- execute_step(step, input) do
          {:cont, {:completed, [current | executed_steps]}}
        else
          {:error, %Step{} = current} ->
            {:halt, {:failed, [current | executed_steps]}}

          {:error, reason} ->
            {:halt,
             {:failed,
              [
                %Step{base_execution_step(step, step.input) | error: reason, status: :failed}
                | executed_steps
              ]}}
        end
      end)

    %Execution{workflow: workflow, status: status, steps: Enum.reverse(steps)}
  end

  def extract_input(%WorkflowStep{input: input}, executed_steps, args) do
    {:ok,
     Enum.reduce(input, %{}, fn {key, value}, acc ->
       value =
         case value do
           {:args, field} ->
             Map.fetch!(args, field)

           {:ref, step_name, field} ->
             case Enum.find(executed_steps, fn s -> s.name == step_name end) do
               nil -> raise KeyError, "Bad reference: Step #{step_name} not found"
               step -> Map.fetch!(step.output, field)
             end

           _ ->
             value
         end

       Map.put(acc, key, value)
     end)}
  rescue
    exception -> {:error, {:input_error, Exception.format(:error, exception)}}
  end

  defp execute_step(step, input) do
    base = base_execution_step(step, input)

    try do
      case step.tool.execute(input) do
        {:ok, output} -> {:ok, %Step{base | output: output, status: :completed}}
        {:error, reason} -> {:error, %Step{base | error: {:tool_result, reason}, status: :failed}}
      end
    rescue
      e ->
        {:error,
         %Step{
           base
           | error: {:tool_error, Exception.format(:error, e, __STACKTRACE__)},
             status: :failed
         }}
    catch
      :exit, reason -> {:error, %Step{base | error: {:exit, reason}, status: :failed}}
    end
  end

  defp base_execution_step(step, input) do
    %Step{name: step.name, order: step.order, input: input}
  end
end
