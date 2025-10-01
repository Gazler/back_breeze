defmodule Cassowary.Solver do
  alias __MODULE__
  alias Cassowary.{Constraint, Variable, Symbol, Row, Strength, Tag, Util}

  @type t() :: %Solver{
          constraints: map(),
          var_data: map(),
          var_for_symbol: map(),
          rows: map(),
          id_tick: pos_integer(),
          objective: Row.t(),
          artificial: nil | Row.t(),
          should_clear_changes: boolean(),
          changed: MapSet.t(Variable.t()),
          infeasible_rows: [Symbol.t()],
          public_changes: [{Variable.t(), number()}]
        }

  defstruct constraints: %{},
            var_data: %{},
            var_for_symbol: %{},
            rows: %{},
            id_tick: 1,
            objective: Row.new(0.0),
            artificial: nil,
            should_clear_changes: false,
            changed: MapSet.new(),
            infeasible_rows: [],
            public_changes: []

  @spec new() :: t()
  def new(), do: %Solver{}

  @spec add_constraint(t(), Constraint.t()) :: {:ok, t()} | {:error, atom()}
  def add_constraint(solver, %Constraint{} = constraint) do
    with false <- Map.has_key?(solver.constraints, constraint) do
      {solver, row, tag} = create_row(solver, constraint)
      subject = choose_subject(row, tag)

      res =
        if subject.kind == :invalid && all_dummies?(row) do
          if !Util.near_zero?(row.constant) do
            {:error, :unsatisfiable_constraint}
          else
            {:ok, tag.marker}
          end
        else
          {:ok, subject}
        end

      case res do
        {:ok, subject} ->
          res =
            if subject.kind == :invalid do
              case add_with_artificial_variable?(solver, row) do
                {:ok, solver, satisfiable} ->
                  if !satisfiable do
                    {:error, :unsatisfiable_constraint}
                  else
                    {:ok, solver}
                  end

                {:error, reason} ->
                  {:error, reason}
              end
            else
              row = Row.solve_for_symbol(row, subject)

              solver = substitute(solver, subject, row)

              solver =
                if subject.kind == :external && row.constant != 0.0 do
                  v = Map.fetch!(solver.var_for_symbol, subject)
                  variable_changed(solver, v)
                else
                  solver
                end

              solver =
                Map.update!(solver, :rows, fn rows ->
                  Map.put(rows, subject, row)
                end)

              {:ok, solver}
            end

          case res do
            {:ok, solver} ->
              solver
              |> Map.update!(:constraints, &Map.put(&1, constraint, tag))
              |> optimize(:objective)

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      true -> {:error, :duplicate_constraint}
    end
  end

  @spec fetch_changes(t()) :: t()
  def fetch_changes(%Solver{} = solver) do
    solver =
      if solver.should_clear_changes do
        solver
        |> Map.put(:changed, MapSet.new())
        |> Map.put(:should_clear_changes, false)
      else
        Map.put(solver, :should_clear_changes, true)
      end

    solver = Map.put(solver, :public_changes, [])

    public_changes =
      Enum.reduce(solver.changed, [], fn variable, acc ->
        case Map.fetch(solver.var_data, variable) do
          {:ok, {old_value, symbol, _}} ->
            new_value =
              case Map.fetch(solver.rows, symbol) do
                {:ok, row} -> row.constant
                :error -> 0.0
              end

            if old_value != new_value do
              [{variable, new_value} | acc]
            else
              solver
            end

          :error ->
            acc
        end
      end)

    Map.put(solver, :public_changes, public_changes)
  end

  def pretty_print(solver) do
    solver.constraints
    |> Map.keys()
    |> Enum.each(&IO.puts(Constraint.pretty_print(&1)))
  end

  @spec create_row(t(), Constraint.t()) :: {t(), Row.t(), Tag.t()}
  defp create_row(%__MODULE__{} = solver, constraint) do
    expr = constraint.expression
    row = Row.new(expr.constant)

    {solver, row} =
      Enum.reduce(expr.terms, {solver, row}, fn term, {solver, row} ->
        if !Cassowary.Util.near_zero?(term.coefficient) do
          {solver, symbol} = get_var_symbol(solver, term.variable)

          other_row = Map.get(solver.rows, symbol)

          row =
            if other_row do
              {r, _} = Row.insert_row(row, other_row, term.coefficient)
              r
            else
              Row.insert_symbol(row, symbol, term.coefficient)
            end

          {solver, row}
        else
          {solver, row}
        end
      end)

    {solver, row, tag} =
      case constraint.operator do
        :<= ->
          coeff = 1.0
          slack = Symbol.new(solver.id_tick, :slack)
          solver = Map.put(solver, :id_tick, solver.id_tick + 1)
          row = Row.insert_symbol(row, slack, coeff)

          if constraint.strength < Strength.required() do
            error = Symbol.new(solver.id_tick, :error)
            solver = Map.put(solver, :id_tick, solver.id_tick + 1)
            row = Row.insert_symbol(row, error, -coeff)

            solver =
              Map.update!(solver, :objective, fn objective ->
                Row.insert_symbol(objective, error, constraint.strength)
              end)

            {solver, row, %Tag{marker: slack, other: error}}
          else
            {solver, row, %Tag{marker: slack, other: Symbol.invalid()}}
          end

        :>= ->
          coeff = -1.0
          slack = Symbol.new(solver.id_tick, :slack)
          solver = Map.put(solver, :id_tick, solver.id_tick + 1)
          row = Row.insert_symbol(row, slack, coeff)

          if(constraint.strength < Strength.required()) do
            error = Symbol.new(solver.id_tick, :error)
            solver = Map.put(solver, :id_tick, solver.id_tick + 1)
            row = Row.insert_symbol(row, error, -coeff)

            solver =
              Map.update!(solver, :objective, fn objective ->
                Row.insert_symbol(objective, error, constraint.strength)
              end)

            {solver, row, %Tag{marker: slack, other: error}}
          else
            {solver, row, %Tag{marker: slack, other: Symbol.invalid()}}
          end

        :== ->
          if constraint.strength < Strength.required() do
            errplus = Symbol.new(solver.id_tick, :error)
            solver = Map.put(solver, :id_tick, solver.id_tick + 1)
            errminus = Symbol.new(solver.id_tick, :error)
            solver = Map.put(solver, :id_tick, solver.id_tick + 1)
            row = Row.insert_symbol(row, errplus, -1.0)
            row = Row.insert_symbol(row, errminus, 1.0)

            solver =
              Map.update!(solver, :objective, fn objective ->
                objective
                |> Row.insert_symbol(errplus, constraint.strength)
                |> Row.insert_symbol(errminus, constraint.strength)
              end)

            {solver, row, %Tag{marker: errplus, other: errminus}}
          else
            dummy = Symbol.new(solver.id_tick, :dummy)
            solver = Map.put(solver, :id_tick, solver.id_tick + 1)
            row = Row.insert_symbol(row, dummy, 1.0)
            {solver, row, %Tag{marker: dummy, other: Symbol.invalid()}}
          end
      end

    row =
      if row.constant < 0.0 do
        Row.reverse_sign(row)
      else
        row
      end

    {solver, row, tag}
  end

  @spec get_var_symbol(t(), Variable.t()) :: {t(), Symbol.t()}
  defp get_var_symbol(solver, variable) do
    case Map.fetch(solver.var_data, variable) do
      {:ok, {value, symbol, refcount}} ->
        solver =
          Map.update!(solver, :var_data, &Map.put(&1, variable, {value, symbol, refcount + 1}))

        {solver, symbol}

      :error ->
        symbol = Symbol.new(solver.id_tick, :external)

        solver =
          solver
          |> Map.put(:id_tick, solver.id_tick + 1)
          |> Map.update!(:var_data, &Map.put(&1, variable, {:nan, symbol, 1}))
          |> Map.update!(:var_for_symbol, &Map.put(&1, symbol, variable))

        {solver, symbol}
    end
  end

  @spec choose_subject(Row.t(), Tag.t()) :: Symbol.t()
  defp choose_subject(row, tag) do
    symbol =
      row.cells
      |> Map.keys()
      |> Enum.find(&(&1.kind == :external))

    if symbol do
      symbol
    else
      symbol =
        if tag.marker.kind in [:slack, :error] && Row.coefficient_for(row, tag.marker) < 0.0 do
          tag.marker
        end

      if symbol do
        symbol
      else
        symbol =
          if tag.other.kind in [:slack, :error] && Row.coefficient_for(row, tag.marker) < 0.0 do
            tag.other
          end

        if symbol do
          symbol
        else
          Symbol.invalid()
        end
      end
    end
  end

  @spec all_dummies?(Row.t()) :: boolean()
  defp all_dummies?(row) do
    row.cells
    |> Map.keys()
    |> Enum.all?(&(&1.kind == :dummy))
  end

  @spec add_with_artificial_variable?(t(), Row.t()) :: {:ok, t(), boolean()} | {:error, atom()}
  defp add_with_artificial_variable?(solver, row) do
    art = Symbol.new(solver.id_tick, :slack)

    solver =
      solver
      |> Map.put(:id_tick, solver.id_tick + 1)
      |> Map.update!(:rows, &Map.put(&1, art, row))
      |> Map.put(:artificial, row)

    case optimize(solver, :artificial) do
      {:ok, solver} ->
        success = Util.near_zero?(solver.artificial.constant)

        solver = Map.put(solver, :artificial, nil)

        res =
          Map.get_and_update(solver, :rows, fn rows ->
            Map.pop(rows, art)
          end)

        res =
          case res do
            {nil, solver} ->
              {:ok, solver, success}

            {row, solver} ->
              if row.cells == [] do
                {:return, solver, success}
              else
                entering = any_pivotable_symbol(row)

                if entering.kind == :invalid do
                  {:return, solver, false}
                else
                  row = Row.solve_for_symbols(row, art, entering)

                  solver = substitute(solver, entering, row)

                  Map.put(solver, :rows, Map.put(solver.rows, entering, row))
                  {:ok, solver, success}
                end
              end
          end

        case res do
          {:return, solver, success} ->
            {:ok, solver, success}

          {:ok, solver, success} ->
            solver =
              Map.update!(solver, :rows, fn rows ->
                rows
                |> Enum.map(fn {k, row} ->
                  {k, Row.remove(row, art)}
                end)
                |> Map.new()
              end)

            solver = Map.put(solver, :objective, Row.remove(solver.objective, art))

            {:ok, solver, success}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec optimize(t(), :objective | :artificial) :: {:ok, t()} | {:error, atom()}
  defp optimize(solver, objective_type) do
    objective = Map.get(solver, objective_type)

    case get_entering_symbol(objective) do
      %Symbol{kind: :invalid} ->
        {:ok, solver}

      entering ->
        case get_leaving_row(solver, entering) do
          {_solver, nil, nil} ->
            {:error, :objective_unbounded}

          {solver, leaving, row} ->
            row = Row.solve_for_symbols(row, leaving, entering)
            solver = substitute(solver, entering, row)

            solver =
              if entering.kind == :external && row.constant != 0.0 do
                variable = Map.fetch!(solver.var_for_symbol, entering)

                variable_changed(solver, variable)
              else
                solver
              end

            solver = Map.put(solver, :rows, Map.put(solver.rows, entering, row))

            optimize(solver, objective_type)
        end
    end
  end

  @spec get_entering_symbol(Row.t()) :: Symbol.t()
  defp get_entering_symbol(objective) do
    Enum.reduce_while(objective.cells, Symbol.invalid(), fn {symbol, value}, invalid ->
      if symbol.kind != :dummy and value < 0.0 do
        {:halt, symbol}
      else
        {:cont, invalid}
      end
    end)
  end

  @spec get_leaving_row(t(), Symbol.t()) :: {t(), Symbol.t() | nil, Row.t() | nil}
  def get_leaving_row(solver, entering) do
    {_, symbol} =
      Enum.reduce(solver.rows, {Float.max_finite(), nil}, fn {sym, row}, {best_ratio, best_sym} ->
        cond do
          sym.kind == :external ->
            {best_ratio, best_sym}

          (coef = Row.coefficient_for(row, entering)) < 0.0 ->
            ratio = -row.constant / coef
            if ratio < best_ratio, do: {ratio, sym}, else: {best_ratio, best_sym}

          true ->
            {best_ratio, best_sym}
        end
      end)

    if symbol do
      {row, solver} = Map.get_and_update!(solver, :rows, &Map.pop!(&1, symbol))
      {solver, symbol, row}
    else
      {solver, nil, nil}
    end
  end

  @spec substitute(t(), Symbol.t(), Row.t()) :: t()
  defp substitute(solver, symbol, row) do
    solver =
      Enum.reduce(solver.rows, solver, fn {other_symbol, other_row}, solver ->
        {new_row, constant_changed} = Row.substitute(other_row, symbol, row)

        solver = put_in(solver.rows[other_symbol], new_row)

        solver =
          if other_symbol.kind == :external && constant_changed do
            variable = Map.fetch!(solver.var_for_symbol, other_symbol)

            variable_changed(solver, variable)
          else
            solver
          end

        if other_symbol.kind != :external && new_row.constant < 0.0 do
          Map.put(
            solver,
            :infeasible_rows,
            List.insert_at(solver.infeasible_rows, -1, other_symbol)
          )
        else
          solver
        end
      end)

    {objective, _} = Row.substitute(solver.objective, symbol, row)
    solver = Map.put(solver, :objective, objective)

    if solver.artificial do
      {artificial, _} = Row.substitute(solver.artificial, symbol, row)
      Map.put(solver, :artificial, artificial)
    else
      solver
    end
  end

  @spec variable_changed(t(), Variable.t()) :: t()
  defp variable_changed(solver, variable) do
    solver =
      if solver.should_clear_changes do
        solver
        |> Map.put(:changed, MapSet.new())
        |> Map.put(:should_clear_changes, false)
      else
        solver
      end

    Map.update!(solver, :changed, &MapSet.put(&1, variable))
  end

  @spec any_pivotable_symbol(Row.t()) :: Symbol.t()
  defp any_pivotable_symbol(row) do
    row.cells
    |> Map.keys()
    |> Enum.find(Symbol.invalid(), fn symbol ->
      symbol.kind == :slack || symbol.kind == :error
    end)
  end
end
