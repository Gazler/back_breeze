defmodule BackBreeze.Box.InlineLayoutTest do
  use ExUnit.Case, async: true
  alias BackBreeze.Box
  alias BackBreeze.Box.InlineLayout

  test "inline children reuse an unchanged inherited ANSI style" do
    row =
      Box.new(
        display: :inline,
        style: %{foreground_color: 7, background_color: 0},
        children: for(_ <- 1..10, do: Box.new(content: "row"))
      )

    parent = self()

    worker =
      spawn_link(fn ->
        receive do
          :render -> send(parent, {:inline_result, InlineLayout.child_result(row, structured: true)})
        end

        receive do: (:stop -> :ok)
      end)

    Code.ensure_loaded!(BackBreeze.Box.LayerMap)
    :erlang.trace_pattern({BackBreeze.Box.LayerMap, :content_style_sequence, 1}, true, [:local])
    :erlang.trace(worker, true, [:call])

    try do
      send(worker, :render)
      assert_receive {:inline_result, %{box: %{width: 30}}}, 1000
      delivery = :erlang.trace_delivered(worker)
      assert_receive {:trace_delivered, ^worker, ^delivery}
      assert_receive {:trace, ^worker, :call, {BackBreeze.Box.LayerMap, :content_style_sequence, _}}
      refute_receive {:trace, ^worker, :call, {BackBreeze.Box.LayerMap, :content_style_sequence, _}}, 0
    after
      :erlang.trace_pattern({BackBreeze.Box.LayerMap, :content_style_sequence, 1}, false, [:local])
      send(worker, :stop)
    end
  end

  test "nested single-line rows preserve all descendant dimensions and styled output" do
    for selected <- [false, true] do
      leaf = fn text, width -> Box.new(content: text, style: %{width: width}) end

      inner =
        Box.new(
          display: :inline,
          style: %{width: :full, overflow: :hidden},
          children: [leaf.("=", :auto), leaf.("Item 249", 22), leaf.("ready", :auto)]
        )

      item = Box.new(style: %{width: :full, overflow: :hidden, padding_left: 1}, children: [inner])

      row =
        Box.new(
          display: :inline,
          style: %{width: 32, foreground_color: 7, background_color: if(selected, do: 4, else: 0)},
          children: [
            if(selected, do: leaf.(">", 1), else: Box.new(style: %{width: 0, height: 0, overflow: :hidden})),
            item
          ]
        )

      expected = Box.render_structured_with_dimensions(row, defer_layers: true)
      actual = InlineLayout.child_result(row, structured: true)
      assert actual != nil
      assert actual.dimensions == expected.dimensions
      assert {actual.box.width, actual.box.height} == {expected.box.width, expected.box.height}

      assert Box.layer_maps_to_content(actual.box.layer_map, %{}, actual.box.width, actual.box.height) ==
               Box.layer_maps_to_content(expected.box.layer_map, %{}, expected.box.width, expected.box.height)
    end
  end

  test "complex rows fall back to ordinary layout" do
    for child <- [
          Box.new(content: "two\nlines"),
          Box.new(content: "界"),
          Box.new(content: "padding", style: %{padding: 1}),
          Box.new(content: "overlay", position: :absolute)
        ] do
      row = Box.new(display: :inline, style: %{width: 32}, children: [child])
      assert InlineLayout.child_result(row, structured: true) == nil
    end
  end
end
