defmodule BackBreeze.Grid.Children do
  @moduledoc false

  alias BackBreeze.Box.CacheKey

  def prepare(children, context) do
    children
    |> Enum.reduce(empty_prepare_state(), &prepare_child(&1, &2, context))
    |> finish_prepare_state()
  end

  defp empty_prepare_state, do: {[], [], 0}

  defp finish_prepare_state({children, dims, _flow_index}) do
    {Enum.reverse(children), Enum.reverse(dims)}
  end

  defp prepare_child(child_box, state, context) do
    case prepare_mode(child_box) do
      :positioned -> append_positioned_child(child_box, state, context)
      :cached_nested_grid -> append_cached_nested_grid_child(child_box, state, context)
      :flow -> append_flow_child(child_box, state, context)
    end
  end

  defp prepare_mode(child_box) do
    cond do
      overlay_position?(child_box) -> :positioned
      cacheable_nested_grid_child?(child_box) -> :cached_nested_grid
      true -> :flow
    end
  end

  defp cacheable_nested_grid_child?(%{display: %BackBreeze.Grid{}, children: [_ | _]} = child_box) do
    CacheKey.cacheable?(child_box)
  end

  defp cacheable_nested_grid_child?(_child_box), do: false

  defp append_positioned_child(child_box, {children, dims, flow_index}, %{box: box}) do
    child_box = inherit_parent_colors(child_box, box.style)
    {[child_box | children], [%{dims: nil, left: 0, top: 0} | dims], flow_index}
  end

  defp append_flow_child(child_box, {children, dims, flow_index}, context) do
    child_box = inherit_parent_colors(child_box, context.box.style)
    position = flow_position(flow_index, context)

    {
      [child_box | children],
      [child_dimension(position) | dims],
      flow_index + 1
    }
  end

  defp append_cached_nested_grid_child(child_box, {children, dims, flow_index}, context) do
    child_box = inherit_parent_colors(child_box, context.box.style)
    position = flow_position(flow_index, context)
    style = nested_grid_child_style(child_box, position, context)
    rendered_grid = render_nested_grid_child(child_box, style, context.opts)
    child = rendered_nested_grid_child(child_box, style, rendered_grid)
    grouped_dims = nested_grid_child_dimensions(rendered_grid, position)

    {[child | children], [%{dims: grouped_dims} | dims], flow_index + 1}
  end

  defp flow_position(flow_index, context) do
    row_index = div(flow_index, context.box.display.columns)
    col_index = rem(flow_index, context.box.display.columns)
    left = Enum.at(context.column_offsets, col_index, 0)
    top = Enum.at(context.row_offsets, row_index, 0)
    {row_index, col_index, left, top}
  end

  defp child_dimension({_row_index, _col_index, left, top}) do
    %{dims: nil, left: left, top: top}
  end

  defp nested_grid_child_style(child_box, {row_index, col_index, _left, _top}, context) do
    %{
      child_box.style
      | width: Enum.at(context.column_widths, col_index, context.item_width),
        height: Enum.at(context.row_heights, row_index, context.item_height)
    }
  end

  defp render_nested_grid_child(child_box, style, opts) do
    BackBreeze.Grid.render_structured_with_dimensions(
      child_box.children,
      child_box.display,
      style,
      opts
    )
  end

  defp rendered_nested_grid_child(child_box, style, rendered_grid) do
    %{
      content: content,
      width: width,
      height: height,
      content_height: content_height,
      layer_map: layer_map,
      fixed_layer_map: fixed_layer_map
    } = rendered_grid

    %{
      child_box
      | children: [],
        content: content,
        width: width,
        height: height,
        state: :rendered,
        layer_map: layer_map,
        fixed_layer_map: fixed_layer_map,
        overlay?: nested_grid_child_overlay?(child_box, style, content_height, height)
    }
  end

  defp nested_grid_child_overlay?(child_box, style, content_height, height) do
    visual_overflow?(style, content_height, height) or contains_overlay_descendants?(child_box)
  end

  defp nested_grid_child_dimensions(rendered_grid, {_row_index, _col_index, left, top}) do
    %{width: width, height: height, per_item_dimensions: inner_dimensions} = rendered_grid

    container_dim = %{
      content_height: height,
      viewport_height: height,
      height: height,
      width: width,
      viewport_width: width,
      content_width: width,
      left: left,
      top: top
    }

    shifted_inner_dimensions =
      inner_dimensions
      |> List.flatten()
      |> shift_dimensions(left, top)

    [container_dim | shifted_inner_dimensions]
  end

  defp shift_dimensions(dimensions, left_offset, top_offset) do
    Enum.map(dimensions, &shift_dimension(&1, left_offset, top_offset))
  end

  defp shift_dimension(dims, left_offset, top_offset) do
    dims
    |> Map.update(:left, left_offset, &(&1 + left_offset))
    |> Map.update(:top, top_offset, &(&1 + top_offset))
  end

  defp inherit_parent_colors(%{style: style} = child, parent_style) do
    style =
      style
      |> maybe_inherit_background(parent_style.background_color)
      |> maybe_inherit_foreground(parent_style.foreground_color)

    %{child | style: style}
  end

  defp maybe_inherit_background(style, nil), do: style

  defp maybe_inherit_background(style, background_color) do
    if is_nil(style.background_color) do
      BackBreeze.Style.background_color(style, background_color)
    else
      style
    end
  end

  defp maybe_inherit_foreground(style, nil), do: style

  defp maybe_inherit_foreground(style, foreground_color) do
    if is_nil(style.foreground_color) do
      BackBreeze.Style.foreground_color(style, foreground_color)
    else
      style
    end
  end

  defp overlay_position?(%{position: position}), do: position in [:absolute, :fixed]

  defp contains_overlay_descendants?(%{position: position}) when position in [:absolute, :fixed],
    do: true

  defp contains_overlay_descendants?(%{children: children}) when is_list(children) do
    Enum.any?(children, &contains_overlay_descendants?/1)
  end

  defp contains_overlay_descendants?(_), do: false

  defp visual_overflow?(%{overflow: :hidden}, _content_height, _height), do: false
  defp visual_overflow?(_style, content_height, height), do: content_height > max(height || 0, 0)
end
