defmodule BackBreeze.RenderCache do
  @moduledoc false

  use GenServer

  @table :back_breeze_render_cache
  @max_entries 4_096
  @max_memory_words 8_000_000
  @generation_key {__MODULE__, :generation_counter}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    ensure_table()
    generation_ref()
    {:ok, %{}}
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

  def fetch_stable(key, fun) when is_function(fun, 0) do
    if disabled?() do
      fun.()
    else
      do_fetch_stable(key, fun)
    end
  end

  def clear do
    ensure_started()
    :ets.delete_all_objects(@table)
    :counters.put(generation_ref(), 1, 0)
  end

  def size do
    ensure_started()
    :ets.info(@table, :size)
  end

  def advance_generation do
    ensure_started()
    :counters.add(generation_ref(), 1, 1)
    :ok
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

  defp do_fetch_stable(key, fun) do
    ensure_started()
    stable_key = {:stable, key}

    case :ets.lookup(@table, stable_key) do
      [{^stable_key, value}] ->
        value

      [] ->
        value = fun.()
        maybe_reset_cache()
        true = :ets.insert(@table, {stable_key, value})
        value
    end
  end

  defp disabled? do
    System.get_env("BACK_BREEZE_DISABLE_RENDER_CACHE") in ["1", "true", "TRUE"]
  end

  defp ensure_started do
    if :ets.whereis(@table) == :undefined or :persistent_term.get(@generation_key, nil) == nil do
      Application.ensure_all_started(:back_breeze)
    end

    :ok
  end

  defp generations do
    current_generation = :counters.get(generation_ref(), 1)
    {current_generation, current_generation - 1}
  end

  defp generation_ref do
    case :persistent_term.get(@generation_key, nil) do
      nil ->
        ref = :counters.new(1, [:atomics])
        :counters.put(ref, 1, 0)

        try do
          :persistent_term.put(@generation_key, ref)
          ref
        rescue
          ArgumentError ->
            :persistent_term.get(@generation_key)
        end

      ref ->
        ref
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

  defp maybe_reset_cache do
    if size() >= @max_entries or cache_memory_words() >= @max_memory_words do
      clear()
    end
  end

  defp cache_memory_words do
    ensure_started()
    :ets.info(@table, :memory) || 0
  end
end
