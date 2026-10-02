# Karakuri

Working notes. Last updated 2026-10-02.

## Goal

An AI agent that generates workflows, where executing a generated workflow **never involves the designer**.

- **Designer** (an agent) — reads a user's requirements, picks tools, wires steps, tests against sample data, hands the result to the UI. Human in the loop.
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

**Stack:** Elixir, Phoenix LiveView, daisyUI. One application, two directories — the separation is architectural, not deployment. The rules worth enforcing: nothing under the executor references `Phoenix.*`, `KarakuriWeb`, or any designer module.

## Scope

**In:** workflows as data; fixed tool catalog; a compiler that validates specs statically; linear step chains; LiveView to prompt, generate, review and run.

**Out:** triggers beyond a Run button, auth, scheduling, branching, loops, expressions in params, agent-created tools, auto-repair of production failures, human editing of specs.

**Demo beat — two workflows, told in this order:**

1. `extract_number` — all deterministic, flagged reproducible. Unset the API key, restart, run it again on different input. It works.
2. `summarize_inbox` — has an `llm.summarize@1` step, flagged non-reproducible. It needs the key, but **the designer isn't running** and it executes anyway.

The second is the stronger demonstration, because it separates the two things people conflate. The flag in the UI is what makes the distinction visible rather than asserted.

---

## Current state

### Executor — works

- `%Workflow{name, steps, input, output}` with `%Workflow.Step{name, tool, order, input, output}`
- `%Execution{workflow, status, steps, output}` with `%Execution.Step{name, order, status, input, output, error, started_at, finished_at}`
- `Enum.reduce_while` interpreter, `with` chain per step
- `extract_input/3` resolves `{:args, field}` and `{:ref, step_name, field}`; literals pass through
- Resolution failures produce a failed step rather than escaping the run
- Tagged errors: `{:input_error, _}`, `{:tool_result, _}`, `{:tool_error, _}`, `{:exit, _}`
- `Karakuri.Executor.Tool` behaviour — `execute(map) :: {:ok, map} | {:error, any}`
- One tool: `Tool.Regex`, returning `%{match: ...}`. Capture-group handling deliberately dropped: it returns the first capture if the pattern has exactly one group, otherwise the whole match.
- Notifies a pid: `{:notify, :step_started | :step_finished | :workflow_finished, workflow_name, payload}`

### Server — works

`Karakuri.Server` GenServer: in-memory store plus run orchestration. Seeds `example_extract_number` at boot, `reset/0` restores it. Runs the executor under `Task.Supervisor.async_nolink`, receives notifies, updates state, rebroadcasts on the `"execution_event"` PubSub topic.

### Web — works

`WorkflowLive.Index` and `WorkflowLive.Show`, shared `Components`. Timeline merges `workflow.steps` with `execution.steps` by name so not-yet-run steps render as pending. Per-status icons, timestamps, workflow-level result slot. Form driven by the workflow's single `input:` key.

### Designer — scaffolded

- `Karakuri.Designer.Session` struct: `requirement, sample, status, spec, workflow, execution, feedback, reason, messages, attempts`
- `Karakuri.Designer.run/1` — a trampoline over `draft → compile → test`
- `draft/1` returns a hardcoded spec (no LLM call yet); `compile/1` and `test/1` are pass-throughs
- `priv/system_prompt.md` — spec rules, response contract, and a hand-written tool list

### Compiler — stub

`Karakuri.Compiler.compile/1` is `Jason.decode/1`. Nothing validates, nothing resolves.

### Toolbox — one entry

`Karakuri.Toolbox.catalog/0`, hardcoded, with NimbleOptions-shaped `input`, typed `output`, and an `example`.

---

## Open bugs

### Designer

