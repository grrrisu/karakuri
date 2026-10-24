# Karakuri — TODO

Last reviewed against `designer-workflow-2` @ `3163618` on 2026-10-24. Concept lives in [KARAKURI.md](KARAKURI.md).

## Decided

- **2026-10-22 — Arg naming:** the agent names the workflow's input; `Designer.run/2` binds the session's sample to that name. The agent never supplies the value. Arg names are strings end to end (W2). Multiple inputs later: samples get ids, the spec maps names to sample ids (KARAKURI.md › The agent interface).
- **2026-10-19 — Ref syntax:** `["args", "key"]` and `["ref", "step", "key"]`. See KARAKURI.md › Workflow definition.
- **2026-10-19 — Keep Ecto/Postgres.** Unused, but harmless. `mix setup` / `mix test` need a running Postgres — say so in the README.
- **2026-10-19 — Jido is the designer agent**, design time only.
- **2026-10-19 — Design flow** (KARAKURI.md › Who calls whom): `submit_workflow` is the agent's last call and ends its loop; the agent runs in its own task, the Server never waits on it; the session (with the sample) lives in the Server under its id; the tool functions in `Designer` call `run/2` and update the session, the Server broadcasts on `"design:<id>"`. **Happy path first**, failure paths after.
- **2026-10-19 — `Karakuri.Designer.Registry`** holds design sessions and monitors agent tasks; `Karakuri.Server` keeps workflows and executions. Designer → `Karakuri.Executor.Server.put_workflow` on Save is the only call across.
- **2026-10-19 — No separate `Workbench` module.** `Karakuri.Designer` is the context and holds the agent-facing functions; implementations in `Designer.*` modules.
- **2026-10-19 — Designer split:** a deterministic `Designer.run(spec_json, sample)` (compile + dry run) and a loop outside it that retries. See KARAKURI.md › Designer.

## Decisions needed

**1. ~~Shape of the Jido loop~~** — decided 2026-10-19: option B, a ReAct agent that models and tests its own workflows through tools. Start with an in-process Elixir API in the `Karakuri.Designer` context, exposed as `Jido.Action`s; MCP/CLI later over the same API. See KARAKURI.md › The agent interface.

**1a. How a tool call finds its session** — answered from the docs 2026-10-23: `ask_stream/3` forwards opts to `ask/3`, which accepts `tool_context:` and merges it into every tool's execution context. Pass `tool_context: %{session_id: id}`. The spike confirms the exact key path in `run/2`'s context (top level vs nested). Needs `Agent.Behaviour.ask_stream/3` (today `/2`).

**1b. ~~Does the human still save?~~** — yes: the agent submits, the human reviews extracted values and saves. The agent is gone by then.

**1d. Agent ↔ app communication.** Agent → app decided 2026-10-19: the design Task consumes `ask_stream/3` events and forwards a filtered subset (see KARAKURI.md › Seeing what the agent does). Still open: cancel (app → running agent), and whether the model actually emits text between tool calls — depends on model and prompt; check in the spike.

**1c. `workflow` param as an object or a JSON string?** New argument for string: `Action.to_tool/0` builds the tool schema with `strict: true`. Strict tool schemas (OpenAI-style) don't allow free-form objects, and a workflow spec is exactly that. A string param (`"workflow": "<JSON>"`) works under any provider and matches `Compiler.compile/1`, which takes JSON today. Recommendation changes to **string**; the spike tries a `:map` param with the chosen provider if you'd prefer the object.

**2. ~~What `run/2` returns~~** — decided 2026-10-19: success returns the dry-run execution too. Proposed shape `{:ok, workflow, execution} | {:error, {:invalid, [String.t()]}} | {:error, {:dry_run_failed, Execution.t()}}` — the error carries the reason, not the session; confirm. Name: `Designer.run/2`.

**2b. Sample → args.** The form gives a raw string, but the *model* picks the arg name (`"input": "text"`). So `run/2` must build the args from the compiled workflow: `%{workflow.input => sample}`. Today the executor uses atom arg keys (`%{text: ...}`); with model-chosen names they must be strings (W2).

**3. Where string patterns become regexes.** The seeded workflow and all tests pass compiled `~r//` values. A spec from JSON can only carry strings, and `Regex.run/2` with a string raises. Recommendation: the tool accepts a string and compiles it. That keeps inputs serializable and the compiler generic. An invalid pattern is then a `{:tool_result, _}`, and the compiler can pre-check it.

