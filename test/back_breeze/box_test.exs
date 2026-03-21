defmodule BackBreeze.BoxTest do
  use ExUnit.Case, async: true

  describe "render_with_dimensions/2" do
    test "calculates nested dimensions" do
      child = BackBreeze.Box.new(content: "Hello\nWorld", style: %{border: :line})

      inner_box =
        BackBreeze.Box.new(children: [child, child], style: %{border: :line, height: 10})

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
               ││World││
               │└─────┘│
               └───────┘\
               """

      assert dimensions == [
               %{
                 height: 10,
                 content_height: 10,
                 viewport_height: 10
               },
               %{
                 left: 0,
                 top: 0,
                 width: 9,
                 height: 10,
                 content_width: 9,
                 content_height: 8,
                 viewport_height: 8,
                 viewport_width: 9
               },
               %{
                 left: 1,
                 top: 1,
                 width: 7,
                 height: 4,
                 content_width: 7,
                 content_height: 2,
                 viewport_height: 2,
                 viewport_width: 7
               },
               %{
                 left: 1,
                 top: 5,
                 width: 7,
                 height: 4,
                 content_width: 7,
                 content_height: 2,
                 viewport_height: 2,
                 viewport_width: 7
               }
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
               \e[38;5;3m┌─────┐\e[0m
               \e[38;5;3m│\e[0m\e[1mHello\e[0m\e[38;5;3m│\e[0m
               \e[38;5;3m└─────┘\e[0m\
               """
    end

    test "renders border cells with the box background color" do
      box =
        BackBreeze.Box.new(
          content: "Hello",
          style: %{border: :line, border_color: 3, background_color: 0}
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               \e[48;5;0;38;5;3m┌─────┐\e[0m
               \e[48;5;0;38;5;3m│\e[0m\e[48;5;0mHello\e[0m\e[48;5;0;38;5;3m│\e[0m
               \e[48;5;0;38;5;3m└─────┘\e[0m\
               """
    end

    test "children inherit parent background color by default" do
      box =
        BackBreeze.Box.new(
          style: %{border: :line, background_color: 0},
          children: [BackBreeze.Box.new(content: "Hello", style: %{foreground_color: 7})]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               \e[48;5;0m┌─────┐\e[0m
               \e[48;5;0m│\e[0m\e[48;5;0;38;5;7mHello\e[0m\e[48;5;0m│\e[0m
               \e[48;5;0m└─────┘\e[0m\
               """
    end

    test "child background color overrides inherited parent background" do
      box =
        BackBreeze.Box.new(
          style: %{border: :line, background_color: 0},
          children: [BackBreeze.Box.new(content: "Hello", style: %{background_color: 1})]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               \e[48;5;0m┌─────┐\e[0m
               \e[48;5;0m│\e[0m\e[48;5;1mHello\e[0m\e[48;5;0m│\e[0m
               \e[48;5;0m└─────┘\e[0m\
               """
    end

    test "parent background fills unused interior rows around child content" do
      box =
        BackBreeze.Box.new(
          style: %{border: :line, background_color: 0, width: 10, height: 6},
          children: [BackBreeze.Box.new(content: "Hello", style: %{foreground_color: 7})]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               \e[48;5;0m┌────────┐\e[0m
               \e[48;5;0m│\e[0m\e[48;5;0;38;5;7mHello\e[0m\e[48;5;0m   │\e[0m
               \e[48;5;0m│        │\e[0m
               \e[48;5;0m│        │\e[0m
               \e[48;5;0m│        │\e[0m
               \e[48;5;0m└────────┘\e[0m\
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

    test "uses remaining width for width-full children in inline layout" do
      box =
        BackBreeze.Box.new(
          display: :inline,
          style: %{width: 20},
          children: [
            BackBreeze.Box.new(content: "Left"),
            BackBreeze.Box.new(content: " Mid"),
            BackBreeze.Box.new(content: "Right", style: %{width: :full, text_align: :right})
          ]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content == "Left Mid       Right"
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
               └─────┘\
               """
    end

    test "clips children to the viewport when overflow is hidden" do
      child = BackBreeze.Box.new(content: "ABCDEFGHIJ")

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 8, height: 3, overflow: :hidden},
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
          style: %{border: :line, width: 8, height: 3, overflow: :hidden},
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

    test "preserves the left border when horizontally scrolling overflowing child content" do
      box =
        BackBreeze.Box.new(
          scroll: {1, 2},
          style: %{border: :line, width: 8, height: 4, overflow: :hidden},
          children: [
            BackBreeze.Box.new(content: "AAAAAA"),
            BackBreeze.Box.new(content: "BBBBBB"),
            BackBreeze.Box.new(content: "CCCCCC")
          ]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │BBBB  │
               │CCCC  │
               └──────┘\
               """
    end

    test "preserves the top border when vertically scrolling overflowing child content" do
      box =
        BackBreeze.Box.new(
          scroll: {1, 0},
          style: %{border: :line, width: 8, height: 4, overflow: :hidden},
          children: [
            BackBreeze.Box.new(content: "AAAAAA"),
            BackBreeze.Box.new(content: "BBBBBB"),
            BackBreeze.Box.new(content: "CCCCCC")
          ]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │BBBBBB│
               │CCCCCC│
               └──────┘\
               """
    end

    test "clips absolute children inside the viewport" do
      child = BackBreeze.Box.new(content: "HELLO", position: :absolute, left: 5, top: 1)

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 8, height: 3, overflow: :hidden},
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

    test "renders absolute children from a fixed-height child as a parent overlay" do
      dropdown =
        BackBreeze.Box.new(
          style: %{width: 6, height: 1},
          children: [
            BackBreeze.Box.new(content: "POST"),
            BackBreeze.Box.new(content: "GET\nPUT", position: :absolute, left: 0, top: 1)
          ]
        )

      sibling = BackBreeze.Box.new(content: "URL")

      box =
        BackBreeze.Box.new(
          style: %{border: :line},
          children: [dropdown, sibling]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │POST  │
               │GET   │
               │PUT   │
               │URL   │
               └──────┘\
               """
    end

    test "absolute full-size children fill their parent" do
      overlay =
        BackBreeze.Box.new(
          position: :absolute,
          top: 0,
          left: 0,
          style: %{width: :full, height: :full, background_color: 0}
        )

      label =
        BackBreeze.Box.new(
          content: "Help",
          position: :absolute,
          top: 1,
          left: 2,
          style: %{foreground_color: 7, background_color: 0}
        )

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 10, height: 6},
          children: [overlay, label]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌────────┐
               │\e[48;5;0m \e[0m\e[48;5;0;38;5;7mHelp\e[0m\e[48;5;0m   \e[0m│
               │\e[48;5;0m        \e[0m│
               │\e[48;5;0m        \e[0m│
               │\e[48;5;0m        \e[0m│
               └────────┘\
               """
    end

    test "supports absolute right and bottom offsets" do
      child = BackBreeze.Box.new(content: "OK", position: :absolute, right: 1, bottom: 1)

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 10, height: 6},
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌────────┐
               │        │
               │        │
               │        │
               │      OK│
               └────────┘\
               """
    end

    test "supports fixed right and bottom offsets relative to the screen" do
      child = BackBreeze.Box.new(content: "X", position: :fixed, right: 0, bottom: 0)

      box =
        BackBreeze.Box.new(
          style: %{width: :screen, height: :screen},
          children: [child]
        )

      rendered =
        BackBreeze.Box.render(box, terminal: %Termite.Terminal{size: %{width: 5, height: 3}})

      assert rendered.content ==
               """
                    
                    
                   X\
               """
    end

    test "supports centered absolute positioning relative to the parent" do
      child = BackBreeze.Box.new(content: "OK", position: :absolute, left: :center, top: :center)

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 10, height: 6},
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌────────┐
               │        │
               │   OK   │
               │        │
               │        │
               └────────┘\
               """
    end

    test "supports centered fixed positioning relative to the screen" do
      child = BackBreeze.Box.new(content: "OK", position: :fixed, left: :center, top: :center)

      box =
        BackBreeze.Box.new(
          style: %{width: :screen, height: :screen},
          children: [child]
        )

      rendered =
        BackBreeze.Box.render(box, terminal: %Termite.Terminal{size: %{width: 10, height: 4}})

      assert rendered.content ==
               """
                         
                   OK    
                         
                         \
               """
    end

    test "supports inset-constrained fixed screen overlays" do
      child =
        BackBreeze.Box.new(
          position: :fixed,
          left: 1,
          right: 1,
          top: 1,
          bottom: 1,
          style: %{border: :line, width: :screen, height: :screen}
        )

      box =
        BackBreeze.Box.new(
          style: %{width: :screen, height: :screen},
          children: [child]
        )

      rendered =
        BackBreeze.Box.render(box, terminal: %Termite.Terminal{size: %{width: 10, height: 6}})

      assert rendered.content ==
               """
                         
                ┌──────┐ 
                │      │ 
                │      │ 
                └──────┘ 
                         \
               """
    end

    test "reports inset-constrained fixed screen overlay dimensions from the constrained outer size" do
      child =
        BackBreeze.Box.new(
          position: :fixed,
          left: 1,
          right: 1,
          top: 1,
          bottom: 1,
          style: %{border: :line, width: :screen, height: :screen}
        )

      box =
        BackBreeze.Box.new(
          style: %{width: :screen, height: :screen},
          children: [child]
        )

      %{dimensions: dimensions} =
        BackBreeze.Box.render_with_dimensions(
          box,
          terminal: %Termite.Terminal{size: %{width: 10, height: 6}}
        )

      assert Enum.any?(dimensions, fn
               %{left: 1, top: 1, width: 8, height: 4} -> true
               _ -> false
             end)
    end

    test "clips children with width-screen overflow hidden" do
      child = BackBreeze.Box.new(content: "ABCDEFGHIJKLMNOPQRST")

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: :screen, height: 3, overflow: :hidden},
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

    test "fills remaining parent height for a block child with height-full" do
      header = BackBreeze.Box.new(content: "Header")

      body =
        BackBreeze.Box.new(
          content: "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE\nFFFFFF",
          style: %{width: 6, height: :full, overflow: :hidden, scrollbar: true}
        )

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 8, height: 7, overflow: :hidden},
          children: [header, body]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content ==
               """
               ┌──────┐
               │Header│
               │AAAAA█│
               │BBBBB█│
               │CCCCC█│
               │DDDDD││
               └──────┘\
               """
    end

    test "renders a vertical scrollbar for overflowing child content" do
      child = BackBreeze.Box.new(content: "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE\nFFFFFF")

      box =
        BackBreeze.Box.new(
          style: %{border: :line, width: 8, height: 5, overflow: :hidden, scrollbar: true},
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
          style: %{border: :line, width: 8, height: 5, overflow: :hidden, scrollbar: true},
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
          style: %{border: :line, width: 8, height: 5, overflow: :hidden, scrollbar: true}
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
            width: 8,
            height: 5,
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
            width: 8,
            height: 5,
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
            width: 7,
            height: 4,
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
          style: %{border: :line, width: 8, height: 5, overflow: :hidden, scrollbar: true},
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
            width: 8,
            height: 5,
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
            width: 8,
            height: 3,
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
          style: %{border: :line, width: 8, height: 6, overflow: :hidden, scrollbar: true}
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
            width: 8,
            height: 6,
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
            width: 8,
            height: 6,
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
            width: 8,
            height: 6,
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
            width: 7,
            height: 4,
            overflow: :hidden,
            scrollbar: %{
              axis: :horizontal,
              thumb: %{foreground_color: 2},
              track: %{foreground_color: 8}
            }
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
          style: %{border: :line, width: 3, height: 9, overflow: :hidden, scrollbar: true},
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

    test "supports colored arrows via arrows config map" do
      child = BackBreeze.Box.new(content: Enum.map_join(1..8, "\n", fn _ -> "ABCDEFGHIJKL" end))

      box =
        BackBreeze.Box.new(
          scroll: {1, 3},
          style: %{
            border: :line,
            width: 8,
            height: 6,
            overflow: :hidden,
            scrollbar: %{axis: :both, arrows: %{foreground_color: 2}}
          },
          children: [child]
        )

      rendered = BackBreeze.Box.render(box)
      assert String.contains?(rendered.content, "\e[38;5;2m▲")
      assert String.contains?(rendered.content, "\e[38;5;2m▼")
      assert String.contains?(rendered.content, "\e[38;5;2m◀")
      assert String.contains?(rendered.content, "\e[38;5;2m▶")
    end

    test "scrollbar inherits border_color for track and thumb" do
      children = Enum.map(1..6, &BackBreeze.Box.new(content: "Line #{&1}"))

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            border_color: 3,
            width: 8,
            height: 3,
            overflow: :hidden,
            scrollbar: true
          },
          children: children
        )

      rendered = BackBreeze.Box.render(box)
      assert String.contains?(rendered.content, "\e[38;5;3m│")
      assert String.contains?(rendered.content, "\e[38;5;3m█")
    end

    test "scrollbar inherits the box background for track and arrows" do
      children = Enum.map(1..6, &BackBreeze.Box.new(content: "Line #{&1}"))

      box =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            border_color: 3,
            background_color: 0,
            width: 10,
            height: 5,
            overflow: :hidden,
            scrollbar: %{axis: :vertical, arrows: true}
          },
          children: children
        )

      rendered = BackBreeze.Box.render(box)
      assert String.contains?(rendered.content, "\e[48;5;0;38;5;3m▲")
      assert String.contains?(rendered.content, "\e[48;5;0;38;5;3m│")
      assert String.contains?(rendered.content, "\e[48;5;0;38;5;3m▼")
    end

    test "scrollbar inherits a parent background when the child has none" do
      child =
        BackBreeze.Box.new(
          style: %{
            border: :line,
            border_color: 3,
            width: 10,
            height: 5,
            overflow: :hidden,
            scrollbar: %{axis: :vertical, arrows: true}
          },
          children: Enum.map(1..6, &BackBreeze.Box.new(content: "Line #{&1}"))
        )

      parent =
        BackBreeze.Box.new(
          style: %{background_color: 4},
          children: [child]
        )

      rendered = BackBreeze.Box.render(parent)
      assert String.contains?(rendered.content, "\e[48;5;4;38;5;3m▲")
      assert String.contains?(rendered.content, "\e[48;5;4;38;5;3m│")
      assert String.contains?(rendered.content, "\e[48;5;4;38;5;3m▼")
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

  describe "width: :full" do
    test "child fills parent content width" do
      child = BackBreeze.Box.new(content: "Hi", style: %{border: :line, width: :full})
      box = BackBreeze.Box.new(children: [child], style: %{border: :line, width: 10})
      rendered = BackBreeze.Box.render(box)

      # width: 10 is total outer width, so parent content width is 8
      # child width-full fills that 8-wide content area, yielding 6 inner columns once bordered
      assert rendered.content ==
               """
               ┌────────┐
               │┌──────┐│
               ││Hi    ││
               │└──────┘│
               └────────┘\
               """
    end

    test "multiple children without border each fill parent width" do
      child = fn text -> BackBreeze.Box.new(content: text, style: %{width: :full}) end

      box =
        BackBreeze.Box.new(
          children: [child.("A"), child.("B")],
          style: %{border: :line, width: 8}
        )

      rendered = BackBreeze.Box.render(box)

      # width: 8 is total outer width, so parent content width is 6
      assert rendered.content ==
               """
               ┌──────┐
               │A     │
               │B     │
               └──────┘\
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

  describe "padding with children" do
    test "insets child content once inside directional padding" do
      box =
        BackBreeze.Box.new(
          style: %{width: 10, height: 4, padding_top: 1, padding_left: 1},
          children: [BackBreeze.Box.new(content: "X")]
        )

      rendered = BackBreeze.Box.render(box)

      assert rendered.content == "          \n X        \n          \n          "
    end
  end
end
