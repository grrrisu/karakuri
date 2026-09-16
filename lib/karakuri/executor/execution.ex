defmodule Karakuri.Executor.Execution do
  defstruct workflow: nil, status: :pending, steps: []

  defmodule Step do
    @type state :: :pending | :running | :completed | :failed

    @type t :: %__MODULE__{
            name: String.t() | nil,
            order: non_neg_integer(),
            status: state(),
            input: map(),
            output: map(),
            error: any()
          }

    defstruct name: nil, order: 0, status: :pending, input: %{}, output: %{}, error: nil
  end
end