1. **The attempt guard is in the wrong clause.** `run/1` checks `attempts >= @max_attempts` *before* the terminal-status clause, so a session that succeeds on the third attempt gets flipped to `:failed`. Terminals must match first — or better, move the guard into `draft/1`, where the retry is actually spent.
2. **`draft/1` never increments `attempts`.** Harmless while `compile` and `test` always succeed; an infinite loop the moment either routes back to `:drafting`.
3. **The stub spec uses a different ref form than the system prompt.** `draft/1` emits `["args", "text"]` and `["ref", "the_answer", "match"]`; the prompt documents `"{args.text}"` and `"{the_answer.match}"`. Must pick one before the compiler is written — the stub becomes the compiler's fixture, and the real model will follow the prompt.
4. **The stub spec includes `order: 0`.** Unused everywhere; delete.
5. **`system_prompt.md` duplicates the catalog** instead of concatenating `Toolbox.catalog/0`. Already drifted — the descriptions differ, and the catalog's example uses a grouped pattern (`Total:\s*([0-9.,]+)`) while the prompt's uses `\d+`.
6. **The catalog's example teaches a grouped pattern**, which the regex tool now handles by a hidden arity rule. Either the example loses its group or the rule becomes explicit.
7. **The response contract is ambiguous.** The prompt specifies `{"status": "impossible", ...}` but shows a bare workflow object for success. Needs `{"status": "ok", "workflow": {...}}` so the union is discriminated by one field. `suggested_tools` is missing entirely.
8. **No `failure_kind`.** "Never compiled", "dry run kept failing" and "model call errored" want different messages and different remedies; one `reason` string can't carry that.

### Executor / web

9. **`Show`'s notify guard matches on `@workflow_name`, which only `handle_event("start_workflow")` assigns.** Before the user clicks Start the assign does not exist, so every event falls to the catch-all and the page never updates — a run started from another tab, or already running on page load, is invisible. Match `@workflow.name` instead, which `handle_params` always assigns; the `workflow_name` assign then goes away.
10. **`:workflow_failed` never arrives.** The executor sends `:workflow_finished` unconditionally, so a failed run flashes "finished". Either carry the status in the payload and branch on it, or emit a distinct event.
11. **`Atom.to_string(workflow.input)` in two places** (`handle_event` and `input_form/1`), plus the atom-keyed args map. Breaks as soon as the compiler produces `%Workflow{input: "text"}` per the strings-for-model-supplied-names rule. Three-place change.
12. **`start_workflow`'s return value is discarded**, so `{:error, :busy}` / `{:error, :not_found}` would still flash "started".
13. **`inspect(@execution_step)` in the template** renders the whole struct — fine for regex, bad for a 200KB `pdf2text` output.
14. **One execution per workflow, keyed by name.** Every run overwrites the last: no history, no per-execution URL, and it hides memory growth.
15. **`execution_ref` is a single global lock** — one run at a time across the whole server.
16. **`input: :text` assumes one scalar arg.** A PDF workflow needs a file.
17. Cosmetic: `flash_notfication` typo; `dbg` in the catch-all `handle_info` will spam the console during a demo once two workflows exist; `tabindex="2  "`.

---

## The designer contract

### Session states

`:drafting → :compiling → :testing`, with two back-edges to `:drafting` carrying feedback. Three terminals:

| Terminal | Means | UI shows |
| --- | --- | --- |
| `:completed` | valid spec, dry run passed | steps, extracted values, Save button |
| `:failed` | attempts exhausted, or model unreachable | message + why; **Try again** (primary) and a pre-filled form to rephrase |
| `:impossible` | model says the catalog doesn't suffice | reason + suggested tools |

`:impossible` is not a failure. Conflating it with `:failed` loses the best demo beat.

On `:failed`, **Try again** (same inputs, fresh session) is the better primary action: three attempts failed with accumulated bad context anchoring the model, and a clean session often succeeds. Only "dry run kept failing" is genuinely the user's to fix.

### Request shape

```
<requirement>
create a workflow that extracts a number from a text
</requirement>

<sample_input>
The answer is 42
</sample_input>
```

The sample is DATA, never instructions — stated explicitly in the system prompt, because samples will eventually be arbitrary extracted document text.

### Response shape

