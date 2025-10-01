defmodule Cassowary.Expression do
  alias __MODULE__
  alias Cassowary.{Term, Variable}

  @type t() :: %Expression{terms: [Term.t()], constant: float()}

  defstruct terms: [], constant: 0.0

  @spec new(Term.t() | [Term.t()], float()) :: t()
  def new(term, constant \\ 0.0)

  def new(%Term{} = term, constant) do
    new([term], constant)
  end

  def new(terms, constant) when is_list(terms) do
    %Expression{terms: terms, constant: constant}
  end

  @spec from(t() | Variable.t() | number()) :: t()
  def from(%Expression{} = expr), do: expr
  def from(%Variable{} = var), do: new(Term.new(var, 1.0))
  def from(number) when is_number(number), do: new([], number)

  @spec add(t() | Variable.t() | number(), t() | Variable.t() | number()) :: t()
  def add(a, b) do
    a = from(a)
    b = from(b)

    new(a.terms ++ b.terms, a.constant + b.constant)
  end

  @spec subtract(t() | Variable.t() | number(), t() | Variable.t() | number()) :: t()
  def subtract(a, b) do
    a = from(a)
    b = from(b)

    negated_terms =
      Enum.map(b.terms, fn %Term{variable: v, coefficient: c} ->
        Term.new(v, -c)
      end)

    new(a.terms ++ negated_terms, a.constant - b.constant)
  end

  def multiply(%Expression{terms: terms, constant: constant}, factor)
      when is_number(factor) do
    new_terms =
      Enum.map(terms, fn %Term{variable: v, coefficient: c} ->
        %Term{variable: v, coefficient: c * factor}
      end)

    new(new_terms, constant * factor)
  end

  def divide(%Expression{} = expr, factor) do
    multiply(expr, 1 / factor)
  end

  def pretty_print(%Expression{} = expression) do
    expression.terms
    |> Enum.map(&Term.pretty_print/1)
    |> Enum.intersperse(" + ")
    |> List.insert_at(-1, expression.constant)
  end
end
