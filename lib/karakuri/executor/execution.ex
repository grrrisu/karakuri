defmodule Karakuri.Executor.Execution do
  defstruct workflow: nil, status: :pending, steps: [], output: nil

  defmodule Step do
    @type state :: :pending | :running | :completed | :failed

    @type t :: %__MODULE__{
            name: String.t() | nil,
            order: non_neg_integer(),
            status: state(),
            input: map(),
            output: map(),
            error: any(),
            started_at: any() | nil,
            finished_at: any() | nil
          }

    defstruct name: nil,
              order: 0,
              status: :pending,
              input: %{},
              output: %{},
              error: nil,
              started_at: nil,
              finished_at: nil
  end
end
