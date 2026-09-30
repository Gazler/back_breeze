# Rendering benchmarks

Run from the BackBreeze checkout after fetching its dependencies.

## Fullscreen navigation

```sh
mix run bench/navigation_benchmark.exs --width 278 --height 76 --items 250 --iterations 40
```

This synthetic workload uses only BackBreeze: a header, footer, windowed list
of multi-box rows, and a dense text panel in a two-column grid. Selection and
the visible list window advance each frame. Only visible rows are constructed;
this measures rendering, not a virtual-list implementation. It needs no Breeze,
Phoenix, application data, network services, or captured fixtures.

It reports median/p95 render milliseconds, mean BEAM reductions, and a SHA-256
digest of all output frames and dimensions. Tree construction, cache clearing,
and hashing are outside the measurement; layout, composition, and ANSI generation
are included. Terminal writes and higher-level view expansion are not included,
so these numbers are not directly comparable to end-to-end TUI timings.

Two modes run sequentially:

- `navigation`: caches persist while selection changes, allowing reuse of the
  unchanged text panel and rows. The initial frame is warmed five times.
- `cold`: both render and prepared-content caches are cleared before every frame.

Use `--cold` to run only cold frames, `--warmup 0` to disable warmup, and
`--width`/`--height` to test other sizes (minimum 60×8). More iterations than
items will revisit selections, so keep iterations below the item count when
investigating first-visit performance.

Use `--virtual` to replace the binary text panel with uncached, lazy styled
`VirtualText`, scrolled into a 10,000-line source with a scrollbar:

```sh
mix run bench/navigation_benchmark.exs --virtual --width 278 --height 76
```

This exercises a terminal-like styled viewport that is regenerated each frame,
rather than a reusable plain-text panel. Run both workloads when evaluating
renderer changes; neither includes Breeze event handling or terminal transport.

## Existing static-tree benchmark

```sh
mix run bench/render_benchmark.exs -- --width 278 --height 76 --iterations 40 --cold
```

The existing runner covers static scenarios, captured trees, subtree profiling,
and optional phase profiling. Navigation uses changing trees instead of repeatedly
rendering one cached frame. Leave profiling off when collecting timing baselines.
