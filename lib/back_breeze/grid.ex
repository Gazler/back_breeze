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
  alias BackBreeze.RenderCache

  @doc """
  Create a grid with the specified number of columns.
  """
  defstruct [:columns, :rows, :gap_x, :gap_y]

  @auto_sizes [:screen, :auto, :full]

  @doc false
  def precompute(items, grid, style, opts) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    width =
      case style.width do
        width when width in @auto_sizes -> screen_width
        other -> other
      end

    width_offset =
      if(style.border.left, do: 1, else: 0) +
        if(style.border.right, do: 1, else: 0) +
        style_value(style, :padding_left) +
        style_value(style, :padding_right)

    height =
      case style.height do
        height when height in @auto_sizes -> screen_height
        other -> other
      end

    height_offset =
      if(style.border.top, do: 1, else: 0) +
        if(style.border.bottom, do: 1, else: 0) +
        style_value(style, :padding_top) +
        style_value(style, :padding_bottom)

    rows = Enum.chunk_every(items, grid.columns)
    row_count = grid.rows || length(rows)
    gap_x = max(grid.gap_x || 0, 0)
    gap_y = max(grid.gap_y || 0, 0)
    total_gap_x = max(grid.columns - 1, 0) * gap_x
    total_gap_y = max(row_count - 1, 0) * gap_y

    column_widths =
      resolve_track_sizes(rows, grid.columns, width - width_offset - total_gap_x, :width)

    row_heights =
      resolve_track_sizes(rows, row_count, height - height_offset - total_gap_y, :height)

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
    render_with_dimensions(items, grid, style, opts, false)
  end

  @doc false
  def render_structured_with_dimensions(items, grid, style, opts) do
    render_with_dimensions(items, grid, style, opts, true)
  end

  defp render_with_dimensions(items, grid, style, opts, structured?) do
    terminal = Keyword.get(opts, :terminal)

    RenderCache.with_frame(fn ->
      RenderCache.fetch_stable(
        {:grid_render_with_dimensions, structured?, if(terminal, do: terminal.size, else: nil),
         items, grid, style},
        fn ->
          do_render_with_dimensions(items, grid, style, opts, structured?)
        end
      )
    end)
  end

  defp do_render_with_dimensions(items, grid, style, opts, structured?) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    width_offset =
      if(style.border.left, do: 1, else: 0) +
        if(style.border.right, do: 1, else: 0) +
        style_value(style, :padding_left) +
        style_value(style, :padding_right)

    # Although this is similar to the calculation in precompute, dividing into columns happens
    # only if the width is not explicitly specified, compared to always dividing in the
    # precompute function
    height_offset =
      if(style.border.top, do: 1, else: 0) +
        if(style.border.bottom, do: 1, else: 0) +
        style_value(style, :padding_top) +
        style_value(style, :padding_bottom)

    rows = Enum.chunk_every(items, grid.columns)
    row_count = grid.rows || length(rows)

    total_width =
      case style.width do
        width when width in @auto_sizes -> screen_width - width_offset
        other when is_integer(other) -> max(other - width_offset, 0)
        other -> other
      end

    total_height =
      case style.height do
        h when is_integer(h) and h > 0 -> max(h - height_offset, 0)
        _ -> screen_height - height_offset
      end

    gap_x = max(grid.gap_x || 0, 0)
    gap_y = max(grid.gap_y || 0, 0)
    total_gap_x = max(grid.columns - 1, 0) * gap_x
    total_gap_y = max(row_count - 1, 0) * gap_y

    {column_widths, row_heights} =
      BenchProfile.measure({__MODULE__, :tracks}, fn ->
        {
          resolve_track_sizes(rows, grid.columns, total_width - total_gap_x, :width),
          resolve_track_sizes(rows, row_count, total_height - total_gap_y, :height)
        }
      end)

    column_offsets = prefix_offsets(column_widths, gap_x)
    row_offsets = prefix_offsets(row_heights, gap_y)

    rows_with_results =
      BenchProfile.measure({__MODULE__, :children}, fn ->
        rows
        |> Enum.with_index()
        |> Enum.map(fn {cols, row_index} ->
          row_height = Enum.at(row_heights, row_index, 0)

          cols
          |> Enum.with_index()
          |> Enum.map(fn {item, col_index} ->
            col_width = Enum.at(column_widths, col_index, 0)
            width = col_width
            height = row_height

            style = %{item.style | width: max(width, 0), height: max(height, 0)}

            %{
              item: item,
              result: render_grid_item(item, style, structured?, opts)
            }
          end)
        end)
      end)

    {per_item_dimensions, rendered_children, simple_row_or_column?} =
      rows_with_results
      |> Enum.with_index()
      |> Enum.reduce({[], [], true}, fn {row, row_index}, {dims_acc, children_acc, simple_acc} ->
        top = Enum.at(row_offsets, row_index, 0)

        {row_dims, row_children, row_simple?} =
          row
          |> Enum.with_index()
          |> Enum.reduce({[], [], simple_acc}, fn
            {%{result: %{dimensions: dimensions, box: item_box}}, col_index},
            {dims_row_acc, children_row_acc, simple_row_acc} ->
              left = Enum.at(column_offsets, col_index, 0)

              shifted_dimensions = Enum.map(dimensions, &shift_dimension(&1, left, top))

              overlay? = item_box.overlay?
              layer = if(overlay?, do: max(item_box.layer || 0, 1), else: item_box.layer || 0)

              child = %{
                item_box
                | left: left,
                  top: top,
                  layer: layer,
                  overlay?: overlay?
              }

              {
                [shifted_dimensions | dims_row_acc],
                [child | children_row_acc],
                simple_row_acc and not overlay?
              }
          end)

        {
          dims_acc ++ Enum.reverse(row_dims),
          children_acc ++ Enum.reverse(row_children),
          row_simple?
        }
      end)

    {content, rendered_width, rendered_height, layer_map} =
      BenchProfile.measure({__MODULE__, :compose}, fn ->
        use_structured_simple_compose? = simple_compose_from_layer_maps?(rendered_children)

        cond do
          simple_row_or_column? and grid.columns == 1 and gap_y == 0 ->
            rows_with_results
            |> Enum.map(fn
              [%{result: %{box: item_box}}] ->
                materialized_content(item_box)

              row ->
                Enum.map_join(row, "\n", fn %{result: %{box: item_box}} ->
                  materialized_content(item_box)
                end)
            end)
            |> BackBreeze.Box.join_vertical(height: total_height)
            |> then(fn {content, width, height} -> {content, width, height, %{}} end)

          simple_row_or_column? and row_count == 1 and gap_x == 0 and
              not use_structured_simple_compose? ->
            rows_with_results
            |> List.flatten()
            |> Enum.map(fn %{result: %{box: item_box}} -> materialized_content(item_box) end)
            |> BackBreeze.Box.join_horizontal()
            |> then(fn {content, width, height} -> {content, width, height, %{}} end)

          simple_row_or_column? and row_count == 1 ->
            children =
              rendered_children
              |> Enum.sort_by(fn child ->
                {child.layer || 0, -(child.top || 0), -(child.left || 0), child.overlay?}
              end)
              |> Enum.map(&%{&1 | position: :absolute})

            %{width: width, height: height, layer_map: layer_map} =
              BackBreeze.Box.compose_absolute_children_layer_map(
                children,
                width: total_width,
                height: total_height,
                clip: true,
                sorted: true
              )

            content =
              if structured? do
                nil
              else
                BackBreeze.Box.layer_map_to_content(layer_map, width, height)
              end

            {content, width, height, layer_map}

          true ->
            children =
              rendered_children
              |> Enum.sort_by(fn child ->
                {child.layer || 0, -(child.top || 0), -(child.left || 0), child.overlay?}
              end)
              |> Enum.map(&%{&1 | position: :absolute})

            %{width: width, height: height, layer_map: layer_map} =
              BackBreeze.Box.compose_absolute_children_layer_map(
                children,
                width: total_width,
                height: total_height,
                clip: true,
                sorted: true
              )

            content =
              if structured? do
                nil
              else
                BackBreeze.Box.layer_map_to_content(layer_map, width, height)
              end

            {content, width, height, layer_map}
        end
      end)

    %{
      content: content,
      width: resolved_extent(style.width, total_width, rendered_width),
      height: resolved_extent(style.height, total_height, rendered_height),
      content_width: rendered_width,
      content_height: rendered_height,
      per_item_dimensions: per_item_dimensions,
      layer_map: layer_map,
      rendered_children: rendered_children
    }
  end

  defp resolved_extent(value, total, rendered) do
    cond do
      is_integer(value) and value > 0 -> value
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

        case style_value do
          value when is_integer(value) and value > 0 -> value
          _ -> nil
        end

      _ ->
        nil
    end
  end

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

  defp render_grid_item(
         %{state: :rendered, width: width, height: height} = item,
         style,
         _structured?,
         _opts
       )
       when width == style.width and height == style.height do
    %{box: item, dimensions: []}
  end

  defp render_grid_item(item, style, true, opts) do
    BackBreeze.Box.render_cached_with_dimensions(%{item | style: style},
      structured: true,
      terminal: Keyword.get(opts, :terminal)
    )
  end

  defp render_grid_item(item, style, false, opts) do
    BackBreeze.Box.render_cached_with_dimensions(%{item | style: style},
      terminal: Keyword.get(opts, :terminal)
    )
  end

  defp shift_dimension(dims, left, top) do
    dims
    |> Map.update(:left, left, &(&1 + left))
    |> Map.update(:top, top, &(&1 + top))
  end

  defp prefix_offsets(values, gap) do
    {offsets, _sum} =
      Enum.map_reduce(values, 0, fn value, sum ->
        {sum, sum + value + gap}
      end)

    offsets
  end

  defp simple_compose_from_layer_maps?(children) do
    Enum.any?(children, fn
      %{content: content, layer_map: layer_map}
      when not is_binary(content) and is_map(layer_map) and map_size(layer_map) > 0 ->
        true

      %{layer_map: layer_map} when is_map(layer_map) and map_size(layer_map) > 0 ->
        true

      _ ->
        false
    end)
  end

  defp materialized_content(%{content: content}) when is_binary(content), do: content

  defp materialized_content(%{layer_map: layer_map, width: width, height: height}) do
    BackBreeze.Box.layer_map_to_content(layer_map, width, height)
  end

  defp style_value(style, side_key) do
    case Map.get(style, side_key) do
      value when is_integer(value) -> value
      _ -> Map.get(style, :padding, 0) || 0
    end
  end
end
