defmodule Karakuri.DesignerTest do
  use ExUnit.Case

  alias Karakuri.Designer
  alias Karakuri.Designer.Session
  alias Karakuri.Designer.Registry

  @requirement "Calculate the answer to life, the universe, and everything."
  @sample %{text: "And the answer is 42."} |> Jason.encode!()

  setup do
    sessions = %{
      "test" => %Session{
        id: "test",
        status: :drafting,
        requirement: @requirement,
        sample: @sample
      }
    }

    registry = start_supervised!({Registry, sessions: sessions, name: DesignerTest})
    %{registry: registry}
  end

  test "starts a new designer session", %{registry: registry} do
    assert {:ok, session} = Designer.start_session(@requirement, @sample, registry)
    assert session.requirement == @requirement
    assert session.sample == @sample
    assert session.status == :drafting
  end

  test "check workflow", %{registry: registry} do
    Designer.check_workflow("test", "{}", registry)
  end
end
