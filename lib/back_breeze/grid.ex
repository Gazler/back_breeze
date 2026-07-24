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
  alias BackBreeze.VirtualText

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
      |> BackBreeze.Style.constrain_height(style.max_height)

    height_offset =
      if(style.border.top, do: 1, else: 0) +
        if(style.border.bottom, do: 1, else: 0) +
        style_value(style, :padding_top) +
        style_value(style, :padding_bottom)

    rows = items |> flow_grid_items() |> Enum.chunk_every(grid.columns)
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
      if cacheable_items?(items) do
        RenderCache.fetch_stable(
          {:grid_render_with_dimensions, structured?, if(terminal, do: terminal.size, else: nil), items, grid, style},
          fn ->
            do_render_with_dimensions(items, grid, style, opts, structured?)
          end
        )
      else
        do_render_with_dimensions(items, grid, style, opts, structured?)
      end
    end)
  end

  defp cacheable_items?(items) when is_list(items), do: Enum.all?(items, &cacheable_item?/1)

  defp cacheable_item?(%{content: %VirtualText{cache?: false}}), do: false

  defp cacheable_item?(%{children: children}) when is_list(children),
    do: Enum.all?(children, &cacheable_item?/1)

  defp cacheable_item?(_item), do: true

  defp do_render_with_dimensions(items, grid, style, opts, structured?) do
    if simple_vertical_grid?(grid) do
      do_render_vertical_stack_with_dimensions(items, grid, style, opts, structured?)
    else
      do_render_grid_with_dimensions(items, grid, style, opts, structured?)
    end
  end

  defp simple_vertical_grid?(%{columns: 1, gap_x: gap_x, gap_y: gap_y}) do
    (is_nil(gap_x) or gap_x == 0) and (is_nil(gap_y) or gap_y == 0)
  end

  defp simple_vertical_grid?(_grid), do: false

  defp flow_grid_items(items), do: Enum.reject(items, &positioned_grid_item?/1)

  defp positioned_grid_item?(%{position: position}), do: position in [:absolute, :fixed]
  defp positioned_grid_item?(_item), do: false

  defp do_render_grid_with_dimensions(items, grid, style, opts, structured?) do
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

    flow_items = flow_grid_items(items)
    rows = Enum.chunk_every(flow_items, grid.columns)
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
      |> constrain_total_height(style, height_offset)

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

    rendered_results =
      BenchProfile.measure({__MODULE__, :children}, fn ->
        {results, _flow_index} =
          Enum.map_reduce(items, 0, fn item, flow_index ->
            if positioned_grid_item?(item) do
              {
                %{
                  item: item,
                  flow_index: nil,
                  result: render_grid_item(item, item.style, structured?, opts)
                },
                flow_index
              }
            else
              row_index = div(flow_index, grid.columns)
              col_index = rem(flow_index, grid.columns)
              row_height = Enum.at(row_heights, row_index, 0)
              col_width = Enum.at(column_widths, col_index, 0)

              style = %{item.style | width: max(col_width, 0), height: max(row_height, 0)}

              {
                %{
                  item: item,
                  flow_index: flow_index,
                  result: render_grid_item(item, style, structured?, opts)
                },
                flow_index + 1
              }
            end
          end)

        results
      end)

    {per_item_dimensions, rendered_flow_children, rendered_overlay_children, simple_row_or_column?} =
      rendered_results
      |> Enum.reduce({[], [], [], true}, fn
        %{flow_index: nil, result: %{dimensions: dimensions, box: item_box}},
        {dims_acc, flow_acc, overlay_acc, _simple_acc} ->
          overlay? = item_box.overlay?
          layer = if(overlay?, do: max(item_box.layer || 0, 1), else: item_box.layer || 0)

          {resolved_left, resolved_top} =
            resolve_positioned_overlay_origin(item_box, total_width, total_height, opts)

          child = %{
            item_box
            | left: resolved_left,
              top: resolved_top,
              layer: layer,
              overlay?: overlay?
          }

          shifted_dimensions =
            Enum.map(dimensions, &shift_dimension(&1, resolved_left, resolved_top))

          {[shifted_dimensions | dims_acc], flow_acc, [child | overlay_acc], false}

        %{flow_index: flow_index, result: %{dimensions: dimensions, box: item_box}},
        {dims_acc, flow_acc, overlay_acc, simple_acc} ->
          row_index = div(flow_index, grid.columns)
          col_index = rem(flow_index, grid.columns)
          left = Enum.at(column_offsets, col_index, 0)
          top = Enum.at(row_offsets, row_index, 0)
          overlay? = item_box.overlay?
          layer = if(overlay?, do: max(item_box.layer || 0, 1), else: item_box.layer || 0)

          child = %{
            item_box
            | left: left,
              top: top,
              layer: layer,
              overlay?: overlay?
          }

          shifted_dimensions = Enum.map(dimensions, &shift_dimension(&1, left, top))

          {
            [shifted_dimensions | dims_acc],
            [child | flow_acc],
            overlay_acc,
            simple_acc and not overlay? and not positioned_grid_item?(item_box)
          }
      end)
      |> then(fn {dims, flow_children, overlay_children, simple?} ->
        {Enum.reverse(dims), Enum.reverse(flow_children), Enum.reverse(overlay_children), simple?}
      end)

    {content, rendered_width, rendered_height, layer_map, fixed_layer_map} =
      BenchProfile.measure({__MODULE__, :compose}, fn ->
        compose_grid_children(
          rendered_flow_children,
          rendered_overlay_children,
          simple_row_or_column?,
          grid,
          row_count,
          gap_x,
          gap_y,
          total_width,
          total_height,
          style,
          structured?
        )
      end)

    %{
      content: content,
      width: resolved_extent(style.width, total_width, rendered_width),
      height:
        resolved_extent(
          BackBreeze.Style.constrain_height(style.height, style.max_height),
          total_height,
          rendered_height
        ),
      content_width: rendered_width,
      content_height: rendered_height,
      per_item_dimensions: per_item_dimensions,
      layer_map: layer_map,
      fixed_layer_map: fixed_layer_map,
      rendered_children: rendered_flow_children ++ rendered_overlay_children
    }
  end

  defp do_render_vertical_stack_with_dimensions(items, grid, style, opts, structured?) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    width_offset =
      if(style.border.left, do: 1, else: 0) +
        if(style.border.right, do: 1, else: 0) +
        style_value(style, :padding_left) +
        style_value(style, :padding_right)

    height_offset =
      if(style.border.top, do: 1, else: 0) +
        if(style.border.bottom, do: 1, else: 0) +
        style_value(style, :padding_top) +
        style_value(style, :padding_bottom)

    flow_items = flow_grid_items(items)
    row_count = grid.rows || length(flow_items)

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
      |> constrain_total_height(style, height_offset)

    row_heights =
      BenchProfile.measure({__MODULE__, :tracks}, fn ->
        resolve_track_sizes(Enum.map(flow_items, &[&1]), row_count, total_height, :height)
      end)

    row_offsets = prefix_offsets(row_heights, 0)

    {per_item_dimensions, rendered_flow_children, rendered_overlay_children, simple_column?} =
      BenchProfile.measure({__MODULE__, :children}, fn ->
        items
        |> Enum.reduce({[], [], [], true, 0}, fn item, {dims_acc, flow_acc, overlay_acc, simple_acc, flow_index} ->
          if positioned_grid_item?(item) do
            %{dimensions: dimensions, box: item_box} =
              render_grid_item(item, item.style, structured?, opts)

            overlay? = item_box.overlay?
            layer = if(overlay?, do: max(item_box.layer || 0, 1), else: item_box.layer || 0)

            {resolved_left, resolved_top} =
              resolve_positioned_overlay_origin(item_box, total_width, total_height, opts)

            child = %{
              item_box
              | left: resolved_left,
                top: resolved_top,
                layer: layer,
                overlay?: overlay?
            }

            shifted_dimensions =
              Enum.map(dimensions, &shift_dimension(&1, resolved_left, resolved_top))

            {[shifted_dimensions | dims_acc], flow_acc, [child | overlay_acc], false, flow_index}
          else
            row_height = Enum.at(row_heights, flow_index, 0)
            style = %{item.style | width: max(total_width, 0), height: max(row_height, 0)}

            %{dimensions: dimensions, box: item_box} =
              render_grid_item(item, style, structured?, opts)

            top = Enum.at(row_offsets, flow_index, 0)
            overlay? = item_box.overlay?
            layer = if(overlay?, do: max(item_box.layer || 0, 1), else: item_box.layer || 0)

            child = %{item_box | left: 0, top: top, layer: layer, overlay?: overlay?}
            shifted_dimensions = Enum.map(dimensions, &shift_dimension(&1, 0, top))

            {
              [shifted_dimensions | dims_acc],
              [child | flow_acc],
              overlay_acc,
              simple_acc and not overlay? and not positioned_grid_item?(item_box),
              flow_index + 1
            }
          end
        end)
        |> then(fn {dims, flow_children, overlay_children, simple?, _flow_index} ->
          {Enum.reverse(dims), Enum.reverse(flow_children), Enum.reverse(overlay_children), simple?}
        end)
      end)

    {content, rendered_width, rendered_height, layer_map, fixed_layer_map} =
      BenchProfile.measure({__MODULE__, :compose}, fn ->
        compose_grid_children(
          rendered_flow_children,
          rendered_overlay_children,
          simple_column?,
          grid,
          row_count,
          0,
          0,
          total_width,
          total_height,
          style,
          structured?
        )
      end)

    %{
      content: content,
      width: resolved_extent(style.width, total_width, rendered_width),
      height:
        resolved_extent(
          BackBreeze.Style.constrain_height(style.height, style.max_height),
          total_height,
          rendered_height
        ),
      content_width: rendered_width,
      content_height: rendered_height,
      per_item_dimensions: per_item_dimensions,
      layer_map: layer_map,
      fixed_layer_map: fixed_layer_map,
      rendered_children: rendered_flow_children ++ rendered_overlay_children
    }
  end

  defp resolved_extent(value, total, rendered) do
    cond do
      is_integer(value) and value > 0 -> value
      value in @auto_sizes -> total
      true -> rendered || total
    end
  end

  defp constrain_total_height(total_height, %{max_height: max_height}, height_offset)
       when is_integer(max_height) and max_height >= 0 do
    min(total_height, max(max_height - height_offset, 0))
  end

  defp constrain_total_height(total_height, _style, _height_offset), do: total_height

  defp compose_grid_children(
         rendered_flow_children,
         rendered_overlay_children,
         simple_row_or_column?,
         grid,
         row_count,
         gap_x,
         gap_y,
         total_width,
         total_height,
         style,
         structured?
       ) do
    use_structured_simple_compose? = simple_compose_from_layer_maps?(rendered_flow_children)

    {content, width, height, layer_map, fixed_layer_map} =
      cond do
        simple_row_or_column? and grid.columns == 1 and gap_y == 0 and
            not use_structured_simple_compose? ->
          rendered_flow_children
          |> join_rendered_column(total_height)
          |> then(fn {content, width, height} -> {content, width, height, %{}, %{}} end)

        simple_row_or_column? and row_count == 1 and gap_x == 0 and
            not use_structured_simple_compose? ->
          rendered_flow_children
          |> join_rendered_row()
          |> then(fn {content, width, height} -> {content, width, height, %{}, %{}} end)

        simple_row_or_column? and row_count == 1 ->
          compose_positioned_grid_children(
            rendered_flow_children,
            total_width,
            total_height,
            style,
            structured?
          )

        true ->
          compose_positioned_grid_children(
            rendered_flow_children,
            total_width,
            total_height,
            style,
            structured?
          )
      end

    if rendered_overlay_children == [] do
      {content, width, height, layer_map, fixed_layer_map}
    else
      base_child = %{
        content: content || "",
        width: width,
        height: height,
        layer: 0,
        layer_map: layer_map,
        fixed_layer_map: fixed_layer_map,
        left: 0,
        top: 0,
        position: :absolute,
        overlay?: false
      }

      compose_positioned_grid_children(
        [base_child | rendered_overlay_children],
        total_width,
        total_height,
        style,
        structured?
      )
    end
  end

  defp compose_positioned_grid_children(children, total_width, total_height, style, structured?) do
    children =
      children
      |> Enum.sort_by(fn child ->
        {child.layer || 0, -sort_offset(child.top), -sort_offset(child.left), child.overlay?}
      end)
      |> Enum.map(&composition_child/1)

    opts = [
      width: total_width,
      height: compose_target_height(style.height, total_height),
      clip: true,
      sorted: true
    ]

    %{
      width: width,
      height: height,
      layer_map: layer_map,
      fixed_layer_map: fixed_layer_map
    } =
      case BackBreeze.Box.compose_non_overlapping_children_layer_map(children, opts) do
        {:ok, result} ->
          result

        :error ->
          BackBreeze.Box.compose_absolute_children_layer_map(children, opts)
      end

    content =
      if structured? do
        nil
      else
        BackBreeze.Box.layer_maps_to_content(layer_map, fixed_layer_map, width, height)
      end

    {content, width, height, layer_map, fixed_layer_map}
  end

  defp composition_child(%{position: :fixed} = child), do: child
  defp composition_child(child), do: %{child | position: :absolute}

  defp compose_target_height(value, total) do
    case value do
      extent when extent in [:screen, :full] -> total
      extent when is_integer(extent) and extent > 0 -> total
      _ -> nil
    end
  end

  defp sort_offset(offset) when is_integer(offset), do: offset
  defp sort_offset(_offset), do: 0

  defp resolve_positioned_overlay_origin(%{position: :fixed} = child, _width, _height, opts) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    {resolve_overlay_edge(child.left, child.right, child.width, screen_width),
     resolve_overlay_edge(child.top, child.bottom, child.height, screen_height)}
  end

  defp resolve_positioned_overlay_origin(child, width, height, _opts) do
    {resolve_overlay_edge(child.left, child.right, child.width, width),
     resolve_overlay_edge(child.top, child.bottom, child.height, height)}
  end

  defp resolve_overlay_edge(value, _opposite, _child_size, _container_size)
       when is_integer(value),
       do: value

  defp resolve_overlay_edge(:center, _opposite, child_size, container_size)
       when is_integer(child_size) and is_integer(container_size) do
    max(div(container_size - child_size, 2), 0)
  end

  defp resolve_overlay_edge(nil, opposite, child_size, container_size)
       when is_integer(opposite) and is_integer(child_size) and is_integer(container_size) do
    max(container_size - child_size - opposite, 0)
  end

  defp resolve_overlay_edge(_, _, _, _), do: 0

  defp resolve_track_sizes(_rows, track_count, _total, _axis) when track_count <= 0, do: []

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
      structured: true,
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
      %{fixed_layer_map: fixed_layer_map}
      when is_map(fixed_layer_map) and map_size(fixed_layer_map) > 0 ->
        true

      %{content: content, layer_map: layer_map}
      when not is_binary(content) and is_map(layer_map) and map_size(layer_map) > 0 ->
        true

      %{layer_map: layer_map} when is_map(layer_map) and map_size(layer_map) > 0 ->
        true

      _ ->
        false
    end)
  end

  defp join_rendered_column(children, total_height) do
    content = Enum.map_join(children, "\n", &materialized_content/1)
    width = Enum.reduce(children, 0, fn child, acc -> max(acc, rendered_width(child)) end)
    height = Enum.reduce(children, 0, fn child, acc -> acc + rendered_height(child) end)

    {content, width, min(height, total_height)}
  end

  defp join_rendered_row(children) do
    child_rows =
      Enum.map(children, fn child ->
        {rendered_width(child), rendered_height(child), content_rows(child)}
      end)

    width =
      Enum.reduce(child_rows, 0, fn {child_width, _height, _rows}, acc -> acc + child_width end)

    height =
      Enum.reduce(child_rows, 0, fn {_width, child_height, _rows}, acc ->
        max(acc, child_height)
      end)

    rows =
      if height == 0 do
        []
      else
        Enum.map(0..(height - 1), fn row_index ->
          Enum.map(child_rows, fn {child_width, _child_height, rows} ->
            row_at(rows, row_index) || String.duplicate(" ", child_width)
          end)
        end)
      end

    {IO.iodata_to_binary(Enum.intersperse(rows, "\n")), width, height}
  end

  defp content_rows(child), do: child |> materialized_content() |> :binary.split("\n", [:global])

  defp row_at(rows, index) when is_list(rows), do: Enum.at(rows, index)

  defp rendered_width(%{width: width}) when is_integer(width), do: max(width, 0)

  defp rendered_width(%{content: content}) when is_binary(content),
    do: BackBreeze.Utils.string_length(content)

  defp rendered_width(_child), do: 0

  defp rendered_height(%{height: height}) when is_integer(height), do: max(height, 0)

  defp rendered_height(%{content: content}) when is_binary(content) do
    content
    |> :binary.split("\n", [:global])
    |> length()
  end

  defp rendered_height(_child), do: 0

  defp materialized_content(%{fixed_layer_map: fixed_layer_map} = child)
       when is_map(fixed_layer_map) and map_size(fixed_layer_map) > 0 do
    if is_map(child.layer_map) and map_size(child.layer_map) > 0 do
      BackBreeze.Box.layer_map_to_content(child.layer_map, child.width, child.height)
    else
      ""
    end
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
