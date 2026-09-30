defmodule BackBreeze.Box.InlineLayout do
  @moduledoc false
  alias BackBreeze.Box.{Geometry, LayerMap, Scene}

  # A single-row subtree needs no wrapping, vertical layout, or ANSI parsing.
  # Reject unsupported nodes before exporting any result. Ordinary layout is
  # still authoritative for borders, overlays, wrapping, and multiline text.
  def child_result(%{display: :inline, children: [_ | _]} = box, opts) do
    if Keyword.get(opts, :structured, false) do
      case row(box, nil, nil) do
        {:ok, rendered, dims, _spans} -> %{box: rendered, dimensions: dims}
        :error -> nil
      end
    end
  end

  def child_result(_, _), do: nil

  defp row(%{children: [], content: text, style: %{width: 0, height: 0, overflow: :hidden}} = box, _, parent_style)
       when text in ["", nil] do
    box = %{box | style: inherit(box.style, parent_style)}

    if supported?(box) do
      dim = %{dimension(0) | height: 0, viewport_height: 0, content_height: 0}
      {:ok, %{box | content: "", width: 0, height: 0, state: :rendered}, [dim], []}
    else
      :error
    end
  end

  defp row(box, available, parent_style) do
    style = inherit(box.style, parent_style)

    width =
      case style.width do
        value when value in [:full, :screen] -> available
        :auto -> :auto
        value -> value
      end

    style = %{style | width: width}
    box = %{box | style: style}

    if supported?(box) and (width == :auto or (is_integer(width) and width > 0)) do
      layout(box, width, style_sequence(style, parent_style))
    else
      :error
    end
  end

  defp layout(%{children: [], content: text} = box, width, seq)
       when is_binary(text) and byte_size(text) > 0 do
    width = if width == :auto, do: byte_size(text), else: width

    if byte_size(text) <= width and Regex.match?(~r/\A[\x20-\x7e]+\z/, text) do
      if seq == "" do
        :error
      else
        text = text <> String.duplicate(" ", width - byte_size(text))
        spans = [{text, seq}]
        {:ok, rendered(box, width, [], spans), [dimension(width)], spans}
      end
    else
      :error
    end
  end

  defp layout(%{content: content, children: children, display: display} = box, width, seq)
       when content in ["", nil] and children != [] do
    if display == :inline or (display == :block and length(children) == 1) do
      inner_width = if is_integer(width), do: width - Geometry.padding_horizontal(box.style), else: nil

      children
      |> Enum.reduce_while({[], [], [], 0}, fn child, {boxes, dims, spans, x} ->
        available = if is_integer(inner_width), do: inner_width - x, else: nil

        case row(child, available, {box.style, seq}) do
          {:ok, rendered, child_dims, child_spans} ->
            dims = Enum.reduce(child_dims, dims, fn dim, acc -> [%{dim | left: dim.left + x} | acc] end)
            {:cont, {[%{rendered | left: x, top: 0} | boxes], dims, [child_spans | spans], x + rendered.width}}

          :error ->
            {:halt, :error}
        end
      end)
      |> finish(box, width, seq)
    else
      :error
    end
  end

  defp layout(_, _, _), do: :error

  defp finish(:error, _, _, _), do: :error

  defp finish({children, dims, spans, used}, box, width, seq) do
    left = Geometry.style_value(box.style, :padding_left)
    padding = Geometry.padding_horizontal(box.style)
    width = if width == :auto, do: used + padding, else: width

    if used + padding <= width and seq != "" do
      spans = spans |> Enum.reverse() |> List.flatten()
      spans = if left > 0, do: [{String.duplicate(" ", left), seq} | spans], else: spans
      right = width - used - left
      spans = if right > 0, do: spans ++ [{String.duplicate(" ", right), seq}], else: spans
      children = Enum.map(children, &%{&1 | left: &1.left + left})
      dims = Enum.map(dims, &%{&1 | left: &1.left + left})
      {:ok, rendered(box, width, Enum.reverse(children), spans), [dimension(width) | Enum.reverse(dims)], spans}
    else
      :error
    end
  end

  defp rendered(box, width, children, spans) do
    %{
      box
      | width: width,
        height: 1,
        state: :rendered,
        content: nil,
        children: children,
        layer_map: Scene.from_styled_rows([spans], 0, 0),
        fixed_layer_map: %{},
        overlay?: false
    }
  end

  defp dimension(width),
    do: %{
      width: width,
      viewport_width: width,
      content_width: width,
      height: 1,
      viewport_height: 1,
      content_height: 1,
      left: 0,
      top: 0
    }

  defp supported?(%{style: s} = box) do
    box.state == :ready and box.position == :relative and box.scroll == {0, 0} and
      not box.overlay? and map_size(box.fixed_layer_map) == 0 and
      s.border == BackBreeze.Border.none() and Geometry.padding_vertical(s) == 0 and
      Geometry.style_value(s, :padding_left) >= 0 and Geometry.style_value(s, :padding_right) >= 0 and
      (box.children != [] or Geometry.zero_padding?(s)) and
      s.scrollbar == false and not s.repeat_x and not s.repeat_y and not s.reverse and
      s.height in [0, 1, :auto] and (is_nil(s.max_height) or s.max_height >= 1) and
      s.text_align == :left and (box.children == [] or (not s.bold and not s.italic))
  end

  defp inherit(style, nil), do: style

  defp inherit(style, {parent, _seq}) do
    %{
      style
      | foreground_color: style.foreground_color || parent.foreground_color,
        background_color: style.background_color || parent.background_color
    }
  end

  defp style_sequence(style, {parent, seq})
       when style.foreground_color == parent.foreground_color and
              style.background_color == parent.background_color and
              style.bold == parent.bold and style.italic == parent.italic and
              style.reverse == parent.reverse,
       do: seq

  defp style_sequence(style, _parent), do: LayerMap.content_style_sequence(style)
end
