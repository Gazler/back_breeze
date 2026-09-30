defmodule BackBreeze.Box.SceneOutput do
  @moduledoc false
  alias BackBreeze.Box.{LayerMap, Scene}

  # Rows contain sorted, non-overlapping spans:
  #   {left, right_exclusive, text, style_sequence, bytes_per_cell}
  # Unlike Scene rectangles, span ends are exclusive. A span has a uniform
  # style and byte width, allowing clipping without grapheme traversal.

  def render(%{__scene__: layers} = scene, bounds) do
    safe? =
      Enum.all?(layers, fn {map, _, _, _} ->
        Enum.all?(LayerMap.default_fill_entries(map), fn {{char, _}, _, _, _, _} ->
          BackBreeze.Ucwidth.width(char) == 1
        end)
      end)

    if safe? and bounds.max_x >= bounds.start_x and bounds.max_y >= bounds.start_y do
      rows = Enum.reduce(layers, %{}, &paint_layer(&1, &2, bounds))

      bounds.start_y..bounds.max_y
      |> Enum.map(fn y -> render_row(Map.get(rows, y, []), bounds) end)
      |> Enum.intersperse("\n")
      |> IO.iodata_to_binary()
    else
      LayerMap.to_content(Scene.materialize(scene), %{}, bounds)
    end
  end

  defp paint_layer({%{__text_rows__: text, __text_style__: style}, dx, dy, _}, rows, bounds) do
    text
    |> Enum.with_index(dy)
    |> Enum.reduce(rows, fn {line, y}, acc ->
      put_span(acc, y, {dx, dx + byte_size(line), line, style, 1}, bounds)
    end)
  end

  defp paint_layer({%{__styled_rows__: text}, dx, dy, _}, rows, bounds) do
    text
    |> Enum.with_index(dy)
    |> Enum.reduce(rows, fn {line, y}, acc ->
      {acc, _} =
        Enum.reduce(line, {acc, dx}, fn {text, style}, {acc, x} ->
          {put_span(acc, y, {x, x + byte_size(text), text, style, 1}, bounds), x + byte_size(text)}
        end)

      acc
    end)
  end

  defp paint_layer({map, dx, dy, _}, rows, bounds) do
    rows = paint_fills(map, dx, dy, rows, bounds)
    paint_cells(map, dx, dy, rows, bounds)
  end

  defp paint_fills(map, dx, dy, rows, bounds) do
    map
    |> LayerMap.default_fill_entries()
    |> Enum.reverse()
    |> Enum.reduce(rows, fn
      {{char, style}, left, top, right, bottom}, acc ->
        top = max(top + dy, bounds.start_y)
        bottom = min(bottom + dy, bounds.max_y)
        left = max(left + dx, bounds.start_x)
        right = min(right + dx + 1, bounds.max_x + 1)

        if top <= bottom and left < right do
          span = {left, right, String.duplicate(char, right - left), style, byte_size(char)}
          Enum.reduce(top..bottom, acc, &put_span(&2, &1, span, bounds))
        else
          acc
        end
    end)
  end

  defp paint_cells(map, dx, dy, rows, bounds) do
    map
    |> Enum.reduce(%{}, fn
      {{y, x}, {char, style}}, acc ->
        y = y + dy
        x = x + dx

        if y >= bounds.start_y and y <= bounds.max_y and x >= bounds.start_x and x <= bounds.max_x,
          do: Map.update(acc, y, [{x, char, style}], &[{x, char, style} | &1]),
          else: acc

      _, acc ->
        acc
    end)
    |> Enum.reduce(rows, fn {y, cells}, acc ->
      cells |> Enum.sort() |> coalesce([]) |> Enum.reduce(acc, &put_span(&2, y, &1, bounds))
    end)
  end

  defp coalesce([], acc), do: Enum.reverse(acc)

  defp coalesce([{x, char, style} | rest], [{left, x, text, style, unit} | acc])
       when byte_size(char) == unit,
       do: coalesce(rest, [{left, x + 1, text <> char, style, unit} | acc])

  defp coalesce([{x, char, style} | rest], acc),
    do: coalesce(rest, [{x, x + 1, char, style, byte_size(char)} | acc])

  defp put_span(rows, y, {left, right, _, _, _} = span, bounds) do
    left = max(left, bounds.start_x)
    right = min(right, bounds.max_x + 1)

    if y >= bounds.start_y and y <= bounds.max_y and left < right do
      span = slice(span, left, right)
      Map.update(rows, y, [span], &overlay(&1, span))
    else
      rows
    end
  end

  defp overlay([], span), do: [span]

  defp overlay([{left, right, _, _, _} = old | rest], {start, stop, _, _, _} = span) do
    cond do
      right <= start ->
        [old | overlay(rest, span)]

      left >= stop ->
        [span, old | rest]

      true ->
        prefix = if left < start, do: [slice(old, left, start)], else: []

        if right > stop,
          do: prefix ++ [span, slice(old, stop, right) | rest],
          else: prefix ++ overlay(rest, span)
    end
  end

  defp slice({left, right, _, _, _} = span, left, right), do: span

  defp slice({left, _, text, style, unit}, start, stop),
    do: {start, stop, binary_part(text, (start - left) * unit, (stop - start) * unit), style, unit}

  defp render_row(spans, bounds) do
    {parts, buffer, style, x} =
      Enum.reduce(spans, {[], [], "", bounds.start_x}, fn {left, right, text, next_style, _},
                                                          {parts, buffer, style, x} ->
        {parts, buffer, style} =
          if left > x,
            do: append(parts, buffer, style, String.duplicate(" ", left - x), ""),
            else: {parts, buffer, style}

        {parts, buffer, style} = append(parts, buffer, style, text, next_style)
        {parts, buffer, style, right}
      end)

    {parts, buffer, style} =
      if x <= bounds.max_x,
        do: append(parts, buffer, style, String.duplicate(" ", bounds.max_x + 1 - x), ""),
        else: {parts, buffer, style}

    Enum.reverse(flush(parts, buffer, style))
  end

  defp append(parts, buffer, style, text, style), do: {parts, [text | buffer], style}
  defp append(parts, buffer, style, text, next), do: {flush(parts, buffer, style), [text], next}
  defp flush(parts, [], _), do: parts
  defp flush(parts, buffer, ""), do: [Enum.reverse(buffer) | parts]

  defp flush(parts, buffer, style),
    do: [[style, Enum.reverse(buffer), Termite.Style.reset_code()] | parts]
end
