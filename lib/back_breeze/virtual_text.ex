defmodule BackBreeze.VirtualText do
  @moduledoc """
  Virtualized text content that can be projected into a viewport without
  materializing every visible ancestor render.
  """

  defstruct [:content, :cache_key, :intrinsic_width, :line_count_fn, :slice_fn, cache?: true]

  def new(content) when is_binary(content),
    do: %__MODULE__{content: content, cache_key: {:binary, content}}

  def lazy(opts) when is_list(opts) do
    %__MODULE__{
      cache_key: Keyword.fetch!(opts, :cache_key),
      intrinsic_width: Keyword.fetch!(opts, :intrinsic_width),
      line_count_fn: Keyword.fetch!(opts, :line_count_fn),
      slice_fn: Keyword.fetch!(opts, :slice_fn),
      cache?: Keyword.get(opts, :cache?, true)
    }
  end
end

defmodule BackBreeze.VirtualText.Source do
  @moduledoc """
  Helpers for constructing virtual text data sources.
  """

  def binary(content), do: BackBreeze.VirtualText.new(content)
  def lazy(opts), do: BackBreeze.VirtualText.lazy(opts)
end
