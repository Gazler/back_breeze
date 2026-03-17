defmodule BackBreeze.RenderCacheTest do
  use ExUnit.Case, async: false

  alias BackBreeze.RenderCache

  setup do
    RenderCache.clear()
    :ok
  end

  test "resets the cache once it reaches the entry limit" do
    for idx <- 1..4_096 do
      assert RenderCache.fetch({:key, idx}, fn -> idx end) == idx
    end

    assert RenderCache.size() == 4_096
    assert RenderCache.fetch({:overflow, 1}, fn -> :ok end) == :ok
    assert RenderCache.size() == 1
  end

  test "reuses entries from the previous frame generation" do
    counter = :counters.new(1, [])

    assert RenderCache.with_frame(fn ->
             RenderCache.fetch(:stable, fn ->
               :counters.add(counter, 1, 1)
               :ok
             end)
           end) == :ok

    assert RenderCache.with_frame(fn ->
             RenderCache.fetch(:stable, fn ->
               :counters.add(counter, 1, 1)
               :ok
             end)
           end) == :ok

    assert :counters.get(counter, 1) == 1
  end

  test "drops entries that are older than the previous frame generation" do
    counter = :counters.new(1, [])

    assert RenderCache.with_frame(fn ->
             RenderCache.fetch(:stale, fn ->
               :counters.add(counter, 1, 1)
               :ok
             end)
           end) == :ok

    assert RenderCache.with_frame(fn -> :next end) == :next

    assert RenderCache.with_frame(fn ->
             RenderCache.fetch(:stale, fn ->
               :counters.add(counter, 1, 1)
               :ok
             end)
           end) == :ok

    assert :counters.get(counter, 1) == 2
  end
end
