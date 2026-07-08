defmodule BackBreeze.Box.Join do
  @moduledoc false

  alias BackBreeze.Box.TextMetrics

  def join_vertical([], _opts) do
    {"", 0, 0}
  end

  def join_vertical(items, opts) do
    case single_line_items_metrics(items) do
      {:ok, max_width, line_count} ->
        sliced_items = slice_vertical_items(items, opts)
        {Enum.join(sliced_items, "\n"), max_width, line_count}

      :multiline ->
        do_join_vertical(items, opts)
    end
  end

  def join_horizontal([], _opts) do
    {"", 0, 0}
  end

  def join_horizontal(items, opts) do
    case single_line_horizontal_content(items) do
      {:ok, content, width} ->
        {content, width, 0}

      :multiline ->
        do_join_horizontal(items, opts)
    end
  end

  defp do_join_vertical(items, opts) do
    max_width =
      items
      |> Enum.map(&TextMetrics.width/1)
      |> Enum.max(fn -> 0 end)

    items =
      Enum.flat_map(items, &:binary.split(&1, "\n", [:global]))

    line_count = length(items)

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

    {Enum.join(items, "\n"), max_width, line_count}
  end

  defp single_line_items_metrics(items) do
    Enum.reduce_while(items, {:ok, 0, 0}, fn item, {:ok, max_width, line_count} ->
      case TextMetrics.metrics(item) do
        {width, 1} -> {:cont, {:ok, max(max_width, width), line_count + 1}}
        _ -> {:halt, :multiline}
      end
    end)
  end

  defp slice_vertical_items(items, opts) do
    case Keyword.get(opts, :height) do
      :screen ->
        {_screen_width, screen_height} =
          BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

        slice_vertical_items(items, screen_height, opts)

      height when is_integer(height) ->
        slice_vertical_items(items, height, opts)

      _ ->
        items
    end
  end

  defp slice_vertical_items(items, height, opts) do
    {start_pos, _} = Keyword.get(opts, :scroll, {0, 0})
    end_pos = height + start_pos - 1
    Enum.slice(items, start_pos..end_pos//1)
  end

  defp do_join_horizontal(items, opts) do
    items = Enum.map(items, fn x -> {max(TextMetrics.height(x) - 1, 0), x} end)

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

  defp single_line_horizontal_content(items) do
    items
    |> Enum.reduce_while({[], 0}, fn item, {acc, total_width} ->
      case TextMetrics.metrics(item) do
        {width, 1} -> {:cont, {[item | acc], total_width + width}}
        _ -> {:halt, :multiline}
      end
    end)
    |> case do
      :multiline -> :multiline
      {reversed_items, width} -> {:ok, IO.iodata_to_binary(Enum.reverse(reversed_items)), width}
    end
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
