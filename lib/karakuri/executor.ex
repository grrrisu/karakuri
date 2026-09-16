defmodule Karakuri.Executor do
  alias Karakuri.Executor.Execution
  alias Karakuri.Executor.Execution.Step

  def execute(workflow, %{} = args) do
    {status, steps} =
      Enum.reduce_while(workflow.steps, {:completed, []}, fn step, {_status, acc} ->
        input = Map.merge(step.input, args)

        case execute_step(step, input) do
          {:ok, current} -> {:cont, {:completed, [current | acc]}}
          {:error, current} -> {:halt, {:failed, [current | acc]}}
        end
      end)

    %Execution{workflow: workflow, status: status, steps: Enum.reverse(steps)}
  end

  defp execute_step(step, input) do
    base = %Step{name: step.name, order: step.order, input: input}

    try do
      case step.tool.execute(input) do
        {:ok, output} -> {:ok, %Step{base | output: output, status: :completed}}
        {:error, reason} -> {:error, %Step{base | error: reason, status: :failed}}
      end
    rescue
      e ->
        {:error,
         %Step{base | error: Exception.format(:error, e, __STACKTRACE__), status: :failed}}
    catch
      :exit, reason -> {:error, %Step{base | error: {:exit, reason}, status: :failed}}
    end
  end
end
