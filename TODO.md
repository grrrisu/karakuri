# Karakuri — TODO

Last reviewed against `designer-flow` @ `7d81a36` on 2026-10-20. Concept lives in [KARAKURI.md](KARAKURI.md).

## Decided

- **2026-10-19 — Ref syntax:** `["args", "key"]` and `["ref", "step", "key"]`. See KARAKURI.md › Workflow definition.
- **2026-10-19 — Keep Ecto/Postgres.** Unused, but harmless. `mix setup` / `mix test` need a running Postgres — say so in the README.
- **2026-10-19 — Jido is the designer agent**, design time only.
- **2026-10-19 — Design flow** (KARAKURI.md › Who calls whom): `submit_workflow` is the agent's last call and ends its loop; the agent runs in its own task, the Server never waits on it; the session (with the sample) lives in the Server under its id; the tool functions in `Designer` call `run/2` and update the session, the Server broadcasts on `"design:<id>"`. **Happy path first**, failure paths after.
- **2026-10-19 — `Karakuri.Designer.Registry`** holds design sessions and monitors agent tasks; `Karakuri.Server` keeps workflows and executions. Designer → `Karakuri.Executor.Server.put_workflow` on Save is the only call across.
- **2026-10-19 — No separate `Workbench` module.** `Karakuri.Designer` is the context and holds the agent-facing functions; implementations in `Designer.*` modules.
- **2026-10-19 — Designer split:** a deterministic `Designer.run(spec_json, sample)` (compile + dry run) and a loop outside it that retries. See KARAKURI.md › Designer.

## Decisions needed

**1. ~~Shape of the Jido loop~~** — decided 2026-10-19: option B, a ReAct agent that models and tests its own workflows through tools. Start with an in-process Elixir API in the `Karakuri.Designer` context, exposed as `Jido.Action`s; MCP/CLI later over the same API. See KARAKURI.md › The agent interface.

**1a. How a tool call finds its session.** The sample and budget must come from server-side session state, so each `Jido.Action` needs the session id. Jido Actions are `run(params, context)`, and the Standalone ReAct guide says an agent injects its state as the `:state` context key — so `session_id` in agent state should reach every tool. **Confirm in the spike** — it decides whether the interface works as designed. Fallback: `session_id` as a tool parameter. That's acceptable, because the id only *selects* a session; the sample is still looked up server-side and the model can't change it.

**1b. ~~Does the human still save?~~** — yes: the agent submits, the human reviews extracted values and saves. The agent is gone by then.

**1d. Agent ↔ app communication.** Agent → app decided 2026-10-19: the design Task consumes `ask_stream/3` events and forwards a filtered subset (see KARAKURI.md › Seeing what the agent does). Still open: cancel (app → running agent), and whether the model actually emits text between tool calls — depends on model and prompt; check in the spike.

**1c. `workflow` param as an object or a JSON string?** An object lets the tool schema describe it (and enables constrained decoding later); a string is simpler to pass through. Recommendation: object with a loose schema (`name`, `input`, `steps`, `output` required, steps free-form) — the compiler gives the precise errors.

**2. ~~What `run/2` returns~~** — decided 2026-10-19: success returns the dry-run execution too. Proposed shape `{:ok, workflow, execution} | {:error, {:invalid, [String.t()]}} | {:error, {:dry_run_failed, Execution.t()}}` — the error carries the reason, not the session; confirm. Name: `Designer.run/2`.

**2b. Sample → args.** The form gives a raw string, but the *model* picks the arg name (`"input": "text"`). So `run/2` must build the args from the compiled workflow: `%{workflow.input => sample}`. Today the executor uses atom arg keys (`%{text: ...}`); with model-chosen names they must be strings (W2).

**3. Where string patterns become regexes.** The seeded workflow and all tests pass compiled `~r//` values. A spec from JSON can only carry strings, and `Regex.run/2` with a string raises. Recommendation: the tool accepts a string and compiles it. That keeps inputs serializable and the compiler generic. An invalid pattern is then a `{:tool_result, _}`, and the compiler can pre-check it.

