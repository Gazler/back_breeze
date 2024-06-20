size = %{width: 15, height: 10}

a =
  BackBreeze.Box.new(%{
    style: %{border: :line, height: 3},
    content: "aaaa",
    position: :absolute,
    left: 7 * 2,
    top: 4
  })

b = BackBreeze.Box.new(%{style: %{foreground_color: 4}, content: "bbbb"})

c =
  BackBreeze.Box.new(%{
    style: %{foreground_color: 2},
    content: "cccccccc",
    position: :absolute,
    left: 8 * 2,
    top: 4
  })

title = BackBreeze.Box.new(%{content: "Absolute", position: :absolute, left: 2, top: 0})

box =
  BackBreeze.Box.new(%{
    style: %{border: :line, width: size.width * 2, height: size.height},
    children: [a, b, c, title]
  })
  |> BackBreeze.Box.render()

IO.puts(box.content)
