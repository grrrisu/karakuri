defmodule KarakuriWeb.WorkflowLive.Components do
  use Phoenix.Component

  alias Phoenix.Naming

  import KarakuriWeb.CoreComponents

  def reset_button(assigns) do
    ~H"""
    <div class="flex justify-end">
      <.button id="reset-workflows" phx-click="reset">
        <.icon
          name="hero-arrow-uturn-left"
          class="size-4"
        /> Reset
      </.button>
    </div>
    """
  end

  def bg_class_for_status(status) do
    Map.get(
      %{
        in_progress: "bg-info",
        completed: "bg-success",
        failed: "bg-error"
      },
      status
    )
  end

  def workflow_steps(assigns) do
    execution_steps = (assigns.execution && Map.get(assigns.execution, :steps)) || []

    steps =
      Enum.reduce(assigns.workflow_steps, [], fn step, acc ->
        execution_step =
          execution_steps |> Enum.find(&(&1.name == step.name))

        acc ++ [{step, execution_step}]
      end)

    assigns =
      assign(assigns,
        steps: steps,
        started: !is_nil(assigns.execution),
        finished: get_in(List.last(steps), [Access.elem(1), Access.key(:status)]) == :completed,
        started_at: get_in(List.first(steps), [Access.elem(1), Access.key(:started_at)]),
        finished_at: get_in(List.last(steps), [Access.elem(1), Access.key(:finished_at)])
      )

    ~H"""
    <ul class="timeline timeline-vertical">
      <li>
        <div class="timeline-start">
          <.time time={@started_at} />
        </div>
        <div class="timeline-middle">
          <.icon name="hero-inbox-arrow-down" class="size-4" />
        </div>
        <div class="timeline-end w-full">
          {render_slot(@workflow_input)}
        </div>
        <hr class={@started && "bg-success"} />
      </li>
      <.workflow_step
        :for={{workflow_step, execution_step} <- @steps}
        step={workflow_step}
        execution_step={execution_step}
        :key={workflow_step.name}
      />
      <li>
        <hr class={@finished && "bg-success"} />
        <div class="timeline-start">
          <.time time={@finished_at} />
        </div>
        <div class="timeline-middle">
          <.icon name="hero-inbox-arrow-down" class="size-4" />
        </div>
        <div class="timeline-end timeline-box min-w-full min-h-10">
          {render_slot(@workflow_output)}
        </div>
      </li>
    </ul>
    """
  end

  def workflow_step(assigns) do
    status = assigns.execution_step && Map.get(assigns.execution_step, :status)

    time =
      assigns.execution_step &&
        (Map.get(assigns.execution_step, :finished_at) ||
           Map.get(assigns.execution_step, :started_at))

    assigns =
      assign(assigns,
        name: Naming.humanize(assigns.step.name),
        tool:
          assigns.step.tool
          |> Atom.to_string()
          |> String.replace(~r/Elixir.Karakuri.Executor.Tool./, "")
          |> Naming.humanize(),
        inputs:
          assigns.step.input |> Map.keys() |> Enum.map(&Naming.humanize/1) |> Enum.join(", "),
        status: status,
        time: time,
        bg_class: bg_class_for_status(status)
      )

    ~H"""
    <li id={"workflow-step-#{@step.name}"}>
      <hr class={@bg_class} />
      <div class="timeline-start">
        <.time time={@time} />
      </div>
      <div class="timeline-middle">
        <.icon
          :if={@status == :in_progress}
          name="hero-cog-6-tooth animate-spin"
          class="size-4 bg-info"
        />
        <.icon :if={@status == :completed} name="hero-check-circle" class="size-4 bg-success" />
        <.icon :if={@status == :failed} name="hero-x-circle" class="size-4 bg-error" />
      </div>
      <div class="timeline-end timeline-box w-full">
        <p><strong>{@name}</strong></p>
        <p><.icon name="hero-cog-6-tooth" class="size-4" /> {@tool}</p>
        <p>Inputs: {@inputs}</p>
        <p>Output: {@execution_step |> inspect()}</p>
      </div>
      <hr class={@bg_class} />
    </li>
    """
  end

  def time(%{time: nil} = assigns) do
    ~H"""
    <span>--:--:--.---</span>
    """
  end

  def time(assigns) do
    assigns =
      assign(assigns, :time, Calendar.strftime(assigns.time, "%H:%M:%S.%3f"))

    ~H"""
    <span>{@time}</span>
    """
  end
end
