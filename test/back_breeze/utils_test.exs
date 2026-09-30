defmodule BackBreeze.UtilsTest do
  use ExUnit.Case, async: true
  doctest BackBreeze.Utils

  test "large plain-text metrics avoid per-character traversal" do
    text = Enum.map_join(1..72, "\n", fn _ -> String.duplicate("x", 242) end)
    BackBreeze.Box.TextMetrics.metrics("warm")
    {:reductions, before} = Process.info(self(), :reductions)
    assert BackBreeze.Box.TextMetrics.metrics(text) == {242, 72}
    assert BackBreeze.TextLayout.source_metrics(text) == {byte_size(text), 242}
    assert BackBreeze.Utils.string_length(text) == byte_size(text)
    {:reductions, after_render} = Process.info(self(), :reductions)
    assert after_render - before < byte_size(text)
  end

  test "string_length/1 ignores escape sequences" do
    style =
      BackBreeze.Style.bold()
      |> BackBreeze.Style.foreground_color(3)

    output = BackBreeze.Style.render(style, "Hello World")

    assert BackBreeze.Utils.string_length(output) == 11
  end
end
