Code.require_file("../../bench/support/navigation.exs", __DIR__)

defmodule BackBreeze.NavigationBenchmarkTest do
  use ExUnit.Case, async: false
  alias BackBreeze.Bench.Navigation

  test "virtual workload uses uncached lazy styled text and scrollbars" do
    tree = Navigation.tree(80, 24, 250, 90, virtual: true)
    panel = tree.children |> Enum.at(1) |> Map.fetch!(:children) |> Enum.at(1)
    assert %BackBreeze.VirtualText{cache?: false} = panel.content
    assert panel.style.scrollbar.enabled
    assert panel.scroll == {500, 0}
    rendered = BackBreeze.Box.render(tree)
    assert rendered.width == 80
    assert rendered.height == 24
    assert rendered.content =~ "Line 501"
  end

  test "navigation changes frames while retaining fullscreen dimensions" do
    for {width, height} <- [{80, 24}, {278, 76}] do
      frames =
        for selected <- [1, 90] do
          tree = Navigation.tree(width, height, 250, selected)
          result = BackBreeze.Box.render(tree)
          assert result.width == width
          assert result.height == height
          assert result.content =~ "Item"
          assert result.content =~ "Line"
          result.content
        end

      assert hd(frames) != List.last(frames)
    end
  end

  test "rejects invalid benchmark sizes and counts" do
    assert_raise ArgumentError, fn -> Navigation.validate!(width: 10) end
    assert_raise ArgumentError, fn -> Navigation.validate!(iterations: 0) end
    assert_raise ArgumentError, fn -> Navigation.validate!(items: -1) end
  end
end
