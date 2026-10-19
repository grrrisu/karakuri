# Karakuri

Concept. Last updated 2026-10-19. Work items — bugs, next steps, open decisions — live in [TODO.md](TODO.md).

## Idea

An AI agent designs workflows. Running a workflow never involves the agent.

- **Designer** (agent, design time) — reads a requirement and a sample input, picks tools from a fixed catalog, wires steps, dry-runs the result on the sample. A human reviews and saves.
- **Executor** (no agent, run time) — reads a definition and runs it. Control flow comes from the definition and nowhere else.

The precise claim: **the executor never asks a model what to do.** A tool may call an external service for a value — even a model — but that is one request and one response, and running it needs no designer. What must never exist in the executor is an agent loop: no planner choosing the next step, no model interpreting the definition.

Name: *karakuri ningyō*, the Edo-period clockwork automata, and *karakuri kaizen* — automating with springs and levers instead of motors, because the simpler mechanism is more reliable. Design-time intelligence, run-time mechanism.

## PoC goal

Show the loop end to end with the smallest thing that runs:

> describe → generate → validate → dry-run on the sample → review → save → run, with the designer out of the picture.

If that works convincingly, it's worth following up. Anything not needed for that loop is out.

**In:** workflows as data, a fixed tool catalog, a compiler that validates definitions, linear step chains, a Jido agent as designer, a LiveView UI to describe, review and run, an in-memory store. Postgres stays configured (Phoenix default) but nothing is persisted yet.

**Out:** auth, triggers beyond a Run button, scheduling, branching, loops, expressions in params, agent-created tools, human editing of definitions, run history.

## Demo

1. **`extract_number`** — regex steps only. Run it. Unset the API key, restart, run it again on different input. It still works: the designer is gone, the workflow isn't.
2. *To be defined.*

## Architecture

```
          design time (agent)                         │      run time (no agent)
                                                      │
requirement + sample                                  │
        │                                             │
  Jido agent ──tool call──► Designer (API) ► run/2    │
     ▲                        │ Compiler.compile      │
     │                        │ Executor.execute (dry run on the sample)
     └──── feedback ◄─────────┘                       │
                              │ {:ok, workflow, execution}
                              ▼                       │
                     human review → Save ─────────────┼──► Executor.execute ──► %Execution{}
```

One Elixir/Phoenix application. The separation is architectural, not deployment: nothing in the executor references `Phoenix.*`, `KarakuriWeb`, `Jido` or any designer module. The executor runs from `iex` with nothing else started.

| Part | Role |
| --- | --- |
| `Karakuri.Executor` | Interpreter. Walks a `%Workflow{}`, returns an `%Execution{}`, notifies a pid per step. |
| `Karakuri.Compiler` | Spec JSON → `%Workflow{}` or a list of error messages. Owned by the executor side; the designer calls it. |
| `Karakuri.Toolbox` | The tool catalog. The single source for both compiler and designer prompt. |
| `Karakuri.Designer` | Design-time context: `run/2` (compile + dry run, no model), the session, and the agent-facing tool functions. |
| Designer agent (Jido) | ReAct agent. Models and tests its own workflow through `Designer` tools. |
| `Karakuri.Server` | In-memory store, run orchestration, PubSub broadcast. |
| `KarakuriWeb` | LiveView UI. |

**Jido is design-time only.** It drives the model; it never runs a saved workflow. Jido can also run deterministic action pipelines, which makes it tempting as the executor — but then "the executor has no agent" becomes a claim about how Jido is configured instead of a property of 40 lines we own.

## Workflow definition

- A workflow has a name, one input, a linear list of steps, and an output.
- Each step calls one tool from the catalog.
- A step's input values are **literals or whole refs** — never a template. Refs are the only ordering.
- The workflow's output is a ref.
- No branching, no loops, no expressions. Iteration lives inside tools: lists in, lists out. String building is a tool.

**Refs** (decided 2026-10-19):

| JSON | Compiles to | Points at |
| --- | --- | --- |
| `["args", "text"]` | `{:args, "text"}` | the workflow's input |
| `["ref", "find_total", "match"]` | `{:ref, "find_total", :match}` | an output field of an *earlier* step |

Any other value is a literal. A list-typed param whose literal value starts with `"args"` or `"ref"` would be ambiguous; no catalog tool has a list param today, and the compiler should reject such a tool entry if one appears.

```json
{
  "name": "extract_total",
  "input": "text",
  "steps": [
    { "name": "find_total", "tool": "regex@1",
      "input": { "text": ["args", "text"], "pattern": "Total:\\s*([0-9.,]+)" } }
  ],
  "output": ["ref", "find_total", "match"]
}
```

