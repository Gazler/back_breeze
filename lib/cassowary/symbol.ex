defmodule Cassowary.Symbol do
  @type kind() :: :invalid | :external | :slack | :error | :dummy
  @type t() :: %__MODULE__{id: pos_integer(), kind: kind()}

  @enforce_keys [:kind]
  defstruct [:kind, id: 0]

  @kinds ~w[invalid external slack error dummy]a

  def new(id, kind) when is_integer(id) and kind in @kinds do
    %__MODULE__{id: id, kind: kind}
  end

  def invalid do
    %__MODULE__{kind: :invalid}
  end
end
