items = ["Short", "A longer item", "Medium text"]

auto_children =
  Enum.map(items, fn text ->
    BackBreeze.Box.new(content: text, style: %{border: :line, width: :auto, background_color: 3, foreground_color: 0})
  end)

fill_children =
  Enum.map(items, fn text ->
    BackBreeze.Box.new(content: text, style: %{border: :line, width: :full, background_color: 3, foreground_color: 0})
  end)

label = fn text, width ->
  BackBreeze.Box.new(
    content: text,
    style: %{border: :line, bold: true, foreground_color: 3, width: width}
  )
end

auto_column =
  BackBreeze.Box.new(
    children: [label.("width: :auto", :auto) | auto_children],
    style: %{border: :line, border_color: 2, width: 20}
  )

fill_column =
  BackBreeze.Box.new(
    children: [label.("width: :full", :full) | fill_children],
    style: %{border: :line, border_color: 4, width: 20}
  )

%{content: content} =
  BackBreeze.Box.new(
    children: [auto_column, fill_column],
    display: :inline
  )
  |> BackBreeze.Box.render()

IO.puts(content)