**4. Are tools `Jido.Action`s?** Tempting: actions bring schema validation and convert to LLM tool format, which is what `Toolbox` hand-builds. But the executor would then depend on `jido_action`. That is not an agent, so it doesn't break the invariant, but it ties the run-time to a library whose 3.0 is in beta. Recommendation: no for the PoC; keep `Karakuri.Executor.Tool` and `Toolbox` as they are.

**5. The second demo.**

**6. `Karakuri.Executor.Server` and the no-Phoenix rule.** The rename (`80758c2`) puts a module that uses `Phoenix.PubSub` inside `Karakuri.Executor`, the namespace the rule says must not touch Phoenix. Either narrow the rule to the interpreter and its data (docs now say this), or move the Server back out (`Karakuri.Runner`?). Matters once the boundary check exists: "nothing under `Karakuri.Executor` references Phoenix" is a one-line xref check; "nothing except `Server`" needs an exception list.

**7. Mock agent: how to simulate tool calls.** Proposal in KARAKURI.md › The mock agent: a scripted agent whose tool calls really call `Designer` functions, emitting events around them through a lazy stream. Can be built before the spike; the spike only replaces the guessed event `data` shapes.

## Next — in order

1. **Get `mix test` green** — fix `designer_test.exs` (D1). Needs Postgres running.
2. **Make stub, prompt and catalog example use the list ref form** (D4, D5). The prompt still documents `"{args.text}"`.
3. **Regex takes string patterns**, drop `named_captures` (E3, E4). Seeded workflow uses strings.
4. **`Toolbox.catalog/0` is the only tool list** — append it to the prompt at runtime, drop the hand-written block (D5).
5. **Compiler**, minimal: shape → tool resolution → params → refs → output. Returns `{:ok, %Workflow{}} | {:error, [String.t()]}`. One test per error message.
6. **`Designer.run/2`** — compile + dry run. Offline tests with fixture specs: one valid, one invalid, one that fails on the sample. Delete the trampoline (D2, D3 go away with it).
7. **Spike: Jido** (1a, 1d). One dummy agent, one dummy Action. Print what arrives in `context`, and every event from `ask_stream/3` — especially what `:llm_completed` and `:tool_completed` carry in `data`.
8. **`Designer.Registry`** (sessions, own `Task.Supervisor`, monitor, `"design:<id>"` broadcasts) + **agent-facing `Designer` functions** + `Designer.Report` — `check` / `submit` / `report_impossible`, JSON-shaped results with truncated step outputs, check budget. Testable without Jido or a model.
9. **Jido agent** — add `jido` / `jido_ai` (pin 2.x; 3.0 is in beta), three Action wrappers, system prompt with the catalog.
10. **UI: create form** (requirement + sample), `Designer.start_session/2` on the same Task + notify + PubSub pattern, status line, review shows extracted values, Save.
11. **Second demo.**

## Bugs

### Designer flow (`7d81a36`)

- **N1. A retry never runs the new spec.** The trampoline survives inside `check_workflow`: after the first check, `test/2` sets the session status to the execution's status (`:completed` or `:failed`). The next `check_workflow` call hits the first `run/2` clause — terminal status — which only bumps `attempts`. No compile, no dry run: the agent gets the *old* result for its *new* spec, forever. Same root: a failed dry run sets the session to `:failed`, which in the concept means "the whole design failed".
  Fix in the concept's shape: `Designer.run(spec, sample)` is stateless — compile, build args, execute, return `{:ok, workflow, execution} | {:error, …}`. `check_workflow` is the only place that touches the session: spend a check, call `run/2`, append `{spec, result}` to `attempts`. Session status stays `:running` until submit / impossible / agent exit. That removes `@max_attempts` from `run` too — the budget lives in the session.
