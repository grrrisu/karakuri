defmodule Karakuri.Executor.Workflow do
  defstruct name: nil, steps: [], input: :input, output: nil

  defmodule Step do
    defstruct name: nil, tool: nil, order: 0, input: %{}, output: %{}
  end

  def example_extract_number() do
    step1 = %Step{
      name: "sentence",
      order: 0,
      tool: Karakuri.Executor.Tool.Regex,
      input: %{text: {:args, :text}, pattern: ~r/I sat at my desk[^.]+./}
    }

    step2 = %Step{
      name: "quote",
      order: 1,
      tool: Karakuri.Executor.Tool.Regex,
      input: %{text: {:ref, "sentence", :match}, pattern: ~r/\"(.+?)\"/}
    }

    step3 = %Step{
      name: "number",
      order: 2,
      tool: Karakuri.Executor.Tool.Regex,
      input: %{text: {:ref, "quote", :match}, pattern: ~r/\d+/}
    }

    %__MODULE__{
      name: "extract_number",
      input: :text,
      output: {:ref, "number", :match},
      steps: [step1, step2, step3]
    }
  end
end
