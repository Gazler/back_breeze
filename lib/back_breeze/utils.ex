defmodule BackBreeze.Utils do
  @moduledoc """
  This module contains functions for dealing with strings containing
  escape codes.
  """
  alias BackBreeze.Ucwidth

  @doc """
  Return the string length without escape sequences, factoring in glyph width.

  ```elixir
  iex> BackBreeze.Utils.string_length("\e1;38;5;3m123🍏")
  5
  ```
  """
  def string_length(str) do
    do_string_length(str, false, 0)
  end

  @doc """
  Strip escape characters from a string.

  ```elixir
  iex> BackBreeze.Utils.strip_escape_chars("\e1;38;5;3m123🍏")
  "123🍏"
  ```
  """
  def strip_escape_chars(str) do
    str
    |> do_strip_escape_chars(false, [])
    |> IO.iodata_to_binary()
  end

  defp do_string_length(<<>>, _in_seq, len), do: len

  defp do_string_length(<<"\e", rest::binary>>, _in_seq, len),
    do: do_string_length(rest, true, len)

  defp do_string_length(<<"m", rest::binary>>, true, len), do: do_string_length(rest, false, len)
  defp do_string_length(<<_char, rest::binary>>, true, len), do: do_string_length(rest, true, len)

  defp do_string_length(<<char, rest::binary>>, false, len) when char < 128,
    do: do_string_length(rest, false, len + 1)

  defp do_string_length(<<codepoint::utf8, rest::binary>>, false, len) do
    do_string_length(rest, false, len + Ucwidth.width_codepoint(codepoint))
  end

  defp do_strip_escape_chars(<<>>, _in_seq, acc), do: Enum.reverse(acc)

  defp do_strip_escape_chars(<<"\e", rest::binary>>, _in_seq, acc),
    do: do_strip_escape_chars(rest, true, acc)

  defp do_strip_escape_chars(<<"m", rest::binary>>, true, acc),
    do: do_strip_escape_chars(rest, false, acc)

  defp do_strip_escape_chars(<<_char, rest::binary>>, true, acc),
    do: do_strip_escape_chars(rest, true, acc)

  defp do_strip_escape_chars(<<char, rest::binary>>, false, acc) when char < 128 do
    do_strip_escape_chars(rest, false, [char | acc])
  end

  defp do_strip_escape_chars(<<codepoint::utf8, rest::binary>>, false, acc) do
    do_strip_escape_chars(rest, false, [<<codepoint::utf8>> | acc])
  end
end
