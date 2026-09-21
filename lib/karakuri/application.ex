defmodule Karakuri.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Karakuri.Executor.TaskSupervisor},
      Karakuri.Server,
      KarakuriWeb.Telemetry,
      Karakuri.Repo,
      {DNSCluster, query: Application.get_env(:karakuri, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Karakuri.PubSub},
      # Start a worker by calling: Karakuri.Worker.start_link(arg)
      # {Karakuri.Worker, arg},
      # Start to serve requests, typically the last entry
      KarakuriWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Karakuri.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    KarakuriWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
