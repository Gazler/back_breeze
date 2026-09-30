defmodule BackBreeze.Box.SceneCells do
  @moduledoc false

  # Public cell-map conversion. Scene owns geometry. This module owns painting
  # and fill occlusion. SceneOutput handles the separate direct-ANSI path.
  alias BackBreeze.Box.LayerMap

  # Painting state: {cells, fill_groups, covering_fills, row_interval_cache}.
  # Coverage contains fills from later layers only. Cache entries are updated
  # when crossing a filled layer, so cells never rescan every fill per column.
  def materialize(layers) do
    # Walk front to back. Later fills hide earlier cells, while explicit cells
    # in the same layer always win over that layer's own fills. Accumulating
    # entries backwards lets Map.new resolve overlapping cells in paint order.
    {cells, fill_groups, _coverage, _rows} =
      layers |> Enum.reverse() |> Enum.reduce({[], [], [], %{}}, &paint_layer/2)

    fills = fill_groups |> Enum.reverse() |> List.flatten()
    cells |> Map.new() |> LayerMap.put_default_fill_entries(fills)
  end

  defp paint_layer({%{__styled_rows__: text}, dx, dy, _rect}, {cells, groups, coverage, rows}) do
    styles = for row <- text, {_text, style} <- row, uniq: true, do: style

    palettes = Map.new(styles, &{&1, ascii_palette(&1)})

    {cells, _} =
      Enum.reduce(text, {cells, dy}, fn row, {cells, y} ->
        intervals = Map.get_lazy(rows, y, fn -> row_intervals(coverage, y) end)

        {cells, _} =
          Enum.reduce(row, {cells, dx}, fn {text, style}, {cells, x} ->
            relevant =
              Enum.filter(intervals, fn {left, right} ->
                right >= x and left < x + byte_size(text)
              end)

            {paint_text(text, x, y, Map.fetch!(palettes, style), relevant, cells), x + byte_size(text)}
          end)

        {cells, y + 1}
      end)

    {cells, groups, coverage, rows}
  end

  defp paint_layer(
         {%{__text_rows__: text, __text_style__: style}, dx, dy, _rect},
         {cells, groups, coverage, rows}
       ) do
    palette = ascii_palette(style)

    {cells, _y} =
      Enum.reduce(text, {cells, dy}, fn row, {cells, y} ->
        intervals = Map.get_lazy(rows, y, fn -> row_intervals(coverage, y) end)

        intervals =
          Enum.filter(intervals, fn {left, right} ->
            right >= dx and left < dx + byte_size(row)
          end)

        {paint_text(row, dx, y, palette, intervals, cells), y + 1}
      end)

    {cells, groups, coverage, rows}
  end

  defp paint_layer({map, dx, dy, _rect}, {cells, groups, coverage, rows}) do
    {cells, rows} =
      Enum.reduce(map, {cells, rows}, fn
        {{y, x}, value}, {cells, rows} ->
          x = x + dx
          y = y + dy

          {intervals, rows} =
            case rows do
              %{^y => intervals} ->
                {intervals, rows}

              _ ->
                intervals = row_intervals(coverage, y)
                {intervals, Map.put(rows, y, intervals)}
            end

          hidden? = Enum.any?(intervals, fn {left, right} -> x >= left and x <= right end)
          {if(hidden?, do: cells, else: [{{y, x}, value} | cells]), rows}

        _, acc ->
          acc
      end)

    fills = LayerMap.shifted_default_fill_entries(map, dx, dy)

    rows =
      if fills == [] do
        rows
      else
        Map.new(rows, fn {y, intervals} -> {y, row_intervals(fills, y) ++ intervals} end)
      end

    {cells, [fills | groups], fills ++ coverage, rows}
  end

  defp row_intervals(fills, y) do
    for {_point, left, top, right, bottom} <- fills, y >= top and y <= bottom, do: {left, right}
  end

  # Reuse cell values rather than allocate a new {character, style} per column.
  defp ascii_palette(style), do: 0..127 |> Enum.map(&{<<&1>>, style}) |> List.to_tuple()

  defp paint_text(<<>>, _x, _y, _style, _intervals, cells), do: cells

  defp paint_text(<<char, rest::binary>>, x, y, palette, [], cells),
    do: paint_text(rest, x + 1, y, palette, [], [{{y, x}, elem(palette, char)} | cells])

  defp paint_text(<<char, rest::binary>>, x, y, palette, intervals, cells) do
    cells =
      if Enum.any?(intervals, fn {left, right} -> x >= left and x <= right end),
        do: cells,
        else: [{{y, x}, elem(palette, char)} | cells]

    paint_text(rest, x + 1, y, palette, intervals, cells)
  end
end
