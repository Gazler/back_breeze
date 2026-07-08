defmodule BackBreeze.Box.LayerMap do
  @moduledoc false

  alias BackBreeze.RenderCache
  alias BackBreeze.Ucwidth

  @wide_glyph_key :__wide_glyphs__
  @default_fill_key :__default_fill__

  def merge(target_map, source_map, {offset_x, offset_y}) do
    target_map = clear_fill_covered_cells(target_map, source_map, offset_x, offset_y)
    wide_glyphs? = has_wide_glyphs?(target_map) or has_wide_glyphs?(source_map)

    context = %{
      offset_x: offset_x,
      offset_y: offset_y,
      preserve_plain_spaces?: has_wide_glyphs?(source_map) or map_size(target_map) == 0
    }

    {map, max_x, max_y} =
      Enum.reduce(source_map, {target_map, 0, 0}, &merge_entry(&1, &2, context))

    map =
      map
      |> mark_wide_glyph_metadata(wide_glyphs?)
      |> merge_default_fills(target_map, source_map, {offset_x, offset_y})

    {map, max(max_x, max_x(map)), max(max_y, max_y(map))}
  end

  def clear_covered_by_source(target_map, source_map, {offset_x, offset_y}) do
    coverage_rects = layer_map_coverage_rects(source_map, offset_x, offset_y)

    if coverage_rects == [] do
      target_map
    else
      target_map
      |> Enum.reduce(%{}, &clear_covered_entry(&1, &2, coverage_rects))
      |> put_uncovered_default_fills(target_map, coverage_rects)
      |> mark_wide_glyph_metadata(has_wide_glyphs?(target_map))
    end
  end

  def generate(nil, layer_map, _start_x, _y) do
    {layer_map, max(max_x(layer_map), 0), max(max_y(layer_map), 0)}
  end

  def generate(content, layer_map, start_x, y) do
    reset = Termite.Style.reset_code()

    {_x, y, {acc, max_x, _, _, _}} =
      generate_binary(content, layer_map, start_x, start_x, y, 1, false, "", reset, reset)

    compact_full_surface_fill(acc, max_x - 1, y)
  end

  def cached_generate(content, start_x \\ 0, start_y \\ 0, layer_map \\ %{})

  def cached_generate(content, start_x, start_y, layer_map)
      when is_binary(content) and map_size(layer_map) == 0 do
    if start_x == 0 and start_y == 0 do
      RenderCache.fetch_stable({:generate_layer_map, content}, fn ->
        generate(content, %{}, 0, 0)
      end)
    else
      generate(content, %{}, start_x, start_y)
    end
  end

  def cached_generate(content, start_x, start_y, layer_map) do
    generate(content, layer_map, start_x, start_y)
  end

  def cached_blank_container(box, width, height) do
    RenderCache.fetch_stable({:blank_container_layer_map, box.style, width, height}, fn ->
      blank_container(box, width, height)
    end)
  end

  def to_content(layer_map, width, height) when is_integer(width) and is_integer(height) do
    cached_to_content(layer_map, %{}, %{
      start_x: 0,
      start_y: 0,
      max_x: width - 1,
      max_y: height - 1
    })
  end

  def to_content(layer_map, overlay_layer_map, %{} = bounds) do
    do_to_content(layer_map, overlay_layer_map, bounds)
  end

  def to_content(layer_map, overlay_layer_map, width, height) do
    cached_to_content(layer_map, overlay_layer_map, %{
      start_x: 0,
      start_y: 0,
      max_x: width - 1,
      max_y: height - 1
    })
  end

  def cached_to_content(layer_map, overlay_layer_map, bounds) do
    area = (bounds.max_x - bounds.start_x + 1) * (bounds.max_y - bounds.start_y + 1)

    if area >= 256 and (map_size(layer_map) > 0 or map_size(overlay_layer_map) > 0) do
      RenderCache.fetch_stable(
        {:layer_maps_to_content, layer_map, overlay_layer_map, bounds},
        fn -> do_to_content(layer_map, overlay_layer_map, bounds) end
      )
    else
      do_to_content(layer_map, overlay_layer_map, bounds)
    end
  end

  def filter(layer_map, %{start_x: start_x, start_y: start_y, max_x: max_x, max_y: max_y}) do
    bounds = %{start_x: start_x, start_y: start_y, max_x: max_x, max_y: max_y}
    filtered = Enum.reduce(layer_map, %{}, &filter_entry(&1, &2, bounds))

    filtered
    |> mark_wide_glyph_metadata(has_wide_glyphs?(layer_map) and map_size(filtered) > 0)
    |> maybe_clip_default_fill(layer_map, bounds)
  end

  def shift(layer_map, shift_x, shift_y) do
    shift = %{x: shift_x, y: shift_y}
    shifted = Enum.reduce(layer_map, %{}, &shift_entry(&1, &2, shift))

    shifted
    |> mark_wide_glyph_metadata(has_wide_glyphs?(layer_map) and map_size(shifted) > 0)
    |> maybe_shift_default_fill(layer_map, shift_x, shift_y)
  end

  def shift_simple_child(layer_map, shift_x, shift_y) do
    shift = %{x: shift_x, y: shift_y}
    {map, wide?} = Enum.reduce(layer_map, {%{}, false}, &shift_simple_child_entry(&1, &2, shift))

    fills = shifted_default_fill_entries(layer_map, shift_x, shift_y)
    {map, fills, wide?}
  end

  def clip_child(layer_map, %{overflow: :hidden, border: border}, %{max_x: max_x, max_y: max_y})
      when is_integer(max_x) and is_integer(max_y) do
    bounds = child_clip_bounds(border, max_x, max_y)
    clipped = Enum.reduce(layer_map, %{}, &filter_entry(&1, &2, bounds))

    clipped
    |> mark_wide_glyph_metadata(has_wide_glyphs?(layer_map) and map_size(clipped) > 0)
    |> maybe_clip_default_fill(layer_map, bounds)
  end

  def clip_child(layer_map, _style, _bounds), do: layer_map

  def clip_required?(
        %{width: child_width, height: child_height},
        %{border: border},
        %{max_x: max_x, max_y: max_y},
        false
      )
      when is_integer(child_width) and is_integer(child_height) and is_integer(max_x) and
             is_integer(max_y) do
    left = if(border.left, do: 1, else: 0)
    top = if(border.top, do: 1, else: 0)
    right = max(max_x - if(border.right, do: 1, else: 0), left - 1)
    bottom = max(max_y - if(border.bottom, do: 1, else: 0), top - 1)

    child_width > max(right - left + 1, 0) or child_height > max(bottom - top + 1, 0)
  end

  def clip_required?(
        _child,
        _style,
        _bounds,
        _has_overlay_children?
      ),
      do: true

  defp merge_entry({@wide_glyph_key, true}, acc, _context), do: acc
  defp merge_entry({@default_fill_key, _value}, acc, _context), do: acc

  defp merge_entry({{_y, _x}, {" ", ""}}, acc, %{preserve_plain_spaces?: false}), do: acc

  defp merge_entry({{y, x}, {char, _} = value}, {acc, cur_max_x, cur_max_y}, context) do
    shifted_x = x + context.offset_x
    shifted_y = y + context.offset_y
    width = Ucwidth.width(char)
    acc = clear_wide_continuation_cells(acc, shifted_y, shifted_x, width)

    {
      Map.put(acc, {shifted_y, shifted_x}, value),
      max(cur_max_x, shifted_x + width - 1),
      max(cur_max_y, shifted_y)
    }
  end

  defp merge_entry(_entry, acc, _context), do: acc

  defp clear_covered_entry({@wide_glyph_key, true}, acc, _coverage_rects),
    do: Map.put(acc, @wide_glyph_key, true)

  defp clear_covered_entry({@default_fill_key, _value}, acc, _coverage_rects), do: acc

  defp clear_covered_entry({{y, x} = key, value}, acc, coverage_rects) do
    if point_in_any_rect?(x, y, coverage_rects), do: acc, else: Map.put(acc, key, value)
  end

  defp clear_covered_entry(_entry, acc, _coverage_rects), do: acc

  defp filter_entry({@wide_glyph_key, true}, acc, _bounds), do: acc
  defp filter_entry({@default_fill_key, _value}, acc, _bounds), do: acc

  defp filter_entry({{y, x} = key, value}, acc, bounds) do
    if point_in_bounds?(x, y, bounds), do: Map.put(acc, key, value), else: acc
  end

  defp filter_entry(_entry, acc, _bounds), do: acc

  defp shift_entry({@wide_glyph_key, true}, acc, _shift), do: acc
  defp shift_entry({@default_fill_key, _value}, acc, _shift), do: acc

  defp shift_entry({{y, x}, value}, acc, shift) do
    Map.put(acc, {y + shift.y, x + shift.x}, value)
  end

  defp shift_entry(_entry, acc, _shift), do: acc

  defp shift_simple_child_entry({@wide_glyph_key, true}, {acc, _wide?}, _shift), do: {acc, true}
  defp shift_simple_child_entry({@default_fill_key, _value}, acc, _shift), do: acc

  defp shift_simple_child_entry({{y, x}, value}, {acc, wide?}, shift) do
    {Map.put(acc, {y + shift.y, x + shift.x}, value), wide?}
  end

  defp shift_simple_child_entry(_entry, acc, _shift), do: acc

  defp child_clip_bounds(border, max_x, max_y) do
    left = if border.left, do: 1, else: 0
    top = if border.top, do: 1, else: 0

    %{
      start_x: left,
      start_y: top,
      max_x: max(max_x - if(border.right, do: 1, else: 0), left - 1),
      max_y: max(max_y - if(border.bottom, do: 1, else: 0), top - 1)
    }
  end

  defp point_in_bounds?(x, y, bounds) do
    x >= bounds.start_x and x <= bounds.max_x and y >= bounds.start_y and y <= bounds.max_y
  end

  def put_default_fill_entries(layer_map, []), do: Map.delete(layer_map, @default_fill_key)

  def put_default_fill_entries(layer_map, fills) do
    Map.put(layer_map, @default_fill_key, normalize_default_fill_entries(fills))
  end

  def has_wide_glyphs?(layer_map) when is_map(layer_map),
    do: Map.get(layer_map, @wide_glyph_key, false)

  def has_wide_glyphs?(_layer_map), do: false

  def entries?(layer_map) when is_map(layer_map),
    do: map_size(layer_map) > metadata_count(layer_map)

  def entries?(_layer_map), do: false

  def content?(layer_map) when is_map(layer_map) do
    entries?(layer_map) or default_fill_entries(layer_map) != []
  end

  def content?(_layer_map), do: false

  def height(layer_map) when map_size(layer_map) == 0, do: nil

  def height(layer_map) do
    explicit_max_y =
      Enum.reduce(layer_map, nil, fn
        {{y, _x}, _value}, nil -> y
        {{y, _x}, _value}, acc -> max(acc, y)
        _, acc -> acc
      end)

    fill_max_y =
      case default_fill_entries(layer_map) do
        [] -> nil
        fills -> fills |> Enum.map(&elem(&1, 4)) |> Enum.max()
      end

    case Enum.reject([explicit_max_y, fill_max_y], &is_nil/1) do
      [] -> nil
      values -> Enum.max(values) + 1
    end
  end

  def max_x(layer_map) when map_size(layer_map) == 0, do: -1

  def max_x(layer_map) do
    explicit_max_x =
      Enum.reduce(layer_map, nil, fn
        {{_y, x}, _value}, nil -> x
        {{_y, x}, _value}, acc -> max(acc, x)
        _, acc -> acc
      end)

    fill_max_x =
      case default_fill_entries(layer_map) do
        [] -> nil
        fills -> fills |> Enum.map(&elem(&1, 3)) |> Enum.max()
      end

    case Enum.reject([explicit_max_x, fill_max_x], &is_nil/1) do
      [] -> -1
      values -> Enum.max(values)
    end
  end

  def max_y(layer_map) do
    case height(layer_map) do
      nil -> -1
      height -> height - 1
    end
  end

  def default_fill_entries(layer_map) when is_map(layer_map) do
    layer_map
    |> Map.get(@default_fill_key)
    |> default_fill_entries()
  end

  def default_fill_entries(nil), do: []
  def default_fill_entries([]), do: []
  def default_fill_entries([_ | _] = fills), do: fills
  def default_fill_entries({_point, _left, _top, _right, _bottom} = fill), do: [fill]

  def shifted_default_fill_entries(source_map, shift_x, shift_y) do
    source_map
    |> default_fill_entries()
    |> Enum.map(fn
      {{_char, _style} = point, left, top, right, bottom} ->
        {point, left + shift_x, top + shift_y, right + shift_x, bottom + shift_y}
    end)
  end

  def normalize_default_fill_entries(fills) do
    {fills, _seen} =
      Enum.reduce(fills, {[], MapSet.new()}, &normalize_default_fill_entry/2)

    Enum.reverse(fills)
  end

  defp normalize_default_fill_entry(fill, {acc, seen}) do
    if MapSet.member?(seen, fill), do: {acc, seen}, else: {[fill | acc], MapSet.put(seen, fill)}
  end

  def mark_wide_glyph_metadata(map, true) when map_size(map) > 0,
    do: Map.put(map, @wide_glyph_key, true)

  def mark_wide_glyph_metadata(map, _value), do: Map.delete(map, @wide_glyph_key)

  def content_style_sequence(style) do
    []
    |> maybe_add_style(style.bold, &Termite.Style.bold/1)
    |> maybe_add_style(style.italic, &Termite.Style.italic/1)
    |> maybe_add_style(style.reverse, &Termite.Style.reverse/1)
    |> maybe_add_color(style.foreground_color, &Termite.Style.foreground/2)
    |> maybe_add_color(style.background_color, &Termite.Style.background/2)
    |> case do
      [] ->
        ""

      funs ->
        Enum.reduce(funs, Termite.Style.ansi256(), fn fun, acc -> fun.(acc) end)
        |> Termite.Style.render_to_string("")
        |> String.trim_trailing(Termite.Style.reset_code())
    end
  end

  defp blank_container(%{content: "", style: style}, width, height)
       when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    border = blank_container_border(style)
    border_seq = border_style_sequence(border)
    fill_seq = content_style_sequence(style)
    bounds = blank_container_bounds(width, height, border)

    map =
      %{}
      |> maybe_add_blank_container_fill(fill_seq, bounds)
      |> add_blank_container_borders(border, border_seq, width, height, bounds)

    {map, bounds.last_x, bounds.last_y}
  end

  defp blank_container(_, _width, _height), do: nil

  defp blank_container_border(style) do
    style.border
    |> Map.put(:color, style.border_color || style.border.color)
    |> Map.put(:background_color, style.background_color)
  end

  defp blank_container_bounds(width, height, border) do
    last_x = width - 1
    last_y = height - 1

    %{
      last_x: last_x,
      last_y: last_y,
      inner_left: if(border.left, do: 1, else: 0),
      inner_top: if(border.top, do: 1, else: 0),
      inner_right: if(border.right, do: last_x - 1, else: last_x),
      inner_bottom: if(border.bottom, do: last_y - 1, else: last_y)
    }
  end

  defp maybe_add_blank_container_fill(map, "", _bounds), do: map

  defp maybe_add_blank_container_fill(map, fill_seq, bounds) do
    if bounds.inner_left <= bounds.inner_right and bounds.inner_top <= bounds.inner_bottom do
      Map.put(map, @default_fill_key, [
        {{" ", fill_seq}, bounds.inner_left, bounds.inner_top, bounds.inner_right, bounds.inner_bottom}
      ])
    else
      map
    end
  end

  defp add_blank_container_borders(map, border, border_seq, width, height, bounds) do
    map
    |> maybe_add_horizontal_border(%{
      y: 0,
      width: width,
      char: border.top,
      left_corner: border.top_left,
      right_corner: border.top_right,
      seq: border_seq
    })
    |> maybe_add_horizontal_border(%{
      y: bounds.last_y,
      width: width,
      char: border.bottom,
      left_corner: border.bottom_left,
      right_corner: border.bottom_right,
      seq: border_seq
    })
    |> maybe_add_vertical_border(%{
      x: 0,
      height: height,
      char: border.left,
      top_corner: border.top_left,
      bottom_corner: border.bottom_left,
      seq: border_seq
    })
    |> maybe_add_vertical_border(%{
      x: bounds.last_x,
      height: height,
      char: border.right,
      top_corner: border.top_right,
      bottom_corner: border.bottom_right,
      seq: border_seq
    })
  end

  defp clear_fill_covered_cells(target_map, source_map, offset_x, offset_y) do
    fills = shifted_default_fill_entries(source_map, offset_x, offset_y)

    if fills == [] do
      target_map
    else
      Enum.reduce(target_map, %{}, &clear_fill_covered_entry(&1, &2, fills))
    end
  end

  defp clear_fill_covered_entry({@wide_glyph_key, true}, acc, _fills),
    do: Map.put(acc, @wide_glyph_key, true)

  defp clear_fill_covered_entry({@default_fill_key, value}, acc, _fills),
    do: Map.put(acc, @default_fill_key, value)

  defp clear_fill_covered_entry({{y, x} = key, value}, acc, fills) do
    if point_in_any_fill?(x, y, fills), do: acc, else: Map.put(acc, key, value)
  end

  defp clear_fill_covered_entry(_entry, acc, _fills), do: acc

  defp merge_default_fills(map, target_map, source_map, {offset_x, offset_y}) do
    fills =
      (shifted_default_fill_entries(source_map, offset_x, offset_y) ++
         default_fill_entries(target_map))
      |> normalize_default_fill_entries()

    put_default_fills(map, fills)
  end

  defp put_default_fills(map, []), do: Map.delete(map, @default_fill_key)
  defp put_default_fills(map, fills), do: Map.put(map, @default_fill_key, fills)

  defp layer_map_coverage_rects(source_map, offset_x, offset_y) do
    explicit_rects =
      Enum.reduce(source_map, [], &coverage_rect_entry(&1, &2, {offset_x, offset_y}))

    fill_rects =
      source_map
      |> shifted_default_fill_entries(offset_x, offset_y)
      |> Enum.map(fn {_point, left, top, right, bottom} -> {left, top, right, bottom} end)

    explicit_rects ++ fill_rects
  end

  defp coverage_rect_entry({{_y, _x}, {" ", ""}}, acc, _offset), do: acc

  defp coverage_rect_entry({{y, x}, {char, _style}}, acc, {offset_x, offset_y}) do
    width = Ucwidth.width(char)
    [{x + offset_x, y + offset_y, x + offset_x + width - 1, y + offset_y} | acc]
  end

  defp coverage_rect_entry(_entry, acc, _offset), do: acc

  defp point_in_any_rect?(x, y, rects) do
    Enum.any?(rects, fn {left, top, right, bottom} ->
      x >= left and x <= right and y >= top and y <= bottom
    end)
  end

  defp put_uncovered_default_fills(map, target_map, coverage_rects) do
    fills =
      target_map
      |> default_fill_entries()
      |> Enum.flat_map(&subtract_fill_coverage(&1, coverage_rects))
      |> normalize_default_fill_entries()

    put_default_fills(map, fills)
  end

  defp subtract_fill_coverage({point, left, top, right, bottom}, coverage_rects) do
    coverage_rects
    |> Enum.reduce([{left, top, right, bottom}], fn coverage_rect, rects ->
      Enum.flat_map(rects, &subtract_rect(&1, coverage_rect))
    end)
    |> Enum.map(fn {left, top, right, bottom} -> {point, left, top, right, bottom} end)
  end

  defp subtract_rect(
         {left, top, right, bottom} = rect,
         {cover_left, cover_top, cover_right, cover_bottom}
       ) do
    if right < cover_left or left > cover_right or bottom < cover_top or top > cover_bottom do
      [rect]
    else
      overlap_top = max(top, cover_top)
      overlap_bottom = min(bottom, cover_bottom)

      [
        {left, top, right, cover_top - 1},
        {left, cover_bottom + 1, right, bottom},
        {left, overlap_top, cover_left - 1, overlap_bottom},
        {cover_right + 1, overlap_top, right, overlap_bottom}
      ]
      |> Enum.filter(fn {left, top, right, bottom} -> left <= right and top <= bottom end)
    end
  end

  defp point_in_any_fill?(x, y, fills) do
    Enum.any?(fills, fn
      {_point, left, top, right, bottom} ->
        x >= left and x <= right and y >= top and y <= bottom
    end)
  end

  defp do_to_content(layer_map, overlay_layer_map, bounds)
       when map_size(overlay_layer_map) == 0 do
    if has_wide_glyphs?(layer_map) do
      rows_to_content(layer_map, bounds)
    else
      dense_rows_to_content(%{
        bounds: bounds,
        layer_map: layer_map,
        overlay?: false,
        overlay_layer_map: overlay_layer_map,
        reset: Termite.Style.reset_code()
      })
    end
  end

  defp do_to_content(layer_map, overlay_layer_map, bounds) do
    if has_wide_glyphs?(layer_map) or has_wide_glyphs?(overlay_layer_map) do
      merge_visible(layer_map, overlay_layer_map, bounds)
      |> rows_to_content(bounds)
    else
      dense_rows_to_content(%{
        bounds: bounds,
        layer_map: layer_map,
        overlay?: true,
        overlay_layer_map: overlay_layer_map,
        reset: Termite.Style.reset_code()
      })
    end
  end

  defp dense_rows_to_content(%{bounds: bounds} = context) do
    bounds.start_y..bounds.max_y
    |> Enum.map(&dense_row_to_content(&1, context))
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
  end

  defp dense_row_to_content(y, %{bounds: bounds, reset: reset} = context) do
    bounds.start_x..bounds.max_x
    |> Enum.reduce({[], [], "", false}, &append_dense_cell(&1, y, &2, context))
    |> finish_dense_row(reset)
  end

  defp append_dense_cell(x, y, {segments, buffer, last_style, skip}, context) do
    {point, skip_next} = dense_cell_point(x, y, skip, context)

    case point do
      nil -> append_dense_blank_cell(x, y, {segments, buffer, last_style, skip_next}, context)
      _ -> append_dense_point(point, {segments, buffer, last_style, skip_next}, context)
    end
  end

  defp dense_cell_point(_x, _y, true, %{overlay?: false}), do: {:skip, false}

  defp dense_cell_point(x, y, _skip, %{layer_map: layer_map, overlay?: false}) do
    point = Map.get(layer_map, {y, x}) || default_fill_at(layer_map, y, x)
    {point, wide_point?(point)}
  end

  defp dense_cell_point(x, y, skip, %{overlay?: true} = context) do
    overlay_point =
      Map.get(context.overlay_layer_map, {y, x}) ||
        default_fill_at(context.overlay_layer_map, y, x)

    point =
      if skip do
        overlay_point
      else
        overlay_point || Map.get(context.layer_map, {y, x}) ||
          default_fill_at(context.layer_map, y, x)
      end

    {point, wide_point?(overlay_point)}
  end

  defp append_dense_point(:skip, {segments, buffer, last_style, _skip_next}, _context) do
    {segments, buffer, last_style, false}
  end

  defp append_dense_point({char, style}, {segments, buffer, style, skip_next}, _context) do
    {segments, [char | buffer], style, skip_next}
  end

  defp append_dense_point(
         {char, style},
         {segments, buffer, last_style, skip_next},
         %{reset: reset}
       ) do
    {flush_buffer(segments, buffer, last_style, reset), [char], style, skip_next}
  end

  defp append_dense_blank_cell(x, y, state, %{overlay?: false, layer_map: layer_map, reset: reset}) do
    if wide_continuation?(layer_map, y, x) do
      {segments, buffer, last_style, _skip_next} = state
      {segments, buffer, last_style, false}
    else
      append_dense_blank(state, reset)
    end
  end

  defp append_dense_blank_cell(_x, _y, state, %{reset: reset}),
    do: append_dense_blank(state, reset)

  defp append_dense_blank({segments, buffer, "", skip_next}, _reset) do
    {segments, [" " | buffer], "", skip_next}
  end

  defp append_dense_blank({segments, buffer, last_style, skip_next}, reset) do
    {flush_buffer(segments, buffer, last_style, reset), [" "], "", skip_next}
  end

  defp finish_dense_row({segments, buffer, style, _skip}, reset) do
    segments
    |> flush_buffer(buffer, style, reset)
    |> Enum.reverse()
  end

  defp wide_point?({char, _style}), do: Ucwidth.width(char) == 2
  defp wide_point?(_point), do: false

  defp merge_visible(layer_map, overlay_layer_map, bounds) do
    merge(
      filter(layer_map, bounds),
      filter(overlay_layer_map, bounds),
      {0, 0}
    )
    |> elem(0)
  end

  defp rows_to_content(layer_map, bounds) do
    reset = Termite.Style.reset_code()
    rows = group_rows(layer_map, bounds)

    bounds.start_y..bounds.max_y
    |> Enum.map(&sparse_row_to_content(&1, rows, bounds, reset))
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
  end

  defp sparse_row_to_content(y, rows, bounds, reset) do
    rows
    |> Map.get(y, [])
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce({[], [], "", bounds.start_x}, &append_sparse_cell(&1, &2, reset))
    |> finish_sparse_row(bounds.max_x, reset)
  end

  defp append_sparse_cell({x, char, style}, {segments, buffer, last_style, cursor_x}, reset) do
    {segments, buffer, last_style} =
      append_gap({segments, buffer, last_style}, reset, max(x - cursor_x, 0))

    {segments, buffer} = append_styled_char({segments, buffer, last_style}, {char, style}, reset)
    {segments, buffer, style, x + Ucwidth.width(char)}
  end

  defp append_styled_char({segments, buffer, style}, {char, style}, _reset) do
    {segments, [char | buffer]}
  end

  defp append_styled_char({segments, buffer, last_style}, {char, _style}, reset) do
    {flush_buffer(segments, buffer, last_style, reset), [char]}
  end

  defp finish_sparse_row({segments, buffer, style, cursor_x}, max_x, reset) do
    {segments, buffer, style} =
      append_gap({segments, buffer, style}, reset, max(max_x + 1 - cursor_x, 0))

    segments
    |> flush_buffer(buffer, style, reset)
    |> Enum.reverse()
  end

  defp group_rows(layer_map, bounds) do
    Enum.reduce(layer_map, %{}, fn
      {{y, x}, {char, style}}, acc
      when y >= bounds.start_y and y <= bounds.max_y and x >= bounds.start_x and x <= bounds.max_x ->
        Map.update(acc, y, [{x, char, style}], &[{x, char, style} | &1])

      _, acc ->
        acc
    end)
  end

  defp flush_buffer(segments, [], _style, _reset), do: segments
  defp flush_buffer(segments, buffer, nil, _reset), do: [Enum.reverse(buffer) | segments]
  defp flush_buffer(segments, buffer, "", _reset), do: [Enum.reverse(buffer) | segments]

  defp flush_buffer(segments, buffer, style, reset) do
    [reset, Enum.reverse(buffer), style | segments]
  end

  defp append_gap({segments, buffer, ""}, _reset, 0), do: {segments, buffer, ""}
  defp append_gap({segments, buffer, style}, _reset, 0), do: {segments, buffer, style}

  defp append_gap({segments, buffer, ""}, _reset, gap) do
    {segments, [String.duplicate(" ", gap) | buffer], ""}
  end

  defp append_gap({segments, buffer, style}, reset, gap) do
    {flush_buffer(segments, buffer, style, reset), [String.duplicate(" ", gap)], ""}
  end

  defp clear_wide_continuation_cells(layer_map, _y, _x, width) when width <= 1, do: layer_map

  defp clear_wide_continuation_cells(layer_map, y, x, width) do
    Enum.reduce((x + 1)..(x + width - 1), layer_map, fn continuation_x, acc ->
      Map.delete(acc, {y, continuation_x})
    end)
  end

  defp wide_continuation?(layer_map, y, x) when x > 0 do
    case Map.get(layer_map, {y, x - 1}) do
      {char, _style} -> Ucwidth.width(char) == 2
      _ -> false
    end
  end

  defp wide_continuation?(_layer_map, _y, _x), do: false

  defp add_codepoint(codepoint, map, x, y, max_x, current_seq, seq, active_seq)
       when is_integer(codepoint) do
    width = Ucwidth.width_codepoint(codepoint)
    char = <<codepoint::utf8>>

    map =
      map
      |> Map.put({y, x}, {char, current_seq})
      |> maybe_mark_wide_glyph(width)

    {x + width, y, {map, max(max_x, x + width), false, seq, active_seq}}
  end

  defp maybe_mark_wide_glyph(map, width) when width > 1, do: Map.put(map, @wide_glyph_key, true)
  defp maybe_mark_wide_glyph(map, _width), do: map

  defp default_fill_at(layer_map, y, x) do
    Enum.find_value(default_fill_entries(layer_map), fn
      {{_char, _style} = point, left, top, right, bottom}
      when x >= left and x <= right and y >= top and y <= bottom ->
        point

      _ ->
        nil
    end)
  end

  defp maybe_clip_default_fill(map, source_map, %{
         start_x: start_x,
         start_y: start_y,
         max_x: max_x,
         max_y: max_y
       }) do
    fills =
      source_map
      |> default_fill_entries()
      |> Enum.flat_map(&clip_default_fill_entry(&1, {start_x, start_y, max_x, max_y}))
      |> normalize_default_fill_entries()

    put_default_fills(map, fills)
  end

  defp maybe_shift_default_fill(map, source_map, shift_x, shift_y) do
    fills =
      shifted_default_fill_entries(source_map, shift_x, shift_y)
      |> normalize_default_fill_entries()

    put_default_fills(map, fills)
  end

  defp clip_default_fill_entry(
         {{_char, _style} = point, left, top, right, bottom},
         {start_x, start_y, max_x, max_y}
       ) do
    clipped_left = max(left, start_x)
    clipped_top = max(top, start_y)
    clipped_right = min(right, max_x)
    clipped_bottom = min(bottom, max_y)

    if clipped_left <= clipped_right and clipped_top <= clipped_bottom do
      [{point, clipped_left, clipped_top, clipped_right, clipped_bottom}]
    else
      []
    end
  end

  defp metadata_count(layer_map) do
    if(has_wide_glyphs?(layer_map), do: 1, else: 0) +
      if Map.has_key?(layer_map, @default_fill_key), do: 1, else: 0
  end

  defp compact_full_surface_fill(layer_map, max_x, max_y)
       when max_x >= 0 and max_y >= 0 and map_size(layer_map) > 0 do
    area = (max_x + 1) * (max_y + 1)
    explicit_count = map_size(layer_map) - metadata_count(layer_map)

    if compact_full_surface_fill_candidate?(layer_map, area, explicit_count) do
      compact_dominant_full_surface_fill(layer_map, max_x, max_y, area)
    else
      {layer_map, max_x, max_y}
    end
  end

  defp compact_full_surface_fill(layer_map, max_x, max_y), do: {layer_map, max_x, max_y}

  defp compact_full_surface_fill_candidate?(layer_map, area, explicit_count) do
    area >= 512 and not Map.has_key?(layer_map, @default_fill_key) and explicit_count == area
  end

  defp compact_dominant_full_surface_fill(layer_map, max_x, max_y, area) do
    case dominant_fill_point(layer_map, area) do
      nil ->
        {layer_map, max_x, max_y}

      point ->
        compacted =
          layer_map
          |> Enum.reduce(%{}, fn
            {{_y, _x}, ^point}, acc ->
              acc

            {key, value}, acc ->
              Map.put(acc, key, value)
          end)
          |> Map.put(@default_fill_key, [{point, 0, 0, max_x, max_y}])

        {compacted, max_x, max_y}
    end
  end

  defp dominant_fill_point(layer_map, area) do
    threshold = div(area * 4, 5)

    layer_map
    |> Enum.reduce(%{}, fn
      {{_y, _x}, point}, acc ->
        Map.update(acc, point, 1, &(&1 + 1))

      _, acc ->
        acc
    end)
    |> Enum.max_by(fn {_point, count} -> count end, fn -> nil end)
    |> case do
      {point, count} when count >= threshold -> point
      _ -> nil
    end
  end

  defp maybe_add_horizontal_border(map, %{char: nil}), do: map

  defp maybe_add_horizontal_border(map, border) do
    Enum.reduce(0..(border.width - 1), map, fn x, acc ->
      Map.put(acc, {border.y, x}, {horizontal_border_char(x, border), border.seq})
    end)
  end

  defp horizontal_border_char(0, %{left_corner: left_corner}) when not is_nil(left_corner),
    do: left_corner

  defp horizontal_border_char(x, %{width: width, right_corner: right_corner})
       when x == width - 1 and not is_nil(right_corner),
       do: right_corner

  defp horizontal_border_char(_x, %{char: char}), do: char

  defp maybe_add_vertical_border(map, %{char: nil}), do: map

  defp maybe_add_vertical_border(map, border) do
    Enum.reduce(0..(border.height - 1), map, fn y, acc ->
      case vertical_border_char(y, border) do
        nil -> acc
        char -> Map.put(acc, {y, border.x}, {char, border.seq})
      end
    end)
  end

  defp vertical_border_char(0, %{top_corner: top_corner}) when not is_nil(top_corner), do: nil

  defp vertical_border_char(y, %{height: height, bottom_corner: bottom_corner})
       when y == height - 1 and not is_nil(bottom_corner),
       do: nil

  defp vertical_border_char(_y, %{char: char}), do: char

  defp border_style_sequence(border) do
    []
    |> maybe_add_color(Map.get(border, :color), &Termite.Style.foreground/2)
    |> maybe_add_color(Map.get(border, :background_color), &Termite.Style.background/2)
    |> case do
      [] ->
        ""

      funs ->
        Enum.reduce(funs, Termite.Style.ansi256(), fn fun, style -> fun.(style) end)
        |> Termite.Style.render_to_string("")
        |> String.trim_trailing(Termite.Style.reset_code())
    end
  end

  defp maybe_add_style(funs, true, fun), do: [fun | funs]
  defp maybe_add_style(funs, _enabled, _fun), do: funs

  defp maybe_add_color(funs, nil, _fun), do: funs
  defp maybe_add_color(funs, value, fun), do: [fn style -> fun.(style, value) end | funs]

  defp accumulate_sgr_sequence(_active_seq, new_seq, reset) when new_seq == reset, do: reset
  defp accumulate_sgr_sequence(active_seq, new_seq, reset) when active_seq == reset, do: new_seq
  defp accumulate_sgr_sequence(active_seq, new_seq, _reset), do: active_seq <> new_seq

  defp generate_binary(<<"\e[0m", rest::binary>>, layer_map, start_x, x, y, max_x, false, _seq, _active_seq, reset) do
    generate_binary(rest, layer_map, start_x, x, y, max_x, false, reset, reset, reset)
  end

  defp generate_binary(<<"\e", rest::binary>>, layer_map, start_x, x, y, max_x, false, _seq, active_seq, reset) do
    generate_binary(rest, layer_map, start_x, x, y, max_x, true, "\e", active_seq, reset)
  end

  defp generate_binary(<<"m", rest::binary>>, layer_map, start_x, x, y, max_x, true, seq, active_seq, reset) do
    next_active_seq = accumulate_sgr_sequence(active_seq, seq <> "m", reset)
    generate_binary(rest, layer_map, start_x, x, y, max_x, false, "", next_active_seq, reset)
  end

  defp generate_binary(<<char, rest::binary>>, layer_map, start_x, x, y, max_x, true, seq, active_seq, reset)
       when char < 128 do
    generate_binary(rest, layer_map, start_x, x, y, max_x, true, seq <> <<char>>, active_seq, reset)
  end

  defp generate_binary(<<char::utf8, rest::binary>>, layer_map, start_x, x, y, max_x, true, seq, active_seq, reset) do
    generate_binary(rest, layer_map, start_x, x, y, max_x, true, seq <> <<char::utf8>>, active_seq, reset)
  end

  defp generate_binary(<<"\n", rest::binary>>, layer_map, start_x, _x, y, max_x, false, _seq, active_seq, reset) do
    generate_binary(rest, layer_map, start_x, start_x, y + 1, max_x, false, "", active_seq, reset)
  end

  defp generate_binary(<<char, rest::binary>>, layer_map, start_x, x, y, max_x, false, seq, active_seq, reset)
       when char < 128 do
    current_seq = if active_seq == reset, do: "", else: active_seq

    {x, y, {layer_map, max_x, false, seq, active_seq}} =
      add_codepoint(char, layer_map, x, y, max_x, current_seq, seq, active_seq)

    generate_binary(rest, layer_map, start_x, x, y, max_x, false, seq, active_seq, reset)
  end

  defp generate_binary(<<cp::utf8, rest::binary>>, layer_map, start_x, x, y, max_x, false, seq, active_seq, reset) do
    codepoint = cp
    current_seq = if active_seq == reset, do: "", else: active_seq

    {x, y, {layer_map, max_x, false, seq, active_seq}} =
      add_codepoint(codepoint, layer_map, x, y, max_x, current_seq, seq, active_seq)

    generate_binary(rest, layer_map, start_x, x, y, max_x, false, seq, active_seq, reset)
  end

  defp generate_binary(<<>>, layer_map, _start_x, x, y, max_x, in_seq?, seq, active_seq, _reset) do
    {x, y, {layer_map, max_x, in_seq?, seq, active_seq}}
  end
end
