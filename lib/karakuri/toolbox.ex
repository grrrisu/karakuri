defmodule Karakuri.Toolbox do
  def catalog do
    [
      %{
        key: "regex@1",
        description: "Regular expression tool, uses a pattern to match text",
        input: [
          pattern: [
            type: :string,
            required: true,
            doc: "PCRE pattern. Escape backslashes in JSON: \\\\d+"
          ],
          text: [
            type: :string,
            required: true,
            doc: "Text to search. Usually a ref to a previous step's output."
          ]
        ],
        output: %{match: [type: :string, doc: "The matched text."]},
        example: %{
          name: "find_total",
          tool: "regex@1",
          input: %{text: "{args.text}", pattern: "Total:\\s*([0-9.,]+)"}
        }
      }
    ]
  end
end
