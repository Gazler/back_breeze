rows = [
  BackBreeze.Box.new(content: "repeat_x demo"),
  BackBreeze.Box.new(content: ""),
  BackBreeze.Box.new(
    content: "╱",
    style: %{width: 32, repeat_x: true, foreground_color: 3}
  ),
  BackBreeze.Box.new(
    content: "╱╲",
    style: %{width: 32, repeat_x: true, foreground_color: 4}
  ),
  BackBreeze.Box.new(
    content: "━",
    style: %{width: 32, repeat_x: true, foreground_color: 5}
  ),
  BackBreeze.Box.new(content: ""),
  BackBreeze.Box.new(content: "repeat both dimensions"),
  BackBreeze.Box.new(
    content: "╱",
    style: %{
      width: 18,
      height: 7,
      repeat_x: true,
      repeat_y: true,
      border: :line,
      foreground_color: 3
    }
  )
]

rows
|> Enum.map(&BackBreeze.Box.render/1)
|> Enum.map(& &1.content)
|> Enum.join("\n")
|> IO.puts()
