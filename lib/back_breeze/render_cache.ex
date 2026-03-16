defmodule BackBreeze.RenderCache do
  @moduledoc false

  use GenServer

  @table :back_breeze_render_cache
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [[]]}
    }
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    ensure_table()

    {:ok, %{}}
  end

  def fetch(key, fun) when is_function(fun, 0) do
    ensure_started()

    case :ets.lookup(@table, key) do
      [{^key, value}] ->
        value

      [] ->
        value = fun.()
        true = :ets.insert(@table, {key, value})
        value
    end
  end

  def clear do
    ensure_started()
    :ets.delete_all_objects(@table)
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          ArgumentError ->
            @table
        end

      tid ->
        tid
    end
  end
end
