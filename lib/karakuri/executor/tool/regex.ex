defmodule Karakuri.Executor.Tool.Regex do
  @behaviour Karakuri.Executor.Tool

  def execute(%{pattern: pattern, text: text, named_captures: true}) do
    case Regex.named_captures(pattern, text) do
      nil -> {:error, "no match"}
      match -> {:ok, match}
    end
  end

  def execute(%{pattern: pattern, text: text}) do
    case Regex.run(pattern, text) do
      nil ->
        {:error, "no match"}

      [_all, capture] ->
        {:ok, %{match: capture}}

      [match] ->
        {:ok, %{match: match}}

      _ ->
        {:error,
         "unsupported match format, expected a single capture or if you want to use named captures, set named_captures: true"}
    end
  end
end
