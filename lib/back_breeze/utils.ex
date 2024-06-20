defmodule BackBreeze.Utils do
  def string_length(str) do
    str
    |> String.graphemes()
    |> Enum.reduce({false, 0}, fn char, {in_seq, len} ->
      cond do
        char == "\e" -> {true, len}
        in_seq && is_terminator?(char) -> {false, len}
        in_seq == true -> {true, len}
        true -> {false, len + 1}
      end
    end)
    |> elem(1)
  end

  def strip_escape_chars(str) do
    str
    |> String.graphemes()
    |> Enum.reduce({false, ""}, fn char, {in_seq, acc} ->
      cond do
        char == "\e" -> {true, acc}
        in_seq && is_terminator?(char) -> {false, acc}
        in_seq == true -> {true, acc}
        true -> {false, acc <> char}
      end
    end)
    |> elem(1)
  end

  defp is_terminator?("m"), do: true
  defp is_terminator?(_), do: false
end
