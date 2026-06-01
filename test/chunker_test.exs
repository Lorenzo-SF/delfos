defmodule Delfos.Indexer.ChunkerTest do
  use ExUnit.Case, async: true

  alias Delfos.Indexer.Chunker

  @fid "00000000-0000-0000-0000-000000000001"
  @pid "00000000-0000-0000-0000-000000000002"

  test "genera un chunk para contenido pequeño" do
    content = "def hello, do: :world"
    chunks = Chunker.chunk_symbol(content, nil, @fid, @pid)
    assert length(chunks) == 1
    assert List.first(chunks).content == content
  end

  test "genera múltiples chunks para contenido grande" do
    content = String.duplicate("def func_#{:rand.uniform(999)}, do: :ok\n", 100)
    chunks = Chunker.chunk_symbol(content, nil, @fid, @pid)
    assert length(chunks) > 1
  end

  test "todos los chunks tienen file_id y project_id" do
    content = "def hello, do: :world"
    chunks = Chunker.chunk_symbol(content, nil, @fid, @pid)
    assert Enum.all?(chunks, fn c -> c.file_id == @fid and c.project_id == @pid end)
  end
end
