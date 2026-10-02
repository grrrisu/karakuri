# Karakuri

Working notes. Last updated 2026-10-01.

## Goal

An AI agent that generates workflows, where executing a generated workflow **never involves the designer**.

- **Designer** (an agent) — reads a user's requirements, picks tools, wires steps, tests against sample data, saves the definition. Human in the loop.
- **Executor** (no agent) — reads a definition and runs it. The control flow comes from the definition and nowhere else.

**The precise claim:** the executor never asks a model *what to do*; a step may ask a model *for a value*. A tool that calls an LLM — summarize this email, classify this ticket — is one request and one response, like any other external call, and running it needs no designer. What must never exist in the executor is an agent loop: no planner choosing the next step, no model interpreting the definition.

Two properties fall out, and they're worth keeping separate:

| | Independent of the designer | Deterministic |
| --- | --- | --- |
| `regex@1`, `pdf2text@1` | ✅ | ✅ |
| `llm.summarize@1` | ✅ | ❌ |
| anything agentic | ❌ | ❌ |

The first column is the architecture and is non-negotiable. The second is a property of the tools a given workflow happens to use, computed by the compiler and shown in the UI.

Name: *karakuri ningyō*, the Edo-period clockwork automata, and *karakuri kaizen* — Toyota's practice of automating with springs and levers instead of motors, because the simpler mechanism is more reliable. Design-time intelligence, run-time mechanism.

**Stack:** Elixir, Phoenix LiveView, daisyUI. Jido in the designer. One application, two directories — the separation is architectural, not deployment. The rules worth enforcing: nothing under the executor references `Phoenix.*`, `KarakuriWeb`, or any designer module.

## Scope

**In:** workflows as data; fixed tool registry; a compiler that validates specs statically; linear step chains; LiveView to prompt, generate, review and run.

**Out:** triggers beyond a Run button, auth, scheduling, branching, loops, expressions in params, agent-created tools, auto-repair of production failures.

**Demo beat — two workflows, told in this order:**

1. `extract_number` — all deterministic, flagged reproducible. Unset the API key, restart, run it again on different input. It works.
2. `summarize_inbox` — has an `llm.summarize@1` step, flagged non-reproducible. It needs the key, but **the designer isn't running** and it executes anyway.

The second is the stronger demonstration, because it separates the two things people conflate. The flag in the UI is what makes the distinction visible rather than asserted.

## Current state

**Executor** — runs a chain end to end.

- `%Workflow{name, steps, input, output}` with `%Workflow.Step{name, tool, order, input, output}`
- `%Execution{workflow, status, steps, output}` with `%Execution.Step{name, order, status, input, output, error, started_at, finished_at}`
- `Enum.reduce_while` interpreter, `with` chain per step
- `extract_input/3` resolves `{:args, field}` and `{:ref, step_name, field}`; literals pass through
- Resolution failures produce a failed step rather than escaping the run
- Tagged errors: `{:input_error, _}`, `{:tool_result, _}`, `{:tool_error, _}`, `{:exit, _}`
- `Karakuri.Executor.Tool` behaviour — `execute(map) :: {:ok, map} | {:error, any}`
- One tool: `Tool.Regex`, returning `%{match: ...}`
- Notifies a pid: `{:notify, :step_started | :step_finished | :workflow_finished, workflow_name, payload}`

**Server** (`Karakuri.Server` GenServer) — in-memory store plus run orchestration. Seeds `example_extract_number` at boot, `reset/0` restores it. Runs the executor under `Task.Supervisor.async_nolink`, receives notifies, updates state, rebroadcasts on the `"execution_event"` PubSub topic.

**Web** — `WorkflowLive.Index` and `WorkflowLive.Show`, shared `Components`. Timeline merges `workflow.steps` with `execution.steps` by name so not-yet-run steps render as pending. Per-status icons, timestamps, workflow-level result slot. Form is driven by the workflow's single `input:` key.

**Tests** — executor, server (via `assert_receive` on the PubSub topic), LiveView.

## Open bugs

1. **`Show.handle_info/2` trusts the broadcast's workflow name.** One global topic + taking the name from the message = running B while viewing A silently swaps the page to B. Match on the currently-viewed workflow, catch-all ignores the rest.
2. **`start_workflow` is a cast and can't fail.** Already-running → `dbg` to console, user sees "started". Unknown name → `nil` workflow → task raises → `:DOWN` clears the ref but the execution stays `:in_progress` forever. Make it a `call` returning `:ok | {:error, :busy} | {:error, :not_found}`; have `:DOWN` mark the execution failed.
3. **Failed steps may not notify.** The `else` branch in `execute_step` halts without a `step_finished`, so a failure leaves the step spinning until the task result lands. Needs a `:step_failed` event and a test.
4. **`inspect(@execution_step)` in the template** renders the whole struct. Fine for regex; a 200KB `pdf2text` output goes straight into the DOM diff. Truncate in the template.
5. **One execution per workflow, keyed by name.** Every run overwrites the last. No history, no per-execution URL, and it masks memory growth.
6. **`execution_ref` is a single global lock** — one run at a time across the whole server.
7. **`input: :text` assumes one scalar arg.** A PDF workflow needs a file and probably a second arg.

## Settled

