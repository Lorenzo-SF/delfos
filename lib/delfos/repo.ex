defmodule Delfos.Repo do
  @moduledoc """
  Ecto.Repo for Delfos.

  Note: this module does NOT auto-start the Ecto adapter. The supervision
  tree starts `Delfos.RepoStarter` (a GenServer that knows how to spin
  up the repo on demand). Commands that need DB access should either:

    1. Wait for boot to finish — `Delfos.Application.start/2` schedules a
       task that calls `RepoStarter.start_repo/0` shortly after the
       supervisor comes up. By the time user commands run, the repo is
       usually running.
    2. Call `Delfos.RepoStarter.start_repo/0` explicitly before any query.
    3. Use the auto-initialized `Delfos.Repo` in `mix run` / iex sessions
       where you can manually start the repo.

  For releases, the auto-start task in `Application.start/2` is the
  canonical path: by the time `Delfos.CLI.main/1` dispatches a command,
  the repo has either started successfully or failed (and the user
  sees the failure surfaced through normal error channels).
  """

  use Ecto.Repo,
    otp_app: :delfos,
    adapter: Ecto.Adapters.Postgres
end
