defmodule BackBreeze.Scrollbar do
  @moduledoc false

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
  @shows [:auto, :always, :never, :focus]
  @modes [:overlay, :inset]
  @placements [:start, :end]

  @spec normalize(term(), map()) :: t()
  def normalize(value, style \\ %BackBreeze.Style{})

  def normalize(nil, style), do: normalize(false, style)

  def normalize(false, _style), do: %__MODULE__{enabled: false}

  def normalize(true, style) do
    default(style)
    |> Map.put(:enabled, true)
  end

  def normalize(axis, style) when axis in @axes do
    default(style)
    |> Map.merge(%{enabled: true, axis: axis})
  end

  def normalize(%__MODULE__{} = scrollbar, _style), do: scrollbar

  def normalize(map, style) when is_map(map) do
    base = default(style)

    axis = normalize_axis(Map.get(map, :axis, base.axis))
    show = normalize_show(Map.get(map, :show, base.show))
    mode = normalize_mode(Map.get(map, :mode, base.mode))
    placement = normalize_placement(Map.get(map, :placement, base.placement))

    min_thumb_size =
      map
      |> Map.get(:min_thumb_size, base.min_thumb_size)
      |> normalize_int(base.min_thumb_size)
      |> max(1)

    sizing = normalize_sizing(Map.get(map, :sizing, base.sizing))
    arrows = normalize_boolean(Map.get(map, :arrows, base.arrows), base.arrows)

    vertical_placement =
      map
      |> Map.get(:vertical_placement)
      |> normalize_optional_placement()

    horizontal_placement =
      map
      |> Map.get(:horizontal_placement)
      |> normalize_optional_placement()

    common_thumb = Map.get(map, :thumb, %{})
    common_track = Map.get(map, :track, %{})

    vertical_overrides = Map.get(map, :vertical, %{})
    horizontal_overrides = Map.get(map, :horizontal, %{})

    vertical =
      normalize_axis_segments(
        base.vertical,
        common_thumb,
        common_track,
        vertical_overrides,
        Map.get(style, :border_color)
      )

    horizontal =
      normalize_axis_segments(
        base.horizontal,
        common_thumb,
        common_track,
        horizontal_overrides,
        Map.get(style, :border_color)
      )

    intersection =
      base.intersection
      |> merge_segment(Map.get(map, :intersection, %{}), Map.get(style, :border_color))
      |> segment_to_renderable()

    %__MODULE__{
      enabled: true,
      axis: axis,
      show: show,
      mode: mode,
      placement: placement,
      vertical_placement: vertical_placement,
      horizontal_placement: horizontal_placement,
      min_thumb_size: min_thumb_size,
      sizing: sizing,
      arrows: arrows,
      vertical: vertical,
      horizontal: horizontal,
      intersection: intersection
    }
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
  def effective_viewport_size(%__MODULE__{mode: :inset}, width, height, vertical?, horizontal?) do
    width = if vertical?, do: max(width - 1, 0), else: width
    height = if horizontal?, do: max(height - 1, 0), else: height
    {width, height}
  end

  def effective_viewport_size(_config, width, height, _vertical?, _horizontal?),
    do: {width, height}

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

  @spec style_sequence(map()) :: binary()
  def style_sequence(%Segment{} = segment), do: segment.style
  def style_sequence(_segment), do: ""

  @spec segment_char(map()) :: binary() | nil
  def segment_char(%Segment{char: char}), do: char
  def segment_char(_), do: nil

  defp default(style) do
    border_color = Map.get(style, :border_color)

    %__MODULE__{
      enabled: false,
      vertical: %{
        track: %Segment{char: "│", foreground_color: border_color},
        thumb: %Segment{char: "█"},
        arrow_start: %Segment{char: "▲", foreground_color: border_color},
        arrow_end: %Segment{char: "▼", foreground_color: border_color}
      },
      horizontal: %{
        track: %Segment{char: "─", foreground_color: border_color},
        thumb: %Segment{char: "█"},
        arrow_start: %Segment{char: "◀", foreground_color: border_color},
        arrow_end: %Segment{char: "▶", foreground_color: border_color}
      },
      intersection: %Segment{char: "┼", foreground_color: border_color}
    }
    |> renderable_segments()
  end

  defp normalize_axis(value) when value in @axes, do: value
  defp normalize_axis(_), do: :vertical

  defp normalize_show(value) when value in @shows, do: value
  defp normalize_show(_), do: :auto

  defp normalize_mode(value) when value in @modes, do: value
  defp normalize_mode(_), do: :inset

  defp normalize_placement(value) when value in @placements, do: value
  defp normalize_placement(_), do: :end

  defp normalize_optional_placement(value) when value in @placements, do: value
  defp normalize_optional_placement(_), do: nil

  defp normalize_sizing(:proportional), do: :proportional

  defp normalize_sizing({:fixed, value}) do
    {:fixed, max(normalize_int(value, 1), 1)}
  end

  defp normalize_sizing(_), do: :proportional

  defp normalize_boolean(value, _default) when is_boolean(value), do: value

  defp normalize_boolean(value, default) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "true" -> true
      "1" -> true
      "false" -> false
      "0" -> false
      _ -> default
    end
  end

  defp normalize_boolean(_value, default), do: default

  defp normalize_int(value, _default) when is_integer(value), do: value

  defp normalize_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {value, ""} -> value
      _ -> default
    end
  end

  defp normalize_int(_value, default), do: default

  defp normalize_axis_segments(base, common_thumb, common_track, overrides, fallback_color) do
    thumb =
      base.thumb
      |> merge_segment(common_thumb, fallback_color)
      |> merge_segment(Map.get(overrides, :thumb, %{}), fallback_color)
      |> merge_segment(overrides, fallback_color)
      |> segment_to_renderable()

    track =
      base.track
      |> merge_segment(common_track, fallback_color)
      |> merge_segment(Map.get(overrides, :track, %{}), fallback_color)
      |> segment_to_renderable()

    arrow_start =
      base.arrow_start
      |> merge_segment(Map.get(overrides, :arrow_start, %{}), fallback_color)
      |> segment_to_renderable()

    arrow_end =
      base.arrow_end
      |> merge_segment(Map.get(overrides, :arrow_end, %{}), fallback_color)
      |> segment_to_renderable()

    %{thumb: thumb, track: track, arrow_start: arrow_start, arrow_end: arrow_end}
  end

  defp merge_segment(%Segment{} = segment, map, fallback_color) when is_map(map) do
    char = Map.get(map, :char, segment.char)

    segment =
      %Segment{
        segment
        | char: normalize_char(char, segment.char),
          foreground_color:
            map
            |> Map.get(:foreground_color, segment.foreground_color || fallback_color)
            |> normalize_color(segment.foreground_color || fallback_color),
          background_color:
            map
            |> Map.get(:background_color, segment.background_color)
            |> normalize_color(segment.background_color),
          bold: normalize_boolean(Map.get(map, :bold, segment.bold), segment.bold),
          italic: normalize_boolean(Map.get(map, :italic, segment.italic), segment.italic),
          reverse: normalize_boolean(Map.get(map, :reverse, segment.reverse), segment.reverse)
      }

    cond do
      Map.has_key?(map, :char) and map.char == nil -> %Segment{segment | char: nil}
      true -> segment
    end
  end

  defp merge_segment(%Segment{} = segment, _other, _fallback_color), do: segment

  defp normalize_char(nil, default), do: default

  defp normalize_char(char, _default) when is_binary(char) do
    char
    |> String.graphemes()
    |> List.first()
  end

  defp normalize_char(_char, default), do: default

  defp normalize_color(nil, default), do: default

  defp normalize_color(value, _default) when is_integer(value) and value >= 0 and value <= 255,
    do: value

  defp normalize_color(_value, default), do: default

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

    token = "§"

    style_prefix =
      style
      |> Termite.Style.render_to_string(token)
      |> String.split(token, parts: 2)
      |> List.first()

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
end
