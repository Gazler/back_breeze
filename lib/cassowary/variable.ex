defmodule Cassowary.Variable do
  @type t() :: %__MODULE__{id: pos_integer()}

  @enforce_keys [:id]
  defstruct [:id]

  @spec new(integer()) :: t()
  def new(id \\ __MODULE__.ID.id()) do
    %__MODULE__{id: id}
  end
end

defmodule Cassowary.Variable.ID do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end

  def id do
    Agent.get_and_update(__MODULE__, &{&1, &1 + 1})
  end
end
