defmodule Delfos.Config.DiagnosticsTest do
  use ExUnit.Case, async: true
  @moduletag :postgres

  alias Delfos.Config.Diagnostics

  describe "run/0" do
    test "returns a list of check results" do
      results = Diagnostics.run()
      assert is_list(results)
      assert length(results) > 0
    end

    test "each result has required keys" do
      results = Diagnostics.run()

      Enum.each(results, fn r ->
        assert Map.has_key?(r, :status)
        assert Map.has_key?(r, :label)
        assert Map.has_key?(r, :detail)
        assert r.status in [:pass, :fail, :warn]
      end)
    end

    test "includes a config file check" do
      results = Diagnostics.run()
      config_check = Enum.find(results, &(&1.label == "Config file"))
      assert config_check != nil
    end

    test "includes an encryption key check" do
      results = Diagnostics.run()
      key_check = Enum.find(results, &(&1.label == "Encryption key"))
      assert key_check != nil
    end
  end

  describe "summary/0" do
    test "returns a string" do
      assert is_binary(Diagnostics.summary())
    end

    test "contains pass/fail/warn counts" do
      summary = Diagnostics.summary()
      assert summary =~ "passed"
      assert summary =~ "failed"
      assert summary =~ "warnings"
    end
  end
end