**Scope map vs `Enum.find`** — not needed. On a sequential, halt-on-first-failure executor with unique step names, both are last-wins and behaviourally identical. Revisit when output has to be two things at once (real value for the next step, blob ref for the trace), or when the trace stops being an in-memory accumulator.

**Retries don't create duplicate step entries.** Tools own transient retries; most executor failures are deterministic and retrying changes nothing. Attempt history, if ever needed, goes *inside* the step record. Resume-after-fix creates a new `Execution` seeded from the previous scope.

**`{:args, field}` separate from `{:ref, name, field}`** — keep the split. Args are the workflow's signature, step outputs are internal; the compiler can check them separately and `args` never becomes a reserved step name.

**Executor ↔ web uses a notify pid, not telemetry.** Telemetry silently detaches handlers that raise, is implicit, and isn't meant to carry payloads. The pid is explicit, visible at the call site, and the executor still knows nothing about Phoenix. Telemetry stays available for metrics.

**PubSub topic, not a direct send to the LiveView** — the LiveView pid changes on reconnect, a second tab has another, and the run outlives any socket.

**`execution.steps` stays 1:1 with `workflow.steps`.** The view merges the two by name to render pending steps.

**Update the store before broadcasting**; **subscribe before reading on mount.** Otherwise the view renders stale state or misses an event.

**One app, not two.** Designer-independence is a property of the code, not of the deployment; a second deployable would only cost time. The invariant is enforced by module references, not by the dependency list — an `llm.*` tool legitimately needs a model client, so "no LLM deps in the executor" was never the right check.

## Design rules

**Refs are the only ordering.** `order:` is still in the structs and still unused.

**No expressions in params.** A value is a literal or a whole ref, never a template. `"Total: {a.b}"` would make it a language and kill static checking. String building is a tool.

**Iteration stays inside tools.** Lists in, lists out — no `foreach` in the spec.

**The tool catalog is generated from the registry**, never hand-written into a prompt, and carries per-tool `doc` and `examples` — that's what drives first-shot generation quality.

**The compiler is the executor's, and the designer calls it.** Two copies of the schema drift within a day and produce the worst failure: designer says valid, executor says unknown tool.

**Sample input is mandatory** to create a workflow and becomes the version's fixture. The LLM can't write a regex without seeing the extracted text, and the fixture doubles as a regression test.

**Blob refs, not raw payloads**, once anything large crosses a step boundary. The seam is the storage boundary, not the executor — the executor keeps passing real values.

**Versioning.** Step names immutable. Runs pin `workflow_version` + `spec_hash`. Versions record `author :agent | :human` and `parent_version_id`, so regeneration can't silently eat hand edits.

**Tools declare `deterministic?/0`.** The compiler ORs it across a workflow's steps into a `deterministic` flag shown in the UI. Most tools are `true`; a tool that calls a model, reads the clock, or hits a changing source is `false`. A tool calling an LLM must still have a *stable output shape* — the call is non-deterministic, the step's contract must not be, or `{:ref, "summarize", :summary}` becomes a coin flip. That means structured output inside the tool, and credentials from config, never from the definition.

**A workflow with a non-deterministic step can't be replayed.** Its fixture test asserts on shape, not content.

**Don't assert on `Exception.format/2` output** in tests — it changes between releases. Assert on the error tag.

## Next

1. The open bugs above, roughly in listed order.
2. **Explicit `capture:` on `Tool.Regex`.** Capture-by-list-arity breaks on two groups and makes the pattern secretly control the output shape.
3. **`pdf2text`** — first non-string tool, first real test of the output-shape convention, and where the blob question gets a real answer.
4. **The compiler.** Registry lookup, param validation, ref type-checking, topo sort, unique step names, the `deterministic` flag. Plus a test file of deliberately broken specs — that file is the contract with the designer.
5. **The designer.** Smallest possible version first: hardcoded catalog, one structured-output call, save via the existing store. Even a regex-only version proves the loop and shows whether validation errors feed back usefully.
6. **`llm.summarize@1`**, for the second demo workflow — the first non-deterministic tool, and the thing that makes the flag mean something.

## Library decisions

| Concern | Decision |
| --- | --- |
| Step interpreter | `Enum.reduce_while`. Owned, ~40 lines. |
| Run envelope | `Task.Supervisor` now; Oban later, one job per run, `max_attempts: 1`. |
| Executor → web | Notify pid → `Server` → PubSub. |
| FSM | Finitomata in the **designer** session, if at all. Not in the executor. |
| Mermaid | Derived from the spec's refs, ~20 lines. No engine needed. |
| External commands | MuonTrap over `System.cmd` — timeouts, no orphans. |
| Param schemas | NimbleOptions per tool → JSON Schema for the designer's catalog. |
| Structured output | Constrained decoding against a schema built from the live registry. Rules out compile-time-schema libraries like instructor_ex. |

**Post-hackday:** Reactor (DAG, concurrency, compensation), Sage (compensation only), Continuum (durable replay — the answer if approval steps or long runs arrive; fits via one interpreter workflow module taking the spec as run input).

## Open questions

- Does a literal that *looks* like a ref need an escape hatch?
- Type lattice: do lists need element types? (Untyped for now, noted as debt.)
- Is `file` a distinct type carrying a blob id rather than a path? (Should be — a spec must not be able to name `/etc/passwd`.)
- Can a tool's output schema depend on its params, or is it fixed per tool version?
- Does cancel need to interrupt mid-step?