**4. Are tools `Jido.Action`s?** Tempting: actions bring schema validation and convert to LLM tool format, which is what `Toolbox` hand-builds. But the executor would then depend on `jido_action`. That is not an agent, so it doesn't break the invariant, but it ties the run-time to a library whose 3.0 is in beta. Recommendation: no for the PoC; keep `Karakuri.Executor.Tool` and `Toolbox` as they are.

**5. The second demo.**

**6. `Karakuri.Executor.Server` and the no-Phoenix rule.** The rename (`80758c2`) puts a module that uses `Phoenix.PubSub` inside `Karakuri.Executor`, the namespace the rule says must not touch Phoenix. Either narrow the rule to the interpreter and its data (docs now say this), or move the Server back out (`Karakuri.Runner`?). Matters once the boundary check exists: "nothing under `Karakuri.Executor` references Phoenix" is a one-line xref check; "nothing except `Server`" needs an exception list.

**8. Where does the compiler live?** `0de1572` moved it to `Karakuri.Designer.Compiler`. The concept had it on the executor side ("owned by the executor, the designer calls it"), because anything that turns a JSON spec into a `%Workflow{}` at run time — loading saved specs once they're persisted, importing one, an MCP client submitting one — would otherwise depend on the designer namespace. If saved workflows will always be stored as compiled structs and only the designer ever compiles, the move is fine. Which is it?

**7. Mock agent: how to simulate tool calls.** Proposal in KARAKURI.md › The mock agent: a scripted agent whose tool calls really call `Designer` functions, emitting events around them through a lazy stream. Can be built before the spike; the spike only replaces the guessed event `data` shapes.

## Next — in order

