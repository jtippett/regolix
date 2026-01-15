defmodule RegolixTest do
  use ExUnit.Case

  describe "new/0" do
    test "creates a new engine" do
      assert {:ok, engine} = Regolix.new()
      assert is_reference(engine)
    end
  end

  describe "new!/0" do
    test "returns engine directly" do
      engine = Regolix.new!()
      assert is_reference(engine)
    end
  end

  describe "add_policy/3" do
    test "adds a valid policy" do
      {:ok, engine} = Regolix.new()

      {:ok, engine2} =
        Regolix.add_policy(engine, "test.rego", """
        package test
        default allow = false
        """)

      assert is_reference(engine2)
    end

    test "returns error for invalid policy" do
      {:ok, engine} = Regolix.new()

      assert {:error, %Regolix.Error{type: :parse_error}} =
               Regolix.add_policy(engine, "bad.rego", "invalid {{{")
    end
  end

  describe "add_policy!/3" do
    test "returns engine for valid policy" do
      engine = Regolix.new!()

      engine2 =
        Regolix.add_policy!(engine, "test.rego", """
        package test
        """)

      assert is_reference(engine2)
    end

    test "raises for invalid policy" do
      engine = Regolix.new!()

      assert_raise Regolix.Error, ~r/parse_error/, fn ->
        Regolix.add_policy!(engine, "bad.rego", "invalid {{{")
      end
    end
  end
end
