defmodule BackBreeze.Bench.Navigation do
  @moduledoc false
  alias BackBreeze.Box

  def validate!(opts) do
    opts = Keyword.merge([width: 278, height: 76, items: 250, iterations: 40, warmup: 5], opts)

    for {key, minimum} <- [width: 60, height: 8, items: 1, iterations: 1, warmup: 0] do
      value = Keyword.fetch!(opts, key)

      unless is_integer(value) and value >= minimum,
        do: raise(ArgumentError, "#{key} must be at least #{minimum}")
    end

    opts
  end

  def tree(width, height, count, selected, opts \\ []) do
    panel_height = height - 2
    visible = panel_height - 2
    offset = max(0, min(selected - div(visible, 2), count - visible))

    rows =
      for n <- (offset + 1)..min(count, offset + visible) do
        Box.new(
          children: [
            Box.new(content: if(n == selected, do: ">", else: " "), style: %{width: 2}),
            Box.new(
              content: "Item #{String.pad_leading(to_string(n), 4, "0")}",
              style: %{width: 21}
            ),
            Box.new(content: "ready", style: %{width: 7, foreground_color: 2})
          ],
          display: :inline,
          style: %{width: 32, height: 1, background_color: if(n == selected, do: 4, else: 0)}
        )
      end

    text =
      Enum.map_join(1..visible, "\n", fn n ->
        String.pad_trailing("Line #{n} ", width - 36, "abcdefghij")
      end)

    text_panel =
      if opts[:virtual] do
        source =
          BackBreeze.VirtualText.lazy(
            cache_key: {:benchmark_log, width},
            cache?: false,
            intrinsic_width: width - 36,
            line_count_fn: fn _ -> 10_000 end,
            slice_fn: fn start, count, cols ->
              for n <- (start + 1)..(start + count)//1 do
                label = "Line #{n} "

                [
                  {String.slice(label, 0, cols), %{foreground_color: 2}},
                  {String.duplicate("x", max(cols - String.length(label), 0)), %{foreground_color: 7}}
                ]
              end
            end
          )

        Box.new(
          content: source,
          scroll: {500, 0},
          style: %{
            width: width - 34,
            height: panel_height,
            border: :line,
            overflow: :hidden,
            scrollbar: true
          }
        )
      else
        Box.new(
          content: text,
          style: %{width: width - 34, height: panel_height, border: :line, foreground_color: 7}
        )
      end

    panels =
      Box.new(
        display: %BackBreeze.Grid{columns: 2},
        style: %{width: width, height: panel_height},
        children: [
          Box.new(
            children: rows,
            style: %{width: 34, height: panel_height, border: :line, overflow: :hidden}
          ),
          text_panel
        ]
      )

    Box.new(
      style: %{width: width, height: height, background_color: 0},
      children: [
        Box.new(content: "Navigation benchmark", style: %{height: 1}),
        panels,
        Box.new(content: "Up/Down select | Q quit", style: %{height: 1})
      ]
    )
  end

  def run(opts) do
    opts = validate!(opts)
    terminal = %Termite.Terminal{size: %{width: opts[:width], height: opts[:height]}}
    modes = if opts[:cold], do: [:cold], else: [:navigation, :cold]

    for mode <- modes do
      clear()
      start = min(opts[:items], opts[:height])

      build = fn index ->
        selected = rem(start - 1 + index, opts[:items]) + 1
        tree(opts[:width], opts[:height], opts[:items], selected, opts)
      end

      if opts[:warmup] > 0 do
        for _ <- 1..opts[:warmup], do: Box.render_with_dimensions(build.(0), terminal: terminal)
      end

      samples =
        for index <- 1..opts[:iterations] do
          tree = build.(index)
          if mode == :cold, do: clear()
          {:reductions, before} = Process.info(self(), :reductions)

          {us, %{box: box}} =
            :timer.tc(fn -> Box.render_with_dimensions(tree, terminal: terminal) end)

          {:reductions, after_render} = Process.info(self(), :reductions)
          # Hashing is deliberately outside the measured render.
          digest =
            :crypto.hash(:sha256, :erlang.term_to_binary({box.content, box.width, box.height}))

          {us, after_render - before, digest}
        end

      times = samples |> Enum.map(&elem(&1, 0)) |> Enum.sort()
      percentile = fn p -> Enum.at(times, max(0, ceil(length(times) * p) - 1)) / 1000 end

      digest =
        samples
        |> Enum.map(&elem(&1, 2))
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)

      IO.inspect(
        %{
          mode: mode,
          workload: if(opts[:virtual], do: :virtual_text, else: :plain_text),
          size: {opts[:width], opts[:height]},
          items: opts[:items],
          frames: length(samples),
          median_ms: percentile.(0.5),
          p95_ms: percentile.(0.95),
          mean_reductions: div(Enum.sum(Enum.map(samples, &elem(&1, 1))), length(samples)),
          frame_digest: digest
        },
        label: "navigation benchmark"
      )
    end
  end

  defp clear do
    BackBreeze.RenderCache.clear()
    BackBreeze.PreparedContentStore.clear()
  end
end
