defmodule Cassowary.Row do
  alias Cassowary.{Symbol, Util}

  @type t() :: %__MODULE__{constant: float(), cells: map()}

  @enforce_keys :constant
  defstruct [:constant, cells: %{}]

  def new(constant) when is_float(constant) do
    %__MODULE__{constant: constant}
  end

  @spec insert_row(t(), t(), float()) :: {t(), boolean()}
  def insert_row(%__MODULE__{} = row, %__MODULE__{} = other, coefficient) do
    constant_diff = other.constant * coefficient

    row = Map.put(row, :constant, row.constant + constant_diff)

    row =
      Enum.reduce(other.cells, row, fn {s, v}, r ->
        insert_symbol(r, s, v * coefficient)
      end)

    {row, constant_diff != 0.0}
  end

  @spec insert_symbol(t(), Cassowary.Symbol.t(), float()) :: t()
  def insert_symbol(row, symbol, coefficient) do
    {_cell, cells} =
      Map.get_and_update(row.cells, symbol, fn
        nil ->
          if Util.near_zero?(coefficient) do
            :pop
          else
            {coefficient, coefficient}
          end

        coeff ->
          coeff = coeff + coefficient

          if Util.near_zero?(coeff) do
            :pop
          else
            {coeff, coeff}
          end
      end)

    Map.put(row, :cells, cells)
  end

  @spec reverse_sign(t()) :: t()
  def reverse_sign(row) do
    row
    |> Map.put(:constant, -row.constant)
    |> Map.update!(:cells, fn cells ->
      Enum.map(cells, fn {symbol, coeff} ->
        {symbol, -coeff}
      end)
      |> Map.new()
    end)
  end

  @spec coefficient_for(t(), Symbol.t()) :: float()
  def coefficient_for(row, symbol) do
    Map.get(row.cells, symbol, 0.0)
  end

  @spec substitute(t(), Symbol.t(), t) :: {t(), boolean()}
  def substitute(row, symbol, other_row) do
    {coeff, cells} = Map.pop(row.cells, symbol)
    row = Map.put(row, :cells, cells)

    if coeff do
      insert_row(row, other_row, coeff)
    else
      {row, false}
    end
  end

  @spec solve_for_symbol(t(), Symbol.t()) :: t()
  def solve_for_symbol(row, symbol) do
    {old_coeff, row} =
      Map.get_and_update!(row, :cells, fn cells ->
        Map.pop!(cells, symbol)
      end)

    factor = -1.0 / old_coeff

    row = Map.put(row, :constant, row.constant * factor)

    Map.update!(row, :cells, &Map.new(&1, fn {sym, coeff} -> {sym, coeff * factor} end))
  end

  @spec solve_for_symbols(t(), Symbol.t(), Symbol.t()) :: t()
  def solve_for_symbols(row, lhs, rhs) do
    row = insert_symbol(row, lhs, -1.0)
    solve_for_symbol(row, rhs)
  end

  @spec remove(t(), Symbol.t()) :: t()
  def remove(row, symbol) do
    Map.update!(row, :cells, fn cells ->
      Map.delete(cells, symbol)
    end)
  end

  def pretty_row(%Cassowary.Row{constant: const, cells: cells}) do
    cell_str =
      cells
      |> Enum.map(fn {s, c} -> "#{s.kind}-#{s.id}: #{c}" end)
      |> Enum.join(", ")

    IO.puts("Row(constant=#{const}, cells=[#{cell_str}])")
  end
end
