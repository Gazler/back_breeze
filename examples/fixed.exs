size = %{width: 30, height: 10}

main =
  BackBreeze.Box.new(%{
    style: %{border: :line, width: size.width, height: size.height},
    children: [
      BackBreeze.Box.new(%{content: "Main content"}),
      BackBreeze.Box.new(%{
        content: "Absolute",
        position: :absolute,
        right: 2,
        top: 1,
        style: %{foreground_color: 3}
      }),
      BackBreeze.Box.new(%{
        style: %{border: :rounded, width: 12, height: 3},
        position: :fixed,
        right: 1,
        bottom: 1,
        children: [
          BackBreeze.Box.new(%{content: "Fixed"}),
          BackBreeze.Box.new(%{content: "bottom-right"})
        ]
      })
    ]
  })

IO.puts(
  BackBreeze.Box.render(main, terminal: %Termite.Terminal{size: size}).content
)
