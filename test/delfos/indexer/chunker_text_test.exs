defmodule Delfos.Indexer.ChunkerTextTest do
  use ExUnit.Case, async: true

  alias Delfos.Indexer.Chunker

  describe "chunk_text/2 (iter-051 public API)" do
    test "chunks short text into one chunk" do
      text = "defmodule Foo do\nend"

      chunks = Chunker.chunk_text(text, max_tokens: 100)

      assert length(chunks) == 1
      assert hd(chunks).text == text
      assert hd(chunks).line_start == 1
    end

    test "chunks long text into multiple chunks" do
      # 200 lines of 100 chars = 20000 chars ≈ 5000 tokens.
      long_text = Enum.map_join(1..200, "\n", fn i -> String.duplicate("a", 100) <> " line #{i}" end)

      chunks = Chunker.chunk_text(long_text, max_tokens: 50)

      assert length(chunks) > 1
      Enum.each(chunks, fn chunk ->
        assert is_binary(chunk.text)
        assert is_integer(chunk.line_start)
        assert is_integer(chunk.line_end)
      end)
    end

    test "accepts empty content without crashing" do
      chunks = Chunker.chunk_text("", max_tokens: 100)
      assert chunks == [] or length(chunks) == 1
    end

    test "uses default max_tokens when not specified" do
      # Should not raise.
      _ = Chunker.chunk_text("hello world")
      assert true
    end
  end
end
