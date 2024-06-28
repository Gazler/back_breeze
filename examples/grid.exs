child = fn
  x, border -> BackBreeze.Box.new(style: %{border: :line, border_color: border}, content: x)
end

panel = fn
  title, content, border ->
    BackBreeze.Box.new(
      style: %{border: :line, border_color: border},
      children: [
        BackBreeze.Box.new(content: content),
        BackBreeze.Box.new(
          position: :absolute,
          left: 2,
          top: 0,
          content: title,
          style: %{foreground_color: border}
        )
      ]
    )
end

nested_children = [
  panel.("Grid", "This is a thing", 3),
  child.("I am working on", 4),
  child.("Grids", 5)
]

children =
  [
    panel.("Hello", "Hello", 2),
    BackBreeze.Box.new(
      style: %{border: :line},
      display: %BackBreeze.Grid{columns: 1},
      children: nested_children
    ),
    child.("World", 6)
  ]

%{content: content} =
  BackBreeze.Box.new(
    children: children,
    style: %{border: :line, width: :screen, border_color: 1},
    display: %BackBreeze.Grid{columns: 3}
  )
  |> BackBreeze.Box.render(terminal: %Termite.Terminal{size: %{width: 53, height: 14}})

IO.puts(content)

:timer.sleep(2000)
