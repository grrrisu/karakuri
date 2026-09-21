defmodule Karakuri.ServerTest do
  use ExUnit.Case, async: false

  alias Karakuri.Server

  setup do
    Phoenix.PubSub.subscribe(Karakuri.PubSub, "execution_event")
    Server.reset()
    :ok
  end

  test "runs the three-step extract number workflow" do
    text = "I sat at my desk, stared into the garden and thought \"42 will do\" I typed it out."
    assert :ok = Server.start_workflow("extract_number", %{text: text})

    assert_receive {:notify, :step_finished, "extract_number",
                    %{name: "number", status: :completed}}

    execution = Server.get_last_execution("extract_number")

    assert execution.status == :completed
    assert Enum.map(execution.steps, & &1.name) == ["sentence", "quote", "number"]
    assert Enum.map(execution.steps, & &1.status) == [:completed, :completed, :completed]
    assert List.last(execution.steps).output.match == "42"
  end

  test "receive execution notifications" do
    text = "I sat at my desk, stared into the garden and thought \"42 will do\" I typed it out."
    assert :ok = Server.start_workflow("extract_number", %{text: text})

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
end
