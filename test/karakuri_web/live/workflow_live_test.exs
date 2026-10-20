defmodule KarakuriWeb.WorkflowLiveTest do
  use KarakuriWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Karakuri.Executor.Server

  setup do
    Server.reset()
    :ok
  end

  test "lists the example workflow", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/workflows")

    assert has_element?(view, "a[href='/workflows/extract_number']")
  end

  test "renders all three steps and runs the workflow from the form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/workflows/extract_number")

    assert has_element?(view, "#start-workflow-form")
    assert has_element?(view, "#workflow-step-sentence")
    assert has_element?(view, "#workflow-step-quote")
    assert has_element?(view, "#workflow-step-number")

    text = "I sat at my desk, stared into the garden and thought \"42 will do\" I typed it out."

    view
    |> form("#start-workflow-form")
    |> render_submit(%{"text" => text, "workflow_name" => "extract_number"})

    render(view)

    assert has_element?(view, "#workflow-step-sentence .bg-success")
    assert has_element?(view, "#workflow-step-quote .bg-success")
    assert has_element?(view, "#workflow-step-number .bg-success")
    assert has_element?(view, "#workflow-step-number", "42")
  end

  test "receive execution notifications", %{conn: conn} do
    Phoenix.PubSub.subscribe(Karakuri.PubSub, "execution_event")

    {:ok, view, _html} = live(conn, ~p"/workflows/extract_number")
    text = "I sat at my desk, stared into the garden and thought \"42 will do\" I typed it out."

    view
    |> form("#start-workflow-form")
    |> render_submit(%{"text" => text, "workflow_name" => "extract_number"})

    assert_receive {:notify, :step_started, "extract_number",
                    %{name: "sentence", status: :in_progress}}

    assert_receive {:notify, :step_finished, "extract_number",
                    %{name: "sentence", status: :completed}}

    assert_receive {:notify, :step_started, "extract_number",
                    %{name: "quote", status: :in_progress}}

    assert_receive {:notify, :step_finished, "extract_number",
                    %{name: "quote", status: :completed}}

    assert_receive {:notify, :step_started, "extract_number",
                    %{name: "number", status: :in_progress}}

    assert_receive {:notify, :step_finished, "extract_number",
                    %{name: "number", status: :completed}}
  end

  test "resets from the workflow view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/workflows/extract_number")

    view
    |> element("#reset-workflows")
    |> render_click()

    assert_redirect(view, "/workflows")
    assert Server.get_last_execution("extract_number") == nil
  end
end
