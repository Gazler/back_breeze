defmodule BackBreeze.Cache.Default do
  @moduledoc false

  @behaviour BackBreeze.Cache

  alias BackBreeze.PreparedContentStore.Default, as: PreparedContentStore
  alias BackBreeze.RenderCache.Default, as: RenderCache

  @impl true
  def children, do: [RenderCache, PreparedContentStore]

  @impl true
  def with_frame(fun), do: RenderCache.with_frame(fun)

  @impl true
  def fetch(:render, key, fun), do: RenderCache.fetch(key, fun)
  def fetch(:stable, key, fun), do: RenderCache.fetch_stable(key, fun)
  def fetch(:prepared, key, fun), do: PreparedContentStore.fetch(key, fun)

  @impl true
  def clear(:render), do: RenderCache.clear()
  def clear(:prepared), do: PreparedContentStore.clear()

  @impl true
  def size(:render), do: RenderCache.size()
  def size(:prepared), do: PreparedContentStore.size()

  @impl true
  def advance_generation, do: RenderCache.advance_generation()

  @impl true
  def max_memory_bytes, do: RenderCache.max_memory_bytes()
end
