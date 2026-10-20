defmodule KarakuriWeb.WorkflowLive.Index do
  use KarakuriWeb, :live_view

  alias Karakuri.Executor.Server
  import KarakuriWeb.WorkflowLive.Components

  def mount(_params, _session, socket) do
    socket = assign_workflows(socket)
    {:ok, socket}
  end

  def handle_event("reset", _params, socket) do
    Server.reset()

    {:noreply, socket |> put_flash(:info, "Data has been reset") |> assign_workflows()}
  end

  defp assign_workflows(socket) do
    assign(socket, workflows: Server.get_workflow_names())
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.reset_button />
      <.main_title>Workflows</.main_title>

      <div :for={workflow <- @workflows} key={workflow}>
        <.link navigate={~p"/workflows/#{workflow}"}>
          <p><.icon name="hero-square-3-stack-3d" class="size-4" /> {workflow}</p>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
