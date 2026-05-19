defmodule BackBreeze.TextSurfaceTest do
  use ExUnit.Case, async: true

  alias BackBreeze.TextSpan
  alias BackBreeze.VirtualText

  test "renders styled text spans within a box" do
    content = [
      TextSpan.new("Hello ", %{foreground_color: 2}),
      TextSpan.new("World", %{bold: true, foreground_color: 4})
    ]

    style =
      BackBreeze.Style.border()
      |> BackBreeze.Style.width(13)

    output = BackBreeze.Style.render(style, content)

    assert output ==
             """
             ┌───────────┐
             │\e[38;5;2mHello \e[0m\e[1;38;5;4mWorld\e[0m│
             └───────────┘\
             """
  end

  test "text span foreground overrides inherited foreground" do
    content = [
      TextSpan.new("Icon", %{foreground_color: {154, 103, 174}}),
      TextSpan.new(" Text")
    ]

    output =
      BackBreeze.Style.render(%BackBreeze.Style{foreground_color: {235, 219, 178}}, content)

    assert output ==
             "\e[38;2;154;103;174mIcon\e[0m\e[38;2;235;219;178m Text\e[0m"
  end

  test "structured virtual text span foreground overrides inherited foreground" do
    content =
      VirtualText.lazy(
        cache_key: {:structured_span_color_fixture, make_ref()},
        cache?: false,
        intrinsic_width: 9,
        line_count_fn: fn _width -> 1 end,
        slice_fn: fn _start_line, _count, _width ->
          [[{"Icon", %{foreground_color: {154, 103, 174}}}, {" Text", %{}}]]
        end
      )

    style = %BackBreeze.Style{
      foreground_color: {235, 219, 178},
      width: 9,
      height: 1,
      overflow: :hidden,
      scrollbar: true
    }

    {_content, dimensions} =
      BackBreeze.Style.calculate_and_render(style, content, structured: true)

    output =
      BackBreeze.Box.layer_map_to_content(
        dimensions.layer_map,
        dimensions.rendered_width,
        dimensions.height
      )

    assert output ==
             "\e[38;2;154;103;174mIcon\e[0m\e[38;2;235;219;178m Text\e[0m"
  end

  test "supports deep viewport slicing for text spans" do
    content =
      1..200
      |> Enum.map(fn index ->
        [
          TextSpan.new("Line ", %{foreground_color: 2}),
          TextSpan.new(Integer.to_string(index), %{bold: true})
        ]
      end)
      |> Enum.intersperse([TextSpan.new("\n")])
      |> List.flatten()

    style =
      BackBreeze.Style.border()
      |> BackBreeze.Style.width(10)
      |> BackBreeze.Style.height(4)
      |> BackBreeze.Style.overflow(:hidden)

    output = BackBreeze.Style.render(style, content, offset_top: 197)

    assert output ==
             """
             ┌────────┐
             │\e[38;5;2mLine \e[0m\e[1m198\e[0m│
             │\e[38;5;2mLine \e[0m\e[1m199\e[0m│
             └────────┘\
             """
  end

  test "renders lazy virtual text near the end of a fixed-height viewport" do
    content =
      VirtualText.lazy(
        cache_key: :lazy_virtual_text_fixture,
        intrinsic_width: 12,
        line_count_fn: fn _width -> 2_000 end,
        slice_fn: fn start_line, count, _width ->
          Enum.map(start_line..(start_line + count - 1), fn index ->
            "Line #{index + 1}" |> String.pad_trailing(12, ".")
          end)
        end
      )

    style =
      BackBreeze.Style.border()
      |> BackBreeze.Style.width(14)
      |> BackBreeze.Style.height(5)
      |> BackBreeze.Style.overflow(:hidden)

    output = BackBreeze.Style.render(style, content, offset_top: 1_996)

    assert output ==
             """
             ┌────────────┐
             │Line 1997...│
             │Line 1998...│
             │Line 1999...│
             └────────────┘\
             """
  end

  test "virtual text content obeys box scroll offsets" do
    content =
      VirtualText.lazy(
        cache_key: :box_virtual_text_fixture,
        intrinsic_width: 12,
        line_count_fn: fn _width -> 20 end,
        slice_fn: fn start_line, count, _width ->
          Enum.map(start_line..(start_line + count - 1), fn index ->
            "Line #{index + 1}" |> String.pad_trailing(12, ".")
          end)
        end
      )

    box =
      BackBreeze.Box.new(
        content: content,
        scroll: {3, 0},
        style: %{border: :line, width: 14, height: 5, overflow: :hidden}
      )

    rendered = BackBreeze.Box.render(box)

    assert rendered.content ==
             """
             ┌────────────┐
             │Line 4......│
             │Line 5......│
             │Line 6......│
             └────────────┘\
             """
  end
end
