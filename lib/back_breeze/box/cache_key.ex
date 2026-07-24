defmodule BackBreeze.Box.CacheKey do
  @moduledoc false

  alias BackBreeze.VirtualText

  def cacheable?(%{content: %VirtualText{cache?: false}}), do: false

  def cacheable?(%{children: children}) when is_list(children) do
    Enum.all?(children, &cacheable?/1)
  end

  def cacheable?(_box), do: true

  def combine_children_cacheable?(absolutes), do: length(absolutes) in [1, 2]

  def combine_children_key(box, absolutes, relative, opts) do
    terminal = Keyword.get(opts, :terminal)

    {
      :combine_children,
      box.style.border,
      box.width,
      box.height,
      box.style.width,
      box.style.height,
      box.style.max_height,
      if(terminal, do: terminal.size, else: nil),
      rendered_key(relative),
      Enum.map(absolutes, &rendered_key/1)
    }
  end

  def rendered_key(box) do
    {
      box.position,
      box.left,
      box.top,
      box.right,
      box.bottom,
      box.width,
      box.height,
      box.layer,
      content_key(box.content),
      box.layer_map,
      fixed_layer_map(box)
    }
  end

  def box_key(%BackBreeze.Box{} = box) do
    {
      box.style,
      box.width,
      box.height,
      box.state,
      box.position,
      box.left,
      box.top,
      box.right,
      box.bottom,
      box.display,
      box.scroll,
      box.layer,
      content_key(box.content),
      fixed_layer_map(box),
      Enum.map(box.children, &box_key/1)
    }
  end

  def content_key(%VirtualText{cache_key: cache_key}) when not is_nil(cache_key),
    do: {:virtual_text, cache_key}

  def content_key(%VirtualText{content: content}), do: {:virtual_text_binary, content}
  def content_key(content), do: content

  defp fixed_layer_map(%{fixed_layer_map: fixed_layer_map}) when is_map(fixed_layer_map),
    do: fixed_layer_map

  defp fixed_layer_map(_), do: %{}
end
