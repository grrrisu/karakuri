# Karakuri

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Environment variables

Local env vars are loaded with [Dotenvy](https://hexdocs.pm/dotenvy) in `config/runtime.exs`, from these sources in order (later wins):

1. `.env`
2. `.env.<env>` (e.g. `.env.dev`, `.env.test`)
3. Real shell environment

Create a `.env.dev` in the project root (it is git-ignored):

```sh
ANTHROPIC_API_KEY=sk-ant-...
MOCK_AGENT=true
```

| Variable            | Required | Description                         |
| ------------------- | -------- | ----------------------------------- |
| `ANTHROPIC_API_KEY` | Yes, unless `MOCK_AGENT` is set | Anthropic API key used by ReqLLM/Jido AI for the designer agent |
| `MOCK_AGENT`        | No       | When set to any value, uses `Karakuri.Designer.Agent.MockAgent` instead of `Karakuri.Designer.Agent`. Remove the line (don't set it to `false`) to use the real agent |

Values from `.env` files are mapped into application config, not the OS environment, so `System.get_env/1` returns `nil` for them. To check values from IEx:

```elixir
Application.get_env(:req_llm, :anthropic_api_key)
Application.get_env(:karakuri, :designer_agent_module)
```

Restart the server after changing a `.env` file.

In production, set `ANTHROPIC_API_KEY` in the real environment.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
