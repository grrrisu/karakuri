defmodule Karakuri.Executor do
  alias Karakuri.Executor.Workflow
  alias Karakuri.Executor.Execution
  alias Karakuri.Executor.Execution.Step
  alias Karakuri.Executor.Workflow.Step, as: WorkflowStep

  def execute(%Workflow{} = workflow, %{} = args, pid \\ nil) do
    pid = pid || self()

    {status, steps} =
      Enum.reduce_while(workflow.steps, {:completed, []}, fn workflow_step,
                                                             {_status, executed_steps} ->
        {enum_state, {status, executed_step}} =
          execute_step(workflow.name, workflow_step, executed_steps, args, pid)

        {enum_state, {status, [executed_step | executed_steps]}}
      end)

    send(pid, {:notify, :workflow_finished, workflow.name})
    %Execution{workflow: workflow.name, status: status, steps: Enum.reverse(steps)}
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

  defp execute_step(workflow_name, step, executed_steps, args, pid) do
    with {:ok, input} <- extract_input(step, executed_steps, args),
         _msg <- notify_step_started(pid, workflow_name, step, input),
         # _ <- Process.sleep(500),
         {:ok, current} <- execute_each(step, input),
         _msg <- notfiy_step_finished(pid, workflow_name, current) do
      {:cont, {:completed, current}}
    else
      {:error, %Step{} = current} ->
        {:halt, {:failed, current}}

      {:error, reason} ->
        {:halt,
         {:failed, %Step{base_execution_step(step, step.input) | error: reason, status: :failed}}}
    end
  end

  defp notify_step_started(pid, workflow_name, step, input) do
    execution_step = %Step{
      base_execution_step(step, input)
      | status: :in_progress,
        started_at: DateTime.utc_now()
    }

    notify(pid, :step_started, workflow_name, execution_step)
  end

  defp notfiy_step_finished(pid, workflow_name, executed_step) do
    notify(pid, :step_finished, workflow_name, executed_step)
  end

  defp notify(pid, event, workflow_name, payload) do
    send(pid, {:notify, event, workflow_name, payload})
  end

  defp execute_each(%WorkflowStep{} = step, input) do
    base = base_execution_step(step, input)

    try do
      case step.tool.execute(input) do
        {:ok, output} -> {:ok, successful_step(base, output)}
        {:error, reason} -> {:error, failed_step(base, {:tool_result, reason})}
      end
    rescue
      e ->
        {:error, failed_step(base, {:tool_error, Exception.format(:error, e, __STACKTRACE__)})}
    catch
      :exit, reason -> {:error, failed_step(base, {:exit, reason})}
    end
  end

  defp successful_step(%Step{} = base_step, output) do
    %Step{base_step | output: output, status: :completed, finished_at: DateTime.utc_now()}
  end

  defp failed_step(%Step{} = base_step, error_message) do
    %Step{base_step | error: error_message, status: :failed, finished_at: DateTime.utc_now()}
  end

  defp base_execution_step(step, input) do
    %Step{name: step.name, order: step.order, input: input}
  end
end
