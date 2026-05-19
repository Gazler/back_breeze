defmodule BackBreeze.ScrollbarTest do
  use ExUnit.Case, async: true

  test "proportional thumb sizing uses viewport size" do
    {scrollbar, _style} = BackBreeze.Scrollbar.normalize(true, %BackBreeze.Style{})

    assert BackBreeze.Scrollbar.thumb_size(scrollbar, 3, 5, 10) == 2
    assert BackBreeze.Scrollbar.thumb_size(scrollbar, 3, 3, 10) == 1
  end
end