```json
{ "status": "ok", "workflow": { "name": "...", "input": "...", "steps": [...], "output": "..." } }
{ "status": "impossible", "reason": "...", "suggested_tools": [ <catalog-shaped entry> ] }
```

Suggested tools are prose for a human to implement. **Never auto-registered.**

### Feedback shapes

```
<validation_errors>
step "number": unknown tool "regexp@1" (available: regex@1)
</validation_errors>
Return the corrected workflow JSON.
```

```
<dry_run_failure>
step "extract" completed. output.text (first 500 of 48213 chars): "..."
step "total" failed: no match
  pattern: "Total: ([0-9.]+)"
</dry_run_failure>
Return the corrected workflow JSON.
```

**The dry-run feedback must include completed steps' outputs.** That is the entire reason whole-spec generation works instead of incremental building: the model guesses a pattern, sees the real text in the trace, and corrects. Without the outputs, round 2 is another blind guess.

### What dry-run cannot catch

A pattern that matches the *wrong* thing — the invoice number instead of the total. Every step succeeds. No loop fixes this, which is why human review shows **extracted values**, not the spec.

### Sample preparation ≠ workflow execution

If the sample is a PDF, text must be extracted *before* generation so the model can read it. Same tool, different phase, fixed logic — not a model decision.

---

## Next

**1. Decide the ref form.** Blocks everything downstream, because the compiler is written against it and the stub spec is its first fixture.

- `"{args.text}"` — what the prompt documents, natural for the model, readable for a human. Needs a parser and the whole-value-or-nothing rule enforced.
- `["args", "text"]` — unambiguous, no escaping, makes partial interpolation impossible by construction. Uglier, and the model needs telling.

Recommendation: the string form, since the prompt already documents it and it's what a model produces naturally. Then make `draft/1`'s stub match.

**2. Make `Toolbox.catalog/0` the only tool list.** Keep the prose in `system_prompt.md`, append the catalog as JSON at runtime. Drop the hand-written block. Fix the example's grouped pattern while in there.

**3. Fix the designer bugs** — attempt guard placement, attempt increment, `order:`, the response contract, `failure_kind`.

**4. Write the compiler.** Phases, each collecting *all* its errors before the next:
   1. shape — required keys, types
   2. tool resolution — key → module via Toolbox
   3. param validation — NimbleOptions per step
   4. ref checking — target exists, is earlier, field exists, arg name matches the declared input
   5. output check — the workflow's output ref resolves
   6. step names unique, no dead steps, `deterministic` flag

Returns `{:ok, %Workflow{}} | {:error, [String.t()]}`. Every message prefixed `step "<name>": ` or `workflow: `, and lists the alternatives when the valid set is closed.

**5. The broken-spec test file.** One case per error message. This file is the contract between designer and executor, and writing the messages while *you* are the one reading them is how they end up good.

**6. Real `draft/1`.** Replace the stub with a model call. Keep a fixture of known-good JSON so compiler tests don't need the network.

**7. Wire the designer into the UI** — a create form (requirement + sample, both required), `Server.start_design/2` following the same Task + notify + PubSub pattern as executions, and a status line reading *Drafting… → Checking… → Testing… → Ready*.

**8. Then:** `pdf2text`, the blob question, `llm.summarize@1`, execution history.

---

## Settled

**Scope map vs `Enum.find`** — not needed. On a sequential, halt-on-first-failure executor with unique step names, both are last-wins and behaviourally identical. Revisit when a step's output has to be two things at once (real value for the next step, blob ref for the trace), or when the trace stops being an in-memory accumulator.

**Retries don't create duplicate step entries.** Tools own transient retries; most executor failures are deterministic. Attempt history, if ever needed, goes *inside* the step record.

**`{:args, field}` separate from `{:ref, name, field}`** — args are the workflow's signature, step outputs are internal. The compiler checks them separately and `args` never becomes a reserved step name.

**Model-supplied names are strings; registry-supplied names are atoms.** Arg names come from the model, so `{:args, "text"}` and `%Workflow{input: "text"}` — never `String.to_atom` on model output. Tool param names and output field names come from the closed catalog, so atoms are safe there.

