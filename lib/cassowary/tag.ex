defmodule Cassowary.Tag do
  alias Cassowary.Symbol

  @type t() :: %__MODULE__{marker: Symbol.t(), other: Symbol.t()}

  @enforce_keys [:marker, :other]
  defstruct [:marker, :other]
end
