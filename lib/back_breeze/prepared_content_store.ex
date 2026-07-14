defmodule BackBreeze.PreparedContentStore do
  @moduledoc false

  def fetch(key, fun) when is_function(fun, 0) do
    BackBreeze.Cache.fetch(:prepared, key, fun)
  end

  def size, do: BackBreeze.Cache.size(:prepared)
  def clear, do: BackBreeze.Cache.clear(:prepared)
end
