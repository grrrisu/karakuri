defmodule Karakuri.Designer.Actions.CheckWorkflow do
  use Jido.Action,
    name: "check_workflow",
    description: """
    Compile a workflow spec and dry-run it on the sample input.
    Returns each step's output, or the errors. Costs one check from your budget.
    """,
    schema: [
      spec: [type: :string, required: true, doc: "The workflow spec as a JSON string."]
    ]

  alias Karakuri.Designer

  @impl true
  def run(%{spec: spec}, %{session_id: session_id}) do
    {:ok, Designer.check_workflow(session_id, spec)}
  end
end
