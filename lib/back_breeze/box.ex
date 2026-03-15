defmodule BackBreeze.Box do
  @moduledoc """
  A Box is the basic styling primitive used in BackBreeze. If a box has children,
  they will be rendered first and collapsed down, until a single box remains with
  the rendered contents.
  """
  alias BackBreeze.Ucwidth

  defstruct content: "",
            children: [],
            style: %BackBreeze.Style{},
            width: nil,
            height: nil,
            state: :ready,
            position: :relative,
            left: nil,
            top: nil,
            right: nil,
            bottom: nil,
            display: :block,
            scroll: {0, 0},
            layer: 0,
            layer_map: %{},
            overlay?: false

  @doc """
  Create a new `BackBreeze.Box` struct.

  ## Options

   * `:style` - a style map, with any valid keys from `BackBreeze.Style`. The `:border`
     style can be provided as `:line` for convenience.

  All other options are passed to the `BackBreeze.Box` struct.

  """
  def new(opts) do
    map = Map.new(opts)
    style = Map.get(map, :style, %{})

    style =
      case Map.get(style, :border) do
        :line -> %{style | border: BackBreeze.Border.line()}
        :rounded -> %{style | border: BackBreeze.Border.rounded()}
        _ -> style
      end

    style =
      case Map.get(style, :scrollbar) do
        true -> BackBreeze.Style.scrollbar(style, true)
        _ -> style
      end

    style = struct(BackBreeze.Style, style)

    struct(BackBreeze.Box, Map.put(map, :style, style))
  end

  @doc """
  Render a box and a tree of its children.

  ## Options

    * `:terminal` - the terminal to use. This is used for the terminal size if provided.
  """
  def render(box, opts \\ []) do
    render_with_dimensions(box, opts)
    |> Map.get(:box)
  end

  @doc """
  Render a box and a tree of its children whilst tracking dimensions.

  This function returns the box as with `render/2`, but it is wrapped in a map which
  also contains the rendered dimension for each box as a flat list.
  This can be used at a higher level to determine the viewport.

  ## Options

  See `render/2`
  """

  def render_with_dimensions(box, opts \\ []) do
    %{box: box, dimensions: dimensions} =
      render_and_calc(%{box: box, dimensions: [], id: 0}, opts)

    dimensions = Enum.sort(dimensions) |> Enum.map(&elem(&1, 1))
    %{box: box, dimensions: dimensions}
  end

  defp render_and_calc(%{box: %{state: :rendered}} = acc, _opts) do
    acc
  end

  defp render_and_calc(%{box: %{children: []} = box} = acc, opts) do
    {content, dimensions, width} = render_self(box, opts)

    dimensions =
      dimensions
      |> Map.put(:width, width)
      |> Map.put_new(:viewport_width, width)
      |> Map.put_new(:content_width, width)
      |> Map.put(:left, 0)
      |> Map.put(:top, 0)

    {scrollbar_config, _} = BackBreeze.Scrollbar.normalize(box.style.scrollbar, box.style)

    {content, width, layer_map} =
      if box.style.overflow == :hidden and scrollbar_config.enabled do
        {layer_map, max_width, max_height} = generate_layer_map(content, %{}, 0, 0)

        layer_map =
          BackBreeze.Scrollbar.add_to_layer_map(layer_map, %{
            style: box.style,
            scroll: box.scroll,
            content_height: dimensions.content_height,
            content_width: raw_content_width(box.content),
            max_x: max_width,
            max_y: max_height
          })

        {layer_maps_to_content(layer_map, %{}, %{
           start_x: 0,
           start_y: 0,
           max_x: max_width,
           max_y: max_height
         }), max_width + 1, layer_map}
      else
        {content, width, %{}}
      end

    box = %{
      box
      | content: content,
        width: width,
        height: dimensions.height,
        state: :rendered,
        children: [],
        layer_map: layer_map
    }

    %{acc | box: box, dimensions: [{acc.id, dimensions} | acc.dimensions], id: acc.id + 1}
  end

  defp render_and_calc(%{box: box} = acc, opts) do
    prev_id = acc.id

    child_length = length(box.children)

    {child_layer_map, child_width, child_height, has_overlay_children?, child_layer, acc} =
      render_children(%{acc | id: prev_id + 1}, opts)

    style_width = if box.style.width == :auto, do: 0, else: box.style.width

    width =
      cond do
        box.style.overflow == :hidden ->
          box.style.width

        is_integer(box.style.width) and box.style.width > 0 ->
          box.style.width

        true ->
          max(style_width, child_width)
      end

    style_height = if box.style.height == :auto, do: 0, else: box.style.height

    height =
      cond do
        box.style.overflow == :hidden ->
          box.style.height

        is_integer(box.style.height) and box.style.height > 0 ->
          box.style.height

        true ->
          max(style_height, child_height)
      end

    style = %{box.style | width: width, height: height}

    # We don't want offset to apply twice in cases when there are children.
    {content, dimensions, _width} =
      render_self(%{box | width: width, height: height, style: style, scroll: {0, 0}}, opts)

    border_rows =
      if(box.style.border.top, do: 1, else: 0) +
        if box.style.border.bottom, do: 1, else: 0

    dimensions =
      Enum.zip(Enum.reverse(box.children), Enum.take(acc.dimensions, child_length))
      |> Enum.reduce(
        %{
          content_height: 0,
          viewport_height: dimensions.height - border_rows,
          viewport_width: width,
          height: dimensions.height,
          width: width
        },
        fn
          {%{position: position}, _}, acc when position in [:absolute, :fixed] -> acc
          {_, {_, dims}}, acc -> %{acc | content_height: dims.height + acc.content_height}
        end
      )

    dimensions =
      if box.style.height in [:auto, :full] ||
           (is_integer(box.style.height) && box.style.height <= 0 && box.style.width != :screen) do
        resolved_height = max(dimensions.height, dimensions.content_height)

        %{
          dimensions
          | height: resolved_height,
            viewport_height: max(dimensions.viewport_height, resolved_height - border_rows)
        }
      else
        dimensions
      end

    dimensions =
      dimensions
      |> Map.put(:width, width)
      |> Map.put_new(:viewport_width, width)
      |> Map.put_new(:content_width, width)
      |> Map.put(:left, 0)
      |> Map.put(:top, 0)

    acc = %{acc | dimensions: [{prev_id, dimensions} | acc.dimensions], id: acc.id}

    {layer_map, max_width, max_height} = generate_layer_map(content, %{}, 0, 0)
    max_height = max(max_height, max(rendered_height(content) - 1, 0))

    {_, offset_left} = box.scroll

    child_layer_map =
      if offset_left > 0 do
        shift_layer_map(child_layer_map, -offset_left, 0)
      else
        child_layer_map
      end

    clip_relative_children? =
      box.style.overflow == :hidden ||
        (is_integer(box.style.height) && box.style.height > 0 && !has_overlay_children?)

    child_layer_map =
      if clip_relative_children? do
        clip_child_layer_map(child_layer_map, box.style, max_width, max_height)
      else
        child_layer_map
      end

    max_width =
      if box.style.overflow == :hidden do
        max_width
      else
        max(max_width, child_width)
      end

    max_height =
      cond do
        box.style.overflow == :hidden ->
          max_height

        box.style.height in [:auto, :full] ||
            (is_integer(box.style.height) && box.style.height <= 0) ->
          max(max_height, child_height)

        has_overlay_children? ->
          max(max_height, child_height)

        true ->
          max_height
      end

    child_layer_map =
      BackBreeze.Scrollbar.add_to_layer_map(child_layer_map, %{
        style: box.style,
        scroll: box.scroll,
        content_height: dimensions.content_height,
        content_width: child_width,
        max_x: max_width,
        max_y: max_height
      })

    content =
      layer_maps_to_content(layer_map, child_layer_map, %{
        start_x: 0,
        start_y: 0,
        max_x: max_width,
        max_y: max_height
      })

    box = %{
      box
      | content: content,
        width: max_width + 1,
        height: max_height + 1,
        layer: max(box.layer || 0, child_layer || 0),
        state: :rendered,
        layer_map: Map.merge(layer_map, child_layer_map),
        overlay?: has_overlay_children?
    }

    %{acc | box: box}
  end

  defp render_self(box, opts) do
    {offset_top, _} = box.scroll
    opts = Keyword.put(opts, :offset_top, offset_top)
    {content, dimensions} = BackBreeze.Style.calculate_and_render(box.style, box.content, opts)

    items =
      String.split(content, "\n")
      |> Enum.map(&{BackBreeze.Utils.string_length(&1), &1})

    {max_width, _} = Enum.max(items)
    {content, dimensions, max_width}
  end

  defp render_children(
         %{box: %{children: children, display: %BackBreeze.Grid{}} = box} = acc,
         opts
       ) do
    %{
      width: item_width,
      height: item_height,
      column_widths: column_widths,
      row_heights: row_heights
    } =
      BackBreeze.Grid.precompute(children, box.display, box.style, opts)

    {children, grouped_dims} =
      children
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn
        {%{display: %BackBreeze.Grid{}, children: children} = child_box, child_index}, child_acc
        when children != [] ->
          row_index = div(child_index, box.display.columns)
          col_index = rem(child_index, box.display.columns)
          child_left = span_before(column_widths, col_index)
          child_top = span_before(row_heights, row_index)

          style = %{
            child_box.style
            | width: Enum.at(column_widths, col_index, item_width),
              height: Enum.at(row_heights, row_index, item_height)
          }

          %{content: content, width: w, height: h, per_item_dimensions: inner_dimensions} =
            BackBreeze.Grid.render_with_dimensions(
              child_box.children,
              child_box.display,
              style,
              opts
            )

          {children, dims} = child_acc

          child = %{
            child_box
            | children: [],
              content: content,
              width: w,
              height: h,
              state: :rendered,
              overlay?:
                rendered_height(content) > max(h || 0, 0) ||
                  contains_overlay_descendants?(child_box)
          }

          container_dim = %{
            content_height: h,
            viewport_height: h,
            height: h,
            width: w,
            viewport_width: w,
            content_width: w,
            left: child_left,
            top: child_top
          }

          shifted_inner_dimensions =
            inner_dimensions
            |> List.flatten()
            |> shift_dimensions(child_left, child_top)

          {children ++ [child], dims ++ [%{dims: [container_dim | shifted_inner_dimensions]}]}

        {child_box, child_index}, child_acc ->
          row_index = div(child_index, box.display.columns)
          col_index = rem(child_index, box.display.columns)
          child_left = span_before(column_widths, col_index)
          child_top = span_before(row_heights, row_index)
          {children, dims} = child_acc
          {children ++ [child_box], dims ++ [%{dims: nil, left: child_left, top: child_top}]}
      end)

    children = set_layer(children, [], -1)

    has_overlay_children? =
      Enum.any?(
        children,
        &(overlay_position?(&1) || &1.overlay? || contains_overlay_descendants?(&1))
      )

    relative = Enum.filter(children, &(not overlay_position?(&1)))

    {layer, style} =
      case {children, relative} do
        {[%{} | _], [x | _]} -> {Enum.max(Enum.map(children, & &1.layer)), x.style}
        {[%{} | _], _} -> {Enum.max(Enum.map(children, & &1.layer)), %BackBreeze.Style{}}
        _ -> {0, %BackBreeze.Style{}}
      end

    %{content: content, width: width, height: height, per_item_dimensions: per_item_dims} =
      BackBreeze.Grid.render_with_dimensions(children, box.display, box.style, opts)

    {final_id, new_dims} =
      Enum.zip(grouped_dims, per_item_dims)
      |> Enum.reduce({acc.id, []}, fn
        {%{dims: nil, left: left, top: top}, child_dims}, {id, acc_d} ->
          shifted_child_dims = shift_dimensions(child_dims, left, top)
          entries = Enum.with_index(shifted_child_dims, id) |> Enum.map(fn {d, i} -> {i, d} end)
          {id + length(child_dims), acc_d ++ entries}

        {%{dims: grouped}, _}, {id, acc_d} ->
          entries = Enum.with_index(grouped, id) |> Enum.map(fn {d, i} -> {i, d} end)
          {id + length(grouped), acc_d ++ entries}
      end)

    acc = %{acc | dimensions: acc.dimensions ++ new_dims, id: final_id}

    absolutes = Enum.filter(children, &overlay_position?/1)

    relative = %{
      box
      | style: style,
        content: content,
        children: [],
        height: height,
        width: width,
        layer: layer,
        position: :relative,
        left: nil,
        top: nil
    }

    {layer_map, width, height, acc} = combine_children(box, absolutes, relative, acc, opts)
    {layer_map, width, height, has_overlay_children?, layer, acc}
  end

  defp render_children(%{box: %{children: children} = box} = acc, opts) when children != [] do
    parent_width = resolved_parent_width(box, opts)
    parent_height = resolved_parent_height(box, opts)

    {children, acc, _used_extent} =
      set_layer(children, [], -1)
      |> Enum.map(&resolve_absolute_fill_offsets(&1, box.style.border))
      |> resolve_fill_widths(parent_width, box.display, box.style.overflow)
      |> Enum.reduce({[], acc, 0}, fn child, {boxes, child_acc, used_extent} ->
        child = resolve_fill_height(child, box.display, parent_height, used_extent)
        child_id = child_acc.id
        child_acc = render_and_calc(%{child_acc | box: child}, opts)
        {child_left, child_top} = child_origin(box, child_acc.box, used_extent, opts)

        child_acc =
          shift_dimension_range(child_acc, child_id, child_acc.id, child_left, child_top)

        used_extent =
          if overlay_position?(child_acc.box) do
            used_extent
          else
            used_extent + child_extent(child_acc.box, box.display)
          end

        {[child_acc.box | boxes], child_acc, used_extent}
      end)

    children = Enum.reverse(children)
    has_overlay_children? = Enum.any?(children, &(overlay_position?(&1) || &1.overlay?))

    relative =
      children
      |> Enum.filter(&(not overlay_position?(&1)))

    {layer, style} =
      case {children, relative} do
        {[%{} | _], [x | _]} -> {Enum.max(Enum.map(children, & &1.layer)), x.style}
        {[%{} | _], _} -> {Enum.max(Enum.map(children, & &1.layer)), %BackBreeze.Style{}}
        _ -> {0, %BackBreeze.Style{}}
      end

    items = Enum.map(relative, & &1.content)

    relative_has_overlay? =
      Enum.any?(relative, fn child ->
        child.overlay? || rendered_height(child.content) > max(child.height || 0, 0)
      end)

    resolved_join_height =
      cond do
        box.display == :block && relative_has_overlay? && box.style.overflow != :hidden ->
          nil

        true ->
          box.style.height
      end

    opts = Keyword.put(opts, :height, resolved_join_height)
    opts = Keyword.put(opts, :scroll, box.scroll)

    {content, width, height} =
      case box.display do
        :block -> join_vertical(items, opts)
        :inline -> join_horizontal(items)
      end

    absolutes = Enum.filter(children, &overlay_position?/1)

    relative = %{
      box
      | style: style,
        content: content,
        children: [],
        height: height,
        width: width,
        layer: layer,
        position: :relative,
        left: nil,
        top: nil
    }

    {layer_map, width, height, acc} = combine_children(box, absolutes, relative, acc, opts)
    {layer_map, width, height, has_overlay_children?, layer, acc}
  end

  defp combine_children(box, absolutes, relative, acc, opts) do
    rendered_boxes = [relative | absolutes] |> Enum.sort_by(& &1.layer)

    border = box.style.border

    Enum.reduce(rendered_boxes, {%{}, 0, 0, acc}, fn rendered_box,
                                                     {layer_map, max_width, max_height, acc} ->
      {start_x, y} =
        case {rendered_box.position, border.left, border.top} do
          {position, _, _} when position in [:absolute, :fixed] ->
            resolve_overlay_origin(rendered_box, box, relative, border, opts)

          {_, nil, nil} ->
            {0, 0}

          {_, _, nil} ->
            {1, 0}

          _ ->
            {1, 1}
        end

      {map, width, height} =
        cond do
          overlay_position?(rendered_box) && map_size(rendered_box.layer_map) > 0 ->
            merge_layer_map(layer_map, rendered_box.layer_map, start_x, y)

          true ->
            generate_layer_map(rendered_box.content, layer_map, start_x, y)
        end

      {map, max(max_width, width), max(max_height, height), acc}
    end)
  end

  defp merge_layer_map(target_map, source_map, offset_x, offset_y) do
    {map, max_x, max_y} =
      Enum.reduce(source_map, {target_map, 0, 0}, fn
        {{_y, _x}, {" ", ""}}, acc ->
          acc

        {{y, x}, {char, _} = value}, {acc, cur_max_x, cur_max_y} ->
          shifted_x = x + offset_x
          shifted_y = y + offset_y
          width = Ucwidth.width(char)

          {
            Map.put(acc, {shifted_y, shifted_x}, value),
            max(cur_max_x, shifted_x + width - 1),
            max(cur_max_y, shifted_y)
          }

        _, acc ->
          acc
      end)

    {map, max_x, max_y}
  end

  defp generate_layer_map(content, layer_map, start_x, y) do
    reset = Termite.Style.reset_code()

    {_x, y, {acc, _, _}} =
      content
      |> String.graphemes()
      |> Enum.reduce({start_x, y, {layer_map, false, ""}}, fn
        "\n", {_x, y, acc} -> {start_x, y + 1, acc}
        "\e", {x, y, {map, false, _}} -> {x, y, {map, true, "\e"}}
        "m", {x, y, {map, true, seq}} -> {x, y, {map, false, seq <> "m"}}
        c, {x, y, {map, true, seq}} -> {x, y, {map, true, seq <> c}}
        c, {x, y, {map, _, ^reset}} -> add_layer_char(c, map, x, y, "", reset)
        c, {x, y, {map, _, seq}} -> add_layer_char(c, map, x, y, seq, seq)
      end)

    {max_x, map} = Map.pop(acc, :max_x, 1)

    {map, max_x - 1, y}
  end

  defp layer_maps_to_content(layer_map, overlay_layer_map, %{
         start_x: start_x,
         start_y: start_y,
         max_x: max_x,
         max_y: max_y
       }) do
    reset = Termite.Style.reset_code()

    content =
      Enum.map(start_y..max_y, fn y ->
        {content, buffer, style, _} =
          Enum.reduce(start_x..max_x, {"", "", "", false}, fn x,
                                                              {acc, buffer, last_style, skip} ->
            overlay_point = Map.get(overlay_layer_map, {y, x})

            point =
              if skip do
                overlay_point
              else
                overlay_point || Map.get(layer_map, {y, x})
              end

            skip_next =
              case overlay_point do
                {char, _} -> Ucwidth.width(char) == 2
                _ -> false
              end

            case {point, buffer, last_style} do
              {nil, _, _} -> {acc, buffer, last_style, skip_next}
              {{char, style}, _, style} -> {acc, buffer <> char, style, skip_next}
              {{char, style}, _, ""} -> {acc <> buffer, char, style, skip_next}
              {{char, style}, _, last} -> {acc <> last <> buffer <> reset, char, style, skip_next}
            end
          end)

        case {buffer, style} do
          {"", _} -> content
          {_, nil} -> content <> buffer
          {_, ""} -> content <> buffer
          {_, style} -> content <> style <> buffer <> reset
        end
      end)

    Enum.join(content, "\n")
  end

  defp clip_child_layer_map(layer_map, %{overflow: :hidden, border: border}, max_x, max_y)
       when is_integer(max_x) and is_integer(max_y) do
    left = if border.left, do: 1, else: 0
    top = if border.top, do: 1, else: 0
    right = max(max_x - if(border.right, do: 1, else: 0), left - 1)
    bottom = max(max_y - if(border.bottom, do: 1, else: 0), top - 1)

    Enum.reduce(layer_map, %{}, fn
      {{y, x}, value}, acc when x >= left and x <= right and y >= top and y <= bottom ->
        Map.put(acc, {y, x}, value)

      _, acc ->
        acc
    end)
  end

  defp clip_child_layer_map(layer_map, _style, _width, _height), do: layer_map

  defp shift_layer_map(layer_map, shift_x, shift_y) do
    Enum.reduce(layer_map, %{}, fn
      {{y, x}, value}, acc ->
        Map.put(acc, {y + shift_y, x + shift_x}, value)

      _, acc ->
        acc
    end)
  end

  defp add_layer_char(c, map, x, y, current_seq, seq) do
    width = Ucwidth.width(c)

    map =
      map
      |> Map.update(:max_x, x + width, fn cur -> max(cur, x + width) end)
      |> Map.put({y, x}, {c, current_seq})

    {x + width, y, {map, false, seq}}
  end

  defp raw_content_width(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> Enum.map(&BackBreeze.Utils.string_length/1)
    |> Enum.max(fn -> 0 end)
  end

  defp raw_content_width(_), do: 0

  defp rendered_height(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> length()
  end

  defp rendered_height(_), do: 0

  defp resolved_parent_width(%{style: %{width: width, border: border}}, opts) do
    case width do
      w when is_integer(w) ->
        w

      :screen ->
        {screen_width, _screen_height} =
          BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

        max(screen_width - border_horizontal(border), 0)

      _ ->
        nil
    end
  end

  defp resolved_parent_height(%{style: %{height: height, border: border}}, opts) do
    case height do
      h when is_integer(h) ->
        h

      :screen ->
        {_screen_width, screen_height} =
          BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

        max(screen_height - border_vertical(border), 0)

      _ ->
        nil
    end
  end

  defp border_horizontal(border),
    do: if(border.left, do: 1, else: 0) + if(border.right, do: 1, else: 0)

  defp border_vertical(border),
    do: if(border.top, do: 1, else: 0) + if(border.bottom, do: 1, else: 0)

  defp resolve_fill_widths(children, nil, _display, _overflow), do: children

  defp resolve_fill_widths(children, parent_width, display, overflow) do
    Enum.map(children, fn child ->
      auto_fill_container? =
        display == :block &&
          child.style.width == :auto &&
          (match?(%BackBreeze.Grid{}, child.display) || child.children != [])

      auto_wrap_leaf_child? =
        display == :block &&
          overflow != :hidden &&
          not overlay_position?(child) &&
          child.style.width == :auto &&
          child.children == [] &&
          plain_wrap_leaf_child?(child)

      should_fill_width? =
        child.style.width == :full ||
          auto_wrap_leaf_child? ||
          (not overlay_position?(child) && auto_fill_container?)

      if should_fill_width? do
        border_adj = border_horizontal(child.style.border)

        %{child | style: %{child.style | width: max(0, parent_width - border_adj)}}
      else
        child
      end
    end)
  end

  defp resolve_fill_height(child, _display, nil, _used_height), do: child

  defp resolve_fill_height(child, :inline, parent_height, _used_height) do
    if child.style.height == :full do
      border_adj = border_vertical(child.style.border)

      %{child | style: %{child.style | height: max(0, parent_height - border_adj)}}
    else
      child
    end
  end

  defp resolve_fill_height(child, :block, parent_height, used_height) do
    if child.style.height != :full do
      child
    else
      border_adj = border_vertical(child.style.border)

      used_height = if overlay_position?(child), do: 0, else: used_height
      %{child | style: %{child.style | height: max(0, parent_height - used_height - border_adj)}}
    end
  end

  defp resolve_absolute_fill_offsets(
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

  defp resolve_absolute_fill_offsets(
         %{position: position, style: %{width: :full}} = child,
         border
       )
       when position in [:absolute, :fixed] do
    %{child | left: default_fill_offset(child.left, border.left, position)}
  end

  defp resolve_absolute_fill_offsets(
         %{position: position, style: %{height: :full}} = child,
         border
       )
       when position in [:absolute, :fixed] do
    %{child | top: default_fill_offset(child.top, border.top, position)}
  end

  defp resolve_absolute_fill_offsets(child, _border), do: child

  defp default_fill_offset(nil, edge, :absolute), do: if(edge, do: 1, else: 0)
  defp default_fill_offset(0, edge, :absolute), do: if(edge, do: 1, else: 0)
  defp default_fill_offset(nil, _edge, :fixed), do: 0
  defp default_fill_offset(0, _edge, :fixed), do: 0
  defp default_fill_offset(offset, _edge, _position), do: offset

  defp child_origin(
         %{display: :inline, style: %{border: border}} = parent,
         child,
         used_extent,
         opts
       ) do
    left = used_extent + border_left_offset(border)
    top = border_top_offset(border)

    if overlay_position?(child),
      do: resolve_overlay_origin(child, parent, parent.style.border, opts),
      else: {left, top}
  end

  defp child_origin(%{style: %{border: border}} = parent, child, used_extent, opts) do
    left = border_left_offset(border)
    top = used_extent + border_top_offset(border)

    if overlay_position?(child),
      do: resolve_overlay_origin(child, parent, parent.style.border, opts),
      else: {left, top}
  end

  defp child_extent(child, :inline), do: child.width || raw_content_width(child.content)
  defp child_extent(child, _display), do: child.height || rendered_height(child.content)
  defp span_before(values, index), do: values |> Enum.take(index) |> Enum.sum()

  defp shift_dimension_range(acc, from_id, to_id, left_offset, top_offset) do
    dimensions =
      Enum.map(acc.dimensions, fn
        {id, dims} when id >= from_id and id < to_id ->
          {id, shift_dimension(dims, left_offset, top_offset)}

        entry ->
          entry
      end)

    %{acc | dimensions: dimensions}
  end

  defp shift_dimensions(dimensions, left_offset, top_offset) do
    Enum.map(dimensions, &shift_dimension(&1, left_offset, top_offset))
  end

  defp shift_dimension(dims, left_offset, top_offset) do
    dims
    |> Map.update(:left, left_offset, &(&1 + left_offset))
    |> Map.update(:top, top_offset, &(&1 + top_offset))
  end

  defp border_left_offset(border), do: if(border.left, do: 1, else: 0)
  defp border_top_offset(border), do: if(border.top, do: 1, else: 0)

  defp set_layer([], result, _layer) do
    Enum.reverse(result)
  end

  defp set_layer([%{position: position} = box | rest], result, layer)
       when position in [:absolute, :fixed] do
    next_layer = max(layer + 1, box.layer || layer + 1)
    set_layer(rest, [%{box | layer: next_layer} | result], next_layer + 1)
  end

  defp set_layer([box | rest], result, layer) when is_binary(box) do
    set_layer(rest, [box | result], layer || 0)
  end

  defp set_layer([box | rest], result, nil) do
    next_layer = box.layer || 0
    set_layer(rest, [%{box | layer: next_layer} | result], next_layer)
  end

  defp set_layer([box | rest], result, layer) do
    next_layer = box.layer || layer
    set_layer(rest, [%{box | layer: next_layer} | result], next_layer)
  end

  defp resolve_overlay_origin(child, parent, border, opts) do
    resolve_overlay_origin(child, parent, nil, border, opts)
  end

  defp resolve_overlay_origin(child, parent, rendered_parent, border, opts) do
    {container_width, container_height} =
      overlay_container_size(child, parent, rendered_parent, border, opts)

    {
      resolve_edge_offset(child.left, child.right, child.width, container_width),
      resolve_edge_offset(child.top, child.bottom, child.height, container_height)
    }
  end

  defp overlay_container_size(%{position: :fixed}, _parent, _rendered_parent, _border, opts) do
    BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
  end

  defp overlay_container_size(_child, parent, rendered_parent, border, opts) do
    width =
      first_size(
        rendered_parent && rendered_parent.width,
        parent.width,
        parent.style.width
      )

    height =
      first_size(
        rendered_parent && rendered_parent.height,
        parent.height,
        parent.style.height
      )

    {
      resolved_overlay_width(width, border, opts),
      resolved_overlay_height(height, border, opts)
    }
  end

  defp resolved_overlay_width(width, border, _opts) when is_integer(width),
    do: width + border_horizontal(border)

  defp resolved_overlay_width(:screen, _border, opts) do
    {screen_width, _screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
    screen_width
  end

  defp resolved_overlay_width(_, _border, _opts), do: 0

  defp resolved_overlay_height(height, border, _opts) when is_integer(height),
    do: height + border_vertical(border)

  defp resolved_overlay_height(:screen, _border, opts) do
    {_screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
    screen_height
  end

  defp resolved_overlay_height(_, _border, _opts), do: 0

  defp resolve_edge_offset(value, _opposite, _child_size, _container_size) when is_integer(value),
    do: value

  defp resolve_edge_offset(nil, opposite, child_size, container_size)
       when is_integer(opposite) and is_integer(child_size) and is_integer(container_size) do
    max(container_size - child_size - opposite, 0)
  end

  defp resolve_edge_offset(_, _, _, _), do: 0

  defp plain_wrap_leaf_child?(%{style: style}) do
    style.bold == false &&
      style.italic == false &&
      style.reverse == false &&
      style.padding == 0 &&
      style.scrollbar == false &&
      style.border.style == :none &&
      is_nil(style.border_color) &&
      is_nil(style.foreground_color) &&
      is_nil(style.background_color) &&
      style.height == 0 &&
      style.overflow == :auto
  end

  defp first_size(value, _fallback, _final) when is_integer(value) and value > 0, do: value
  defp first_size(:screen, _fallback, _final), do: :screen

  defp first_size(_value, fallback, _final) when is_integer(fallback) and fallback > 0,
    do: fallback

  defp first_size(_value, :screen, _final), do: :screen
  defp first_size(_value, _fallback, final), do: final

  defp overlay_position?(%{position: position}), do: position in [:absolute, :fixed]

  defp contains_overlay_descendants?(%{position: position}) when position in [:absolute, :fixed],
    do: true

  defp contains_overlay_descendants?(%{children: children}) when is_list(children) do
    Enum.any?(children, &contains_overlay_descendants?/1)
  end

  defp contains_overlay_descendants?(_), do: false

  @doc false
  def join_vertical(items, opts \\ [])

  def join_vertical([], _opts) do
    {"", 0, 0}
  end

  def join_vertical(items, opts) do
    items_with_width =
      Enum.map(items, fn x ->
        max_width =
          String.split(x, "\n") |> Enum.map(&BackBreeze.Utils.string_length(&1)) |> Enum.max()

        {max_width, x}
      end)

    {max_width, _} = Enum.max(items_with_width)

    items =
      items
      |> Enum.join("\n")
      |> String.split("\n")

    items =
      case Keyword.get(opts, :height) do
        :screen ->
          {_screen_width, screen_height} =
            BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

          height = screen_height

          # TODO: swap X and Y obviously
          {start_pos, _} = Keyword.get(opts, :scroll, {0, 0})
          end_pos = height + start_pos - 1
          Enum.slice(items, start_pos..end_pos//1)

        height when is_integer(height) ->
          {start_pos, _} = Keyword.get(opts, :scroll, {0, 0})
          end_pos = height + start_pos - 1
          Enum.slice(items, start_pos..end_pos//1)

        _ ->
          items
      end

    {Enum.join(items, "\n"), max_width, length(items)}
  end

  @doc false
  def join_horizontal(items, opts \\ [])

  def join_horizontal([], _opts) do
    {"", 0, 0}
  end

  def join_horizontal(items, opts) do
    items = Enum.map(items, fn x -> {String.graphemes(x) |> Enum.count(&(&1 == "\n")), x} end)

    {max_height, _} = Enum.max(items)

    rows =
      items
      |> Enum.map(fn {height, item} ->
        padding = String.duplicate("\n", max_height - height)

        String.split(padding <> item, "\n")
        |> normalize_width(opts)
      end)
      |> Enum.zip()
      |> Enum.map(fn x -> Enum.join(Tuple.to_list(x), "") end)

    width = rows |> Enum.reverse() |> hd() |> BackBreeze.Utils.string_length()

    content =
      rows
      |> Enum.join("\n")

    {content, width, max_height}
  end

  defp normalize_width(items, opts) do
    align = Keyword.get(opts, :align, :left)
    items = Enum.map(items, &{BackBreeze.Utils.string_length(&1), &1})
    {max_width, _} = Enum.max(items)

    Enum.map(items, fn {width, item} ->
      padding = max_width - width

      case align do
        :left ->
          item <> String.duplicate(" ", padding)

        :right ->
          String.duplicate(" ", padding) <> item

        :center ->
          String.duplicate(" ", div(padding, 2) + rem(padding, 2)) <>
            item <> String.duplicate(" ", div(padding, 2))
      end
    end)
  end
end