**Tools** take a map and return `{:ok, map}` with named fields, or `{:error, reason}` for expected failures. Inputs and outputs are JSON-serializable. Each tool declares whether it is deterministic.

**Names.** Names the model supplies (workflow, step, arg names) stay strings. Names from the catalog (tool keys, param and output fields) may be atoms. Never `String.to_atom` on model output.

## Designer

Two layers with a hard line between them.

### `Designer.run/2` — deterministic, no model

`Karakuri.Designer.run(spec_json, sample)` takes one spec and answers whether it works on the sample:

| Result | Means |
| --- | --- |
| `{:ok, %Workflow{}, %Execution{}}` | compiles, dry run completed. The execution carries the extracted values for review. |
| `{:error, {:invalid, [message]}}` | the compiler rejected it |
| `{:error, {:dry_run_failed, %Execution{}}}` | compiled, but a step failed on the sample |

Plus a pure `feedback(error) :: String.t()` that renders an error for the model. Both are testable with fixtures and no network.

`run/2` knows nothing about sessions, budgets or the model.

### The agent — Jido, ReAct (decided 2026-10-19)

The agent is given the executor infrastructure through a small set of tools and models its own workflow: it drafts a spec, tests it on the sample, reads the trace, revises, and submits when it's satisfied. Our code never decides *when* to check — the agent does. Our code decides what counts as done.

### The agent interface

`Karakuri.Designer` is the context: the one public module for everything design-time. Implementations live in modules underneath it.

```
Karakuri.Designer                    public API
  run(spec, sample)                  terms in, terms out — compile + dry run, knows nothing about agents
  start_design(requirement, sample)  creates the session, starts the agent task
  check_workflow(session_id, spec)   ┐
  submit_workflow(session_id, spec)  ├ agent-facing: session-bound, JSON-shaped in and out
  report_impossible(session_id, …)   ┘

Karakuri.Designer.Session            struct: requirement, sample, check budget, attempts, outcome
Karakuri.Designer.Report             %Execution{} / compiler errors → JSON-shaped maps for the model (truncation lives here)
Karakuri.Designer.Agent              the Jido agent: model, system prompt, tool list
Karakuri.Designer.Actions.*          one Jido.Action per agent-facing function, a few lines each
```

- **Two kinds of function, one context.** `run/2` returns Elixir terms and is what tests and the review screen use. The agent-facing functions return plain JSON-like maps — no structs, no tuples, no atoms the model has to understand — built by `Report`.
- **Adapters stay thin.** A `Jido.Action` only unpacks params and context and calls `Designer`. An MCP server later is the same three functions over a different transport.
- **Nothing in the executor references `Designer`.** The dependency points one way.

**Tools** (proposed):

| Tool | Params | Returns |
| --- | --- | --- |
| `check_workflow` | `workflow` (spec object) | `{ok: true, steps: [{name, output}], output}` or `{ok: false, errors: [...]}` / `{ok: false, failed_step, error, steps: [{name, output}]}` — completed steps' outputs included, truncated |
| `submit_workflow` | `workflow` | `{accepted: true}` or the same errors as `check_workflow`. Re-runs the check — the gate. On accept, the session ends and the UI shows it for review. |
| `report_impossible` | `reason`, `suggested_tools` | `{accepted: true}`. Session ends as impossible. |

The catalog and the spec rules go into the system prompt rather than a `list_tools` tool: the agent needs them every time, and a lookup tool costs a round trip. Revisit when the catalog grows.

**What the agent never gets:** the sample as a parameter (it comes from the session — otherwise the agent can make a check pass by testing against easier input), saving or running a stored workflow, or any tool with side effects beyond the dry run.

**Limits are ours, not Jido's.** `Designer` counts checks per session and answers `{ok: false, error: "check budget exhausted"}` after N (start with 5). Jido's iteration limit is a backstop, not the budget.

### Who calls whom

```
 1. WorkflowLive.submit(requirement, sample)
      → Server.create_session(requirement, sample)            returns session_id; session holds sample + check budget
      → Server starts a design Task under a supervisor, monitors it  (never ask_sync inside the Server — see below)
 2. design Task: Jido.AgentServer.start(agent, state: %{session_id: id})
                 Agent.ask_stream(pid, prompt)                 prompt = requirement + sample text
                 for each event → notify Server → broadcast "design:<id>" {:agent_event, …}   (see "Seeing what the agent does")
 3. ┌ agent → check_workflow(spec)
    │   → Designer.check_workflow(session_id, spec)
    │       → Server: spend one check from the budget
    │       → Designer.run(spec, session.sample)
    │            → Compiler.compile(spec)                      {:error, [msg]} → back to the agent
    │            → Executor.execute(workflow, %{workflow.input => sample})
    │       → Server: record attempt, then broadcast "design:<id>" {:checked, n, result}
    │   ← JSON result to the agent
    └ agent loops as it sees fit
 4. agent → submit_workflow(spec)
      → Designer.submit_workflow(session_id, spec)
          → Designer.run again (the gate)
          → Server: session := completed(workflow, execution), then broadcast "design:<id>" :completed
      ← {accepted: true} — the agent writes a final message and its process ends
 5. Server sees the agent exit.  Session still open → mark failed (budget spent, crash, gave up), broadcast.
 6. WorkflowLive shows extracted values.  Human clicks Save → Server.save_workflow(session_id) → put_workflow.
```

