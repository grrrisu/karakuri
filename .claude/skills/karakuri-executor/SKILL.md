---
name: karakuri-executor
description: How Karakuri's execution engine works and the rules for changing it. Use when adding or modifying a tool, touching the interpreter or input resolution, changing execution notifications or the store, or writing executor tests. Also use before adding dependencies to the executor, or when something tempts you to put branching, loops or expressions into a workflow definition.
---

# Karakuri executor

The executor runs workflow definitions. Definitions are **data**; the executor is a fixed interpreter that walks them. An AI agent (the designer) produces definitions, but executing one never involves the designer — that independence is the point of the project.

Independence from the designer is not the same as "no model calls." A step may call an LLM as a service — summarize this email, classify this ticket — and that is one request and one response, like any other external call. What the executor must never contain is an *agent*: anything that decides what happens next. The sequence of steps comes from the definition and nowhere else.

## Layout

| Module | Role |
| --- | --- |
| `Karakuri.Executor` | The interpreter. Pure-ish: takes a workflow and args, returns an `%Execution{}`. |
| `Karakuri.Executor.Workflow` | Definition structs — `%Workflow{}`, `%Workflow.Step{}`. |
| `Karakuri.Executor.Execution` | Run record — `%Execution{}`, `%Execution.Step{}`. |
| `Karakuri.Executor.Tool` | Behaviour every tool implements. |
| `Karakuri.Executor.Tool.*` | The tools themselves. |
| `Karakuri.Server` | In-memory store + run orchestration. Owns PubSub. |
| `KarakuriWeb.WorkflowLive.*` | Index and Show, plus shared components. |

Definition vs record: `%Workflow.Step{}` says what *should* happen, `%Execution.Step{}` records what *did*. They share `name` and that is how the UI zips them together.

## How a run works

1. `Server.start_workflow/2` starts `Executor.execute/3` under a `Task.Supervisor`, passing the server's pid.
2. `Executor.execute/3` folds over `workflow.steps` with `Enum.reduce_while`, halting on the first failure.
3. Per step: resolve input, notify `:step_started`, call the tool, notify `:step_finished`.
4. The executor `send`s `{:notify, event, workflow_name, payload}` to that pid. It does nothing else with it.
5. `Server` updates its state **then** broadcasts on the `"execution_event"` PubSub topic.
6. The task's return value is the authoritative `%Execution{}`; `Server` stores it when the task result arrives.

## Input resolution

A step's `input` map holds either literals or refs:

- `{:args, :text}` — the run's arguments
- `{:ref, "sentence", :match}` — a completed step's output field
- anything else — a literal, passed through

`extract_input/3` resolves these against the already-executed steps. Refs can only point backwards, because only completed steps are in scope.

## Error shape

Failures are tagged tuples on `%Execution.Step{error: ...}`:

| Tag | Meaning |
| --- | --- |
| `{:input_error, _}` | A ref didn't resolve, or an arg was missing. Should be impossible once the compiler exists — if you see one, the compiler has a hole. |
| `{:tool_result, reason}` | The tool ran and returned `{:error, reason}`. A normal outcome, e.g. a regex that didn't match. |
| `{:tool_error, _}` | The tool raised. A bug. |
| `{:exit, reason}` | The tool exited. |

`:tool_result` and `:tool_error` are different on purpose: the first means the workflow needs fixing, the second means the code does. Don't collapse them.

## Adding a tool

Implement `Karakuri.Executor.Tool`:

```elixir
defmodule Karakuri.Executor.Tool.Example do
  @behaviour Karakuri.Executor.Tool

  @impl true
  def execute(%{some_input: value}) do
    {:ok, %{result: transformed}}
  end
end
```

Rules:

- **Output is always a map with named fields.** Refs point at field names (`{:ref, "step", :result}`), so a bare string or number can't be referenced. Even single-value tools return `%{match: "42"}`.
- **Return `{:error, reason}` for expected failures.** Don't raise for "no match" or "file not found" — those are results, not bugs.
- **Don't retry inside the executor; retry inside the tool.** A network retry belongs in the tool so it re-fetches without re-running four upstream steps. Most executor-level failures are deterministic and retrying changes nothing.
- **Keep inputs and outputs serializable.** Definitions will round-trip through JSON. No pids, refs or funs.
- **Shell out with MuonTrap, not `System.cmd`** — timeouts, and no orphaned OS processes when the task dies.
- **Declare `deterministic?/0`.** Most tools are `true`. A tool that calls a model, reads the clock, or hits a changing external source is `false`, which marks every workflow using it as non-reproducible. Don't claim `true` to make a workflow look better.

### Tools that call a model

Allowed, and they follow the same contract as any other tool. A few things they need that a regex doesn't:

- A timeout, and retry-on-transient inside the tool.
- `deterministic?/0` returning `false`.
- A stable output shape. The *call* is non-deterministic; the step's contract must not be. Ask for structured output and return named fields, so `{:ref, "summarize", :summary}` always resolves.
- Credentials from config, never from the definition. A workflow definition is data that gets passed around and shown in a UI.

Note the consequence for fixtures: a workflow containing such a step can't be replayed deterministically, so a fixture test over it will be flaky. Assert on shape, not on content.

## Rules that are easy to break

**No `Phoenix.*` or `KarakuriWeb` in the executor.** Broadcasting directly from the interpreter is the natural move under time pressure and it's wrong: the executor stays runnable from `iex` with nothing else started. Notify the pid; `Server` decides what that means.

**The executor never asks a model what to do; a step may ask a model for a value.** A tool that calls an LLM is fine — it is one call to an external service, and executing it needs no designer. What must never appear is an agent loop: no planner choosing the next step, no model interpreting the definition, no designer module referenced from the executor. Control flow comes from the definition, always. A tool that calls a model declares `deterministic?/0` as `false` so the workflow can be flagged.

**No expressions or templates in params.** A value is a whole ref or a literal. `"Total: {a.b}"` must stay invalid — allowing it makes the definition a programming language and makes static checking impossible. String building is a tool.

**No `foreach` or branching in the definition.** Iteration lives inside tools: lists in, lists out. A tool handling a collection is boring; a spec language with map/reduce is a different project.

**`execution.steps` stays 1:1 with `workflow.steps`, in order.** The UI, the tests and the timeline all depend on it. Retries and attempts go *inside* a step record, never as extra entries.

**Never `String.to_atom` on anything from a definition.** Tool names and field names resolve through a registry lookup; an unknown name is a validation error, not an atom leak.

**`order:` on `%Workflow.Step{}` is unused.** Refs define the ordering. Don't start depending on it; it should probably be deleted.

## Testing

- Assert on error **tags**, never on `Exception.format/2` output — that string changes between Elixir releases.
- `Executor.execute/3` is testable on its own with no server, no PubSub and no Phoenix. Prefer that for interpreter behaviour.
- Server-level tests subscribe to `"execution_event"` and use `assert_receive`.
- Failure paths need tests as much as happy paths — a step that fails must still produce a complete `%Execution{}`, never raise out of `execute/3`.

## Current gaps

See `KARAKURI.md` for the live list. At time of writing: executions are keyed by workflow name so each run overwrites the last; `start_workflow` is a cast and can't report failure; and the registry, the JSON spec format and the compiler don't exist yet.
