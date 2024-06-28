defmodule BackBreeze.Style do
  alias __MODULE__

  defstruct bold: false,
            italic: false,
            padding: 0,
            reverse: false,
            border: BackBreeze.Border.none(),
            width: 0,
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
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
    style = Map.from_struct(style)

    string_length = BackBreeze.Utils.string_length(str)

    {border, style} = Map.pop(style, :border)
    {overflow, style} = Map.pop(style, :overflow)
    {width, style} = Map.pop(style, :width, string_length)
    {height, style} = Map.pop(style, :height, 0)

    width = if width == :auto, do: string_length, else: width

    {width, str} =
      cond do
        width == :screen -> {screen_width - 2, str}
        overflow == :auto && string_length > width -> {string_length, str}
        overflow == :hidden && string_length > width -> {width, String.slice(str, 0, width)}
        true -> {width, str}
      end

    height =
      cond do
        height == :screen -> screen_height - 2
        true -> height
      end

    termite_style =
      Enum.reduce(style, Termite.Style.ansi256(), fn
        {_, nil}, t_style -> t_style
        {:bold, true}, t_style -> Termite.Style.bold(t_style)
        {:italic, true}, t_style -> Termite.Style.italic(t_style)
        {:reverse, true}, t_style -> Termite.Style.reverse(t_style)
        {:foreground_color, col}, t_style -> Termite.Style.foreground(t_style, col)
        {:background_color, col}, t_style -> Termite.Style.background(t_style, col)
        _, t_style -> t_style
      end)

    border = %{border | color: style.border_color}

    content =
      BackBreeze.Border.render_left(border) <>
        Termite.Style.render_to_string(termite_style, str) <>
        String.duplicate(" ", width - string_length) <>
        BackBreeze.Border.render_right(border)

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

    BackBreeze.Border.render_top(border, width) <>
      content <>
      if(padding != "" || border.bottom, do: "\n", else: "") <>
      padding <> BackBreeze.Border.render_bottom(border, width)
  end
end
