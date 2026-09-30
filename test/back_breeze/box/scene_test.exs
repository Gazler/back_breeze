defmodule BackBreeze.Box.SceneTest do
  use ExUnit.Case, async: true
  alias BackBreeze.Box.{LayerMap, Scene}

  test "stacked scene fragments need only linear overlap checks" do
    owner = self()
    fragments = for y <- 0..75, do: {Scene.from_text_rows(["row"], "\e[31m", 0, 0), 0, y}

    worker =
      spawn_link(fn ->
        receive do
          :compose -> send(owner, {:composed, Scene.compose(fragments, nil)})
        end

        receive do: (:stop -> :ok)
      end)

    :erlang.trace_pattern({Scene, :overlap?, 2}, true, [:local])
    :erlang.trace(worker, true, [:call])

    try do
      send(worker, :compose)
      assert_receive {:composed, scene}, 1000
      assert Scene.deferred?(scene)
      delivered = :erlang.trace_delivered(worker)
      assert_receive {:trace_delivered, ^worker, ^delivered}
      assert overlap_calls(worker, 0) <= 76
    after
      :erlang.trace_pattern({Scene, :overlap?, 2}, false, [:local])
      send(worker, :stop)
    end
  end

  defp overlap_calls(worker, count) do
    receive do
      {:trace, ^worker, :call, {Scene, :overlap?, _}} -> overlap_calls(worker, count + 1)
    after
      0 -> count
    end
  end

  test "fragments inside the envelope still distinguish gaps from overlaps" do
    row = Scene.from_text_rows(["row"], "\e[31m", 0, 0)
    assert Scene.deferred?(Scene.compose([{row, 0, 0}, {row, 0, 2}, {row, 0, 1}], nil))
    refute Scene.deferred?(Scene.compose([{row, 0, 0}, {row, 0, 2}, {row, 0, 2}], nil))
  end

  test "simple label layout matches the full renderer" do
    alias BackBreeze.Box

    for width <- [:auto, 22], height <- [0, 1, :auto], overflow <- [:auto, :hidden] do
      box =
        Box.new(
          content: "label",
          style: %{
            width: width,
            height: height,
            overflow: overflow,
            foreground_color: 7,
            background_color: 0,
            bold: true
          }
        )

      expected = Box.render_structured_with_dimensions(box)
      actual = BackBreeze.Box.LayoutOnly.child_result(box, structured: true)
      assert actual != nil
      assert actual.dimensions == expected.dimensions
      assert actual.box.content == expected.box.content
      assert {actual.box.width, actual.box.height} == {expected.box.width, expected.box.height}
    end
  end

  test "structured inline rows compose child layers without an ANSI round trip" do
    alias BackBreeze.Box

    box =
      Box.new(
        display: :inline,
        style: %{background_color: 0},
        children: [
          Box.new(content: "name", style: %{width: 22}),
          Box.new(content: "stopped", style: %{foreground_color: 2})
        ]
      )

    regular = Box.render_with_dimensions(box)
    %{box: deferred, dimensions: dimensions} = Box.render_structured_with_dimensions(box, defer_layers: true)
    assert Scene.deferred?(deferred.layer_map)
    assert {deferred.width, deferred.height} == {regular.box.width, regular.box.height}
    assert dimensions == regular.dimensions

    assert Scene.to_content(deferred.layer_map, %{
             start_x: 0,
             start_y: 0,
             max_x: deferred.width - 1,
             max_y: deferred.height - 1
           }) == regular.box.content

    assert String.replace(regular.box.content, ~r/\e\[[0-9;]*m/, "") == "name                  stopped"
  end

  test "large empty spacers remain compact until clipped" do
    alias BackBreeze.Box
    box = Box.new(content: "", style: %{width: 32, height: 180, background_color: 0})
    %{box: deferred} = Box.render_structured_with_dimensions(box, defer_layers: true)
    assert %{__scene__: _} = deferred.layer_map

    assert Scene.to_content(deferred.layer_map, %{start_x: 0, start_y: 0, max_x: 31, max_y: 179}) ==
             BackBreeze.Style.render(box.style, box.content)
  end

  test "content-only rendering preserves output and dimensions without exporting cell maps" do
    alias BackBreeze.Box

    box =
      Box.new(
        content: String.duplicate(String.duplicate("x", 78) <> "\n", 20),
        style: %{width: 80, height: 24, foreground_color: 7, border: :line}
      )

    box = Box.new(children: [box], style: %{width: 80, height: 24, background_color: 0})
    regular = Box.render_with_dimensions(box)
    compact = Box.render_content_with_dimensions(box)
    assert compact.dimensions == regular.dimensions
    assert compact.box.content == regular.box.content
    assert {compact.box.width, compact.box.height} == {regular.box.width, regular.box.height}
    assert compact.box.layer_map == %{}
    assert compact.box.fixed_layer_map == %{}
    assert compact.box.children == []
    assert Box.render_with_dimensions(box) == regular
  end

  test "styled text rows remain deferred when clipped" do
    rows = [[{"hello", "red"}, {" world", "blue"}], [{"second row ", "green"}]]
    scene = Scene.from_styled_rows(rows, 2, 3)

    expected =
      LayerMap.generate("\e[31mhello\e[0m\e[34m world\e[0m\n\e[32msecond row \e[0m", %{}, 2, 3)
      |> elem(0)

    ansi =
      Scene.from_styled_rows(
        [[{"hello", "\e[31m"}, {" world", "\e[34m"}], [{"second row ", "\e[32m"}]],
        2,
        3
      )

    assert Scene.materialize(ansi) == expected
    bounds = %{start_x: 4, start_y: 3, max_x: 9, max_y: 4}
    clipped = Scene.clip(scene, bounds)
    assert Scene.deferred?(clipped)
    assert Scene.materialize(clipped) == LayerMap.filter(Scene.materialize(scene), bounds)

    assert Scene.to_content(clipped, bounds) ==
             LayerMap.to_content(Scene.materialize(scene), %{}, bounds)
  end

  test "text cells share identical styled values in the public map" do
    map = Scene.from_text_rows([String.duplicate("x", 1000)], "fg", 0, 0) |> Scene.materialize()
    values = for x <- 0..999, do: Map.fetch!(map, {0, x})
    assert Enum.uniq(values) == [{"x", "fg"}]
    assert :erts_debug.size(values) < 3000
  end

  test "text painting ignores fill intervals outside the text columns" do
    rows = List.duplicate(String.duplicate("x", 240), 72)
    base = Scene.from_text_rows(rows, "fg", 36, 1)
    outside = Scene.merge(base, %{__default_fill__: [{{" ", "bg"}, 0, 0, 33, 75}]}, {0, 0})

    cost = fn scene ->
      {:reductions, before} = Process.info(self(), :reductions)
      result = Scene.materialize(scene)
      {:reductions, after_render} = Process.info(self(), :reductions)
      {result, after_render - before}
    end

    cost.(base)
    # Collection reductions vary with test order; use the least interrupted
    # sample to compare the actual painting work rather than GC scheduling.
    {plain, plain_cost} = Enum.min_by(for(_ <- 1..5, do: cost.(base)), &elem(&1, 1))
    {filled, filled_cost} = Enum.min_by(for(_ <- 1..5, do: cost.(outside)), &elem(&1, 1))
    assert Map.delete(filled, :__default_fill__) == plain
    assert filled_cost < plain_cost * 1.2
  end

  test "large plain styled text retains row binaries through layout" do
    alias BackBreeze.Box
    text = Enum.map_join(1..20, "\n", fn _ -> String.duplicate("x", 78) end)

    box =
      Box.new(content: text, style: %{width: 80, height: 22, border: :line, foreground_color: 7})

    %{box: deferred} = Box.render_structured_with_dimensions(box, defer_layers: true)
    assert %{__scene__: layers} = deferred.layer_map
    assert Enum.any?(layers, fn {map, _, _, _} -> Map.has_key?(map, :__text_rows__) end)
    rendered = Box.render(box)

    assert LayerMap.to_content(deferred.layer_map, deferred.width, deferred.height) ==
             rendered.content
  end

  test "text rows remain compact until painting and respect later fills" do
    rows = ["hello world", "second row "]
    scene = Scene.from_text_rows(rows, "color", 2, 3)
    assert Scene.deferred?(scene)
    assert LayerMap.bounds(scene) == {12, 4}

    expected =
      for {row, y} <- Enum.with_index(rows, 3),
          {char, x} <- Enum.with_index(String.graphemes(row), 2),
          into: %{},
          do: {{y, x}, {char, "color"}}

    assert Scene.materialize(scene) == expected
    overlay = %{__default_fill__: [{{".", "bg"}, 5, 3, 8, 4}]}

    assert Scene.materialize(Scene.merge(scene, overlay, {0, 0})) ==
             LayerMap.merge_map(expected, overlay, {0, 0})
  end

  test "translated overlapping layers agree with eager composition" do
    for seed <- 1..30 do
      {eager, deferred} =
        Enum.reduce(0..12, {%{}, %{}}, fn n, {eager, deferred} ->
          x = rem(seed * 7 + n * 3, 17) - 5
          y = rem(seed * 3 + n * 7, 11) - 4

          map = %{
            {0, 0} => {"A", "color"},
            {1, 2} => {"B", "color"},
            __default_fill__: [{{".", "bg#{n}"}, 0, 0, rem(n, 4) + 2, rem(n, 3) + 1}]
          }

          {LayerMap.merge_map(eager, map, {x, y}), LayerMap.merge_map(Scene.wrap(deferred), Scene.wrap(map), {x, y})}
        end)

      assert Scene.materialize(deferred) == eager
      bounds = %{start_x: 0, start_y: 0, max_x: 15, max_y: 9}
      assert LayerMap.to_content(deferred, %{}, bounds) == LayerMap.to_content(eager, %{}, bounds)
      assert Scene.to_content(deferred, bounds) == LayerMap.to_content(eager, %{}, bounds)
    end
  end

  test "final paint does not rescan the full screen for each row background" do
    base = for y <- 0..75, x <- 0..277, into: %{}, do: {{y, x}, {"x", "color"}}
    base = Scene.wrap(base)
    single = LayerMap.merge_map(base, %{__default_fill__: [{{".", "bg"}, 0, 0, 31, 75}]}, {0, 0})

    rows =
      Enum.reduce(0..75, base, fn y, acc ->
        LayerMap.merge_map(acc, %{__default_fill__: [{{".", "bg"}, 0, 0, 31, 0}]}, {0, y})
      end)

    cost = fn scene ->
      {:reductions, before} = Process.info(self(), :reductions)
      map = Scene.materialize(scene)
      {:reductions, after_paint} = Process.info(self(), :reductions)
      {map, after_paint - before}
    end

    {one_map, one_cost} = cost.(single)
    {row_map, row_cost} = cost.(rows)
    assert Map.delete(one_map, :__default_fill__) == Map.delete(row_map, :__default_fill__)
    assert row_cost < one_cost * 3
  end

  test "public renders retain plain layer maps and matching dimensions" do
    alias BackBreeze.Box
    text = Enum.map_join(1..20, "\n", fn _ -> String.duplicate("x", 78) end)
    leaf = Box.new(content: text, style: %{foreground_color: 2})

    box =
      Enum.reduce(1..3, leaf, fn _, child ->
        Box.new(children: [child], style: %{border: :line, padding: 1})
      end)

    %{box: rendered, dimensions: dims} = Box.render_with_dimensions(box)
    %{box: structured, dimensions: structured_dims} = Box.render_structured_with_dimensions(box)
    refute Scene.deferred?(rendered.layer_map)
    refute Scene.deferred?(structured.layer_map)
    assert dims == structured_dims

    assert rendered.content ==
             Box.layer_map_to_content(structured.layer_map, structured.width, structured.height)
  end

  test "nested translation and composition retain leaf maps until materialization" do
    leaf = %{{0, 0} => {"A", "color"}, {1, 2} => {"B", "color"}}
    scene = leaf |> Scene.wrap() |> LayerMap.shift(3, 2) |> LayerMap.shift(4, 5)
    assert Scene.deferred?(scene)
    assert Scene.materialize(scene) == LayerMap.shift(leaf, 7, 7)
    assert LayerMap.bounds(scene) == {9, 8}
  end

  test "deferred backgrounds, borders and overlapping fills match eager merging" do
    base = %{{0, 0} => {"B", "color"}, __default_fill__: [{{".", "bg"}, 0, 0, 5, 3}]}
    child = %{{0, 0} => {"C", "color"}, __default_fill__: [{{"-", "child"}, 0, 0, 2, 1}]}
    overlay = %{{0, 0} => {"X", "color"}, __default_fill__: [{{"=", "overlay"}, 0, 0, 1, 0}]}
    expected = base |> LayerMap.merge_map(child, {1, 1}) |> LayerMap.merge_map(overlay, {2, 2})

    actual =
      base
      |> Scene.wrap()
      |> LayerMap.merge_map(Scene.wrap(child), {1, 1})
      |> LayerMap.merge_map(overlay, {2, 2})

    assert Scene.deferred?(actual)
    assert Scene.materialize(actual) == expected
  end

  test "clipping, transparent spaces and wide glyphs preserve existing semantics" do
    base = %{{0, 0} => {"A", "color"}, {0, 1} => {"B", "color"}, {0, 2} => {"C", "color"}}
    {wide, _, _} = LayerMap.generate("界", %{}, 0, 0)

    for source <- [%{{0, 0} => {" ", ""}}, wide] do
      actual = LayerMap.merge_map(Scene.wrap(base), source, {0, 0})
      assert Scene.materialize(actual) == LayerMap.merge_map(base, source, {0, 0})
    end

    bounds = %{start_x: 1, start_y: 0, max_x: 1, max_y: 0}

    assert Scene.materialize(LayerMap.filter(Scene.wrap(base), bounds)) ==
             LayerMap.filter(base, bounds)
  end
end
