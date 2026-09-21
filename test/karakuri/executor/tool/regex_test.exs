defmodule Karakuri.Executor.Tool.RegexTest do
  use ExUnit.Case
  alias Karakuri.Executor.Tool.Regex

  test "regex tool matches a pattern in text" do
    input = %{text: "The answer is 42", pattern: ~r/\d+/}
    assert Regex.execute(input) == {:ok, %{match: "42"}}
  end

  test "regex tool returns capture" do
    input = %{text: "The answer is 42", pattern: ~r/The answer is (\d+)/}
    assert Regex.execute(input) == {:ok, %{match: "42"}}
  end

  test "regex tool returns no match when pattern is not found" do
    input = %{text: "No numbers here", pattern: ~r/\d+/}
    assert Regex.execute(input) == {:error, "no match"}
  end

  test "regex tool returns error with multiple captures" do
    input = %{text: "The answer is 42", pattern: ~r/The (.+) is (\d+)/}
    assert {:error, _} = Regex.execute(input)
  end

  test "regex tool returns named captures" do
    input = %{
      text: "The answer is 42",
      pattern: ~r/The answer is (?<number>\d+)/,
      named_captures: true
    }

    assert Regex.execute(input) == {:ok, %{"number" => "42"}}
  end
end
