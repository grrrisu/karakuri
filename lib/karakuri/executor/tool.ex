defmodule Karakuri.Executor.Tool do
  @moduledoc """
  Behaviour for executor tools.
  """
  @callback execute(input :: map()) :: {:ok, map()} | {:error, any()}
end
