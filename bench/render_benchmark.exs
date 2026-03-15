Mix.Task.run("app.start")

defmodule BackBreeze.RenderBenchmark do
  alias BackBreeze.Box
  alias BackBreeze.Grid

  @default_iterations 50
  @warmup_iterations 5

  def run(argv) do
    {opts, _argv, _invalid} =
      OptionParser.parse(argv,
        switches: [
          iterations: :integer,
          scenario: :string,
          tree_file: :string,
          width: :integer,
          height: :integer,
          subtree_depth: :integer,
          top: :integer,
          phase_profile: :boolean
        ],
        aliases: [i: :iterations, s: :scenario]
      )

    iterations = Keyword.get(opts, :iterations, @default_iterations)
    filter = Keyword.get(opts, :scenario)
    tree_file = Keyword.get(opts, :tree_file)
    subtree_depth = Keyword.get(opts, :subtree_depth)
    top = Keyword.get(opts, :top, 10)
    phase_profile? = Keyword.get(opts, :phase_profile, false)

    scenarios(tree_file, Keyword.get(opts, :width, 250), Keyword.get(opts, :height, 34))
    |> maybe_filter(filter)
    |> Enum.each(&run_scenario(&1, iterations, subtree_depth, top, phase_profile?))
  end

  defp maybe_filter(scenarios, nil), do: scenarios

  defp maybe_filter(scenarios, filter) do
    Enum.filter(scenarios, fn {name, _size, _builder} -> String.contains?(name, filter) end)
  end

  defp run_scenario({name, size, builder}, iterations, subtree_depth, top, phase_profile?) do
    terminal = %Termite.Terminal{size: %{width: elem(size, 0), height: elem(size, 1)}}
    box = builder.()

    if phase_profile? do
      BackBreeze.BenchProfile.enable!()
      BackBreeze.BenchProfile.reset!()
    else
      BackBreeze.BenchProfile.disable!()
    end

    Enum.each(1..@warmup_iterations, fn _ ->
      Box.render_with_dimensions(box, terminal: terminal)
    end)

    samples =
      Enum.map(1..iterations, fn _ ->
        {us, result} =
          :timer.tc(fn ->
            Box.render_with_dimensions(box, terminal: terminal)
          end)

        {us, result}
      end)

    times = Enum.map(samples, &elem(&1, 0))
    %{box: rendered_box, dimensions: dimensions} = samples |> List.last() |> elem(1)

    IO.puts("")
    IO.puts("#{name} #{elem(size, 0)}x#{elem(size, 1)}")
    IO.puts("  iterations: #{iterations}")
    IO.puts("  avg: #{format_us(avg(times))}")
    IO.puts("  min: #{format_us(Enum.min(times))}")
    IO.puts("  p50: #{format_us(percentile(times, 0.50))}")
    IO.puts("  p95: #{format_us(percentile(times, 0.95))}")
    IO.puts("  max: #{format_us(Enum.max(times))}")
    IO.puts("  content bytes: #{byte_size(rendered_box.content)}")
    IO.puts("  dimensions: #{length(dimensions)}")

    if phase_profile? do
      print_phase_profile()
    end

    if is_integer(subtree_depth) do
      print_subtree_breakdown(box, terminal, iterations, subtree_depth, top)
    end
  end

  defp print_phase_profile do
    IO.puts("  phase profile:")

    BackBreeze.BenchProfile.snapshot()
    |> Enum.sort_by(fn {_label, stats} -> stats.total_us end, :desc)
    |> Enum.each(fn {label, stats} ->
      avg_us = stats.total_us / max(stats.count, 1)
      IO.puts("    #{inspect(label)} total=#{format_us(stats.total_us)} avg=#{format_us(avg_us)} max=#{format_us(stats.max_us)} count=#{stats.count}")
    end)
  end

  defp print_subtree_breakdown(box, terminal, iterations, subtree_depth, top) do
    IO.puts("  subtree breakdown (depth=#{subtree_depth}, top=#{top}):")

    box
    |> subtrees_at_depth(subtree_depth)
    |> Enum.map(fn {path, subtree} ->
      {avg_us, rendered} = measure(subtree, terminal, max(div(iterations, 2), 5))

      %{
        path: Enum.join(path, "."),
        avg_us: avg_us,
        bytes: byte_size(rendered.box.content),
        dims: length(rendered.dimensions),
        children: length(subtree.children),
        display: inspect(subtree.display),
        border?: subtree.style.border != BackBreeze.Border.none(),
        overflow: subtree.style.overflow
      }
    end)
    |> Enum.sort_by(& &1.avg_us, :desc)
    |> Enum.take(top)
    |> Enum.each(fn row ->
      IO.puts(
        "    path=#{row.path} avg=#{format_us(row.avg_us)} bytes=#{row.bytes} dims=#{row.dims} children=#{row.children} display=#{row.display} border=#{row.border?} overflow=#{row.overflow}"
      )
    end)
  end

  defp subtrees_at_depth(box, depth), do: do_subtrees_at_depth(box, depth, [])

  defp do_subtrees_at_depth(box, 0, path), do: [{path, box}]

  defp do_subtrees_at_depth(box, depth, path) do
    box.children
    |> Enum.with_index()
    |> Enum.filter(fn {child, _} -> is_struct(child, BackBreeze.Box) end)
    |> Enum.flat_map(fn {child, index} -> do_subtrees_at_depth(child, depth - 1, path ++ [index]) end)
  end

  defp measure(box, terminal, iterations) do
    Enum.each(1..@warmup_iterations, fn _ ->
      Box.render_with_dimensions(box, terminal: terminal)
    end)

    samples =
      Enum.map(1..iterations, fn _ ->
        :timer.tc(fn -> Box.render_with_dimensions(box, terminal: terminal) end)
      end)

    avg_us = samples |> Enum.map(&elem(&1, 0)) |> avg()
    rendered = samples |> List.last() |> elem(1)
    {avg_us, rendered}
  end

  defp avg(values), do: Enum.sum(values) / max(length(values), 1)

  defp percentile(values, percentile) do
    sorted = Enum.sort(values)
    index = min(max(round((length(sorted) - 1) * percentile), 0), length(sorted) - 1)
    Enum.at(sorted, index)
  end

  defp format_us(us) when is_float(us), do: :erlang.float_to_binary(us / 1_000, decimals: 2) <> "ms"
  defp format_us(us), do: format_us(us * 1.0)

  defp scenarios(nil, _width, _height) do
    [
      {"flat_text", {80, 24}, &flat_text/0},
      {"stacked_blocks", {80, 24}, &stacked_blocks/0},
      {"nested_grid", {80, 24}, &nested_grid/0},
      {"posting_like_small", {80, 24}, &posting_like/0},
      {"posting_like_medium", {120, 36}, &posting_like/0},
      {"posting_like_wide", {250, 36}, &posting_like/0}
    ]
  end

  defp scenarios(tree_file, width, height) do
    [
      {"captured_tree", {width, height}, fn -> load_tree!(tree_file) end}
      | scenarios(nil, width, height)
    ]
  end

  defp flat_text do
    Box.new(
      style: %{border: :rounded, width: :screen, height: :screen},
      content:
        Enum.map_join(1..20, "\n", fn row ->
          "Row #{row} " <> String.duplicate("content ", 6)
        end)
    )
  end

  defp stacked_blocks do
    rows =
      Enum.map(1..12, fn index ->
        Box.new(
          style: %{border: :line, height: 3},
          children: [
            Box.new(content: "Section #{index}", style: %{bold: true}),
            Box.new(content: String.duplicate("value ", 8))
          ]
        )
      end)

    Box.new(
      style: %{border: :rounded, width: :screen, height: :screen},
      children: rows
    )
  end

  defp nested_grid do
    panel = fn title, color ->
      Box.new(
        style: %{border: :line, border_color: color, height: 8},
        children: [
          Box.new(
            style: %{display: %Grid{columns: 2}},
            children: [
              Box.new(content: String.duplicate("left ", 6)),
              Box.new(content: String.duplicate("right ", 6)),
              Box.new(content: String.duplicate("alpha ", 6)),
              Box.new(content: String.duplicate("beta ", 6))
            ]
          ),
          Box.new(
            position: :absolute,
            left: 2,
            top: 0,
            style: %{foreground_color: color},
            content: title
          )
        ]
      )
    end

    Box.new(
      style: %{border: :rounded, width: :screen, height: :screen},
      display: %Grid{columns: 3},
      children: [
        panel.("One", 2),
        panel.("Two", 3),
        panel.("Three", 4),
        panel.("Four", 5),
        panel.("Five", 6),
        panel.("Six", 1)
      ]
    )
  end

  defp posting_like do
    Box.new(
      style: %{width: :screen, height: :screen},
      children: [
        top_bar(),
        Box.new(style: %{height: 1}, content: ""),
        main_grid(),
        footer()
      ]
    )
  end

  defp top_bar do
    Box.new(
      style: %{display: %Grid{columns: 3}, height: 3},
      children: [
        Box.new(
          style: %{background_color: 4, foreground_color: 7, bold: true, width: 10},
          content: " POST   ▼ "
        ),
        Box.new(
          style: %{reverse: true},
          content: " https://jsonplaceholder.typicode.com/posts"
        ),
        Box.new(
          style: %{background_color: 4, foreground_color: 7, bold: true, width: 8},
          content: "  Send  "
        )
      ]
    )
  end

  defp main_grid do
    Box.new(
      style: %{display: %Grid{columns: 2}, height: 19},
      children: [
        collection_panel(),
        right_panels()
      ]
    )
  end

  defp collection_panel do
    entries =
      [
        "GET  echo",
        "POST echo post",
        "▼ jsonplaceholder/",
        "    ▼ posts/",
        "        GET  get all",
        "        GET  get one",
        "        POST create",
        "        DEL  delete a post",
        "    ▼ comments/",
        "        GET  get comments",
        "    ▼ todos/",
        "        GET  get all",
        "        GET  get one",
        "    ▼ users/",
        "        GET  get all"
      ]
      |> Enum.map(&Box.new(content: &1))

    Box.new(
      style: %{border: :rounded, height: 19},
      children: entries ++ [Box.new(content: ""), Box.new(content: "")]
    )
  end

  defp right_panels do
    Box.new(
      style: %{display: %Grid{columns: 1}, height: 19},
      children: [
        request_panel(),
        response_panel()
      ]
    )
  end

  defp request_panel do
    Box.new(
      style: %{border: :rounded, height: 10},
      children: [
        Box.new(content: " Headers  Body  Query  Auth  Info "),
        scroll_like_headers(),
        Box.new(
          style: %{display: %Grid{columns: 3}, height: 2},
          children: [
            Box.new(content: "Name", style: %{width: 8}),
            Box.new(content: "Value input"),
            Box.new(
              content: " Add ",
              style: %{background_color: 7, foreground_color: 0, bold: true, width: 7}
            )
          ]
        )
      ]
    )
  end

  defp scroll_like_headers do
    rows =
      [
        {"Content-Type", "application/json"},
        {"Referer", "https://example.com/"},
        {"Accept-Encoding", "gzip"},
        {"Cache-Control", "no-cache"},
        {"X-Test-Header", "one"},
        {"X-Test-Header", "two"}
      ]
      |> Enum.map(fn {label, value} ->
        Box.new(
          style: %{display: :inline},
          children: [
            Box.new(content: label, style: %{foreground_color: 4, width: 18}),
            Box.new(content: value)
          ]
        )
      end)

    Box.new(
      style: %{height: 7, overflow: :hidden, scrollbar: %{axis: :vertical, arrows: true, show: :always}},
      children: rows
    )
  end

  defp response_panel do
    body =
      [
        "  1  {",
        "  2    \"title\": \"foo\",",
        "  3    \"body\": \"bar\",",
        "  4    \"userId\": 1,",
        "  5    \"id\": 101",
        "  6  }"
      ]
      |> Enum.map(&Box.new(content: &1))

    Box.new(
      style: %{border: :rounded, height: 10},
      children: [Box.new(content: " Body  Headers  Cookies  Trace ", style: %{foreground_color: 4, bold: true}) | body]
    )
  end

  defp footer do
    Box.new(
      style: %{display: :inline, height: 1},
      children: [
        keycap("^j"),
        Box.new(content: "Send"),
        keycap("^t"),
        Box.new(content: "Method"),
        keycap("Tab"),
        Box.new(content: "Next"),
        keycap("F1"),
        Box.new(content: "Help"),
        keycap("q"),
        Box.new(content: "Quit")
      ]
    )
  end

  defp keycap(label) do
    Box.new(
      style: %{background_color: 7, foreground_color: 0, bold: true},
      content: " #{label} "
    )
  end

  defp load_tree!(path) do
    path
    |> File.read!()
    |> :erlang.binary_to_term()
  end
end

BackBreeze.RenderBenchmark.run(System.argv())
