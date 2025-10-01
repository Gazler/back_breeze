defmodule BackBreeze.Layout.Constraint do
  alias __MODULE__

  @type type :: :min | :max | :length | :percentage | :fill | :ratio
  @type ratio_t() :: %Constraint{
          type: :ratio,
          value: {non_neg_integer(), non_neg_integer()}
        }
  @type t ::
          %Constraint{
            type: :min | :max | :length | :percentage | :fill,
            value: non_neg_integer()
          }
          | ratio_t()

  defstruct [:type, :value]

  @types [:min, :max, :length, :percentage, :ratio, :fill]

  @spec new(type(), non_neg_integer() | {non_neg_integer(), non_neg_integer()}) :: t()
  def new(type, value)
      when (type in @types and (is_number(value) and value >= 0)) or
             (is_tuple(value) and tuple_size(value) == 2) do
    %Constraint{type: type, value: value}
  end

  @spec min(non_neg_integer()) :: t()
  def min(value) when is_number(value) and value >= 0 do
    new(:min, value)
  end

  @spec max(non_neg_integer()) :: t()
  def max(value) when is_number(value) and value >= 0 do
    new(:max, value)
  end

  @spec length(non_neg_integer()) :: t()
  def length(value) when is_number(value) and value >= 0 do
    new(:length, value)
  end

  @spec percentage(non_neg_integer()) :: t()
  def percentage(value) when is_number(value) and value >= 0 and value <= 100 do
    new(:percentage, value)
  end

  @spec ratio({non_neg_integer(), non_neg_integer()}) :: t()
  def ratio({num, den})
      when is_number(num) and num >= 0 and is_number(den) and den >= 0 do
    new(:ratio, {num, den})
  end

  @spec fill(non_neg_integer()) :: t()
  def fill(value) when is_number(value) and value >= 0 do
    new(:fill, value)
  end
end
