defmodule BackBreeze.Joiner do
  @moduledoc false

  defstruct boxes: [], dimensions: [], content: [], width: 0, height: 0

  def new(items) do
    dimensions = Enum.flat_map(items, & &1.dimensions)
    boxes = Enum.map(items, & &1.box)
    %__MODULE__{boxes: boxes, dimensions: dimensions}
  end

  def join_horizontal(joiner) do
    {content, width, height} =
      joiner.boxes
      |> Enum.map(& &1.content)
      |> BackBreeze.Box.join_horizontal()

    %{
      joiner
      | boxes: [%BackBreeze.Box{content: content}],
        content: content,
        width: width,
        height: height
    }
  end

  def join_vertical(joiner) do
    {content, width, height} =
      joiner.boxes
      |> Enum.map(& &1.content)
      |> BackBreeze.Box.join_vertical()

    %{
      joiner
      | boxes: [%BackBreeze.Box{content: content}],
        content: content,
        width: width,
        height: height
    }
  end

  def merge(joiners) do
    {boxes, dimensions} =
      Enum.reduce(joiners, {[], []}, fn joiner, {boxes, dimensions} ->
        {boxes ++ joiner.boxes, dimensions ++ joiner.dimensions}
      end)

    %__MODULE__{boxes: boxes, dimensions: dimensions}
  end
end
