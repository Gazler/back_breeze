defmodule BackBreeze.Cache do
  @moduledoc """
  Defines the cache backend used by BackBreeze.

  BackBreeze ships with `BackBreeze.Cache.Default`, which uses the cache
  implementation provided by this package. Runtimes with different storage
  capabilities can configure a backend of their own:

      config :back_breeze, cache_backend: MyApp.BackBreezeCache

  The backend must be configured before `:back_breeze` is compiled.
  Applications that need different cache behavior are responsible for providing
  that implementation.
  """

  @type cache :: :render | :stable | :prepared
  @type cache_scope :: :render | :prepared

  @backend Application.compile_env(:back_breeze, :cache_backend, BackBreeze.Cache.Default)
  @compile {:no_warn_undefined, @backend}

  @callback children() :: [Supervisor.child_spec()]
  @callback with_frame((-> term())) :: term()
  @callback fetch(cache(), term(), (-> term())) :: term()
  @callback clear(cache_scope()) :: :ok
  @callback size(cache_scope()) :: non_neg_integer()
  @callback advance_generation() :: :ok
  @callback max_memory_words() :: non_neg_integer()

  @optional_callbacks max_memory_words: 0

  @doc false
  def backend, do: @backend

  @doc false
  def children, do: @backend.children()

  @doc false
  def with_frame(fun), do: @backend.with_frame(fun)

  @doc false
  def fetch(cache, key, fun), do: @backend.fetch(cache, key, fun)

  @doc false
  def clear(cache), do: @backend.clear(cache)

  @doc false
  def size(cache), do: @backend.size(cache)

  @doc false
  def advance_generation, do: @backend.advance_generation()

  @doc false
  def max_memory_words do
    if function_exported?(@backend, :max_memory_words, 0) do
      @backend.max_memory_words()
    else
      0
    end
  end
end
