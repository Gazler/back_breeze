defmodule BackBreeze.BenchProfile do
  @moduledoc false

  @enabled_key {__MODULE__, :enabled}
  @stats_key {__MODULE__, :stats}

  def enable!, do: Process.put(@enabled_key, true)
  def disable!, do: Process.delete(@enabled_key)

  def reset! do
    Process.put(@stats_key, %{})
  end

  def enabled?, do: Process.get(@enabled_key, false)

  def measure(label, fun) do
    if enabled?() do
      {us, result} = :timer.tc(fun)
      record(label, us)
      result
    else
      fun.()
    end
  end

  def snapshot do
    Process.get(@stats_key, %{})
  end

  defp record(label, us) do
    stats =
      Process.get(@stats_key, %{})
      |> Map.update(label, %{count: 1, total_us: us, max_us: us}, fn stat ->
        %{count: stat.count + 1, total_us: stat.total_us + us, max_us: max(stat.max_us, us)}
      end)

    Process.put(@stats_key, stats)
  end
end
