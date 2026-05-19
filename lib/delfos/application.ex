defmodule Delfos.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Delfos.Repo,
      {Task.Supervisor, name: Delfos.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Delfos.Supervisor)
  end
end
