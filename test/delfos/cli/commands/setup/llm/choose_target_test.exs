defmodule Delfos.CLI.Commands.Setup.LLM.ChooseTargetTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Delfos.CLI.Commands.Setup.LLM.ChooseTarget

  describe "choose/1" do
    test "returns the target provided in opts without prompting" do
      for target <- [:llm, :embedding, :both, :skip] do
        assert ChooseTarget.choose(target: target) == target
      end
    end
  end
end
