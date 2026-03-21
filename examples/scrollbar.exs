render = fn title, box ->
  IO.puts("\n#{title}")
  IO.puts(String.duplicate("=", String.length(title)))
  IO.puts(box |> BackBreeze.Box.render() |> Map.get(:content))
end

vertical_content =
  Enum.map_join(1..14, "\n", fn row ->
    "Row #{row}: Lorem ipsum"
  end)

vertical_viewport_height = 5
vertical_height = vertical_viewport_height + 2
vertical_line_count = vertical_content |> String.split("\n") |> length()
max_vertical_scroll = max(vertical_line_count - vertical_viewport_height, 0)

vertical_top =
  BackBreeze.Box.new(
    content: vertical_content,
    scroll: {0, 0},
    style: %{
      border: :line,
      border_color: 3,
      width: 22,
      height: vertical_height,
      overflow: :hidden,
      scrollbar: true
    }
  )

vertical_bottom =
  BackBreeze.Box.new(
    content: vertical_content,
    scroll: {max_vertical_scroll, 0},
    style: %{
      border: :line,
      border_color: 4,
      width: 22,
      height: vertical_height,
      overflow: :hidden,
      scrollbar: %{thumb: %{foreground_color: 2}, track: %{foreground_color: 8}}
    }
  )

horizontal =
  BackBreeze.Box.new(
    content: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    scroll: {0, 10},
    style: %{
      border: :line,
      border_color: 5,
      width: 20,
      height: 4,
      overflow: :hidden,
      scrollbar: %{
        axis: :horizontal,
        thumb: %{foreground_color: 6},
        track: %{foreground_color: 8}
      }
    }
  )

both_axes =
  BackBreeze.Box.new(
    content:
      Enum.map_join(1..8, "\n", fn row ->
        "L#{row}: ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      end),
    scroll: {2, 7},
    style: %{
      border: :line,
      border_color: 3,
      width: 20,
      height: 6,
      overflow: :hidden,
      scrollbar: %{
        axis: :both,
        arrows: %{foreground_color: 4},
        thumb: %{char: "▓", foreground_color: 2, bold: true},
        track: %{char: "·", foreground_color: 8}
      }
    }
  )

height_full =
  BackBreeze.Box.new(
    style: %{border: :line, border_color: 6, width: 26, height: 8, overflow: :hidden},
    children: [
      BackBreeze.Box.new(content: "Fixed header", style: %{foreground_color: 6}),
      BackBreeze.Box.new(
        content:
          Enum.map_join(1..12, "\n", fn row ->
            "Row #{row}: fill-height body"
          end),
        style: %{
          width: :full,
          height: :full,
          overflow: :hidden,
          scrollbar: %{thumb: %{foreground_color: 2}, track: %{foreground_color: 8}}
        }
      )
    ]
  )

render.("Vertical scrollbar thumb at top (scroll: {0, 0})", vertical_top)
render.("Vertical scrollbar thumb at bottom (max scroll)", vertical_bottom)
render.("Horizontal scrollbar", horizontal)
render.("Both axes with arrows + custom thumb/track", both_axes)
render.("height-full child with scrollbar", height_full)