**Executor ↔ web uses a notify pid, not telemetry.** Telemetry silently detaches handlers that raise, is implicit, and isn't meant to carry payloads.

**PubSub topic, not a direct send to the LiveView** — the pid changes on reconnect, a second tab has another, and the run outlives any socket.

**Update the store before broadcasting; subscribe before reading on mount.**

**The designer has no LLM tools.** Nothing in the loop is the model's decision: validation and dry-run are unconditional, saving is the human's. The model only emits specs. A model that *could* choose to skip validation sometimes will.

**Whole-spec generation, not incremental.** The dry-run trace gives the model the same information prefix-execution would, at the cost of one extra round trip. Revisit only if the loop fails to converge in three attempts on realistic requests.

**Sample input is mandatory, enforced by the form** — not negotiated by the model. That keeps the response shape singular and gives the model real text to pattern against.

**Retry budget: 3, then hard fail.** No handoff to a human editor.

**One app, not two.** Designer-independence is a property of the code. The invariant is enforced by module references, not by the dependency list — an `llm.*` tool legitimately needs a model client.

## Design rules

**Refs are the only ordering.** `order:` is still in the structs and still unused.

**No expressions in params.** A value is a literal or a whole ref, never a template.

**Iteration stays inside tools.** Lists in, lists out — no `foreach` in the spec.

**The catalog is generated from the registry**, never hand-written into a prompt, and carries per-param `doc` plus an `example` — that's what drives first-shot generation quality.

**The compiler is the executor's, and the designer calls it.** Two copies of the schema drift within a day and produce the worst failure: designer says valid, executor says unknown tool.

**Sample input becomes the version's fixture**, and doubles as a regression test when the spec is edited.

**Blob refs, not raw payloads**, once anything large crosses a step boundary. The seam is the storage boundary, not the executor.

**Versioning.** Step names immutable. Runs pin `workflow_version` + `spec_hash`. Versions record `author :agent | :human` and `parent_version_id`.

**Tools declare `deterministic?/0`.** ORed across a workflow into a flag shown in the UI. A tool calling an LLM must still have a *stable output shape* — the call is non-deterministic, the step's contract must not be. Structured output inside the tool; credentials from config, never from the definition.

**A workflow with a non-deterministic step can't be replayed.** Its fixture test asserts on shape, not content.

**Don't assert on `Exception.format/2` output** in tests.

## Library decisions

| Concern | Decision |
| --- | --- |
| Step interpreter | `Enum.reduce_while`. Owned, ~40 lines. |
| Run envelope | `Task.Supervisor` now; Oban later, one job per run, `max_attempts: 1`. |
| Executor → web | Notify pid → `Server` → PubSub. |
| Designer loop | Plain trampoline over a `%Session{}`. Finitomata only if the live state diagram is wanted for the demo. |
| Mermaid | Derived from the spec's refs, ~20 lines. No engine needed. |
| External commands | MuonTrap over `System.cmd` — timeouts, no orphans. |
| Param schemas | NimbleOptions per tool → JSON for the prompt. |
| Structured output | Constrained decoding once the error pattern is known; plain JSON + repair loop for the first spike. |

**Post-hackday:** Reactor (DAG, concurrency, compensation), Sage (compensation only), Continuum (durable replay — the answer if approval steps or long runs arrive).

## Open questions

- Does a literal that *looks* like a ref need an escape hatch?
- Type lattice: do lists need element types? (Untyped for now, noted as debt.)
- Is `file` a distinct type carrying a blob id rather than a path? (Should be — a spec must not be able to name `/etc/passwd`.)
- Can a tool's output schema depend on its params, or is it fixed per tool version?
- Does cancel need to interrupt mid-step?
- Name collisions: the model picked `extract_number`, which collides with the seeded example. Reject, overwrite, or auto-suffix?
- Does the designer's dry run broadcast to the UI timeline, or stay silent? (Broadcasting reuses the component for free and makes a better demo.)
