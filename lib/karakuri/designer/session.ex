defmodule Karakuri.Designer.Session do
  defstruct [
    :id,
    # from the form
    :requirement,
    # %{"text" => "The answer is 42"}
    :sample,
    # completed, failed (eg. too many attempts), impossible, drafting, compiling, testing
    :status,
    # drafted workflow in JSON format
    :spec,
    # compiled %Workflow{}, once valid
    :workflow,
    # %Execution{} from the dry run
    :execution,
    # what goes back to the model next round
    :feedback,
    # :impossible / :failed explanation
    :reason,
    # LLM conversation so far
    messages: [],
    attempts: 0
  ]
end
