defmodule BackBreeze.StyleTest do
  use ExUnit.Case, async: true

  describe "composing styles" do
    test "styles can be composed" do
      style =
        BackBreeze.Style.bold()
        |> BackBreeze.Style.width(17)
        |> BackBreeze.Style.border()
        |> BackBreeze.Style.foreground_color(3)

      assert style.bold
      assert style.width == 17
      assert style.border == BackBreeze.Border.line()
      assert style.foreground_color == 3
    end

    test "supports scrollbar style values" do
      assert BackBreeze.Style.scrollbar(%BackBreeze.Style{}, true).scrollbar.enabled == true
      assert BackBreeze.Style.scrollbar(%BackBreeze.Style{}, :vertical).scrollbar == :vertical
      assert BackBreeze.Style.scrollbar(%BackBreeze.Style{}, :horizontal).scrollbar == :horizontal
      assert BackBreeze.Style.scrollbar(%BackBreeze.Style{}, :both).scrollbar == :both
      assert BackBreeze.Style.scrollbar(%BackBreeze.Style{}, false).scrollbar == false

      style =
        BackBreeze.Style.scrollbar(%BackBreeze.Style{}, %{
          axis: :both,
          thumb: %{char: "▓", foreground_color: 2},
          track: %{char: "·", foreground_color: 8}
        })

      assert is_map(style.scrollbar)
      assert style.scrollbar.axis == :both
    end

    test "outputting the styles" do
      style =
        BackBreeze.Style.bold()
        |> BackBreeze.Style.width(17)
        |> BackBreeze.Style.border()
        |> BackBreeze.Style.foreground_color(3)

      output = BackBreeze.Style.render(style, "Hello World")
      assert output == "┌───────────────┐\n│\e[1;38;5;3mHello World    \e[0m│\n└───────────────┘"
    end

    test "renders borders with the box background color" do
      style =
        BackBreeze.Style.width(7)
        |> BackBreeze.Style.border()
        |> BackBreeze.Style.border_color(3)
        |> BackBreeze.Style.background_color(0)

      output = BackBreeze.Style.render(style, "Hello")

      assert output ==
               """
               \e[48;5;0;38;5;3m┌─────┐\e[0m
               \e[48;5;0;38;5;3m│\e[0m\e[48;5;0mHello\e[0m\e[48;5;0;38;5;3m│\e[0m
               \e[48;5;0;38;5;3m└─────┘\e[0m\
               """
    end

    test "renders empty lines when a height is specified" do
      style =
        BackBreeze.Style.height(5)
        |> BackBreeze.Style.border()

      output = BackBreeze.Style.render(style, "Hello World")

      assert output ==
               "┌───────────┐\n│Hello World│\n│           │\n│           │\n└───────────┘"
    end

    test "renders screen width content" do
      style =
        BackBreeze.Style.height(:screen)
        |> BackBreeze.Style.width(:screen)
        |> BackBreeze.Style.border()

      {width, height} = BackBreeze.screen_dimensions(nil)
      output = BackBreeze.Style.render(style, "Hello World") |> String.split("\n")

      assert length(output) == height
      assert String.length(hd(output)) == width
    end

    test "renders unbordered screen-sized content without losing two rows" do
      style =
        BackBreeze.Style.height(:screen)
        |> BackBreeze.Style.width(:screen)

      {output, dimensions} =
        BackBreeze.Style.calculate_and_render(
          style,
          "x",
          terminal: %Termite.Terminal{size: %{width: 10, height: 4}}
        )

      assert dimensions.height == 4
      assert output |> String.split("\n") |> hd() |> String.length() == 10
    end

    test "renders padding rows with background styling" do
      style =
        BackBreeze.Style.height(3)
        |> BackBreeze.Style.width(4)
        |> BackBreeze.Style.background_color(0)

      output = BackBreeze.Style.render(style, "")

      assert output ==
               """
               \e[48;5;0m    \e[0m
               \e[48;5;0m    \e[0m
               \e[48;5;0m    \e[0m\
               """
    end

    test "aligns content in the center" do
      style =
        BackBreeze.Style.width(7)
        |> BackBreeze.Style.text_align(:center)

      output = BackBreeze.Style.render(style, "Hey")

      assert output == "  Hey  "
    end

    test "aligns content on the right" do
      style =
        BackBreeze.Style.width(7)
        |> BackBreeze.Style.text_align(:right)

      output = BackBreeze.Style.render(style, "Hey")

      assert output == "    Hey"
    end

    test "adds bottom padding outside the content height" do
      style =
        BackBreeze.Style.height(1)
        |> BackBreeze.Style.padding_bottom(1)

      output = BackBreeze.Style.render(style, "Hey")

      assert output == "Hey\n   "
    end

    test "adds directional horizontal padding" do
      style =
        BackBreeze.Style.width(6)
        |> BackBreeze.Style.padding_left(1)
        |> BackBreeze.Style.padding_right(2)

      output = BackBreeze.Style.render(style, "Hey")

      assert output == " Hey  "
    end

    test "treats explicit height as outer height when padding is present" do
      style =
        BackBreeze.Style.height(4)
        |> BackBreeze.Style.width(10)
        |> BackBreeze.Style.padding_top(1)
        |> BackBreeze.Style.padding_bottom(1)

      output = BackBreeze.Style.render(style, "X")

      assert output == "          \nX         \n          \n          "
    end
  end

  describe "overflow/2" do
    test ":scroll sets overflow hidden and enables scrollbar" do
      style = BackBreeze.Style.overflow(:scroll)
      assert style.overflow == :hidden
      assert style.scrollbar == true
    end
  end

  describe "border_color/2" do
    test "sets border_color" do
      style = BackBreeze.Style.border_color(3)
      assert style.border_color == 3
    end
  end

  describe "scrollbar color inheritance" do
    test "scrollbar foreground_color propagates to border_color when not set" do
      style = BackBreeze.Style.scrollbar(%BackBreeze.Style{}, %{foreground_color: 5})
      assert style.border_color == 5
    end

    test "scrollbar foreground_color does not overwrite existing border_color" do
      style =
        BackBreeze.Style.border_color(3)
        |> BackBreeze.Style.scrollbar(%{foreground_color: 5})

      assert style.border_color == 3
    end

    test "border_color propagates to scrollbar regardless of order" do
      forward = BackBreeze.Style.border_color(3) |> BackBreeze.Style.scrollbar(true)

      backward =
        BackBreeze.Style.scrollbar(%BackBreeze.Style{}, true) |> BackBreeze.Style.border_color(3)

      assert forward.scrollbar.vertical.track.foreground_color == 3
      assert backward.scrollbar.vertical.track.foreground_color == 3
    end

    test "border_color does not overwrite explicit scrollbar colors" do
      style =
        BackBreeze.Style.scrollbar(%BackBreeze.Style{}, %{foreground_color: 5})
        |> BackBreeze.Style.border_color(3)

      assert style.scrollbar.vertical.track.foreground_color == 5
    end
  end

  describe "text overflow" do
    test "overflows with auto height" do
      content = String.duplicate("hello world ", 10)

      style =
        BackBreeze.Style.border()
        |> BackBreeze.Style.width(32)

      output = BackBreeze.Style.render(style, content)

      assert output ==
               """
               ┌──────────────────────────────┐
               │hello world hello world hello │
               │world hello world hello world │
               │hello world hello world hello │
               │world hello world hello world │
               └──────────────────────────────┘\
               """
    end

    test "hides content with fixed height" do
      content = String.duplicate("hello world ", 10)

      style =
        BackBreeze.Style.border()
        |> BackBreeze.Style.width(32)
        |> BackBreeze.Style.height(4)
        |> BackBreeze.Style.overflow(:hidden)

      output = BackBreeze.Style.render(style, content)

      assert output ==
               """
               ┌──────────────────────────────┐
               │hello world hello world hello │
               │world hello world hello world │
               └──────────────────────────────┘\
               """
    end

    test "adds padding with a specified height" do
      content = String.duplicate("hello world ", 10)

      style =
        BackBreeze.Style.border()
        |> BackBreeze.Style.width(32)
        |> BackBreeze.Style.height(10)

      output = BackBreeze.Style.render(style, content)

      assert output ==
               """
               ┌──────────────────────────────┐
               │hello world hello world hello │
               │world hello world hello world │
               │hello world hello world hello │
               │world hello world hello world │
               │                              │
               │                              │
               │                              │
               │                              │
               └──────────────────────────────┘\
               """
    end

    test "truncates content with no height when overflow is hidden" do
      content = String.duplicate("hello world ", 5)

      style =
        BackBreeze.Style.border()
        |> BackBreeze.Style.width(12)
        |> BackBreeze.Style.overflow(:hidden)

      output = BackBreeze.Style.render(style, content)

      assert output == "┌──────────┐\n│hello worl│\n└──────────┘"
    end

    test "allows a top offset for scrolling" do
      content = for i <- 1..5, into: "", do: "Line #{i} "

      style =
        BackBreeze.Style.border()
        |> BackBreeze.Style.width(9)
        |> BackBreeze.Style.height(5)
        |> BackBreeze.Style.overflow(:hidden)

      output = BackBreeze.Style.render(style, content, offset_top: 1)

      assert output ==
               """
               ┌───────┐
               │Line 2 │
               │Line 3 │
               │Line 4 │
               └───────┘\
               """
    end
  end
end
