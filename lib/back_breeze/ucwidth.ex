defmodule BackBreeze.Ucwidth do
  @moduledoc """
  Module for dealing with variable width glyphs.
  """

  @doc """
  Return the width of a character when considering glyphs that are more than 1 character wide.

  ```elixir
  iex> BackBreeze.Ucwidth.width("H")
  1

  iex> BackBreeze.Ucwidth.width("🍏")
  2
  ```
  """
  def width(<<char>>) when char < 128, do: 1

  def width(<<codepoint::utf8>>) do
    width_codepoint(codepoint)
  end

  def width(char) do
    case String.next_codepoint(char) do
      {<<codepoint::utf8>>, _rest} -> width_codepoint(codepoint)
      nil -> 0
    end
  end

  def width_codepoint(codepoint) when is_integer(codepoint) and codepoint < 128, do: 1
  def width_codepoint(codepoint) when is_integer(codepoint) and codepoint in 0x2500..0x259F, do: 1
  def width_codepoint(codepoint) when is_integer(codepoint) and codepoint in 0x25A0..0x25FF, do: 1

  def width_codepoint(codepoint) when is_integer(codepoint) do
    case Process.get({__MODULE__, codepoint}) do
      nil ->
        width = :prim_tty.npwcwidth(codepoint)

        Process.put({__MODULE__, codepoint}, width)
        width

      width ->
        width
    end
  end
end
