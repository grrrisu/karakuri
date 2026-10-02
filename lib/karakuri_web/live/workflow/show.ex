defmodule KarakuriWeb.WorkflowLive.Show do
  use KarakuriWeb, :live_view

  alias Karakuri.Server
  import KarakuriWeb.WorkflowLive.Components

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Karakuri.PubSub, "execution_event")
    end

    {:ok, assign(socket, page_title: "Workflows")}
  end

  def handle_params(params, _uri, socket) do
    socket =
      assign_workflow_and_its_lastest_execution(socket, params["workflow"])

    {:noreply, socket}
  end

  def handle_event("reset", _params, socket) do
    Server.reset()

    {:noreply,
     socket |> put_flash(:info, "Data has been reset") |> push_navigate(to: ~p"/workflows")}
  end

  def handle_event("start_workflow", %{"workflow_name" => workflow_name} = params, socket) do
    input_key = socket.assigns.workflow.input || :input
    input = Map.get(params, input_key |> Atom.to_string())
    Server.start_workflow(workflow_name, %{input_key => input})

    socket =
      socket
      |> flash_notfication(:workflow_started, workflow_name)
      |> assign(workflow_name: workflow_name)

    {:noreply, socket}
  end

  def handle_info(
        {:notify, notification, workflow_name, _step},
        %{assigns: %{workflow_name: workflow_name}} = socket
      ) do
    socket =
      socket
      |> assign_workflow_and_its_lastest_execution(workflow_name)
      |> flash_notfication(notification, workflow_name)

    {:noreply, socket}
  end

  def handle_info({:notify, _notification, workflow_name, _step}, socket) do
    dbg("Received notification from another workflow: #{workflow_name}")
    {:noreply, socket}
  end

  defp assign_workflow_and_its_lastest_execution(socket, workflow_name) do
    assign(socket,
      workflow: Server.get_workflow(workflow_name),
      execution: Server.get_last_execution(workflow_name)
    )
  end

  defp flash_notfication(socket, notification, workflow_name) do
    case notification do
      :workflow_started -> put_flash(socket, :info, "Workflow #{workflow_name} started")
      :workflow_finished -> put_flash(socket, :info, "Workflow #{workflow_name} finished")
      :workflow_failed -> put_flash(socket, :error, "Workflow #{workflow_name} failed")
      _ -> socket
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.reset_button />
      <.main_title>Workflow {Phoenix.Naming.humanize(@workflow.name)}</.main_title>

      <.workflow_steps
        workflow_steps={@workflow.steps}
        execution={@execution}
      >
        <:workflow_input>
          <.input_form workflow={@workflow} />
        </:workflow_input>
        <:workflow_output :let={result}>
          <label class="text-gray-500">Result:</label>
          <span>{result}</span>
        </:workflow_output>
      </.workflow_steps>
    </Layouts.app>
    """
  end

  def input_form(assigns) do
    key = (assigns.workflow.input || :input) |> Atom.to_string()

    assigns =
      assign(assigns,
        label: key |> Phoenix.Naming.humanize(),
        key: key,
        placeholder: "Enter #{key}"
      )

    ~H"""
    <form id="start-workflow-form" phx-submit="start_workflow">
      <div class="flex flex-row justify-center items-center gap-4">
        <div class="grow">
          <.input type="hidden" name="workflow_name" value={@workflow.name} />
          <.input
            type="textarea"
            label={@label}
            name={@key}
            placeholder={@placeholder}
            value=""
            tabindex="1"
          />
        </div>
        <.button tabindex="2  ">
          <.icon name="hero-play" class="size-4" /> Start
        </.button>
      </div>
    </form>
    """
  end
end
