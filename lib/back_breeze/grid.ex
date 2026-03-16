defmodule BackBreeze.Grid do
  @moduledoc """
  Struct for creating a grid to be used by a Box.

  BackBreeze.Box.new(
    style: %{border: :line},
    display: %BackBreeze.Grid{columns: 1},
    children: [BackBreeze.Box.new(content: "Hello"), BackBreeze.Box.new(content: "World")]
  )
  """
  alias BackBreeze.BenchProfile

  @doc """
  Create a grid with the specified number of columns.
  """
  defstruct [:columns, :rows]

  @auto_sizes [:screen, :auto, :full]

  @doc false
  def precompute(items, grid, style, opts) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    width =
      case style.width do
        width when width in @auto_sizes -> screen_width
        other -> other
      end

    width_offset = if(style.border.left, do: 1, else: 0) + if style.border.right, do: 1, else: 0

    height =
      case style.height do
        height when height in @auto_sizes -> screen_height
        other -> other
      end

    height_offset = if(style.border.top, do: 1, else: 0) + if style.border.bottom, do: 1, else: 0

    rows = Enum.chunk_every(items, grid.columns)
    row_count = grid.rows || length(rows)
    column_widths = resolve_track_sizes(rows, grid.columns, width - width_offset, :width)
    row_heights = resolve_track_sizes(rows, row_count, height - height_offset, :height)

    %{
      width: Enum.min(column_widths, fn -> 0 end),
      height: Enum.max(row_heights, fn -> 0 end),
      column_widths: column_widths,
      row_heights: row_heights
    }
  end

  @doc false
  def render(items, grid, style, opts) do
    %{content: content, width: width, height: height} =
      render_with_dimensions(items, grid, style, opts)

    {content, width, height}
  end

  @doc false
  def render_with_dimensions(items, grid, style, opts) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    width_offset = if(style.border.left, do: 1, else: 0) + if style.border.right, do: 1, else: 0

    # Although this is similar to the calculation in precompute, dividing into columns happens
    # only if the width is not explicitly specified, compared to always dividing in the
    # precompute function
    height_offset = if(style.border.top, do: 1, else: 0) + if style.border.bottom, do: 1, else: 0

    rows = Enum.chunk_every(items, grid.columns)
    row_count = grid.rows || length(rows)

    total_width =
      case style.width do
        width when width in @auto_sizes -> screen_width - width_offset
        other -> other
      end

    total_height =
      case style.height do
        h when is_integer(h) and h > 0 -> h
        _ -> screen_height - height_offset
      end

    {column_widths, row_heights} =
      BenchProfile.measure({__MODULE__, :tracks}, fn ->
        {
          resolve_track_sizes(rows, grid.columns, total_width, :width),
          resolve_track_sizes(rows, row_count, total_height, :height)
        }
      end)

    rows_with_results =
      BenchProfile.measure({__MODULE__, :children}, fn ->
        rows
        |> Enum.with_index()
        |> Enum.map(fn {cols, row_index} ->
          row_height = Enum.at(row_heights, row_index, 0)

          cols
          |> Enum.with_index()
          |> Enum.map(fn {%{style: %{border: border}} = item, col_index} ->
            col_width = Enum.at(column_widths, col_index, 0)

            width = col_width - if(border.left, do: 1, else: 0) - if border.right, do: 1, else: 0

            height =
              row_height - if(border.top, do: 1, else: 0) - if border.bottom, do: 1, else: 0

            style = %{item.style | width: max(width, 0), height: max(height, 0)}

            %{
              item: item,
              result: render_grid_item(item, style)
            }
          end)
        end)
      end)

    per_item_dimensions =
      rows_with_results
      |> Enum.with_index()
      |> Enum.flat_map(fn {row, row_index} ->
        top = Enum.take(row_heights, row_index) |> Enum.sum()

        row
        |> Enum.with_index()
        |> Enum.map(fn {%{result: %{dimensions: dimensions}}, col_index} ->
          left = Enum.take(column_widths, col_index) |> Enum.sum()
          Enum.map(dimensions, &shift_dimension(&1, left, top))
        end)
      end)

    simple_row_or_column? =
      Enum.all?(List.flatten(rows_with_results), fn %{item: item, result: %{box: item_box}} ->
        not item_box.overlay? and not contains_absolute_descendants?(item)
      end)

    {content, rendered_width, rendered_height, layer_map} =
      BenchProfile.measure({__MODULE__, :compose}, fn ->
        cond do
          simple_row_or_column? and grid.columns == 1 ->
            rows_with_results
            |> Enum.map(fn
              [%{result: %{box: item_box}}] ->
                item_box.content

              row ->
                Enum.map_join(row, "\n", fn %{result: %{box: item_box}} -> item_box.content end)
            end)
            |> BackBreeze.Box.join_vertical(height: total_height)
            |> then(fn {content, width, height} -> {content, width, height, %{}} end)

          simple_row_or_column? and row_count == 1 ->
            rows_with_results
            |> List.flatten()
            |> Enum.map(fn %{result: %{box: item_box}} -> item_box.content end)
            |> BackBreeze.Box.join_horizontal()
            |> then(fn {content, width, height} -> {content, width, height, %{}} end)

          true ->
            children =
              rows_with_results
              |> Enum.with_index()
              |> Enum.flat_map(fn {row, row_index} ->
                top = Enum.take(row_heights, row_index) |> Enum.sum()

                row
                |> Enum.with_index()
                |> Enum.map(fn {%{item: item, result: %{box: item_box}}, col_index} ->
                  left = Enum.take(column_widths, col_index) |> Enum.sum()

                  overlay? = item_box.overlay? || contains_absolute_descendants?(item)

                  layer =
                    if overlay? do
                      max(item_box.layer || 0, 1)
                    else
                      item_box.layer || 0
                    end

                  %{
                    item_box
                    | position: :absolute,
                      left: left,
                      top: top,
                      layer: layer,
                      overlay?: overlay?
                  }
                end)
              end)
              |> Enum.sort_by(fn child -> {child.overlay?, child.top || 0, child.left || 0} end)

            %{content: content, width: width, height: height, layer_map: layer_map} =
              BackBreeze.Box.compose_absolute_children(
                children,
                width: total_width,
                height: total_height,
                clip: true
              )

            {content, width, height, layer_map}
        end
      end)

    %{
      content: content,
      width: resolved_extent(style.width, total_width, rendered_width),
      height: resolved_extent(style.height, total_height, rendered_height),
      per_item_dimensions: per_item_dimensions,
      layer_map: layer_map
    }
  end

  defp resolved_extent(value, total, rendered) do
    cond do
      is_integer(value) and value > 0 -> total
      value in @auto_sizes -> total
      true -> rendered || total
    end
  end

  defp resolve_track_sizes(rows, track_count, total, axis) do
    explicit =
      case axis do
        :width ->
          0..(track_count - 1)
          |> Enum.map(fn track_index ->
            rows
            |> Enum.map(&Enum.at(&1, track_index))
            |> Enum.reject(&is_nil/1)
            |> Enum.map(&explicit_track_size(&1, axis))
            |> Enum.reject(&is_nil/1)
            |> Enum.max(fn -> nil end)
          end)

        :height ->
          rows
          |> Enum.take(track_count)
          |> Enum.map(fn row ->
            row
            |> Enum.map(&explicit_track_size(&1, axis))
            |> Enum.reject(&is_nil/1)
            |> Enum.max(fn -> nil end)
          end)
      end

    grow_indexes =
      explicit
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {nil, index} -> [index]
        _ -> []
      end)

    distribute_dimension(track_count, max(total, 0), explicit, grow_indexes)
  end

  defp explicit_track_size(item, axis) do
    case item do
      %{style: style} ->
        style_value = Map.get(style, axis)
        border_size = border_size(style.border, axis)

        case style_value do
          value when is_integer(value) and value > 0 -> value + border_size
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp border_size(border, :width),
    do: if(border.left, do: 1, else: 0) + if(border.right, do: 1, else: 0)

  defp border_size(border, :height),
    do: if(border.top, do: 1, else: 0) + if(border.bottom, do: 1, else: 0)

  defp distribute_dimension(count, total, explicit, grow_indexes) do
    explicit_total =
      explicit
      |> Enum.reject(&is_nil/1)
      |> Enum.sum()

    remainder = max(total - explicit_total, 0)

    grow_sizes =
      if grow_indexes == [] do
        base = div(total, max(count, 1))
        extra = rem(total, max(count, 1))

        0..(count - 1)
        |> Enum.map(fn index -> base + if(index < extra, do: 1, else: 0) end)
      else
        base = div(remainder, length(grow_indexes))
        extra = rem(remainder, length(grow_indexes))

        grow_indexes
        |> Enum.with_index()
        |> Map.new(fn {track_index, index} ->
          {track_index, base + if(index < extra, do: 1, else: 0)}
        end)
      end

    explicit
    |> Enum.with_index()
    |> Enum.map(fn
      {nil, index} when is_map(grow_sizes) -> Map.get(grow_sizes, index, 0)
      {nil, index} -> Enum.at(grow_sizes, index, 0)
      {value, _index} -> value
    end)
  end

  defp render_grid_item(%{state: :rendered, width: width, height: height} = item, style)
       when width == style.width and height == style.height do
    %{box: item, dimensions: []}
  end

  defp render_grid_item(item, style) do
    BackBreeze.Box.render_with_dimensions(%{item | style: style})
  end

  defp shift_dimension(dims, left, top) do
    dims
    |> Map.update(:left, left, &(&1 + left))
    |> Map.update(:top, top, &(&1 + top))
  end

  defp contains_absolute_descendants?(%{position: :absolute}), do: true

  defp contains_absolute_descendants?(%{children: children}) when is_list(children) do
    Enum.any?(children, &contains_absolute_descendants?/1)
  end

  defp contains_absolute_descendants?(_), do: false
end
