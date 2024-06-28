defmodule BackBreeze.AbsoluteTest do
  use ExUnit.Case, async: true

  test "absolute positioning" do
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
        content: "ccccc",
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

    assert box.content ==
             """
             ┌─Absolute─────────────────────┐
             │\e[38;5;4mbbbb\e[0m                          │
             │                              │
             │                              │
             │             ┌─\e[38;5;2mccccc\e[0m          │
             │             │aaaa│           │
             │             │    │           │
             │             │    │           │
             │             └────┘           │
             │                              │
             │                              │
             └──────────────────────────────┘\
             """
  end
end
