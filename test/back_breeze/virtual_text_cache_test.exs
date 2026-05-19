defmodule BackBreeze.VirtualTextCacheTest do
  use ExUnit.Case, async: false

  alias BackBreeze.PreparedContentStore
  alias BackBreeze.VirtualText

  setup do
    BackBreeze.RenderCache.clear()
    PreparedContentStore.clear()

    on_exit(fn ->
      BackBreeze.RenderCache.clear()
      PreparedContentStore.clear()
    end)

    :ok
  end

  test "lazy virtual text is not retained in the prepared content cache" do
    content =
      VirtualText.lazy(
        cache_key: {:lazy_cache_fixture, make_ref()},
        intrinsic_width: 16,
        line_count_fn: fn _width -> 1_000 end,
        slice_fn: fn start_line, count, _width ->
          Enum.map(start_line..(start_line + count - 1), fn index ->
            "Line #{index + 1}" |> String.pad_trailing(16, ".")
          end)
        end
      )

    style =
      BackBreeze.Style.width(16)
      |> BackBreeze.Style.height(4)
      |> BackBreeze.Style.overflow(:hidden)

    output = BackBreeze.Style.render(style, content, offset_top: 996)

    assert output =~ "Line 997"
    assert PreparedContentStore.size() == 0
  end

  test "cache-disabled virtual text bypasses stable render caches" do
    box =
      BackBreeze.Box.new(
        content: uncached_virtual_text("Line"),
        scroll: {996, 0},
        style: %{width: 16, height: 4, overflow: :hidden}
      )

    rendered = BackBreeze.Box.render(box)

    assert rendered.content =~ "Line 997"
    assert PreparedContentStore.size() == 0

    render_cache_size = BackBreeze.RenderCache.size()

    rendered =
      box
      |> Map.put(:content, uncached_virtual_text("Next"))
      |> BackBreeze.Box.render()

    assert rendered.content =~ "Next 997"
    assert PreparedContentStore.size() == 0
    assert BackBreeze.RenderCache.size() == render_cache_size
  end

  defp uncached_virtual_text(prefix) do
    VirtualText.lazy(
      cache_key: {:uncached_lazy_fixture, make_ref()},
      cache?: false,
      intrinsic_width: 16,
      line_count_fn: fn _width -> 1_000 end,
      slice_fn: fn start_line, count, _width ->
        Enum.map(start_line..(start_line + count - 1), fn index ->
          "#{prefix} #{index + 1}" |> String.pad_trailing(16, ".")
        end)
      end
    )
  end
end
