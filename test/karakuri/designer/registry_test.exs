defmodule Karakuri.Designer.RegistryTest do
  use ExUnit.Case, async: true

  alias Karakuri.Designer.Registry
  alias Karakuri.Designer.Session

  @requirement "Find the answer to life"
  @sample "The answer is 42"

  setup do
    registry = start_supervised!({Registry, name: nil})
    %{registry: registry}
  end

  describe "create_session/3" do
    test "creates a drafting session with a generated id and starts an agent", %{
      registry: registry
    } do
      assert {:ok, %Session{} = session} =
               Registry.create_session(registry, @requirement, @sample)

      assert is_binary(session.id)
      assert session.requirement == @requirement
      assert session.sample == @sample
      assert session.status == :drafting
      assert session.attempts == 0
      assert %Task{} = session.agent_task
      assert is_pid(session.agent_pid)

      task_ref = Process.monitor(session.agent_task.pid)
      assert_receive {:DOWN, ^task_ref, :process, _pid, :normal}, 5_000

      assert {:ok, stored} = Registry.get_session(registry, session.id)
      assert stored.id == session.id
      assert stored.status == :completed

      assert Enum.map(stored.messages, & &1.kind) == [
               :request_started,
               :llm_started,
               :request_completed
             ]

      assert stored.feedback == {:ok, ~s({"mocked":true})}
      assert stored.agent_task == nil
    end

    test "generates unique ids", %{registry: registry} do
      {:ok, a} = Registry.create_session(registry, @requirement, @sample)
      {:ok, b} = Registry.create_session(registry, @requirement, @sample)

      refute a.id == b.id
    end
  end

  describe "get_and_update/3" do
    setup %{registry: registry} do
      {:ok, session} = Registry.create_session(registry, @requirement, @sample)
      %{session: session}
    end

    test "updates with a keyword list and stores the result", %{
      registry: registry,
      session: session
    } do
      assert {:ok, updated} =
               Registry.get_and_update(registry, session.id, spec: "{}", status: :compiling)

      assert updated.spec == "{}"
      assert updated.status == :compiling
      assert {:ok, stored} = Registry.get_session(registry, session.id)
      assert stored.spec == "{}"
    end

    test "updates with a function", %{registry: registry, session: session} do
      assert {:ok, updated} =
               Registry.get_and_update(registry, session.id, &%{&1 | attempts: &1.attempts + 1})

      assert updated.attempts == 1
      assert {:ok, stored} = Registry.get_session(registry, session.id)
      assert stored.attempts == 1

      send(registry, {make_ref(), session})

      assert {:ok, stored} = Registry.get_session(registry, session.id)
      assert stored.attempts == 1
    end

    test "returns not_found for an unknown id", %{registry: registry} do
      assert {:error, :not_found} = Registry.get_and_update(registry, "unknown", spec: "{}")
    end

    test "rejects unknown fields and id changes", %{registry: registry, session: session} do
      assert {:error, :invalid_update} = Registry.get_and_update(registry, session.id, foo: 1)
      assert {:error, :invalid_update} = Registry.get_and_update(registry, session.id, id: "x")

      assert {:error, :invalid_update} =
               Registry.get_and_update(registry, session.id, &%{&1 | id: "x"})

      assert {:ok, stored} = Registry.get_session(registry, session.id)
      assert stored.id == session.id
      assert stored.requirement == session.requirement
      assert stored.sample == session.sample
    end
  end

  describe "clear/1" do
    test "removes all sessions and ignores late notifications", %{registry: registry} do
      {:ok, session} = Registry.create_session(registry, @requirement, @sample)

      assert :ok = Registry.clear(registry)
      assert {:error, :not_found} = Registry.get_session(registry, session.id)

      send(registry, {make_ref(), session})

      assert {:error, :not_found} = Registry.get_session(registry, session.id)
    end
  end
end
