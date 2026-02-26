content =
  "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."

child =
  BackBreeze.Box.new(%{
    style: %{border: :line, width: 30, height: 15},
    content: "EXTRA HEIGHT #{content}"
  })

box = BackBreeze.Box.new(children: [child]) |> BackBreeze.Box.render()

IO.puts(box.content)

child =
  BackBreeze.Box.new(%{
    style: %{border: :line, width: 30, height: 5, overflow: :hidden},
    content: "2 box OVERFLOW HIDDEN #{content}"
  })

box = BackBreeze.Box.new(style: %{border: :line}, children: [child]) |> BackBreeze.Box.render()

IO.puts(box.content)

child =
  BackBreeze.Box.new(%{
    style: %{border: :line, width: 30},
    content: "3 box AUTO HEIGHT #{content}"
  })

parent = BackBreeze.Box.new(style: %{border: :line}, children: [child]) |> BackBreeze.Box.render()

box = BackBreeze.Box.new(style: %{border: :line}, children: [parent]) |> BackBreeze.Box.render()

IO.puts(box.content)

child =
  BackBreeze.Box.new(%{
    style: %{border: :line, width: 30, height: 5, overflow: :hidden},
    scroll: {2, 0},
    content: "2 box OVERFLOW HIDDEN #{content}"
  })

box = BackBreeze.Box.new(style: %{border: :line}, children: [child]) |> BackBreeze.Box.render()

IO.puts(box.content)

child =
  BackBreeze.Box.new(%{
    style: %{
      border: :line,
      width: 30,
      height: 5,
      overflow: :hidden,
      scrollbar: %{
        axis: :vertical,
        arrows: true,
        thumb: %{char: "▓", foreground_color: 2, bold: true},
        track: %{char: "·", foreground_color: 8}
      }
    },
    scroll: {2, 0},
    content: "3 box WITH CONFIGURED SCROLLBAR #{content}"
  })

box = BackBreeze.Box.new(style: %{border: :line}, children: [child]) |> BackBreeze.Box.render()

IO.puts(box.content)
