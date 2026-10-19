---
name: karakuri-executor
description: How Karakuri's execution engine works and the rules for changing it. Use when adding or modifying a tool, touching the interpreter or input resolution, changing execution notifications or the store, or writing executor tests. Also use before adding dependencies to the executor, or when something tempts you to put branching, loops or expressions into a workflow definition.
---

# Karakuri executor

The executor runs workflow definitions. Definitions are **data**; the executor is a fixed interpreter that walks them. An AI agent (the designer) produces definitions, but executing one never involves the designer — that independence is the point of the project. Concept: `KARAKURI.md`. Known bugs and next steps: `TODO.md`.

Independence from the designer is not the same as "no external calls." A tool may call a service — even a model — for a value: one request, one response. What the executor must never contain is an *agent*: anything that decides what happens next. The sequence of steps comes from the definition and nowhere else.

## Layout

| Module | Role |
| --- | --- |
| `Karakuri.Executor` | The interpreter. Takes a workflow and args, returns an `%Execution{}`. |
| `Karakuri.Executor.Workflow` | Definition structs — `%Workflow{}`, `%Workflow.Step{}` — plus the seeded `example_extract_number/0`. |
| `Karakuri.Executor.Execution` | Run record — `%Execution{}`, `%Execution.Step{}`. |
| `Karakuri.Executor.Tool` | Behaviour every tool implements. |
| `Karakuri.Executor.Tool.*` | The tools. Today only `Tool.Regex`. |
| `Karakuri.Toolbox` | The catalog: tool key, description, params, output fields, example. |
| `Karakuri.Compiler` | Spec JSON → `%Workflow{}`. Currently a stub (`Jason.decode/1`). |
| `Karakuri.Designer` | Design-time context, not part of the executor. `run/2` compiles a spec and dry-runs it on the sample; its agent-facing functions are exposed to the Jido agent as tools. Only dry runs — never saves or runs a stored workflow. |
| `Karakuri.Server` | In-memory store + run orchestration. Owns PubSub. |
| `KarakuriWeb.WorkflowLive.*` | Index and Show, plus shared components. |

Definition vs record: `%Workflow.Step{}` says what *should* happen, `%Execution.Step{}` records what *did*. They share `name`, and that is how the UI zips them together.

## How a run works

1. `Server.start_workflow/2` (currently a cast) starts `Executor.execute/3` under `Karakuri.Executor.TaskSupervisor` with `async_nolink`, passing the server's pid. One run at a time.
2. `Executor.execute/3` folds over `workflow.steps` with `Enum.reduce_while`, halting on the first failure.
3. Per step: resolve input, notify `:step_started`, call the tool, notify `:step_finished`.
4. After the fold: notify `:workflow_finished` with the output (`nil` if the run failed).
5. The executor `send`s `{:notify, event, workflow_name, payload}` to that pid and does nothing else with it.
6. `Server` updates its state and broadcasts on the `"execution_event"` PubSub topic. The rule is *update, then broadcast*.
7. The task's return value is the authoritative `%Execution{}`; `Server` stores it when the result arrives. A crashed task produces a `:workflow_failed` broadcast from `Server`.

## Input resolution

A step's `input` map holds literals or refs:

- `{:args, name}` — the run's arguments
- `{:ref, "step_name", :field}` — an earlier step's output field
- anything else — a literal, passed through

`extract_input/3` resolves these against the already-executed steps. Refs can only point backwards, because only completed steps are in scope. The workflow's `output` is resolved the same way.

In spec JSON the same refs are lists, and the compiler turns them into the tuples above:

| JSON | Executor |
| --- | --- |
| `["args", "text"]` | `{:args, "text"}` |
| `["ref", "find_total", "match"]` | `{:ref, "find_total", :match}` — field name looked up in the catalog, never `String.to_atom` |

The executor only ever sees tuples. Don't teach it to understand the list form; that's the compiler's job.

**Arg names:** today they are atoms (`{:args, :text}`, `%Workflow{input: :text}`). Once the compiler exists they become strings (`{:args, "text"}`), because they come from the model. Step names are already strings; output field names come from the catalog and stay atoms.

## Error shape

Failures are tagged tuples on `%Execution.Step{error: ...}`:

