defmodule BackBreeze.Box do
  @moduledoc """
  A Box is the basic styling primitive used in BackBreeze. If a box has children,
  they will be rendered first and collapsed down, until a single box remains with
  the rendered contents.
  """
  alias BackBreeze.BenchProfile
  alias BackBreeze.Box.BlockLayerMap
  alias BackBreeze.Box.CacheKey
  alias BackBreeze.Box.Geometry
  alias BackBreeze.Box.LayoutOnly
  alias BackBreeze.RenderCache
  alias BackBreeze.VirtualText
  alias BackBreeze.Box.LayerMap
  alias BackBreeze.Box.PositionedLayout
  alias BackBreeze.Box.TextMetrics
  alias BackBreeze.Grid.Children, as: GridChildren

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
            fixed_layer_map: %{},
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
    RenderCache.with_frame(fn ->
      fetch_box_render(box, fn -> render_with_dimensions_cache_key(box, opts) end, fn ->
        do_render_with_dimensions(box, opts)
      end)
      |> maybe_flatten_rendered_box(opts)
    end)
  end

  defp do_render_with_dimensions(box, opts) do
    %{box: box, dimensions: dimensions} =
      render_and_calc(%{box: box, dimensions: [], id: 0}, opts)

    dimensions = Enum.sort(dimensions) |> Enum.map(&elem(&1, 1))
    box = ensure_rendered_content(box)
    %{box: box, dimensions: dimensions}
  end

  @doc false
  def render_structured_with_dimensions(box, opts \\ []) do
    RenderCache.with_frame(fn ->
      fetch_box_render(box, fn -> render_structured_cache_key(box, opts) end, fn ->
        do_render_structured_with_dimensions(box, opts)
      end)
    end)
  end

  defp do_render_structured_with_dimensions(box, opts) do
    %{box: box, dimensions: dimensions} =
      render_and_calc(
        %{box: box, dimensions: [], id: 0},
        Keyword.put(opts, :structured, true)
      )

    %{box: box, dimensions: Enum.sort(dimensions) |> Enum.map(&elem(&1, 1))}
  end

  @doc false
  def render_cached_with_dimensions(box, opts \\ []) do
    render_cached_target(box, opts)
  end

  defp fetch_box_render(box, cache_key_fun, render_fun) do
    if CacheKey.cacheable?(box) do
      RenderCache.fetch_stable(cache_key_fun.(), render_fun)
    else
      render_fun.()
    end
  end

  defp render_cached_target(box, opts) do
    if structured_render?(opts) do
      render_structured_with_dimensions(box, Keyword.delete(opts, :structured))
    else
      render_with_dimensions(box, opts)
    end
  end

  defp render_with_dimensions_cache_key(box, opts) do
    {:render_with_dimensions, terminal_size(opts), CacheKey.box_key(box)}
  end

  defp render_structured_cache_key(box, opts) do
    {:render_structured_with_dimensions, terminal_size(opts), CacheKey.box_key(box)}
  end

  defp structured_render?(opts), do: Keyword.get(opts, :structured, false)

  defp terminal_size(opts) do
    case Keyword.get(opts, :terminal) do
      nil -> nil
      terminal -> terminal.size
    end
  end

  defp cached_or_generate_layer_map(%{content: %VirtualText{cache?: false}}, content) do
    LayerMap.generate(content, %{}, 0, 0)
  end

  defp cached_or_generate_layer_map(_box, content), do: LayerMap.cached_generate(content)

  defp cached_or_layer_maps_to_content(box, layer_map, overlay_layer_map, bounds) do
    if CacheKey.cacheable?(box) do
      LayerMap.cached_to_content(layer_map, overlay_layer_map, bounds)
    else
      LayerMap.to_content(layer_map, overlay_layer_map, bounds)
    end
  end

  @doc false
  def compose_absolute_children(children, opts \\ []) do
    %{width: width, height: height, layer_map: layer_map, fixed_layer_map: fixed_layer_map} =
      compose_absolute_children_layer_map(children, opts)

    %{
      content: layer_maps_to_content(layer_map, fixed_layer_map, width, height),
      width: width,
      height: height,
      layer_map: layer_map,
      fixed_layer_map: fixed_layer_map
    }
  end

  @doc false
  def positioned_overlay?(box), do: PositionedLayout.overlay?(box)

  @doc false
  def compose_absolute_children_layer_map(children, opts \\ []),
    do: PositionedLayout.compose_absolute_children_layer_map(children, opts)

  @doc false
  def compose_non_overlapping_children_layer_map(children, opts \\ []),
    do: PositionedLayout.compose_non_overlapping_children_layer_map(children, opts)

  @doc false
  def layer_map_to_content(layer_map, width, height) do
    LayerMap.cached_to_content(layer_map, %{}, %{
      start_x: 0,
      start_y: 0,
      max_x: width - 1,
      max_y: height - 1
    })
  end

  @doc false
  def layer_maps_to_content(layer_map, fixed_layer_map, width, height) do
    LayerMap.cached_to_content(layer_map, fixed_layer_map, %{
      start_x: 0,
      start_y: 0,
      max_x: width - 1,
      max_y: height - 1
    })
  end

  @doc false
  def localize_fixed_layer_map(%BackBreeze.Box{fixed_layer_map: fixed_layer_map} = box)
      when map_size(fixed_layer_map) > 0 do
    {layer_map, max_x, max_y} = LayerMap.merge(box.layer_map, fixed_layer_map, {0, 0})
    width = max(box.width || 0, max_x + 1)
    height = max(box.height || 0, max_y + 1)

    %{
      box
      | layer_map: layer_map,
        fixed_layer_map: %{},
        width: width,
        height: height,
        content: layer_map_to_content(layer_map, width, height)
    }
  end

  def localize_fixed_layer_map(%BackBreeze.Box{} = box), do: box

  defp render_and_calc(%{box: %{state: :rendered}} = acc, _opts) do
    acc
  end

  defp render_and_calc(%{box: %{children: []} = box} = acc, opts) do
    {content, dimensions, width} =
      BenchProfile.measure({__MODULE__, :render_self}, fn -> render_self(box, opts) end)

    {direct_layer_map, dimensions} = Map.pop(dimensions, :layer_map)

    dimensions =
      dimensions
      |> Map.put(:width, width)
      |> Map.put_new(:viewport_width, width)
      |> Map.put_new(:content_width, width)
      |> Map.put(:left, 0)
      |> Map.put(:top, 0)

    structured? = Keyword.get(opts, :structured, false)

    {content, width, layer_map} =
      maybe_add_self_scrollbar(box, content, width, dimensions, direct_layer_map, structured?)

    box = %{
      box
      | content: content,
        width: width,
        height: dimensions.height,
        state: :rendered,
        children: [],
        layer_map: layer_map,
        overlay?:
          not Map.get(dimensions, :scrollbar_rendered?, false) and
            visual_overflow?(box.style, dimensions.content_height, dimensions.height)
    }

    %{acc | box: box, dimensions: [{acc.id, dimensions} | acc.dimensions], id: acc.id + 1}
  end

  defp render_and_calc(%{box: box} = acc, opts) do
    prev_id = acc.id
    {children_result, acc} = render_child_result(acc, prev_id, opts)
    render_context = child_render_context(box, children_result, prev_id, opts)

    render_child_container(acc, box, render_context, opts)
  end

  defp render_child_result(acc, prev_id, opts) do
    {child_layer_map, child_fixed_layer_map, child_width, child_height, has_overlay_children?, child_layer, children,
     acc} =
      BenchProfile.measure({__MODULE__, :render_children}, fn ->
        render_children(%{acc | id: prev_id + 1}, opts)
      end)

    {
      %{
        layer_map: child_layer_map,
        fixed_layer_map: child_fixed_layer_map,
        width: child_width,
        height: child_height,
        has_overlay_children?: has_overlay_children?,
        layer: child_layer,
        children: children
      },
      acc
    }
  end

  defp child_render_context(box, children_result, prev_id, opts) do
    structured? = Keyword.get(opts, :structured, false)

    children_content_height =
      case box.display do
        %BackBreeze.Grid{} ->
          max(content_height(children_result.children, box.display), children_result.height)

        _ ->
          content_height(children_result.children, box.display)
      end

    overlay_only_children? =
      children_result.children != [] and
        Enum.all?(children_result.children, &(&1.position == :absolute or &1.overlay?))

    preserve_base_scroll? = renderable_content?(box.content) and overlay_only_children?

    rendered_child = %{
      content: children_result.layer_map,
      width: children_result.width,
      height: children_result.height,
      layer: children_result.layer
    }

    %{
      children: children_result.children,
      rendered_child: rendered_child,
      fixed_layer_map: children_result.fixed_layer_map,
      children_content_height: children_content_height,
      has_overlay_children?: children_result.has_overlay_children?,
      preserve_base_scroll?: preserve_base_scroll?,
      box_style: box.style,
      opts: opts,
      prev_id: prev_id,
      structured?: structured?
    }
  end

  defp render_child_container(acc, box, render_context, opts) do
    render_path = child_container_render_path(box, render_context)

    case render_path do
      :wrapped ->
        render_wrapped_content_container(acc, render_context.prev_id, render_context.rendered_child, opts)

      :plain_content ->
        render_plain_content_container(acc, render_context.prev_id, render_context.rendered_child)

      :passthrough_layer_map ->
        render_passthrough_layer_map_container(
          acc,
          render_context.prev_id,
          hd(render_context.children),
          render_context.rendered_child
        )

      :regular ->
        render_regular_child_container(acc, box, render_context)
    end
  end

  defp maybe_add_self_scrollbar(box, content, width, dimensions, direct_layer_map, structured?) do
    if self_scrollbar_required?(box, dimensions) do
      {base_layer_map, max_width, max_height} =
        self_scrollbar_base_layer_map(box, content, width, dimensions, direct_layer_map)

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
        self_scrollbar_content(box, layer_map, max_width, max_height, structured?),
        max_width + 1,
        layer_map
      }
    else
      {content, width, %{}}
    end
  end

  defp self_scrollbar_required?(box, dimensions) do
    {scrollbar_config, _} = BackBreeze.Scrollbar.normalize(box.style.scrollbar, box.style)

    box.style.overflow == :hidden and scrollbar_config.enabled and
      not Map.get(dimensions, :scrollbar_rendered?, false)
  end

  defp self_scrollbar_base_layer_map(_box, _content, width, dimensions, layer_map)
       when is_map(layer_map) do
    {layer_map, max(width - 1, 0), max(dimensions.height - 1, 0)}
  end

  defp self_scrollbar_base_layer_map(box, content, _width, _dimensions, _direct_layer_map) do
    BenchProfile.measure({__MODULE__, :generate_layer_map}, fn ->
      cached_or_generate_layer_map(box, content)
    end)
  end

  defp self_scrollbar_content(box, layer_map, max_width, max_height, structured?) do
    if not structured? do
      BenchProfile.measure({__MODULE__, :layer_maps_to_content}, fn ->
        cached_or_layer_maps_to_content(box, layer_map, %{}, %{
          start_x: 0,
          start_y: 0,
          max_x: max_width,
          max_y: max_height
        })
      end)
    end
  end

  defp render_regular_child_container(acc, box, context) do
    extent = regular_child_container_extent(box.style, context)
    style = %{box.style | width: extent.width, height: extent.height}

    {content, dimensions, rendered_width} = render_child_container_self(box, style, context)

    border_rows = border_row_count(box.style.border)

    dimensions =
      regular_child_container_dimensions(dimensions, context, extent.width, border_rows)

    acc = %{acc | dimensions: [{context.prev_id, dimensions} | acc.dimensions], id: acc.id}

    layer_result = regular_child_container_layer_result(box, content, rendered_width, dimensions, context)

    content = regular_child_container_content(box, layer_result, context)

    box = %{
      box
      | content: content,
        width: layer_result.max_width + 1,
        height: layer_result.max_height + 1,
        layer: max(box.layer || 0, context.rendered_child.layer || 0),
        state: :rendered,
        children: [],
        layer_map: layer_result.layer_map,
        fixed_layer_map: layer_result.fixed_layer_map,
        overlay?: context.has_overlay_children?
    }

    %{acc | box: box}
  end

  defp regular_child_container_extent(style, context) do
    %{
      width: regular_child_container_width(style, context.rendered_child.width),
      height: regular_child_container_height(style, context.children_content_height)
    }
  end

  defp regular_child_container_width(style, child_width) do
    style_width = if style.width == :auto, do: 0, else: style.width

    cond do
      style.overflow == :hidden and is_integer(style.width) and style.width > 0 ->
        style.width

      is_integer(style.width) and style.width > 0 ->
        style.width

      true ->
        max(
          style_width,
          child_width + Geometry.padding_horizontal(style) + Geometry.border_horizontal(style.border)
        )
    end
  end

  defp regular_child_container_height(style, children_content_height) do
    style_height = if style.height == :auto, do: 0, else: style.height

    height =
      cond do
        style.overflow == :hidden and is_integer(style.height) and style.height > 0 ->
          style.height

        is_integer(style.height) and style.height > 0 ->
          style.height

        true ->
          max(
            style_height,
            children_content_height + Geometry.padding_vertical(style) +
              Geometry.border_vertical(style.border)
          )
      end

    BackBreeze.Style.constrain_height(height, style.max_height)
  end

  defp render_child_container_self(box, style, context) do
    scroll = if context.preserve_base_scroll?, do: box.scroll, else: {0, 0}

    BenchProfile.measure({__MODULE__, :render_self}, fn ->
      render_self(
        %{box | width: style.width, height: style.height, style: style, scroll: scroll},
        context.opts
      )
    end)
  end

  defp regular_child_container_dimensions(base_dimensions, context, width, border_rows) do
    base_content_height = Map.get(base_dimensions, :content_height, 0)

    %{
      content_height: max(base_content_height, context.children_content_height),
      viewport_height: base_dimensions.height - border_rows,
      viewport_width: width,
      height: base_dimensions.height,
      width: width
    }
    |> maybe_resolve_regular_child_container_height(context, border_rows)
    |> Map.put(:width, width)
    |> Map.put_new(:viewport_width, width)
    |> Map.put_new(:content_width, width)
    |> Map.put(:left, 0)
    |> Map.put(:top, 0)
  end

  defp maybe_resolve_regular_child_container_height(dimensions, context, border_rows) do
    style = context.box_style

    if style.height in [:auto, :full] ||
         (is_integer(style.height) and style.height <= 0 and style.width != :screen) do
      resolved_height =
        max(dimensions.height, dimensions.content_height)
        |> BackBreeze.Style.constrain_height(style.max_height)

      %{
        dimensions
        | height: resolved_height,
          viewport_height: max(dimensions.viewport_height, resolved_height - border_rows)
      }
    else
      dimensions
    end
  end

  defp regular_child_container_layer_result(box, content, rendered_width, dimensions, context) do
    base_layer_context = %{
      content: content,
      rendered_width: rendered_width,
      rendered_height: dimensions.height
    }

    base_layer = regular_child_container_base_layer(box, context, base_layer_context)

    max_height = max(base_layer.max_height, max(dimensions.height - 1, 0))
    child_layer_map = scrolled_child_layer_map(context.rendered_child.content, box.scroll)

    base_bounds = %{max_width: base_layer.max_width, max_height: max_height}

    child_layer_map =
      maybe_clip_regular_child_layer_map(child_layer_map, box, context, base_bounds)

    {max_width, max_height} =
      regular_child_container_bounds(box, child_layer_map, base_bounds, context)

    scrollbar_context = %{
      dimensions: dimensions,
      max_width: max_width,
      max_height: max_height,
      content_width: context.rendered_child.width
    }

    child_layer_map = add_regular_child_scrollbar(child_layer_map, box, scrollbar_context)

    layer_map = merge_regular_child_layer_map(base_layer.layer_map, child_layer_map)

    %{
      layer_map: layer_map,
      fixed_layer_map: context.fixed_layer_map,
      max_width: max_width,
      max_height: max_height
    }
  end

  defp regular_child_container_base_layer(box, context, base_layer_context) do
    skip_base_context = %{
      children: context.children,
      has_overlay_children?: context.has_overlay_children?,
      rendered_width: base_layer_context.rendered_width,
      rendered_height: base_layer_context.rendered_height
    }

    if skip_container_base_layer?(box, skip_base_context) do
      %{
        layer_map: %{},
        max_width: max(base_layer_context.rendered_width - 1, 0),
        max_height: max(base_layer_context.rendered_height - 1, 0)
      }
    else
      {layer_map, max_width, max_height} =
        BenchProfile.measure({__MODULE__, :container_base_layer}, fn ->
          LayerMap.cached_blank_container(
            box,
            base_layer_context.rendered_width,
            base_layer_context.rendered_height
          ) ||
            cached_or_generate_layer_map(box, base_layer_context.content)
        end)

      %{layer_map: layer_map, max_width: max_width, max_height: max_height}
    end
  end

  defp scrolled_child_layer_map(child_layer_map, {_offset_top, offset_left}) do
    if offset_left > 0 do
      LayerMap.shift(child_layer_map, -offset_left, 0)
    else
      child_layer_map
    end
  end

  defp maybe_clip_regular_child_layer_map(child_layer_map, box, context, bounds) do
    {_offset_top, offset_left} = box.scroll

    clip_context = %{
      offset_left: offset_left,
      offset_top: elem(box.scroll, 0),
      max_x: bounds.max_width,
      max_y: bounds.max_height,
      has_overlay_children?: context.has_overlay_children?
    }

    if clip_regular_child_layer_map?(box.style, context) and
         child_layer_map_clip_required?(context.rendered_child, box.style, clip_context) do
      BenchProfile.measure({__MODULE__, :clip_child_layer_map}, fn ->
        LayerMap.clip_child(child_layer_map, box.style, %{
          max_x: bounds.max_width,
          max_y: bounds.max_height
        })
      end)
    else
      child_layer_map
    end
  end

  defp clip_regular_child_layer_map?(style, context) do
    style.overflow == :hidden ||
      (((is_integer(style.height) and style.height > 0) or
          (is_integer(style.max_height) and style.max_height >= 0)) and
         not context.has_overlay_children?)
  end

  defp regular_child_container_bounds(box, child_layer_map, base_bounds, context) do
    {child_merge_width, child_merge_height} =
      regular_child_merge_bounds(child_layer_map, context.fixed_layer_map, context.rendered_child)

    max_width =
      if box.style.overflow == :hidden do
        base_bounds.max_width
      else
        max(base_bounds.max_width, child_merge_width)
      end

    max_height =
      cond do
        box.style.overflow == :hidden ->
          base_bounds.max_height

        is_integer(box.style.max_height) and box.style.max_height >= 0 ->
          base_bounds.max_height

        box.style.height in [:auto, :full] ||
            (is_integer(box.style.height) and box.style.height <= 0) ->
          max(base_bounds.max_height, child_merge_height)

        true ->
          base_bounds.max_height
      end

    {max_width, max_height}
  end

  defp regular_child_merge_bounds(child_layer_map, child_fixed_layer_map, rendered_child) do
    if LayerMap.content?(child_layer_map) or LayerMap.content?(child_fixed_layer_map) do
      {max(rendered_child.width - 1, 0), max(rendered_child.height - 1, 0)}
    else
      {rendered_child.width, rendered_child.height}
    end
  end

  defp add_regular_child_scrollbar(child_layer_map, box, context) do
    BenchProfile.measure({__MODULE__, :scrollbar_layer_map}, fn ->
      BackBreeze.Scrollbar.add_to_layer_map(child_layer_map, %{
        style: box.style,
        scroll: box.scroll,
        content_height: context.dimensions.content_height,
        content_width: context.content_width,
        max_x: context.max_width,
        max_y: context.max_height
      })
    end)
  end

  defp merge_regular_child_layer_map(layer_map, child_layer_map) do
    BenchProfile.measure({__MODULE__, :merge_layer_maps}, fn ->
      case LayerMap.merge_metadata_base(layer_map, child_layer_map) do
        {:ok, map} ->
          map

        :error ->
          LayerMap.merge_map(layer_map, child_layer_map, {0, 0})
      end
    end)
  end

  defp regular_child_container_content(_box, _layer_result, %{structured?: true}), do: nil

  defp regular_child_container_content(box, layer_result, _context) do
    BenchProfile.measure({__MODULE__, :layer_maps_to_content}, fn ->
      cached_or_layer_maps_to_content(
        box,
        layer_result.layer_map,
        layer_result.fixed_layer_map,
        %{
          start_x: 0,
          start_y: 0,
          max_x: layer_result.max_width,
          max_y: layer_result.max_height
        }
      )
    end)
  end

  defp border_row_count(border) do
    if(border.top, do: 1, else: 0) + if(border.bottom, do: 1, else: 0)
  end

  defp render_passthrough_layer_map_container(
         %{box: box} = acc,
         prev_id,
         child,
         %{layer: child_layer}
       ) do
    dimensions =
      %{
        width: child.width,
        viewport_width: child.width,
        content_width: child.width,
        height: child.height,
        viewport_height: child.height,
        content_height: child.height,
        left: 0,
        top: 0
      }

    box = %{
      box
      | content: child.content,
        width: child.width,
        height: child.height,
        layer: max(box.layer || 0, child_layer || 0),
        state: :rendered,
        children: [],
        layer_map: child.layer_map,
        overlay?: false
    }

    %{acc | box: box, dimensions: [{prev_id, dimensions} | acc.dimensions], id: acc.id}
  end

  defp render_plain_content_container(
         %{box: box} = acc,
         prev_id,
         %{content: child_content, layer: child_layer}
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
         %{content: child_content, width: child_width, height: child_height, layer: child_layer},
         opts
       ) do
    {width, height} = wrapped_content_extent(box.style, child_width, child_height)
    style = %{box.style | width: width, height: height}

    {content, dimensions, width} =
      render_self(
        %{
          box
          | content: child_content,
            children: [],
            scroll: {0, 0},
            width: width,
            height: height,
            style: style
        },
        opts
      )

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

  defp wrapped_content_extent(style, child_width, child_height) do
    {
      wrapped_content_width(style, child_width),
      wrapped_content_height(style, child_height)
    }
  end

  defp wrapped_content_width(style, child_width) do
    style_width = if style.width == :auto, do: 0, else: style.width

    if is_integer(style.width) and style.width > 0 do
      style.width
    else
      max(
        style_width,
        child_width + Geometry.padding_horizontal(style) + Geometry.border_horizontal(style.border)
      )
    end
  end

  defp wrapped_content_height(style, child_height) do
    style_height = if style.height == :auto, do: 0, else: style.height

    height =
      if is_integer(style.height) and style.height > 0 do
        style.height
      else
        max(
          style_height,
          child_height + Geometry.padding_vertical(style) + Geometry.border_vertical(style.border)
        )
      end

    BackBreeze.Style.constrain_height(height, style.max_height)
  end

  defp render_self(box, opts) do
    {offset_top, _} = box.scroll
    opts = Keyword.put(opts, :offset_top, offset_top)
    terminal = Keyword.get(opts, :terminal)
    box = normalize_container_box(box)

    cache_key =
      {:render_self, box.style, CacheKey.content_key(box.content), offset_top,
       if(terminal, do: terminal.size, else: nil)}

    render = fn ->
      {content, dimensions} = BackBreeze.Style.calculate_and_render(box.style, box.content, opts)
      {rendered_width, dimensions} = Map.pop(dimensions, :rendered_width)
      max_width = rendered_width || raw_content_width(content)
      {content, dimensions, max_width}
    end

    if CacheKey.cacheable?(box), do: RenderCache.fetch_stable(cache_key, render), else: render.()
  end

  defp normalize_container_box(box) do
    style =
      box.style
      |> maybe_resolve_container_extent(:width, box.width)
      |> maybe_resolve_container_extent(:height, box.height)

    %{box | style: style}
  end

  defp maybe_resolve_container_extent(style, _field, value) when not is_integer(value),
    do: style

  defp maybe_resolve_container_extent(style, field, value) do
    case Map.get(style, field) do
      extent when extent in [:full, :screen] -> Map.put(style, field, value)
      _ -> style
    end
  end

  defp renderable_content?(content) when is_binary(content), do: content != ""
  defp renderable_content?(content) when is_list(content), do: content != []
  defp renderable_content?(%VirtualText{}), do: true
  defp renderable_content?(_content), do: false

  defp render_children(
         %{box: %{children: children, display: %BackBreeze.Grid{}} = box} = acc,
         opts
       ) do
    box = normalize_container_box(box)

    {children, grouped_dims, grid_result} = render_grid_children(children, box, opts)
    children = set_layer(children, [], -1)
    relative = relative_children(children)
    has_overlay_children? = grid_overlay_children?(children)
    {layer, style} = child_layer_and_style(children, relative)
    acc = append_grid_dimensions(acc, grouped_dims, grid_result.per_item_dimensions, box.style)

    absolutes = grid_absolute_children(children)
    relative_has_overlay? = overlay_children?(relative)

    if not Keyword.get(opts, :structured, false) and
         plain_content_children?(box, absolutes, has_overlay_children?, relative_has_overlay?) do
      {grid_result.content, %{}, grid_result.width, grid_result.height, false, layer, children, acc}
    else
      relative =
        relative_render_box(box, %{
          style: style,
          content: grid_result.content,
          height: grid_result.height,
          width: grid_result.width,
          layer: layer,
          layer_map: grid_result.layer_map,
          fixed_layer_map: grid_result.fixed_layer_map,
          overlay?: has_overlay_children?
        })

      combine_context = %{box: box, absolutes: absolutes, relative: relative, opts: opts}

      {layer_map, fixed_layer_map, width, height, acc} =
        combine_children(acc, combine_context)

      width = max(width, raw_content_width(grid_result.content))
      height = max(height, rendered_height(grid_result.content))

      {layer_map, fixed_layer_map, width, height, has_overlay_children?, layer, children, acc}
    end
  end

  defp render_children(%{box: %{children: children} = box} = acc, opts) when children != [] do
    {children, acc} = render_flow_children(children, box, acc, opts)
    context = flow_children_context(box, children)
    opts = flow_join_opts(box, context.relative_has_overlay?, opts)
    structured? = Keyword.get(opts, :structured, false)
    context = Map.put(context, :structured?, structured?)

    {content, width, height, relative_layer_map, relative_fixed_layer_map} =
      join_flow_children(box, context, opts)

    relative =
      relative_render_box(box, %{
        style: context.style,
        content: content,
        height: height,
        width: width,
        layer: context.layer,
        layer_map: relative_layer_map,
        fixed_layer_map: relative_fixed_layer_map
      })

    finish_flow_children(acc, box, children, relative, context, content, width, height, opts)
  end

  defp render_grid_children(children, box, opts) do
    %{
      width: item_width,
      height: item_height,
      column_widths: column_widths,
      row_heights: row_heights
    } =
      BackBreeze.Grid.precompute(children, box.display, box.style, opts)

    column_offsets = prefix_offsets(column_widths)
    row_offsets = prefix_offsets(row_heights)

    grid_context = %{
      box: box,
      opts: opts,
      item_width: item_width,
      item_height: item_height,
      column_widths: column_widths,
      row_heights: row_heights,
      column_offsets: column_offsets,
      row_offsets: row_offsets
    }

    {children, grouped_dims} =
      BenchProfile.measure({__MODULE__, :grid_prepare_children}, fn ->
        GridChildren.prepare(children, grid_context)
      end)

    %{
      per_item_dimensions: _per_item_dims,
      layer_map: _grid_layer_map,
      fixed_layer_map: _grid_fixed_layer_map
    } =
      grid_result =
      BackBreeze.Grid.render_with_dimensions(children, box.display, box.style, opts)

    {children, grouped_dims, grid_result}
  end

  defp append_grid_dimensions(acc, grouped_dims, per_item_dims, style) do
    {final_id, new_dims} =
      Enum.zip(grouped_dims, per_item_dims)
      |> Enum.reduce({acc.id, []}, fn {grouped, child_dims}, {id, acc_d} ->
        dims = grouped.dims || child_dims
        entries = Enum.with_index(dims, id) |> Enum.map(fn {d, i} -> {i, d} end)
        {id + length(dims), Enum.reverse(entries, acc_d)}
      end)
      |> then(fn {final_id, dims} -> {final_id, Enum.reverse(dims)} end)

    {content_left, content_top} = Geometry.content_origin(style)

    new_dims =
      Enum.map(new_dims, fn {id, dims} ->
        {id, shift_dimension(dims, content_left, content_top)}
      end)

    %{acc | dimensions: Enum.reverse(new_dims, acc.dimensions), id: final_id}
  end

  defp render_flow_children(children, box, acc, opts) do
    parent_width = Geometry.resolved_parent_width(box, opts)
    parent_height = Geometry.resolved_parent_height(box, opts)

    context = %{
      box: box,
      opts: opts,
      display: box.display,
      parent_width: parent_width,
      parent_height: parent_height
    }

    {children, acc, _used_extent} =
      BenchProfile.measure({__MODULE__, :flow_children}, fn ->
        children
        |> prepare_flow_children(box, parent_width)
        |> Enum.reduce({[], acc, 0}, &render_flow_child(&1, &2, context))
      end)

    {Enum.reverse(children), acc}
  end

  defp prepare_flow_children(children, box, parent_width) do
    children
    |> set_layer([], -1)
    |> Enum.map(&inherit_parent_colors(&1, box.style))
    |> Enum.map(&PositionedLayout.resolve_fill_offsets(&1, box.style.border))
    |> resolve_fill_widths(parent_width, box.display, box.style.overflow)
  end

  defp render_flow_child(child, {boxes, child_acc, used_extent}, context) do
    child =
      child
      |> resolve_fill_width(context, used_extent)
      |> resolve_fill_height(context.display, context.parent_height, used_extent)
      |> PositionedLayout.resolve_fill_size(context.box, context.opts)

    child_result =
      BenchProfile.measure({__MODULE__, :flow_child_render}, fn ->
        layout_opts =
          if context.display == :inline do
            Keyword.put(context.opts, :structured, true)
          else
            context.opts
          end

        LayoutOnly.child_result(child, layout_opts) ||
          render_cached_with_dimensions(child,
            structured: true,
            terminal: Keyword.get(context.opts, :terminal)
          )
      end)

    {child_left, child_top} = child_origin(context.box, child_result.box, used_extent, context.opts)

    child_acc =
      append_rendered_child_dimensions(
        child_acc,
        child_result.dimensions,
        child_left,
        child_top
      )

    rendered_child = position_flow_child(child_result.box, child_left, child_top)
    used_extent = advance_flow_extent(rendered_child, context.display, used_extent)

    {[rendered_child | boxes], child_acc, used_extent}
  end

  defp position_flow_child(child, child_left, child_top) do
    if PositionedLayout.overlay?(child) do
      child
    else
      %{child | left: child_left, top: child_top}
    end
  end

  defp advance_flow_extent(child, display, used_extent) do
    if PositionedLayout.overlay?(child) do
      used_extent
    else
      used_extent + child_extent(child, display)
    end
  end

  defp flow_children_context(box, children) do
    relative = relative_children(children)
    has_overlay_children? = Enum.any?(children, &(PositionedLayout.overlay?(&1) || &1.overlay?))
    {layer, style} = child_layer_and_style(children, relative)

    %{
      children: children,
      relative: relative,
      absolutes: flow_absolute_children(children, box),
      has_overlay_children?: has_overlay_children?,
      relative_has_overlay?: overlay_children?(relative),
      layer: layer,
      style: style
    }
  end

  defp flow_join_opts(box, relative_has_overlay?, opts) do
    resolved_join_height =
      if box.display == :block and relative_has_overlay? and box.style.overflow != :hidden do
        nil
      else
        box.style.height
      end

    resolved_join_height =
      case {resolved_join_height, box.style.max_height} do
        {height, max_height}
        when is_integer(max_height) and max_height >= 0 and
               (is_integer(height) or height in [:auto, :full, :screen]) ->
          BackBreeze.Style.constrain_height(
            if(is_integer(height), do: height, else: max_height),
            max_height
          )

        _ ->
          resolved_join_height
      end

    opts
    |> Keyword.put(:height, resolved_join_height)
    |> Keyword.put(:scroll, box.scroll)
  end

  defp join_flow_children(box, context, opts) do
    retain_layer_map_context = %{
      relative: context.relative,
      absolutes: context.absolutes,
      relative_has_overlay?: context.relative_has_overlay?,
      structured?: context.structured?
    }

    BenchProfile.measure({__MODULE__, :flow_join}, fn ->
      if BlockLayerMap.retain_for_combine?(box, retain_layer_map_context) do
        {width, height, layer_map, fixed_layer_map} =
          BlockLayerMap.compose(context.relative, box)

        {nil, width, height, layer_map, fixed_layer_map}
      else
        items = Enum.map(context.relative, &materialized_flow_content(&1, box.display))

        {content, width, height} =
          case box.display do
            :block -> join_vertical(items, opts)
            :inline -> join_horizontal(items)
          end

        {content, width, height, %{}, %{}}
      end
    end)
  end

  defp finish_flow_children(acc, box, children, relative, context, content, width, height, opts) do
    if not context.structured? and
         plain_content_children?(
           box,
           context.absolutes,
           context.has_overlay_children?,
           context.relative_has_overlay?
         ) do
      {content, %{}, width, height, false, context.layer, children, acc}
    else
      {origin_x, origin_y} = Geometry.content_origin(box.style)
      combine_context = %{box: box, absolutes: context.absolutes, relative: relative, opts: opts}

      {layer_map, fixed_layer_map, width, height, acc} =
        combine_children(acc, combine_context)

      width = max(width + 1 - origin_x, raw_content_width(content))
      height = max(height + 1 - origin_y, rendered_height(content))

      {
        layer_map,
        fixed_layer_map,
        width,
        height,
        context.has_overlay_children?,
        context.layer,
        children,
        acc
      }
    end
  end

  defp relative_render_box(box, attrs) do
    %{
      box
      | style: attrs.style,
        content: attrs.content,
        children: [],
        height: attrs.height,
        width: attrs.width,
        layer: attrs.layer,
        position: :relative,
        left: nil,
        top: nil,
        layer_map: attrs.layer_map,
        fixed_layer_map: attrs.fixed_layer_map,
        overlay?: Map.get(attrs, :overlay?, box.overlay?)
    }
  end

  defp relative_children(children), do: Enum.filter(children, &(not PositionedLayout.overlay?(&1)))

  defp grid_absolute_children(children), do: Enum.filter(children, &(&1.position == :absolute))

  defp flow_absolute_children(children, %{style: %{overflow: :hidden}}) do
    Enum.filter(children, &PositionedLayout.overlay?/1)
  end

  defp flow_absolute_children(children, _box) do
    overlay_absolutes =
      children
      |> Enum.filter(&(not PositionedLayout.overlay?(&1) and &1.overlay?))
      |> Enum.map(&%{&1 | position: :absolute})

    Enum.filter(children, &PositionedLayout.overlay?/1) ++ overlay_absolutes
  end

  defp overlay_children?(children), do: Enum.any?(children, & &1.overlay?)

  defp grid_overlay_children?(children) do
    Enum.any?(
      children,
      &(PositionedLayout.overlay?(&1) || &1.overlay? || contains_overlay_descendants?(&1))
    )
  end

  defp child_layer_and_style([%{} | _] = children, [first_relative | _]) do
    {Enum.max(Enum.map(children, & &1.layer)), first_relative.style}
  end

  defp child_layer_and_style([%{} | _] = children, _relative) do
    {Enum.max(Enum.map(children, & &1.layer)), %BackBreeze.Style{}}
  end

  defp child_layer_and_style(_children, _relative), do: {0, %BackBreeze.Style{}}

  defp content_height(children, :inline) do
    children
    |> Enum.reject(&(&1.position == :absolute))
    |> Enum.map(&(&1.height || 0))
    |> Enum.max(fn -> 0 end)
  end

  defp content_height(children, %BackBreeze.Grid{}) do
    children
    |> Enum.reject(&PositionedLayout.overlay?/1)
    |> Enum.map(fn child -> normalize_grid_offset(child.top) + (child.height || 0) end)
    |> Enum.max(fn -> 0 end)
  end

  defp content_height(children, _display) do
    Enum.reduce(children, 0, fn
      %{position: position}, acc when position in [:absolute, :fixed] -> acc
      child, acc -> acc + (child.height || 0)
    end)
  end

  defp normalize_grid_offset(offset) when is_integer(offset), do: offset
  defp normalize_grid_offset(_offset), do: 0

  defp combine_children(acc, %{box: box, absolutes: absolutes, relative: relative, opts: opts}) do
    BenchProfile.measure({__MODULE__, {:combine_children, length(absolutes)}}, fn ->
      {map, fixed_map, width, height} =
        PositionedLayout.combine_children(box, absolutes, relative, opts)

      {map, fixed_map, width, height, acc}
    end)
  end

  defp fixed_layer_map(%{fixed_layer_map: fixed_layer_map}) when is_map(fixed_layer_map),
    do: fixed_layer_map

  defp fixed_layer_map(_), do: %{}

  defp child_layer_map_clip_required?(
         _rendered_child,
         _style,
         %{offset_left: offset_left, offset_top: offset_top}
       )
       when offset_left > 0 or offset_top > 0,
       do: true

  defp child_layer_map_clip_required?(
         %{width: child_width, height: child_height},
         style,
         %{max_x: max_x, max_y: max_y, has_overlay_children?: has_overlay_children?}
       ) do
    child = %{width: child_width, height: child_height}
    bounds = %{max_x: max_x, max_y: max_y}
    LayerMap.clip_required?(child, style, bounds, has_overlay_children?)
  end

  defp raw_content_width(content), do: TextMetrics.width(content)
  defp rendered_height(content), do: TextMetrics.height(content)

  defp resolve_fill_widths(children, nil, _display, _overflow), do: children

  defp resolve_fill_widths(children, parent_width, display, overflow) do
    context = %{parent_width: parent_width, display: display, overflow: overflow}
    Enum.map(children, &resolve_child_fill_width(&1, context))
  end

  defp resolve_child_fill_width(child, context) do
    if child_should_fill_width?(child, context) do
      %{child | style: %{child.style | width: max(0, context.parent_width)}}
    else
      child
    end
  end

  defp child_should_fill_width?(child, context) do
    explicit_fill_width?(child, context.display) or
      auto_wrap_leaf_child?(child, context) or
      auto_fill_container?(child, context.display)
  end

  defp explicit_fill_width?(child, display) do
    display != :inline and child.style.width in [:full, :screen]
  end

  defp auto_fill_container?(child, :block) do
    not PositionedLayout.overlay?(child) and
      child.style.width == :auto and
      (match?(%BackBreeze.Grid{}, child.display) or
         (child.display != :inline and child.children != []))
  end

  defp auto_fill_container?(_child, _display), do: false

  defp auto_wrap_leaf_child?(child, %{display: :block, overflow: overflow}) do
    overflow != :hidden and
      not PositionedLayout.overlay?(child) and
      child.style.width == :auto and
      child.children == [] and
      plain_wrap_leaf_child?(child)
  end

  defp auto_wrap_leaf_child?(_child, _context), do: false

  defp resolve_fill_width(child, %{parent_width: nil}, _used_width), do: child

  defp resolve_fill_width(child, %{display: :inline, parent_width: parent_width}, used_width) do
    if child.style.width in [:full, :screen] and not PositionedLayout.overlay?(child) do
      remaining_width = max(parent_width - used_width, 0)
      %{child | style: %{child.style | width: remaining_width}}
    else
      child
    end
  end

  defp resolve_fill_width(child, _flow_context, _used_width), do: child

  defp resolve_fill_height(child, _display, nil, _used_height), do: child

  defp resolve_fill_height(child, :inline, parent_height, _used_height) do
    if child.style.height in [:full, :screen] do
      height =
        max(0, parent_height)
        |> BackBreeze.Style.constrain_height(child.style.max_height)

      %{child | style: %{child.style | height: height}}
    else
      child
    end
  end

  defp resolve_fill_height(child, :block, parent_height, used_height) do
    if child.style.height not in [:full, :screen] do
      child
    else
      used_height = if PositionedLayout.overlay?(child), do: 0, else: used_height

      height =
        max(0, parent_height - used_height)
        |> BackBreeze.Style.constrain_height(child.style.max_height)

      %{child | style: %{child.style | height: height}}
    end
  end

  defp child_origin(%{display: :inline, style: style} = parent, child, used_extent, opts) do
    {inner_left, inner_top} = Geometry.content_origin(style)
    left = used_extent + inner_left
    top = inner_top

    if PositionedLayout.overlay?(child),
      do: PositionedLayout.resolve_origin(child, parent, nil, opts),
      else: {left, top}
  end

  defp child_origin(%{style: style} = parent, child, used_extent, opts) do
    {inner_left, inner_top} = Geometry.content_origin(style)
    left = inner_left
    top = used_extent + inner_top

    if PositionedLayout.overlay?(child),
      do: PositionedLayout.resolve_origin(child, parent, nil, opts),
      else: {left, top}
  end

  defp child_extent(child, :inline), do: child.width || raw_content_width(child.content)

  defp child_extent(child, _display) do
    positive_size(child.height) ||
      positive_size(LayerMap.height(child.layer_map)) ||
      positive_size(rendered_height(child.content)) ||
      1
  end

  defp positive_size(value) when is_integer(value) and value > 0, do: value
  defp positive_size(_value), do: nil

  defp append_rendered_child_dimensions(acc, dimensions, left_offset, top_offset) do
    {shifted, next_id} =
      Enum.map_reduce(dimensions, acc.id, fn dims, id ->
        {{id, shift_dimension(dims, left_offset, top_offset)}, id + 1}
      end)

    %{acc | dimensions: Enum.reverse(shifted, acc.dimensions), id: next_id}
  end

  defp prefix_offsets(values) do
    {offsets, _sum} =
      Enum.map_reduce(values, 0, fn value, sum ->
        {sum, sum + value}
      end)

    offsets
  end

  defp ensure_rendered_content(%{content: content, fixed_layer_map: fixed_layer_map} = box)
       when is_binary(content) and map_size(fixed_layer_map) == 0,
       do: box

  defp ensure_rendered_content(%{layer_map: layer_map, width: width, height: height} = box) do
    content =
      LayerMap.cached_to_content(layer_map, fixed_layer_map(box), %{
        start_x: 0,
        start_y: 0,
        max_x: width - 1,
        max_y: height - 1
      })

    %{box | content: content}
  end

  defp maybe_flatten_rendered_box(%{box: box} = result, opts) do
    if is_binary(box.content) and not Keyword.get(opts, :structured, false) and
         not LayerMap.content?(box.layer_map) and
         not LayerMap.content?(fixed_layer_map(box)) do
      %{result | box: %{box | layer_map: %{}}}
    else
      result
    end
  end

  defp materialized_content(%{fixed_layer_map: fixed_layer_map} = box)
       when map_size(fixed_layer_map) > 0 do
    if LayerMap.content?(box.layer_map) do
      layer_map_to_content(box.layer_map, box.width, box.height)
    else
      ""
    end
  end

  defp materialized_content(%{content: content}) when is_binary(content), do: content

  defp materialized_content(%{layer_map: layer_map, width: width, height: height}) do
    layer_map_to_content(layer_map, width, height)
  end

  defp materialized_flow_content(box, :inline) do
    case {materialized_content(box), box.width} do
      {"", width} when is_integer(width) and width > 0 ->
        String.duplicate(" ", width)

      {content, _width} ->
        content
    end
  end

  defp materialized_flow_content(box, _display),
    do: materialized_content(box)

  defp shift_dimension(dims, left_offset, top_offset) do
    dims
    |> Map.update(:left, left_offset, &(&1 + left_offset))
    |> Map.update(:top, top_offset, &(&1 + top_offset))
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

  defp child_container_render_path(_box, %{structured?: true}),
    do: :regular

  defp child_container_render_path(box, %{
         children: children,
         rendered_child: %{content: child_content},
         has_overlay_children?: has_overlay_children?,
         structured?: false
       }) do
    cond do
      wrappable_single_child_container?(box, children, child_content, has_overlay_children?) ->
        :wrapped

      wrappable_plain_child_container?(box, child_content, has_overlay_children?) ->
        :wrapped

      wrappable_hidden_child_container?(box, child_content, has_overlay_children?) ->
        :wrapped

      plain_content_container?(box, child_content, has_overlay_children?) ->
        :plain_content

      layer_map_passthrough_hidden_wrapper?(box, children, child_content, has_overlay_children?) ->
        :passthrough_layer_map

      true ->
        :regular
    end
  end

  defp wrappable_single_child_container?(box, children, child_content, has_overlay_children?)
       when is_binary(child_content) do
    box.content == "" and
      box.display == :block and
      box.scroll == {0, 0} and
      box.style.scrollbar == false and
      not reflowing_full_extent_wrapper?(box.style) and
      not has_overlay_children? and
      single_relative_child?(children)
  end

  defp wrappable_single_child_container?(_box, _children, _child_content, _has_overlay_children?),
    do: false

  defp wrappable_plain_child_container?(box, child_content, has_overlay_children?)
       when is_binary(child_content) do
    unscrolled_child_without_overlays?(box, has_overlay_children?) and
      plain_wrapper_style?(box) and
      box.style.width not in [:full, :screen] and
      box.style.height not in [:full, :screen]
  end

  defp wrappable_plain_child_container?(_box, _child_content, _has_overlay_children?), do: false

  defp wrappable_hidden_child_container?(box, child_content, has_overlay_children?)
       when is_binary(child_content) do
    unscrolled_child_without_overlays?(box, has_overlay_children?) and
      plain_hidden_wrapper_style?(box)
  end

  defp wrappable_hidden_child_container?(_box, _child_content, _has_overlay_children?),
    do: false

  defp unscrolled_child_without_overlays?(box, has_overlay_children?) do
    box.scroll == {0, 0} and box.style.scrollbar == false and not has_overlay_children?
  end

  defp single_relative_child?([%{position: position}])
       when position != :absolute and position != :fixed,
       do: true

  defp single_relative_child?(_children), do: false

  defp reflowing_full_extent_wrapper?(style) do
    (style.width in [:full, :screen] or style.height in [:full, :screen]) and
      (Geometry.padding_horizontal(style) > 0 or Geometry.padding_vertical(style) > 0 or
         Geometry.border_horizontal(style.border) > 0 or Geometry.border_vertical(style.border) > 0)
  end

  defp layer_map_passthrough_hidden_wrapper?(
         box,
         children,
         child_layer_map,
         has_overlay_children?
       ) do
    box.content == "" and
      box.scroll == {0, 0} and
      box.style.scrollbar == false and
      not has_overlay_children? and
      single_relative_child?(children) and
      LayerMap.content?(child_layer_map) and
      plain_hidden_wrapper_style?(box)
  end

  defp skip_container_base_layer?(
         box,
         %{
           children: children,
           has_overlay_children?: has_overlay_children?,
           rendered_width: rendered_width,
           rendered_height: rendered_height
         }
       ) do
    with %{style: child_style, width: child_width, height: child_height, left: left, top: top} <-
           single_relative_child_box(children),
         true <- is_integer(child_width) and is_integer(child_height),
         true <- empty_passthrough_container?(box, has_overlay_children?),
         true <- child_origin_is_zero?(left, top),
         true <-
           child_fills_container?(child_width, child_height, rendered_width, rendered_height),
         true <- matching_text_styles?(box.style, child_style) do
      true
    else
      _ -> false
    end
  end

  defp empty_passthrough_container?(box, has_overlay_children?) do
    box.content == "" and
      not has_overlay_children? and
      box.scroll == {0, 0} and
      box.style.border == BackBreeze.Border.none() and
      Geometry.zero_padding?(box.style)
  end

  defp child_origin_is_zero?(left, top), do: left in [nil, 0] and top in [nil, 0]

  defp child_fills_container?(child_width, child_height, rendered_width, rendered_height) do
    child_width >= rendered_width and child_height >= rendered_height
  end

  defp matching_text_styles?(parent_style, child_style) do
    child_style.background_color == parent_style.background_color and
      child_style.foreground_color == parent_style.foreground_color and
      child_style.bold == parent_style.bold and
      child_style.italic == parent_style.italic and
      child_style.reverse == parent_style.reverse
  end

  defp single_relative_child_box([%{position: position} = child])
       when position != :absolute and position != :fixed,
       do: child

  defp single_relative_child_box(_children), do: nil

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
           max_height: nil,
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

  defp plain_hidden_wrapper_style?(%{
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
           max_height: nil,
           border: border,
           overflow: :hidden,
           scrollbar: false,
           border_color: nil,
           foreground_color: nil,
           background_color: nil
         }
       }) do
    border == BackBreeze.Border.none()
  end

  defp plain_hidden_wrapper_style?(_box), do: false

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

  defp plain_wrap_leaf_child?(%{style: style}) do
    style.bold == false &&
      style.italic == false &&
      style.reverse == false &&
      style.padding == 0 &&
      Geometry.style_value(style, :padding_top) == 0 &&
      Geometry.style_value(style, :padding_right) == 0 &&
      Geometry.style_value(style, :padding_bottom) == 0 &&
      Geometry.style_value(style, :padding_left) == 0 &&
      style.scrollbar == false &&
      style.border.style == :none &&
      is_nil(style.border_color) &&
      is_nil(style.foreground_color) &&
      is_nil(style.background_color) &&
      style.height == 0 &&
      style.overflow == :auto
  end

  defp contains_overlay_descendants?(%{position: position}) when position in [:absolute, :fixed],
    do: true

  defp contains_overlay_descendants?(%{children: children}) when is_list(children) do
    Enum.any?(children, &contains_overlay_descendants?/1)
  end

  defp contains_overlay_descendants?(_), do: false

  @doc false
  def join_vertical(items, opts \\ []), do: BackBreeze.Box.Join.join_vertical(items, opts)

  @doc false
  def join_horizontal(items, opts \\ []), do: BackBreeze.Box.Join.join_horizontal(items, opts)
end
