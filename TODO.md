# Karakuri — TODO

Last reviewed against `c8cdba3` on 2026-10-19. Concept lives in [KARAKURI.md](KARAKURI.md).

## Decided

- **2026-10-19 — Ref syntax:** `["args", "key"]` and `["ref", "step", "key"]`. See KARAKURI.md › Workflow definition.
- **2026-10-19 — Keep Ecto/Postgres.** Unused, but harmless. `mix setup` / `mix test` need a running Postgres — say so in the README.
- **2026-10-19 — Jido is the designer agent**, design time only.
- **2026-10-19 — Design flow** (KARAKURI.md › Who calls whom): `submit_workflow` is the agent's last call and ends its loop; the agent runs in its own task, the Server never waits on it; the session (with the sample) lives in the Server under its id; the tool functions in `Designer` call `run/2` and update the session, the Server broadcasts on `"design:<id>"`. **Happy path first**, failure paths after.
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

## Next — in order

1. **Get `mix test` green** — fix `designer_test.exs` (D1). Needs Postgres running.
2. **Make stub, prompt and catalog example use the list ref form** (D4, D5). The prompt still documents `"{args.text}"`.
3. **Regex takes string patterns**, drop `named_captures` (E3, E4). Seeded workflow uses strings.
4. **`Toolbox.catalog/0` is the only tool list** — append it to the prompt at runtime, drop the hand-written block (D5).
5. **Compiler**, minimal: shape → tool resolution → params → refs → output. Returns `{:ok, %Workflow{}} | {:error, [String.t()]}`. One test per error message.
6. **`Designer.run/2`** — compile + dry run. Offline tests with fixture specs: one valid, one invalid, one that fails on the sample. Delete the trampoline (D2, D3 go away with it).
7. **Spike: Jido** (1a, 1d). One dummy agent, one dummy Action. Print what arrives in `context`, and every event from `ask_stream/3` — especially what `:llm_completed` and `:tool_completed` carry in `data`.
8. **Agent-facing `Designer` functions** + `Designer.Report` — session store, `check` / `submit` / `report_impossible`, JSON-shaped results with truncated step outputs, check budget. Testable without Jido or a model.
9. **Jido agent** — add `jido` / `jido_ai` (pin 2.x; 3.0 is in beta), three Action wrappers, system prompt with the catalog.
10. **UI: create form** (requirement + sample), `Server.start_design/2` on the same Task + notify + PubSub pattern, status line, review shows extracted values, Save.
11. **Second demo.**

## Bugs

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

- Execution history and per-execution URLs (today: one execution per workflow name, a global run lock).
- File inputs, `pdf2text`, blob refs instead of raw payloads.
- `failure_kind` on the designer session (never compiled / dry run kept failing / model errored).
- Deterministic flag per workflow, shown in the UI.
- Side-effecting tools: the dry run would fire them on sample data. Needs a `side_effects?` declaration and a stub or refusal.
- Approved extracted values recorded as the fixture's expected output → regression test.
- Compile-time boundary check that the executor doesn't reference `Phoenix.*` / `KarakuriWeb` / designer.
- Versioning, Oban, Reactor.
