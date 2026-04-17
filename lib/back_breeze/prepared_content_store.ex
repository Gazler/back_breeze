defmodule BackBreeze.PreparedContentStore do
  @moduledoc false

  use GenServer

  @table :back_breeze_prepared_content_store
  @max_entries 32
  @max_bytes 64 * 1_024 * 1_024
  @counter_key {__MODULE__, :access_counter}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    ensure_table()
    access_counter()
    {:ok, %{}}
  end

  def fetch(key, fun) when is_function(fun, 0) do
    ensure_started()

    case :ets.lookup(@table, key) do
      [{^key, value, _size, _accessed_at}] ->
        touch(key, value)

      [] ->
        value = fun.()
        insert(key, value)
        value
    end
  end

  def size do
    ensure_started()
    :ets.info(@table, :size) || 0
  end

  def clear do
    ensure_started()
    :ets.delete_all_objects(@table)
    :counters.put(access_counter(), 1, 0)
    :ok
  end

  defp touch(key, value) do
    size = entry_size(value)
    true = :ets.insert(@table, {key, value, size, next_access()})
    value
  end

  defp insert(key, value) do
    size = entry_size(value)
    true = :ets.insert(@table, {key, value, size, next_access()})
    evict_if_needed()
    value
  end

  defp evict_if_needed do
    if over_limit?() do
      @table
      |> :ets.tab2list()
      |> Enum.sort_by(fn {_key, _value, _size, accessed_at} -> accessed_at end)
      |> Enum.reduce_while(:ok, fn {key, _value, _size, _accessed_at}, :ok ->
        :ets.delete(@table, key)

        if over_limit?() do
          {:cont, :ok}
        else
          {:halt, :ok}
        end
      end)
    end
  end

  defp over_limit? do
    size() > @max_entries or total_bytes() > @max_bytes
  end

  defp total_bytes do
    ensure_started()

    :ets.foldl(fn {_key, _value, size, _accessed_at}, acc -> acc + size end, 0, @table)
  end

  defp entry_size(%{content: content}) when is_binary(content), do: byte_size(content)
  defp entry_size(other), do: :erlang.external_size(other)

  defp next_access do
    ensure_started()
    counter = access_counter()
    :counters.add(counter, 1, 1)
    :counters.get(counter, 1)
  end

  defp ensure_started do
    if :ets.whereis(@table) == :undefined or :persistent_term.get(@counter_key, nil) == nil do
      Application.ensure_all_started(:back_breeze)
    end

    :ok
  end

  defp access_counter do
    case :persistent_term.get(@counter_key, nil) do
      nil ->
        ref = :counters.new(1, [:atomics])
        :counters.put(ref, 1, 0)

        try do
          :persistent_term.put(@counter_key, ref)
          ref
        rescue
          ArgumentError ->
            :persistent_term.get(@counter_key)
        end

      ref ->
        ref
    end
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        rescue
          ArgumentError ->
            @table
        end

      tid ->
        tid
    end
  end
end
