%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/"], excluded: []},
      strict: false,
      color: true,
      checks: %{
        disabled: [
          {Credo.Check.Refactor.LongQuoteBlocks, []},
        ]
      }
    }
  ]
}
