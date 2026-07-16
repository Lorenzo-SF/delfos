defmodule Delfos.CLI.Commands.Stadistics do
  @moduledoc """
  Shows local usage and knowledge-base statistics for registered projects.

  The command name intentionally follows the requested CLI spelling:
  `stadistics`.
  """

  import Ecto.Query

  alias Alaja
  alias Delfos.{Repo, Statistics}
  alias Delfos.Schema.Project

  @help """
  USAGE
      delfos stadistics
      delfos stadistics <project_name>
      delfos stadistics --list
      delfos stadistics --all

  ARGUMENTS
      project_name     Exact name of a registered project

  FLAGS
      --list           List registered project names
      --all            Show statistics for every registered project
      --help, -h       Show this help

  METRIC DEFINITIONS
      Tokens generated     Estimated from successful MCP response text at
                           four characters per token.
      Tokens saved         Estimated against loading the project's complete
                           indexed knowledge base for each successful call.
      Time saved           Derived from saved tokens at an explicit baseline
                           of 1,000 context tokens/second.

  PRIVACY
      Usage is stored only in Delfos' local database. Queries, arguments,
      source code, responses and error messages are never persisted.
  """

  def run([]), do: print_help()
  def run(["--help"]), do: print_help()
  def run(["-h"]), do: print_help()

  def run(args) when is_list(args) do
    {opts, positional, errors} =
      Alaja.CLI.OptionsParser.parse(args, %{
        switches: [list: :boolean, all: :boolean, help: :boolean],
        aliases: [h: :help],
        defaults: [list: false, all: false, help: false]
      })

    cond do
      errors != [] ->
        command_error(Enum.join(errors, "; "), :invalid_options)

      Keyword.get(opts, :help, false) ->
        print_help()

      length(positional) > 1 ->
        command_error("Only one project name may be provided.", :invalid_arguments)

      true ->
        run_with_opts(%{
          project: List.first(positional) || "",
          list: Keyword.get(opts, :list, false),
          all: Keyword.get(opts, :all, false)
        })
    end
  end

  @doc false
  def run_with_opts(opts) when is_map(opts) do
    project_name = opts |> Map.get(:project, "") |> normalize_project_name()
    list? = Map.get(opts, :list, false) == true
    all? = Map.get(opts, :all, false) == true

    cond do
      list? and all? ->
        command_error("--list and --all cannot be used together.", :invalid_arguments)

      project_name != "" and (list? or all?) ->
        command_error(
          "A project name cannot be combined with --list or --all.",
          :invalid_arguments
        )

      list? ->
        list_projects()

      all? ->
        show_all_projects()

      project_name == "" ->
        print_help()

      true ->
        show_project(project_name)
    end
  end

  defp print_help do
    Alaja.print_raw(@help)
    :ok
  end

  defp list_projects do
    projects = Repo.all(from(p in Project, order_by: [asc: p.name]))

    if projects == [] do
      Alaja.print_warning("No registered projects. Run: delfos init")
    else
      Alaja.print_raw("\nREGISTERED PROJECTS\n")

      Enum.each(projects, fn project ->
        Alaja.print_raw("  #{project.name}\n")
      end)

      Alaja.print_raw("\nUse: delfos stadistics <project_name>\n")
    end

    :ok
  end

  defp show_all_projects do
    projects = Repo.all(from(p in Project, order_by: [asc: p.name]))

    if projects == [] do
      Alaja.print_warning("No registered projects. Run: delfos init")
    else
      Enum.each(projects, &print_project/1)
    end

    :ok
  end

  defp show_project(project_name) do
    case Repo.get_by(Project, name: project_name) do
      nil ->
        command_error(
          "Unknown project '#{project_name}'. Use 'delfos stadistics --list' to see registered projects.",
          :unknown_project
        )

      project ->
        print_project(project)
        :ok
    end
  end

  defp print_project(project) do
    usage = Statistics.usage_snapshot(project.id)
    index = Statistics.index_snapshot(project)

    Alaja.print_raw("\n=== DELFOS PROJECT STADISTICS ===\n")
    Alaja.print_info("Project: #{project.name}")
    Alaja.print_raw("  Path: #{project.path}\n")
    Alaja.print_raw("  Stack: #{project.primary_stack || "unknown"}\n")

    Alaja.print_raw("\n  USAGE (LOCAL ONLY)\n")

    Alaja.print_raw(
      "    Tokens generated (estimated): #{format_integer(usage.response_tokens)}\n"
    )

    Alaja.print_raw("    Tokens saved (estimated):     #{format_integer(usage.saved_tokens)}\n")

    Alaja.print_raw(
      "    Time saved (estimated @ #{format_integer(Statistics.saved_time_baseline_tokens_per_second())} tokens/s): " <>
        "#{format_duration(usage.estimated_saved_time_ms)}\n"
    )

    Alaja.print_raw("    MCP calls processed:          #{format_integer(usage.total_calls)}\n")

    Alaja.print_raw(
      "      Success: #{usage.success_calls}  Errors: #{usage.error_calls}  " <>
        "Timeouts: #{usage.timeout_calls}  Success rate: #{format_percent(usage.success_rate)}\n"
    )

    Alaja.print_raw("    Last used:                    #{format_datetime(usage.last_used_at)}\n")

    Alaja.print_raw(
      "    Actual MCP latency:           total #{format_duration(usage.total_duration_ms)}, " <>
        "avg #{format_duration(round(usage.avg_duration_ms))}, " <>
        "max #{format_duration(usage.max_duration_ms)}\n"
    )

    print_tool_usage(usage.per_tool)

    Alaja.print_raw("\n  KNOWLEDGE BASE\n")

    Alaja.print_raw(
      "    Last updated:                 #{format_datetime(index.last_updated_at)}\n"
    )

    Alaja.print_raw(
      "    Files / LOC / source size:    #{format_integer(index.files)} / " <>
        "#{format_integer(index.lines_of_code)} / #{format_bytes(index.source_bytes)}\n"
    )

    Alaja.print_raw(
      "    Symbols / chunks / relations: #{format_integer(index.symbols)} / " <>
        "#{format_integer(index.chunks)} / #{format_integer(index.relationships)}\n"
    )

    Alaja.print_raw(
      "    Indexed context tokens:       #{format_integer(index.knowledge_base_tokens)}\n"
    )

    Alaja.print_raw(
      "    Embedding coverage:           #{format_integer(index.embedded_symbols)}/" <>
        "#{format_integer(index.symbols)} (#{format_percent(index.embedding_coverage)})\n"
    )

    Alaja.print_raw(
      "    Summary coverage:             #{format_integer(index.summarized_symbols)}/" <>
        "#{format_integer(index.symbols)} (#{format_percent(index.summary_coverage)})\n"
    )

    Alaja.print_raw("    Languages:                    #{format_languages(index.languages)}\n")
    Alaja.print_raw("    Files in dependency cycles:   #{format_integer(index.cycle_files)}\n")
    Alaja.print_raw("    TODOs detected:               #{format_integer(index.todos)}\n")
  end

  defp print_tool_usage(per_tool) when map_size(per_tool) == 0 do
    Alaja.print_raw("    Calls by tool:                none\n")
  end

  defp print_tool_usage(per_tool) do
    tools =
      per_tool
      |> Enum.sort_by(fn {tool, count} -> {-count, tool} end)
      |> Enum.map_join(", ", fn {tool, count} -> "#{tool}=#{count}" end)

    Alaja.print_raw("    Calls by tool:                #{tools}\n")
  end

  defp command_error(message, reason) do
    Alaja.print_error(message)
    {:error, reason}
  end

  defp normalize_project_name(nil), do: ""
  defp normalize_project_name(name), do: name |> to_string() |> String.trim()

  defp format_datetime(nil), do: "never"
  defp format_datetime(datetime), do: to_string(datetime)

  defp format_percent(value) when is_number(value), do: "#{Float.round(value * 1.0, 1)}%"
  defp format_percent(_value), do: "0.0%"

  defp format_languages([]), do: "none"

  defp format_languages(languages) do
    Enum.map_join(languages, ", ", fn {language, count} -> "#{language} (#{count})" end)
  end

  defp format_duration(milliseconds) when not is_number(milliseconds), do: "0 ms"

  defp format_duration(milliseconds) do
    milliseconds = max(round(milliseconds), 0)

    cond do
      milliseconds < 1_000 -> "#{milliseconds} ms"
      milliseconds < 60_000 -> "#{Float.round(milliseconds / 1_000, 1)} s"
      milliseconds < 3_600_000 -> "#{Float.round(milliseconds / 60_000, 1)} min"
      true -> "#{Float.round(milliseconds / 3_600_000, 1)} h"
    end
  end

  defp format_bytes(bytes) when not is_integer(bytes) or bytes <= 0, do: "0 B"
  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KiB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MiB"

  defp format_integer(value) when not is_integer(value), do: "0"

  defp format_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end
end
