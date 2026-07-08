Mix.Task.run("app.start")

defmodule BackBreeze.RenderBenchmark do
  alias BackBreeze.Box
  alias BackBreeze.Grid

  @default_iterations 50
  @warmup_iterations 5
  @default_width 250
  @default_height 34

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
          phase_profile: :boolean,
          cold: :boolean,
          warmup: :integer
        ],
        aliases: [i: :iterations, s: :scenario]
      )

    opts = apply_env_defaults(opts)
    maybe_print_usage_summary(argv, opts)

    iterations = Keyword.get(opts, :iterations, @default_iterations)
    filter = Keyword.get(opts, :scenario)
    tree_file = Keyword.get(opts, :tree_file)
    subtree_depth = Keyword.get(opts, :subtree_depth)
    top = Keyword.get(opts, :top, 10)
    phase_profile? = Keyword.get(opts, :phase_profile, false)
    cold? = Keyword.get(opts, :cold, false)
    warmup_iterations = Keyword.get(opts, :warmup, @warmup_iterations)
    width = Keyword.get(opts, :width, @default_width)
    height = Keyword.get(opts, :height, @default_height)

    scenarios(tree_file, width, height)
    |> maybe_filter(filter, width, height)
    |> Enum.each(
      &run_scenario(&1, iterations, subtree_depth, top, phase_profile?, cold?, warmup_iterations)
    )
  end

  defp maybe_print_usage_summary(argv, opts) do
    if argv == [] and no_benchmark_overrides?(opts) do
      IO.puts("""
      render_benchmark.exs usage:
        BACK_BREEZE_TREE_FILE=bench/fixtures/posting_tree.etf BACK_BREEZE_WIDTH=80 BACK_BREEZE_HEIGHT=30 mix run bench/render_benchmark.exs
        BACK_BREEZE_TREE_FILE=bench/fixtures/posting_tree.etf BACK_BREEZE_WIDTH=80 BACK_BREEZE_HEIGHT=30 BACK_BREEZE_ITERATIONS=1 BACK_BREEZE_COLD=1 BACK_BREEZE_WARMUP=0 mix run bench/render_benchmark.exs

      CLI equivalents:
        mix run bench/render_benchmark.exs -- --scenario posting_tree --width 80 --height 30
        mix run bench/render_benchmark.exs -- --tree_file bench/fixtures/posting_tree.etf --width 80 --height 30 --iterations 1 --cold --warmup 0

      Environment variable equivalents:
        BACK_BREEZE_SCENARIO
        BACK_BREEZE_TREE_FILE
        BACK_BREEZE_WIDTH
        BACK_BREEZE_HEIGHT
        BACK_BREEZE_ITERATIONS
        BACK_BREEZE_COLD=1
        BACK_BREEZE_WARMUP=0
        BACK_BREEZE_PHASE_PROFILE=1
        BACK_BREEZE_SUBTREE_DEPTH=3
        BACK_BREEZE_TOP=10
      """)
    end
  end

  defp no_benchmark_overrides?(opts) do
    Enum.all?(
      [
        :iterations,
        :scenario,
        :tree_file,
        :width,
        :height,
        :subtree_depth,
        :top,
        :phase_profile,
        :cold,
        :warmup
      ],
      &(not Keyword.has_key?(opts, &1))
    )
  end

  defp maybe_filter(scenarios, nil, _width, _height), do: scenarios

  defp maybe_filter(scenarios, filter, width, height) do
    cond do
      File.exists?(filter) ->
        [{fixture_name(filter), {width, height}, fn -> load_tree!(filter) end}]

      File.exists?(fixture_path(filter)) ->
        path = fixture_path(filter)
        [{fixture_name(path), {width, height}, fn -> load_tree!(path) end}]

      true ->
        Enum.filter(scenarios, fn {name, _size, _builder} -> String.contains?(name, filter) end)
    end
  end

  defp run_scenario(
         {name, size, builder},
         iterations,
         subtree_depth,
         top,
         phase_profile?,
         cold?,
         warmup_iterations
       ) do
    terminal = %Termite.Terminal{size: %{width: elem(size, 0), height: elem(size, 1)}}
    box = builder.()

    if phase_profile? do
      BackBreeze.BenchProfile.enable!()
      BackBreeze.BenchProfile.reset!()
    else
      BackBreeze.BenchProfile.disable!()
    end

    warmup(box, terminal, cold?, warmup_iterations)

    {times, %{box: rendered_box, dimensions: dimensions}} =
      Enum.reduce(1..iterations, {[], nil}, fn _, {times, _last_result} ->
        maybe_reset_caches(cold?)

        {us, result} =
          :timer.tc(fn ->
            Box.render_with_dimensions(box, terminal: terminal)
          end)

        {[us | times], result}
      end)

    times = Enum.reverse(times)

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
      print_subtree_breakdown(
        box,
        terminal,
        iterations,
        subtree_depth,
        top,
        cold?,
        warmup_iterations
      )
    end
  end

  defp print_phase_profile do
    IO.puts("  phase profile:")

    BackBreeze.BenchProfile.snapshot()
    |> Enum.sort_by(fn {_label, stats} -> stats.total_us end, :desc)
    |> Enum.each(fn {label, stats} ->
      avg_us = stats.total_us / max(stats.count, 1)

      IO.puts(
        "    #{inspect(label)} total=#{format_us(stats.total_us)} avg=#{format_us(avg_us)} max=#{format_us(stats.max_us)} count=#{stats.count}"
      )
    end)
  end

  defp print_subtree_breakdown(
         box,
         terminal,
         iterations,
         subtree_depth,
         top,
         cold?,
         warmup_iterations
       ) do
    IO.puts("  subtree breakdown (depth=#{subtree_depth}, top=#{top}):")

    box
    |> subtrees_at_depth(subtree_depth)
    |> Enum.map(fn {path, subtree} ->
      {avg_us, rendered} =
        measure(subtree, terminal, max(div(iterations, 2), 5), cold?, warmup_iterations)

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
    |> Enum.flat_map(fn {child, index} ->
      do_subtrees_at_depth(child, depth - 1, path ++ [index])
    end)
  end

  defp measure(box, terminal, iterations, cold?, warmup_iterations) do
    warmup(box, terminal, cold?, warmup_iterations)

    samples =
      Enum.map(1..iterations, fn _ ->
        maybe_reset_caches(cold?)
        :timer.tc(fn -> Box.render_with_dimensions(box, terminal: terminal) end)
      end)

    avg_us = samples |> Enum.map(&elem(&1, 0)) |> avg()
    rendered = samples |> List.last() |> elem(1)
    {avg_us, rendered}
  end

  defp avg(values), do: Enum.sum(values) / max(length(values), 1)

  defp warmup(_box, _terminal, _cold?, warmup_iterations) when warmup_iterations <= 0, do: :ok

  defp warmup(box, terminal, cold?, warmup_iterations) do
    Enum.each(1..warmup_iterations, fn _ ->
      maybe_reset_caches(cold?)
      Box.render_with_dimensions(box, terminal: terminal)
    end)
  end

  defp maybe_reset_caches(true) do
    BackBreeze.RenderCache.clear()
    BackBreeze.PreparedContentStore.clear()
  end

  defp maybe_reset_caches(false), do: :ok

  defp percentile(values, percentile) do
    sorted = Enum.sort(values)
    index = min(max(round((length(sorted) - 1) * percentile), 0), length(sorted) - 1)
    Enum.at(sorted, index)
  end

  defp format_us(us) when is_float(us),
    do: :erlang.float_to_binary(us / 1_000, decimals: 2) <> "ms"

  defp format_us(us), do: format_us(us * 1.0)

  defp apply_env_defaults(opts) do
    opts
    |> put_env_integer(:iterations, "BACK_BREEZE_ITERATIONS")
    |> put_env_string(:scenario, "BACK_BREEZE_SCENARIO")
    |> put_env_string(:tree_file, "BACK_BREEZE_TREE_FILE")
    |> put_env_integer(:width, "BACK_BREEZE_WIDTH")
    |> put_env_integer(:height, "BACK_BREEZE_HEIGHT")
    |> put_env_integer(:subtree_depth, "BACK_BREEZE_SUBTREE_DEPTH")
    |> put_env_integer(:top, "BACK_BREEZE_TOP")
    |> put_env_boolean(:phase_profile, "BACK_BREEZE_PHASE_PROFILE")
    |> put_env_boolean(:cold, "BACK_BREEZE_COLD")
    |> put_env_integer(:warmup, "BACK_BREEZE_WARMUP")
  end

  defp put_env_integer(opts, key, env_name) do
    case {Keyword.has_key?(opts, key), System.get_env(env_name)} do
      {true, _} ->
        opts

      {false, nil} ->
        opts

      {false, value} ->
        case Integer.parse(value) do
          {parsed, ""} -> Keyword.put(opts, key, parsed)
          _ -> opts
        end
    end
  end

  defp put_env_string(opts, key, env_name) do
    case {Keyword.has_key?(opts, key), System.get_env(env_name)} do
      {true, _} -> opts
      {false, nil} -> opts
      {false, value} when value != "" -> Keyword.put(opts, key, value)
      {false, _} -> opts
    end
  end

  defp put_env_boolean(opts, key, env_name) do
    case {Keyword.has_key?(opts, key), System.get_env(env_name)} do
      {true, _} ->
        opts

      {false, value} when value in ["1", "true", "TRUE", "yes", "YES"] ->
        Keyword.put(opts, key, true)

      {false, _} ->
        opts
    end
  end

  defp scenarios(nil, _width, _height) do
    [
      {"flat_text", {80, 24}, &flat_text/0},
      {"stacked_blocks", {80, 24}, &stacked_blocks/0},
      {"nested_grid", {80, 24}, &nested_grid/0},
      {"posting_like_small", {80, 24}, &posting_like/0},
      {"posting_like_medium", {120, 36}, &posting_like/0},
      {"posting_like_wide", {250, 36}, &posting_like/0},
      {"large_styled_list", {240, 80}, &large_styled_list/0}
    ]
  end

  defp scenarios(tree_file, width, height) do
    [
      {fixture_name(tree_file), {width, height}, fn -> load_tree!(tree_file) end}
    ]
  end

  defp fixture_name(path) do
    path
    |> Path.basename(".etf")
  end

  defp fixture_path(name) do
    base =
      if String.ends_with?(name, ".etf") do
        name
      else
        name <> ".etf"
      end

    Path.join("bench/fixtures", base)
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

  defp large_styled_list do
    Box.new(
      style: %{width: :screen, height: :screen},
      children: [
        Box.new(
          style: %{display: :inline, height: 3},
          children: [
            Box.new(content: " Hex.pm package browser ", style: %{bold: true, width: 32}),
            Box.new(content: "Search   ecto, phoenix, live_view", style: %{width: 80}),
            Box.new(content: "100 packages", style: %{width: 20, foreground_color: 8})
          ]
        ),
        Box.new(
          style: %{display: %Grid{columns: 2}, height: 74},
          children: [
            package_list_panel(),
            package_detail_panel()
          ]
        ),
        Box.new(
          style: %{display: :inline, height: 1},
          children: [
            keycap("/"),
            Box.new(content: "Search  "),
            keycap("Enter"),
            Box.new(content: "Run  "),
            keycap("g"),
            Box.new(content: "Open  "),
            keycap("q"),
            Box.new(content: "Quit")
          ]
        )
      ]
    )
  end

  defp package_list_panel do
    rows =
      Enum.map(1..100, fn index ->
        selected? = index == 23

        Box.new(
          style: %{
            display: :inline,
            height: 1,
            width: :full,
            background_color: if(selected?, do: 4, else: 0),
            foreground_color: if(selected?, do: 0, else: 7)
          },
          children: [
            Box.new(content: if(selected?, do: ">", else: " "), style: %{width: 1}),
            Box.new(
              content: package_name(index),
              style: %{width: 24, bold: true}
            ),
            Box.new(
              content: "#{rem(index, 9) + 1}.#{rem(index, 17)}.#{rem(index, 23)}",
              style: %{width: 12}
            ),
            Box.new(
              content: format_downloads(index * 123_456),
              style: %{width: 14, foreground_color: 5}
            )
          ]
        )
      end)

    Box.new(
      style: %{border: :rounded, height: 74, background_color: 0, overflow: :hidden},
      children: [
        Box.new(content: "Packages", style: %{bold: true, height: 1}),
        Box.new(
          style: %{display: :inline, height: 1, foreground_color: 8},
          children: [
            Box.new(content: "Name", style: %{width: 25}),
            Box.new(content: "Latest", style: %{width: 12}),
            Box.new(content: "Downloads", style: %{width: 14})
          ]
        ),
        Box.new(
          style: %{
            height: 70,
            overflow: :hidden,
            scrollbar: %{axis: :vertical, arrows: true, show: :always}
          },
          children: rows
        )
      ]
    )
  end

  defp package_detail_panel do
    Box.new(
      style: %{border: :rounded, height: 74, background_color: 0, overflow: :hidden},
      children: [
        Box.new(content: "Package", style: %{bold: true, height: 1}),
        Box.new(
          style: %{display: :inline, height: 2},
          children: [
            Box.new(content: "postgrex", style: %{width: 28, bold: true, foreground_color: 4}),
            Box.new(content: "1.0.0", style: %{width: 14, foreground_color: 5}),
            Box.new(content: "2.8m downloads", style: %{width: 30, foreground_color: 8})
          ]
        ),
        Box.new(content: " Overview  Releases  Links ", style: %{height: 1, foreground_color: 4}),
        Box.new(content: "PostgreSQL driver for Elixir.", style: %{height: 2}),
        detail_field("Latest", "1.0.0"),
        detail_field("License", "Apache-2.0"),
        detail_field("Updated", "2026-05-12"),
        detail_field("Published", "2014-04-22"),
        detail_field("Docs", "https://postgrex.hexdocs.pm/"),
        detail_field("Hex", "https://hex.pm/packages/postgrex")
      ]
    )
  end

  defp detail_field(label, value) do
    Box.new(
      style: %{display: :inline, height: 1},
      children: [
        Box.new(content: label, style: %{width: 12, foreground_color: 8}),
        Box.new(content: value)
      ]
    )
  end

  defp package_name(index) do
    names =
      ~w(jason certifi idna parse_trans hackney ssl_verify_fun unicode_util_compat mimerl metrics gettext plug ranch telemetry mime decimal plug_crypto phoenix db_connection cowboy ecto tzdata plug_cowboy postgrex phoenix_pubsub timex httpoison ecto_sql poison combine jose nimble_parsec connection cowlib recon ex_doc excoveralls makeup makeup_elixir dialyxir credo prometheus bunt poolboy phoenix_html file_system phoenix_ecto junit_formatter erlex ex_machina verl erlsom elixir_make msgpax sentry xml_builder optimal castore jsx)

    base = Enum.at(names, rem(index - 1, length(names)))

    if index > length(names), do: "#{base}_#{index}", else: base
  end

  defp format_downloads(value) when value >= 1_000_000,
    do: "#{Float.round(value / 1_000_000, 1)}m"

  defp format_downloads(value) when value >= 1_000,
    do: "#{Float.round(value / 1_000, 1)}k"

  defp format_downloads(value), do: Integer.to_string(value)

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
      style: %{
        height: 7,
        overflow: :hidden,
        scrollbar: %{axis: :vertical, arrows: true, show: :always}
      },
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
      children: [
        Box.new(
          content: " Body  Headers  Cookies  Trace ",
          style: %{foreground_color: 4, bold: true}
        )
        | body
      ]
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
