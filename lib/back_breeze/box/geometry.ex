defmodule BackBreeze.Box.Geometry do
  @moduledoc false

  def resolved_parent_width(%{width: rendered_width, style: style}, _opts)
      when is_integer(rendered_width) do
    max(rendered_width - border_horizontal(style.border) - padding_horizontal(style), 0)
  end

  def resolved_parent_width(%{style: %{width: width} = style}, opts) do
    case width do
      width when is_integer(width) ->
        max(width - border_horizontal(style.border) - padding_horizontal(style), 0)

      extent when extent in [:screen, :full] ->
        {screen_width, _screen_height} =
          BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

        max(screen_width - border_horizontal(style.border) - padding_horizontal(style), 0)

      _ ->
        nil
    end
  end

  def resolved_parent_height(%{height: rendered_height, style: style}, _opts)
      when is_integer(rendered_height) do
    max(rendered_height - border_vertical(style.border) - padding_vertical(style), 0)
  end

  def resolved_parent_height(%{style: %{height: height} = style}, opts) do
    resolved_height =
      case height do
        height when is_integer(height) ->
          height

        extent when extent in [:screen, :full] ->
          {_screen_width, screen_height} =
            BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

          screen_height

        _ ->
          nil
      end

    case BackBreeze.Style.constrain_height(resolved_height, style.max_height) do
      height when is_integer(height) ->
        max(height - border_vertical(style.border) - padding_vertical(style), 0)

      _ ->
        nil
    end
  end

  def border_horizontal(border),
    do: edge_size(border.left) + edge_size(border.right)

  def border_vertical(border),
    do: edge_size(border.top) + edge_size(border.bottom)

  def padding_horizontal(style),
    do: style_value(style, :padding_left) + style_value(style, :padding_right)

  def padding_vertical(style),
    do: style_value(style, :padding_top) + style_value(style, :padding_bottom)

  def content_origin(style) do
    {
      edge_size(style.border.left) + style_value(style, :padding_left),
      edge_size(style.border.top) + style_value(style, :padding_top)
    }
  end

  def zero_padding?(style) do
    style_value(style, :padding_left) == 0 and
      style_value(style, :padding_right) == 0 and
      style_value(style, :padding_top) == 0 and
      style_value(style, :padding_bottom) == 0
  end

  def style_value(style, side_key) do
    case Map.get(style, side_key) do
      value when is_integer(value) -> value
      _ -> Map.get(style, :padding, 0) || 0
    end
  end

  defp edge_size(value) when value in [nil, false], do: 0
  defp edge_size(_value), do: 1
end
