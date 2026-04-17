defmodule BackBreeze.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BackBreeze.RenderCache,
      BackBreeze.PreparedContentStore
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BackBreeze.Supervisor)
  end
end
