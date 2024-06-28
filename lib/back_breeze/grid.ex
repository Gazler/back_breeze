defmodule BackBreeze.Grid do
  defstruct [:columns, :rows]

  @auto_sizes [:screen, :auto]

  def precompute(items, grid, style, opts) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    width =
      case style.width do
        width when width in @auto_sizes -> screen_width
        other -> other
      end

    width_offset = if(style.border.left, do: 1, else: 0) + if style.border.right, do: 1, else: 0

    height =
      case style.height do
        height when height in @auto_sizes -> screen_height
        other -> other
      end

    height_offset = if(style.border.top, do: 1, else: 0) + if style.border.bottom, do: 1, else: 0

    rows = Enum.chunk_every(items, grid.columns)

    item_width = div(width - width_offset, grid.columns)
    item_height = div(height - height_offset, length(rows))

    %{width: item_width, height: item_height}
  end

  def render(items, grid, style, opts) do
    {screen_width, screen_height} = BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

    width_offset = if(style.border.left, do: 1, else: 0) + if style.border.right, do: 1, else: 0

    # Although this is similar to the calculation in precompute, dividing into columns happens
    # only if the width is not explicitly specified, compared to always dividing in the
    # precompute function
    item_width =
      case style.width do
        width when width in @auto_sizes -> div(screen_width - width_offset, grid.columns)
        other -> other
      end

    height_offset = if(style.border.top, do: 1, else: 0) + if style.border.bottom, do: 1, else: 0

    rows = Enum.chunk_every(items, grid.columns)

    item_height = div(screen_height - height_offset, length(rows))

    Enum.map(rows, fn cols ->
      Enum.map(cols, fn %{style: %{border: border}} = item ->
        width = item_width - if(border.left, do: 1, else: 0) - if border.right, do: 1, else: 0
        height = item_height - if(border.top, do: 1, else: 0) - if border.bottom, do: 1, else: 0
        style = %{item.style | width: width, height: height}
        BackBreeze.Box.render(%{item | style: style})
      end)
      |> Enum.map(& &1.content)
      |> BackBreeze.Box.join_horizontal()
      |> elem(0)
    end)
    |> BackBreeze.Box.join_vertical()
  end
end
