defmodule BackBreeze.BoxTest do
  use ExUnit.Case, async: true

  describe "render_with_dimensions/2" do
    test "calculates nested dimensions" do
      child = BackBreeze.Box.new(content: "Hello\nWorld", style: %{border: :line})
      inner_box = BackBreeze.Box.new(children: [child, child], style: %{border: :line, height: 6})
      box = BackBreeze.Box.new(children: [inner_box])
      %{box: box, dimensions: dimensions} = BackBreeze.Box.render_with_dimensions(box)

      assert box.content ==
               """
               ┌───────┐
               │┌─────┐│
               ││Hello││
               ││World││
               │└─────┘│
               │┌─────┐│
               ││Hello││
               └───────┘\
               """

      assert dimensions == [
               %{height: 8, content_height: 8, viewport_height: 8},
               %{height: 8, content_height: 8, viewport_height: 6},
               %{height: 4, content_height: 2, viewport_height: 2},
               %{height: 4, content_height: 2, viewport_height: 2}
             ]
    end
  end

  describe "render/1" do
    test "renders a single child" do
      child = BackBreeze.Box.new(content: "Hello", style: %{bold: true})
      box = BackBreeze.Box.new(children: [child])
      rendered = BackBreeze.Box.render(box)

      assert rendered.state == :rendered
      assert rendered.content == BackBreeze.Style.bold() |> BackBreeze.Style.render("Hello")
    end

    test "renders a single element" do
      box = BackBreeze.Box.new(content: "Hello", style: %{border: :line, bold: true})
      rendered = BackBreeze.Box.render(box)

      assert rendered.state == :rendered

      assert rendered.content ==
               """
               ┌─────┐
               │\e[1mHello\e[0m│
               └─────┘\
               """
    end

    test "renders with a coloured border" do
      box =
        BackBreeze.Box.new(content: "Hello", style: %{border: :line, border_color: 3, bold: true})

      rendered = BackBreeze.Box.render(box)

      assert rendered.state == :rendered

      assert rendered.content ==
               """
               \e[33m┌─────┐\e[0m
               \e[33m│\e[0m\e[1mHello\e[0m\e[33m│\e[0m
               \e[33m└─────┘\e[0m\
               """
    end

    test "renders unicode correctly" do
      child = BackBreeze.Box.new(content: "🍏", style: %{forground_color: 2})
      box = BackBreeze.Box.new(children: [child], style: %{border: :line})
      rendered = BackBreeze.Box.render(box)

      assert rendered.state == :rendered

      assert rendered.content ==
               """
               ┌──┐
               │🍏│
               └──┘\
               """
    end

    test "renders a tree of children joined horizontally" do
      child = BackBreeze.Box.new(content: "Hello", style: %{bold: true, foreground_color: 3})
      nested = BackBreeze.Box.new(children: [child], style: %{border: :line})

      world = BackBreeze.Box.new(content: "World", style: %{italic: true})
      box = BackBreeze.Box.new(children: [child, nested, nested, world], display: :inline)
      rendered = BackBreeze.Box.render(box)

      assert rendered.state == :rendered

      assert rendered.content ==
               """
                    ┌─────┐┌─────┐     
                    │\e[1;38;5;3mHello\e[0m││\e[1;38;5;3mHello\e[0m│     
               \e[1;38;5;3mHello\e[0m└─────┘└─────┘\e[3mWorld\e[0m\
               """
    end

    test "renders a tree with empty absolute nesting" do
      child = BackBreeze.Box.new(content: "Hello", style: %{bold: true, foreground_color: 3})
      nested = BackBreeze.Box.new(children: [child], position: :absolute, top: 0, left: 1)
      box = BackBreeze.Box.new(style: %{border: :line}, children: [nested])
      rendered = BackBreeze.Box.render(box)
      assert rendered.state == :rendered

      assert rendered.content ==
               """
               ┌\e[1;38;5;3mHello\e[0m┐
               │     │
               └─────┘\
               """
    end

    test "clips children to the viewport when overflow is hidden" do
      child = BackBreeze.Box.new(content: "ABCDEFGHIJ")

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 6, height: 1, overflow: :hidden},
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │ABCDEF│
               └──────┘\
               """
    end

    test "supports horizontal child scrolling with overflow hidden" do
      child = BackBreeze.Box.new(content: "ABCDEFGHIJ")

      box =
        BackBreeze.Box.new(
          scroll: {0, 2},
          style: %{border: :line, width: 6, height: 1, overflow: :hidden},
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │CDEFGH│
               └──────┘\
               """
    end

    test "clips absolute children inside the viewport" do
      child = BackBreeze.Box.new(content: "HELLO", position: :absolute, left: 5, top: 1)

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 6, height: 1, overflow: :hidden},
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │    HE│
               └──────┘\
               """
    end

    test "clips children with width-screen overflow hidden" do
      child = BackBreeze.Box.new(content: "ABCDEFGHIJKLMNOPQRST")

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: :screen, height: 1, overflow: :hidden},
          children: [child]
        )

      rendered =
        BackBreeze.Box.render(box, terminal: %Termite.Terminal{size: %{width: 10, height: 5}})

      assert rendered.content ==
               """
               ┌────────┐
               │ABCDEFGH│
               └────────┘\
               """
    end

    test "renders a vertical scrollbar for overflowing child content" do
      child = BackBreeze.Box.new(content: "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE\nFFFFFF")

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 6, height: 3, overflow: :hidden, scrollbar: true},
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │AAAAAA█
               │BBBBBB█
               │CCCCCC│
               └──────┘\
               """
    end

    test "moves scrollbar thumb based on vertical scroll offset" do
      child = BackBreeze.Box.new(content: "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE\nFFFFFF")

      box =
        BackBreeze.Box.new(
          scroll: {3, 0},
          style: %{border: :line, width: 6, height: 3, overflow: :hidden, scrollbar: true},
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │DDDDDD│
               │EEEEEE█
               │FFFFFF█
               └──────┘\
               """
    end

    test "renders a vertical scrollbar for overflowing leaf content" do
      box =
        BackBreeze.Box.new(
          content: "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE\nFFFFFF",
          scroll: {1, 0},
          style: %{border: :line, width: 6, height: 3, overflow: :hidden, scrollbar: true}
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │BBBBBB█
               │CCCCCC█
               │DDDDDD│
               └──────┘\
               """
    end

    test "supports custom scrollbar chars and colors" do
      child = BackBreeze.Box.new(content: "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE\nFFFFFF")

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 6,
            height: 3,
            overflow: :hidden,
            scrollbar: %{
              axis: :vertical,
              thumb: %{char: "▓", foreground_color: 2, bold: true},
              track: %{char: "·", foreground_color: 8}
            }
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert String.contains?(rendered.content, "\e[1;38;5;2m▓\e[0m")
      assert String.contains?(rendered.content, "\e[38;5;8m·\e[0m")
    end

    test "supports start placement for vertical scrollbars" do
      child = BackBreeze.Box.new(content: "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE\nFFFFFF")

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 6,
            height: 3,
            overflow: :hidden,
            scrollbar: %{axis: :vertical, placement: :start}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               █AAAAAA│
               █BBBBBB│
               │CCCCCC│
               └──────┘\
               """
    end

    test "renders a horizontal scrollbar and thumb" do
      child = BackBreeze.Box.new(content: "ABCDEFGHIJKL")

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 5,
            height: 2,
            overflow: :hidden,
            scrollbar: %{axis: :horizontal}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌─────┐
               │ABCDE│
               │     │
               └██───┘\
               """
    end

    test "scales thumb proportionally by default" do
      child = BackBreeze.Box.new(content: "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE\nFFFFFF")

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 6, height: 3, overflow: :hidden, scrollbar: true},
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert String.contains?(rendered.content, "│AAAAAA█")
      assert String.contains?(rendered.content, "│BBBBBB█")
    end

    test "supports fixed thumb sizing override" do
      child = BackBreeze.Box.new(content: "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE\nFFFFFF")

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 6,
            height: 3,
            overflow: :hidden,
            scrollbar: %{axis: :vertical, sizing: {:fixed, 1}}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │AAAAAA█
               │BBBBBB│
               │CCCCCC│
               └──────┘\
               """
    end

    test "respects show: :never" do
      child = BackBreeze.Box.new(content: "ABCDEFGHIJKL\nMNOPQRSTUVWX\nYZ0123456789")

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 6,
            height: 3,
            overflow: :hidden,
            scrollbar: %{axis: :both, show: :never, thumb: %{char: "▓"}, track: %{char: "·"}}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      refute String.contains?(rendered.content, "▓")
      refute String.contains?(rendered.content, "·")
    end

    test "supports show: :always for non-overflowing content" do
      child = BackBreeze.Box.new(content: "ABC")

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 5,
            height: 2,
            overflow: :hidden,
            scrollbar: %{axis: :vertical, show: :always}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)
      assert String.contains?(rendered.content, "█")
    end

    test "draws end scrollbar on border gutter for bordered containers" do
      child = BackBreeze.Box.new(content: "ABCDEF")

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 6,
            height: 1,
            overflow: :hidden,
            scrollbar: %{axis: :vertical, show: :always}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │ABCDEF█
               └──────┘\
               """
    end

    test "scrollbar thumb reaches the bottom at max vertical scroll" do
      content = Enum.map_join(1..30, "\n", fn i -> "L#{i}" end)

      box =
        BackBreeze.Box.new(
          content: content,
          scroll: {26, 0},
          style: %{border: :line, width: 6, height: 4, overflow: :hidden, scrollbar: true}
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │L27   │
               │L28   │
               │L29   │
               │L30   █
               └──────┘\
               """
    end

    test "renders both scrollbars with arrows" do
      child = BackBreeze.Box.new(content: "ABCDEFGHIJKL\nMNOPQRSTUVWX\nYZ0123456789\nabcdefghijk")

      box =
        BackBreeze.Box.new(
          scroll: {1, 3},
          style: %{
            border: :line,
            width: 6,
            height: 4,
            overflow: :hidden,
            scrollbar: %{axis: :both, arrows: true}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert String.contains?(rendered.content, "▲")
      assert String.contains?(rendered.content, "▼")
      assert String.contains?(rendered.content, "◀")
      assert String.contains?(rendered.content, "▶")
      assert String.contains?(rendered.content, "┘")
    end

    test "vertical arrows are not trimmed when horizontal scrollbar sits on the bottom border" do
      child = BackBreeze.Box.new(content: Enum.map_join(1..8, "\n", fn _ -> "ABCDEFGHIJKL" end))

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 6,
            height: 4,
            overflow: :hidden,
            scrollbar: %{axis: :both, arrows: true}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)
      rows = String.split(rendered.content, "\n")

      assert String.ends_with?(Enum.at(rows, 1), "▲")
      assert String.ends_with?(Enum.at(rows, 4), "▼")
    end

    test "horizontal arrows are not trimmed when vertical scrollbar sits on the right border" do
      child = BackBreeze.Box.new(content: Enum.map_join(1..8, "\n", fn _ -> "ABCDEFGHIJKL" end))

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 6,
            height: 4,
            overflow: :hidden,
            scrollbar: %{axis: :both, arrows: true}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)
      rows = String.split(rendered.content, "\n")

      assert String.ends_with?(Enum.at(rows, 5), "▶┘")
    end

    test "supports colored horizontal scrollbar" do
      child = BackBreeze.Box.new(content: "ABCDEFGH")

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            width: 5,
            height: 2,
            overflow: :hidden,
            scrollbar: %{axis: :horizontal, thumb: %{foreground_color: 2}, track: %{foreground_color: 8}}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)
      assert String.contains?(rendered.content, "\e[38;5;2m███\e[0m")
      assert String.contains?(rendered.content, "\e[38;5;8m──\e[0m")
    end

    test "scrollbar thumb reaches the bottom with absolute-positioned siblings" do
      absolute_child = BackBreeze.Box.new(content: "x", position: :absolute, left: 1, top: 0)

      relative_children = Enum.map(~w(A B C D E F G H I), &BackBreeze.Box.new(content: &1))

      box =
        BackBreeze.Box.new(
          scroll: {2, 0},
          style: %{border: :line, width: 1, height: 7, overflow: :hidden, scrollbar: true},
          children: [absolute_child | relative_children]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌─┐
               │C│
               │D│
               │E█
               │F█
               │G█
               │H█
               │I█
               └─┘\
               """
    end
  end

  describe "join_vertical/2" do
    test "joins items vertically" do
      items = ["One line", "Two\nLines", "Three\n+\n+\nLines"]
      {content, 8, 7} = BackBreeze.Box.join_vertical(items)

      assert content ==
               """
               One line
               Two
               Lines
               Three
               +
               +
               Lines\
               """
    end
  end

  describe "join_horizontal/2" do
    test "joins items with padding" do
      items = ["One line", "Two\nLines", "Three\n+\n+\nLines"]
      {content, 18, 3} = BackBreeze.Box.join_horizontal(items)

      assert content ==
               """
                            Three
                            +    
                       Two  +    
               One lineLinesLines\
               """
    end

    test "aligns lines on the right" do
      items = ["One line", "Two\nLines", "Three\n+\n+\nLines"]
      {content, 18, 3} = BackBreeze.Box.join_horizontal(items, align: :right)

      assert content ==
               """
                            Three
                                +
                         Two    +
               One lineLinesLines\
               """
    end

    test "aligns lines in the center" do
      items = ["One line", "Two\nLines", "Three\n+\n+\nLines"]
      {content, 18, 3} = BackBreeze.Box.join_horizontal(items, align: :center)

      assert content ==
               """
                            Three
                              +  
                        Two   +  
               One lineLinesLines\
               """
    end
  end
end
