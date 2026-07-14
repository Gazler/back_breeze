defmodule BackBreeze.Box.PositionedLayout do
  @moduledoc false

  alias BackBreeze.Box.CacheKey
  alias BackBreeze.Box.Geometry
  alias BackBreeze.Box.LayerMap
  alias BackBreeze.RenderCache

  def overlay?(%{position: position}), do: position in [:absolute, :fixed]

  def compose_absolute_children_layer_map(children, opts) do
    rendered_boxes = sorted_rendered_boxes(children, opts)

    {layer_map, fixed_layer_map, max_width, max_height} =
      Enum.reduce(rendered_boxes, {%{}, %{}, 0, 0}, fn box, {layer_map, fixed_layer_map, max_width, max_height} ->
        {start_x, start_y} = {box.left || 0, box.top || 0}

        {map, fixed_map, width, height} =
          merge_positioned_layer_maps(layer_map, fixed_layer_map, box, {start_x, start_y})

        {map, fixed_map, max(max_width, width), max(max_height, height)}
      end)

    {width, height} = composed_layer_map_dimensions(max_width, max_height, opts)

    %{
      width: width,
      height: height,
      layer_map: layer_map,
      fixed_layer_map: fixed_layer_map
    }
  end

  def compose_non_overlapping_children_layer_map(children, opts) do
    rendered_boxes = sorted_rendered_boxes(children, opts)

    case collect_non_overlapping_layer_maps(rendered_boxes) do
      {:ok, layer_map, fills, wide?, max_width, max_height} ->
        layer_map =
          layer_map
          |> LayerMap.put_default_fill_entries(fills)
          |> LayerMap.mark_wide_glyph_metadata(wide?)

        {width, height} = composed_layer_map_dimensions(max_width, max_height, opts)

        {:ok,
         %{
           width: width,
           height: height,
           layer_map: layer_map,
           fixed_layer_map: %{}
         }}

      :error ->
        :error
    end
  end

  def combine_children(box, absolutes, relative, opts) do
    case direct_relative_combine(box, absolutes, relative) do
      {:ok, result} ->
        result

      :error ->
        if CacheKey.combine_children_cacheable?(absolutes) do
          RenderCache.fetch(CacheKey.combine_children_key(box, absolutes, relative, opts), fn ->
            do_combine_children(box, absolutes, relative, opts)
          end)
        else
          do_combine_children(box, absolutes, relative, opts)
        end
    end
  end

  defp direct_relative_combine(box, [], relative) do
    if Geometry.content_origin(box.style) == {0, 0} and relative.position != :fixed and
         LayerMap.content?(relative.layer_map) do
      {:ok,
       {relative.layer_map, fixed_layer_map(relative), max((relative.width || 0) - 1, 0),
        max((relative.height || 0) - 1, 0)}}
    else
      :error
    end
  end

  defp direct_relative_combine(_box, _absolutes, _relative), do: :error

  def resolve_fill_size(%{position: position} = child, parent, opts)
      when position in [:absolute, :fixed] do
    {container_width, container_height} =
      overlay_container_size(child, overlay_layout_context(parent, parent.style.border, opts))

    width =
      constrained_overlay_extent(child.style.width, child.left, child.right, container_width)

    height =
      constrained_overlay_extent(child.style.height, child.top, child.bottom, container_height)

    style =
      child.style
      |> maybe_put_extent(:width, width)
      |> maybe_put_extent(:height, height)

    %{child | style: style}
  end

  def resolve_fill_size(child, _parent, _opts), do: child

  def resolve_fill_offsets(
        %{position: position, style: %{width: :full, height: :full}} = child,
        border
      )
      when position in [:absolute, :fixed] do
    %{
      child
      | left: default_fill_offset(child.left, border.left, position),
        top: default_fill_offset(child.top, border.top, position)
    }
  end

  def resolve_fill_offsets(
        %{position: position, style: %{width: :full}} = child,
        border
      )
      when position in [:absolute, :fixed] do
    %{child | left: default_fill_offset(child.left, border.left, position)}
  end

  def resolve_fill_offsets(
        %{position: position, style: %{height: :full}} = child,
        border
      )
      when position in [:absolute, :fixed] do
    %{child | top: default_fill_offset(child.top, border.top, position)}
  end

  def resolve_fill_offsets(child, _border), do: child

  def resolve_origin(child, parent, rendered_parent, opts) do
    child
    |> resolve_overlay_origin(overlay_layout_context(parent, rendered_parent, parent.style.border, opts))
  end

  defp sorted_rendered_boxes(children, opts) do
    if Keyword.get(opts, :sorted, false) do
      children
    else
      Enum.sort_by(children, & &1.layer)
    end
  end

  defp composed_layer_map_dimensions(max_width, max_height, opts) do
    clip? = Keyword.get(opts, :clip, false)

    {
      composed_layer_map_extent(max_width, Keyword.get(opts, :width), clip?) + 1,
      composed_layer_map_extent(max_height, Keyword.get(opts, :height), clip?) + 1
    }
  end

  defp composed_layer_map_extent(_current_extent, target_extent, true)
       when is_integer(target_extent) do
    max(target_extent - 1, 0)
  end

  defp composed_layer_map_extent(current_extent, target_extent, _clip?)
       when is_integer(target_extent) do
    max(current_extent, target_extent - 1)
  end

  defp composed_layer_map_extent(current_extent, _target_extent, _clip?), do: current_extent

  defp do_combine_children(box, [], relative, _opts) do
    {start_x, start_y} = Geometry.content_origin(box.style)

    merge_positioned_layer_maps(%{}, %{}, relative, {start_x, start_y})
  end

  defp do_combine_children(box, [absolute], relative, opts) do
    {rel_x, rel_y} = Geometry.content_origin(box.style)
    {overlay_x, overlay_y} = resolve_origin(absolute, box, relative, opts)

    {base_map, base_fixed_map, base_width, base_height} =
      merge_positioned_layer_maps(%{}, %{}, relative, {rel_x, rel_y})

    {map, fixed_map, width, height} =
      merge_positioned_layer_maps(base_map, base_fixed_map, absolute, {overlay_x, overlay_y})

    {map, fixed_map, max(base_width, width), max(base_height, height)}
  end

  defp do_combine_children(box, [absolute_one, absolute_two], relative, opts) do
    [first_box, second_box, third_box] =
      Enum.sort_by([relative, absolute_one, absolute_two], & &1.layer)

    merge_rendered_boxes(
      [first_box, second_box, third_box],
      merge_render_context(box, relative, opts)
    )
  end

  defp do_combine_children(box, absolutes, relative, opts) do
    rendered_boxes = [relative | absolutes] |> Enum.sort_by(& &1.layer)
    merge_rendered_boxes(rendered_boxes, merge_render_context(box, relative, opts))
  end

  defp merge_render_context(box, relative, opts) do
    %{box: box, relative: relative, opts: opts}
  end

  defp merge_rendered_boxes(rendered_boxes, context) do
    state =
      Enum.reduce(rendered_boxes, empty_merge_state(), fn rendered_box, state ->
        merge_rendered_box(state, rendered_box, context)
      end)

    {state.layer_map, state.fixed_layer_map, state.max_width, state.max_height}
  end

  defp empty_merge_state do
    %{layer_map: %{}, fixed_layer_map: %{}, max_width: 0, max_height: 0}
  end

  defp merge_rendered_box(state, rendered_box, context) do
    %{box: box, relative: relative, opts: opts} = context

    {start_x, start_y} =
      if overlay?(rendered_box) do
        resolve_origin(rendered_box, box, relative, opts)
      else
        Geometry.content_origin(box.style)
      end

    {map, fixed_map, width, height} =
      merge_positioned_layer_maps(
        state.layer_map,
        state.fixed_layer_map,
        rendered_box,
        {start_x, start_y}
      )

    %{
      state
      | layer_map: map,
        fixed_layer_map: fixed_map,
        max_width: max(state.max_width, width),
        max_height: max(state.max_height, height)
    }
  end

  defp collect_non_overlapping_layer_maps(children) do
    children
    |> do_collect_non_overlapping_layer_maps(empty_non_overlapping_state())
    |> finish_non_overlapping_layer_maps()
  end

  defp do_collect_non_overlapping_layer_maps([], state), do: state

  defp do_collect_non_overlapping_layer_maps([child | rest], state) do
    case non_overlapping_child_entry(child, state.rects) do
      {:ok, entry} ->
        next_state = append_non_overlapping_child_entry(state, entry)
        do_collect_non_overlapping_layer_maps(rest, next_state)

      :error ->
        :error
    end
  end

  defp non_overlapping_child_entry(child, rects) do
    with true <- child.position != :fixed,
         true <- not child.overlay?,
         true <- not LayerMap.entries?(fixed_layer_map(child)),
         true <- LayerMap.entries?(child.layer_map),
         left when is_integer(left) <- child.left || 0,
         top when is_integer(top) <- child.top || 0,
         width when is_integer(width) <- child.width,
         height when is_integer(height) <- child.height,
         rect = {left, top, left + max(width - 1, 0), top + max(height - 1, 0)},
         false <- rect_overlaps_any?(rect, rects) do
      {child_map, child_fills, child_wide?} =
        LayerMap.shift_simple_child(child.layer_map, left, top)

      {:ok,
       %{
         layer_map: child_map,
         fills: child_fills,
         wide?: child_wide?,
         rect: rect
       }}
    else
      _ -> :error
    end
  end

  defp append_non_overlapping_child_entry(state, entry) do
    %{
      state
      | layer_map: Map.merge(state.layer_map, entry.layer_map),
        fills: entry.fills ++ state.fills,
        wide?: state.wide? or entry.wide?,
        rects: [entry.rect | state.rects],
        max_width: max(state.max_width, elem(entry.rect, 2)),
        max_height: max(state.max_height, elem(entry.rect, 3))
    }
  end

  defp finish_non_overlapping_layer_maps(:error), do: :error

  defp finish_non_overlapping_layer_maps(%{
         layer_map: layer_map,
         fills: fills,
         wide?: wide?,
         max_width: max_width,
         max_height: max_height
       }) do
    {:ok, layer_map, fills, wide?, max_width, max_height}
  end

  defp empty_non_overlapping_state do
    %{layer_map: %{}, fills: [], wide?: false, rects: [], max_width: 0, max_height: 0}
  end

  defp rect_overlaps_any?(rect, rects), do: Enum.any?(rects, &rect_overlaps?(rect, &1))

  defp rect_overlaps?({left1, top1, right1, bottom1}, {left2, top2, right2, bottom2}) do
    left1 <= right2 and right1 >= left2 and top1 <= bottom2 and bottom1 >= top2
  end

  defp merge_positioned_layer_maps(layer_map, fixed_layer_map, rendered_box, {start_x, start_y}) do
    fixed_layer_map =
      clear_fixed_layer_map_under_normal(fixed_layer_map, rendered_box, start_x, start_y)

    {normal_map, normal_width, normal_height} =
      merge_normal_layer_map(layer_map, rendered_box, start_x, start_y)

    {fixed_map, _fixed_width, _fixed_height} =
      merge_fixed_layer_map(fixed_layer_map, rendered_box, start_x, start_y)

    {normal_map, fixed_map, normal_width, normal_height}
  end

  defp clear_fixed_layer_map_under_normal(
         fixed_layer_map,
         %{position: :fixed},
         _start_x,
         _start_y
       ),
       do: fixed_layer_map

  defp clear_fixed_layer_map_under_normal(fixed_layer_map, _rendered_box, _start_x, _start_y)
       when map_size(fixed_layer_map) == 0,
       do: fixed_layer_map

  defp clear_fixed_layer_map_under_normal(fixed_layer_map, rendered_box, start_x, start_y) do
    cond do
      LayerMap.content?(rendered_box.layer_map) ->
        LayerMap.clear_covered_by_source(
          fixed_layer_map,
          rendered_box.layer_map,
          {start_x, start_y}
        )

      LayerMap.content?(fixed_layer_map(rendered_box)) ->
        fixed_layer_map

      is_binary(rendered_box.content) and rendered_box.content != "" ->
        {source_map, _max_x, _max_y} = LayerMap.cached_generate(rendered_box.content)
        LayerMap.clear_covered_by_source(fixed_layer_map, source_map, {start_x, start_y})

      true ->
        fixed_layer_map
    end
  end

  defp merge_normal_layer_map(layer_map, %{position: :fixed}, _start_x, _start_y) do
    {layer_map, LayerMap.max_x(layer_map), LayerMap.max_y(layer_map)}
  end

  defp merge_normal_layer_map(layer_map, rendered_box, start_x, start_y) do
    cond do
      LayerMap.content?(rendered_box.layer_map) and map_size(layer_map) == 0 and start_x == 0 and
          start_y == 0 ->
        {rendered_box.layer_map, max((rendered_box.width || 0) - 1, 0), max((rendered_box.height || 0) - 1, 0)}

      LayerMap.content?(rendered_box.layer_map) ->
        LayerMap.merge(layer_map, rendered_box.layer_map, {start_x, start_y})

      LayerMap.content?(fixed_layer_map(rendered_box)) ->
        {layer_map, LayerMap.max_x(layer_map), LayerMap.max_y(layer_map)}

      true ->
        LayerMap.generate(rendered_box.content, layer_map, start_x, start_y)
    end
  end

  defp merge_fixed_layer_map(fixed_layer_map, rendered_box, start_x, start_y) do
    {fixed_layer_map, width, height} =
      merge_existing_fixed_layer_map(fixed_layer_map, rendered_box)

    case rendered_box do
      %{position: :fixed, layer_map: layer_map} when is_map(layer_map) ->
        {map, box_width, box_height} =
          if LayerMap.content?(layer_map) do
            LayerMap.merge(fixed_layer_map, layer_map, {start_x, start_y})
          else
            LayerMap.generate(rendered_box.content, fixed_layer_map, start_x, start_y)
          end

        {map, max(width, box_width), max(height, box_height)}

      _ ->
        {fixed_layer_map, width, height}
    end
  end

  defp merge_existing_fixed_layer_map(fixed_layer_map, rendered_box) do
    case fixed_layer_map(rendered_box) do
      map when map_size(map) == 0 ->
        {fixed_layer_map, LayerMap.max_x(fixed_layer_map), LayerMap.max_y(fixed_layer_map)}

      map ->
        current_width = LayerMap.max_x(fixed_layer_map)
        current_height = LayerMap.max_y(fixed_layer_map)
        {merged, width, height} = LayerMap.merge(fixed_layer_map, map, {0, 0})
        {merged, max(current_width, width), max(current_height, height)}
    end
  end

  defp fixed_layer_map(%{fixed_layer_map: fixed_layer_map}) when is_map(fixed_layer_map),
    do: fixed_layer_map

  defp fixed_layer_map(_box), do: %{}

  defp overlay_layout_context(parent, border, opts) do
    overlay_layout_context(parent, nil, border, opts)
  end

  defp overlay_layout_context(parent, rendered_parent, border, opts) do
    %{parent: parent, rendered_parent: rendered_parent, border: border, opts: opts}
  end

  defp resolve_overlay_origin(child, context) do
    {container_width, container_height} = overlay_container_size(child, context)

    {
      resolve_edge_offset(child.left, child.right, child.width, container_width),
      resolve_edge_offset(child.top, child.bottom, child.height, container_height)
    }
  end

  defp overlay_container_size(%{position: :fixed}, %{opts: opts}) do
    BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
  end

  defp overlay_container_size(_child, %{
         parent: parent,
         rendered_parent: rendered_parent,
         border: border,
         opts: opts
       }) do
    width =
      first_size(
        rendered_parent && rendered_parent.width,
        parent.width,
        resolved_parent_overlay_extent(parent, :width, border, opts)
      )

    height =
      first_size(
        rendered_parent && rendered_parent.height,
        parent.height,
        resolved_parent_overlay_extent(parent, :height, border, opts)
      )

    {
      resolved_overlay_width(width, border, opts),
      resolved_overlay_height(height, border, opts)
    }
  end

  defp resolved_overlay_width(width, _border, _opts) when is_integer(width), do: width

  defp resolved_overlay_width(:screen, _border, opts) do
    {screen_width, _screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
    screen_width
  end

  defp resolved_overlay_width(_, _border, _opts), do: 0

  defp resolved_overlay_height(height, _border, _opts) when is_integer(height), do: height

  defp resolved_overlay_height(:screen, _border, opts) do
    {_screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
    screen_height
  end

  defp resolved_overlay_height(_, _border, _opts), do: 0

  defp resolved_parent_overlay_extent(%{position: :fixed} = parent, :width, _border, opts) do
    {screen_width, _screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    constrained_overlay_extent(
      parent.style.width,
      parent.left,
      parent.right,
      screen_width
    ) || resolved_overlay_width(parent.style.width, parent.style.border, opts)
  end

  defp resolved_parent_overlay_extent(%{position: :fixed} = parent, :height, _border, opts) do
    {_screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    constrained_overlay_extent(
      parent.style.height,
      parent.top,
      parent.bottom,
      screen_height
    ) || resolved_overlay_height(parent.style.height, parent.style.border, opts)
  end

  defp resolved_parent_overlay_extent(parent, :width, _border, opts),
    do: Map.get(parent.style, :width) |> resolved_overlay_width(parent.style.border, opts)

  defp resolved_parent_overlay_extent(parent, :height, _border, opts),
    do: Map.get(parent.style, :height) |> resolved_overlay_height(parent.style.border, opts)

  defp constrained_overlay_extent(extent, start_edge, end_edge, container_extent)
       when extent in [:screen, :full] and is_integer(start_edge) and is_integer(end_edge) and
              is_integer(container_extent) do
    max(container_extent - start_edge - end_edge, 0)
  end

  defp constrained_overlay_extent(extent, start_edge, end_edge, container_extent)
       when is_integer(extent) and is_integer(start_edge) and is_integer(end_edge) and
              is_integer(container_extent) and extent >= container_extent do
    max(container_extent - start_edge - end_edge, 0)
  end

  defp constrained_overlay_extent(_extent, _start_edge, _end_edge, _container_extent), do: nil

  defp maybe_put_extent(style, _field, nil), do: style
  defp maybe_put_extent(style, field, value), do: Map.put(style, field, value)

  defp default_fill_offset(nil, edge, :absolute), do: if(edge, do: 1, else: 0)
  defp default_fill_offset(0, edge, :absolute), do: if(edge, do: 1, else: 0)
  defp default_fill_offset(nil, _edge, :fixed), do: 0
  defp default_fill_offset(0, _edge, :fixed), do: 0
  defp default_fill_offset(offset, _edge, _position), do: offset

  defp resolve_edge_offset(value, _opposite, _child_size, _container_size) when is_integer(value),
    do: value

  defp resolve_edge_offset(:center, _opposite, child_size, container_size)
       when is_integer(child_size) and is_integer(container_size) do
    max(div(container_size - child_size, 2), 0)
  end

  defp resolve_edge_offset(nil, opposite, child_size, container_size)
       when is_integer(opposite) and is_integer(child_size) and is_integer(container_size) do
    max(container_size - child_size - opposite, 0)
  end

  defp resolve_edge_offset(_, _, _, _), do: 0

  defp first_size(value, _fallback, _final) when is_integer(value) and value > 0, do: value
  defp first_size(:screen, _fallback, _final), do: :screen

  defp first_size(_value, fallback, _final) when is_integer(fallback) and fallback > 0,
    do: fallback

  defp first_size(_value, :screen, _final), do: :screen
  defp first_size(_value, _fallback, final), do: final
end
