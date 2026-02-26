# BackBreeze

A terminal layout rendering library built on top of [Termite](https://github.com/Gazler/termite)

## Features

 * ANSI colors and text styling
 * text reflowing/overflow
 * text offsets to allow for scrolling
 * optional viewport scrollbars for overflow-hidden regions
 * configurable scrollbar axis/placement/chars/colors/arrows
 * joining text horizontally/vertically
 * grid based rendering
 * absolute positioning

## Scrollbar configuration

```elixir
BackBreeze.Box.new(
  style: %{
    border: :line,
    width: 30,
    height: 8,
    overflow: :hidden,
    scrollbar: %{
      axis: :both,
      show: :auto,
      placement: :end,
      arrows: true,
      thumb: %{char: "▓", foreground_color: 2, bold: true},
      track: %{char: "·", foreground_color: 8}
    }
  },
  scroll: {3, 10},
  children: [BackBreeze.Box.new(content: "...")]
)
```

Supported scrollbar shorthands remain available:
`false | true | :vertical | :horizontal | :both`.

By default, scrollbar thumbs are single-cell and in `:inset` mode they render on the
border gutter when a border exists, preserving content columns.

## Installation

He package can be installed by adding `back_breeze` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:back_breeze, "~> 0.2.0"}
  ]
end
```

## Examples

```elixir
Mix.install([{:back_breeze, "~> 0.2.0"}])

content =
  "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."

child = BackBreeze.Box.new(%{style: %{border: :line, width: 30}, content: content})
box = BackBreeze.Box.new(children: [child]) |> BackBreeze.Box.render()

IO.puts(box.content)

```

More examples are available in the examples directory.

## Documentation

https://hexdocs.pm/back_breeze

Documentation can be generated with ExDoc using:

```sh
mix docs
```
