defmodule BackBreeze.GridTest do
  alias BackBreeze.Grid
  use ExUnit.Case, async: true

  describe "precompute/4 with screen dimensions" do
    test "computes the width and height for the items" do
      terminal = %Termite.Terminal{size: %{width: 30, height: 20}}
      items = ["Foo", "Bar", "Baz"]
      style = %BackBreeze.Style{width: :screen, height: :screen}

      assert %{width: 10, height: 20} =
               BackBreeze.Grid.precompute(items, %Grid{columns: 3}, style, terminal: terminal)
    end

    test "considers borders for the dimensions" do
      terminal = %Termite.Terminal{size: %{width: 30, height: 20}}
      items = ["Foo", "Bar", "Baz"]
      style = %BackBreeze.Style{width: :screen, height: :screen} |> BackBreeze.Style.border()

      assert %{width: 9, height: 18} =
               BackBreeze.Grid.precompute(items, %Grid{columns: 3}, style, terminal: terminal)
    end

    test "caps screen height before computing row tracks" do
      terminal = %Termite.Terminal{size: %{width: 30, height: 20}}
      items = ["Foo", "Bar", "Baz"]

      style =
        %BackBreeze.Style{width: :screen, height: :screen, max_height: 10}
        |> BackBreeze.Style.border()

      assert %{width: 9, height: 8} =
               BackBreeze.Grid.precompute(items, %Grid{columns: 3}, style, terminal: terminal)
    end

    test "allows an explicit width/height" do
      terminal = %Termite.Terminal{size: %{width: 30, height: 20}}
      items = ["Foo", "Bar", "Baz"]
      style = %BackBreeze.Style{width: 20, height: 10} |> BackBreeze.Style.border()

      assert %{width: 6, height: 8} =
               BackBreeze.Grid.precompute(items, %Grid{columns: 3}, style, terminal: terminal)
    end
  end

  describe "render/4" do
    terminal = %Termite.Terminal{size: %{width: 20, height: 4}}
    items = ["Foo", "Bar", "Baz"] |> Enum.map(&BackBreeze.Box.new(content: &1))
    style = %BackBreeze.Style{width: :screen, height: :screen} |> BackBreeze.Style.border()

    assert {"Foo   Bar   Baz   \n                  ", 18, 2} =
             BackBreeze.Grid.render(items, %Grid{columns: 3}, style, terminal: terminal)

    test "explicit grid size respects the grid's own horizontal padding" do
      items = [
        BackBreeze.Box.new(content: "HEADER"),
        BackBreeze.Box.new(content: "FOOT")
      ]

      style =
        %BackBreeze.Style{width: 20, height: 4}
        |> BackBreeze.Style.padding_left(2)
        |> BackBreeze.Style.padding_right(2)

      assert {"HEADER          \n                \nFOOT            \n                ", 20, 4} =
               BackBreeze.Grid.render(items, %Grid{columns: 1}, style,
                 terminal: %Termite.Terminal{size: %{width: 20, height: 4}}
               )
    end

    test "column gaps reduce track width and add spacing between cells" do
      items = ["Foo", "Bar", "Baz"] |> Enum.map(&BackBreeze.Box.new(content: &1))
      style = %BackBreeze.Style{width: :screen, height: :screen} |> BackBreeze.Style.border()

      assert {"Foo    Bar   Baz  \n                  ", 18, 2} =
               BackBreeze.Grid.render(items, %Grid{columns: 3, gap_x: 1}, style,
                 terminal: %Termite.Terminal{size: %{width: 20, height: 4}}
               )
    end
  end
end
