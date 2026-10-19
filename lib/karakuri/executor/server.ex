defmodule Karakuri.Executor.Server do
  use GenServer

  alias Karakuri.Executor.Workflow
  alias Karakuri.Executor.Execution
  alias Karakuri.Executor

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: opts[:name] || __MODULE__)
  end

  def reset() do
    GenServer.cast(__MODULE__, :reset)
  end

  def get_workflow_names() do
    GenServer.call(__MODULE__, :get_workflow_names)
  end

  def get_workflow(name) do
    GenServer.call(__MODULE__, {:get_workflow, name})
  end

  def start_workflow(name, input) do
    GenServer.cast(__MODULE__, {:start_workflow, name, input})
  end

  def put_workflow(workflow) do
    GenServer.call(__MODULE__, {:put_workflow, workflow})
  end

  def get_last_execution(workflow_name) do
    GenServer.call(__MODULE__, {:get_last_execution, workflow_name})
  end

  def get_executions(workflow_name) do
    GenServer.call(__MODULE__, {:get_executions, workflow_name})
  end

  def init(:ok) do
    state = %{execution_ref: nil, execution_workflow: nil}
    {:ok, Map.merge(state, set_examples())}
  end

  defp set_examples() do
    example_workflow = Workflow.example_extract_number()
    %{workflows: %{example_workflow.name => example_workflow}, executions: %{}}
  end

  def handle_cast(:reset, state) do
    {:noreply, Map.merge(state, set_examples())}
  end

  def handle_cast({:start_workflow, name, input}, %{execution_ref: nil} = state) do
    workflow = Map.get(state.workflows, name)
    pid = self()

    task =
      Task.Supervisor.async_nolink(Karakuri.Executor.TaskSupervisor, fn ->
        Executor.execute(workflow, input, pid)
      end)

    execution = %Execution{workflow: workflow.name, status: :in_progress, steps: []}

    {:noreply,
     %{
       state
       | execution_ref: task.ref,
         execution_workflow: workflow.name,
         executions: Map.put(state.executions, workflow.name, execution)
     }}
  end

  def handle_cast({:start_workflow, name, _input}, %{execution_ref: _ref} = state) do
    # TODO handle case when a workflow is already running
    dbg("Workflow #{name} is already running.")
    {:noreply, state}
  end

  def handle_call(:get_workflow_names, _from, state) do
    {:reply, Map.keys(state.workflows), state}
  end

  def handle_call({:get_workflow, name}, _from, state) do
    {:reply, Map.get(state.workflows, name), state}
  end

  def handle_call({:put_workflow, workflow}, _from, state) do
    {:reply, :ok, %{state | workflows: Map.put(state.workflows, workflow.name, workflow)}}
  end

  def handle_call({:get_last_execution, workflow_name}, _from, state) do
    {:reply, Map.get(state.executions, workflow_name), state}
  end

  def handle_call({:get_executions, workflow_name}, _from, state) do
    {:reply,
     Enum.filter(state.executions, fn {_id, exec} -> exec.workflow == workflow_name end)
     |> Enum.map(&elem(&1, 1)), state}
  end

  def handle_info({:notify, :step_started, workflow_name, step}, state) do
    broadcast_execution_event(:step_started, workflow_name, step)
    execution = Map.get(state.executions, workflow_name)
    execution = %{execution | steps: execution.steps ++ [step]}

    {:noreply, %{state | executions: Map.put(state.executions, workflow_name, execution)}}
  end

  def handle_info({:notify, :step_finished, workflow_name, step}, state) do
    broadcast_execution_event(:step_finished, workflow_name, step)
    execution = Map.get(state.executions, workflow_name)
    execution = %{execution | steps: List.replace_at(execution.steps, -1, step)}

    {:noreply, %{state | executions: Map.put(state.executions, workflow_name, execution)}}
  end

  def handle_info({:notify, :workflow_finished, workflow_name, output}, state) do
    broadcast_execution_event(:workflow_finished, workflow_name, output)
    execution = Map.get(state.executions, workflow_name)
    execution = %{execution | output: output}
    state = %{state | executions: Map.put(state.executions, workflow_name, execution)}
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{execution_ref: ref} = state)
      when reason != :normal do
    broadcast_execution_event(:workflow_failed, state.execution_workflow, reason)
    execution = Map.get(state.executions, state.execution_workflow)
    execution = %{execution | status: :failed}
    state = %{state | executions: Map.put(state.executions, execution.workflow, execution)}
    {:noreply, %{state | execution_ref: nil, execution_workflow: nil}}
  end

  def handle_info({ref, execution}, %{execution_ref: ref} = state) do
    # dbg("Received execution result for execution_ref: #{inspect(ref)}: #{inspect(execution)}")
    state = %{state | executions: Map.put(state.executions, execution.workflow, execution)}
    {:noreply, %{state | execution_ref: nil, execution_workflow: nil}}
  end

  def handle_info(_msg, state) do
    # dbg(msg)
    {:noreply, state}
  end

  defp broadcast_execution_event(event, workflow_name, payload) do
    Phoenix.PubSub.broadcast(
      Karakuri.PubSub,
      "execution_event",
      {:notify, event, workflow_name, payload}
    )
  end
end
