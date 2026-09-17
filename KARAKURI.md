# Karakuri からくり

Working notes — hackday project.

## Goal

An AI agent that generates workflows, where the generated workflows run **completely without AI**.

Two separate applications:

- **Designer** (AI) — reads a user's requirements, picks tools, wires steps, tests against sample data, saves the definition. Human in the loop.
- **Executor** (no AI) — reads a definition and runs it. Faster, cheaper, more reliable, and the data never touches a model unless a step explicitly calls one.

The name comes from *karakuri ningyō*, the Edo-period clockwork automata, and from *karakuri kaizen* — Toyota's practice of automating with springs and levers instead of motors, because the simpler mechanism is more reliable. Design-time intelligence, run-time mechanism.

**Tech stack:** Elixir, Phoenix LiveView. Jido (+ possibly Finitomata) in the designer. Nothing AI-shaped in the executor.

## Scope

**In:**

- Workflows as data (JSON spec, not generated code)
- A fixed tool registry
- A compiler that validates specs statically
- A linear step chain
- A Phoenix LiveView app to prompt, generate, review and run
- Elixir umbrella, dependency arrow pointing designer → executor only

**Out for the hackday:**

- Triggers beyond a Run button
- Auth, scheduling
- Branching and loops
- Expression syntax in params
- Agent-driven tool creation
- Automatic repair on production failure

**Demo beat to build toward:** unset the API key, restart, run the workflow again on a different PDF.

## Current state

Executor runs a three-step chain end to end.

- `%Workflow{}` / `%Step{}` / `%Execution{}` structs
- `Enum.reduce_while` interpreter with a `with` chain per step
- `extract_input/3` resolving `{:args, field}` and `{:ref, step_name, field}`; literals pass through
- Resolution failures produce a failed `%Execution.Step{}` instead of escaping the run
- Tagged error tuples: `{:input_error, _}`, `{:tool_result, _}`, `{:tool_error, _}`, `{:exit, _}`
- One regex tool, returning `%{match: ...}`
- Tests at unit (`extract_input/3`) and integration (`execute/2`) level

Args leak fixed — args are reachable only by ref, never merged into every step.

`execution.steps` stays 1:1 with `workflow.steps`, same order. Worth preserving: the tests, the timeline UI and the mermaid highlighting all lean on it.

## Next steps

1. **`extract_input/3` should not build execution records.** Return `{:error, {:input_error, ...}}` and let `execute/2` construct the failed `%Execution.Step{}`. The current coupling shows up in the test, which has to assemble a full execution step to assert on ref resolution.
2. **Structured input errors instead of formatted strings.** `{:input_error, :unknown_step, name}`, `{:input_error, :unknown_field, name, field}`, `{:input_error, :missing_arg, field}`. These are exactly the errors the compiler will later prevent — when one reaches the executor, you want to know which hole it came through without parsing English.
3. **Explicit `capture:` param on the regex tool.** Capture-by-list-arity breaks on two groups (`FunctionClauseError` surfaced as `:tool_error`) and makes the pattern secretly control the output shape.
4. **`pdf2text`** — the first non-string tool, and the first real test of whether the output-shape convention holds. Also where the blob question either shows up or turns out to be ignorable for the demo.
5. **Workflow-level `output`.** Right now a run succeeds and the answer is `List.last(execution.steps).output.match`.
6. **The compiler.** Registry lookup, param validation, ref type-checking, topo sort, unique step names. Then a test file of deliberately broken specs — that file is the contract between the two apps.
7. Then: persistence, LiveView, and only after that the designer.

## Settled

**Scope map vs `Enum.find`** — not needed yet. On a sequential, halt-on-first-failure executor with unique step names, `Enum.find` over the newest-first list and `Map.put` into a scope map are behaviourally identical (both last-wins). Revisit when either of these lands:

- **Blobs.** `pdf2text` output has to be two things at once: the real string for the next step's param, and `%{blob: ..., bytes: ..., preview: ...}` for the trace and for designer feedback. One structure can't hold both.
- **The trace stops being an in-memory accumulator** — streamed to PubSub, written per-step, or replaced by a telemetry handler. Then there's no list left to search.

