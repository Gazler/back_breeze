defmodule BackBreeze.Box.LayerMapTest do
  use ExUnit.Case, async: true

  alias BackBreeze.Box.LayerMap

  test "merges a metadata-only base without rebuilding source cells" do
    base = %{
      __default_fill__: [{{" ", "base"}, 0, 0, 3, 0}]
    }

    source = %{
      {0, 0} => {"A", "text"},
      __default_fill__: [{{" ", "source"}, 0, 0, 0, 0}]
    }

    assert {:ok, merged} = LayerMap.merge_metadata_base(base, source)
    assert merged[{0, 0}] == {"A", "text"}

    assert merged.__default_fill__ == [
             {{" ", "source"}, 0, 0, 0, 0},
             {{" ", "base"}, 0, 0, 3, 0}
           ]
  end

  test "drops transparent source spaces so they reveal the base fill" do
    base = %{__default_fill__: [{{" ", "base"}, 0, 0, 3, 0}]}
    source = %{{0, 0} => {" ", ""}}

    assert {:ok, merged} = LayerMap.merge_metadata_base(base, source)
    refute Map.has_key?(merged, {0, 0})
    assert merged.__default_fill__ == [{{" ", "base"}, 0, 0, 3, 0}]
  end

  test "falls back when the base contains explicit cells" do
    base = %{{0, 0} => {"B", "base"}}
    source = %{{0, 0} => {"A", "text"}}

    assert :error = LayerMap.merge_metadata_base(base, source)
  end
end
