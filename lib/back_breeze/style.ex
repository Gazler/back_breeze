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
    %{style | background_color: color}
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

    auto_width = width in [:auto, :full]
    border_width = if(border.left, do: 1, else: 0) + if(border.right, do: 1, else: 0)
    border_height = if(border.top, do: 1, else: 0) + if(border.bottom, do: 1, else: 0)

    width = if width in [:auto, :full], do: string_length, else: width
    width = if width == :screen, do: screen_width - border_width, else: width
    height = if height == :full, do: 0, else: height
    height = if height == :screen, do: screen_height - border_height, else: height

    str =
      cond do
        string_length <= width -> str
        overflow == :hidden && height == 0 -> BackBreeze.String.truncate(str, width)
        true -> BackBreeze.String.reflow(str, width)
      end

    termite_style = to_termite(style)

    border = %{border | color: style.border_color}

    lines =
      case String.split(str, "\n") do
        [""] -> []
        other -> other
      end

    content_height = if List.last(lines) == "", do: length(lines) - 1, else: length(lines)
    original_height = height

    width =
      if auto_width && length(lines) > 1,
        do: BackBreeze.Utils.string_length(hd(lines)),
        else: width

    start_pos = Keyword.get(opts, :offset_top, 0)
    end_pos = if overflow == :hidden, do: height + start_pos - 1, else: -1

    lines = Enum.slice(lines, start_pos..end_pos//1)

    rendered_rows =
      Enum.map(lines, fn line ->
        string_length = BackBreeze.Utils.string_length(line)
        string_padding = if width > string_length, do: width - string_length, else: 0

        BackBreeze.Border.render_left(border) <>
          Termite.Style.render_to_string(
            termite_style,
            line <> String.duplicate(" ", string_padding)
          ) <>
          BackBreeze.Border.render_right(border)
      end)

    line_count = length(lines)

    padding_rows =
      case height - line_count do
        remaining when remaining > 0 ->
          Enum.map(1..remaining, fn _i ->
            BackBreeze.Border.render_left(border) <>
              Termite.Style.render_to_string(termite_style, String.duplicate(" ", width)) <>
              BackBreeze.Border.render_right(border)
          end)

        _ ->
          []
      end

    rows =
      []
      |> maybe_append_row(BackBreeze.Border.render_top(border, width))
      |> Kernel.++(rendered_rows)
      |> Kernel.++(padding_rows)
      |> maybe_append_row(BackBreeze.Border.render_bottom(border, width))

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
end
