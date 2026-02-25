defmodule BackBreeze do
  @moduledoc """
  The main module for BackBreeze, containing some helper functions.
  """

  @doc """
  Return the screen dimensions. Use the terminal dimensions if specified
  otherwise calculate using the `:io` module.
  """
  @default_screen_width 80
  @default_screen_height 24

  def screen_dimensions(%Termite.Terminal{size: size}), do: {size.width, size.height}
  def screen_dimensions(nil), do: {screen_width(), screen_height()}

  defp screen_width() do
    case :io.columns() do
      {:ok, cols} -> cols
      _ -> @default_screen_width
    end
  end

  defp screen_height() do
    case :io.rows() do
      {:ok, height} -> height
      _ -> @default_screen_height
    end
  end
end
