defmodule Cassowary.Term do
  alias __MODULE__
  alias Cassowary.Variable

  @type t() :: %Term{variable: Variable.t(), coefficient: float()}

  @enforce_keys [:variable, :coefficient]
  defstruct [:variable, :coefficient]

  alias Cassowary.Variable

  @spec new(Variable.t(), float()) :: t()
  def new(%Variable{} = variable, coefficient \\ 1.0) do
    %Term{variable: variable, coefficient: coefficient}
  end

  @spec negate(t()) :: t()
  def negate(%Term{variable: v, coefficient: c}) do
    %Term{variable: v, coefficient: -c}
  end

  def pretty_print(%Term{variable: variable, coefficient: coefficient}) do
    "(#{coefficient}) * v#{variable.id}"
  end
end
