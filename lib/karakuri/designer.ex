defmodule Karakuri.Designer do
  alias Karakuri.Designer.Session

  alias Karakuri.Executor.Workflow

  @max_attempts 3

  def generate(requirement, sample) do
    session = %Session{status: :drafting, attempts: 0, requirement: requirement, sample: sample}

    case run(session) do
      %Session{status: :completed, workflow: workflow} -> {:ok, workflow}
      %Session{status: :failed} = failed_session -> {:error, failed_session}
      %Session{status: :impossible} = impossible_session -> {:error, impossible_session}
      %Session{status: _wip} = wip_session -> {:error, wip_session}
    end
  end

  def run(%Session{status: status} = session) when status in [:completed, :failed, :impossible],
    do: session

  def run(%Session{attempts: n} = session) when n >= @max_attempts,
    do: %{session | status: :failed}

  def run(%Session{status: :drafting} = session),
    do: session |> draft() |> run() |> dbg(label: "after drafting")

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
  def compile(session),
    do: %{session | status: :testing, workflow: %Workflow{name: "the_answer_to_life"}}

  def test(session),
    do: %{session | status: :completed}
end
