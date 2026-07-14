defmodule BackBreeze.CacheTest do
  use ExUnit.Case, async: true

  test "uses the default cache backend" do
    assert BackBreeze.Cache.backend() == BackBreeze.Cache.Default

    assert BackBreeze.Cache.children() == [
             BackBreeze.RenderCache.Default,
             BackBreeze.PreparedContentStore.Default
           ]
  end
end
