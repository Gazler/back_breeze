defmodule BackBreeze.BenchProfile do
  @moduledoc false

  @global_enabled_key {__MODULE__, :global_enabled}
  @enabled_key {__MODULE__, :enabled}
  @stats_key {__MODULE__, :stats}
  @table __MODULE__

  def enable!, do: Process.put(@enabled_key, true)
  def disable!, do: Process.delete(@enabled_key)

  def enable_global! do
    ensure_table!()
    :persistent_term.put(@global_enabled_key, true)
  end

  def disable_global!, do: :persistent_term.put(@global_enabled_key, false)

  def reset! do
    Process.put(@stats_key, %{})
  end

  def reset_global! do
    ensure_table!()
    :ets.delete_all_objects(@table)
  end

  def enabled?, do: Process.get(@enabled_key, false) or global_enabled?()

  def measure(label, fun) do
    cond do
      Process.get(@enabled_key, false) ->
        {us, result} = :timer.tc(fun)
        record(label, us)
        result

      global_enabled?() ->
        {us, result} = :timer.tc(fun)
        record_global(label, us)
        result

      true ->
        fun.()
    end
  end

  def snapshot do
    Process.get(@stats_key, %{})
  end

  def snapshot_global do
    ensure_table!()

    @table
    |> :ets.tab2list()
    |> Map.new(fn {label, count, total_us, max_us} ->
      {label, %{count: count, total_us: total_us, max_us: max_us}}
    end)
  end

  defp record(label, us) do
    stats =
      Process.get(@stats_key, %{})
      |> Map.update(label, %{count: 1, total_us: us, max_us: us}, fn stat ->
        %{count: stat.count + 1, total_us: stat.total_us + us, max_us: max(stat.max_us, us)}
      end)

    Process.put(@stats_key, stats)
  end

  defp record_global(label, us) do
    ensure_table!()
    :ets.update_counter(@table, label, [{2, 1}, {3, us}], {label, 0, 0, 0})
    update_max(label, us)
  end

  defp update_max(label, us) do
    case :ets.lookup(@table, label) do
      [{^label, count, total_us, max_us}] when us > max_us ->
        :ets.insert(@table, {label, count, total_us, us})

      _entry ->
        :ok
    end
  end

  defp global_enabled?, do: :persistent_term.get(@global_enabled_key, false)

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _table -> @table
    end
  end
end
