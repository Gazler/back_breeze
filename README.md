# BackBreeze

A terminal layout rendering library built on top of [Termite](https://github.com/Gazler/termite)

## Features

 * ANSI colors and text styling
 * text reflowing/overflow
 * text offsets to allow for scrolling
 * optional viewport scrollbars for overflow-hidden regions
 * joining text horizontally/vertically
 * grid based rendering
 * absolute positioning

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
