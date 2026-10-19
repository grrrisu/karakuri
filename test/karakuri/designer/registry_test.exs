defmodule Karakuri.Designer.RegistryTest do
  use ExUnit.Case, async: true

  alias Karakuri.Designer.Registry
  alias Karakuri.Designer.Session

  @requirement "Find the answer to life"
  @sample %{"text" => "The answer is 42"}

  setup do
    registry = start_supervised!({Registry, name: nil})
    %{registry: registry}
  end

  describe "create_session/3" do
    test "creates a drafting session with a generated id", %{registry: registry} do
      assert {:ok, %Session{} = session} =
               Registry.create_session(registry, @requirement, @sample)

      assert is_binary(session.id)
      assert session.requirement == @requirement
      assert session.sample == @sample
      assert session.status == :drafting
      assert session.attempts == 0
      assert {:ok, ^session} = Registry.get_session(registry, session.id)
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
      assert {:ok, ^updated} = Registry.get_session(registry, session.id)
    end

    test "updates with a function", %{registry: registry, session: session} do
      assert {:ok, updated} =
               Registry.get_and_update(registry, session.id, &%{&1 | attempts: &1.attempts + 1})

      assert updated.attempts == 1
      assert {:ok, ^updated} = Registry.get_session(registry, session.id)
    end

    test "returns not_found for an unknown id", %{registry: registry} do
      assert {:error, :not_found} = Registry.get_and_update(registry, "unknown", spec: "{}")
    end

    test "rejects unknown fields and id changes", %{registry: registry, session: session} do
      assert {:error, :invalid_update} = Registry.get_and_update(registry, session.id, foo: 1)
      assert {:error, :invalid_update} = Registry.get_and_update(registry, session.id, id: "x")

      assert {:error, :invalid_update} =
               Registry.get_and_update(registry, session.id, &%{&1 | id: "x"})

      assert {:ok, ^session} = Registry.get_session(registry, session.id)
    end
  end
end
