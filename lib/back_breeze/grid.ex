defmodule BackBreeze.Grid do
  @moduledoc """
  Struct for creating a grid to be used by a Box.

  BackBreeze.Box.new(
    style: %{border: :line},
    display: %BackBreeze.Grid{columns: 1},
    children: [BackBreeze.Box.new(content: "Hello"), BackBreeze.Box.new(content: "World")]
  )
  """

  @doc """
  Create a grid with the specified number of columns.
  """
  defstruct [:columns, :rows]

  @auto_sizes [:screen, :auto]

  @doc false
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
    row_count = grid.rows || length(rows)

    item_width = div(width - width_offset, grid.columns)
    item_height = div(height - height_offset, row_count)

    %{width: item_width, height: item_height}
  end

  @doc false
  def render(items, grid, style, opts) do
    %{content: content, width: width, height: height} =
      render_with_dimensions(items, grid, style, opts)

    {content, width, height}
  end

  @doc false
  def render_with_dimensions(items, grid, style, opts) do
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
    row_count = grid.rows || length(rows)

    total_height =
      case style.height do
        h when is_integer(h) and h > 0 -> h
        _ -> screen_height - height_offset
      end

    base_height = div(total_height, row_count)
    remainder = rem(total_height, row_count)

    rows_with_results =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {cols, row_index} ->
        row_height = base_height + if(row_index < remainder, do: 1, else: 0)

        Enum.map(cols, fn %{style: %{border: border}} = item ->
          width = item_width - if(border.left, do: 1, else: 0) - if border.right, do: 1, else: 0
          height = row_height - if(border.top, do: 1, else: 0) - if border.bottom, do: 1, else: 0

          style = %{item.style | width: width, height: height, overflow: :hidden}
          BackBreeze.Box.render_with_dimensions(%{item | style: style})
        end)
      end)

    per_item_dimensions =
      Enum.flat_map(rows_with_results, fn row -> Enum.map(row, & &1.dimensions) end)

    rows_with_results
    |> Enum.map(&BackBreeze.Joiner.new/1)
    |> Enum.map(&BackBreeze.Joiner.join_horizontal/1)
    |> BackBreeze.Joiner.merge()
    |> BackBreeze.Joiner.join_vertical()
    |> Map.put(:per_item_dimensions, per_item_dimensions)
  end
end
