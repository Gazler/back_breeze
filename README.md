# BackBreeze

BackBreeze is a terminal layout and rendering library for Elixir. It builds
styled boxes, grids, overlays, and scrollable regions, then renders them to text
for output through [Termite](https://github.com/gazler/termite) or plain
`IO.puts/1`.

It is intended for terminal UIs that need predictable layout without carrying a
full widget framework.

## Breeze

For a full TUI framework, see [Breeze](https://github.com/gazler/breeze).
Breeze is a LiveView-inspired TUI library built on Termite and BackBreeze, with
views, components, templates, events, and common UI blocks.

Documentation is available at https://breeze.hexdocs.pm.

## Installation

Add `back_breeze` to your dependencies:

```elixir
def deps do
  [
    {:back_breeze, "~> 0.4.0"}
  ]
end
```

## Example

```elixir
Mix.install([{:back_breeze, "~> 0.4.0"}])

box =
  BackBreeze.Box.new(
    style: %{border: :rounded, width: 40, padding: 1},
    children: [
      BackBreeze.Box.new(
        style: %{foreground_color: 4, bold: true},
        content: "BackBreeze"
      ),
      BackBreeze.Box.new(
        content: "Boxes can contain text, styled children, and layout rules."
      )
    ]
  )
  |> BackBreeze.Box.render()

IO.puts(box.content)
```

## What It Provides

BackBreeze keeps the public surface small. Most rendering starts with
`BackBreeze.Box.new/1` and ends with `BackBreeze.Box.render/2`.

The default render cache is bounded in bytes at runtime. Its limit is 70% of
the memory reported as available by OTP's memory supervisor when BackBreeze
starts, up to 1 GiB. Set an explicit limit when automatic detection is not
appropriate:

```elixir
config :back_breeze, render_cache_max_memory_bytes: 32 * 1_024 * 1_024
```

Core layout features include:

* borders, padding, colors, and text styling
* text spans for mixed styling within shared text layout
* virtual text sources for lazy or viewport-oriented content
* automatic text wrapping and overflow handling
* inline, block, absolute, and fixed positioning
* grid layout with rows, columns, and gaps
* scroll offsets and optional scrollbars for clipped regions
* dimension tracking for higher-level viewport handling

See the `examples/` directory for focused examples of boxes, grids, overflow,
scrollbars, absolute positioning, repeated fills, and fullscreen rendering.

## Documentation

API documentation is available on HexDocs:

https://back-breeze.hexdocs.pm

You can also generate the documentation locally:

```sh
mix docs
```
