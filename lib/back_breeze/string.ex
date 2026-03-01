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
    break = Keyword.get(opts, :break, :word)

    {str, _, word, line, _} =
      str
      |> String.graphemes()
      |> Enum.reduce({"", 0, "", "", false}, fn char,
                                                {acc, cur_width, cur_word, cur_line, in_ansi} ->
        char_width = Ucwidth.width(char)
        next_width = cur_width + char_width

        cond do
          char == "\e" ->
            {acc, cur_width, cur_word <> char, cur_line, true}

          in_ansi && char == "m" ->
            {acc, cur_width, cur_word <> char, cur_line, false}

          in_ansi ->
            {acc, cur_width, cur_word <> char, cur_line, true}

          char == "\n" && cur_line == "" ->
            {acc <> cur_word <> "\n", 0, "", "", false}

          char == "\n" ->
            {acc <> cur_line <> cur_word <> "\n", 0, "", "", false}

          break == :word && char in @whitespace && cur_width == width ->
            {acc <> cur_line <> cur_word <> "\n", 0, "", "", false}

          break == :word && char in @whitespace ->
            {acc, next_width, "", cur_line <> cur_word <> char, false}

          string_length(cur_word) >= width ->
            {acc <> cur_word <> "\n", char_width, char, "", false}

          break == :char && next_width > width ->
            {acc <> cur_line <> cur_word <> char <> "\n", 0, "", "", false}

          break == :word && next_width > width ->
            word = cur_word <> char
            {acc <> cur_line <> "\n", string_length(word), word, "", false}

          true ->
            {acc, next_width, cur_word <> char, cur_line, false}
        end
      end)

    str <> line <> word
  end
end
