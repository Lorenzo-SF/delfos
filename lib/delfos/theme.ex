defmodule Delfos.Theme do
  @moduledoc """
  User-customisable colour theme for Delfos CLI output.

  Loads `~/.config/delfos/theme.json` on boot and merges it with
  Pote's built-in palette. Components like `Alaja.Components.Box`,
  `AnimatedBar`, `Bar`, `Json` use the resolved colours instead of
  the hard-coded RGB tuples scattered through the code.

  ## Theme file format

      {
        "primary":   "#A1E7FA",
        "secondary": "#3AABA3",
        "success":   "#97C53C",
        "warning":   "#FDD808",
        "error":     "#FF5B5B",
        "info":      "#00FFFF",
        "muted":     "#808080",
        "embed_ok":   "#00C850",
        "embed_warn": "#D4B400",
        "embed_bad":  "#DC3232"
      }

  Each key is optional — missing keys fall back to Pote's defaults.
  Values may be:
    * `"#RRGGBB"` — hex colour (Pote parses it)
    * `"#RGB"` — short hex
    * `"red"` / `"blue"` / etc. — CSS color names (Pote parses it)
    * `"theme:primary"` — reference to another theme key
    * `{"r": 161, "g": 231, "b": 250}` — raw RGB tuple
    * `[161, 231, 250]` — array form

  ## Why this module

  Pre-v2.6.0 the colour palette was hard-coded in 9 different
  components (Box border, AnimatedBar filled, status freshness,
  message hints, etc). Changing the brand colour meant patching
  each call site. After v2.5.0 the call sites use this module,
  which delegates to Pote.

  ## Per-component usage

  Most components take their colours as opts (e.g.
  `Box.print(content, border_color: theme().primary)`). When the
  user has a custom theme, the helper functions below resolve the
  right RGB tuple.
  """

  @doc """
  Returns the resolved theme map. Looks up the user's
  `~/.config/delfos/theme.json` and merges it on top of Pote's
  defaults. Falls back to pure Pote defaults if no theme file
  exists or it's unreadable.

  The result is cached in a process dictionary so the file is
  read at most once per process (the typical CLI lifetime is one
  command, so the cache effectively never hits).
  """
  @spec theme() :: map()
  def theme do
    case Process.get({__MODULE__, :theme}) do
      nil ->
        resolved = load()
        Process.put({__MODULE__, :theme}, resolved)
        resolved

      cached ->
        cached
    end
  end

  @doc """
  Convenience accessor: returns the RGB tuple for a theme key,
  or falls back to Pote's default if the user didn't override it.
  """
  @spec color(atom()) :: {integer(), integer(), integer()} | nil
  def color(key) do
    Map.get(theme(), key) || Pote.get_color(key)
  end

  @doc """
  Returns the path to the user's theme file (if it exists).
  Empty list `[]` when there's no customisation.
  """
  @spec user_overrides() :: [{atom(), {integer(), integer(), integer()}}]
  def user_overrides do
    theme()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  # Reads + parses the theme file. Returns a flat atom-keyed map of
  # {r, g, b} tuples. Missing or malformed file → empty map (caller
  # falls back to Pote defaults).
  defp load do
    path = theme_file_path()

    with true <- File.exists?(path),
         {:ok, content} <- File.read(path),
         {:ok, parsed} <- safe_decode(content) do
      Map.new(parsed, fn {k, v} -> {safe_atom(k), parse_value(v)} end)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    else
      _ -> %{}
    end
  end

  @doc false
  def theme_file_path do
    config_dir = Application.get_env(:delfos, :config_dir) || default_config_dir()
    Path.join(config_dir, "theme.json")
  end

  defp default_config_dir do
    case System.get_env("XDG_CONFIG_HOME") do
      nil -> Path.join(System.get_env("HOME") || "/tmp", ".config/delfos")
      dir -> Path.join(dir, "delfos")
    end
  end

  defp safe_decode(content) do
    Jason.decode(content)
  rescue
    _ -> {:error, :decode_failed}
  end

  defp safe_atom(key) when is_atom(key), do: key

  defp safe_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> :"#{key}"
      _ -> :"#{key}"
    end
  end

  defp safe_atom(_), do: nil

  # Accept all the value formats documented in the moduledoc.
  # Returns nil for unparseable values so they get filtered out.
  defp parse_value(value) when is_map(value) do
    # Convert the JSON-decoded map (%{"r" => 255, "g" => 0, "b" => 0}
    # or %{r: 255, g: 0, b: 0}) to the "rgb:R,G,B" string Pote expects.
    r = Map.get(value, "r", Map.get(value, :r))
    g = Map.get(value, "g", Map.get(value, :g))
    b = Map.get(value, "b", Map.get(value, :b))

    parse_value("rgb:#{r},#{g},#{b}")
  end

  defp parse_value(value) when is_list(value) and length(value) == 3 do
    [r, g, b] = value
    parse_value("rgb:#{r},#{g},#{b}")
  end

  defp parse_value(value) when is_binary(value) do
    case Pote.Orchestrator.parse_color(value) do
      {:ok, rgb} -> rgb
      _ -> nil
    end
  end

  defp parse_value(_), do: nil

  @doc """
  Returns the canonical/default theme map. Use this for tests or
  for rendering components when you want zero user customisation.
  """
  @spec defaults() :: map()
  def defaults do
    %{
      primary: Pote.get_color(:primary),
      secondary: Pote.get_color(:secondary),
      success: Pote.get_color(:success),
      warning: Pote.get_color(:warning),
      error: Pote.get_color(:error),
      info: Pote.get_color(:info),
      muted: {128, 128, 128},
      embed_ok: {0, 200, 80},
      embed_warn: {220, 180, 0},
      embed_bad: {220, 50, 50}
    }
  end
end
