defmodule BackBreeze.Box.LayerMapTest do
  use ExUnit.Case, async: true

  alias BackBreeze.Box.LayerMap

  test "combined bounds match separate extent queries" do
    maps = [
      %{},
      %{{-7, -3} => {"x", ""}},
      %{{2, 3} => {"界", ""}, __wide_glyphs__: true},
      %{__default_fill__: [{{" ", ""}, -9, -8, -4, -2}]},
      %{{1, 6} => {"x", ""}, __default_fill__: [{{".", ""}, 0, 0, 3, 9}]}
    ]

    for map <- maps do
      assert LayerMap.bounds(map) == {LayerMap.max_x(map), LayerMap.max_y(map)}
    end
  end

  test "combined fullscreen bounds avoid two cell-map traversals" do
    map = for y <- 0..75, x <- 0..277, into: %{}, do: {{y, x}, {"x", ""}}

    cost = fn fun ->
      {:reductions, before} = Process.info(self(), :reductions)
      result = fun.()
      {:reductions, after_render} = Process.info(self(), :reductions)
      {result, after_render - before}
    end

    {{277, 75}, separate} = cost.(fn -> {LayerMap.max_x(map), LayerMap.max_y(map)} end)
    {{277, 75}, combined} = cost.(fn -> LayerMap.bounds(map) end)
    assert combined < separate * 0.75
  end

  test "fill merging does not test every cell against fills on other rows" do
    target = for y <- 0..75, x <- 0..277, into: %{}, do: {{y, x}, {"x", ""}}
    one = %{__default_fill__: [{{" ", "bg"}, 0, 0, 31, 75}]}
    rows = %{__default_fill__: for(y <- 0..75, do: {{" ", "bg"}, 0, y, 31, y})}

    cost = fn source ->
      {:reductions, before} = Process.info(self(), :reductions)
      merged = LayerMap.merge_map(target, source, {0, 0})
      {:reductions, after_render} = Process.info(self(), :reductions)
      {merged, after_render - before}
    end

    cost.(one)
    {single, single_cost} = cost.(one)
    {split, split_cost} = cost.(rows)
    assert Map.delete(split, :__default_fill__) == Map.delete(single, :__default_fill__)
    bounds = %{start_x: 0, start_y: 0, max_x: 277, max_y: 75}
    assert LayerMap.to_content(split, %{}, bounds) == LayerMap.to_content(single, %{}, bounds)
    assert split_cost < single_cost * 3
  end

  test "fill merging respects translated bounds, explicit cells, and background priority" do
    target = %{
      {0, 0} => {"A", ""},
      {1, 2} => {"B", ""},
      {2, 3} => {"C", ""},
      {3, 4} => {"D", ""},
      __default_fill__: [{{".", ""}, 0, 0, 4, 3}]
    }

    source = %{{1, 1} => {"X", ""}, __default_fill__: [{{"-", ""}, 0, 0, 1, 1}]}
    result = LayerMap.merge_map(target, source, {2, 1})
    assert result[{0, 0}] == {"A", ""}
    refute Map.has_key?(result, {1, 2})
    assert result[{2, 3}] == {"X", ""}
    assert result[{3, 4}] == {"D", ""}

    assert LayerMap.to_content(result, %{}, %{start_x: 0, start_y: 0, max_x: 4, max_y: 3}) ==
             "A....\n..--.\n..-X.\n....D"
  end

  test "a single unshifted fragment does not rebuild a fullscreen cell map" do
    map = for y <- 0..75, x <- 0..277, into: %{}, do: {{y, x}, {"x", ""}}
    LayerMap.compose_fragments([{map, 0, 0}])
    {:reductions, before} = Process.info(self(), :reductions)
    result = LayerMap.compose_fragments([{map, 0, 0}])
    {:reductions, after_render} = Process.info(self(), :reductions)
    assert result == map
    assert after_render - before < 1000
  end

  test "fragment composition matches translated maps, including fills and wide characters" do
    {first, _, _} = LayerMap.generate("\e[44m界 A\e[0m", %{}, 0, 0)
    second = %{{0, 0} => {"B", ""}, __default_fill__: [{{" ", "\e[41m"}, 0, 0, 5, 1}]}
    fragments = [{first, 2, 1}, {second, -1, 3}]
    bounds = %{start_x: 0, start_y: 1, max_x: 4, max_y: 3}

    expected =
      Enum.reduce(fragments, %{}, fn {map, x, y}, acc ->
        {cells, fills, wide?} = LayerMap.shift_simple_child(map, x, y)
        merged = Map.merge(acc, cells)

        merged
        |> LayerMap.put_default_fill_entries(fills ++ LayerMap.default_fill_entries(acc))
        |> LayerMap.mark_wide_glyph_metadata(wide? or LayerMap.has_wide_glyphs?(acc))
      end)

    assert LayerMap.compose_fragments(fragments) == expected
    assert LayerMap.compose_fragments(fragments, bounds) == LayerMap.filter(expected, bounds)

    assert LayerMap.to_content(LayerMap.compose_fragments(fragments, bounds), %{}, bounds) ==
             LayerMap.to_content(LayerMap.filter(expected, bounds), %{}, bounds)
  end

  test "fragment composition preserves last cell and fill priority and empty clips" do
    a = %{{0, 0} => {"A", ""}, __default_fill__: [{{".", ""}, 0, 0, 3, 0}]}
    b = %{{0, 0} => {"B", ""}, __default_fill__: [{{"-", ""}, 0, 0, 3, 0}]}
    result = LayerMap.compose_fragments([{a, 0, 0}, {b, 0, 0}])
    assert LayerMap.to_content(result, %{}, %{start_x: 0, start_y: 0, max_x: 3, max_y: 0}) == "B---"
    assert LayerMap.compose_fragments([{a, 0, 0}], %{start_x: 9, start_y: 9, max_x: 10, max_y: 10}) == %{}
    assert LayerMap.compose_fragments([]) == %{}
  end

  test "dense rendering preserves overlapping fill priority and explicit overlay cells" do
    base = %{__default_fill__: [{{"a", ""}, 1, 0, 2, 1}, {{"b", ""}, 0, 0, 3, 2}]}
    overlay = %{{1, 1} => {"X", ""}, __default_fill__: [{{"c", ""}, 2, 1, 3, 2}]}
    bounds = %{start_x: 0, start_y: 0, max_x: 3, max_y: 2}
    assert LayerMap.to_content(base, overlay, bounds) == "baab\nbXcc\nbbcc"
  end

  test "dense rendering does not rescan off-row fills for every cell" do
    bounds = %{start_x: 0, start_y: 0, max_x: 79, max_y: 19}
    fill = {{" ", ""}, 0, 0, 79, 19}
    off_row = for y <- 20..219, do: {{"x", ""}, 0, y, 79, y}
    baseline = %{__default_fill__: [fill]}
    crowded = %{__default_fill__: off_row ++ [fill]}
    LayerMap.to_content(baseline, %{}, bounds)
    {expected, baseline_cost} = rendering_cost(baseline, bounds)
    {actual, crowded_cost} = rendering_cost(crowded, bounds)
    assert actual == expected
    assert crowded_cost < baseline_cost * 3
  end

  defp rendering_cost(map, bounds) do
    {:reductions, before} = Process.info(self(), :reductions)
    content = LayerMap.to_content(map, %{}, bounds)
    {:reductions, after_render} = Process.info(self(), :reductions)
    {content, after_render - before}
  end

  test "merges a metadata-only base without rebuilding source cells" do
    base = %{
      __default_fill__: [{{" ", "base"}, 0, 0, 3, 0}]
    }

    source = %{
      {0, 0} => {"A", "text"},
      __default_fill__: [{{" ", "source"}, 0, 0, 0, 0}]
    }

    assert {:ok, merged} = LayerMap.merge_metadata_base(base, source)
    assert merged[{0, 0}] == {"A", "text"}

    assert merged.__default_fill__ == [
             {{" ", "source"}, 0, 0, 0, 0},
             {{" ", "base"}, 0, 0, 3, 0}
           ]
  end

  test "drops transparent source spaces so they reveal the base fill" do
    base = %{__default_fill__: [{{" ", "base"}, 0, 0, 3, 0}]}
    source = %{{0, 0} => {" ", ""}}

    assert {:ok, merged} = LayerMap.merge_metadata_base(base, source)
    refute Map.has_key?(merged, {0, 0})
    assert merged.__default_fill__ == [{{" ", "base"}, 0, 0, 3, 0}]
  end

  test "falls back when the base contains explicit cells" do
    base = %{{0, 0} => {"B", "base"}}
    source = %{{0, 0} => {"A", "text"}}

    assert :error = LayerMap.merge_metadata_base(base, source)
  end

  test "merges maps without calculating bounds" do
    base = %{{0, 0} => {"B", "base"}}
    source = %{{0, 0} => {"A", "text"}, {1, 2} => {"C", "text"}}

    assert LayerMap.merge_map(base, source, {1, 1}) ==
             source
             |> Enum.map(fn {{y, x}, value} -> {{y + 1, x + 1}, value} end)
             |> Map.new()
             |> Map.put({0, 0}, {"B", "base"})
  end
end
