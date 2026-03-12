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

  test "grid distributes remainder rows evenly" do
    child = fn x -> BackBreeze.Box.new(style: %{border: :line}, content: x) end

    box =
      BackBreeze.Box.new(
        children: [child.("A"), child.("B"), child.("C")],
        style: %{border: :line, width: :screen},
        display: %BackBreeze.Grid{columns: 1, rows: 3}
      )

    %{dimensions: dimensions} =
      BackBreeze.Box.render_with_dimensions(box,
        terminal: %Termite.Terminal{size: %{width: 20, height: 12}}
      )

    heights = dimensions |> Enum.drop(1) |> Enum.map(& &1.height)
    assert heights == [4, 3, 3]
  end

  test "grid with explicit height uses it as total_height instead of screen height" do
    child = fn x -> BackBreeze.Box.new(style: %{border: :line}, content: x) end

    box =
      BackBreeze.Box.new(
        children: [child.("A"), child.("B"), child.("C")],
        style: %{border: :line, width: :screen, height: 9},
        display: %BackBreeze.Grid{columns: 1, rows: 3}
      )

    %{dimensions: dimensions} =
      BackBreeze.Box.render_with_dimensions(box,
        terminal: %Termite.Terminal{size: %{width: 20, height: 12}}
      )

    heights = dimensions |> Enum.drop(1) |> Enum.map(& &1.height)
    assert heights == [3, 3, 3]
  end

  test "grid fits explicit row heights back into the available height" do
    child = fn label, height ->
      BackBreeze.Box.new(style: %{border: :line, height: height}, content: label)
    end

    box =
      BackBreeze.Box.new(
        children: [child.("Top", 9), child.("Bottom", 7)],
        style: %{border: :line, width: :screen, height: 21},
        display: %BackBreeze.Grid{columns: 1, rows: 2}
      )

    %{dimensions: dimensions} =
      BackBreeze.Box.render_with_dimensions(box,
        terminal: %Termite.Terminal{size: %{width: 40, height: 24}}
      )

    heights = dimensions |> Enum.drop(1) |> Enum.map(& &1.height)
    assert heights == [11, 9]
  end

  test "grid assigns height to bordered children with absolute overlays" do
    panel =
      BackBreeze.Box.new(
        style: %{border: :rounded},
        children: [
          BackBreeze.Box.new(content: "Body", style: %{height: :full}),
          BackBreeze.Box.new(position: :absolute, left: 2, top: 0, content: "Title")
        ]
      )

    box =
      BackBreeze.Box.new(
        children: [panel],
        style: %{width: 20, height: 6},
        display: %BackBreeze.Grid{columns: 1, rows: 1}
      )

    rendered = BackBreeze.Box.render(box)

    assert rendered.content ==
             """
             ╭─Title────────────╮
             │Body              │
             │                  │
             │                  │
             │                  │
             ╰──────────────────╯\
             """
  end

  test "grid dimensions" do
    %{dimensions: dimensions} =
      BackBreeze.Box.render_with_dimensions(grid_box(),
        terminal: %Termite.Terminal{size: %{width: 53, height: 14}}
      )

    assert dimensions == [
             %{
               width: :screen,
               height: 14,
               content_height: 28,
               viewport_height: 12,
               viewport_width: :screen
             },
             %{height: 12, content_height: 3, viewport_height: 3},
             %{height: 12, content_height: 12, viewport_height: 12},
             %{height: 4, content_height: 1, viewport_height: 1},
             %{height: 4, content_height: 2, viewport_height: 2},
             %{height: 4, content_height: 1, viewport_height: 1},
             %{height: 12, content_height: 1, viewport_height: 1}
           ]
  end
end
