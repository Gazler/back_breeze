defmodule Cassowary.Constraint do
  alias __MODULE__
  alias Cassowary.{Expression, Strength, Variable}

  @type operators() :: :== | :>= | :<=
  @type t() :: %__MODULE__{
          expression: Expression.t(),
          operator: operators(),
          strength: float()
        }

  import Strength, only: [is_strength: 1]

  @enforce_keys [:expression, :operator, :strength]
  defstruct [:expression, :operator, :strength]

  @eq :==
  @ge :>=
  @le :<=

  @operators [@eq, @ge, @le]

  @spec new(%Expression{}, operators(), float()) :: t()
  def new(%Expression{} = expression, operator, strength \\ Strength.required())
      when operator in @operators and is_strength(strength) do
    %__MODULE__{expression: expression, operator: operator, strength: strength}
  end

  @spec eq(%Expression{}, %Expression{} | %Variable{} | number(), float()) :: t()
  def eq(lhs, rhs, strength \\ Strength.required()) do
    lhs
    |> Expression.subtract(rhs)
    |> new(@eq, strength)
  end

  @spec le(%Expression{}, %Expression{} | %Variable{} | number(), float()) :: t()
  def le(lhs, rhs, strength \\ Strength.required()) do
    lhs
    |> Expression.subtract(rhs)
    |> new(@le, strength)
  end

  @spec ge(%Expression{}, %Expression{} | %Variable{} | number(), float()) :: t()
  def ge(lhs, rhs, strength \\ Strength.required()) do
    lhs
    |> Expression.subtract(rhs)
    |> new(@ge, strength)
  end

  def pretty_print(%Constraint{} = constraint) do
    constraint.expression
    |> Expression.pretty_print()
    |> List.insert_at(-2, constraint.operator)
    |> Enum.join(" ")
  end
end
