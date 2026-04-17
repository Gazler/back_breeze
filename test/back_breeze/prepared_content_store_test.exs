defmodule BackBreeze.PreparedContentStoreTest do
  use ExUnit.Case, async: false

  alias BackBreeze.PreparedContentStore

  setup do
    PreparedContentStore.clear()
    :ok
  end

  test "fetch caches computed values by key" do
    counter = :counters.new(1, [])

    assert PreparedContentStore.fetch(:cached, fn ->
             :counters.add(counter, 1, 1)
             %{content: "value"}
           end) == %{content: "value"}

    assert PreparedContentStore.fetch(:cached, fn ->
             :counters.add(counter, 1, 1)
             %{content: "other"}
           end) == %{content: "value"}

    assert :counters.get(counter, 1) == 1
    assert PreparedContentStore.size() == 1
  end

  test "clear drops entries and resets the access counter" do
    counter = :counters.new(1, [])

    assert PreparedContentStore.fetch(:cached, fn ->
             :counters.add(counter, 1, 1)
             %{content: "value"}
           end) == %{content: "value"}

    assert :ok == PreparedContentStore.clear()

    assert PreparedContentStore.fetch(:cached, fn ->
             :counters.add(counter, 1, 1)
             %{content: "value"}
           end) == %{content: "value"}

    assert :counters.get(counter, 1) == 2
    assert PreparedContentStore.size() == 1
  end

  test "evicts the least recently used entries once it reaches the entry limit" do
    for idx <- 1..32 do
      assert PreparedContentStore.fetch({:key, idx}, fn -> %{content: Integer.to_string(idx)} end) ==
               %{content: Integer.to_string(idx)}
    end

    assert PreparedContentStore.size() == 32

    assert PreparedContentStore.fetch({:key, 1}, fn -> %{content: "new-1"} end) == %{content: "1"}
    assert PreparedContentStore.fetch({:key, 33}, fn -> %{content: "33"} end) == %{content: "33"}

    assert PreparedContentStore.size() == 32
    assert PreparedContentStore.fetch({:key, 1}, fn -> %{content: "new-1"} end) == %{content: "1"}

    assert PreparedContentStore.fetch({:key, 2}, fn -> %{content: "new-2"} end) == %{
             content: "new-2"
           }

    assert PreparedContentStore.fetch({:key, 2}, fn -> %{content: "new-2"} end) == %{
             content: "new-2"
           }

    assert PreparedContentStore.fetch({:key, 34}, fn -> %{content: "34"} end) == %{content: "34"}

    assert PreparedContentStore.size() == 32

    assert PreparedContentStore.fetch({:key, 2}, fn -> %{content: "new-2"} end) == %{
             content: "new-2"
           }

    assert PreparedContentStore.fetch({:key, 3}, fn -> %{content: "new-3"} end) == %{
             content: "new-3"
           }
  end
end
