defmodule BackBreeze.Layout.Spacing do
  @type type :: :space | :overlap
  @type t :: %__MODULE__{type: type(), value: non_neg_integer()}

  defstruct type: :space, value: 0

  alias __MODULE__

  @spec new(type(), non_neg_integer()) :: t()
  def new(type, value) when is_integer(value) and value >= 0 do
    %Spacing{type: type, value: value}
  end
end
