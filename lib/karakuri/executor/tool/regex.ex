defmodule Karakuri.Executor.Tool.Regex do
  def execute(%{pattern: pattern, text: text}) do
    case Regex.run(pattern, text) do
      nil -> {:error, "no match"}
      match -> {:ok, List.first(match)}
    end
  end
end
