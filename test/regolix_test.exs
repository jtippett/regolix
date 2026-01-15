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
end
