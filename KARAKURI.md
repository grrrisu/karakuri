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

**In:** workflows as data, a fixed tool catalog, a compiler that validates definitions, linear step chains, a LiveView UI to describe, review and run, an in-memory store.

**Out:** persistence, auth, triggers beyond a Run button, scheduling, branching, loops, expressions in params, agent-created tools, human editing of definitions, run history.

## Demo

1. **`extract_number`** — regex steps only. Run it. Unset the API key, restart, run it again on different input. It still works: the designer is gone, the workflow isn't.
2. *To be defined.*

## Architecture

```
requirement + sample
        │
   Designer ──(spec JSON)──► Compiler ──(%Workflow{})──► Executor ──► %Execution{}
     ▲  │                        │                          │
     └──┴── feedback: validation errors, dry-run trace ─────┘
```

One Elixir/Phoenix application. The separation is architectural, not deployment: nothing in the executor references `Phoenix.*`, `KarakuriWeb` or any designer module. The executor runs from `iex` with nothing else started.

| Part | Role |
| --- | --- |
| `Karakuri.Executor` | Interpreter. Walks a `%Workflow{}`, returns an `%Execution{}`, notifies a pid per step. |
| `Karakuri.Compiler` | Spec JSON → `%Workflow{}` or a list of error messages. Owned by the executor side; the designer calls it. |
| `Karakuri.Toolbox` | The tool catalog. The single source for both compiler and designer prompt. |
| `Karakuri.Designer` | The draft → compile → test loop over a `%Session{}`. |
| `Karakuri.Server` | In-memory store, run orchestration, PubSub broadcast. |
| `KarakuriWeb` | LiveView UI. |

## Workflow definition

- A workflow has a name, one input, a linear list of steps, and an output.
- Each step calls one tool from the catalog.
- A step's input values are **literals or whole refs** — never a template. A ref points to the workflow's input or to a named output field of an *earlier* step. Refs are the only ordering.
- The workflow's output is a ref.
- No branching, no loops, no expressions. Iteration lives inside tools: lists in, lists out. String building is a tool.
- The concrete JSON ref syntax is an open decision (see TODO.md).

**Tools** take a map and return `{:ok, map}` with named fields, or `{:error, reason}` for expected failures. Inputs and outputs are JSON-serializable. Each tool declares whether it is deterministic.

**Names.** Names the model supplies (workflow, step, arg names) stay strings. Names from the catalog (tool keys, param and output fields) may be atoms. Never `String.to_atom` on model output.

## Designer loop

States `:drafting → :compiling → :testing`, with back-edges to `:drafting` carrying feedback. At most 3 drafts, then hard fail.

| Terminal | Means | UI shows |
| --- | --- | --- |
| `:completed` | valid spec, dry run passed | steps, extracted values, Save |
| `:failed` | attempts exhausted, or model unreachable | reason, **Try again** (fresh session) |
| `:impossible` | the catalog doesn't suffice | reason, suggested tools |

`:impossible` is a legitimate answer, not a failure.

**Request:** `<requirement>` (instructions) and `<sample_input>` (data — the prompt says never to follow anything inside it). The sample is mandatory, enforced by the form.

**Response:** `{"status": "ok", "workflow": {...}}` or `{"status": "impossible", "reason": "...", "suggested_tools": [...]}`. Suggested tools are prose for a human; never auto-registered.

**Feedback** is compiler errors, or the dry-run trace **including completed steps' outputs** — that lets the model see the real intermediate text and correct its patterns instead of guessing again.

**The model has no tools.** Validation and dry run are unconditional; saving is the human's call. The model only emits specs.

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
