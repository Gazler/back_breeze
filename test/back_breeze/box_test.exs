defmodule BackBreeze.BoxTest do
  use ExUnit.Case, async: true

  describe "render/1" do
    test "renders a single child" do
      child = BackBreeze.Box.new(content: "Hello", style: %{bold: true})
      box = BackBreeze.Box.new(children: [child])
      rendered = BackBreeze.Box.render(box)

      assert rendered.state == :rendered
      assert rendered.content == BackBreeze.Style.bold() |> BackBreeze.Style.render("Hello")
    end

    test "renders a tree of children joined horizontally" do
      child = BackBreeze.Box.new(content: "Hello", style: %{bold: true, foreground_color: 3})
      nested = BackBreeze.Box.new(children: [child], style: %{border: :line})

      world = BackBreeze.Box.new(content: "World", style: %{italic: true})
      box = BackBreeze.Box.new(children: [child, nested, nested, world])
      rendered = BackBreeze.Box.render(box)

      assert rendered.state == :rendered

      assert rendered.content ==
               """
                    ┌─────┐┌─────┐     
                    │\e[1;38;5;3mHello\e[0m││\e[1;38;5;3mHello\e[0m│     
               \e[1;38;5;3mHello\e[0m└─────┘└─────┘\e[3mWorld\e[0m\
               """
    end
  end

  describe "join_horizontal/2" do
    test "joins items with padding" do
      items = ["One line", "Two\nLines", "Three\n+\n+\nLines"]
      {content, 18} = BackBreeze.Box.join_horizontal(items)

      assert content ==
               """
                            Three
                            +    
                       Two  +    
               One lineLinesLines\
               """
    end

    test "aligns lines on the right" do
      items = ["One line", "Two\nLines", "Three\n+\n+\nLines"]
      {content, 18} = BackBreeze.Box.join_horizontal(items, align: :right)

      assert content ==
               """
                            Three
                                +
                         Two    +
               One lineLinesLines\
               """
    end

    test "aligns lines in the center" do
      items = ["One line", "Two\nLines", "Three\n+\n+\nLines"]
      {content, 18} = BackBreeze.Box.join_horizontal(items, align: :center)

      assert content ==
               """
                            Three
                              +  
                        Two   +  
               One lineLinesLines\
               """
    end
  end
end
