defmodule BackBreeze.Box.BlockLayerMapTest do
  use ExUnit.Case, async: false

  alias BackBreeze.Box
  alias BackBreeze.Box.{BlockLayerMap, LayerMap}

  test "scrolled composition does not allocate translated child maps" do
    children =
      for y <- 0..2 do
        %Box{
          width: 4,
          height: 1,
          left: 0,
          top: y,
          layer_map: %{{0, 0} => {to_string(y), ""}, __default_fill__: [{{".", ""}, 0, 0, 3, 0}]}
        }
      end

    box = Box.new(scroll: {1, 0}, style: %{width: 4, height: 2, overflow: :hidden})
    parent = self()

    worker =
      spawn_link(fn ->
        receive do
          :render -> send(parent, {:rendered, BlockLayerMap.compose(children, box)})
        end

        receive do
          :stop -> :ok
        end
      end)

    Code.ensure_loaded!(LayerMap)
    :erlang.trace_pattern({LayerMap, :shift_simple_child, 3}, true, [:local])
    :erlang.trace(worker, true, [:call])

    on_exit(fn ->
      :erlang.trace_pattern({LayerMap, :shift_simple_child, 3}, false, [:local])
      send(worker, :stop)
    end)

    send(worker, :render)
    assert_receive {:rendered, {4, 3, map, fixed}}, 1000
    delivery = :erlang.trace_delivered(worker)
    assert_receive {:trace_delivered, ^worker, ^delivery}

    refute_receive {:trace, ^worker, :call, {LayerMap, :shift_simple_child, _}}
    assert Box.layer_maps_to_content(map, fixed, 4, 2) == "1...\n2..."
  end
end
