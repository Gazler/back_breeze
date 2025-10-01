defmodule BackBreeze.Layout.Margin do
  @type t :: %__MODULE__{horizontal: non_neg_integer(), vertical: non_neg_integer()}

  defstruct horizontal: 0, vertical: 0

  alias __MODULE__

  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(horizontal, vertical) do
    %Margin{horizontal: horizontal, vertical: vertical}
  end
end
