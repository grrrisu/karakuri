defmodule Karakuri.DesignerTest do
  use ExUnit.Case, async: false

  alias Karakuri.Designer
  alias Karakuri.Designer.Registry

  @requirement "Calculate the answer to life, the universe, and everything."
  @sample "And the answer is 42."

  setup do
    Registry.clear()
    on_exit(fn -> Registry.clear() end)
  end

  test "starts a new designer session" do
    assert {:ok, session} = Designer.start_session(@requirement, @sample)
    assert session.requirement == @requirement
    assert session.sample == @sample
    assert session.status == :drafting
  end

  test "check workflow" do
    assert {:ok, session} = Designer.start_session(@requirement, @sample)
    Designer.check_workflow(session.id, "{}")
  end
end
