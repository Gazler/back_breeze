defmodule BackBreeze.StyleTest do
  use ExUnit.Case, async: true

  describe "composing styles" do
    test "styles can be composed" do
      style =
        BackBreeze.Style.bold()
        |> BackBreeze.Style.width(15)
        |> BackBreeze.Style.border()
        |> BackBreeze.Style.foreground_color(3)

      assert style.bold
      assert style.width == 15
      assert style.border == BackBreeze.Border.line()
      assert style.foreground_color == 3
    end

    test "outputting the styles" do
      style =
        BackBreeze.Style.bold()
        |> BackBreeze.Style.width(15)
        |> BackBreeze.Style.border()
        |> BackBreeze.Style.foreground_color(3)

      output = BackBreeze.Style.render(style, "Hello World")
      assert output == "┌───────────────┐\n│\e[1;38;5;3mHello World\e[0m    │\n└───────────────┘"
    end

    test "renders empty lines when a height is specified" do
      style =
        BackBreeze.Style.height(3)
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

      {:ok, width} = :io.columns()
      {:ok, height} = :io.rows()
      output = BackBreeze.Style.render(style, "Hello World") |> String.split("\n")

      assert length(output) == height
      assert String.length(hd(output)) == width
    end
  end

  describe "text overflow" do
    test "overflows with auto height" do
      content = String.duplicate("hello world ", 10)

      style =
        BackBreeze.Style.border()
        |> BackBreeze.Style.width(30)

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
        |> BackBreeze.Style.width(30)
        |> BackBreeze.Style.height(2)
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
        |> BackBreeze.Style.width(30)
        |> BackBreeze.Style.height(8)

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
  end
end
