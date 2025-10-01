defmodule BackBreeze.Rect do
  alias __MODULE__
  alias BackBreeze.Layout.Margin

  @type t :: %Rect{
          x: non_neg_integer(),
          y: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  defstruct x: 0, y: 0, width: 0, height: 0

  @spec new(non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def new(x, y, width, height)
      when is_integer(x) and is_integer(y) and is_integer(width) and is_integer(height) do
    %Rect{width: width, height: height, x: x, y: y}
  end

  @spec fullscreen() :: t()
  def fullscreen do
    {width, height} = BackBreeze.screen_dimensions()

    new(0, 0, width, height)
  end

  @spec inner(t(), Margin.t()) :: t()
  def inner(%Rect{} = rect, %Margin{} = margin) do
    %{horizontal: horizontal, vertical: vertical} = margin

    rect
    |> Map.put(:x, rect.x + horizontal)
    |> Map.put(:y, rect.y + vertical)
    |> Map.put(:width, rect.width - horizontal * 2)
    |> Map.put(:height, rect.height - vertical * 2)
  end

  @spec left(t()) :: non_neg_integer()
  def left(%Rect{x: x}) do
    x
  end

  @spec right(t()) :: non_neg_integer()
  def right(%Rect{x: x, width: width}) do
    x + width
  end

  @spec top(t()) :: non_neg_integer()
  def top(%Rect{y: y}) do
    y
  end

  @spec bottom(t()) :: non_neg_integer()
  def bottom(%Rect{y: y, height: height}) do
    y + height
  end
end
