defmodule BackBreeze do
  def screen_dimensions(%Termite.Terminal{size: size}), do: {size.width, size.height}
  def screen_dimensions(nil), do: {screen_width(), screen_height()}

  defp screen_width() do
    {:ok, cols} = :io.columns()
    cols
  end

  defp screen_height() do
    {:ok, height} = :io.rows()
    height
  end
end
