defmodule Delfos.CLI.Commands.Setup.WizardTest do
  @moduledoc """
  Unit tests for the Setup.Wizard helper.

  Exercises the three pieces the wrapper exposes to the setup
  subcommands:

    * `welcome/3` — header banner (no assertions needed; smoke-test)
    * `ask/3`     — numbered prompts with hints + defaults
    * `confirm_summary/1` — Box + yes/no confirmation
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Delfos.CLI.Commands.Setup.Wizard

  describe "welcome/3" do
    test "prints a Header banner" do
      output =
        capture_io(fn ->
          Wizard.welcome("LLM setup", "Provider / model / endpoints")
        end)

      assert output =~ "LLM setup"
      assert output =~ "Provider / model / endpoints"
    end
  end

  describe "ask/3 (free-form)" do
    test "returns {:ok, trimmed} when input is given" do
      output =
        capture_io("http://my-host:9999\n", fn ->
          assert {:ok, "http://my-host:9999"} = Wizard.ask("Ollama URL")
        end)

      assert output =~ "Ollama URL"
    end

    test "returns the default when input is empty" do
      capture_io("\n", fn ->
        assert {:ok, "http://localhost:11434"} =
                 Wizard.ask("Ollama URL", default: "http://localhost:11434")
      end)
    end

    test "returns :skip when input is empty and no default is given" do
      capture_io("\n", fn ->
        assert :skip == Wizard.ask("Optional field")
      end)
    end

    test "trims trailing slashes" do
      capture_io("http://x:9999/\n", fn ->
        assert {:ok, "http://x:9999"} = Wizard.ask("URL")
      end)
    end

    test "renders an indexed prefix when :index is given" do
      output =
        capture_io("\n", fn ->
          Wizard.ask("Pick a model", index: 3, default: "llama3")
        end)

      assert output =~ "3. Pick a model"
    end

    test "renders the hint beneath the prompt" do
      output =
        capture_io("\n", fn ->
          Wizard.ask("URL", hint: "Press Enter to accept the default")
        end)

      assert output =~ "Press Enter to accept the default"
    end
  end

  describe "ask/3 (choices)" do
    test "returns {:ok, choice} for a valid selection" do
      # Pipe the numeric selection ("1") followed by Enter.
      capture_io("1\n", fn ->
        assert {:ok, :llama_cpp} =
                 Wizard.ask(
                   "Engine",
                   choices: [
                     {"llama.cpp", :llama_cpp},
                     {"Ollama", :ollama},
                     {"External", :external}
                   ]
                 )
      end)
    end
  end

  describe "confirm_summary/1" do
    test "renders a Box with the pairs and asks yes/no" do
      output =
        capture_io("1\n", fn ->
          # CaptureIO sees the box output + the prompt + the user's
          # selection. We only need to assert the Box and the summary
          # text appeared.
          result =
            Wizard.confirm_summary([{"URL", "http://localhost:11434"}, {"Model", "llama3"}])

          assert result in [:yes, :no]
        end)

      assert output =~ "Confirm setup"
      assert output =~ "URL: http://localhost:11434"
      assert output =~ "Model: llama3"
    end
  end
end
