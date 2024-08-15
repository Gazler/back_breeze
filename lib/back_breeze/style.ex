defmodule BackBreeze.Style do
  @moduledoc """
  Helper module for styling boxes.
  """
  alias __MODULE__

  defstruct bold: false,
            italic: false,
            padding: 0,
            reverse: false,
            border: BackBreeze.Border.none(),
            width: :auto,
            height: 0,
            overflow: :auto,
            border_color: nil,
            foreground_color: nil,
            background_color: nil

  def bold(style \\ %Style{}) do
    %{style | bold: true}
  end

  def reverse(style \\ %Style{}) do
    %{style | reverse: true}
  end

  def width(style \\ %Style{}, width) do
    %{style | width: width}
  end

  def height(style \\ %Style{}, height) do
    %{style | height: height}
  end

  def border(style \\ %Style{}) do
    %{style | border: BackBreeze.Border.line()}
  end

  def border_left(style \\ %Style{}) do
    %{style | border: BackBreeze.Border.left(style.border)}
  end

  def border_right(style \\ %Style{}) do
    %{style | border: BackBreeze.Border.right(style.border)}
  end

  def border_top(style \\ %Style{}) do
    %{style | border: BackBreeze.Border.top(style.border)}
  end

  def border_bottom(style \\ %Style{}) do
    %{style | border: BackBreeze.Border.bottom(style.border)}
  end

  @overflows [:hidden, :auto]
  def overflow(style \\ %Style{}, overflow) when overflow in @overflows do
    %{style | overflow: overflow}
  end

  def foreground_color(style \\ %Style{}, color) do
    %{style | foreground_color: color}
  end

  def render(style, str, opts \\ []) do
    {content, _} = calculate_and_render(style, str, opts)
    content
  end

  def calculate_and_render(style, str, opts \\ []) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
    style = Map.from_struct(style)

    string_length = BackBreeze.Utils.string_length(str)

    {border, style} = Map.pop(style, :border)
    {overflow, style} = Map.pop(style, :overflow)
    {width, style} = Map.pop(style, :width, string_length)
    {height, style} = Map.pop(style, :height, 0)

    auto_width = width == :auto
    width = if width == :auto, do: string_length, else: width
    width = if width == :screen, do: screen_width - 2, else: width
    height = if height == :screen, do: screen_height - 2, else: height
    str = if string_length > width, do: BackBreeze.String.reflow(str, width), else: str

    termite_style = to_termite(style)

    border = %{border | color: style.border_color}
    lines = String.split(str, "\n")

    content_height = length(lines)
    original_height = height

    width =
      if auto_width && length(lines) > 1,
        do: BackBreeze.Utils.string_length(hd(lines)),
        else: width

    start_pos = Keyword.get(opts, :offset_top, 0)
    end_pos = if overflow == :hidden, do: height + start_pos - 1, else: -1

    lines = Enum.slice(lines, start_pos..end_pos//1)

    content =
      Enum.reduce(lines, "", fn line, acc ->
        string_length = BackBreeze.Utils.string_length(line)
        string_padding = if width > string_length, do: width - string_length, else: 0

        acc <>
          BackBreeze.Border.render_left(border) <>
          Termite.Style.render_to_string(termite_style, line) <>
          String.duplicate(" ", string_padding) <>
          BackBreeze.Border.render_right(border) <> "\n"
      end)

    line_length = length(lines)
    height = if line_length > height, do: 0, else: height + 1 - line_length

    padding =
      if height > 1 do
        Enum.reduce(1..(height - 1), "", fn _i, acc ->
          acc <>
            BackBreeze.Border.render_left(border) <>
            String.duplicate(" ", width) <>
            BackBreeze.Border.render_right(border) <> "\n"
        end)
      else
        ""
      end

    content =
      BackBreeze.Border.render_top(border, width) <>
        String.trim_trailing(content, "\n") <>
        if(padding != "" || border.bottom, do: "\n", else: "") <>
        padding <> BackBreeze.Border.render_bottom(border, width)

    {content, %{height: original_height, content_height: content_height}}
  end

  defp to_termite(style) do
    Enum.reduce(style, Termite.Style.ansi256(), fn
      {_, nil}, t_style -> t_style
      {:bold, true}, t_style -> Termite.Style.bold(t_style)
      {:italic, true}, t_style -> Termite.Style.italic(t_style)
      {:reverse, true}, t_style -> Termite.Style.reverse(t_style)
      {:foreground_color, col}, t_style -> Termite.Style.foreground(t_style, col)
      {:background_color, col}, t_style -> Termite.Style.background(t_style, col)
      _, t_style -> t_style
    end)
  end
end
