defmodule BackBreeze.ScrollbarTest do
  use ExUnit.Case, async: true

  test "scrollbars preserve deferred text and match cell-based rendering" do
    alias BackBreeze.Box.Scene
    scene = Scene.from_text_rows(List.duplicate(String.duplicate("x", 20), 10), "\e[40m", 0, 0)

    style =
      BackBreeze.Box.new(style: %{width: 20, height: 10, overflow: :hidden, scrollbar: true, background_color: 0}).style

    opts = %{
      style: style,
      scroll: {10, 0},
      content_height: 100,
      content_width: 20,
      max_x: 19,
      max_y: 9
    }

    expected = BackBreeze.Scrollbar.add_to_layer_map(Scene.materialize(scene), opts)
    result = BackBreeze.Scrollbar.add_to_layer_map(scene, opts)
    assert Scene.deferred?(result)
    assert Scene.materialize(result) == expected
  end

  test "proportional thumb sizing uses viewport size" do
    {scrollbar, _style} = BackBreeze.Scrollbar.normalize(true, %BackBreeze.Style{})

    assert BackBreeze.Scrollbar.thumb_size(scrollbar, 3, 5, 10) == 2
    assert BackBreeze.Scrollbar.thumb_size(scrollbar, 3, 3, 10) == 1
  end
end
