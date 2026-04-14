defmodule BackBreeze.RenderCacheTest do
  use ExUnit.Case, async: false

  alias BackBreeze.Box
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

  test "dynamic rendered content is cached but stays bounded by the memory cap" do
    for idx <- 1..200 do
      content = String.duplicate("x", idx)
      box = Box.new(content: content, style: %{padding_left: 1})
      %{box: rendered} = Box.render_with_dimensions(box)
      assert rendered.content =~ content
    end

    stable_keys =
      :ets.tab2list(:back_breeze_render_cache)
      |> Enum.map(&elem(&1, 0))
      |> Enum.filter(fn
        {:stable, {:render_self, _, _, _, _}} -> true
        {:stable, {:generate_layer_map, _}} -> true
        {:stable, {:layer_maps_to_content, _, _, _}} -> true
        _ -> false
      end)

    assert stable_keys != []
    assert :ets.info(:back_breeze_render_cache, :memory) < 8_000_000
  end

  test "resets the cache once it reaches the memory limit" do
    large = Enum.map(1..200_000, fn idx -> {idx, Integer.to_string(idx)} end)

    Enum.each(1..10, fn idx ->
      assert RenderCache.fetch_stable({:large, idx}, fn -> large end) == large
    end)

    assert RenderCache.size() < 10
  end
end
