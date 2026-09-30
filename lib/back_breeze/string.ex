defmodule BackBreeze.String do
  @moduledoc false

  alias BackBreeze.Ucwidth
  import BackBreeze.Utils, only: [string_length: 1]

  def truncate(str, width) do
    {result, _} =
      str
      |> String.graphemes()
      |> Enum.reduce_while({"", 0}, fn char, {acc, cur_width} ->
        char_width = Ucwidth.width(char)
        next_width = cur_width + char_width

        if next_width > width do
          {:halt, {acc, cur_width}}
        else
          {:cont, {acc <> char, next_width}}
        end
      end)

    result
  end

  @whitespace [" "]
  def reflow(str, width, opts \\ []) do
    if width > 0 and Regex.match?(~r/\A[\x20-\x7e\n]*\z/, str) and
         Enum.all?(:binary.split(str, "\n", [:global]), &(byte_size(&1) <= width)) do
      str
    else
      do_reflow(str, width, opts)
    end
  end

  defp do_reflow(str, width, opts) do
    break = Keyword.get(opts, :break, :word)

    {str, _, word, line, _, _} =
      str
      |> String.graphemes()
      |> Enum.reduce({"", 0, "", "", false, 0}, fn char, {acc, cur_width, cur_word, cur_line, in_ansi, word_width} ->
        char_width = Ucwidth.width(char)
        next_width = cur_width + char_width

        cond do
          char == "\e" ->
            {acc, cur_width, cur_word <> char, cur_line, true, word_width}

          in_ansi && char == "m" ->
            {acc, cur_width, cur_word <> char, cur_line, false, word_width}

          in_ansi ->
            {acc, cur_width, cur_word <> char, cur_line, true, word_width}

          char == "\n" && cur_line == "" ->
            {acc <> cur_word <> "\n", 0, "", "", false, 0}

          char == "\n" ->
            {acc <> cur_line <> cur_word <> "\n", 0, "", "", false, 0}

          break == :word && char in @whitespace && cur_width == width ->
            {acc <> cur_line <> cur_word <> "\n", 0, "", "", false, 0}

          break == :word && char in @whitespace ->
            {acc, next_width, "", cur_line <> cur_word <> char, false, 0}

          word_width >= width ->
            {acc <> cur_word <> "\n", char_width, char, "", false, string_length(char)}

          break == :char && next_width > width ->
            {acc <> cur_line <> cur_word <> char <> "\n", 0, "", "", false, 0}

          break == :word && next_width > width ->
            word = cur_word <> char
            next_word_width = word_width + string_length(char)
            {acc <> cur_line <> "\n", next_word_width, word, "", false, next_word_width}

          true ->
            {acc, next_width, cur_word <> char, cur_line, false, word_width + string_length(char)}
        end
      end)

    str <> line <> word
  end
end
