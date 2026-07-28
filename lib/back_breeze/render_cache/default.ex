defmodule BackBreeze.RenderCache.Default do
  @moduledoc false

  use GenServer

  @table :back_breeze_render_cache
  @max_entries 4_096
  @maximum_memory_bytes 1_024 * 1_024 * 1_024
  @memory_ratio_numerator 7
  @memory_ratio_denominator 10
  @max_memory_bytes_key {__MODULE__, :max_memory_bytes}
  @generation_key {__MODULE__, :generation_counter}
  @frame_depth_key {__MODULE__, :frame_depth}
  @frame_generations_key {__MODULE__, :frame_generations}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    put_max_memory_bytes()
    ensure_table()
    generation_ref()
    {:ok, %{}}
  end

  def with_frame(fun) when is_function(fun, 0) do
    ensure_started()
    depth = Process.get(@frame_depth_key, 0)

    if depth == 0 do
      current_generation = increment_generation()
      Process.put(@frame_generations_key, {current_generation, current_generation - 1})
    end

    Process.put(@frame_depth_key, depth + 1)

    try do
      fun.()
    after
      if depth == 0 do
        Process.delete(@frame_depth_key)
        Process.delete(@frame_generations_key)
      else
        Process.put(@frame_depth_key, depth)
      end
    end
  end

  def fetch(key, fun) when is_function(fun, 0) do
    do_fetch(key, fun)
  end

  def fetch_stable(key, fun) when is_function(fun, 0) do
    do_fetch_stable(key, fun)
  end

  def clear do
    ensure_started()
    :ets.delete_all_objects(@table)
    :counters.put(generation_ref(), 1, 0)

    if Process.get(@frame_depth_key, 0) > 0 do
      Process.put(@frame_generations_key, {0, -1})
    end
  end

  def size do
    ensure_started()
    :ets.info(@table, :size)
  end

  @doc false
  def max_memory_bytes do
    ensure_started()

    case :persistent_term.get(@max_memory_bytes_key, nil) do
      nil -> put_max_memory_bytes()
      bytes -> bytes
    end
  end

  @doc false
  def limit_for_available_memory(bytes) when is_integer(bytes) and bytes >= 0 do
    bytes
    |> Kernel.*(@memory_ratio_numerator)
    |> div(@memory_ratio_denominator)
    |> min(@maximum_memory_bytes)
    |> max(1)
  end

  def advance_generation do
    ensure_started()
    current_generation = increment_generation()

    if Process.get(@frame_depth_key, 0) > 0 do
      Process.put(@frame_generations_key, {current_generation, current_generation - 1})
    end

    :ok
  end

  defp do_fetch(key, fun) do
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

  defp increment_generation do
    ref = generation_ref()
    :counters.add(ref, 1, 1)
    :counters.get(ref, 1)
  end

  defp ensure_started do
    if :ets.whereis(@table) == :undefined or :persistent_term.get(@generation_key, nil) == nil do
      Application.ensure_all_started(:back_breeze)
    end

    :ok
  end

  defp generations do
    case Process.get(@frame_generations_key) do
      nil ->
        current_generation = :counters.get(generation_ref(), 1)
        {current_generation, current_generation - 1}

      generations ->
        generations
    end
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
    if size() >= @max_entries or cache_memory_bytes() >= max_memory_bytes() do
      clear()
    end
  end

  defp cache_memory_bytes do
    ensure_started()
    (:ets.info(@table, :memory) || 0) * :erlang.system_info(:wordsize)
  end

  defp put_max_memory_bytes do
    bytes = resolve_max_memory_bytes()
    :persistent_term.put(@max_memory_bytes_key, bytes)
    bytes
  end

  defp resolve_max_memory_bytes do
    case Application.get_env(:back_breeze, :render_cache_max_memory_bytes, :auto) do
      :auto ->
        available_memory_bytes() |> limit_for_available_memory()

      bytes when is_integer(bytes) and bytes > 0 ->
        bytes

      value ->
        raise ArgumentError,
              ":back_breeze, :render_cache_max_memory_bytes must be :auto or a positive integer, got: #{inspect(value)}"
    end
  end

  defp available_memory_bytes do
    case Keyword.get(:memsup.get_system_memory_data(), :available_memory) do
      bytes when is_integer(bytes) and bytes >= 0 -> bytes
      _other -> available_memory_from_summary()
    end
  catch
    :exit, _reason -> fallback_available_memory()
  end

  defp available_memory_from_summary do
    case :memsup.get_memory_data() do
      {total, allocated, _worst} when total > 0 -> max(total - allocated, 0)
      _other -> fallback_available_memory()
    end
  end

  defp fallback_available_memory do
    div(@maximum_memory_bytes * @memory_ratio_denominator, @memory_ratio_numerator) + 1
  end
end
