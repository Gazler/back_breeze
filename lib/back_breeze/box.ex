defmodule BackBreeze.Box do
  @moduledoc """
  A Box is the basic styling primitive used in BackBreeze. If a box has children,
  they will be rendered first and collapsed down, until a single box remains with
  the rendered contents.
  """
  alias BackBreeze.Ucwidth

  defmodule ScrollbarContext do
    @moduledoc false

    defstruct style: %BackBreeze.Style{},
              config: %BackBreeze.Scrollbar{},
              scroll: {0, 0},
              metrics: %{},
              max_x: 0,
              max_y: 0,
              left: 0,
              top: 0,
              right: 0,
              bottom: 0,
              viewport_width: 0,
              viewport_height: 0,
              content_width: 0,
              content_height: 0,
              vertical?: false,
              horizontal?: false,
              eff_viewport_width: 0,
              eff_viewport_height: 0,
              vertical_placement: :end,
              horizontal_placement: :end,
              x_scrollbar: 0,
              y_scrollbar: 0,
              vertical_start: 0,
              vertical_end: -1,
              horizontal_start: 0,
              horizontal_end: -1,
              scroll_top: 0,
              scroll_left: 0
  end

  defmodule AxisContext do
    @moduledoc false

    defstruct axis: :vertical,
              config: %BackBreeze.Scrollbar{},
              fixed: 0,
              start: 0,
              stop: -1,
              scroll_value: 0,
              content_size: 0,
              viewport_size: 0
  end

  defstruct content: "",
            children: [],
            style: %BackBreeze.Style{},
            width: nil,
            height: nil,
            state: :ready,
            position: :relative,
            display: :block,
            left: nil,
            scroll: {0, 0},
            top: nil,
            layer: 0,
            layer_map: %{}

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

    scrollbar_config = BackBreeze.Scrollbar.normalize(box.style.scrollbar, box.style)

    {content, width, layer_map} =
      if box.style.overflow == :hidden and scrollbar_config.enabled do
        {layer_map, max_width, max_height} = generate_layer_map(content, %{}, 0, 0)

        layer_map =
          maybe_add_scrollbars(layer_map, %{
            style: box.style,
            scroll: box.scroll,
            metrics: %{
              content_height: dimensions.content_height,
              content_width: raw_content_width(box.content)
            },
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
        state: :rendered,
        children: [],
        layer_map: layer_map
    }

    %{acc | box: box, dimensions: [{acc.id, dimensions} | acc.dimensions], id: acc.id + 1}
  end

  defp render_and_calc(%{box: box} = acc, opts) do
    prev_id = acc.id

    child_length = length(box.children)

    {child_layer_map, child_width, child_height, acc} =
      render_children(%{acc | id: prev_id + 1}, opts)

    style_width = if box.style.width == :auto, do: 0, else: box.style.width

    width =
      if box.style.overflow == :hidden,
        do: box.style.width,
        else: max(style_width, child_width)

    style_height = if box.style.height == :auto, do: 0, else: box.style.height

    height =
      if box.style.overflow == :hidden,
        do: box.style.height,
        else: max(style_height, child_height)

    style = %{box.style | width: width, height: height}

    # We don't want offset to apply twice in cases when there are children.
    {content, dimensions, _width} =
      render_self(%{box | width: width, height: height, style: style, scroll: {0, 0}}, opts)

    border_rows =
      if(box.style.border.top, do: 1, else: 0) +
        if box.style.border.bottom, do: 1, else: 0

    dimensions =
      Enum.take(acc.dimensions, child_length)
      |> Enum.reduce(
        %{
          content_height: 0,
          viewport_height: dimensions.height - border_rows,
          height: dimensions.height
        },
        fn {_, dims}, acc ->
          %{acc | content_height: dims.height + acc.content_height}
        end
      )

    acc = %{acc | dimensions: [{prev_id, dimensions} | acc.dimensions], id: acc.id}

    {layer_map, max_width, max_height} = generate_layer_map(content, %{}, 0, 0)

    {_, offset_left} = box.scroll

    child_layer_map =
      if offset_left > 0 do
        shift_layer_map(child_layer_map, -offset_left, 0)
      else
        child_layer_map
      end

    child_layer_map = clip_child_layer_map(child_layer_map, box.style, max_width, max_height)

    {max_width, max_height} =
      if box.style.overflow == :hidden do
        {max_width, max_height}
      else
        {max(max_width, child_width), max(max_height, child_height)}
      end

    child_layer_map =
      maybe_add_scrollbars(child_layer_map, %{
        style: box.style,
        scroll: box.scroll,
        metrics: %{content_height: dimensions.content_height, content_width: child_width},
        max_x: max_width,
        max_y: max_height
      })

    {start_x, start_y} =
      case box do
        %{position: :absolute, left: left, top: top} -> {left, top}
        _ -> {0, 0}
      end

    content =
      layer_maps_to_content(layer_map, child_layer_map, %{
        start_x: start_x,
        start_y: start_y,
        max_x: max_width,
        max_y: max_height
      })

    box = %{
      box
      | content: content,
        width: max_width + 1,
        state: :rendered,
        layer_map: Map.merge(layer_map, child_layer_map)
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
    %{width: item_width} = BackBreeze.Grid.precompute(children, box.display, box.style, opts)

    {children, dimensions} =
      Enum.reduce(children, {[], []}, fn
        %{display: %BackBreeze.Grid{}, children: children} = child_box, child_acc
        when children != [] ->
          style = %{child_box.style | width: item_width}

          %{content: content, width: w, height: h, dimensions: dimensions} =
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
              state: :rendered
          }

          {children ++ [child], dims ++ dimensions}

        child_box, child_acc ->
          {children, dimensions} = child_acc
          {children ++ [child_box], dimensions ++ [nil]}
      end)

    children = set_layer(children, [], -1)

    relative = Enum.filter(children, &(&1.position != :absolute))

    {layer, style} =
      case relative do
        [x | _] -> {x.layer, x.style}
        _ -> {0, %BackBreeze.Style{}}
      end

    %{content: content, width: width, height: height, dimensions: grid_dims} =
      BackBreeze.Grid.render_with_dimensions(children, box.display, box.style, opts)

    {_, dimensions, _} =
      Enum.reduce(dimensions, {acc.id, [], grid_dims}, fn
        nil, {id, acc, [head | remaining]} -> {id + 1, [{id, head} | acc], remaining}
        other, {id, acc, remaining} -> {id + 1, [{id, other} | acc], remaining}
      end)

    acc = %{acc | dimensions: acc.dimensions ++ Enum.reverse(dimensions)}

    absolutes = Enum.filter(children, &(&1.position == :absolute))

    relative = %{
      box
      | style: style,
        content: content,
        children: [],
        height: height,
        width: width,
        layer: layer
    }

    combine_children(box, absolutes, relative, acc)
  end

  defp render_children(%{box: %{children: children} = box} = acc, opts) when children != [] do
    {children, acc} =
      set_layer(children, [], -1)
      |> Enum.reduce({[], acc}, fn box, {boxes, child_acc} ->
        child_acc = render_and_calc(%{child_acc | box: box}, opts)
        {[child_acc.box | boxes], child_acc}
      end)

    children = Enum.reverse(children)

    relative =
      children
      |> Enum.filter(&(&1.position != :absolute))

    {layer, style} =
      case relative do
        [x | _] -> {x.layer, x.style}
        _ -> {0, %BackBreeze.Style{}}
      end

    items = Enum.map(relative, & &1.content)

    opts = Keyword.put(opts, :height, box.style.height)
    opts = Keyword.put(opts, :scroll, box.scroll)

    {content, width, height} =
      case box.display do
        :block -> join_vertical(items, opts)
        :inline -> join_horizontal(items)
      end

    absolutes = Enum.filter(children, &(&1.position == :absolute))

    relative = %{
      box
      | style: style,
        content: content,
        children: [],
        height: height,
        width: width,
        layer: layer
    }

    combine_children(box, absolutes, relative, acc)
  end

  defp combine_children(box, absolutes, relative, acc) do
    rendered_boxes = [relative | absolutes] |> Enum.sort_by(& &1.layer)

    border = box.style.border

    Enum.reduce(rendered_boxes, {%{}, 0, 0, acc}, fn box,
                                                     {layer_map, max_width, max_height, acc} ->
      {start_x, y} =
        case {box.position, border.left, border.top} do
          {:absolute, _, _} -> {box.left, box.top}
          {_, nil, nil} -> {0, 0}
          {_, _, nil} -> {1, 0}
          _ -> {1, 1}
        end

      {map, width, height} = generate_layer_map(box.content, layer_map, start_x, y)

      {map, max(max_width, width), max(max_height, height), acc}
    end)
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

    Enum.join(content, "\n") |> String.trim_trailing("\n")
  end

  defp maybe_add_scrollbars(layer_map, options)
       when is_map(options) and not is_struct(options, ScrollbarContext) do
    options
    |> build_scrollbar_context()
    |> then(&maybe_add_scrollbars(layer_map, &1))
  end

  defp maybe_add_scrollbars(layer_map, %ScrollbarContext{} = context) do
    cond do
      context.style.overflow != :hidden or !context.config.enabled ->
        layer_map

      !is_integer(context.max_x) or !is_integer(context.max_y) ->
        layer_map

      true ->
        context = prepare_scrollbar_context(context)

        if !context.vertical? and !context.horizontal? do
          layer_map
        else
          layer_map
          |> maybe_clear_scrollbar_strips(context)
          |> maybe_draw_vertical_scrollbar(context)
          |> maybe_draw_horizontal_scrollbar(context)
          |> maybe_draw_intersection(context)
        end
    end
  end

  defp build_scrollbar_context(%{style: style} = options) do
    %ScrollbarContext{
      style: style,
      config: BackBreeze.Scrollbar.normalize(style.scrollbar, style),
      scroll: Map.get(options, :scroll, {0, 0}),
      metrics: Map.get(options, :metrics, %{}),
      max_x: Map.get(options, :max_x),
      max_y: Map.get(options, :max_y)
    }
  end

  defp prepare_scrollbar_context(%ScrollbarContext{} = context) do
    {left, top, right, bottom} =
      viewport_bounds(context.style.border, context.max_x, context.max_y)

    viewport_width = max(right - left + 1, 0)
    viewport_height = max(bottom - top + 1, 0)

    metrics = if is_map(context.metrics), do: context.metrics, else: %{}

    content_height = max(Map.get(metrics, :content_height, viewport_height), viewport_height)
    content_width = max(Map.get(metrics, :content_width, viewport_width), viewport_width)

    %{
      context
      | left: left,
        top: top,
        right: right,
        bottom: bottom,
        viewport_width: viewport_width,
        viewport_height: viewport_height,
        content_width: content_width,
        content_height: content_height
    }
    |> resolve_visible_axes()
    |> set_scrollbar_positions()
    |> set_scroll_offsets()
  end

  defp set_scrollbar_positions(%ScrollbarContext{} = context) do
    vertical_placement = BackBreeze.Scrollbar.placement(context.config, :vertical)
    horizontal_placement = BackBreeze.Scrollbar.placement(context.config, :horizontal)

    {x_scrollbar, y_scrollbar} =
      scrollbar_positions(context, vertical_placement, horizontal_placement)

    {vertical_start, vertical_end} =
      trim_axis_for_intersection(
        context.top,
        context.bottom,
        context.horizontal?,
        horizontal_placement
      )

    {horizontal_start, horizontal_end} =
      trim_axis_for_intersection(
        context.left,
        context.right,
        context.vertical?,
        vertical_placement
      )

    %{
      context
      | vertical_placement: vertical_placement,
        horizontal_placement: horizontal_placement,
        x_scrollbar: x_scrollbar,
        y_scrollbar: y_scrollbar,
        vertical_start: vertical_start,
        vertical_end: vertical_end,
        horizontal_start: horizontal_start,
        horizontal_end: horizontal_end
    }
  end

  defp set_scroll_offsets(%ScrollbarContext{} = context) do
    {scroll_top, scroll_left} = normalize_scroll(context.scroll)
    %{context | scroll_top: scroll_top, scroll_left: scroll_left}
  end

  defp maybe_clear_scrollbar_strips(layer_map, context) do
    layer_map
    |> maybe_clear_vertical_scrollbar_strip(context)
    |> maybe_clear_horizontal_scrollbar_strip(context)
  end

  defp maybe_clear_vertical_scrollbar_strip(
         layer_map,
         %ScrollbarContext{
           config: %{mode: :inset},
           vertical?: true,
           x_scrollbar: x_scrollbar,
           left: left,
           right: right,
           vertical_start: vertical_start,
           vertical_end: vertical_end
         }
       )
       when x_scrollbar >= left and x_scrollbar <= right do
    clear_vertical_strip(layer_map, x_scrollbar, vertical_start, vertical_end)
  end

  defp maybe_clear_vertical_scrollbar_strip(layer_map, _context), do: layer_map

  defp maybe_clear_horizontal_scrollbar_strip(
         layer_map,
         %ScrollbarContext{
           config: %{mode: :inset},
           horizontal?: true,
           y_scrollbar: y_scrollbar,
           top: top,
           bottom: bottom,
           horizontal_start: horizontal_start,
           horizontal_end: horizontal_end
         }
       )
       when y_scrollbar >= top and y_scrollbar <= bottom do
    clear_horizontal_strip(layer_map, y_scrollbar, horizontal_start, horizontal_end)
  end

  defp maybe_clear_horizontal_scrollbar_strip(layer_map, _context), do: layer_map

  defp viewport_bounds(border, max_x, max_y) do
    left = if border.left, do: 1, else: 0
    top = if border.top, do: 1, else: 0

    right = max(max_x - if(border.right, do: 1, else: 0), left)
    bottom = max(max_y - if(border.bottom, do: 1, else: 0), top)

    {left, top, right, bottom}
  end

  defp scrollbar_positions(
         %ScrollbarContext{
           style: %{border: border},
           config: config,
           left: left,
           top: top,
           right: right,
           bottom: bottom
         },
         vertical_placement,
         horizontal_placement
       ) do
    x_scrollbar =
      cond do
        config.mode == :inset and vertical_placement == :start and border.left -> left - 1
        config.mode == :inset and vertical_placement == :end and border.right -> right + 1
        vertical_placement == :start -> left
        true -> right
      end

    y_scrollbar =
      cond do
        config.mode == :inset and horizontal_placement == :start and border.top -> top - 1
        config.mode == :inset and horizontal_placement == :end and border.bottom -> bottom + 1
        horizontal_placement == :start -> top
        true -> bottom
      end

    {x_scrollbar, y_scrollbar}
  end

  defp resolve_visible_axes(%ScrollbarContext{} = context) do
    config = context.config

    vertical? =
      BackBreeze.Scrollbar.axis_enabled?(config, :vertical) and
        BackBreeze.Scrollbar.visible?(
          config,
          :vertical,
          context.content_height,
          context.viewport_height
        )

    horizontal? =
      BackBreeze.Scrollbar.axis_enabled?(config, :horizontal) and
        BackBreeze.Scrollbar.visible?(
          config,
          :horizontal,
          context.content_width,
          context.viewport_width
        )

    {eff_viewport_width, eff_viewport_height} =
      BackBreeze.Scrollbar.effective_viewport_size(config, %{
        width: context.viewport_width,
        height: context.viewport_height,
        vertical?: vertical?,
        horizontal?: horizontal?
      })

    vertical? =
      BackBreeze.Scrollbar.axis_enabled?(config, :vertical) and
        BackBreeze.Scrollbar.visible?(
          config,
          :vertical,
          context.content_height,
          eff_viewport_height
        )

    horizontal? =
      BackBreeze.Scrollbar.axis_enabled?(config, :horizontal) and
        BackBreeze.Scrollbar.visible?(
          config,
          :horizontal,
          context.content_width,
          eff_viewport_width
        )

    {eff_viewport_width, eff_viewport_height} =
      BackBreeze.Scrollbar.effective_viewport_size(config, %{
        width: context.viewport_width,
        height: context.viewport_height,
        vertical?: vertical?,
        horizontal?: horizontal?
      })

    %{
      context
      | vertical?: vertical?,
        horizontal?: horizontal?,
        eff_viewport_width: eff_viewport_width,
        eff_viewport_height: eff_viewport_height
    }
  end

  defp normalize_scroll({top, left}) do
    top = if is_integer(top), do: max(top, 0), else: 0
    left = if is_integer(left), do: max(left, 0), else: 0
    {top, left}
  end

  defp normalize_scroll(_), do: {0, 0}

  defp trim_axis_for_intersection(start_pos, end_pos, other_enabled?, other_placement) do
    start_pos = if other_enabled? && other_placement == :start, do: start_pos + 1, else: start_pos
    end_pos = if other_enabled? && other_placement == :end, do: end_pos - 1, else: end_pos

    {start_pos, max(start_pos - 1, end_pos)}
  end

  defp clear_vertical_strip(layer_map, x, y_start, y_end) when y_start <= y_end do
    Enum.reduce(y_start..y_end, layer_map, fn y, acc ->
      Map.put(acc, {y, x}, {" ", ""})
    end)
  end

  defp clear_vertical_strip(layer_map, _x, _y_start, _y_end), do: layer_map

  defp clear_horizontal_strip(layer_map, y, x_start, x_end) when x_start <= x_end do
    Enum.reduce(x_start..x_end, layer_map, fn x, acc ->
      Map.put(acc, {y, x}, {" ", ""})
    end)
  end

  defp clear_horizontal_strip(layer_map, _y, _x_start, _x_end), do: layer_map

  defp maybe_draw_vertical_scrollbar(layer_map, %ScrollbarContext{vertical?: true} = context) do
    context
    |> vertical_axis_context()
    |> then(&draw_axis_scrollbar(layer_map, &1))
  end

  defp maybe_draw_vertical_scrollbar(layer_map, _context), do: layer_map

  defp maybe_draw_horizontal_scrollbar(
         layer_map,
         %ScrollbarContext{horizontal?: true} = context
       ) do
    context
    |> horizontal_axis_context()
    |> then(&draw_axis_scrollbar(layer_map, &1))
  end

  defp maybe_draw_horizontal_scrollbar(layer_map, _context), do: layer_map

  defp vertical_axis_context(%ScrollbarContext{} = context) do
    %AxisContext{
      axis: :vertical,
      config: context.config,
      fixed: context.x_scrollbar,
      start: context.vertical_start,
      stop: context.vertical_end,
      scroll_value: context.scroll_top,
      content_size: context.content_height,
      viewport_size: context.eff_viewport_height
    }
  end

  defp horizontal_axis_context(%ScrollbarContext{} = context) do
    %AxisContext{
      axis: :horizontal,
      config: context.config,
      fixed: context.y_scrollbar,
      start: context.horizontal_start,
      stop: context.horizontal_end,
      scroll_value: context.scroll_left,
      content_size: context.content_width,
      viewport_size: context.eff_viewport_width
    }
  end

  defp draw_axis_scrollbar(layer_map, %AxisContext{} = axis_context) do
    total_size = axis_context.stop - axis_context.start + 1

    if total_size <= 0 do
      layer_map
    else
      {track_start, track_end, layer_map} =
        maybe_draw_axis_arrows(layer_map, axis_context, total_size)

      draw_scroll_track_and_thumb(layer_map, %{
        axis_context
        | start: track_start,
          stop: track_end
      })
    end
  end

  defp maybe_draw_axis_arrows(
         layer_map,
         %AxisContext{config: %{arrows: true}} = axis_context,
         total_size
       )
       when total_size >= 3 do
    layer_map =
      put_axis_segment(
        layer_map,
        axis_context,
        axis_context.start,
        axis_arrow_segment(axis_context, :start)
      )

    layer_map =
      put_axis_segment(
        layer_map,
        axis_context,
        axis_context.stop,
        axis_arrow_segment(axis_context, :end)
      )

    {axis_context.start + 1, axis_context.stop - 1, layer_map}
  end

  defp maybe_draw_axis_arrows(layer_map, %AxisContext{} = axis_context, _total_size) do
    {axis_context.start, axis_context.stop, layer_map}
  end

  defp draw_scroll_track_and_thumb(
         layer_map,
         %AxisContext{start: track_start, stop: track_end, viewport_size: viewport_size} =
           axis_context
       )
       when track_start <= track_end and viewport_size > 0 do
    track_size = track_end - track_start + 1

    {track_segment, thumb_segment} = axis_segments(axis_context)

    max_scroll = max(axis_context.content_size - axis_context.viewport_size, 0)
    scroll_value = min(max(axis_context.scroll_value, 0), max_scroll)

    thumb_size =
      BackBreeze.Scrollbar.thumb_size(
        axis_context.config,
        track_size,
        max(axis_context.content_size, axis_context.viewport_size)
      )

    thumb_start =
      if max_scroll == 0 or thumb_size >= track_size do
        track_start
      else
        offset = round(scroll_value * (track_size - thumb_size) / max_scroll)
        track_start + offset
      end

    thumb_end = min(thumb_start + thumb_size - 1, track_end)

    layer_map =
      Enum.reduce(track_start..track_end, layer_map, fn pos, acc ->
        put_axis_segment(acc, axis_context, pos, track_segment)
      end)

    Enum.reduce(thumb_start..thumb_end, layer_map, fn pos, acc ->
      put_axis_segment(acc, axis_context, pos, thumb_segment)
    end)
  end

  defp draw_scroll_track_and_thumb(layer_map, _axis_context), do: layer_map

  defp axis_segments(%AxisContext{axis: :vertical, config: config}) do
    {config.vertical.track, config.vertical.thumb}
  end

  defp axis_segments(%AxisContext{axis: :horizontal, config: config}) do
    {config.horizontal.track, config.horizontal.thumb}
  end

  defp axis_arrow_segment(%AxisContext{axis: :vertical, config: config}, :start),
    do: config.vertical.arrow_start

  defp axis_arrow_segment(%AxisContext{axis: :vertical, config: config}, :end),
    do: config.vertical.arrow_end

  defp axis_arrow_segment(%AxisContext{axis: :horizontal, config: config}, :start),
    do: config.horizontal.arrow_start

  defp axis_arrow_segment(%AxisContext{axis: :horizontal, config: config}, :end),
    do: config.horizontal.arrow_end

  defp put_axis_segment(layer_map, %AxisContext{} = axis_context, pos, segment) do
    put_segment(layer_map, axis_point(axis_context, pos), segment)
  end

  defp axis_point(%AxisContext{axis: :vertical, fixed: fixed}, pos), do: {pos, fixed}
  defp axis_point(%AxisContext{axis: :horizontal, fixed: fixed}, pos), do: {fixed, pos}

  defp maybe_draw_intersection(
         layer_map,
         %ScrollbarContext{vertical?: true, horizontal?: true} = context
       ) do
    put_segment(
      layer_map,
      {context.y_scrollbar, context.x_scrollbar},
      context.config.intersection
    )
  end

  defp maybe_draw_intersection(layer_map, _context), do: layer_map

  defp put_segment(layer_map, _point, nil), do: layer_map

  defp put_segment(layer_map, point, segment) do
    char = BackBreeze.Scrollbar.segment_char(segment)

    if is_binary(char) do
      Map.put(layer_map, point, {char, BackBreeze.Scrollbar.style_sequence(segment)})
    else
      layer_map
    end
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

  defp set_layer([], result, _layer) do
    Enum.reverse(result)
  end

  defp set_layer([%{position: :absolute} = box | rest], result, layer) do
    set_layer(rest, [%{box | layer: layer + 1} | result], layer + 2)
  end

  defp set_layer([box | rest], result, layer) when is_binary(box) do
    set_layer(rest, [box | result], layer || 0)
  end

  defp set_layer([box | rest], result, nil) do
    set_layer(rest, [%{box | layer: 0} | result], 0)
  end

  defp set_layer([box | rest], result, layer) do
    set_layer(rest, [%{box | layer: layer} | result], layer)
  end

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
      |> String.trim_trailing("\n")
      |> String.split("\n")

    items =
      case Keyword.get(opts, :height) do
        :screen ->
          {_screen_width, screen_height} =
            BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

          height = screen_height - 2

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
      |> String.trim_trailing("\n")

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