### Seeing what the agent does

The design Task drives the agent with `ask_stream/3` and consumes its `%Jido.AI.Reasoning.ReAct.Event{}` stream, forwarding a filtered subset to the Server, which broadcasts it like any other design event. The stream ends with `:request_completed`, `:request_failed` or `:request_cancelled`; then the Task calls `await/2` and exits.

| Event kind | UI |
| --- | --- |
| `:llm_completed` | the agent's text between tool calls ("the total is on the last line, tightening the pattern…") |
| `:tool_started` | "checking draft 2…" |
| `:tool_completed` | the check result — trace and errors, shown in the timeline component |
| `:request_failed` / `:request_cancelled` | the reason, if the session is still open |
| `:llm_delta` | **dropped** — one message per token would flood the Server and the socket. A "thinking…" indicator instead. |

Two kinds of event, two owners: **the stream is the narrative** (what the agent is doing, for the UI), **the session is the record** (checks spent, submitted workflow, outcome — written by `Designer`). The UI may show both; decisions are only ever made from the session.

Why not the alternatives:
- **`stream_to: {:pid, server}`** — no backpressure, straight into the Server's mailbox.
- **Jido signals** — jido_ai emits them, but the docs don't show subscribing to a running request's events through a signal bus, and it would be a second pub/sub beside Phoenix.PubSub.
- **`Jido.AI.Observe` telemetry** — process-global handlers that detach on error; same reasons as for the executor.

**The agent's job ends at submit.** Human review happens after the agent is gone; it does not wait for the click. A rejected workflow starts a new session (later: with the rejection reason as extra input).

**The Server never blocks on the agent.** The agent's tools call the Server to read and update the session; if the Server were sitting in `ask_sync`, the first tool call would deadlock.

**Update the session, then broadcast**, same rule as runs. Per-session topic `"design:<id>"`, so only the page that started the design listens.

**Outcomes** (read from the session):

| Outcome | Means | UI shows |
| --- | --- | --- |
| completed | `submit_workflow` accepted | steps, extracted values, Save |
| impossible | `report_impossible` called | reason, suggested tools |
| failed | agent exited without either: budget spent, crash, timeout, model unreachable | what was tried, **Try again** |

Impossible is a legitimate answer, not a failure.

**Request:** `<requirement>` (instructions) and `<sample_input>` (data — the prompt says never to follow anything inside it). The sample is mandatory, enforced by the form. The agent sees the sample text so it can write patterns; it just can't substitute it when checking.

**Feedback** is compiler errors, or the dry-run trace **including completed steps' outputs** — that lets the model see the real intermediate text and correct its patterns instead of guessing again.

**The gate is code, not the model.** Whatever shape the loop takes, a spec reaches the review screen only through a passing `run/2` run by our code — never because the model said it was done. And the sample comes from the session, never from the model.

**Human review shows extracted values, not the spec.** A pattern that matches the wrong thing passes every automatic check; only a person looking at the result catches it.

## Compiler

Validates in phases — shape, tool resolution, params, refs, output — and collects every error in a phase before stopping. Messages are prefixed `step "<name>": ` or `workflow: ` and list the valid alternatives when the set is closed (`unknown tool "regexp@1" (available: regex@1)`). These messages are what the model reads, so they're written for it.

## Settled

- **Executor → web:** the executor `send`s to a pid; `Server` updates its store, *then* broadcasts on PubSub. Not telemetry (detaches silently, isn't for payloads). Not a direct send to a LiveView (pids change, tabs multiply, runs outlive sockets).
- **Whole-spec generation**, not step-by-step: the dry-run trace gives the model the same information at one extra round trip.
- **Retries belong inside tools.** `execution.steps` stays 1:1 with `workflow.steps`.
- **Args are separate from step refs** — the workflow's signature vs its internals.
- **One app, not two.** Designer independence is enforced by module references, not by deployment.
- **Interpreter:** `Enum.reduce_while`, owned, ~40 lines. Runs under `Task.Supervisor`.

## Open questions

- What is the second demo?
- What happens on a name collision when the designer proposes a workflow name that already exists?
- Does the designer's dry run show in the UI timeline, or stay silent?