1. **Get `mix test` green** — fix `designer_test.exs` (D1). Needs Postgres running.
2. **Make stub, prompt and catalog example use the list ref form** (D4, D5). The prompt still documents `"{args.text}"`.
3. **Regex takes string patterns**, drop `named_captures` (E3, E4). Seeded workflow uses strings.
4. **`Toolbox.catalog/0` is the only tool list** — append it to the prompt at runtime, drop the hand-written block (D5).
5. **Compiler**, minimal: shape → tool resolution → params → refs → output. Returns `{:ok, %Workflow{}} | {:error, [String.t()]}`. One test per error message.
6. **`Designer.run/2`** — compile + dry run. Offline tests with fixture specs: one valid, one invalid, one that fails on the sample. Delete the trampoline (D2, D3 go away with it).
7. **Spike: Jido** (1a, 1c, 1d). Prerequisites: a model + provider key (direct `provider:model` string is simplest; `:capable` alias isn't configured), dev switched off the mock, a minimal option-B prompt (draft → `check_workflow` with JSON string → revise → reply with final spec), and the Action logging its whole `context` before matching on it. Record: where `session_id` lands in `context`; whether the model calls the tool and with what params; `data` of `:llm_completed` / `:tool_completed`; how an `{:error, _}` from an Action reaches the model (return one on purpose); turns used vs `max_iterations` (10). Keep it cheap: small model, `max_iterations` ~4, one-step requirement.
8. **`Designer.Registry`** (sessions, own `Task.Supervisor`, monitor, `"design:<id>"` broadcasts) + **agent-facing `Designer` functions** + `Designer.Report` — `check` / `submit` / `report_impossible`, JSON-shaped results with truncated step outputs, check budget. Testable without Jido or a model.
9. **Jido agent** — add `jido` / `jido_ai` (pin 2.x; 3.0 is in beta), three Action wrappers, system prompt with the catalog.
10. **UI: create form** (requirement + sample), `Designer.start_session/2` on the same Task + notify + PubSub pattern, status line, review shows extracted values, Save.
11. **Second demo.**

## Bugs

### Check workflow action (`designer-workflow-2` @ `3b65765`)

Done: `Actions.CheckWorkflow` (one line, string spec, `tool_context` session id), `Behaviour.ask_stream/3`, AgentTask passes `tool_context: %{session_id: …}`, raw-string sample, retries re-run (N1 fixed).

- ~~**C1.**~~ fixed in `3163618` (a spent budget short-circuits save/compile/test). **C1. The budget isn't enforced.** `check_attempts/1` marks the session `:failed` when the budget is spent, but the pipeline carries on: `save_spec` reads the stored session, sets `:running`, increments `attempts`, and compile + dry run happen anyway. Refuse by returning early (`with` or a `case` around the rest) with `%{status: "refused", reason: "check budget exhausted (N of N used)"}`.
- **C2. The check outcome is written into the session's status.** `save_result` now stores `status: :completed / :failed` from the dry run. It fixes the crash in `check_result`, but the Registry then says `:completed` after any passing check (nothing submitted) and `:failed` after any failing one (agent still working) — the LiveView will show that. Concept: the session status only changes on submit, impossible, or agent exit; the check's outcome lives in the return value or its own field.
- **C3. `save_spec` sets `:running` on every check** — a submitted session falls back from `:completed`. Set `:running` once in `create_session` (still `:drafting` there today).
- ~~**C4.**~~ fixed in `3163618`. **C4. `MockAgent.ask_stream/3` matches `tool_context: %{session_id: _}` literally** — the opts must be exactly that one-element keyword list; any added option (e.g. `timeout:`) is a `FunctionClauseError`. Take `opts` and read `opts[:tool_context][:session_id]`.
- **C5. `step_error/1`** still interpolates `reason`, which raises for non-strings (`{:exit, {:timeout, _}}`).
- **C6** — `tools: [CheckWorkflow]` wired in `3163618`; the prompt is still the old one. **C6. The action isn't wired:** `Designer.Agent` still has `tools: []`, and its prompt still describes the old JSON-reply contract (A8).
- **C7. The mock crashes:** it calls `CheckWorkflow.run(%{spec: "the json spec"}, …)`; that string isn't JSON, so `{:ok, _} = Compiler.compile(…)` raises inside the agent task (dev and test only).
- Smaller: two budget messages ("max compile attempts reached", "check budget exhausted") for one thing; `feedback` and `reason` duplicate each other; `reason` is `nil` for a normal dry-run failure (use the first failed step + error); `checks_left` in every result would let the agent plan; `compile/1` still sets `:compiled`.

### Registry and agent (`0de1572`)

- **M1** — partly fixed in `5f53f92`: the task result now updates only `messages`, `status`, `feedback`. Remaining: `status` from the task still overrides one set by `submit_workflow` (see M4), and `check_workflow` still writes its whole copy back (N3). **M1. The task result overwrites the session with a stale copy.** The working-copy pipeline (`get → do1 → do2 → update`) is fine with one writer, but during a design there are three: the task, the agent process (tool calls run there, not in the task), and the Registry itself (events). Timeline: task takes copy A → agent's `check_workflow` records attempt 1 → Registry appends an event → `submit_workflow` sets completed → task finishes and `Map.put`s copy A — attempts, events and completion gone. The mock hides it (no tool calls, no events forwarded). Keep the pipeline style, but end it with a *narrow* write: only the fields this pipeline owns, appends as functions applied to the Registry's current value (`fn s -> %{s | attempts: s.attempts ++ [a]} end`). Concretely: the task returns `{session_id, result}`, the `{ref, …}` handler applies the outcome (session still open → failed). N4 also still applies: the clause matches any 2-tuple, no `demonitor(ref, [:flush])`, no catch-all.
- **M2** — note `5f53f92` removed the `{:designer_event, …}` handler, so forwarding needs it back. **M2. Agent events are stored, not forwarded.** The task puts the whole `events` enumerable into `session.messages` and never iterates it. With the mock that's a list that arrives at the end; with Jido it's a stream that nobody consumes, so the UI sees nothing until the agent is done — the opposite of "Seeing what the agent does". The `{:designer_event, session_id, event}` handler is ready; the task needs `Enum.each(events, &send(registry, {:designer_event, session.id, &1}))` before `await`, filtering out `:llm_delta`. It also stores a stream struct (closures) in Registry state.
- **M3** — decided 2026-10-22: the agent names the arg in the spec (`"input": "…"`), our code binds the value: `run/2` executes with `%{workflow.input => session.sample}`. The sample stays a raw string. Naming isn't cheating; supplying the value would be. **M3. The sample is now a JSON string** (`{"text": "…"}`), decoded in `test/1` into the run's args. That makes the user's form decide the arg name, which only works if the model happens to pick the same name in its spec. It also puts JSON inside `<sample_input>` in the prompt, and the Registry test still uses a plain string, which `Jason.decode!` would reject. Concept: the sample is raw text; `run/2` builds `%{workflow.input => sample}` after compiling (2b).
- **M4. The agent's final answer decides the outcome.** `agent_task_finished/2` maps `{:ok, _}` from `await` to `:completed`. With the real agent, `await` returns `{:ok, text}` whenever the model stops talking — with or without a valid workflow. Concept: completed only through `submit_workflow`; when the task ends and the session is still open, it's failed. Fine as a happy-path placeholder, but don't build the UI on it. (It also stores the result in `feedback`, a trampoline field.)
- **M5. Every check passes.** `compile/1` decodes the spec but discards it and returns a hard-coded `%Workflow{}` with no steps; executing no steps completes with `nil` output. Expected for a stub — but then the "check workflow" test (still without assertions, N7) proves nothing. And `{:ok, _} = Compiler.compile(…)` turns invalid JSON from the model into a crash in the agent's tool call instead of an error message back to the agent. N1 (retry never re-runs) is unchanged.
- **M6. `start_agent/1` now runs inside the Registry's `handle_call`.** That's fine for speed, but `{:ok, pid} = Jido.start_agent(…)` crashing there takes down the Registry and every session with it. Match the error and return `{:error, reason}` from `create_session`. With the mock, `agent_pid` is now the Registry's own pid.
- ~~**M7.**~~ fixed in `5f53f92` (unknown ids ignored, with a test). **M7. `update_session/3` creates a session for an unknown id** (`Map.update` with a default `%Session{id: …}`). A late event for a removed session would resurrect an empty one. Ignore unknown ids instead.
- **M8. `Process.sleep(100)` in the Registry test** — timing-dependent, and AGENTS.md asks for `assert_receive` or `:sys.get_state` instead. Once the Registry broadcasts on `"design:<id>"`, subscribe in the test and `assert_receive` the completion.

### Designer flow (`7d81a36`)

- **N1. A retry never runs the new spec.** The trampoline survives inside `check_workflow`: after the first check, `test/2` sets the session status to the execution's status (`:completed` or `:failed`). The next `check_workflow` call hits the first `run/2` clause — terminal status — which only bumps `attempts`. No compile, no dry run: the agent gets the *old* result for its *new* spec, forever. Same root: a failed dry run sets the session to `:failed`, which in the concept means "the whole design failed".
  Fix in the concept's shape: `Designer.run(spec, sample)` is stateless — compile, build args, execute, return `{:ok, workflow, execution} | {:error, …}`. `check_workflow` is the only place that touches the session: spend a check, call `run/2`, append `{spec, result}` to `attempts`. Session status stays `:running` until submit / impossible / agent exit. That removes `@max_attempts` from `run` too — the budget lives in the session.
- ~~**N2.**~~ `input` parameter removed in `0de1572` — sample now comes from the session. The sample's *format* is still open, see M3. **N2. The sample comes from the caller.** `check_workflow(session_id, json_spec, input, …)` takes `input` as a parameter — the agent's tool call would supply it. That is the one thing the concept says the agent must never pass: it can make a check pass by testing against easier input. Drop the parameter; build `%{workflow.input => session.sample}` inside (2b). (The test's `%{text: …}` also uses an atom key, which won't match a string arg name from the compiler.)
- **N3. Lost updates.** `check_workflow` reads the session, works on its copy outside the Registry, then writes the whole copy back (`fn _ -> session end`). Anything the Registry changed in between — status from a `:DOWN`, a recorded event, a second tool call — is silently overwritten. Run the dry run outside the Registry (right — don't block it), but write back a *narrow* change with a function: `fn s -> %{s | checks_left: s.checks_left - 1, attempts: [attempt | s.attempts]} end`. With R2 that function can also refuse when the budget is 0.
- **N4. `handle_info({_ref, result}, …)` matches any 2-tuple.** Guard it (`when is_reference(ref)`), `Process.demonitor(ref, [:flush])`, and find the session by `agent_task.ref`. Add a final catch-all `handle_info(_msg, state)` — a stray message still crashes the Registry today.
- **N5. Process bookkeeping in the session** (`agent_task`, and `agent_pid` via `Map.put` in `start_agent/1` — A7). The `%Task{}` travels to every caller of `get_session`, including the LiveView later, and the Registry has to scan all sessions to map a ref back to a session. Suggest Registry state `%{sessions: %{id => session}, tasks: %{ref => id}}`. Fine to defer, but do it before the LiveView reads sessions.
- **N6. `check_workflow` returns Elixir terms** (`{:error, %Session{}}`). The agent needs JSON-shaped maps (`Designer.Report`). Either the function returns maps, or the `Jido.Action` wrapper converts — decide which layer owns it before writing the wrappers. Concept says the `Designer` function.
- **N7. `test "check workflow"` asserts nothing.** It also builds a session by hand with `status: :drafting` and no sample — it would hide N1 and N2. Once `run/2` is stateless, test it directly with fixture specs (one valid, one invalid, one failing on the sample), and test `check_workflow` for: budget spent, attempt recorded, sample taken from the session.
- ~~**N8.**~~ removed. **N8. `dbg` in `get_session`** — three per call; will drown the console once the agent calls tools.
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
