defmodule BackBreeze.StringTest do
  use ExUnit.Case, async: true

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
end
