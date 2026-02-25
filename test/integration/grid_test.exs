defmodule BackBreeze.Integration.GridTest do
  use ExUnit.Case, async: true

  defp grid_box() do
    child = fn x -> BackBreeze.Box.new(style: %{border: :line}, content: x) end

    children =
      [
        child.("Left\n123\n456"),
        BackBreeze.Box.new(
          style: %{border: :line},
          display: %BackBreeze.Grid{columns: 1},
          children: [child.("Top"), child.("Middle\n123"), child.("Bottom")]
        ),
        child.("Right")
      ]

    BackBreeze.Box.new(
      children: children,
      style: %{border: :line, width: :screen},
      display: %BackBreeze.Grid{columns: 3}
    )
  end

  test "rendering a grid" do
    box =
      BackBreeze.Box.render(grid_box(),
        terminal: %Termite.Terminal{size: %{width: 53, height: 14}}
      )

    assert box.content ==
             """
             ┌───────────────────────────────────────────────────┐
             │┌───────────────┐┌───────────────┐┌───────────────┐│
             ││Left           ││Top            ││Right          ││
             ││123            ││               ││               ││
             ││456            │└───────────────┘│               ││
             ││               │┌───────────────┐│               ││
             ││               ││Middle         ││               ││
             ││               ││123            ││               ││
             ││               │└───────────────┘│               ││
             ││               │┌───────────────┐│               ││
             ││               ││Bottom         ││               ││
             ││               ││               ││               ││
             │└───────────────┘└───────────────┘└───────────────┘│
             └───────────────────────────────────────────────────┘\
             """
  end

  test "grid dimensions" do
    %{dimensions: dimensions} =
      BackBreeze.Box.render_with_dimensions(grid_box(),
        terminal: %Termite.Terminal{size: %{width: 53, height: 14}}
      )

    assert dimensions == [
             %{height: 14, content_height: 20, viewport_height: 12},
             %{height: 12, content_height: 3, viewport_height: 3},
             %{height: 4, content_height: 1, viewport_height: 1},
             %{height: 4, content_height: 2, viewport_height: 2},
             %{height: 4, content_height: 1, viewport_height: 1},
             %{height: 12, content_height: 1, viewport_height: 1}
           ]
  end
end
