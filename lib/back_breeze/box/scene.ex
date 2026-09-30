defmodule BackBreeze.Box.Scene do
  @moduledoc false
  alias BackBreeze.Box.LayerMap

  # A scene stores layers in back-to-front paint order:
  #   {leaf, offset_x, offset_y, {left, top, right, bottom}}
  # Leaf bounds are local and inclusive, __scene_bounds__ is their translated
  # union. Leaves are cell maps, plain ASCII rows, or styled ASCII row segments.
  #
  # Layout transforms this representation without painting it. SceneCells
  # expands it to the existing public cell map. SceneOutput emits ANSI directly.
  # Unsupported content falls back to LayerMap's eager implementation.

  def deferred?(%{__scene__: _}), do: true
  def deferred?(_), do: false

  def to_content(%{__scene__: _} = scene, bounds),
    do: BackBreeze.Box.SceneOutput.render(scene, bounds)

  def to_content(map, bounds), do: LayerMap.to_content(map, %{}, bounds)

  # Internal callers supply rectangular, printable ASCII rows with an opaque
  # style. Keep the binaries intact through translation and cache storage.
  def from_text_rows([], _style, _x, _y), do: %{}

  def from_text_rows([first | _] = rows, style, x, y) do
    rect = {0, 0, byte_size(first) - 1, length(rows) - 1}
    build([{%{__text_rows__: rows, __text_style__: style}, x, y, rect}])
  end

  def from_styled_rows([], _x, _y), do: %{}

  def from_styled_rows(rows, x, y) do
    width =
      rows
      |> Enum.map(fn row -> Enum.reduce(row, 0, fn {text, _}, n -> n + byte_size(text) end) end)
      |> Enum.max()

    if width == 0,
      do: %{},
      else: build([{%{__styled_rows__: rows}, x, y, {0, 0, width - 1, length(rows) - 1}}])
  end

  def wrap(%{__scene__: _} = map), do: map

  def wrap(map) do
    if LayerMap.content?(map) and supported?(map), do: build(layers(map, 0, 0)), else: map
  end

  def supported?(%{__scene__: _}), do: true

  def supported?(map) do
    not LayerMap.has_wide_glyphs?(map) and
      Enum.all?(map, fn
        {{_, _}, {" ", ""}} -> false
        {{_, _}, {<<char>>, _}} when char >= 32 and char < 127 -> true
        {{_, _}, {char, _}} -> BackBreeze.Ucwidth.width(char) == 1
        _ -> true
      end)
  end

  def materialize(%{__scene__: layers}), do: BackBreeze.Box.SceneCells.materialize(layers)
  def materialize(map), do: map

  def shift(%{__scene__: layers}, x, y) do
    build(Enum.map(layers, fn {map, dx, dy, rect} -> {map, dx + x, dy + y, rect} end))
  end

  def merge(target, source, {x, y} = offset) do
    if supported?(target) and supported?(source) do
      build(layers(target, 0, 0) ++ layers(source, x, y))
    else
      LayerMap.merge_map(materialize(target), materialize(source), offset)
    end
  end

  def merge_dimensions(target, source, offset) do
    if supported?(target) and supported?(source) do
      map = merge(target, source, offset)
      {x, y} = LayerMap.bounds(map)
      {map, max(x, 0), max(y, 0)}
    else
      LayerMap.merge(materialize(target), materialize(source), offset)
    end
  end

  def compose(fragments, bounds) do
    # Composition without overlay semantics is safe to flatten only when the
    # fragment rectangles are disjoint. Otherwise retain the eager behavior.
    result =
      Enum.reduce_while(fragments, {[], [], nil}, fn {map, x, y}, {acc, rects, envelope} ->
        rect = rectangle(map, x, y)

        overlaps? =
          envelope != nil and overlap?(envelope, rect) and
            Enum.any?(rects, &overlap?(&1, rect))

        if supported?(map) and not overlaps? do
          {:cont, {[layers(map, x, y) | acc], [rect | rects], expand_envelope(envelope, rect)}}
        else
          {:halt, :fallback}
        end
      end)

    case result do
      :fallback ->
        LayerMap.compose_fragments(
          Enum.map(fragments, fn {map, x, y} -> {materialize(map), x, y} end),
          bounds
        )

      {groups, _, _} ->
        map = groups |> Enum.reverse() |> List.flatten() |> build()
        if bounds, do: LayerMap.filter(map, bounds), else: map
    end
  end

  defp expand_envelope(nil, rect), do: rect

  defp expand_envelope({l, t, r, b}, {ll, tt, rr, bb}),
    do: {min(l, ll), min(t, tt), max(r, rr), max(b, bb)}

  def clip(%{__scene_bounds__: {left, top, right, bottom}} = map, bounds) do
    if left >= bounds.start_x and top >= bounds.start_y and right <= bounds.max_x and
         bottom <= bounds.max_y do
      map
    else
      map.__scene__ |> Enum.flat_map(&clip_layer(&1, bounds)) |> build()
    end
  end

  defp clip_layer({map, dx, dy, {left, top, right, bottom}} = layer, bounds) do
    cond do
      right + dx < bounds.start_x or left + dx > bounds.max_x or bottom + dy < bounds.start_y or
          top + dy > bounds.max_y ->
        []

      left + dx >= bounds.start_x and right + dx <= bounds.max_x and top + dy >= bounds.start_y and
          bottom + dy <= bounds.max_y ->
        [layer]

      true ->
        local = %{
          start_x: bounds.start_x - dx,
          start_y: bounds.start_y - dy,
          max_x: bounds.max_x - dx,
          max_y: bounds.max_y - dy
        }

        clip_leaf(map, dx, dy, local)
    end
  end

  defp clip_leaf(%{__text_rows__: text, __text_style__: style}, dx, dy, bounds),
    do: clip_leaf(%{__styled_rows__: Enum.map(text, &[{&1, style}])}, dx, dy, bounds)

  defp clip_leaf(%{__styled_rows__: text}, dx, dy, bounds) do
    top = max(bounds.start_y, 0)
    left = max(bounds.start_x, 0)

    rows =
      text
      |> Enum.slice(top, max(bounds.max_y - top + 1, 0))
      |> Enum.map(&clip_row(&1, left, bounds.max_x + 1))

    layers(from_styled_rows(rows, dx + left, dy + top), 0, 0)
  end

  defp clip_leaf(map, dx, dy, bounds), do: layers(LayerMap.filter(map, bounds), dx, dy)

  defp clip_row(row, left, right) do
    {parts, _} =
      Enum.reduce(row, {[], 0}, fn {text, style}, {parts, x} ->
        first = max(x, left)
        last = min(x + byte_size(text), right)

        parts =
          if first < last,
            do: [{binary_part(text, first - x, last - first), style} | parts],
            else: parts

        {parts, x + byte_size(text)}
      end)

    Enum.reverse(parts)
  end

  def fills(%{__scene__: layers}) do
    layers
    |> Enum.reverse()
    |> Enum.flat_map(fn {map, x, y, _rect} ->
      LayerMap.shifted_default_fill_entries(map, x, y)
    end)
    |> LayerMap.normalize_default_fill_entries()
  end

  defp layers(%{__scene__: layers}, x, y),
    do: Enum.map(layers, fn {map, dx, dy, rect} -> {map, dx + x, dy + y, rect} end)

  defp layers(map, x, y),
    do: if(LayerMap.content?(map), do: [{map, x, y, rectangle(map, 0, 0)}], else: [])

  defp build([]), do: %{}

  defp build(layers) do
    rect =
      layers
      |> Enum.map(fn {_map, x, y, {l, t, r, b}} -> {l + x, t + y, r + x, b + y} end)
      |> Enum.reduce(fn {l, t, r, b}, {al, at, ar, ab} ->
        {min(l, al), min(t, at), max(r, ar), max(b, ab)}
      end)

    %{__scene__: layers, __scene_bounds__: rect}
  end

  defp rectangle(%{__scene_bounds__: {l, t, r, b}}, x, y), do: {l + x, t + y, r + x, b + y}

  defp rectangle(map, x, y) do
    {right, bottom} = LayerMap.bounds(map)
    # A conservative minimum keeps clipping safe for negative coordinates.
    {left, top} =
      Enum.reduce(map, {0, 0}, fn
        {{cy, cx}, _}, {l, t} -> {min(l, cx), min(t, cy)}
        _, acc -> acc
      end)

    {left, top} =
      Enum.reduce(LayerMap.default_fill_entries(map), {left, top}, fn
        {_, l, t, _, _}, {al, at} -> {min(l, al), min(t, at)}
      end)

    {left + x, top + y, right + x, bottom + y}
  end

  defp overlap?({l, t, r, b}, {ll, tt, rr, bb}), do: l <= rr and r >= ll and t <= bb and b >= tt
end
