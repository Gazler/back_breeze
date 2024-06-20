defmodule BackBreeze.Box do
  defstruct content: "",
            children: [],
            style: %BackBreeze.Style{},
            width: nil,
            state: :ready,
            position: :relative,
            left: nil,
            top: nil,
            layer: 0,
            layer_map: %{}

  def new(opts) do
    map = Map.new(opts)
    style = Map.get(map, :style, %{})

    style =
      case Map.get(style, :border) do
        :line -> %{style | border: BackBreeze.Border.line()}
        _ -> style
      end

    style = struct(BackBreeze.Style, style)
    struct(BackBreeze.Box, Map.put(map, :style, style))
  end

  def render(%{state: :rendered} = box) do
    box
  end

  def render(%{children: []} = box) do
    {content, width} = render_self(box)
    %{box | content: content, width: width, state: :rendered, children: []}
  end

  def render(box) do
    {child_layer_map, child_width, child_height} = render_children(box)

    width =
      if box.style.overflow == :hidden,
        do: box.style.width,
        else: max(box.style.width, child_width)

    style = %{box.style | width: width}

    {content, _width} =
      render_self(%{box | content: box.content, width: width, style: style})

    layer_map = generate_layer_map(content, %{}, 0, 0)

    keys = Map.keys(layer_map)

    {_, max_width} = if keys != [], do: Enum.max_by(keys, &elem(&1, 1)), else: {0, 0}
    {max_height, _} = if keys != [], do: Enum.max_by(keys, &elem(&1, 0)), else: {0, 0}

    max_width = max(max_width, child_width)
    max_height = max(max_height, child_height)

    reset = Termite.Style.reset_code()

    content =
      Enum.map(0..max_height, fn y ->
        {content, buffer, style} =
          Enum.reduce(0..max_width, {"", "", ""}, fn x, {acc, buffer, last_style} ->
            point = Map.get(child_layer_map, {y, x}) || Map.get(layer_map, {y, x})

            case {point, buffer, last_style} do
              {{char, style}, _, style} -> {acc, buffer <> char, style}
              {{char, style}, _, ""} -> {acc <> buffer, char, style}
              {{char, style}, _, last} -> {acc <> last <> buffer <> reset, char, style}
            end
          end)

        case {buffer, style} do
          {"", _} -> content
          {_, nil} -> content <> buffer
          {_, ""} -> content <> buffer
          {_, style} -> content <> style <> buffer <> reset
        end
      end)

    content = Enum.join(content, "\n")

    %{box | content: String.trim_trailing(content, "\n"), width: max_width + 1, state: :rendered}
  end

  def render_self(box) do
    content = BackBreeze.Style.render(box.style, box.content)

    items =
      String.split(content, "\n")
      |> Enum.map(&{BackBreeze.Utils.string_length(&1), &1})

    {max_width, _} = Enum.max(items)
    {content, max_width}
  end

  defp render_children(%{children: children} = box) when children != [] do
    children = set_layer(children, [], -1) |> Enum.map(&render/1)

    relative =
      children
      |> Enum.filter(&(&1.position != :absolute))

    {layer, style} =
      case relative do
        [x | _] -> {x.layer, x.style}
        _ -> {0, %BackBreeze.Style{}}
      end

    {content, width} =
      Enum.map(relative, & &1.content)
      |> join_horizontal()

    absolutes = Enum.filter(children, &(&1.position == :absolute))
    relative = %{box | style: style, content: content, children: [], width: width, layer: layer}
    rendered_boxes = [relative | absolutes] |> Enum.sort_by(& &1.layer)

    border = box.style.border

    layer_map =
      Enum.reduce(rendered_boxes, %{}, fn box, layer_map ->
        {start_x, y} =
          case {box.position, border.left, border.top} do
            {:absolute, _, _} -> {box.left, box.top}
            {_, nil, nil} -> {0, 0}
            {_, _, nil} -> {1, 0}
            _ -> {1, 1}
          end

        generate_layer_map(box.content, layer_map, start_x, y)
      end)

    keys = Map.keys(layer_map)

    {_, max_width} = Enum.max_by(keys, &elem(&1, 1))
    {max_height, _} = Enum.max_by(keys, &elem(&1, 0))

    {layer_map, max_width, max_height}
  end

  defp generate_layer_map(content, layer_map, start_x, y) do
    reset = Termite.Style.reset_code()

    {_x, _y, {acc, _, _}} =
      content
      |> String.graphemes()
      |> Enum.reduce({start_x, y, {layer_map, false, ""}}, fn
        "\n", {_x, y, acc} -> {start_x, y + 1, acc}
        "\e", {x, y, {map, false, _}} -> {x, y, {map, true, "\e"}}
        "m", {x, y, {map, true, seq}} -> {x, y, {map, false, seq <> "m"}}
        c, {x, y, {map, true, seq}} -> {x, y, {map, true, seq <> c}}
        c, {x, y, {map, _, ^reset}} -> {x + 1, y, {Map.put(map, {y, x}, {c, ""}), false, reset}}
        c, {x, y, {map, _, seq}} -> {x + 1, y, {Map.put(map, {y, x}, {c, seq}), false, seq}}
      end)

    acc
  end

  defp set_layer([], result, _layer) do
    Enum.reverse(result)
  end

  defp set_layer([%{position: :absolute} = box | rest], result, layer) do
    set_layer(rest, [%{box | layer: layer + 1} | result], layer + 2)
  end

  defp set_layer([box | rest], result, layer) when is_binary(box) do
    set_layer(rest, [box | result], layer || 0)
  end

  defp set_layer([box | rest], result, nil) do
    set_layer(rest, [%{box | layer: 0} | result], 0)
  end

  defp set_layer([box | rest], result, layer) do
    set_layer(rest, [%{box | layer: layer} | result], layer)
  end

  def join_horizontal(items, opts \\ [])

  def join_horizontal([], _opts) do
    {"", 0}
  end

  def join_horizontal(items, opts) do
    items = Enum.map(items, fn x -> {String.graphemes(x) |> Enum.count(&(&1 == "\n")), x} end)

    {max_height, _} = Enum.max(items)

    rows =
      items
      |> Enum.map(fn {height, item} ->
        padding = String.duplicate("\n", max_height - height)

        String.split(padding <> item, "\n")
        |> normalize_width(opts)
      end)
      |> Enum.zip()
      |> Enum.map(fn x -> Enum.join(Tuple.to_list(x), "") end)

    width = rows |> Enum.reverse() |> hd() |> BackBreeze.Utils.string_length()

    content =
      rows
      |> Enum.join("\n")
      |> String.trim_trailing("\n")

    {content, width}
  end

  defp normalize_width(items, opts) do
    align = Keyword.get(opts, :align, :left)
    items = Enum.map(items, &{BackBreeze.Utils.string_length(&1), &1})
    {max_width, _} = Enum.max(items)

    Enum.map(items, fn {width, item} ->
      padding = max_width - width

      case align do
        :left ->
          item <> String.duplicate(" ", padding)

        :right ->
          String.duplicate(" ", padding) <> item

        :center ->
          String.duplicate(" ", div(padding, 2) + rem(padding, 2)) <>
            item <> String.duplicate(" ", div(padding, 2))
      end
    end)
  end
end
