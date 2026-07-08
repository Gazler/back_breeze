defmodule BackBreeze.Box.BlockLayerMap do
  @moduledoc false

  alias BackBreeze.BenchProfile
  alias BackBreeze.Box.LayerMap
  alias BackBreeze.Box.TextMetrics

  def retain_for_combine?(
        box,
        %{
          relative: relative,
          absolutes: absolutes,
          relative_has_overlay?: relative_has_overlay?,
          structured?: structured?
        }
      ) do
    (structured? and structured_scrolled?(box, relative)) or
      (structured?(box, relative) and
         (structured? or
            ((absolutes != [] or relative_has_overlay?) and
               Enum.any?(relative, &rendered_layer_map_entries?/1))))
  end

  def compose(relative, box) do
    if structured_scrolled?(box, relative) do
      compose_scrolled(relative, box)
    else
      compose_unscrolled(relative, box)
    end
  end

  defp structured?(box, relative) do
    match?(:block, box.display) and box.scroll == {0, 0} and relative != []
  end

  defp structured_scrolled?(box, relative) do
    match?(:block, box.display) and
      match?({top, 0} when top != 0, box.scroll) and
      box.style.overflow == :hidden and
      relative != [] and
      scrolled_viewport?(box) and
      Enum.all?(relative, &scrolled_child_supported?/1)
  end

  defp scrolled_viewport?(box) do
    match?(width when is_integer(width) and width > 0, resolved_parent_width(box, [])) and
      match?(height when is_integer(height) and height > 0, resolved_parent_height(box, []))
  end

  defp scrolled_child_supported?(child) do
    not layer_map_entries?(fixed_layer_map(child)) and
      not child.overlay? and
      is_integer(child.left || 0) and
      is_integer(child.top || 0) and
      is_integer(child.height) and
      is_integer(child.width) and
      (layer_map_entries?(child.layer_map) or default_fill_entries(child.layer_map) != [] or
         is_binary(child.content) or child.content in [nil, ""])
  end

  defp compose_unscrolled(relative, box) do
    children = absolutize_relative_children(relative, box)

    case compose_simple_children(children) do
      {_, _, _, _} = result ->
        result

      :error ->
        %{
          width: width,
          height: height,
          layer_map: layer_map,
          fixed_layer_map: fixed_layer_map
        } = BackBreeze.Box.compose_absolute_children_layer_map(children, sorted: true)

        {width, height, layer_map, fixed_layer_map}
    end
  end

  defp compose_scrolled(relative, box) do
    BenchProfile.measure({__MODULE__, :compose_scrolled}, fn ->
      do_compose_scrolled(relative, box)
    end)
  end

  defp do_compose_scrolled(relative, box) do
    children = absolutize_relative_children(relative, box)
    {scroll_top, scroll_left} = box.scroll
    {total_width, total_height} = children_extent(children)

    with viewport_width when is_integer(viewport_width) and viewport_width > 0 <-
           resolved_parent_width(box, []),
         viewport_height when is_integer(viewport_height) and viewport_height > 0 <-
           resolved_parent_height(box, []),
         viewport = %{
           scroll_left: scroll_left,
           scroll_top: scroll_top,
           width: viewport_width,
           height: viewport_height
         },
         {:ok, layer_map, fills, wide?, _max_width, _max_height} <-
           compose_scrolled_child_layer_maps(children, viewport) do
      layer_map =
        layer_map
        |> LayerMap.put_default_fill_entries(fills)
        |> LayerMap.mark_wide_glyph_metadata(wide?)
        |> LayerMap.filter(%{
          start_x: 0,
          start_y: 0,
          max_x: viewport_width - 1,
          max_y: viewport_height - 1
        })

      {max(total_width, viewport_width), max(total_height, viewport_height), layer_map, %{}}
    else
      _ -> compose_unscrolled(relative, %{box | scroll: {0, 0}})
    end
  end

  defp absolutize_relative_children(relative, box) do
    {content_left, content_top} = content_origin(box.style)

    Enum.map(relative, fn child ->
      %{
        child
        | position: :absolute,
          left: max((child.left || 0) - content_left, 0),
          top: max((child.top || 0) - content_top, 0)
      }
    end)
  end

  defp children_extent(children) do
    Enum.reduce(children, {0, 0}, fn child, {max_width, max_height} ->
      {
        max(max_width, (child.left || 0) + (child.width || 0)),
        max(max_height, (child.top || 0) + (child.height || 0))
      }
    end)
  end

  defp compose_simple_children(children) do
    case compose_simple_child_layer_maps(children) do
      :error ->
        children
        |> simple_items()
        |> case do
          {:ok, items, width, height} ->
            content =
              items
              |> Enum.reverse()
              |> Enum.intersperse("\n")
              |> IO.iodata_to_binary()

            {layer_map, max_x, max_y} = LayerMap.generate(content, %{}, 0, 0)
            {max(width, max_x + 1), max(height, max_y + 1), layer_map, %{}}

          :error ->
            :error
        end

      result ->
        result
    end
  end

  defp compose_simple_child_layer_maps(children) do
    children
    |> do_compose_simple_child_layer_maps(empty_simple_state())
    |> finish_simple_layer_map()
  end

  defp do_compose_simple_child_layer_maps([], state), do: state

  defp do_compose_simple_child_layer_maps([child | rest], state) do
    case simple_child_entry(child, state.height) do
      {:ok, entry} ->
        next_state = append_simple_child_entry(state, entry)
        do_compose_simple_child_layer_maps(rest, next_state)

      :error ->
        :error
    end
  end

  defp simple_child_entry(child, expected_top) do
    cond do
      not simple_child_position?(child, expected_top) ->
        :error

      layer_map_entries?(fixed_layer_map(child)) ->
        :error

      child.overlay? ->
        :error

      not is_integer(child.height) or not is_integer(child.width) ->
        :error

      true ->
        simple_child_entry(child, child.height, child.width)
    end
  end

  defp simple_child_entry(child, height, width) do
    case simple_child_layer_map(child) do
      {:ok, child_map, child_fills, child_wide?, child_width} ->
        {:ok,
         %{
           type: :layer_map,
           height: height,
           width: width,
           child_width: child_width,
           layer_map: child_map,
           fills: child_fills,
           wide?: child_wide?
         }}

      :blank ->
        {:ok, %{type: :blank, height: height, width: width}}

      :error ->
        :error
    end
  end

  defp append_simple_child_entry(state, %{type: :blank, height: height, width: width}) do
    %{state | height: state.height + height, width: max(state.width, width)}
  end

  defp append_simple_child_entry(state, %{
         type: :layer_map,
         height: height,
         width: width,
         child_width: child_width,
         layer_map: child_map,
         fills: child_fills,
         wide?: child_wide?
       }) do
    %{
      state
      | layer_map: Map.merge(state.layer_map, child_map),
        fills: child_fills ++ state.fills,
        wide?: state.wide? or child_wide?,
        height: state.height + height,
        width: max(state.width, max(width, child_width))
    }
  end

  defp finish_simple_layer_map(:error), do: :error

  defp finish_simple_layer_map(%{
         layer_map: layer_map,
         fills: fills,
         wide?: wide?,
         height: height,
         width: width
       }) do
    layer_map =
      layer_map
      |> LayerMap.put_default_fill_entries(fills)
      |> LayerMap.mark_wide_glyph_metadata(wide?)

    {width, height, layer_map, %{}}
  end

  defp empty_simple_state do
    %{layer_map: %{}, fills: [], wide?: false, height: 0, width: 0}
  end

  defp compose_scrolled_child_layer_maps(children, %{
         scroll_left: scroll_left,
         scroll_top: scroll_top,
         width: viewport_width,
         height: viewport_height
       }) do
    viewport = %{
      left: scroll_left,
      top: scroll_top,
      right: scroll_left + viewport_width - 1,
      bottom: scroll_top + viewport_height - 1
    }

    scroll = %{left: scroll_left, top: scroll_top}

    children
    |> do_compose_scrolled_child_layer_maps(empty_scrolled_state(), viewport, scroll)
    |> finish_scrolled_layer_map()
  end

  defp do_compose_scrolled_child_layer_maps([], state, _viewport, _scroll), do: state

  defp do_compose_scrolled_child_layer_maps([child | rest], state, viewport, scroll) do
    case scrolled_child_entry(child, viewport, scroll) do
      {:ok, entry} ->
        next_state = append_scrolled_child_entry(state, entry)
        do_compose_scrolled_child_layer_maps(rest, next_state, viewport, scroll)

      :error ->
        :error
    end
  end

  defp scrolled_child_entry(child, viewport, scroll) do
    with true <- not layer_map_entries?(fixed_layer_map(child)),
         true <- not child.overlay?,
         left when is_integer(left) <- child.left || 0,
         top when is_integer(top) <- child.top || 0,
         height when is_integer(height) <- child.height,
         width when is_integer(width) <- child.width do
      rect = {left, top, left + max(width - 1, 0), top + max(height - 1, 0)}
      bounds = %{max_width: elem(rect, 2) + 1, max_height: elem(rect, 3) + 1}

      if rect_overlaps?(rect, {viewport.left, viewport.top, viewport.right, viewport.bottom}) do
        visible_scrolled_child_entry(child, bounds, scroll)
      else
        {:ok, Map.put(bounds, :type, :hidden)}
      end
    else
      _ -> :error
    end
  end

  defp visible_scrolled_child_entry(child, bounds, scroll) do
    case simple_child_layer_map(child) do
      {:ok, child_map, child_fills, child_wide?, _child_width} ->
        {shifted_map, shifted_fills, shifted_wide?} =
          LayerMap.shift_simple_child(child_map, -scroll.left, -scroll.top)

        shifted_fills =
          LayerMap.shifted_default_fill_entries(child_fills, -scroll.left, -scroll.top) ++
            shifted_fills

        {:ok,
         Map.merge(bounds, %{
           type: :layer_map,
           layer_map: shifted_map,
           fills: shifted_fills,
           wide?: child_wide? or shifted_wide?
         })}

      :blank ->
        {:ok, Map.put(bounds, :type, :blank)}

      :error ->
        :error
    end
  end

  defp append_scrolled_child_entry(state, %{type: :layer_map} = entry) do
    %{
      state
      | layer_map: Map.merge(state.layer_map, entry.layer_map),
        fills: entry.fills ++ state.fills,
        wide?: state.wide? or entry.wide?,
        max_width: max(state.max_width, entry.max_width),
        max_height: max(state.max_height, entry.max_height)
    }
  end

  defp append_scrolled_child_entry(state, %{max_width: max_width, max_height: max_height}) do
    %{
      state
      | max_width: max(state.max_width, max_width),
        max_height: max(state.max_height, max_height)
    }
  end

  defp finish_scrolled_layer_map(:error), do: :error

  defp finish_scrolled_layer_map(%{
         layer_map: layer_map,
         fills: fills,
         wide?: wide?,
         max_width: max_width,
         max_height: max_height
       }) do
    {:ok, layer_map, fills, wide?, max_width, max_height}
  end

  defp empty_scrolled_state do
    %{layer_map: %{}, fills: [], wide?: false, max_width: 0, max_height: 0}
  end

  defp simple_child_layer_map(child) do
    cond do
      layer_map_entries?(child.layer_map) or default_fill_entries(child.layer_map) != [] ->
        {child_map, child_fills, child_wide?} =
          LayerMap.shift_simple_child(child.layer_map, child.left || 0, child.top || 0)

        {:ok, child_map, child_fills, child_wide?, child.width || 0}

      is_binary(child.content) and child.content != "" ->
        {content_map, max_x, _max_y} = LayerMap.cached_generate(child.content)

        {child_map, child_fills, child_wide?} =
          LayerMap.shift_simple_child(content_map, child.left || 0, child.top || 0)

        {:ok, child_map, child_fills, child_wide?, max_x + 1}

      child.content in ["", nil] ->
        :blank

      true ->
        :error
    end
  end

  defp simple_items(children) do
    initial_state = %{items: [], expected_top: 0, max_width: 0, total_height: 0}

    children
    |> Enum.reduce_while(initial_state, &simple_item/2)
    |> case do
      %{items: items, max_width: max_width, total_height: total_height} ->
        {:ok, items, max_width, total_height}

      :error ->
        :error
    end
  end

  defp simple_item(child, state) do
    with true <- simple_child_position?(child, state.expected_top),
         true <- not layer_map_entries?(fixed_layer_map(child)),
         true <- not child.overlay?,
         height when is_integer(height) <- child.height do
      item = materialized_content(child)
      {item_width, item_height} = TextMetrics.metrics(item)

      if item_height == height do
        {:cont,
         %{
           state
           | items: [item | state.items],
             expected_top: state.expected_top + height,
             max_width: max(state.max_width, item_width),
             total_height: state.total_height + item_height
         }}
      else
        {:halt, :error}
      end
    else
      _ -> {:halt, :error}
    end
  end

  defp simple_child_position?(child, expected_top) do
    child.position == :absolute and (child.left || 0) == 0 and (child.top || 0) == expected_top
  end

  defp materialized_content(%{content: content}) when is_binary(content), do: content

  defp materialized_content(%{layer_map: layer_map, width: width, height: height}) do
    LayerMap.to_content(layer_map, width, height)
  end

  defp materialized_content(_child), do: ""

  defp rendered_layer_map_entries?(box) do
    layer_map_entries?(box.layer_map) or layer_map_entries?(fixed_layer_map(box))
  end

  defp fixed_layer_map(%{fixed_layer_map: fixed_layer_map}) when is_map(fixed_layer_map),
    do: fixed_layer_map

  defp fixed_layer_map(_box), do: %{}

  defp layer_map_entries?(layer_map), do: LayerMap.entries?(layer_map)
  defp default_fill_entries(layer_map), do: LayerMap.default_fill_entries(layer_map)

  defp rect_overlaps?({left1, top1, right1, bottom1}, {left2, top2, right2, bottom2}) do
    left1 <= right2 and right1 >= left2 and top1 <= bottom2 and bottom1 >= top2
  end

  defp resolved_parent_width(%{width: rendered_width, style: style}, _opts)
       when is_integer(rendered_width) do
    max(rendered_width - border_horizontal(style.border) - padding_horizontal(style), 0)
  end

  defp resolved_parent_width(%{style: %{width: width} = style}, opts) do
    case width do
      w when is_integer(w) ->
        max(w - border_horizontal(style.border) - padding_horizontal(style), 0)

      extent when extent in [:screen, :full] ->
        {screen_width, _screen_height} =
          BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

        max(screen_width - border_horizontal(style.border) - padding_horizontal(style), 0)

      _ ->
        nil
    end
  end

  defp resolved_parent_height(%{height: rendered_height, style: style}, _opts)
       when is_integer(rendered_height) do
    max(rendered_height - border_vertical(style.border) - padding_vertical(style), 0)
  end

  defp resolved_parent_height(%{style: %{height: height} = style}, opts) do
    case height do
      h when is_integer(h) ->
        max(h - border_vertical(style.border) - padding_vertical(style), 0)

      extent when extent in [:screen, :full] ->
        {_screen_width, screen_height} =
          BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

        max(screen_height - border_vertical(style.border) - padding_vertical(style), 0)

      _ ->
        nil
    end
  end

  defp border_horizontal(border),
    do: if(border.left, do: 1, else: 0) + if(border.right, do: 1, else: 0)

  defp border_vertical(border),
    do: if(border.top, do: 1, else: 0) + if(border.bottom, do: 1, else: 0)

  defp padding_horizontal(style),
    do: style_value(style, :padding_left) + style_value(style, :padding_right)

  defp padding_vertical(style),
    do: style_value(style, :padding_top) + style_value(style, :padding_bottom)

  defp content_origin(style) do
    {
      if(style.border.left, do: 1, else: 0) + style_value(style, :padding_left),
      if(style.border.top, do: 1, else: 0) + style_value(style, :padding_top)
    }
  end

  defp style_value(style, side_key) do
    case Map.get(style, side_key) do
      value when is_integer(value) -> value
      _ -> Map.get(style, :padding, 0) || 0
    end
  end
end
