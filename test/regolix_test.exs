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
      assert Regolix.get_packages(engine) == []

      {:ok, engine} =
        Regolix.add_policy(engine, "test.rego", """
        package test
        default allow = false
        """)

      assert "data.test" in Regolix.get_packages(engine)
    end

    test "can add multiple policies" do
      engine = Regolix.new!()
      engine = Regolix.add_policy!(engine, "authz.rego", "package authz")
      engine = Regolix.add_policy!(engine, "rbac.rego", "package rbac")

      packages = Regolix.get_packages(engine)
      assert "data.authz" in packages
      assert "data.rbac" in packages
    end

    test "returns error for invalid policy" do
      {:ok, engine} = Regolix.new()

      assert {:error, %Regolix.Error{type: :parse_error}} =
               Regolix.add_policy(engine, "bad.rego", "invalid {{{")

      # Verify no package was added
      assert Regolix.get_packages(engine) == []
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

  describe "get_packages/1" do
    test "returns empty list for new engine" do
      engine = Regolix.new!()
      assert Regolix.get_packages(engine) == []
    end

    test "returns loaded package names" do
      engine =
        Regolix.new!()
        |> Regolix.add_policy!("test.rego", "package mypackage")

      assert "data.mypackage" in Regolix.get_packages(engine)
    end
  end
end
