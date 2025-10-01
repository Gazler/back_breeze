defmodule BackBreeze do
  @moduledoc """
  The main module for BackBreeze, containing some helper functions.
  """

  @doc """
  Return the screen dimensions. Use the terminal dimensions if specified
  otherwise calculate using the `:io` module.
  """
  @spec screen_dimensions(struct() | nil) :: {non_neg_integer(), non_neg_integer()}
  def screen_dimensions(terminal \\ nil)
  def screen_dimensions(%Termite.Terminal{size: size}), do: {size.width, size.height}
  def screen_dimensions(nil), do: {screen_width(), screen_height()}

  @spec screen_width() :: non_neg_integer()
  defp screen_width() do
    {:ok, cols} = :io.columns()
    cols
  end

  @spec screen_height() :: non_neg_integer()
  defp screen_height() do
    {:ok, height} = :io.rows()
    height
  end
end
