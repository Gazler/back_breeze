child = fn x -> BackBreeze.Box.new(%{content: "Hello #{x}"}) end

box = BackBreeze.Box.new(scroll: {1, 0}, style: %{overflow: :hidden, border: :line, width: 30, height: 4}, children: [child.(0), child.(1), child.(2), child.(3), child.(4)]) |> BackBreeze.Box.render()

IO.puts(box.content)
