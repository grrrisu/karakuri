defmodule Karakuri.Executor.Workflow do
  defstruct name: nil, steps: []

  defmodule Step do
    defstruct name: nil, tool: nil, order: 0, input: %{}, output: %{}
  end
end
