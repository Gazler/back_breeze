defmodule BackBreeze.Box do
  @moduledoc """
  A Box is the basic styling primitive used in BackBreeze. If a box has children,
  they will be rendered first and collapsed down, until a single box remains with
  the rendered contents.
  """
  alias BackBreeze.Ucwidth

  defstruct content: "",
            children: [],
            style: %BackBreeze.Style{},
            width: nil,
            height: nil,
            state: :ready,
            position: :relative,
            left: nil,
            top: nil,
            display: :block,
            scroll: {0, 0},
            layer: 0,
            layer_map: %{}

  @doc """
  Create a new `BackBreeze.Box` struct.

  ## Options

   * `:style` - a style map, with any valid keys from `BackBreeze.Style`. The `:border`
     style can be provided as `:line` for convenience.

  All other options are passed to the `BackBreeze.Box` struct.

  """
  def new(opts) do
    map = Map.new(opts)
    style = Map.get(map, :style, %{})

    style =
      case Map.get(style, :border) do
        :line -> %{style | border: BackBreeze.Border.line()}
        :rounded -> %{style | border: BackBreeze.Border.rounded()}
        _ -> style
      end

    style =
      case Map.get(style, :scrollbar) do
        true -> BackBreeze.Style.scrollbar(style, true)
        _ -> style
      end

    style = struct(BackBreeze.Style, style)

    struct(BackBreeze.Box, Map.put(map, :style, style))
  end

  @doc """
  Render a box and a tree of its children.

  ## Options

    * `:terminal` - the terminal to use. This is used for the terminal size if provided.
  """
  def render(box, opts \\ []) do
    render_with_dimensions(box, opts)
    |> Map.get(:box)
  end

  @doc """
  Render a box and a tree of its children whilst tracking dimensions.

  This function returns the box as with `render/2`, but it is wrapped in a map which
  also contains the rendered dimension for each box as a flat list.
  This can be used at a higher level to determine the viewport.

  ## Options

  See `render/2`
  """

  def render_with_dimensions(box, opts \\ []) do
    %{box: box, dimensions: dimensions} =
      render_and_calc(%{box: box, dimensions: [], id: 0}, opts)

    dimensions = Enum.sort(dimensions) |> Enum.map(&elem(&1, 1))
    %{box: box, dimensions: dimensions}
  end

  defp render_and_calc(%{box: %{state: :rendered}} = acc, _opts) do
    acc
  end

  defp render_and_calc(%{box: %{children: []} = box} = acc, opts) do
    {content, dimensions, width} = render_self(box, opts)

    {scrollbar_config, _} = BackBreeze.Scrollbar.normalize(box.style.scrollbar, box.style)

    {content, width, layer_map} =
      if box.style.overflow == :hidden and scrollbar_config.enabled do
        {layer_map, max_width, max_height} = generate_layer_map(content, %{}, 0, 0)

        layer_map =
          BackBreeze.Scrollbar.add_to_layer_map(layer_map, %{
            style: box.style,
            scroll: box.scroll,
            content_height: dimensions.content_height,
            content_width: raw_content_width(box.content),
            max_x: max_width,
            max_y: max_height
          })

        {layer_maps_to_content(layer_map, %{}, %{
           start_x: 0,
           start_y: 0,
           max_x: max_width,
           max_y: max_height
         }), max_width + 1, layer_map}
      else
        {content, width, %{}}
      end

    box = %{
      box
      | content: content,
        width: width,
        state: :rendered,
        children: [],
        layer_map: layer_map
    }

    %{acc | box: box, dimensions: [{acc.id, dimensions} | acc.dimensions], id: acc.id + 1}
  end

  defp render_and_calc(%{box: box} = acc, opts) do
    prev_id = acc.id

    child_length = length(box.children)

    {child_layer_map, child_width, child_height, acc} =
      render_children(%{acc | id: prev_id + 1}, opts)

    style_width = if box.style.width == :auto, do: 0, else: box.style.width

    width =
      if box.style.overflow == :hidden,
        do: box.style.width,
        else: max(style_width, child_width)

    style_height = if box.style.height == :auto, do: 0, else: box.style.height

    height =
      if box.style.overflow == :hidden,
        do: box.style.height,
        else: max(style_height, child_height)

    style = %{box.style | width: width, height: height}

    # We don't want offset to apply twice in cases when there are children.
    {content, dimensions, _width} =
      render_self(%{box | width: width, height: height, style: style, scroll: {0, 0}}, opts)

    border_rows =
      if(box.style.border.top, do: 1, else: 0) +
        if box.style.border.bottom, do: 1, else: 0

    dimensions =
      Enum.zip(Enum.reverse(box.children), Enum.take(acc.dimensions, child_length))
      |> Enum.reduce(
        %{
          content_height: 0,
          viewport_height: dimensions.height - border_rows,
          viewport_width: width,
          height: dimensions.height,
          width: width
        },
        fn
          {%{position: :absolute}, _}, acc -> acc
          {_, {_, dims}}, acc -> %{acc | content_height: dims.height + acc.content_height}
        end
      )

    acc = %{acc | dimensions: [{prev_id, dimensions} | acc.dimensions], id: acc.id}

    {layer_map, max_width, max_height} = generate_layer_map(content, %{}, 0, 0)

    {_, offset_left} = box.scroll

    child_layer_map =
      if offset_left > 0 do
        shift_layer_map(child_layer_map, -offset_left, 0)
      else
        child_layer_map
      end

    child_layer_map = clip_child_layer_map(child_layer_map, box.style, max_width, max_height)

    {max_width, max_height} =
      if box.style.overflow == :hidden do
        {max_width, max_height}
      else
        {max(max_width, child_width), max(max_height, child_height)}
      end

    child_layer_map =
      BackBreeze.Scrollbar.add_to_layer_map(child_layer_map, %{
        style: box.style,
        scroll: box.scroll,
        content_height: dimensions.content_height,
        content_width: child_width,
        max_x: max_width,
        max_y: max_height
      })

    {start_x, start_y} =
      case box.position do
        :absolute -> {box.left, box.top}
        _ -> {0, 0}
      end

    content =
      layer_maps_to_content(layer_map, child_layer_map, %{
        start_x: start_x,
        start_y: start_y,
        max_x: max_width,
        max_y: max_height
      })

    box = %{
      box
      | content: content,
        width: max_width + 1,
        state: :rendered,
        layer_map: Map.merge(layer_map, child_layer_map)
    }

    %{acc | box: box}
  end

  defp render_self(box, opts) do
    {offset_top, _} = box.scroll
    opts = Keyword.put(opts, :offset_top, offset_top)
    {content, dimensions} = BackBreeze.Style.calculate_and_render(box.style, box.content, opts)

    items =
      String.split(content, "\n")
      |> Enum.map(&{BackBreeze.Utils.string_length(&1), &1})

    {max_width, _} = Enum.max(items)
    {content, dimensions, max_width}
  end

  defp render_children(
         %{box: %{children: children, display: %BackBreeze.Grid{}} = box} = acc,
         opts
       ) do
    %{width: item_width} = BackBreeze.Grid.precompute(children, box.display, box.style, opts)

    {children, grouped_dims} =
      Enum.reduce(children, {[], []}, fn
        %{display: %BackBreeze.Grid{}, children: children} = child_box, child_acc
        when children != [] ->
          style = %{child_box.style | width: item_width}

          %{content: content, width: w, height: h, dimensions: inner_dimensions} =
            BackBreeze.Grid.render_with_dimensions(
              child_box.children,
              child_box.display,
              style,
              opts
            )

          {children, dims} = child_acc

          child = %{
            child_box
            | children: [],
              content: content,
              width: w,
              height: h,
              state: :rendered
          }

          container_dim = %{content_height: h, viewport_height: h, height: h}
          {children ++ [child], dims ++ [[container_dim | inner_dimensions]]}

        child_box, child_acc ->
          {children, dims} = child_acc
          {children ++ [child_box], dims ++ [nil]}
      end)

    children = set_layer(children, [], -1)

    relative = Enum.filter(children, &(&1.position != :absolute))

    {layer, style} =
      case relative do
        [x | _] -> {x.layer, x.style}
        _ -> {0, %BackBreeze.Style{}}
      end

    %{content: content, width: width, height: height, per_item_dimensions: per_item_dims} =
      BackBreeze.Grid.render_with_dimensions(children, box.display, box.style, opts)

    {final_id, new_dims} =
      Enum.zip(grouped_dims, per_item_dims)
      |> Enum.reduce({acc.id, []}, fn
        {nil, child_dims}, {id, acc_d} ->
          entries = Enum.with_index(child_dims, id) |> Enum.map(fn {d, i} -> {i, d} end)
          {id + length(child_dims), acc_d ++ entries}

        {grouped, _}, {id, acc_d} ->
          entries = Enum.with_index(grouped, id) |> Enum.map(fn {d, i} -> {i, d} end)
          {id + length(grouped), acc_d ++ entries}
      end)

    acc = %{acc | dimensions: acc.dimensions ++ new_dims, id: final_id}

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

    combine_children(box, absolutes, relative, acc)
  end

  defp render_children(%{box: %{children: children} = box} = acc, opts) when children != [] do
    # Mirror BackBreeze.Style.calculate_and_render/3, which resolves :screen to the
    # terminal size minus the outer frame.
    parent_width =
      case box.style.width do
        w when is_integer(w) -> w
        :screen -> opts |> Keyword.get(:terminal) |> BackBreeze.screen_dimensions() |> elem(0) |> Kernel.-(2)
        _ -> nil
      end

    parent_height =
      case box.style.height do
        h when is_integer(h) -> h
        :screen -> opts |> Keyword.get(:terminal) |> BackBreeze.screen_dimensions() |> elem(1) |> Kernel.-(2)
        _ -> nil
      end

    {children, acc, _used_height} =
      set_layer(children, [], -1)
      |> resolve_fill_widths(parent_width)
      |> Enum.reduce({[], acc, 0}, fn child, {boxes, child_acc, used_height} ->
        child = resolve_fill_height(child, box.display, parent_height, used_height)
        child_acc = render_and_calc(%{child_acc | box: child}, opts)

        used_height =
          if child_acc.box.position == :absolute or box.display != :block do
            used_height
          else
            used_height + (child_acc.box.height || rendered_height(child_acc.box.content))
          end

        {[child_acc.box | boxes], child_acc, used_height}
      end)

    children = Enum.reverse(children)

    relative =
      children
      |> Enum.filter(&(&1.position != :absolute))

    {layer, style} =
      case relative do
        [x | _] -> {x.layer, x.style}
        _ -> {0, %BackBreeze.Style{}}
      end

    items = Enum.map(relative, & &1.content)

    opts = Keyword.put(opts, :height, box.style.height)
    opts = Keyword.put(opts, :scroll, box.scroll)

    {content, width, height} =
      case box.display do
        :block -> join_vertical(items, opts)
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

    combine_children(box, absolutes, relative, acc)
  end

  defp combine_children(box, absolutes, relative, acc) do
    rendered_boxes = [relative | absolutes] |> Enum.sort_by(& &1.layer)

    border = box.style.border

    Enum.reduce(rendered_boxes, {%{}, 0, 0, acc}, fn box,
                                                     {layer_map, max_width, max_height, acc} ->
      {start_x, y} =
        case {box.position, border.left, border.top} do
          {:absolute, _, _} -> {box.left, box.top}
          {_, nil, nil} -> {0, 0}
          {_, _, nil} -> {1, 0}
          _ -> {1, 1}
        end

      {map, width, height} = generate_layer_map(box.content, layer_map, start_x, y)

      {map, max(max_width, width), max(max_height, height), acc}
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

  defp layer_maps_to_content(layer_map, overlay_layer_map, %{
         start_x: start_x,
         start_y: start_y,
         max_x: max_x,
         max_y: max_y
       }) do
    reset = Termite.Style.reset_code()

    content =
      Enum.map(start_y..max_y, fn y ->
        {content, buffer, style, _} =
          Enum.reduce(start_x..max_x, {"", "", "", false}, fn x,
                                                              {acc, buffer, last_style, skip} ->
            overlay_point = Map.get(overlay_layer_map, {y, x})

            point =
              if skip do
                overlay_point
              else
                overlay_point || Map.get(layer_map, {y, x})
              end

            skip_next =
              case overlay_point do
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

    Enum.join(content, "\n") |> String.trim_trailing("\n")
  end

  defp clip_child_layer_map(layer_map, %{overflow: :hidden, border: border}, max_x, max_y)
       when is_integer(max_x) and is_integer(max_y) do
    left = if border.left, do: 1, else: 0
    top = if border.top, do: 1, else: 0
    right = max(max_x - if(border.right, do: 1, else: 0), left - 1)
    bottom = max(max_y - if(border.bottom, do: 1, else: 0), top - 1)

    Enum.reduce(layer_map, %{}, fn
      {{y, x}, value}, acc when x >= left and x <= right and y >= top and y <= bottom ->
        Map.put(acc, {y, x}, value)

      _, acc ->
        acc
    end)
  end

  defp clip_child_layer_map(layer_map, _style, _width, _height), do: layer_map

  defp shift_layer_map(layer_map, shift_x, shift_y) do
    Enum.reduce(layer_map, %{}, fn
      {{y, x}, value}, acc ->
        Map.put(acc, {y + shift_y, x + shift_x}, value)

      _, acc ->
        acc
    end)
  end

  defp add_layer_char(c, map, x, y, current_seq, seq) do
    width = Ucwidth.width(c)

    map =
      map
      |> Map.update(:max_x, x + width, fn cur -> max(cur, x + width) end)
      |> Map.put({y, x}, {c, current_seq})

    {x + width, y, {map, false, seq}}
  end

  defp raw_content_width(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> Enum.map(&BackBreeze.Utils.string_length/1)
    |> Enum.max(fn -> 0 end)
  end

  defp raw_content_width(_), do: 0

  defp rendered_height(content) when is_binary(content) do
    content
    |> String.split("\n")
    |> length()
  end

  defp rendered_height(_), do: 0

  defp resolve_fill_widths(children, nil), do: children

  defp resolve_fill_widths(children, parent_width) do
    Enum.map(children, fn child ->
      if child.style.width == :full do
        border_adj =
          if(child.style.border.left, do: 1, else: 0) +
            if child.style.border.right, do: 1, else: 0

        %{child | style: %{child.style | width: max(0, parent_width - border_adj)}}
      else
        child
      end
    end)
  end

  defp resolve_fill_height(child, _display, nil, _used_height), do: child

  defp resolve_fill_height(child, :inline, parent_height, _used_height) do
    if child.style.height == :full do
      border_adj =
        if(child.style.border.top, do: 1, else: 0) +
          if(child.style.border.bottom, do: 1, else: 0)

      %{child | style: %{child.style | height: max(0, parent_height - border_adj)}}
    else
      child
    end
  end

  defp resolve_fill_height(child, :block, parent_height, used_height) do
    if child.position == :absolute or child.style.height != :full do
      child
    else
      border_adj =
        if(child.style.border.top, do: 1, else: 0) +
          if(child.style.border.bottom, do: 1, else: 0)

      %{child | style: %{child.style | height: max(0, parent_height - used_height - border_adj)}}
    end
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

  @doc false
  def join_vertical(items, opts \\ [])

  def join_vertical([], _opts) do
    {"", 0, 0}
  end

  def join_vertical(items, opts) do
    items_with_width =
      Enum.map(items, fn x ->
        max_width =
          String.split(x, "\n") |> Enum.map(&BackBreeze.Utils.string_length(&1)) |> Enum.max()

        {max_width, x}
      end)

    {max_width, _} = Enum.max(items_with_width)

    items =
      items
      |> Enum.join("\n")
      |> String.trim_trailing("\n")
      |> String.split("\n")

    items =
      case Keyword.get(opts, :height) do
        :screen ->
          {_screen_width, screen_height} =
            BackBreeze.screen_dimensions(Keyword.get(opts, :terminal))

          height = screen_height - 2

          # TODO: swap X and Y obviously
          {start_pos, _} = Keyword.get(opts, :scroll, {0, 0})
          end_pos = height + start_pos - 1
          Enum.slice(items, start_pos..end_pos//1)

        height when is_integer(height) ->
          {start_pos, _} = Keyword.get(opts, :scroll, {0, 0})
          end_pos = height + start_pos - 1
          Enum.slice(items, start_pos..end_pos//1)

        _ ->
          items
      end

    {Enum.join(items, "\n"), max_width, length(items)}
  end

  @doc false
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
