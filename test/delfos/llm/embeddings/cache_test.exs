defmodule Delfos.Embeddings.CacheTest do
  use ExUnit.Case, async: false

  alias Delfos.Embeddings.Cache

  setup do
    # Ensure a fresh table per test (the cache is a singleton).
    Cache.clear()

    # Reset persistent_term counters so assertions are isolated.
    for key <- [{Cache, :hits}, {Cache, :misses}, {Cache, :puts}, {Cache, :evictions}] do
      :persistent_term.erase(key)
    end

    :ok
  end

  describe "lookup/1 + put/2" do
    test "miss on empty cache" do
      assert Cache.lookup("hello") == :miss
    end

    test "hit after put" do
      vec = [1.0, 2.0, 3.0]
      assert Cache.put("hello", vec) == :ok
      assert Cache.lookup("hello") == {:ok, vec}
    end

    test "different texts are different keys" do
      Cache.put("a", [1.0])
      Cache.put("b", [2.0])
      assert Cache.lookup("a") == {:ok, [1.0]}
      assert Cache.lookup("b") == {:ok, [2.0]}
    end

    test "non-binary input is :miss" do
      assert Cache.lookup(nil) == :miss
      assert Cache.lookup(123) == :miss
    end
  end

  describe "fill_misses/1 + lookup_batch/1" do
    test "batch lookup with mixed hits and misses" do
      Cache.put("a", [1.0])
      Cache.put("c", [3.0])

      results = Cache.lookup_batch(["a", "b", "c", "d"])

      assert Enum.at(results, 0) == {:ok, [1.0]}
      assert Enum.at(results, 1) == :miss
      assert Enum.at(results, 2) == {:ok, [3.0]}
      assert Enum.at(results, 3) == :miss
    end

    test "fill_misses populates from (text, vec) pairs" do
      pairs = [{"x", [10.0]}, {"y", [20.0]}, {"z", nil}]
      assert Cache.fill_misses(pairs) == :ok

      assert Cache.lookup("x") == {:ok, [10.0]}
      assert Cache.lookup("y") == {:ok, [20.0]}
      # nil pairs are skipped
      assert Cache.lookup("z") == :miss
    end
  end

  describe "stats/0" do
    test "tracks hits, misses, puts" do
      Cache.put("a", [1.0])
      Cache.put("b", [2.0])
      Cache.lookup("a") # hit
      Cache.lookup("a") # hit
      Cache.lookup("z") # miss (not cached)

      stats = Cache.stats()
      assert stats.hits == 2
      assert stats.misses == 1
      assert stats.puts == 2
      assert stats.size == 2
    end
  end

  describe "clear/0" do
    test "removes all entries" do
      Cache.put("a", [1.0])
      Cache.put("b", [2.0])
      assert Cache.stats().size >= 2

      Cache.clear()
      assert Cache.stats().size == 0
      assert Cache.lookup("a") == :miss
    end
  end

  describe "enabled?/0" do
    test "respects :delfos, :embeddings_cache config" do
      original = Application.get_env(:delfos, :embeddings_cache, true)

      try do
        Application.put_env(:delfos, :embeddings_cache, false)
        assert Cache.enabled?() == false
        assert Cache.lookup("hello") == :miss
        # put is also a no-op when disabled
        Cache.put("hello", [1.0])
        assert Cache.lookup("hello") == :miss

        Application.put_env(:delfos, :embeddings_cache, true)
        assert Cache.enabled?() == true
      after
        Application.put_env(:delfos, :embeddings_cache, original)
      end
    end
  end
end
