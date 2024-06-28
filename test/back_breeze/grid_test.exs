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

    test "allows an explicit width/height" do
      terminal = %Termite.Terminal{size: %{width: 30, height: 20}}
      items = ["Foo", "Bar", "Baz"]
      style = %BackBreeze.Style{width: 20, height: 10} |> BackBreeze.Style.border()

      assert %{width: 6, height: 8} =
               BackBreeze.Grid.precompute(items, %Grid{columns: 3}, style, terminal: terminal)
    end
  end
end
