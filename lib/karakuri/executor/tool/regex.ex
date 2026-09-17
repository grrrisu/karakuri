defmodule Karakuri.Executor.Tool.Regex do
  def execute(%{pattern: pattern, text: text}) do
    case Regex.run(pattern, text) do
      nil -> {:error, "no match"}
      [_all, capture] -> {:ok, %{match: capture}}
      [match] -> {:ok, %{match: match}}
      _ -> {:error, "unsupported match format"}
    end
  end
end
