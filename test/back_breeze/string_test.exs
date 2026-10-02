defmodule BackBreeze.StringTest do
  use ExUnit.Case, async: true

  test "already fitting ASCII lines avoid per-character wrapping" do
    text = Enum.map_join(1..72, "\n", fn _ -> String.duplicate("x", 242) end)
    BackBreeze.String.reflow("warm", 242)
    {:reductions, before} = Process.info(self(), :reductions)
    assert BackBreeze.String.reflow(text, 242) == text
    {:reductions, after_render} = Process.info(self(), :reductions)
    assert after_render - before < byte_size(text) * 3
  end

  test "reflow work grows linearly for long styled words" do
    cost = fn size ->
      input = "\e[32m" <> String.duplicate("x", size) <> "\e[0m"
      {:reductions, before} = Process.info(self(), :reductions)
      assert BackBreeze.String.reflow(input, size) == input
      {:reductions, after_render} = Process.info(self(), :reductions)
      after_render - before
    end

    cost.(100)
    small = cost.(2000)
    large = cost.(4000)
    assert large < small * 3
  end

  describe "reflow/3 by word" do
    test "simple line" do
      string = String.duplicate("hello world ", 5)

      assert BackBreeze.String.reflow(string, 11) == """
             hello world
             hello world
             hello world
             hello world
             hello world
             """
    end

    test "reflowing with line breaks" do
      string = String.duplicate("helloworld\n", 5)

      assert BackBreeze.String.reflow(string, 11) == """
             helloworld
             helloworld
             helloworld
             helloworld
             helloworld
             """
    end

    test "variable word length" do
      string = String.duplicate("this is a variable length line ", 3)

      assert BackBreeze.String.reflow(string, 14) == """
             this is a 
             variable 
             length line 
             this is a 
             variable 
             length line 
             this is a 
             variable 
             length line \
             """
    end

    test "word too long for line" do
      string = String.duplicate("this is a longlonglong length line ", 3)

      assert BackBreeze.String.reflow(string, 10) == """
             this is a 
             longlonglo
             ng length 
             line this 
             is a 
             longlonglo
             ng length 
             line this 
             is a 
             longlonglo
             ng length 
             line \
             """
    end
  end

  describe "truncate/2" do
    test "truncates a string to the given width" do
      assert BackBreeze.String.truncate("hello world", 5) == "hello"
    end

    test "does not truncate if the string fits within the width" do
      assert BackBreeze.String.truncate("hello", 10) == "hello"
    end

    test "does not truncate if the string exactly fills the width" do
      assert BackBreeze.String.truncate("hello", 5) == "hello"
    end

    test "accounts for wide characters" do
      # 🍏 is 2 columns wide, so width 4 fits exactly 2
      assert BackBreeze.String.truncate("🍏🍏🍏", 4) == "🍏🍏"
    end
  end

  describe "reflow/3 by char" do
    test "outputs a stream of characters broken by the width boundary" do
      string = String.duplicate("this is a variable length line ", 3)

      assert BackBreeze.String.reflow(string, 14, break: :char) == """
             this is a vari
             able length li
             ne this is a v
             ariable length
              line this is 
             a variable len
             gth line \
             """
    end
  end

  describe "reflow/3 with ANSI escape sequences" do
    test "wraps by visible width, ignoring escape sequence characters" do
      assert BackBreeze.String.reflow("\e[31mhello\e[0m world", 5) == "\e[31mhello\e[0m\nworld"
    end
  end
end
