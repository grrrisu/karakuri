# Karakuri — TODO

Last reviewed against `c8cdba3` on 2026-10-19. Concept lives in [KARAKURI.md](KARAKURI.md).

## Decisions needed

**1. Ref syntax in the spec JSON.** Blocks the compiler, and the stub spec in `draft/1` is the compiler's first fixture. Today the prompt says `"{args.text}"`, the stub emits `["args", "text"]`.

| Form | For | Against |
| --- | --- | --- |
| `"{args.text}"` | what the prompt documents; readable | needs a parser; a literal that looks like a ref needs an escape rule |
| `["args", "text"]` | unambiguous | a list-typed literal param would collide; model needs telling |
| `{"ref": "args.text"}` | unambiguous, readable, models produce it reliably | a map-typed literal param would collide (none in the catalog) |

**2. Where string patterns become regexes.** The seeded workflow and all tests pass compiled `~r//` values; a spec from JSON can only carry strings, and `Regex.run/2` with a string raises. Recommendation: the tool accepts a string and compiles it — keeps inputs serializable and the compiler generic. An invalid pattern is then a `{:tool_result, _}`, and the compiler can pre-check it.

**3. Drop Ecto/Postgres?** `Karakuri.Repo` is started but used nowhere, and `mix setup` / `mix test` both require a running Postgres. For a PoC whose store is in-memory, removing it makes "clone and run" one step shorter.

**4. The second demo.**

## Next — in order

1. **Get `mix test` green** — remove Postgres (decision 3) and fix `designer_test.exs` (bug D1).
2. **Decide the ref syntax**, make the stub, prompt and catalog example agree.
3. **Regex takes string patterns**, drop `named_captures` (bugs E3, E4). Seeded workflow uses strings.
4. **`Toolbox.catalog/0` is the only tool list** — append it to the prompt at runtime, drop the hand-written block (D5).
5. **Compiler**, minimal: shape → tool resolution → params → refs → output. Returns `{:ok, %Workflow{}} | {:error, [String.t()]}`. One test per error message.
6. **Designer bugs** D2–D4, response contract D6.
7. **Real `draft/1`** — model call via `Req`. Keep the known-good JSON as a fixture so compiler tests stay offline.
8. **UI: create form** (requirement + sample), `Server.start_design/2` on the same Task + notify + PubSub pattern, status line *Drafting… → Checking… → Testing… → Ready*, review shows extracted values, Save.
9. **Second demo.**

## Bugs

### Designer

- **D1. `test/karakuri/designer_test.exs` doesn't compile.** Calls `Designer.generate/1` (it's `/2`), `Karakuri.Workflows.compile/1` (doesn't exist) and `@sample` (undefined), and expects JSON back where `generate` returns a workflow. A compile error in a test file stops the whole suite.
- **D2. Attempt guard fires on every non-terminal status** (`designer.ex:22`). Terminals do match first (the old note said otherwise), but once `draft/1` counts attempts, the third draft sets `attempts: 3`, and the guard turns `:compiling` into `:failed` before that draft is ever compiled. Only `:drafting` should check it — or move it into `draft/1`, where an attempt is spent.
- **D3. `draft/1` never increments `attempts`.** Infinite loop once `compile` or `test` can route back to `:drafting`.
- **D4. Stub spec** uses the list ref form and `order: 0`. Follows from decision 1; `order` should go.
- **D5. `system_prompt.md` duplicates the catalog** and has drifted: different description, different example pattern (`\d+` vs `Total:\s*([0-9.,]+)`).
- **D6. Response contract.** Prompt shows a bare workflow for success; needs `{"status": "ok", "workflow": …}`. `suggested_tools` is missing.
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
