defmodule BackBreeze.Integration.GridCacheTest do
  use ExUnit.Case, async: false

  alias BackBreeze.Box
  alias BackBreeze.Grid
  alias BackBreeze.RenderCache

  setup do
    RenderCache.clear()
    :ok
  end

  test "grid child renders are cached per terminal size" do
    child =
      Box.new(
        children: [
          Box.new(content: "X", style: %{border: :line, width: :screen})
        ]
      )

    box =
      Box.new(
        children: [child],
        style: %{width: 10},
        display: %Grid{columns: 1}
      )

    small =
      Box.render(box, terminal: %Termite.Terminal{size: %{width: 12, height: 8}})

    large =
      Box.render(box, terminal: %Termite.Terminal{size: %{width: 16, height: 8}})

    assert small.content ==
             """
             ┌──────────┐
             │X         │
             └──────────┘\
             """

    assert large.content ==
             """
             ┌──────────────┐
             │X             │
             └──────────────┘\
             """
  end
end
