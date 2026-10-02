defmodule BackBreeze.Integration.GridCacheTest do
  use ExUnit.Case, async: false

  alias BackBreeze.Box
  alias BackBreeze.Grid
  alias BackBreeze.RenderCache

  setup do
    RenderCache.clear()
    :ok
  end

  test "auto-height grids retain their last row before the following sibling" do
    grid =
      Box.new(
        children:
          for(
            _ <- 1..3,
            do: Box.new(content: "Panel", style: %{width: 20, height: 5, border: :line})
          ),
        style: %{width: 60},
        display: %Grid{columns: 3}
      )

    box = Box.new(children: [grid, Box.new(content: "After")], style: %{width: 80, height: 24})

    for render <- [&Box.render_with_dimensions/1, &Box.render_structured_with_dimensions/1] do
      %{box: result} = render.(box)

      lines =
        (result.content ||
           Box.layer_maps_to_content(
             result.layer_map,
             result.fixed_layer_map,
             result.width,
             result.height
           ))
        |> String.split("\n")

      assert Enum.at(lines, 4) =~ "└──────────────────┘└──────────────────┘└──────────────────┘"
      assert Enum.at(lines, 5) =~ "After"
    end
  end

  test "structured grids defer terminal text serialization to the outer render" do
    box =
      Box.new(
        children: [Box.new(content: "deferred", style: %{width: 12, height: 2})],
        style: %{width: 12, height: 2},
        display: %Grid{columns: 1}
      )

    parent = self()

    worker =
      spawn_link(fn ->
        receive do
          :render ->
            result = Box.render_structured_with_dimensions(box)
            Box.render_with_dimensions(box)
            send(parent, {:rendered, result})
        end

        receive do
          :stop -> :ok
        end
      end)

    Code.ensure_loaded!(Grid)
    :erlang.trace_pattern({Grid, :render_with_dimensions, 4}, true, [:local])
    :erlang.trace(worker, true, [:call])

    on_exit(fn ->
      :erlang.trace_pattern({Grid, :render_with_dimensions, 4}, false, [:local])
      send(worker, :stop)
    end)

    send(worker, :render)
    assert_receive {:rendered, %{box: rendered}}, 1000
    delivery = :erlang.trace_delivered(worker)
    assert_receive {:trace_delivered, ^worker, ^delivery}
    refute_receive {:trace, ^worker, :call, {Grid, :render_with_dimensions, _}}
    assert rendered.width == 12
    assert rendered.height == 2

    assert Box.layer_maps_to_content(rendered.layer_map, rendered.fixed_layer_map, 12, 2) ==
             "deferred    \n            "
  end

  test "grid child renders are cached per terminal size" do
    child =
      Box.new(
        children: [
          Box.new(content: "X", style: %{border: :line, width: :screen})
        ]
      )

    box =
      Box.new(
        children: [child],
        style: %{width: 10, height: 3},
        display: %Grid{columns: 1}
      )

    small =
      Box.render(box, terminal: %Termite.Terminal{size: %{width: 12, height: 8}})

    large =
      Box.render(box, terminal: %Termite.Terminal{size: %{width: 16, height: 8}})

    assert small.content ==
             """
             ┌────────┐
             │X       │
             └────────┘\
             """

    assert large.content ==
             """
             ┌────────┐
             │X       │
             └────────┘\
             """
  end
end
