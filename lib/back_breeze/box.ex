defmodule BackBreeze.Box do
  alias BackBreeze.Ucwidth

  defstruct content: "",
            children: [],
            style: %BackBreeze.Style{},
            width: nil,
            height: nil,
            state: :ready,
            position: :relative,
            display: :block,
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

  def render(box, opts \\ [])

  def render(%{state: :rendered} = box, _opts) do
    box
  end

  def render(%{children: []} = box, opts) do
    {content, width} = render_self(box, opts)
    %{box | content: content, width: width, state: :rendered, children: []}
  end

  def render(box, opts) do
    {child_layer_map, child_width, child_height} = render_children(box, opts)

    width =
      if box.style.overflow == :hidden,
        do: box.style.width,
        else: max(box.style.width, child_width)

    height =
      if box.style.overflow == :hidden,
        do: box.style.height,
        else: max(box.style.height, child_height)

    style = %{box.style | width: width, height: height}

    {content, _width} =
      render_self(%{box | width: width, height: height, style: style}, opts)

    {layer_map, max_width, max_height} = generate_layer_map(content, %{}, 0, 0)

    max_width = max(max_width, child_width)
    max_height = max(max_height, child_height)

    reset = Termite.Style.reset_code()

    {start_x, start_y} =
      case box do
        %{position: :absolute, left: left, top: top} -> {left, top}
        _ -> {0, 0}
      end

    y_range = start_y..max_height
    x_range = start_x..max_width

    content =
      Enum.map(y_range, fn y ->
        {content, buffer, style, _} =
          Enum.reduce(x_range, {"", "", "", false}, fn x, {acc, buffer, last_style, skip} ->
            child_point = Map.get(child_layer_map, {y, x})

            point =
              if skip do
                child_point
              else
                child_point || Map.get(layer_map, {y, x})
              end

            skip_next =
              case child_point do
                {char, _} -> Ucwidth.width(char) == 2
                _ -> false
              end

            case {point, buffer, last_style} do
              {nil, _, _} -> {acc, buffer, last_style, skip_next}
              {{char, style}, _, style} -> {acc, buffer <> char, style, skip_next}
              {{char, style}, _, ""} -> {acc <> buffer, char, style, skip_next}
              {{char, style}, _, last} -> {acc <> last <> buffer <> reset, char, style, skip_next}
            end
          end)

        case {buffer, style} do
          {"", _} -> content
          {_, nil} -> content <> buffer
          {_, ""} -> content <> buffer
          {_, style} -> content <> style <> buffer <> reset
        end
      end)

    content = Enum.join(content, "\n") |> String.trim_trailing("\n")

    %{box | content: content, width: max_width + 1, state: :rendered}
  end

  defp render_self(box, opts) do
    content = BackBreeze.Style.render(box.style, box.content, opts)

    items =
      String.split(content, "\n")
      |> Enum.map(&{BackBreeze.Utils.string_length(&1), &1})

    {max_width, _} = Enum.max(items)
    {content, max_width}
  end

  defp render_children(%{children: children, display: %BackBreeze.Grid{}} = box, opts) do
    %{width: item_width} = BackBreeze.Grid.precompute(children, box.display, box.style, opts)

    children =
      Enum.map(children, fn
        %{display: %BackBreeze.Grid{}, children: children} = child_box when children != [] ->
          style = %{child_box.style | width: item_width}

          {content, w, h} =
            BackBreeze.Grid.render(child_box.children, child_box.display, style, opts)

          %{child_box | children: [], content: content, width: w, height: h, state: :rendered}

        child_box ->
          child_box
      end)
      |> set_layer([], -1)

    relative = Enum.filter(children, &(&1.position != :absolute))

    {layer, style} =
      case relative do
        [x | _] -> {x.layer, x.style}
        _ -> {0, %BackBreeze.Style{}}
      end

    {content, width, height} = BackBreeze.Grid.render(children, box.display, box.style, opts)

    absolutes = Enum.filter(children, &(&1.position == :absolute))

    relative = %{
      box
      | style: style,
        content: content,
        children: [],
        height: height,
        width: width,
        layer: layer
    }

    combine_children(box, absolutes, relative)
  end

  defp render_children(%{children: children} = box, opts) when children != [] do
    children = set_layer(children, [], -1) |> Enum.map(&render(&1, opts))

    relative =
      children
      |> Enum.filter(&(&1.position != :absolute))

    {layer, style} =
      case relative do
        [x | _] -> {x.layer, x.style}
        _ -> {0, %BackBreeze.Style{}}
      end

    items = Enum.map(relative, & &1.content)

    {content, width, height} =
      case box.display do
        :block -> join_vertical(items)
        :inline -> join_horizontal(items)
      end

    absolutes = Enum.filter(children, &(&1.position == :absolute))

    relative = %{
      box
      | style: style,
        content: content,
        children: [],
        height: height,
        width: width,
        layer: layer
    }

    combine_children(box, absolutes, relative)
  end

  defp combine_children(box, absolutes, relative) do
    rendered_boxes = [relative | absolutes] |> Enum.sort_by(& &1.layer)

    border = box.style.border

    Enum.reduce(rendered_boxes, {%{}, 0, 0}, fn box, {layer_map, max_width, max_height} ->
      {start_x, y} =
        case {box.position, border.left, border.top} do
          {:absolute, _, _} -> {box.left, box.top}
          {_, nil, nil} -> {0, 0}
          {_, _, nil} -> {1, 0}
          _ -> {1, 1}
        end

      {map, width, height} = generate_layer_map(box.content, layer_map, start_x, y)
      {map, max(max_width, width), max(max_height, height)}
    end)
  end

  defp generate_layer_map(content, layer_map, start_x, y) do
    reset = Termite.Style.reset_code()

    {_x, y, {acc, _, _}} =
      content
      |> String.graphemes()
      |> Enum.reduce({start_x, y, {layer_map, false, ""}}, fn
        "\n", {_x, y, acc} -> {start_x, y + 1, acc}
        "\e", {x, y, {map, false, _}} -> {x, y, {map, true, "\e"}}
        "m", {x, y, {map, true, seq}} -> {x, y, {map, false, seq <> "m"}}
        c, {x, y, {map, true, seq}} -> {x, y, {map, true, seq <> c}}
        c, {x, y, {map, _, ^reset}} -> add_layer_char(c, map, x, y, "", reset)
        c, {x, y, {map, _, seq}} -> add_layer_char(c, map, x, y, seq, seq)
      end)

    {max_x, map} = Map.pop(acc, :max_x, 1)

    {map, max_x - 1, y}
  end

  defp add_layer_char(c, map, x, y, current_seq, seq) do
    width = Ucwidth.width(c)

    map =
      map
      |> Map.update(:max_x, x + width, fn cur -> max(cur, x + width) end)
      |> Map.put({y, x}, {c, current_seq})

    {x + width, y, {map, false, seq}}
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

  def join_vertical(items, opts \\ [])

  def join_vertical([], _opts) do
    {"", 0, 0}
  end

  def join_vertical(items, _opts) do
    items_with_width =
      Enum.map(items, fn x ->
        max_width =
          String.split(x, "\n") |> Enum.map(&BackBreeze.Utils.string_length(&1)) |> Enum.max()

        {max_width, x}
      end)

    {max_width, _} = Enum.max(items_with_width)

    content =
      items
      |> Enum.join("\n")
      |> String.trim_trailing("\n")

    {content, max_width, content |> String.split("\n") |> length()}
  end

  def join_horizontal(items, opts \\ [])

  def join_horizontal([], _opts) do
    {"", 0, 0}
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

    {content, width, max_height}
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
