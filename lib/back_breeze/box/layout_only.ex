defmodule BackBreeze.Box.LayoutOnly do
  @moduledoc false

  alias BackBreeze.Box.Geometry
  alias BackBreeze.Box.LayerMap

  def child_result(child, opts)

  def child_result(%{children: [], content: content, style: style} = child, opts)
      when content in ["", nil] do
    with true <- Keyword.get(opts, :structured, false),
         true <- layout_only_style?(style),
         width when is_integer(width) <- layout_only_dimension(child.width, style.width),
         height when is_integer(height) <-
           layout_only_dimension(child.height, style.height)
           |> BackBreeze.Style.constrain_height(style.max_height) do
      dimension = %{
        width: width,
        viewport_width: width,
        content_width: width,
        height: height,
        viewport_height: height,
        content_height: height,
        left: 0,
        top: 0
      }

      layer_map = layout_only_layer_map(style, width, height)

      box = %{
        child
        | content: "",
          width: width,
          height: height,
          state: :rendered,
          children: [],
          layer_map: layer_map,
          fixed_layer_map: %{},
          overlay?: false
      }

      %{box: box, dimensions: [dimension]}
    else
      _ -> nil
    end
  end

  def child_result(_child, _opts), do: nil

  defp layout_only_dimension(value, _style_value) when is_integer(value), do: value
  defp layout_only_dimension(_value, style_value) when is_integer(style_value), do: style_value
  defp layout_only_dimension(_value, _style_value), do: nil

  defp layout_only_layer_map(style, width, height)
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    case LayerMap.content_style_sequence(style) do
      "" -> %{}
      seq -> LayerMap.put_default_fill_entries(%{}, [{{" ", seq}, 0, 0, width - 1, height - 1}])
    end
  end

  defp layout_only_layer_map(_style, _width, _height), do: %{}

  defp layout_only_style?(%BackBreeze.Style{} = style) do
    style.scrollbar == false and
      style.border == BackBreeze.Border.none() and
      Geometry.zero_padding?(style) and
      not style.reverse and
      not style.repeat_x and
      not style.repeat_y
  end
end
