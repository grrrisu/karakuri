defmodule Karakuri.Designer do
  alias Karakuri.Designer.Session

  @max_attempts 3

  def run(%Session{status: s} = session) when s in [:completed, :failed, :impossible], do: session

  def run(%Session{attempts: n} = session) when n >= @max_attempts,
    do: %{session | status: :failed}

  def run(%Session{status: :drafting} = session), do: session |> draft() |> run()
  def run(%Session{status: :compiling} = session), do: session |> compile() |> run()
  def run(%Session{status: :testing} = session), do: session |> test() |> run()

  def draft(session) do
    # Implementation for generating a workflow based on the prompt (requirement + sample)
    # magic agent stuff happening

    {:ok, json} =
      %{
        name: "the_answer_to_life",
        input: "text",
        output: ["ref", "the_answer", "match"],
        steps: [
          %{
            name: "the_answer",
            order: 0,
            tool: "regex@1",
            input: %{text: ["args", "text"], pattern: "\\d+"}
          }
        ]
      }
      |> Jason.encode()

    %{session | status: :compiling, spec: json, workflow: nil}
  end

  #
  def compile(session), do: %{session | status: :testing}
  def test(session), do: %{session | status: :completed}
end