| Tag | Meaning |
| --- | --- |
| `{:input_error, _}` | A ref didn't resolve, or an arg was missing. Should be impossible once the compiler exists — if you see one, the compiler has a hole. |
| `{:tool_result, reason}` | The tool returned `{:error, reason}`. A normal outcome, e.g. a regex that didn't match. |
| `{:tool_error, _}` | The tool raised. A bug. |
| `{:exit, reason}` | The tool exited. |

`:tool_result` and `:tool_error` are different on purpose: the first means the workflow needs fixing, the second means the code does. Don't collapse them.

## Adding a tool

Implement `Karakuri.Executor.Tool` and add an entry to `Karakuri.Toolbox.catalog/0` — the catalog is the only place a tool is described; the designer prompt is generated from it.

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

- **Output is always a map with fixed, named fields**, the same for every call. Refs point at field names, so a bare value can't be referenced, and a field whose name depends on the input can't be checked by the compiler.
- **Return `{:error, reason}` for expected failures.** Don't raise for "no match" or "file not found" — those are results, not bugs.
- **Inputs and outputs are JSON-serializable.** Definitions come from JSON. No compiled regexes, pids, refs or funs — a tool that needs a compiled form compiles it itself.
- **Retry inside the tool, never in the executor.** A network retry belongs in the tool so it re-fetches without re-running upstream steps.
- **Shell out with MuonTrap, not `System.cmd`** — timeouts, and no orphaned OS processes when the task dies.
- **Declare whether the tool is deterministic** (planned `deterministic?/0`). A tool that calls a model, reads the clock or hits a changing source is not. Don't claim otherwise to make a workflow look better.

### `Tool.Regex`

Input `%{pattern, text}`, output `%{match: string}`. No group → whole match; exactly one group → that group; more than one group → `{:error, _}`. The seeded workflow and tests currently pass compiled `~r//` patterns; the plan is for the tool to accept a string and compile it (see `TODO.md`). The `named_captures: true` clause is slated for removal: its field names depend on the pattern.

### Tools that call an external service or a model

Same contract, plus: a timeout and retry-on-transient inside the tool; a stable output shape (ask the service for structured output, return named fields); credentials from config, never from the definition — a definition is data that gets shown in a UI. A non-deterministic step can't be replayed, so its fixture tests assert on shape, not content.

## Rules that are easy to break

**No `Phoenix.*`, `KarakuriWeb`, `Jido` or designer modules in the executor.** Broadcasting from the interpreter is the natural move under time pressure and it's wrong: the executor stays runnable from `iex` with nothing else started. Notify the pid; `Server` decides what that means. Jido is the designer's agent framework; it can run action pipelines too, but saved workflows always run on our interpreter.

**The designer calls the executor, never the other way round.** `Designer.run/2` compiles a spec and dry-runs it with `Executor.execute/3`. That's the only coupling, and it points one way.

**No agent in the executor.** No planner choosing the next step, no model interpreting the definition. Control flow comes from the definition, always.

**No expressions or templates in params.** A value is a whole ref or a literal. `"Total: {a.b}"` must stay invalid — allowing it makes the definition a programming language and makes static checking impossible. String building is a tool.

**No `foreach` or branching in the definition.** Iteration lives inside tools: lists in, lists out.

**`execution.steps` stays 1:1 with `workflow.steps`, in order.** The UI, the tests and the timeline depend on it. Retries go *inside* a step record, never as extra entries. Every step that ends up in the record must also have been announced with `:step_started`, or the store's bookkeeping drifts.

**Never `String.to_atom` on anything from a definition.** Tool keys and field names resolve through the catalog; an unknown name is a validation error, not an atom leak.

**`order:` on `%Workflow.Step{}` is unused.** Refs define the ordering. Don't start depending on it; it is slated for deletion.

## Testing

- Assert on error **tags**, never on `Exception.format/2` output — that string changes between Elixir releases.
- `Executor.execute/3` is testable on its own with no server, no PubSub and no Phoenix, and it notifies the test process by default. Prefer that for interpreter behaviour.
- Server and LiveView tests subscribe to `"execution_event"` and `assert_receive`. A run happens in another process, so wait for `:workflow_finished` before asserting on results.
- Failure paths need tests as much as happy paths — a failing step must still produce a complete `%Execution{}`, never raise out of `execute/3`.
