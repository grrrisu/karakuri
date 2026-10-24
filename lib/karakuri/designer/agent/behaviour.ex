defmodule Karakuri.Designer.Agent.Behaviour do
  @callback ask_stream(pid :: pid(), message :: String.t(), opts :: keyword()) ::
              {:ok, %{request: struct(), events: Enumerable.t()}} | {:error, term()}

  @callback await(request :: struct(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @callback mocked?() :: boolean()
end