- **N2. The sample comes from the caller.** `check_workflow(session_id, json_spec, input, …)` takes `input` as a parameter — the agent's tool call would supply it. That is the one thing the concept says the agent must never pass: it can make a check pass by testing against easier input. Drop the parameter; build `%{workflow.input => session.sample}` inside (2b). (The test's `%{text: …}` also uses an atom key, which won't match a string arg name from the compiler.)
- **N3. Lost updates.** `check_workflow` reads the session, works on its copy outside the Registry, then writes the whole copy back (`fn _ -> session end`). Anything the Registry changed in between — status from a `:DOWN`, a recorded event, a second tool call — is silently overwritten. Run the dry run outside the Registry (right — don't block it), but write back a *narrow* change with a function: `fn s -> %{s | checks_left: s.checks_left - 1, attempts: [attempt | s.attempts]} end`. With R2 that function can also refuse when the budget is 0.
- **N4. `handle_info({_ref, result}, …)` matches any 2-tuple.** Guard it (`when is_reference(ref)`), `Process.demonitor(ref, [:flush])`, and find the session by `agent_task.ref`. Add a final catch-all `handle_info(_msg, state)` — a stray message still crashes the Registry today.
- **N5. Process bookkeeping in the session** (`agent_task`, and `agent_pid` via `Map.put` in `start_agent/1` — A7). The `%Task{}` travels to every caller of `get_session`, including the LiveView later, and the Registry has to scan all sessions to map a ref back to a session. Suggest Registry state `%{sessions: %{id => session}, tasks: %{ref => id}}`. Fine to defer, but do it before the LiveView reads sessions.
- **N6. `check_workflow` returns Elixir terms** (`{:error, %Session{}}`). The agent needs JSON-shaped maps (`Designer.Report`). Either the function returns maps, or the `Jido.Action` wrapper converts — decide which layer owns it before writing the wrappers. Concept says the `Designer` function.
- **N7. `test "check workflow"` asserts nothing.** It also builds a session by hand with `status: :drafting` and no sample — it would hide N1 and N2. Once `run/2` is stateless, test it directly with fixture specs (one valid, one invalid, one failing on the sample), and test `check_workflow` for: budget spent, attempt recorded, sample taken from the session.
- **N8. `dbg` in `get_session`** — three per call; will drown the console once the agent calls tools.
- Still open from before: A5 (session id → agent), A7, A8 (prompt), A9 (model alias + key), A10, R2, R3 (Session shape), R4, R5, R6 (PubSub starts after the Registry; `Designer.Jido` too).

### Designer agent (`80758c2`)

- ~~**A1.**~~ fixed in `7d81a36`. **A1. `Karakuri.Designer.TaskSupervisor` is never started** (`application.ex`). `Task.Supervisor.async_nolink` exits with `:noproc`, which crashes the Registry inside `create_session`. Add it to the children, before the Registry.
- ~~**A2.**~~ fixed in `7d81a36` (task now in `session.agent_task` — see N2). **A2. `create_session` stores a `%Task{}` as the session.** `session = start_agent_task(session)` — but `start_agent_task/1` returns the task, not the session. The caller gets `{:ok, %Task{}}` and the map holds the task. Keep the session; put the task ref in the Registry's own state (`%{sessions: …, tasks: %{ref => session_id}}`).
- ~~**A3.**~~ handlers added in `7d81a36`, bodies still TODO — see N1. **A3. The Registry crashes when a design ends.** It owns the `async_nolink` task, so it receives `{ref, result}` and `{:DOWN, …}`. The only `handle_info` clause matches `{:designer_event, _}`, so the first of those is a `FunctionClauseError`. That's also the hook for "agent completed" — handle `{ref, result}` (demonitor + flush) and `{:DOWN, …}` (session still open → failed), plus a catch-all.
- ~~**A4.**~~ fixed: `Karakuri.Designer.Jido`. **A4. `Shakkuri.Jido.start_agent`** — a module from the other project. Jido 2.x wants an instance in this app: `defmodule Karakuri.Jido, do: use Jido, otp_app: :karakuri`, added to the supervision tree, then `Karakuri.Jido.start_agent(Karakuri.Designer.Agent, id: …)`. Hidden today because dev and test use the mock.
- **A5. The session id never reaches the agent.** `start_agent/1` passes only `id:`; the tools will need the session id (1a). Use the session id as the agent id, or pass it in the agent's initial state — whichever the spike shows ends up in tool `context`.
- ~~**A6.**~~ fixed with R1. **A6. `#{session.sample}` in the prompt** raises if the sample is a map (`String.Chars` isn't implemented for maps) — and it is a map in the Registry test. Same root cause as R1.
- **A7. `Map.put(session, :agent_pid, …)`** adds a key that `%Session{}` doesn't define. Works by accident, but `struct!/2` updates would reject it, and the pid only lives in the task's copy anyway. The pid belongs to the task, not the session (R3).
- **A8. The agent's system prompt is a third copy** (after `system_prompt.md` and `Toolbox`), still with the old ref form in the rules, `"Reply with JSON only"` and the `{"status": "impossible"}` response contract — option A wording. For option B the prompt says: design a workflow, test it with `check_workflow`, finish with `submit_workflow` or `report_impossible`. The catalog part should come from `Toolbox` (D5).
- **A9. `model: :capable`** needs a `model_aliases` entry and a provider key in config. Not in `config/*.exs` yet.
- **A10. `MockAgent.await/2` calls `Mix.env()`** — Mix isn't available in a release. Read a config value instead, or let the scenario define delays.
- **A11. `Designer.check_workflow/2` still drives the trampoline** (`run(session)`, statuses). Expected at this stage; for the concept, `run/2` takes `(spec, sample)` and the session handling stays in `check_workflow`.
- Good: the behaviour + config switch, `async_nolink` from the Registry so it never blocks on the agent, forwarding events to the Registry rather than straight to LiveViews.
- To verify once it compiles against the real agent: that `use Jido.AI.Agent` defines `ask_stream/2` and `await/2` (docs list arities 2,3 and 1,2), so the `@behaviour` is satisfied without warnings.

### Designer.Registry (`dedf453`)

- ~~**R1.**~~ fixed in `7d81a36`: the sample is a raw string. **R1. The sample is stored keyed by arg name** (`%{"text" => …}` in the test and the `Session` comment). But the *model* picks the arg name when it writes the spec (`"input": "invoice"`), so a stored key can't be known upfront. Store the raw sample string; `Designer.run/2` builds `%{workflow.input => sample}` (2b).
- **R2. A function update can't refuse.** `get_and_update/3` with a function must return a `%Session{}`. Spending a check needs "decrement, or refuse if the budget is 0" atomically inside the GenServer — let the function return `{:ok, session} | {:error, reason}`, and the refusal reaches the agent as `"check budget exhausted"`.
- **R3. `Session` still has the trampoline's shape.** `status: :drafting`, `spec`, `feedback`, `messages` belong to the old draft → compile → test loop. For option B: `id, requirement, sample, status (:running | :completed | :impossible | :failed), checks_left, attempts (list of {spec, result}), workflow, execution, reason, suggested_tools`. The agent's pid/monitor ref belongs in the Registry's state, not the session.
- **R4. Name.** In Elixir, `Registry` means a process registry, and the test's `alias Karakuri.Designer.Registry` shadows the stdlib `Registry` in that file. If sessions later become one process each, you'd want the real `Registry` and the names collide. `Designer.Registry` or `Designer.Sessions` would say what it is. Docs use `Designer.Registry` until you decide.
- **R5. `get_and_update/3` returns the updated value**, while `Map.get_and_update`, `Agent.get_and_update` etc. return `{get, update}`. `update_session/3` avoids the surprise.
- **R6. Supervision order** (`application.ex`): `Karakuri.Server` and `Designer.Registry` start *before* `Phoenix.PubSub`. Harmless while neither broadcasts in `init`, but `Designer.Registry` will broadcast, and a broadcast before PubSub is up crashes. Move `{Phoenix.PubSub, …}` to the top. The agent tasks' `Task.Supervisor` also has to start before the Registry.
- **R7. `system_prompt.md` still teaches the old ref form** in its rules block (lines 4–7: `"{args.<name>}"`, `"{<step_name>.<field>}"`) — only the example step was updated. The model follows the rules block. (Part of D5.)
- Fine as is: every update goes through the GenServer, so updates are serialized; `id` is protected; `start_supervised!` with `name: nil` in tests. Sessions are never removed — OK for the PoC, noted under Later.

### Designer

- **D1. `test/karakuri/designer_test.exs` doesn't compile.** Calls `Designer.generate/1` (it's `/2`), `Karakuri.Workflows.compile/1` (doesn't exist) and `@sample` (undefined), and expects JSON back where `generate` returns a workflow. A compile error in a test file stops the whole suite.
- **D2. Attempt guard fires on every non-terminal status** (`designer.ex:22`). Moot once the trampoline is replaced by `run/2` + the Jido loop; carry the lesson over: count an attempt where the model is called, and check the limit only there.
- **D3. `draft/1` never increments `attempts`.** Same — moot after the split.
- **D4. Stub spec** has `order: 0`. The list ref form is now the decided one. Note the JSON key is `input` per step and `input` per workflow, but they mean different things (param map vs arg name).
- **D5. `system_prompt.md` duplicates the catalog** and has drifted: different description, different example pattern (`\d+` vs `Total:\s*([0-9.,]+)`). It also documents the rejected `"{args.text}"` ref form and the catalog example uses it too (`toolbox.ex:23`).
- **D6. Response contract** — obsolete with option B: the agent finishes by calling `submit_workflow` or `report_impossible`, not by answering in a JSON shape. The prompt section on response shape goes away.
- **D7. `dbg` in `run/1`** (`designer.ex:26`).

### Executor

- **E1. An input error overwrites the previous step's record.** On a ref failure the executor sends `:step_finished` without a `:step_started`. `Server` handles `:step_finished` with `List.replace_at(steps, -1, step)`, so the failed step replaces the last *completed* one in the store — or vanishes, if it's the first step. (`executor.ex:57–71`, `server.ex:110–116`)
- **E2. `:workflow_finished` is sent for failed runs too** (`executor.ex:21`), so the UI flashes "finished". `:workflow_failed` is only broadcast when the task crashes (`server.ex:126`), never for a step failure. Carry the status in the payload.
- **E3. Regex tool expects a compiled regex** — see decision 2.
- **E4. `named_captures: true`** returns string-keyed fields whose names depend on the pattern. That breaks the "stable output shape" rule and isn't in the catalog. Remove for the PoC. Also: KARAKURI.md used to say multiple groups return the whole match; the code returns an error, which is the better behaviour.
- **E5. `executor_test.exs:54` asserts on `Exception.format/2` output**, against the project's own rule. Assert on the `:input_error` tag.
- **E6. Cosmetic:** dead `{key, value}` line (`executor.ex:34`); `Execution.Step` typespec says `:running`, code uses `:in_progress`.

### Server

- **S1. Unknown workflow name crashes the Server** (`server.ex:55–63`: `nil.name`), wiping every in-memory workflow.
- **S2. `start_workflow` is a cast**, so a busy or unknown run is silently dropped and the UI flashes "started" anyway. Make it a call returning `:ok | {:error, :busy | :not_found}`.
- **S3. Broadcast before store update** in all three notify handlers. Harmless today — the LiveView's follow-up `get_last_execution` call queues behind the handler — but it inverts the settled rule and breaks as soon as anything reads state another way.
- **S4. `reset/0` during a run** keeps the lock, and the finishing task writes its execution back into the reset store.

### Web

- **W1. `Show` only updates after *you* click Start.** The notify guard matches `@workflow_name`, which only `start_workflow` assigns. Match `@workflow.name`.
- **W2. `Atom.to_string(workflow.input)`** in `handle_event` and `input_form/1`, plus atom-keyed args. Breaks when the compiler produces string arg names.
- **W3. `inspect(@execution_step)`** renders the whole struct. Show the output fields.
- **W4. Unknown workflow URL** → `@workflow` is nil → render crashes.
- **W5. Cosmetic:** `flash_notfication`; `dbg` in the catch-all `handle_info`; `tabindex="2  "`.

### Tests

- **T1. `workflow_live_test.exs:29–38`** asserts on step success straight after `render_submit`, while the run happens in another process. It passes on timing. Wait for the `:workflow_finished` broadcast first.

## Later (post-PoC)

- Remove or expire finished design sessions (today they live until restart).

- Execution history and per-execution URLs (today: one execution per workflow name, a global run lock).
- File inputs, `pdf2text`, blob refs instead of raw payloads.
- `failure_kind` on the designer session (never compiled / dry run kept failing / model errored).
- Deterministic flag per workflow, shown in the UI.
- Side-effecting tools: the dry run would fire them on sample data. Needs a `side_effects?` declaration and a stub or refusal.
- Approved extracted values recorded as the fixture's expected output → regression test.
- Compile-time boundary check that the executor doesn't reference `Phoenix.*` / `KarakuriWeb` / designer.
- Versioning, Oban, Reactor.
