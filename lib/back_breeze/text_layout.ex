defmodule BackBreeze.TextLayout do
  @moduledoc false

  alias BackBreeze.TextSpan
  alias BackBreeze.Ucwidth
  alias BackBreeze.VirtualText
  import BackBreeze.Utils, only: [string_length: 1]

  def span_content?(content) when is_list(content) do
    Enum.all?(content, &match?(%TextSpan{}, &1))
  end

  def span_content?(_content), do: false

  def source_metrics(content) when is_binary(content) do
    source_lines = String.split(content, "\n")

    intrinsic_width =
      Enum.reduce(source_lines, 0, fn line, acc ->
        max(acc, string_length(line))
      end)

    {string_length(content), intrinsic_width}
  end

  def source_metrics(content) when is_list(content) do
    {total_width, _line_width, intrinsic_width} =
      Enum.reduce(content, {0, 0, 0}, fn %TextSpan{text: text}, {total, line, max_width} ->
        Enum.reduce(String.graphemes(text), {total, line, max_width}, fn
          "\n", {t, _l, m} ->
            {t + 1, 0, max(m, line)}

          grapheme, {t, l, m} ->
            width = Ucwidth.width(grapheme)
            {t + width, l + width, max(m, l + width)}
        end)
      end)

    {total_width, intrinsic_width}
  end

  def source_metrics(%VirtualText{content: content}) when is_binary(content) do
    source_metrics(content)
  end

  def source_metrics(%VirtualText{intrinsic_width: intrinsic_width, line_count_fn: line_count_fn}) do
    line_count = line_count_fn.(max(intrinsic_width, 1))
    {intrinsic_width * max(line_count, 1), intrinsic_width}
  end

  def prepare(content, width, overflow, height) when is_binary(content) do
    {string_len, intrinsic_width} = source_metrics(content)

    rendered =
      cond do
        string_len <= width -> content
        overflow == :hidden and height == 0 -> BackBreeze.String.truncate(content, width)
        true -> BackBreeze.String.reflow(content, width)
      end

    lines =
      case String.split(rendered, "\n") do
        [""] -> []
        other -> other
      end

    %{
      kind: :binary,
      content: rendered,
      line_offsets: build_line_offsets(rendered, count_lines(rendered)),
      line_count: content_height(lines),
      raw_line_count: length(lines),
      string_length: string_len,
      intrinsic_width: intrinsic_width
    }
  end

  def prepare(content, width, overflow, height) when is_list(content) do
    {string_len, intrinsic_width} = source_metrics(content)
    lines = wrap_spans(content, width, overflow, height)

    %{
      kind: :spans,
      lines: List.to_tuple(lines),
      line_count: content_height(lines),
      raw_line_count: length(lines),
      string_length: string_len,
      intrinsic_width: intrinsic_width
    }
  end

  def prepare(%VirtualText{content: content}, width, overflow, height) when is_binary(content) do
    prepare(content, width, overflow, height)
  end

  def prepare(
        %VirtualText{
          cache_key: cache_key,
          intrinsic_width: intrinsic_width,
          line_count_fn: line_count_fn,
          slice_fn: slice_fn
        },
        width,
        _overflow,
        _height
      ) do
    normalized_width = max(width || intrinsic_width, 1)
    raw_line_count = line_count_fn.(normalized_width)

    %{
      kind: :virtual,
      cache_key: cache_key,
      raw_line_count: raw_line_count,
      line_count: raw_line_count,
      string_length: intrinsic_width * max(raw_line_count, 1),
      intrinsic_width: intrinsic_width,
      slice_fn: fn start, count -> slice_fn.(start, count, normalized_width) end
    }
  end

  def visible_lines(
        %{kind: :binary, content: content, line_offsets: offsets, raw_line_count: total},
        start,
        count
      ) do
    start = max(start, 0)
    last = min(start + count - 1, total - 1)

    if count <= 0 or start > last do
      []
    else
      Enum.map(start..last, &extract_binary_line(content, offsets, &1))
    end
  end

  def visible_lines(%{kind: :spans, lines: lines, raw_line_count: total}, start, count) do
    start = max(start, 0)
    last = min(start + count - 1, total - 1)

    if count <= 0 or start > last do
      []
    else
      Enum.map(start..last, &elem(lines, &1))
    end
  end

  def visible_lines(%{kind: :virtual, raw_line_count: total, slice_fn: slice_fn}, start, count) do
    start = max(start, 0)
    last = min(start + count - 1, total - 1)

    if count <= 0 or start > last do
      []
    else
      slice_fn.(start, last - start + 1)
    end
  end

  def render_line(line, base_style) when is_binary(line) do
    Termite.Style.render_to_string(base_style, line)
  end

  def render_line(segments, base_style) when is_list(segments) do
    Enum.map_join(segments, "", fn {text, style} ->
      merged_style = merge_styles(base_style, style)
      Termite.Style.render_to_string(merged_style, text)
    end)
  end

  @doc false
  def merge_styles(base_style, style) do
    Enum.reduce(style, base_style, fn
      {_key, nil}, acc ->
        acc

      {:bold, true}, acc ->
        Termite.Style.bold(acc)

      {:italic, true}, acc ->
        Termite.Style.italic(acc)

      {:reverse, true}, acc ->
        Termite.Style.reverse(acc)

      {:foreground_color, color}, acc ->
        acc |> remove_style(:foreground) |> Termite.Style.foreground(color)

      {:background_color, color}, acc ->
        acc |> remove_style(:background) |> Termite.Style.background(color)

      _, acc ->
        acc
    end)
  end

  def line_width(line) when is_binary(line), do: string_length(line)

  def line_width(segments) when is_list(segments) do
    Enum.reduce(segments, 0, fn {text, _style}, acc -> acc + string_length(text) end)
  end

  defp wrap_spans(content, width, overflow, height) do
    max_width = if is_integer(width) and width > 0, do: width, else: nil

    {lines, current_line, current_width} =
      Enum.reduce(content, {[], [], 0}, fn %TextSpan{text: text, style: style}, acc ->
        append_span_text(acc, text, style, max_width)
      end)

    lines = finalize_lines(lines, current_line, current_width)

    if overflow == :hidden and height == 0 do
      case lines do
        [line | _] -> [truncate_span_line(line, max_width)]
        [] -> []
      end
    else
      lines
    end
  end

  defp append_span_text({lines, current_line, current_width}, text, style, max_width) do
    Enum.reduce(String.graphemes(text), {lines, current_line, current_width}, fn
      "\n", {acc_lines, acc_line, _width} ->
        {acc_lines ++ [acc_line], [], 0}

      grapheme, {acc_lines, acc_line, width} ->
        grapheme_width = Ucwidth.width(grapheme)

        cond do
          max_width && max_width > 0 && width > 0 && width + grapheme_width > max_width ->
            {acc_lines ++ [acc_line], [{grapheme, style}], grapheme_width}

          true ->
            {acc_lines, append_segment(acc_line, grapheme, style), width + grapheme_width}
        end
    end)
  end

  defp finalize_lines(lines, current_line, current_width) do
    cond do
      current_line != [] -> lines ++ [current_line]
      lines == [] and current_width == 0 -> []
      true -> lines
    end
  end

  defp append_segment([], grapheme, style), do: [{grapheme, style}]

  defp append_segment(segments, grapheme, style) do
    {head, tail} = Enum.split(segments, length(segments) - 1)

    case tail do
      [{text, ^style}] -> head ++ [{text <> grapheme, style}]
      _ -> segments ++ [{grapheme, style}]
    end
  end

  defp truncate_span_line(line, nil), do: line

  defp truncate_span_line(line, width) do
    {segments, _} =
      Enum.reduce_while(line, {[], 0}, fn {text, style}, {acc, cur_width} ->
        {chunk, next_width} = truncate_text_chunk(text, max(width - cur_width, 0))

        cond do
          chunk == "" ->
            {:halt, {acc, cur_width}}

          next_width + cur_width >= width ->
            {:halt, {acc ++ [{chunk, style}], cur_width + next_width}}

          true ->
            {:cont, {acc ++ [{chunk, style}], cur_width + next_width}}
        end
      end)

    segments
  end

  defp truncate_text_chunk(text, width) do
    Enum.reduce_while(String.graphemes(text), {"", 0}, fn grapheme, {acc, current_width} ->
      grapheme_width = Ucwidth.width(grapheme)

      if current_width + grapheme_width > width do
        {:halt, {acc, current_width}}
      else
        {:cont, {acc <> grapheme, current_width + grapheme_width}}
      end
    end)
  end

  defp remove_style(%Termite.Style{styles: styles} = style, key) do
    %{style | styles: Enum.reject(styles, &match?({^key, _}, &1))}
  end

  defp content_height([]), do: 0

  defp content_height(lines) do
    if List.last(lines) == "" or List.last(lines) == [],
      do: length(lines) - 1,
      else: length(lines)
  end

  defp count_lines(""), do: 0

  defp count_lines(content) when is_binary(content) do
    newline_count = byte_size(content) - byte_size(String.replace(content, "\n", ""))
    if String.ends_with?(content, "\n"), do: newline_count, else: newline_count + 1
  end

  defp build_line_offsets(_content, 0), do: {}

  defp build_line_offsets(content, _line_count) do
    [0 | collect_line_offsets(content, 0, [])] |> List.to_tuple()
  end

  defp collect_line_offsets(content, offset, acc) do
    case :binary.match(content, "\n", scope: {offset, byte_size(content) - offset}) do
      {newline_offset, 1} ->
        collect_line_offsets(content, newline_offset + 1, [newline_offset + 1 | acc])

      :nomatch ->
        Enum.reverse(acc)
    end
  end

  defp extract_binary_line(content, offsets, line_no) do
    start_offset = elem(offsets, line_no)
    offset_count = tuple_size(offsets)

    end_offset =
      if line_no + 1 < offset_count do
        elem(offsets, line_no + 1) - 1
      else
        byte_size(content)
      end

    :binary.part(content, start_offset, max(end_offset - start_offset, 0))
  end
end
