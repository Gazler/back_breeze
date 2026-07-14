defmodule BackBreeze.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link(BackBreeze.Cache.children(),
      strategy: :one_for_one,
      name: BackBreeze.Supervisor
    )
  end
end
