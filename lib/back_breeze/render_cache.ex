defmodule BackBreeze.RenderCache do
  @moduledoc false

  def with_frame(fun) when is_function(fun, 0) do
    BackBreeze.Cache.with_frame(fun)
  end

  def fetch(key, fun) when is_function(fun, 0) do
    BackBreeze.Cache.fetch(:render, key, fun)
  end

  def fetch_stable(key, fun) when is_function(fun, 0) do
    BackBreeze.Cache.fetch(:stable, key, fun)
  end

  def clear, do: BackBreeze.Cache.clear(:render)
  def size, do: BackBreeze.Cache.size(:render)

  @doc false
  def max_memory_words, do: BackBreeze.Cache.max_memory_words()

  def advance_generation, do: BackBreeze.Cache.advance_generation()
end
