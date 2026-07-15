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
    cache_key = {__MODULE__, codepoint}

    case Process.get(cache_key) do
      nil ->
        width = codepoint_width(codepoint)

        Process.put(cache_key, width)
        width

      width ->
        width
    end
  end

  defp codepoint_width(codepoint) do
    # Popcorn bundles :prim_tty, but AtomVM cannot execute its on_load opcode.
    # Unlike Code.ensure_loaded?/1, this only inspects loaded modules, allowing
    # AtomVM to fall back while native OTP retains its NIF-backed implementation.
    if function_exported?(:prim_tty, :npwcwidth, 1) do
      :prim_tty.npwcwidth(codepoint)
    else
      unicode_width(codepoint)
    end
  end

  defp unicode_width(codepoint) do
    case :unicode_util.lookup(codepoint) do
      %{category: {:other, :control}} -> 0
      %{category: {:other, :format}} when codepoint != 0x00AD -> 0
      %{category: {:mark, :non_spacing}} -> 0
      %{category: {:mark, :enclosing}} -> 0
      _properties -> if :unicode_util.is_wide(codepoint), do: 2, else: 1
    end
  end
end
