defmodule BackBreeze.Integration.GridTest do
  use ExUnit.Case, async: true

  test "rendering a grid" do
    child = fn x -> BackBreeze.Box.new(style: %{border: :line}, content: x) end

    children =
      [
        child.("Left"),
        BackBreeze.Box.new(
          style: %{border: :line},
          display: %BackBreeze.Grid{columns: 1},
          children: [child.("Top"), child.("Middle"), child.("Bottom")]
        ),
        child.("Right")
      ]

    box =
      BackBreeze.Box.new(
        children: children,
        style: %{border: :line, width: :screen},
        display: %BackBreeze.Grid{columns: 3}
      )
      |> BackBreeze.Box.render(terminal: %Termite.Terminal{size: %{width: 53, height: 14}})

    assert box.content ==
             """
             ┌───────────────────────────────────────────────────┐
             │┌───────────────┐┌───────────────┐┌───────────────┐│
             ││Left           ││Top            ││Right          ││
             ││               ││               ││               ││
             ││               │└───────────────┘│               ││
             ││               │┌───────────────┐│               ││
             ││               ││Middle         ││               ││
             ││               ││               ││               ││
             ││               │└───────────────┘│               ││
             ││               │┌───────────────┐│               ││
             ││               ││Bottom         ││               ││
             ││               ││               ││               ││
             │└───────────────┘└───────────────┘└───────────────┘│
             └───────────────────────────────────────────────────┘\
             """
  end
end
