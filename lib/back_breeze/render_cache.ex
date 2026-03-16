defmodule BackBreeze.RenderCache do
  @moduledoc false

  use GenServer

  @table :back_breeze_render_cache
  @max_entries 4_096
  @generation_key {__MODULE__, :generations}

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
    put_generations(0, -1)

    {:ok, %{current_generation: 0, previous_generation: -1}}
  end

  def with_frame(fun) when is_function(fun, 0) do
    ensure_started()
    depth = Process.get({__MODULE__, :frame_depth}, 0)

    if depth == 0 do
      advance_generation()
    end

    Process.put({__MODULE__, :frame_depth}, depth + 1)

    try do
      fun.()
    after
      if depth == 0 do
        Process.delete({__MODULE__, :frame_depth})
      else
        Process.put({__MODULE__, :frame_depth}, depth)
      end
    end
  end

  def fetch(key, fun) when is_function(fun, 0) do
    if disabled?() do
      fun.()
    else
      do_fetch(key, fun)
    end
  end

  defp do_fetch(key, fun) do
    ensure_started()
    {current_generation, previous_generation} = generations()

    case :ets.lookup(@table, {current_generation, key}) do
      [{{^current_generation, ^key}, value}] ->
        value

      [] ->
        case :ets.lookup(@table, {previous_generation, key}) do
          [{{^previous_generation, ^key}, value}] ->
            maybe_reset_cache()
            true = :ets.insert(@table, {{current_generation, key}, value})
            value

          [] ->
            value = fun.()
            maybe_reset_cache()
            true = :ets.insert(@table, {{current_generation, key}, value})
            value
        end
    end
  end

  defp disabled? do
    System.get_env("BACK_BREEZE_DISABLE_RENDER_CACHE") in ["1", "true", "TRUE"]
  end

  def clear do
    ensure_started()
    :ets.delete_all_objects(@table)
    put_generations(0, -1)
  end

  def size do
    ensure_started()
    :ets.info(@table, :size)
  end

  def advance_generation do
    ensure_started()
    GenServer.call(__MODULE__, :advance_generation)
  end

  @impl true
  def handle_call(:advance_generation, _from, %{current_generation: current, previous_generation: previous} = state) do
    delete_generation(previous)
    next_current = current + 1
    put_generations(next_current, current)

    {:reply, :ok, %{state | current_generation: next_current, previous_generation: current}}
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

  defp generations do
    :persistent_term.get(@generation_key, {0, -1})
  end

  defp put_generations(current_generation, previous_generation) do
    :persistent_term.put(@generation_key, {current_generation, previous_generation})
  end

  defp delete_generation(generation) when generation < 0, do: :ok

  defp delete_generation(generation) do
    true =
      :ets.match_delete(@table, {{generation, :_}, :_})

    :ok
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

  defp maybe_reset_cache do
    if size() >= @max_entries do
      clear()
    end
  end
end
