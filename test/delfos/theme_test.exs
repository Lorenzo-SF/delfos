defmodule Delfos.ThemeTest do
  @moduledoc """
  Unit tests for the user-customisable theme loader.

  Exercises:
    - Missing theme.json → empty map (callers fall back to Pote)
    - Valid theme.json with hex strings → parsed RGB tuples
    - Invalid file content → empty map (no crash)
    - color/1 falls back to Pote defaults for missing keys
    - Default cache: theme/0 returns the same map on repeat calls
  """

  use ExUnit.Case, async: false

  alias Delfos.Theme

  setup do
    # Each test gets its own config dir so theme.json doesn't bleed
    tmp =
      Path.join(
        System.tmp_dir!(),
        "delfos_theme_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    Application.put_env(:delfos, :config_dir, tmp)
    # Reset the in-process cache so theme/0 re-reads from the new dir.
    Process.delete({Theme, :theme})

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.delete_env(:delfos, :config_dir)
      Process.delete({Theme, :theme})
    end)

    %{tmp: tmp}
  end

  describe "theme/0" do
    test "returns empty map when no theme.json exists", %{tmp: _tmp} do
      assert Theme.theme() == %{}
    end

    test "parses a valid theme.json with hex strings", %{tmp: tmp} do
      File.write!(
        Path.join(tmp, "theme.json"),
        Jason.encode!(%{
          "primary" => "#FF0000",
          "warning" => "#00FF00"
        })
      )

      theme = Theme.theme()
      assert theme[:primary] == {255, 0, 0}
      assert theme[:warning] == {0, 255, 0}
    end

    test "ignores malformed theme.json", %{tmp: tmp} do
      File.write!(Path.join(tmp, "theme.json"), "this is not json")

      assert Theme.theme() == %{}
    end

    test "ignores unknown / malformed value formats", %{tmp: tmp} do
      File.write!(
        Path.join(tmp, "theme.json"),
        Jason.encode!(%{
          "primary" => 12345,
          "warning" => "not a colour"
        })
      )

      assert Theme.theme() == %{}
    end

    test "supports RGB array format", %{tmp: tmp} do
      File.write!(
        Path.join(tmp, "theme.json"),
        Jason.encode!(%{
          "primary" => [100, 150, 200]
        })
      )

      assert Theme.theme()[:primary] == {100, 150, 200}
    end

    test "supports RGB object form", %{tmp: tmp} do
      File.write!(
        Path.join(tmp, "theme.json"),
        Jason.encode!(%{
          "primary" => %{"r" => 50, "g" => 100, "b" => 150}
        })
      )

      assert Theme.theme()[:primary] == {50, 100, 150}
    end
  end

  describe "color/1" do
    test "returns the user override when present", %{tmp: tmp} do
      File.write!(Path.join(tmp, "theme.json"), Jason.encode!(%{"primary" => "#FF0000"}))

      assert Theme.color(:primary) == {255, 0, 0}
    end

    test "falls back to Pote default when key is missing from theme", %{tmp: _tmp} do
      assert Theme.color(:primary) == Pote.get_color(:primary)
    end

    test "falls back to Pote default when no theme.json exists at all", %{tmp: _tmp} do
      assert Theme.color(:secondary) == Pote.get_color(:secondary)
    end
  end

  describe "caching" do
    test "theme/0 returns the same map on repeat calls", %{tmp: tmp} do
      File.write!(Path.join(tmp, "theme.json"), Jason.encode!(%{"primary" => "#FF0000"}))

      first = Theme.theme()
      # Mutate the file — cached value should NOT change because the
      # process dict memoises.
      File.write!(Path.join(tmp, "theme.json"), Jason.encode!(%{"primary" => "#00FF00"}))
      second = Theme.theme()

      assert first == second
      assert first[:primary] == {255, 0, 0}
    end
  end
end
