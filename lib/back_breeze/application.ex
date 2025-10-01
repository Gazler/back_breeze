defmodule BackBreeze.Application do
  @doc false

  use Application

  def start(_type, _args) do
    children = [Cassowary.Variable.ID]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