Cheap either way: the resolver is a few lines with one call site.

**Retries don't create duplicate step entries.** Tools own their transient retries (a network retry inside the tool re-fetches without re-running four upstream steps); most executor-level failures are deterministic and retrying changes nothing. If attempt history is ever wanted, it goes *inside* the step record as an `attempts:` list, not as extra entries. Resume-after-fix creates a **new** `Execution` seeded from the previous scope, so runs stay immutable.

**`{:args, field}` separate from `{:ref, name, field}`** — keep the split. Args are the workflow's signature, step outputs are internal; the compiler can type-check them separately, and `args` never becomes a reserved step name.

## Things to keep in mind

**Refs are the only ordering.** `order:` is still in the structs, unused. Delete it before something depends on it.

**No expressions in params.** A value is a literal or a whole ref, never a template. The moment you allow `"Total: {a.b}"` you have a language and lose static checking. String building is a tool.

**Iteration stays inside tools.** Lists in, lists out — no `foreach` in the spec.

**The tool catalog is generated from the registry**, never hand-written into a prompt. It must include per-tool `doc` and `examples`, since that's what drives first-shot generation quality.

**The compiler lives in the executor and the designer calls it.** Two copies of the schema will drift within a day and produce the worst failure: designer says valid, executor says unknown tool.

**Sample input is mandatory** to create a workflow, and becomes the version's stored fixture. The LLM can't write a regex without seeing the extracted text, and the fixture later doubles as a regression test.

**Blob refs, not raw payloads**, once anything large moves between steps. This came up three times for different reasons — trace size, designer feedback, journal size — which means it's a type, not an optimisation.

**Versioning.** Step ids are immutable. Runs pin `workflow_version` + `spec_hash`. Versions record `author :agent | :human` and `parent_version_id`, so agent regeneration can't silently eat hand edits.

**A `no_llm` flag** computed by the compiler from the tool catalog. It's the field that makes the thesis visible in the UI.

**Keep the executor's mix.exs clean.** A CI test asserting no LLM deps turns the architectural claim into something the build enforces.

**Don't assert on Elixir's exception formatting** in tests — `Exception.format/2` output changes between releases. Assert on the error tag.

## Library decisions

| Concern | Decision |
| --- | --- |
| Step interpreter | `Enum.reduce_while` over topo-sorted steps. ~40 lines, fully owned. |
| Run envelope | `Task.Supervisor` now; Oban later, one job per run, `max_attempts: 1`. |
| FSM | Finitomata in the **designer** session (compile-time known, event-driven). Not in the executor. |
| Mermaid | Derived from the spec's refs, ~20 lines. No engine needed. |
| Progress visibility | `:telemetry` when it starts to matter — not an invented trace abstraction, and never `Phoenix.PubSub` inline in the executor. |
| External commands | MuonTrap over `System.cmd` — timeouts and no orphaned processes. |
| Param schemas | NimbleOptions per tool, converted to JSON Schema for the designer's catalog. |

**Post-hackday candidates**, all good answers to problems that don't exist yet:

- **Reactor** — real DAG execution, concurrency, compensation. Port when parallel branches or undo-on-failure arrive.
- **Sage** — saga compensation, if tools start touching systems you don't own.
- **Continuum** — durable execution with replay. The answer if approval steps (`await signal`) or long-running runs arrive. Fits via a single interpreter workflow module taking the spec as run input. Requires Elixir 1.19/1.20; pre-1.0, single maintainer.

## Open questions

- Is `{:ref, source, field}` the only non-literal, or does a literal that *looks* like a ref need an escape hatch?
- Type lattice: `:string, :integer, :decimal, :boolean, :file, :list, :map` — do lists need element types? (Untyped for the hackday, noted as debt.)
- Is `file` a distinct type carrying a blob id, rather than a string path? (Should be — a spec must not be able to name `/etc/passwd`.)
- Does the tool output schema ever depend on params (`captures: ["total", "date"]`), or is it always fixed per tool version?
- Does cancel need to interrupt mid-step, or is between-steps enough?
