defmodule BackBreeze.Layout.Element do
  alias __MODULE__
  alias BackBreeze.Layout.Constants
  alias Cassowary.{Variable, Expression, Strength, Constraint}

  @type t() :: %Element{start: Variable.t(), end: Variable.t()}

  defstruct [:start, :end]

  def new(%Variable{} = start_var, %Variable{} = end_var) do
    %Element{start: start_var, end: end_var}
  end

  @spec size(t()) :: Expression.t()
  def size(%Element{} = element) do
    Expression.subtract(element.end, element.start)
  end

  @spec has_size(t(), float() | t() | Expression.t(), Strength.t()) :: Constraint.t()
  def has_size(%Element{} = element, %Element{} = size, strength) do
    expr = size(size)

    element
    |> size()
    |> Constraint.eq(expr, strength)
  end

  def has_size(%Element{} = element, size, strength) do
    element
    |> size()
    |> Constraint.eq(size, strength)
  end

  def has_min_size(%Element{} = element, size, strength) when is_number(size) do
    element
    |> size()
    |> Constraint.ge(size * Constants.float_precision_multiplier(), strength)
  end

  def has_double_size(%Element{} = element, %Element{} = size, strength) do
    element
    |> size()
    |> Constraint.eq(size |> size() |> Expression.multiply(2), strength)
  end

  def has_max_size(%Element{} = element, size, strength) when is_integer(size) do
    element
    |> size()
    |> Constraint.le(size * Constants.float_precision_multiplier(), strength)
  end

  @spec has_int_size(t(), non_neg_integer(), Strength.t()) :: Constraint.t()
  def has_int_size(%Element{} = element, size, strength) when is_integer(size) do
    element
    |> size()
    |> Constraint.eq(size * Constants.float_precision_multiplier(), strength)
  end

  def is_empty(%Element{} = element) do
    element
    |> size()
    |> Constraint.eq(0.0, Strength.required() - Strength.weak())
  end
end
