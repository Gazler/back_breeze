defmodule BackBreeze.Box do
  @moduledoc """
  A Box is the basic styling primitive used in BackBreeze. If a box has children,
  they will be rendered first and collapsed down, until a single box remains with
  the rendered contents.
  """
  alias BackBreeze.BenchProfile
  alias BackBreeze.RenderCache
  alias BackBreeze.Ucwidth

  @wide_glyph_key :__wide_glyphs__

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
    terminal = Keyword.get(opts, :terminal)

    RenderCache.with_frame(fn ->
      RenderCache.fetch_stable(
        {:render_with_dimensions, if(terminal, do: terminal.size, else: nil), box},
        fn ->
          %{box: box, dimensions: dimensions} =
            render_and_calc(%{box: box, dimensions: [], id: 0}, opts)

          dimensions = Enum.sort(dimensions) |> Enum.map(&elem(&1, 1))
          box = ensure_rendered_content(box)
          %{box: box, dimensions: dimensions}
        end
      )
    end)
  end

  @doc false
  def render_structured_with_dimensions(box, opts \\ []) do
    terminal = Keyword.get(opts, :terminal)

    RenderCache.with_frame(fn ->
      RenderCache.fetch_stable(
        {:render_structured_with_dimensions, if(terminal, do: terminal.size, else: nil), box},
        fn ->
          %{box: box, dimensions: dimensions} =
            render_and_calc(
              %{box: box, dimensions: [], id: 0},
              Keyword.put(opts, :structured, true)
            )

          %{box: box, dimensions: Enum.sort(dimensions) |> Enum.map(&elem(&1, 1))}
        end
      )
    end)
  end

  @doc false
  def render_cached_with_dimensions(box, opts \\ []) do
    structured? = Keyword.get(opts, :structured, false)
    terminal = Keyword.get(opts, :terminal)

    RenderCache.fetch_stable(
      {:render_box, structured?, if(terminal, do: terminal.size, else: nil), box},
      fn ->
        if structured? do
          render_structured_with_dimensions(box, Keyword.delete(opts, :structured))
        else
          render_with_dimensions(box, opts)
        end
      end
    )
  end

  @doc false
  def compose_absolute_children(children, opts \\ []) do
    %{width: width, height: height, layer_map: layer_map} =
      compose_absolute_children_layer_map(children, opts)

    %{
      content: layer_map_to_content(layer_map, width, height),
      width: width,
      height: height,
      layer_map: layer_map
    }
  end

  @doc false
  def compose_absolute_children_layer_map(children, opts \\ []) do
    rendered_boxes =
      if Keyword.get(opts, :sorted, false) do
        children
      else
        Enum.sort_by(children, & &1.layer)
      end

    {layer_map, max_width, max_height} =
      Enum.reduce(rendered_boxes, {%{}, 0, 0}, fn box, {layer_map, max_width, max_height} ->
        {start_x, start_y} = {box.left || 0, box.top || 0}

        {map, width, height} =
          if layer_map_entries?(box.layer_map) do
            merge_layer_map(layer_map, box.layer_map, start_x, start_y)
          else
            generate_layer_map(box.content, layer_map, start_x, start_y)
          end

        {map, max(max_width, width), max(max_height, height)}
      end)

    target_width = Keyword.get(opts, :width)
    target_height = Keyword.get(opts, :height)
    clip? = Keyword.get(opts, :clip, false)

    max_x =
      cond do
        clip? and is_integer(target_width) -> max(target_width - 1, 0)
        is_integer(target_width) -> max(max_width, target_width - 1)
        true -> max_width
      end

    max_y =
      cond do
        clip? and is_integer(target_height) -> max(target_height - 1, 0)
        is_integer(target_height) -> max(max_height, target_height - 1)
        true -> max_height
      end

    %{width: max_x + 1, height: max_y + 1, layer_map: layer_map}
  end

  @doc false
  def layer_map_to_content(layer_map, width, height) do
    cached_layer_maps_to_content(layer_map, %{}, %{
      start_x: 0,
      start_y: 0,
      max_x: width - 1,
      max_y: height - 1
    })
  end

  defp render_and_calc(%{box: %{state: :rendered}} = acc, _opts) do
    acc
  end

  defp render_and_calc(%{box: %{children: []} = box} = acc, opts) do
    {content, dimensions, width} =
      BenchProfile.measure({__MODULE__, :render_self}, fn -> render_self(box, opts) end)

    dimensions =
      dimensions
      |> Map.put(:width, width)
      |> Map.put_new(:viewport_width, width)
      |> Map.put_new(:content_width, width)
      |> Map.put(:left, 0)
      |> Map.put(:top, 0)

    {scrollbar_config, _} = BackBreeze.Scrollbar.normalize(box.style.scrollbar, box.style)

    structured? = Keyword.get(opts, :structured, false)

    {content, width, layer_map} =
      if box.style.overflow == :hidden and scrollbar_config.enabled do
        {base_layer_map, max_width, max_height} =
          BenchProfile.measure({__MODULE__, :generate_layer_map}, fn ->
            cached_generate_layer_map(content)
          end)

        layer_map =
          BackBreeze.Scrollbar.add_to_layer_map(base_layer_map, %{
            style: box.style,
            scroll: box.scroll,
            content_height: dimensions.content_height,
            content_width: raw_content_width(box.content),
            max_x: max_width,
            max_y: max_height
          })

        {
          if(structured?,
            do: nil,
            else:
              BenchProfile.measure({__MODULE__, :layer_maps_to_content}, fn ->
                cached_layer_maps_to_content(layer_map, %{}, %{
                  start_x: 0,
                  start_y: 0,
                  max_x: max_width,
                  max_y: max_height
                })
              end)
          ),
          max_width + 1,
          layer_map
        }
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
        layer_map: layer_map,
        overlay?: visual_overflow?(box.style, dimensions.content_height, dimensions.height)
    }

    %{acc | box: box, dimensions: [{acc.id, dimensions} | acc.dimensions], id: acc.id + 1}
  end

  defp render_and_calc(%{box: box} = acc, opts) do
    prev_id = acc.id

    {child_layer_map, child_width, child_height, has_overlay_children?, child_layer, children,
     acc} =
      BenchProfile.measure({__MODULE__, :render_children}, fn ->
        render_children(%{acc | id: prev_id + 1}, opts)
      end)

    structured? = Keyword.get(opts, :structured, false)
    children_content_height = content_height(children, box.display)

    cond do
      not structured? and
        is_binary(child_layer_map) and box.scroll == {0, 0} and
        box.style.scrollbar == false and not has_overlay_children? and
        plain_wrapper_style?(box) and
        box.style.width not in [:full, :screen] and
          box.style.height not in [:full, :screen] ->
        render_wrapped_content_container(
          acc,
          prev_id,
          box,
          child_layer_map,
          child_layer,
          opts
        )

      not structured? and plain_content_container?(box, child_layer_map, has_overlay_children?) ->
        render_plain_content_container(
          acc,
          prev_id,
          child_layer_map,
          child_width,
          child_height,
          child_layer,
          opts
        )

      true ->
        style_width = if box.style.width == :auto, do: 0, else: box.style.width

        width =
          cond do
            box.style.overflow == :hidden ->
              box.style.width

            is_integer(box.style.width) and box.style.width > 0 ->
              box.style.width

            true ->
              max(
                style_width,
                child_width + padding_horizontal(box.style) + border_horizontal(box.style.border)
              )
          end

        style_height = if box.style.height == :auto, do: 0, else: box.style.height

        height =
          cond do
            box.style.overflow == :hidden ->
              box.style.height

            is_integer(box.style.height) and box.style.height > 0 ->
              box.style.height

            true ->
              max(
                style_height,
                children_content_height +
                  padding_vertical(box.style) +
                  border_vertical(box.style.border)
              )
          end

        style = %{box.style | width: width, height: height}

        # We don't want offset to apply twice in cases when there are children.
        {content, dimensions, _width} =
          BenchProfile.measure({__MODULE__, :render_self}, fn ->
            render_self(%{box | width: width, height: height, style: style, scroll: {0, 0}}, opts)
          end)

        border_rows =
          if(box.style.border.top, do: 1, else: 0) +
            if box.style.border.bottom, do: 1, else: 0

        dimensions = %{
          content_height: children_content_height,
          viewport_height: dimensions.height - border_rows,
          viewport_width: width,
          height: dimensions.height,
          width: width
        }

        dimensions =
          if box.style.height in [:auto, :full] ||
               (is_integer(box.style.height) && box.style.height <= 0 &&
                  box.style.width != :screen) do
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

        rendered_width = raw_content_width(content)

        {layer_map, max_width, max_height} =
          BenchProfile.measure({__MODULE__, :container_base_layer}, fn ->
            cached_blank_container_layer_map(box, rendered_width, dimensions.height) ||
              cached_generate_layer_map(content)
          end)

        max_height = max(max_height, max(rendered_height(content) - 1, 0))

        {offset_top, offset_left} = box.scroll

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
          if clip_relative_children? and
               (offset_left > 0 or
                  offset_top > 0 or
                  clip_child_layer_map_required?(
                    child_width,
                    child_height,
                    box.style,
                    max_width,
                    max_height,
                    has_overlay_children?
                  )) do
            BenchProfile.measure({__MODULE__, :clip_child_layer_map}, fn ->
              clip_child_layer_map(child_layer_map, box.style, max_width, max_height)
            end)
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
          BenchProfile.measure({__MODULE__, :scrollbar_layer_map}, fn ->
            BackBreeze.Scrollbar.add_to_layer_map(child_layer_map, %{
              style: box.style,
              scroll: box.scroll,
              content_height: dimensions.content_height,
              content_width: child_width,
              max_x: max_width,
              max_y: max_height
            })
          end)

        merged_layer_map =
          BenchProfile.measure({__MODULE__, :merge_layer_maps}, fn ->
            Map.merge(layer_map, child_layer_map)
          end)

        content =
          if structured? do
            nil
          else
            BenchProfile.measure({__MODULE__, :layer_maps_to_content}, fn ->
              cached_layer_maps_to_content(layer_map, child_layer_map, %{
                start_x: 0,
                start_y: 0,
                max_x: max_width,
                max_y: max_height
              })
            end)
          end

        box = %{
          box
          | content: content,
            width: max_width + 1,
            height: max_height + 1,
            layer: max(box.layer || 0, child_layer || 0),
            state: :rendered,
            layer_map: merged_layer_map,
            overlay?: has_overlay_children?
        }

        %{acc | box: box}
    end
  end

  defp render_plain_content_container(
         %{box: box} = acc,
         prev_id,
         child_content,
         _child_width,
         _child_height,
         child_layer,
         _opts
       ) do
    width = raw_content_width(child_content)
    height = rendered_height(child_content)

    dimensions =
      %{
        width: width,
        viewport_width: width,
        content_width: width,
        height: height,
        viewport_height: height,
        content_height: height,
        left: 0,
        top: 0
      }

    box = %{
      box
      | content: child_content,
        width: width,
        height: height,
        layer: max(box.layer || 0, child_layer || 0),
        state: :rendered,
        layer_map: %{},
        overlay?: false
    }

    %{acc | box: box, dimensions: [{prev_id, dimensions} | acc.dimensions], id: acc.id}
  end

  defp render_wrapped_content_container(
         %{box: box} = acc,
         prev_id,
         box,
         child_content,
         child_layer,
         opts
       ) do
    {content, dimensions, width} =
      render_self(%{box | content: child_content, children: [], scroll: {0, 0}}, opts)

    box = %{
      box
      | content: content,
        width: width,
        height: dimensions.height,
        layer: max(box.layer || 0, child_layer || 0),
        state: :rendered,
        children: [],
        layer_map: %{},
        overlay?: false
    }

    %{acc | box: box, dimensions: [{prev_id, dimensions} | acc.dimensions], id: acc.id}
  end

  defp render_self(box, opts) do
    {offset_top, _} = box.scroll
    opts = Keyword.put(opts, :offset_top, offset_top)
    terminal = Keyword.get(opts, :terminal)
    box = normalize_render_self_box(box)

    cache_key =
      {:render_self, box.style, box.content, offset_top,
       if(terminal, do: terminal.size, else: nil)}

    RenderCache.fetch_stable(cache_key, fn ->
      {content, dimensions} = BackBreeze.Style.calculate_and_render(box.style, box.content, opts)
      max_width = raw_content_width(content)
      {content, dimensions, max_width}
    end)
  end

  defp normalize_render_self_box(box) do
    style =
      box.style
      |> maybe_resolve_render_self_extent(:width, box.width)
      |> maybe_resolve_render_self_extent(:height, box.height)

    %{box | style: style}
  end

  defp maybe_resolve_render_self_extent(style, _field, value) when not is_integer(value),
    do: style

  defp maybe_resolve_render_self_extent(style, field, value) do
    case Map.get(style, field) do
      extent when extent in [:full, :screen] -> Map.put(style, field, value)
      _ -> style
    end
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

    column_offsets = prefix_offsets(column_widths)
    row_offsets = prefix_offsets(row_heights)

    {children, grouped_dims} =
      BenchProfile.measure({__MODULE__, :grid_prepare_children}, fn ->
        children
        |> Enum.with_index()
        |> Enum.reduce({[], []}, fn
          {%{display: %BackBreeze.Grid{}, children: nested_children} = child_box, child_index},
          child_acc
          when nested_children != [] ->
            child_box = inherit_parent_background(child_box, box.style)
            row_index = div(child_index, box.display.columns)
            col_index = rem(child_index, box.display.columns)
            child_left = Enum.at(column_offsets, col_index, 0)
            child_top = Enum.at(row_offsets, row_index, 0)

            style = %{
              child_box.style
              | width: Enum.at(column_widths, col_index, item_width),
                height: Enum.at(row_heights, row_index, item_height)
            }

            %{
              content: content,
              width: w,
              height: h,
              content_height: content_height,
              per_item_dimensions: inner_dimensions,
              layer_map: nested_layer_map
            } =
              BackBreeze.Grid.render_structured_with_dimensions(
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
                layer_map: nested_layer_map,
                overlay?:
                  visual_overflow?(style, content_height, h) ||
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

            {[child | children], [%{dims: [container_dim | shifted_inner_dimensions]} | dims]}

          {child_box, child_index}, child_acc ->
            child_box = inherit_parent_background(child_box, box.style)
            row_index = div(child_index, box.display.columns)
            col_index = rem(child_index, box.display.columns)
            child_left = Enum.at(column_offsets, col_index, 0)
            child_top = Enum.at(row_offsets, row_index, 0)
            {children, dims} = child_acc
            {[child_box | children], [%{dims: nil, left: child_left, top: child_top} | dims]}
        end)
        |> then(fn {children, dims} -> {Enum.reverse(children), Enum.reverse(dims)} end)
      end)

    %{
      content: content,
      width: width,
      height: height,
      per_item_dimensions: per_item_dims,
      layer_map: grid_layer_map
    } =
      BackBreeze.Grid.render_with_dimensions(children, box.display, box.style, opts)

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

    {final_id, new_dims} =
      Enum.zip(grouped_dims, per_item_dims)
      |> Enum.reduce({acc.id, []}, fn
        {%{dims: nil, left: _left, top: _top}, child_dims}, {id, acc_d} ->
          entries = Enum.with_index(child_dims, id) |> Enum.map(fn {d, i} -> {i, d} end)
          {id + length(child_dims), Enum.reverse(entries, acc_d)}

        {%{dims: grouped}, _}, {id, acc_d} ->
          entries = Enum.with_index(grouped, id) |> Enum.map(fn {d, i} -> {i, d} end)
          {id + length(grouped), Enum.reverse(entries, acc_d)}
      end)
      |> then(fn {final_id, dims} -> {final_id, Enum.reverse(dims)} end)

    {content_left, content_top} = content_origin(box.style)

    new_dims =
      Enum.map(new_dims, fn {id, dims} ->
        {id, shift_dimension(dims, content_left, content_top)}
      end)

    acc = %{acc | dimensions: acc.dimensions ++ new_dims, id: final_id}

    absolutes = Enum.filter(children, &(&1.position == :absolute))

    relative_has_overlay? =
      Enum.any?(relative, & &1.overlay?)

    if not Keyword.get(opts, :structured, false) and
         plain_content_children?(box, absolutes, has_overlay_children?, relative_has_overlay?) do
      {content, width, height, false, layer, children, acc}
    else
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
          top: nil,
          layer_map: grid_layer_map,
          overlay?: has_overlay_children?
      }

      {layer_map, width, height, acc} = combine_children(box, absolutes, relative, acc, opts)
      {layer_map, width, height, has_overlay_children?, layer, children, acc}
    end
  end

  defp render_children(%{box: %{children: children} = box} = acc, opts) when children != [] do
    parent_width = resolved_parent_width(box, opts)
    parent_height = resolved_parent_height(box, opts)

    {children, acc, _used_extent} =
      BenchProfile.measure({__MODULE__, :flow_children}, fn ->
        set_layer(children, [], -1)
        |> Enum.map(&inherit_parent_background(&1, box.style))
        |> Enum.map(&resolve_absolute_fill_offsets(&1, box.style.border))
        |> resolve_fill_widths(parent_width, box.display, box.style.overflow)
        |> Enum.reduce({[], acc, 0}, fn child, {boxes, child_acc, used_extent} ->
          child =
            resolve_fill_width(
              child,
              box.display,
              parent_width,
              used_extent,
              box.style.overflow
            )

          child = resolve_fill_height(child, box.display, parent_height, used_extent)
          child = resolve_overlay_fill_size(child, box, opts)

          child_result =
            BenchProfile.measure({__MODULE__, :flow_child_render}, fn ->
              render_cached_with_dimensions(child,
                structured: Keyword.get(opts, :structured, false),
                terminal: Keyword.get(opts, :terminal)
              )
            end)

          {child_left, child_top} = child_origin(box, child_result.box, used_extent, opts)

          child_acc =
            append_rendered_child_dimensions(
              child_acc,
              child_result.dimensions,
              child_left,
              child_top
            )

          rendered_child =
            if overlay_position?(child_result.box) do
              child_result.box
            else
              %{child_result.box | left: child_left, top: child_top}
            end

          used_extent =
            if overlay_position?(rendered_child) do
              used_extent
            else
              used_extent + child_extent(rendered_child, box.display)
            end

          {[rendered_child | boxes], child_acc, used_extent}
        end)
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

    relative_has_overlay? =
      Enum.any?(relative, & &1.overlay?)

    resolved_join_height =
      cond do
        box.display == :block && relative_has_overlay? && box.style.overflow != :hidden ->
          nil

        true ->
          box.style.height
      end

    opts = Keyword.put(opts, :height, resolved_join_height)
    opts = Keyword.put(opts, :scroll, box.scroll)

    structured? = Keyword.get(opts, :structured, false)

    {content, width, height, relative_layer_map} =
      BenchProfile.measure({__MODULE__, :flow_join}, fn ->
        if structured? and structured_block_layer_map?(box, relative) do
          {width, height, layer_map} = compose_block_children_layer_map(relative, box)
          {nil, width, height, layer_map}
        else
          items = Enum.map(relative, &materialized_content(&1))

          {content, width, height} =
            case box.display do
              :block -> join_vertical(items, opts)
              :inline -> join_horizontal(items)
            end

          {content, width, height, %{}}
        end
      end)

    overlay_absolutes =
      children
      |> Enum.filter(&(not overlay_position?(&1) and &1.overlay?))
      |> Enum.map(&%{&1 | position: :absolute})

    absolutes = Enum.filter(children, &overlay_position?/1) ++ overlay_absolutes

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
        top: nil,
        layer_map: relative_layer_map
    }

    if not structured? and
         plain_content_children?(box, absolutes, has_overlay_children?, relative_has_overlay?) do
      {content, width, height, false, layer, children, acc}
    else
      {layer_map, width, height, acc} = combine_children(box, absolutes, relative, acc, opts)
      {layer_map, width, height, has_overlay_children?, layer, children, acc}
    end
  end

  defp content_height(children, :inline) do
    children
    |> Enum.reject(&(&1.position == :absolute))
    |> Enum.map(&(&1.height || 0))
    |> Enum.max(fn -> 0 end)
  end

  defp content_height(children, %BackBreeze.Grid{}) do
    children
    |> Enum.reject(&(&1.position == :absolute))
    |> Enum.map(fn child -> (child.top || 0) + (child.height || 0) end)
    |> Enum.max(fn -> 0 end)
  end

  defp content_height(children, _display) do
    Enum.reduce(children, 0, fn
      %{position: :absolute}, acc -> acc
      child, acc -> acc + (child.height || 0)
    end)
  end

  defp combine_children(box, absolutes, relative, acc, opts) do
    BenchProfile.measure({__MODULE__, {:combine_children, length(absolutes)}}, fn ->
      if cacheable_combine_children?(absolutes) do
        RenderCache.fetch(combine_children_cache_key(box, absolutes, relative, opts), fn ->
          do_combine_children(box, absolutes, relative, opts)
        end)
        |> then(fn {map, width, height} -> {map, width, height, acc} end)
      else
        {map, width, height} = do_combine_children(box, absolutes, relative, opts)
        {map, width, height, acc}
      end
    end)
  end

  defp do_combine_children(box, [], relative, _opts) do
    {start_x, start_y} = content_origin(box.style)

    if layer_map_entries?(relative.layer_map) do
      merge_layer_map(%{}, relative.layer_map, start_x, start_y)
    else
      generate_layer_map(relative.content, %{}, start_x, start_y)
    end
  end

  defp do_combine_children(box, [absolute], relative, opts) do
    border = box.style.border
    {rel_x, rel_y} = content_origin(box.style)
    {overlay_x, overlay_y} = resolve_overlay_origin(absolute, box, relative, border, opts)

    {base_map, base_width, base_height} =
      if layer_map_entries?(relative.layer_map) do
        merge_layer_map(%{}, relative.layer_map, rel_x, rel_y)
      else
        generate_layer_map(relative.content, %{}, rel_x, rel_y)
      end

    {map, width, height} =
      if layer_map_entries?(absolute.layer_map) do
        merge_layer_map(base_map, absolute.layer_map, overlay_x, overlay_y)
      else
        generate_layer_map(absolute.content, base_map, overlay_x, overlay_y)
      end

    {map, max(base_width, width), max(base_height, height)}
  end

  defp do_combine_children(box, [absolute_one, absolute_two], relative, opts) do
    border = box.style.border

    [first_box, second_box, third_box] =
      Enum.sort_by([relative, absolute_one, absolute_two], & &1.layer)

    {map, width, height} =
      merge_rendered_box(%{}, first_box, box, relative, border, opts)

    {map, width, height} =
      merge_rendered_box(map, second_box, box, relative, border, opts, width, height)

    merge_rendered_box(map, third_box, box, relative, border, opts, width, height)
  end

  defp do_combine_children(box, absolutes, relative, opts) do
    rendered_boxes = [relative | absolutes] |> Enum.sort_by(& &1.layer)
    border = box.style.border

    {map, width, height, _acc} =
      Enum.reduce(rendered_boxes, {%{}, 0, 0, nil}, fn rendered_box,
                                                       {layer_map, max_width, max_height, acc} ->
        {map, width, height} =
          merge_rendered_box(
            layer_map,
            rendered_box,
            box,
            relative,
            border,
            opts,
            max_width,
            max_height
          )

        {map, width, height, acc}
      end)

    {map, width, height}
  end

  defp cacheable_combine_children?(absolutes), do: length(absolutes) in [1, 2]

  defp combine_children_cache_key(box, absolutes, relative, opts) do
    terminal = Keyword.get(opts, :terminal)

    {
      :combine_children,
      box.style.border,
      box.width,
      box.height,
      box.style.width,
      box.style.height,
      if(terminal, do: terminal.size, else: nil),
      rendered_box_cache_key(relative),
      Enum.map(absolutes, &rendered_box_cache_key/1)
    }
  end

  defp rendered_box_cache_key(box) do
    {
      box.position,
      box.left,
      box.top,
      box.right,
      box.bottom,
      box.width,
      box.height,
      box.layer,
      box.content,
      box.layer_map
    }
  end

  defp merge_rendered_box(layer_map, rendered_box, box, relative, border, opts) do
    merge_rendered_box(layer_map, rendered_box, box, relative, border, opts, 0, 0)
  end

  defp merge_rendered_box(
         layer_map,
         rendered_box,
         box,
         relative,
         border,
         opts,
         max_width,
         max_height
       ) do
    {start_x, start_y} =
      case {rendered_box.position, border.left, border.top} do
        {position, _, _} when position in [:absolute, :fixed] ->
          resolve_overlay_origin(rendered_box, box, relative, border, opts)

        _ ->
          content_origin(box.style)
      end

    {map, width, height} =
      if layer_map_entries?(rendered_box.layer_map) do
        merge_layer_map(layer_map, rendered_box.layer_map, start_x, start_y)
      else
        generate_layer_map(rendered_box.content, layer_map, start_x, start_y)
      end

    {map, max(max_width, width), max(max_height, height)}
  end

  defp merge_layer_map(target_map, source_map, offset_x, offset_y) do
    wide_glyphs? = has_wide_glyphs?(target_map) or has_wide_glyphs?(source_map)

    {map, max_x, max_y} =
      Enum.reduce(source_map, {target_map, 0, 0}, fn
        {@wide_glyph_key, true}, acc ->
          acc

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

    map =
      if wide_glyphs? and map_size(map) > 0 do
        Map.put(map, @wide_glyph_key, true)
      else
        map
      end

    {map, max_x, max_y}
  end

  defp generate_layer_map(content, layer_map, start_x, y) do
    reset = Termite.Style.reset_code()

    {_x, y, {acc, max_x, _, _}} =
      generate_layer_map_binary(content, layer_map, start_x, start_x, y, 1, false, "", reset)

    {acc, max_x - 1, y}
  end

  defp cached_blank_container_layer_map(box, width, height) do
    RenderCache.fetch_stable({:blank_container_layer_map, box.style, width, height}, fn ->
      maybe_generate_blank_container_layer_map(box, width, height)
    end)
  end

  defp cached_generate_layer_map(content, start_x \\ 0, start_y \\ 0, layer_map \\ %{})

  defp cached_generate_layer_map(content, start_x, start_y, layer_map)
       when is_binary(content) and map_size(layer_map) == 0 do
    if start_x == 0 and start_y == 0 do
      RenderCache.fetch_stable({:generate_layer_map, content}, fn ->
        generate_layer_map(content, %{}, 0, 0)
      end)
    else
      generate_layer_map(content, %{}, start_x, start_y)
    end
  end

  defp cached_generate_layer_map(content, start_x, start_y, layer_map) do
    generate_layer_map(content, layer_map, start_x, start_y)
  end

  defp maybe_generate_blank_container_layer_map(%{content: "", style: style}, width, height)
       when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    border =
      style.border
      |> Map.put(:color, style.border_color || style.border.color)
      |> Map.put(:background_color, style.background_color)

    border_seq = border_style_sequence(border)
    fill_seq = content_style_sequence(style)
    map = %{}
    last_x = width - 1
    last_y = height - 1

    inner_left = if(border.left, do: 1, else: 0)
    inner_top = if(border.top, do: 1, else: 0)
    inner_right = if(border.right, do: last_x - 1, else: last_x)
    inner_bottom = if(border.bottom, do: last_y - 1, else: last_y)

    map =
      if fill_seq != "" and inner_left <= inner_right and inner_top <= inner_bottom do
        Enum.reduce(inner_top..inner_bottom, map, fn y, acc ->
          Enum.reduce(inner_left..inner_right, acc, fn x, inner_acc ->
            Map.put(inner_acc, {y, x}, {" ", fill_seq})
          end)
        end)
      else
        map
      end

    map =
      map
      |> maybe_add_horizontal_border(
        0,
        width,
        border.top,
        border.top_left,
        border.top_right,
        border_seq
      )
      |> maybe_add_horizontal_border(
        last_y,
        width,
        border.bottom,
        border.bottom_left,
        border.bottom_right,
        border_seq
      )
      |> maybe_add_vertical_border(
        0,
        height,
        border.left,
        border.top_left,
        border.bottom_left,
        border_seq
      )
      |> maybe_add_vertical_border(
        last_x,
        height,
        border.right,
        border.top_right,
        border.bottom_right,
        border_seq
      )

    {map, last_x, last_y}
  end

  defp maybe_generate_blank_container_layer_map(_, _width, _height), do: nil

  defp maybe_add_horizontal_border(map, _y, _width, nil, _left, _right, _seq), do: map

  defp maybe_add_horizontal_border(map, y, width, char, left_corner, right_corner, seq) do
    map =
      Enum.reduce(0..(width - 1), map, fn x, acc ->
        cond do
          x == 0 and not is_nil(left_corner) -> Map.put(acc, {y, x}, {left_corner, seq})
          x == width - 1 and not is_nil(right_corner) -> Map.put(acc, {y, x}, {right_corner, seq})
          true -> Map.put(acc, {y, x}, {char, seq})
        end
      end)

    map
  end

  defp maybe_add_vertical_border(map, _x, _height, nil, _top, _bottom, _seq), do: map

  defp maybe_add_vertical_border(map, x, height, char, top_corner, bottom_corner, seq) do
    Enum.reduce(0..(height - 1), map, fn y, acc ->
      cond do
        y == 0 and not is_nil(top_corner) -> acc
        y == height - 1 and not is_nil(bottom_corner) -> acc
        true -> Map.put(acc, {y, x}, {char, seq})
      end
    end)
  end

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

  defp content_style_sequence(style) do
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

  defp maybe_add_style(funs, true, fun), do: [fun | funs]
  defp maybe_add_style(funs, _enabled, _fun), do: funs

  defp maybe_add_color(funs, nil, _fun), do: funs
  defp maybe_add_color(funs, value, fun), do: [fn style -> fun.(style, value) end | funs]

  defp generate_layer_map_binary(<<>>, layer_map, _start_x, x, y, max_x, in_seq?, seq, _reset) do
    {x, y, {layer_map, max_x, in_seq?, seq}}
  end

  defp generate_layer_map_binary(
         <<"\n", rest::binary>>,
         layer_map,
         start_x,
         _x,
         y,
         max_x,
         in_seq?,
         seq,
         reset
       ) do
    generate_layer_map_binary(
      rest,
      layer_map,
      start_x,
      start_x,
      y + 1,
      max_x,
      in_seq?,
      seq,
      reset
    )
  end

  defp generate_layer_map_binary(
         <<"\e", rest::binary>>,
         layer_map,
         start_x,
         x,
         y,
         max_x,
         false,
         _seq,
         reset
       ) do
    generate_layer_map_binary(rest, layer_map, start_x, x, y, max_x, true, "\e", reset)
  end

  defp generate_layer_map_binary(
         <<"m", rest::binary>>,
         layer_map,
         start_x,
         x,
         y,
         max_x,
         true,
         seq,
         reset
       ) do
    generate_layer_map_binary(rest, layer_map, start_x, x, y, max_x, false, seq <> "m", reset)
  end

  defp generate_layer_map_binary(
         <<char, rest::binary>>,
         layer_map,
         start_x,
         x,
         y,
         max_x,
         true,
         seq,
         reset
       )
       when char < 128 do
    generate_layer_map_binary(rest, layer_map, start_x, x, y, max_x, true, seq <> <<char>>, reset)
  end

  defp generate_layer_map_binary(
         <<char, rest::binary>>,
         layer_map,
         start_x,
         x,
         y,
         max_x,
         false,
         seq,
         reset
       )
       when char < 128 do
    current_seq = if seq == reset, do: "", else: seq

    {x, y, {layer_map, max_x, false, seq}} =
      add_layer_codepoint(char, layer_map, x, y, max_x, current_seq, seq)

    generate_layer_map_binary(rest, layer_map, start_x, x, y, max_x, false, seq, reset)
  end

  defp generate_layer_map_binary(
         <<codepoint::utf8, rest::binary>>,
         layer_map,
         start_x,
         x,
         y,
         max_x,
         true,
         seq,
         reset
       ) do
    generate_layer_map_binary(
      rest,
      layer_map,
      start_x,
      x,
      y,
      max_x,
      true,
      seq <> <<codepoint::utf8>>,
      reset
    )
  end

  defp generate_layer_map_binary(
         <<codepoint::utf8, rest::binary>>,
         layer_map,
         start_x,
         x,
         y,
         max_x,
         false,
         seq,
         reset
       ) do
    current_seq = if seq == reset, do: "", else: seq

    {x, y, {layer_map, max_x, false, seq}} =
      add_layer_codepoint(codepoint, layer_map, x, y, max_x, current_seq, seq)

    generate_layer_map_binary(rest, layer_map, start_x, x, y, max_x, false, seq, reset)
  end

  defp layer_maps_to_content(layer_map, overlay_layer_map, %{
         start_x: start_x,
         start_y: start_y,
         max_x: max_x,
         max_y: max_y
       })
       when map_size(overlay_layer_map) == 0 do
    if has_wide_glyphs?(layer_map) do
      layer_map_rows_to_content(layer_map, start_x, start_y, max_x, max_y)
    else
      reset = Termite.Style.reset_code()

      rows =
        Enum.map(start_y..max_y, fn y ->
          {segments, buffer, style, _skip} =
            Enum.reduce(start_x..max_x, {[], [], "", false}, fn x,
                                                                {segments, buffer, last_style,
                                                                 skip} ->
              point = if skip, do: :skip, else: Map.get(layer_map, {y, x})

              skip_next =
                case point do
                  {char, _style} -> Ucwidth.width(char) == 2
                  _ -> false
                end

              case point do
                :skip ->
                  {segments, buffer, last_style, false}

                nil ->
                  if wide_continuation?(layer_map, y, x) do
                    {segments, buffer, last_style, false}
                  else
                    if last_style == "" do
                      {segments, [" " | buffer], last_style, false}
                    else
                      {flush_buffer(segments, buffer, last_style, reset), [" "], "", false}
                    end
                  end

                {char, style} when style == last_style ->
                  {segments, [char | buffer], style, skip_next}

                {char, style} ->
                  {flush_buffer(segments, buffer, last_style, reset), [char], style, skip_next}
              end
            end)

          flush_buffer(segments, buffer, style, reset)
          |> Enum.reverse()
        end)

      rows
      |> Enum.intersperse("\n")
      |> IO.iodata_to_binary()
    end
  end

  defp layer_maps_to_content(layer_map, overlay_layer_map, %{
         start_x: start_x,
         start_y: start_y,
         max_x: max_x,
         max_y: max_y
       }) do
    if has_wide_glyphs?(layer_map) or has_wide_glyphs?(overlay_layer_map) do
      merge_visible_layer_maps(layer_map, overlay_layer_map, start_x, start_y, max_x, max_y)
      |> layer_map_rows_to_content(start_x, start_y, max_x, max_y)
    else
      reset = Termite.Style.reset_code()

      rows =
        Enum.map(start_y..max_y, fn y ->
          {segments, buffer, style, _} =
            Enum.reduce(start_x..max_x, {[], [], "", false}, fn x,
                                                                {segments, buffer, last_style,
                                                                 skip} ->
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
                {nil, _, ""} ->
                  {segments, [" " | buffer], "", skip_next}

                {nil, _, _last_style} ->
                  {flush_buffer(segments, buffer, last_style, reset), [" "], "", skip_next}

                {{char, style}, _, style} ->
                  {segments, [char | buffer], style, skip_next}

                {{char, style}, _, _last_style} ->
                  {flush_buffer(segments, buffer, last_style, reset), [char], style, skip_next}
              end
            end)

          flush_buffer(segments, buffer, style, reset)
          |> Enum.reverse()
        end)

      rows
      |> Enum.intersperse("\n")
      |> IO.iodata_to_binary()
    end
  end

  defp flush_buffer(segments, [], _style, _reset), do: segments
  defp flush_buffer(segments, buffer, nil, _reset), do: [Enum.reverse(buffer) | segments]
  defp flush_buffer(segments, buffer, "", _reset), do: [Enum.reverse(buffer) | segments]

  defp flush_buffer(segments, buffer, style, reset) do
    [reset, Enum.reverse(buffer), style | segments]
  end

  defp layer_map_rows_to_content(layer_map, start_x, start_y, max_x, max_y) do
    reset = Termite.Style.reset_code()
    rows = group_layer_map_rows(layer_map, start_x, start_y, max_x, max_y)

    start_y..max_y
    |> Enum.map(fn y ->
      {segments, buffer, style, cursor_x} =
        rows
        |> Map.get(y, [])
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.reduce({[], [], "", start_x}, fn {x, char, style},
                                                 {segments, buffer, last_style, cursor_x} ->
          {segments, buffer, last_style} =
            append_gap(segments, buffer, last_style, reset, max(x - cursor_x, 0))

          segments =
            if style == last_style do
              segments
            else
              flush_buffer(segments, buffer, last_style, reset)
            end

          buffer =
            if style == last_style do
              [char | buffer]
            else
              [char]
            end

          {segments, buffer, style, x + Ucwidth.width(char)}
        end)

      {segments, buffer, style} =
        append_gap(segments, buffer, style, reset, max(max_x + 1 - cursor_x, 0))

      flush_buffer(segments, buffer, style, reset)
      |> Enum.reverse()
    end)
    |> Enum.intersperse("\n")
    |> IO.iodata_to_binary()
  end

  defp append_gap(segments, buffer, "", _reset, 0), do: {segments, buffer, ""}
  defp append_gap(segments, buffer, style, _reset, 0), do: {segments, buffer, style}

  defp append_gap(segments, buffer, "", _reset, gap) do
    {segments, [String.duplicate(" ", gap) | buffer], ""}
  end

  defp append_gap(segments, buffer, style, reset, gap) do
    {flush_buffer(segments, buffer, style, reset), [String.duplicate(" ", gap)], ""}
  end

  defp group_layer_map_rows(layer_map, start_x, start_y, max_x, max_y) do
    Enum.reduce(layer_map, %{}, fn
      {{y, x}, {char, style}}, acc
      when y >= start_y and y <= max_y and x >= start_x and x <= max_x ->
        Map.update(acc, y, [{x, char, style}], &[{x, char, style} | &1])

      _, acc ->
        acc
    end)
  end

  defp merge_visible_layer_maps(layer_map, overlay_layer_map, start_x, start_y, max_x, max_y) do
    filter_layer_map(layer_map, start_x, start_y, max_x, max_y)
    |> Map.merge(filter_layer_map(overlay_layer_map, start_x, start_y, max_x, max_y))
  end

  defp filter_layer_map(layer_map, start_x, start_y, max_x, max_y) do
    filtered =
      Enum.reduce(layer_map, %{}, fn
        {@wide_glyph_key, true}, acc ->
          acc

        {{y, x}, value}, acc when y >= start_y and y <= max_y and x >= start_x and x <= max_x ->
          Map.put(acc, {y, x}, value)

        _, acc ->
          acc
      end)

    if has_wide_glyphs?(layer_map) and map_size(filtered) > 0 do
      Map.put(filtered, @wide_glyph_key, true)
    else
      filtered
    end
  end

  defp has_wide_glyphs?(layer_map), do: Map.get(layer_map, @wide_glyph_key, false)

  defp layer_map_entries?(layer_map) do
    map_size(layer_map) > if(has_wide_glyphs?(layer_map), do: 1, else: 0)
  end

  defp wide_continuation?(layer_map, y, x) when x > 0 do
    case Map.get(layer_map, {y, x - 1}) do
      {char, _style} -> Ucwidth.width(char) == 2
      _ -> false
    end
  end

  defp wide_continuation?(_layer_map, _y, _x), do: false

  defp clip_child_layer_map(layer_map, %{overflow: :hidden, border: border}, max_x, max_y)
       when is_integer(max_x) and is_integer(max_y) do
    left = if border.left, do: 1, else: 0
    top = if border.top, do: 1, else: 0
    right = max(max_x - if(border.right, do: 1, else: 0), left - 1)
    bottom = max(max_y - if(border.bottom, do: 1, else: 0), top - 1)

    clipped =
      Enum.reduce(layer_map, %{}, fn
        {@wide_glyph_key, true}, acc ->
          acc

        {{y, x}, value}, acc when x >= left and x <= right and y >= top and y <= bottom ->
          Map.put(acc, {y, x}, value)

        _, acc ->
          acc
      end)

    if has_wide_glyphs?(layer_map) and map_size(clipped) > 0 do
      Map.put(clipped, @wide_glyph_key, true)
    else
      clipped
    end
  end

  defp clip_child_layer_map(layer_map, _style, _width, _height), do: layer_map

  defp clip_child_layer_map_required?(
         child_width,
         child_height,
         %{border: border},
         max_x,
         max_y,
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

  defp clip_child_layer_map_required?(
         _child_width,
         _child_height,
         _style,
         _max_x,
         _max_y,
         _has_overlay_children?
       ),
       do: true

  defp shift_layer_map(layer_map, shift_x, shift_y) do
    shifted =
      Enum.reduce(layer_map, %{}, fn
        {@wide_glyph_key, true}, acc ->
          acc

        {{y, x}, value}, acc ->
          Map.put(acc, {y + shift_y, x + shift_x}, value)

        _, acc ->
          acc
      end)

    if has_wide_glyphs?(layer_map) and map_size(shifted) > 0 do
      Map.put(shifted, @wide_glyph_key, true)
    else
      shifted
    end
  end

  defp add_layer_codepoint(codepoint, map, x, y, max_x, current_seq, seq)
       when is_integer(codepoint) do
    width = Ucwidth.width_codepoint(codepoint)
    char = <<codepoint::utf8>>

    map =
      map
      |> Map.put({y, x}, {char, current_seq})
      |> maybe_mark_wide_glyph(width)

    {x + width, y, {map, max(max_x, x + width), false, seq}}
  end

  defp maybe_mark_wide_glyph(map, width) when width > 1, do: Map.put(map, @wide_glyph_key, true)
  defp maybe_mark_wide_glyph(map, _width), do: map

  defp raw_content_width(content) when is_binary(content), do: content_metrics(content) |> elem(0)

  defp raw_content_width(_), do: 0

  defp rendered_height(content) when is_binary(content), do: content_metrics(content) |> elem(1)

  defp rendered_height(_), do: 0

  defp content_metrics(content) when is_binary(content) do
    {max_width, current_width, line_count, _in_seq} = content_metrics(content, 0, 0, 1, false)
    {max(max_width, current_width), line_count}
  end

  defp content_metrics(<<>>, max_width, current_width, line_count, in_seq) do
    {max_width, current_width, line_count, in_seq}
  end

  defp content_metrics(<<"\n", rest::binary>>, max_width, current_width, line_count, in_seq) do
    content_metrics(rest, max(max_width, current_width), 0, line_count + 1, in_seq)
  end

  defp content_metrics(<<"\e", rest::binary>>, max_width, current_width, line_count, _in_seq) do
    content_metrics(rest, max_width, current_width, line_count, true)
  end

  defp content_metrics(<<"m", rest::binary>>, max_width, current_width, line_count, true) do
    content_metrics(rest, max_width, current_width, line_count, false)
  end

  defp content_metrics(<<_char, rest::binary>>, max_width, current_width, line_count, true) do
    content_metrics(rest, max_width, current_width, line_count, true)
  end

  defp content_metrics(<<char, rest::binary>>, max_width, current_width, line_count, false)
       when char < 128 do
    content_metrics(rest, max_width, current_width + 1, line_count, false)
  end

  defp content_metrics(
         <<codepoint::utf8, rest::binary>>,
         max_width,
         current_width,
         line_count,
         false
       ) do
    content_metrics(
      rest,
      max_width,
      current_width + Ucwidth.width_codepoint(codepoint),
      line_count,
      false
    )
  end

  defp resolved_parent_width(%{width: rendered_width, style: style}, _opts)
       when is_integer(rendered_width) do
    max(rendered_width - border_horizontal(style.border) - padding_horizontal(style), 0)
  end

  defp resolved_parent_width(%{style: %{width: width} = style}, opts) do
    case width do
      w when is_integer(w) ->
        max(w - border_horizontal(style.border) - padding_horizontal(style), 0)

      :screen ->
        {screen_width, _screen_height} =
          BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

        max(screen_width - border_horizontal(style.border) - padding_horizontal(style), 0)

      _ ->
        nil
    end
  end

  defp resolved_parent_height(%{height: rendered_height, style: style}, _opts)
       when is_integer(rendered_height) do
    max(rendered_height - border_vertical(style.border) - padding_vertical(style), 0)
  end

  defp resolved_parent_height(%{style: %{height: height} = style}, opts) do
    case height do
      h when is_integer(h) ->
        max(h - border_vertical(style.border) - padding_vertical(style), 0)

      :screen ->
        {_screen_width, screen_height} =
          BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

        max(screen_height - border_vertical(style.border) - padding_vertical(style), 0)

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
        (display != :inline && child.style.width in [:full, :screen]) || auto_wrap_leaf_child? ||
          (not overlay_position?(child) && auto_fill_container?)

      if should_fill_width? do
        %{child | style: %{child.style | width: max(0, parent_width)}}
      else
        child
      end
    end)
  end

  defp resolve_fill_width(child, _display, nil, _used_width, _overflow), do: child

  defp resolve_fill_width(child, :inline, parent_width, used_width, _overflow) do
    if child.style.width in [:full, :screen] and not overlay_position?(child) do
      remaining_width = max(parent_width - used_width, 0)
      %{child | style: %{child.style | width: remaining_width}}
    else
      child
    end
  end

  defp resolve_fill_width(child, _display, _parent_width, _used_width, _overflow), do: child

  defp resolve_fill_height(child, _display, nil, _used_height), do: child

  defp resolve_fill_height(child, :inline, parent_height, _used_height) do
    if child.style.height in [:full, :screen] do
      %{child | style: %{child.style | height: max(0, parent_height)}}
    else
      child
    end
  end

  defp resolve_fill_height(child, :block, parent_height, used_height) do
    if child.style.height not in [:full, :screen] do
      child
    else
      used_height = if overlay_position?(child), do: 0, else: used_height
      %{child | style: %{child.style | height: max(0, parent_height - used_height)}}
    end
  end

  defp resolve_overlay_fill_size(%{position: position} = child, parent, opts)
       when position in [:absolute, :fixed] do
    {container_width, container_height} =
      overlay_container_size(child, parent, nil, parent.style.border, opts)

    width =
      constrained_overlay_extent(
        child.style.width,
        child.left,
        child.right,
        container_width,
        border_horizontal(child.style.border)
      )

    height =
      constrained_overlay_extent(
        child.style.height,
        child.top,
        child.bottom,
        container_height,
        border_vertical(child.style.border)
      )

    style =
      child.style
      |> maybe_put_extent(:width, width)
      |> maybe_put_extent(:height, height)

    %{child | style: style}
  end

  defp resolve_overlay_fill_size(child, _parent, _opts), do: child

  defp constrained_overlay_extent(extent, start_edge, end_edge, container_extent, _border_extent)
       when extent in [:screen, :full] and is_integer(start_edge) and is_integer(end_edge) and
              is_integer(container_extent) do
    max(container_extent - start_edge - end_edge, 0)
  end

  defp constrained_overlay_extent(extent, start_edge, end_edge, container_extent, _border_extent)
       when is_integer(extent) and is_integer(start_edge) and is_integer(end_edge) and
              is_integer(container_extent) and extent >= container_extent do
    max(container_extent - start_edge - end_edge, 0)
  end

  defp constrained_overlay_extent(
         _extent,
         _start_edge,
         _end_edge,
         _container_extent,
         _border_extent
       ),
       do: nil

  defp maybe_put_extent(style, _field, nil), do: style
  defp maybe_put_extent(style, field, value), do: Map.put(style, field, value)

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

  defp child_origin(%{display: :inline, style: style} = parent, child, used_extent, opts) do
    {inner_left, inner_top} = content_origin(style)
    left = used_extent + inner_left
    top = inner_top

    if overlay_position?(child),
      do: resolve_overlay_origin(child, parent, parent.style.border, opts),
      else: {left, top}
  end

  defp child_origin(%{style: style} = parent, child, used_extent, opts) do
    {inner_left, inner_top} = content_origin(style)
    left = inner_left
    top = used_extent + inner_top

    if overlay_position?(child),
      do: resolve_overlay_origin(child, parent, parent.style.border, opts),
      else: {left, top}
  end

  defp child_extent(child, :inline), do: child.width || raw_content_width(child.content)
  defp child_extent(child, _display), do: child.height || rendered_height(child.content)

  defp append_rendered_child_dimensions(acc, dimensions, left_offset, top_offset) do
    shifted =
      dimensions
      |> shift_dimensions(left_offset, top_offset)
      |> Enum.with_index(acc.id)
      |> Enum.map(fn {dims, id} -> {id, dims} end)

    %{acc | dimensions: acc.dimensions ++ shifted, id: acc.id + length(dimensions)}
  end

  defp prefix_offsets(values) do
    {offsets, _sum} =
      Enum.map_reduce(values, 0, fn value, sum ->
        {sum, sum + value}
      end)

    offsets
  end

  defp shift_dimensions(dimensions, left_offset, top_offset) do
    Enum.map(dimensions, &shift_dimension(&1, left_offset, top_offset))
  end

  defp structured_block_layer_map?(box, relative) do
    match?(:block, box.display) and
      box.scroll == {0, 0} and
      relative != []
  end

  defp compose_block_children_layer_map(relative, box) do
    border_left = border_left_offset(box.style.border)
    border_top = border_top_offset(box.style.border)

    children =
      Enum.map(relative, fn child ->
        %{
          child
          | position: :absolute,
            left: max((child.left || 0) - border_left, 0),
            top: max((child.top || 0) - border_top, 0)
        }
      end)

    %{width: width, height: height, layer_map: layer_map} =
      compose_absolute_children_layer_map(children, sorted: true)

    {width, height, layer_map}
  end

  defp ensure_rendered_content(%{content: content} = box) when is_binary(content), do: box

  defp ensure_rendered_content(%{layer_map: layer_map, width: width, height: height} = box) do
    %{box | content: layer_map_to_content(layer_map, width, height)}
  end

  defp cached_layer_maps_to_content(layer_map, overlay_layer_map, bounds) do
    area = (bounds.max_x - bounds.start_x + 1) * (bounds.max_y - bounds.start_y + 1)

    if area >= 256 and (map_size(layer_map) > 0 or map_size(overlay_layer_map) > 0) do
      RenderCache.fetch_stable(
        {:layer_maps_to_content, layer_map, overlay_layer_map, bounds},
        fn ->
          layer_maps_to_content(layer_map, overlay_layer_map, bounds)
        end
      )
    else
      layer_maps_to_content(layer_map, overlay_layer_map, bounds)
    end
  end

  defp materialized_content(%{content: content}) when is_binary(content), do: content

  defp materialized_content(%{layer_map: layer_map, width: width, height: height}) do
    layer_map_to_content(layer_map, width, height)
  end

  defp shift_dimension(dims, left_offset, top_offset) do
    dims
    |> Map.update(:left, left_offset, &(&1 + left_offset))
    |> Map.update(:top, top_offset, &(&1 + top_offset))
  end

  defp border_left_offset(border), do: if(border.left, do: 1, else: 0)
  defp border_top_offset(border), do: if(border.top, do: 1, else: 0)

  defp padding_horizontal(style),
    do: style_value(style, :padding_left) + style_value(style, :padding_right)

  defp padding_vertical(style),
    do: style_value(style, :padding_top) + style_value(style, :padding_bottom)

  defp content_origin(style) do
    {
      border_left_offset(style.border) + style_value(style, :padding_left),
      border_top_offset(style.border) + style_value(style, :padding_top)
    }
  end

  defp style_value(style, side_key) do
    case Map.get(style, side_key) do
      value when is_integer(value) -> value
      _ -> Map.get(style, :padding, 0) || 0
    end
  end

  defp plain_content_container?(box, child_content, has_overlay_children?)
       when is_binary(child_content) do
    box.scroll == {0, 0} and
      box.children != [] and
      box.style.scrollbar == false and
      not has_overlay_children? and plain_wrapper_style?(box)
  end

  defp plain_content_container?(_box, _child_layer_map, _has_overlay_children?), do: false

  defp plain_content_children?(box, absolutes, has_overlay_children?, relative_has_overlay?) do
    absolutes == [] and box.scroll == {0, 0} and box.style.scrollbar == false and
      not has_overlay_children? and not relative_has_overlay? and plain_wrapper_style?(box)
  end

  defp plain_wrapper_style?(%{
         content: "",
         position: :relative,
         left: nil,
         top: nil,
         style: %BackBreeze.Style{
           bold: false,
           italic: false,
           padding: 0,
           padding_top: nil,
           padding_right: nil,
           padding_bottom: nil,
           padding_left: nil,
           reverse: false,
           border: border,
           overflow: :auto,
           scrollbar: false,
           border_color: nil,
           foreground_color: nil,
           background_color: nil
         }
       }) do
    border == BackBreeze.Border.none()
  end

  defp plain_wrapper_style?(_box), do: false

  defp visual_overflow?(%{overflow: :hidden}, _content_height, _height), do: false
  defp visual_overflow?(_style, content_height, height), do: content_height > max(height || 0, 0)

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

  defp inherit_parent_background(%{style: style} = child, %{background_color: background_color})
       when not is_nil(background_color) do
    if is_nil(style.background_color) do
      %{child | style: BackBreeze.Style.background_color(style, background_color)}
    else
      child
    end
  end

  defp inherit_parent_background(child, _parent_style), do: child

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
        resolved_parent_overlay_extent(parent, :width, border, opts)
      )

    height =
      first_size(
        rendered_parent && rendered_parent.height,
        parent.height,
        resolved_parent_overlay_extent(parent, :height, border, opts)
      )

    {
      resolved_overlay_width(width, border, opts),
      resolved_overlay_height(height, border, opts)
    }
  end

  defp resolved_overlay_width(width, _border, _opts) when is_integer(width),
    do: width

  defp resolved_overlay_width(:screen, _border, opts) do
    {screen_width, _screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
    screen_width
  end

  defp resolved_overlay_width(_, _border, _opts), do: 0

  defp resolved_overlay_height(height, _border, _opts) when is_integer(height),
    do: height

  defp resolved_overlay_height(:screen, _border, opts) do
    {_screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))
    screen_height
  end

  defp resolved_overlay_height(_, _border, _opts), do: 0

  defp resolved_parent_overlay_extent(%{position: :fixed} = parent, :width, _border, opts) do
    {screen_width, _screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    constrained_overlay_extent(
      parent.style.width,
      parent.left,
      parent.right,
      screen_width,
      border_horizontal(parent.style.border)
    ) || resolved_overlay_width(parent.style.width, parent.style.border, opts)
  end

  defp resolved_parent_overlay_extent(%{position: :fixed} = parent, :height, _border, opts) do
    {_screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    constrained_overlay_extent(
      parent.style.height,
      parent.top,
      parent.bottom,
      screen_height,
      border_vertical(parent.style.border)
    ) || resolved_overlay_height(parent.style.height, parent.style.border, opts)
  end

  defp resolved_parent_overlay_extent(parent, :width, _border, opts),
    do: Map.get(parent.style, :width) |> resolved_overlay_width(parent.style.border, opts)

  defp resolved_parent_overlay_extent(parent, :height, _border, opts),
    do: Map.get(parent.style, :height) |> resolved_overlay_height(parent.style.border, opts)

  defp resolve_edge_offset(value, _opposite, _child_size, _container_size) when is_integer(value),
    do: value

  defp resolve_edge_offset(:center, _opposite, child_size, container_size)
       when is_integer(child_size) and is_integer(container_size) do
    max(div(container_size - child_size, 2), 0)
  end

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
      style_value(style, :padding_top) == 0 &&
      style_value(style, :padding_right) == 0 &&
      style_value(style, :padding_bottom) == 0 &&
      style_value(style, :padding_left) == 0 &&
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
    max_width =
      items
      |> Enum.map(&raw_content_width/1)
      |> Enum.max(fn -> 0 end)

    items =
      Enum.flat_map(items, &:binary.split(&1, "\n", [:global]))

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
    items = Enum.map(items, fn x -> {max(rendered_height(x) - 1, 0), x} end)

    {max_height, _} = Enum.max(items)

    rows =
      items
      |> Enum.map(fn {height, item} ->
        padding = String.duplicate("\n", max_height - height)

        :binary.split(padding <> item, "\n", [:global])
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
