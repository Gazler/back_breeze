defmodule BackBreeze.Style do
  @moduledoc """
  Helper module for styling boxes.
  """
  alias __MODULE__

  defstruct bold: false,
            italic: false,
            padding: 0,
            padding_top: nil,
            padding_right: nil,
            padding_bottom: nil,
            padding_left: nil,
            reverse: false,
            repeat_x: false,
            repeat_y: false,
            border: BackBreeze.Border.none(),
            text_align: :left,
            width: :auto,
            height: 0,
            overflow: :auto,
            scrollbar: false,
            border_color: nil,
            foreground_color: nil,
            background_color: nil

  def bold(style \\ %Style{}) do
    %{style | bold: true}
  end

  def italic(style \\ %Style{}) do
    %{style | italic: true}
  end

  def reverse(style \\ %Style{}) do
    %{style | reverse: true}
  end

  def repeat_x(style \\ %Style{}, enabled \\ true) do
    %{style | repeat_x: enabled}
  end

  def repeat_y(style \\ %Style{}, enabled \\ true) do
    %{style | repeat_y: enabled}
  end

  def repeat(style \\ %Style{}, axis \\ :both)

  def repeat(style, true), do: repeat(style, :both)
  def repeat(style, :x), do: repeat_x(style)
  def repeat(style, :y), do: repeat_y(style)
  def repeat(style, :both), do: style |> repeat_x() |> repeat_y()

  def padding(style \\ %Style{}, padding) when is_integer(padding) and padding >= 0 do
    %{
      style
      | padding: padding,
        padding_top: padding,
        padding_right: padding,
        padding_bottom: padding,
        padding_left: padding
    }
  end

  def padding_top(style \\ %Style{}, padding) when is_integer(padding) and padding >= 0 do
    %{style | padding_top: padding}
  end

  def padding_right(style \\ %Style{}, padding) when is_integer(padding) and padding >= 0 do
    %{style | padding_right: padding}
  end

  def padding_bottom(style \\ %Style{}, padding) when is_integer(padding) and padding >= 0 do
    %{style | padding_bottom: padding}
  end

  def padding_left(style \\ %Style{}, padding) when is_integer(padding) and padding >= 0 do
    %{style | padding_left: padding}
  end

  def text_align(style \\ %Style{}, align) when align in [:left, :center, :right] do
    %{style | text_align: align}
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

  def border(style, :rounded) do
    %{style | border: BackBreeze.Border.rounded()}
  end

  def border(style, :line) do
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

  def overflow(style \\ %Style{}, overflow)

  def overflow(style, :scroll) do
    %{style | overflow: :hidden, scrollbar: true}
  end

  def overflow(style, overflow) when overflow in [:hidden, :auto] do
    %{style | overflow: overflow}
  end

  @scrollbars [false, :vertical, :horizontal, :both]

  def scrollbar(style \\ %Style{}, scrollbar)

  def scrollbar(style, true) do
    {normalized, style} = BackBreeze.Scrollbar.normalize(true, style)
    %{style | scrollbar: normalized}
  end

  def scrollbar(style, scrollbar) when scrollbar in @scrollbars do
    %{style | scrollbar: scrollbar}
  end

  def scrollbar(style, scrollbar) when is_map(scrollbar) do
    {normalized, style} = BackBreeze.Scrollbar.normalize(scrollbar, style)
    %{style | scrollbar: normalized}
  end

  def border_color(style \\ %Style{}, color) do
    style = %{style | border_color: color}

    case style.scrollbar do
      %BackBreeze.Scrollbar{vertical: %{track: %{foreground_color: nil}}} ->
        %{style | scrollbar: BackBreeze.Scrollbar.put_color(style.scrollbar, color)}

      _ ->
        style
    end
  end

  def foreground_color(style \\ %Style{}, color) do
    %{style | foreground_color: color}
  end

  def background_color(style \\ %Style{}, color) do
    style = %{style | background_color: color}

    case style.scrollbar do
      %BackBreeze.Scrollbar{vertical: %{track: %{background_color: nil}}} ->
        %{style | scrollbar: BackBreeze.Scrollbar.put_background(style.scrollbar, color)}

      _ ->
        style
    end
  end

  def render(style, str, opts \\ []) do
    {content, _} = calculate_and_render(style, str, opts)
    content
  end

  def calculate_and_render(style, str, opts \\ []) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
    style = Map.from_struct(style)

    string_length = BackBreeze.Utils.string_length(str)
    source_lines = String.split(str, "\n")

    intrinsic_width =
      Enum.reduce(source_lines, 0, fn line, acc ->
        max(acc, BackBreeze.Utils.string_length(line))
      end)

    {border, style} = Map.pop(style, :border)
    {text_align, style} = Map.pop(style, :text_align, :left)
    {overflow, style} = Map.pop(style, :overflow)
    {repeat_x, style} = Map.pop(style, :repeat_x, false)
    {repeat_y, style} = Map.pop(style, :repeat_y, false)
    {padding, style} = Map.pop(style, :padding, 0)
    {padding_top, style} = Map.pop(style, :padding_top, nil)
    {padding_right, style} = Map.pop(style, :padding_right, nil)
    {padding_bottom, style} = Map.pop(style, :padding_bottom, nil)
    {padding_left, style} = Map.pop(style, :padding_left, nil)
    padding_top = if(is_integer(padding_top), do: padding_top, else: padding)
    padding_right = if(is_integer(padding_right), do: padding_right, else: padding)
    padding_bottom = if(is_integer(padding_bottom), do: padding_bottom, else: padding)
    padding_left = if(is_integer(padding_left), do: padding_left, else: padding)
    {width, style} = Map.pop(style, :width, :auto)
    {height, style} = Map.pop(style, :height, :auto)

    auto_width = width == :auto
    border_width = if(border.left, do: 1, else: 0) + if(border.right, do: 1, else: 0)
    border_height = if(border.top, do: 1, else: 0) + if(border.bottom, do: 1, else: 0)

    width =
      cond do
        width == :auto -> intrinsic_width
        width in [:screen, :full] -> screen_width
        true -> width
      end

    width =
      if is_integer(width) and not auto_width,
        do: max(width - border_width - padding_left - padding_right, 0),
        else: width

    auto_height = height == :auto

    height =
      cond do
        height == :auto -> 0
        height in [:screen, :full] -> screen_height
        true -> height
      end

    height =
      if is_integer(height) and not auto_height,
        do: max(height - border_height - padding_top - padding_bottom, 0),
        else: height

    str =
      cond do
        string_length <= width -> str
        overflow == :hidden && height == 0 -> BackBreeze.String.truncate(str, width)
        true -> BackBreeze.String.reflow(str, width)
      end

    termite_style = to_termite(style)

    border =
      border
      |> Map.put(:color, style.border_color)
      |> Map.put(:background_color, style.background_color)

    lines =
      case String.split(str, "\n") do
        [""] -> []
        other -> other
      end
      |> maybe_repeat_x(width, repeat_x)
      |> maybe_repeat_y(height, repeat_y)

    content_height = if List.last(lines) == "", do: length(lines) - 1, else: length(lines)
    original_height = height

    width =
      if auto_width,
        do:
          Enum.reduce(lines, 0, fn line, acc -> max(acc, BackBreeze.Utils.string_length(line)) end),
        else: width

    start_pos = Keyword.get(opts, :offset_top, 0)
    end_pos = if overflow == :hidden, do: height + start_pos - 1, else: -1

    lines = Enum.slice(lines, start_pos..end_pos//1)

    rendered_rows =
      Enum.map(lines, fn line ->
        string_length = BackBreeze.Utils.string_length(line)
        string_padding = if width > string_length, do: width - string_length, else: 0
        {left_padding, right_padding} = horizontal_padding(text_align, string_padding)

        BackBreeze.Border.render_left(border) <>
          Termite.Style.render_to_string(
            termite_style,
            String.duplicate(" ", padding_left + left_padding) <>
              line <>
              String.duplicate(" ", right_padding + padding_right)
          ) <>
          BackBreeze.Border.render_right(border)
      end)

    inner_width = padding_left + width + padding_right

    top_padding_rows = blank_rows(padding_top, border, termite_style, inner_width)

    bottom_padding_rows = blank_rows(padding_bottom, border, termite_style, inner_width)

    line_count = length(lines)

    padding_rows =
      case height - line_count do
        remaining when remaining > 0 ->
          blank_rows(remaining, border, termite_style, inner_width)

        _ ->
          []
      end

    rows =
      []
      |> maybe_append_row(BackBreeze.Border.render_top(border, inner_width))
      |> Kernel.++(top_padding_rows)
      |> Kernel.++(rendered_rows)
      |> Kernel.++(bottom_padding_rows)
      |> Kernel.++(padding_rows)
      |> maybe_append_row(BackBreeze.Border.render_bottom(border, inner_width))

    content = Enum.join(rows, "\n")
    height = length(rows)

    viewport_height =
      if original_height == 0 do
        content_height
      else
        min(original_height, content_height)
      end

    {content, %{height: height, viewport_height: viewport_height, content_height: content_height}}
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

  defp maybe_append_row(rows, ""), do: rows
  defp maybe_append_row(rows, nil), do: rows
  defp maybe_append_row(rows, row), do: rows ++ [String.trim_trailing(row, "\n")]

  defp blank_rows(count, _border, _termite_style, _inner_width) when count <= 0, do: []

  defp blank_rows(count, border, termite_style, inner_width) do
    Enum.map(1..count, fn _i ->
      BackBreeze.Border.render_left(border) <>
        Termite.Style.render_to_string(termite_style, String.duplicate(" ", inner_width)) <>
        BackBreeze.Border.render_right(border)
    end)
  end

  defp horizontal_padding(:left, padding), do: {0, padding}
  defp horizontal_padding(:right, padding), do: {padding, 0}

  defp horizontal_padding(:center, padding) do
    left = div(padding, 2)
    {left, padding - left}
  end

  defp maybe_repeat_x(lines, width, true) when is_integer(width) and width > 0 do
    Enum.map(lines, &repeat_line_to_width(&1, width))
  end

  defp maybe_repeat_x(lines, _width, _repeat_x), do: lines

  defp maybe_repeat_y([], _height, _repeat_y), do: []

  defp maybe_repeat_y(lines, height, true) when is_integer(height) and height > 0 do
    line_count = length(lines)

    for index <- 0..(height - 1) do
      Enum.at(lines, rem(index, line_count))
    end
  end

  defp maybe_repeat_y(lines, _height, _repeat_y), do: lines

  defp repeat_line_to_width("", _width), do: ""

  defp repeat_line_to_width(line, width) do
    line_width = BackBreeze.Utils.string_length(line)

    repeats =
      width
      |> Kernel.+(line_width - 1)
      |> div(line_width)
      |> max(1)

    line
    |> String.duplicate(repeats)
    |> BackBreeze.String.truncate(width)
  end
end
