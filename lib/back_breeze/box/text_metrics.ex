defmodule BackBreeze.Box.TextMetrics do
  @moduledoc false

  alias BackBreeze.Ucwidth

  def width(content) when is_binary(content), do: metrics(content) |> elem(0)
  def width(_content), do: 0

  def height(content) when is_binary(content), do: metrics(content) |> elem(1)
  def height(_content), do: 0

  def metrics(content) when is_binary(content) do
    {max_width, current_width, line_count, _in_seq} = do_metrics(content, 0, 0, 1, false)
    {max(max_width, current_width), line_count}
  end

  defp do_metrics(<<>>, max_width, current_width, line_count, in_seq) do
    {max_width, current_width, line_count, in_seq}
  end

  defp do_metrics(<<"\n", rest::binary>>, max_width, current_width, line_count, in_seq) do
    do_metrics(rest, max(max_width, current_width), 0, line_count + 1, in_seq)
  end

  defp do_metrics(<<"\e", rest::binary>>, max_width, current_width, line_count, _in_seq) do
    do_metrics(rest, max_width, current_width, line_count, true)
  end

  defp do_metrics(<<"m", rest::binary>>, max_width, current_width, line_count, true) do
    do_metrics(rest, max_width, current_width, line_count, false)
  end

  defp do_metrics(<<_char, rest::binary>>, max_width, current_width, line_count, true) do
    do_metrics(rest, max_width, current_width, line_count, true)
  end

  defp do_metrics(<<char, rest::binary>>, max_width, current_width, line_count, false)
       when char < 128 do
    do_metrics(rest, max_width, current_width + 1, line_count, false)
  end

  defp do_metrics(
         <<codepoint::utf8, rest::binary>>,
         max_width,
         current_width,
         line_count,
         false
       ) do
    do_metrics(
      rest,
      max_width,
      current_width + Ucwidth.width_codepoint(codepoint),
      line_count,
      false
    )
  end
end
