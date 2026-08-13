%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "src/", "test/"],
        excluded: []
      },
      plugins: [],
      checks: %{
        enabled: [
          {Credo.Check.Refactor.Apply, []}
        ],
        disabled: [
          # Allow nested module references like Req.post, Candil.chat/4
          # without requiring top-of-module aliases. Aliases clutter
          # call sites for widely-used modules.
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []}
        ]
      }
    }
  ]
}
