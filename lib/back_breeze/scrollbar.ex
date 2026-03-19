defmodule BackBreeze.Scrollbar.Context do
  @moduledoc false

  defstruct style: %BackBreeze.Style{},
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

defmodule BackBreeze.Scrollbar.AxisContext do
  @moduledoc false

  defstruct axis: :vertical,
            config: nil,
            fixed: 0,
            start: 0,
            stop: -1,
            scroll_value: 0,
            content_size: 0,
            viewport_size: 0
end

defmodule BackBreeze.Scrollbar do
  @moduledoc false

  alias BackBreeze.Scrollbar.Context
  alias BackBreeze.Scrollbar.AxisContext

  defmodule Segment do
    @moduledoc false

    defstruct char: nil,
              foreground_color: nil,
              background_color: nil,
              bold: false,
              italic: false,
              reverse: false,
              style: ""
  end

  defstruct enabled: false,
            axis: :vertical,
            show: :auto,
            mode: :inset,
            placement: :end,
            vertical_placement: nil,
            horizontal_placement: nil,
            min_thumb_size: 1,
            sizing: :proportional,
            arrows: false,
            vertical: %{},
            horizontal: %{},
            intersection: nil

  @type t :: %__MODULE__{}

  @axes [:vertical, :horizontal, :both]

  @spec normalize(term(), map()) :: {t(), map()}
  def normalize(value, style \\ %BackBreeze.Style{})

  def normalize(nil, style), do: normalize(false, style)

  def normalize(false, style), do: {%__MODULE__{enabled: false}, style}

  def normalize(true, style) do
    scrollbar = default(style) |> Map.put(:enabled, true)
    {scrollbar, style}
  end

  def normalize(axis, style) when axis in @axes do
    scrollbar = default(style) |> Map.merge(%{enabled: true, axis: axis})
    {scrollbar, style}
  end

  def normalize(%__MODULE__{} = scrollbar, style), do: {scrollbar, style}

  def normalize(map, style) when is_map(map) do
    {base, style} = default(map, style)
    fallback_color = Map.get(style, :border_color)
    fallback_background = Map.get(style, :background_color)
    common_thumb = Map.get(map, :thumb, %{})
    common_track = Map.get(map, :track, %{})

    arrows =
      case Map.get(map, :arrows, false) do
        true -> %{}
        other -> other
      end

    common_arrows = if is_map(arrows), do: arrows, else: %{}

    vertical =
      build_axis_segments(
        base.vertical,
        common_thumb,
        common_track,
        common_arrows,
        Map.get(map, :vertical, %{}),
        fallback_color,
        fallback_background
      )

    horizontal =
      build_axis_segments(
        base.horizontal,
        common_thumb,
        common_track,
        common_arrows,
        Map.get(map, :horizontal, %{}),
        fallback_color,
        fallback_background
      )

    intersection =
      base.intersection
      |> merge_segment(Map.get(map, :intersection, %{}), fallback_color, fallback_background)
      |> segment_to_renderable()

    scrollbar =
      struct(
        base,
        Map.merge(map, %{
          enabled: true,
          arrows: arrows,
          vertical: vertical,
          horizontal: horizontal,
          intersection: intersection
        })
      )

    {scrollbar, style}
  end

  def normalize(_other, style), do: normalize(true, style)

  @spec axis_enabled?(t(), :vertical | :horizontal) :: boolean()
  def axis_enabled?(%__MODULE__{enabled: true, axis: :both}, _axis), do: true
  def axis_enabled?(%__MODULE__{enabled: true, axis: axis}, axis), do: true
  def axis_enabled?(_config, _axis), do: false

  @spec visible?(t(), :vertical | :horizontal, non_neg_integer(), non_neg_integer()) :: boolean()
  def visible?(%__MODULE__{} = config, _axis, content, viewport) do
    overflow? = content > viewport and viewport > 0

    case config.show do
      :never -> false
      :always -> viewport > 0
      :focus -> overflow?
      _ -> overflow?
    end
  end

  @spec effective_viewport_size(t(), non_neg_integer(), non_neg_integer(), boolean(), boolean()) ::
          {non_neg_integer(), non_neg_integer()}
  def effective_viewport_size(%__MODULE__{} = config, width, height, vertical?, horizontal?) do
    effective_viewport_size(config, %{
      width: width,
      height: height,
      vertical?: vertical?,
      horizontal?: horizontal?
    })
  end

  @spec effective_viewport_size(t(), map()) :: {non_neg_integer(), non_neg_integer()}
  def effective_viewport_size(
        %__MODULE__{mode: :inset},
        %{width: width, height: height, vertical?: vertical?, horizontal?: horizontal?}
      ) do
    width = if vertical?, do: max(width - 1, 0), else: width
    height = if horizontal?, do: max(height - 1, 0), else: height
    {width, height}
  end

  def effective_viewport_size(_config, %{width: width, height: height}), do: {width, height}

  @spec placement(t(), :vertical | :horizontal) :: :start | :end
  def placement(%__MODULE__{} = config, :vertical),
    do: config.vertical_placement || config.placement

  def placement(%__MODULE__{} = config, :horizontal),
    do: config.horizontal_placement || config.placement

  @spec thumb_size(t(), non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def thumb_size(%__MODULE__{} = config, track_size, content_size) do
    case config.sizing do
      {:fixed, size} ->
        min(max(size, 1), max(track_size, 1))

      _ ->
        max(
          min(
            round(track_size * max(track_size, 1) / max(content_size, 1)),
            track_size
          ),
          min(config.min_thumb_size, max(track_size, 1))
        )
    end
  end

  @spec put_color(t(), term()) :: t()
  def put_color(%__MODULE__{} = config, color) do
    %{
      config
      | vertical: Map.new(config.vertical, fn {k, s} -> {k, color_segment(s, color)} end),
        horizontal: Map.new(config.horizontal, fn {k, s} -> {k, color_segment(s, color)} end),
        intersection: color_segment(config.intersection, color)
    }
  end

  @spec put_background(t(), term()) :: t()
  def put_background(%__MODULE__{} = config, color) do
    %{
      config
      | vertical: Map.new(config.vertical, fn {k, s} -> {k, background_segment(s, color)} end),
        horizontal: Map.new(config.horizontal, fn {k, s} -> {k, background_segment(s, color)} end),
        intersection: background_segment(config.intersection, color)
    }
  end

  @spec style_sequence(map()) :: binary()
  def style_sequence(%Segment{} = segment), do: segment.style
  def style_sequence(_segment), do: ""

  @spec segment_char(map()) :: binary() | nil
  def segment_char(%Segment{char: char}), do: char
  def segment_char(_), do: nil

  @spec add_to_layer_map(map(), map()) :: map()
  def add_to_layer_map(layer_map, options)
      when is_map(options) and not is_struct(options, Context) do
    options
    |> build_context()
    |> then(&add_to_layer_map(layer_map, &1))
  end

  def add_to_layer_map(layer_map, %Context{} = context) do
    cond do
      context.style.overflow != :hidden or !context.style.scrollbar.enabled ->
        layer_map

      !is_integer(context.max_x) or !is_integer(context.max_y) ->
        layer_map

      true ->
        context = prepare_context(context)

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

  defp color_segment(%Segment{} = segment, color) do
    %{segment | foreground_color: color} |> segment_to_renderable()
  end

  defp color_segment(nil, _color), do: nil

  defp build_context(%{style: style} = options) do
    {normalized, style} = normalize(style.scrollbar, style)
    style = %{style | scrollbar: normalized}
    {scroll_top, scroll_left} = Map.get(options, :scroll, {0, 0})

    %Context{
      style: style,
      content_width: Map.get(options, :content_width, 0),
      content_height: Map.get(options, :content_height, 0),
      scroll_top: scroll_top,
      scroll_left: scroll_left,
      max_x: Map.get(options, :max_x),
      max_y: Map.get(options, :max_y)
    }
  end

  defp prepare_context(%Context{} = context) do
    {left, top, right, bottom} =
      viewport_bounds(context.style.border, context.max_x, context.max_y)

    viewport_width = max(right - left + 1, 0)
    viewport_height = max(bottom - top + 1, 0)

    %{
      context
      | left: left,
        top: top,
        right: right,
        bottom: bottom,
        viewport_width: viewport_width,
        viewport_height: viewport_height,
        content_width: max(context.content_width, viewport_width),
        content_height: max(context.content_height, viewport_height)
    }
    |> resolve_visible_axes()
    |> set_scrollbar_positions()
  end

  defp set_scrollbar_positions(%Context{} = context) do
    vertical_placement = placement(context.style.scrollbar, :vertical)
    horizontal_placement = placement(context.style.scrollbar, :horizontal)

    {x_scrollbar, y_scrollbar} =
      scrollbar_positions(context, vertical_placement, horizontal_placement)

    {vertical_start, vertical_end} =
      trim_axis_for_intersection(
        context.top,
        context.bottom,
        context.horizontal? and y_scrollbar >= context.top and y_scrollbar <= context.bottom,
        horizontal_placement
      )

    {horizontal_start, horizontal_end} =
      trim_axis_for_intersection(
        context.left,
        context.right,
        context.vertical? and x_scrollbar >= context.left and x_scrollbar <= context.right,
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

  defp maybe_clear_scrollbar_strips(layer_map, context) do
    layer_map
    |> maybe_clear_vertical_scrollbar_strip(context)
    |> maybe_clear_horizontal_scrollbar_strip(context)
  end

  defp maybe_clear_vertical_scrollbar_strip(
         layer_map,
         %Context{
           style: %{scrollbar: %{mode: :inset}},
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
         %Context{
           style: %{scrollbar: %{mode: :inset}},
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
         %Context{
           style: %{border: border, scrollbar: config},
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

  defp resolve_visible_axes(%Context{} = context) do
    config = context.style.scrollbar

    vertical? =
      axis_enabled?(config, :vertical) and
        visible?(config, :vertical, context.content_height, context.viewport_height)

    horizontal? =
      axis_enabled?(config, :horizontal) and
        visible?(config, :horizontal, context.content_width, context.viewport_width)

    {eff_viewport_width, eff_viewport_height} =
      effective_viewport_size(config, %{
        width: context.viewport_width,
        height: context.viewport_height,
        vertical?: vertical?,
        horizontal?: horizontal?
      })

    vertical? =
      axis_enabled?(config, :vertical) and
        visible?(config, :vertical, context.content_height, eff_viewport_height)

    horizontal? =
      axis_enabled?(config, :horizontal) and
        visible?(config, :horizontal, context.content_width, eff_viewport_width)

    {eff_viewport_width, eff_viewport_height} =
      effective_viewport_size(config, %{
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

  defp maybe_draw_vertical_scrollbar(layer_map, %Context{vertical?: true} = context) do
    context
    |> vertical_axis_context()
    |> then(&draw_axis_scrollbar(layer_map, &1))
  end

  defp maybe_draw_vertical_scrollbar(layer_map, _context), do: layer_map

  defp maybe_draw_horizontal_scrollbar(layer_map, %Context{horizontal?: true} = context) do
    context
    |> horizontal_axis_context()
    |> then(&draw_axis_scrollbar(layer_map, &1))
  end

  defp maybe_draw_horizontal_scrollbar(layer_map, _context), do: layer_map

  defp vertical_axis_context(%Context{} = context) do
    %AxisContext{
      axis: :vertical,
      config: context.style.scrollbar,
      fixed: context.x_scrollbar,
      start: context.vertical_start,
      stop: context.vertical_end,
      scroll_value: context.scroll_top,
      content_size: context.content_height,
      viewport_size: context.eff_viewport_height
    }
  end

  defp horizontal_axis_context(%Context{} = context) do
    %AxisContext{
      axis: :horizontal,
      config: context.style.scrollbar,
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
         %AxisContext{config: %{arrows: arrows}} = axis_context,
         total_size
       )
       when is_map(arrows) and total_size >= 3 do
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
      thumb_size(
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
         %Context{vertical?: true, horizontal?: true} = context
       ) do
    put_segment(
      layer_map,
      {context.y_scrollbar, context.x_scrollbar},
      context.style.scrollbar.intersection
    )
  end

  defp maybe_draw_intersection(layer_map, _context), do: layer_map

  defp put_segment(layer_map, _point, nil), do: layer_map

  defp put_segment(layer_map, point, segment) do
    char = segment_char(segment)

    if is_binary(char) do
      Map.put(layer_map, point, {char, style_sequence(segment)})
    else
      layer_map
    end
  end

  defp default(map, style) when is_map(map) do
    color = Map.get(map, :foreground_color)

    style =
      if is_nil(Map.get(style, :border_color)) && !is_nil(color),
        do: %{style | border_color: color},
        else: style

    {default(style), style}
  end

  defp default(style) do
    base = %__MODULE__{
      enabled: false,
      vertical: %{
        track: %Segment{char: "│"},
        thumb: %Segment{char: "█"},
        arrow_start: %Segment{char: "▲"},
        arrow_end: %Segment{char: "▼"}
      },
      horizontal: %{
        track: %Segment{char: "─"},
        thumb: %Segment{char: "█"},
        arrow_start: %Segment{char: "◀"},
        arrow_end: %Segment{char: "▶"}
      },
      intersection: %Segment{char: "┘"}
    }

    case Map.get(style, :border_color) do
      nil -> renderable_segments(base)
      color -> put_color(base, color)
    end
  end

  defp build_axis_segments(
         base,
         common_thumb,
         common_track,
         common_arrows,
         overrides,
         fallback_color,
         fallback_background
       ) do
    overrides = if is_map(overrides), do: overrides, else: %{}

    thumb =
      base.thumb
      |> merge_segment(common_thumb, fallback_color, fallback_background)
      |> merge_segment(Map.get(overrides, :thumb, %{}), fallback_color, fallback_background)
      |> merge_segment(overrides, fallback_color, fallback_background)
      |> segment_to_renderable()

    track =
      base.track
      |> merge_segment(common_track, fallback_color, fallback_background)
      |> merge_segment(Map.get(overrides, :track, %{}), fallback_color, fallback_background)
      |> segment_to_renderable()

    arrow_start =
      base.arrow_start
      |> merge_segment(common_arrows, fallback_color, fallback_background)
      |> merge_segment(Map.get(overrides, :arrow_start, %{}), fallback_color, fallback_background)
      |> segment_to_renderable()

    arrow_end =
      base.arrow_end
      |> merge_segment(common_arrows, fallback_color, fallback_background)
      |> merge_segment(Map.get(overrides, :arrow_end, %{}), fallback_color, fallback_background)
      |> segment_to_renderable()

    %{thumb: thumb, track: track, arrow_start: arrow_start, arrow_end: arrow_end}
  end

  defp merge_segment(%Segment{} = segment, map, fallback_color, fallback_background) when is_map(map) do
    char = Map.get(map, :char, segment.char)

    segment =
      %Segment{
        segment
        | char: char,
          foreground_color:
            Map.get(map, :foreground_color, segment.foreground_color || fallback_color),
          background_color:
            Map.get(map, :background_color, segment.background_color || fallback_background),
          bold: Map.get(map, :bold, segment.bold),
          italic: Map.get(map, :italic, segment.italic),
          reverse: Map.get(map, :reverse, segment.reverse)
      }

    cond do
      Map.has_key?(map, :char) and map.char == nil -> %Segment{segment | char: nil}
      true -> segment
    end
  end

  defp merge_segment(%Segment{} = segment, _other, _fallback_color, _fallback_background),
    do: segment

  defp renderable_segments(%__MODULE__{} = config) do
    %{
      config
      | vertical: %{
          thumb: segment_to_renderable(config.vertical.thumb),
          track: segment_to_renderable(config.vertical.track),
          arrow_start: segment_to_renderable(config.vertical.arrow_start),
          arrow_end: segment_to_renderable(config.vertical.arrow_end)
        },
        horizontal: %{
          thumb: segment_to_renderable(config.horizontal.thumb),
          track: segment_to_renderable(config.horizontal.track),
          arrow_start: segment_to_renderable(config.horizontal.arrow_start),
          arrow_end: segment_to_renderable(config.horizontal.arrow_end)
        },
        intersection: segment_to_renderable(config.intersection)
    }
  end

  defp segment_to_renderable(%Segment{} = segment) do
    style =
      Termite.Style.ansi256()
      |> maybe_foreground(segment.foreground_color)
      |> maybe_background(segment.background_color)
      |> maybe_style(:bold, segment.bold)
      |> maybe_style(:italic, segment.italic)
      |> maybe_style(:reverse, segment.reverse)

    style_prefix =
      style
      |> Termite.Style.render_to_string("")
      |> String.trim_trailing(Termite.Style.reset_code())

    %{segment | style: style_prefix}
  end

  defp maybe_foreground(style, nil), do: style
  defp maybe_foreground(style, color), do: Termite.Style.foreground(style, color)

  defp maybe_background(style, nil), do: style
  defp maybe_background(style, color), do: Termite.Style.background(style, color)

  defp maybe_style(style, :bold, true), do: Termite.Style.bold(style)
  defp maybe_style(style, :italic, true), do: Termite.Style.italic(style)
  defp maybe_style(style, :reverse, true), do: Termite.Style.reverse(style)
  defp maybe_style(style, _key, _enabled), do: style

  defp background_segment(%Segment{background_color: nil} = segment, color),
    do: segment_to_renderable(%{segment | background_color: color})

  defp background_segment(segment, _color), do: segment
end
