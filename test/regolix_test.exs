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

  describe "set_input/2" do
    test "sets input from Elixir map" do
      {:ok, engine} = Regolix.new()
      {:ok, engine} = Regolix.set_input(engine, %{"user" => "alice", "roles" => ["admin"]})
      assert is_reference(engine)
    end

    test "handles nested data structures" do
      {:ok, engine} = Regolix.new()

      {:ok, engine} =
        Regolix.set_input(engine, %{
          "request" => %{
            "method" => "GET",
            "path" => "/api/users"
          }
        })

      assert is_reference(engine)
    end

    test "returns error for non-encodable input" do
      {:ok, engine} = Regolix.new()
      # PIDs cannot be JSON encoded
      assert {:error, %Regolix.Error{type: :json_error}} =
               Regolix.set_input(engine, %{"pid" => self()})
    end
  end

  describe "set_input!/2" do
    test "returns engine directly" do
      engine = Regolix.new!()
      engine = Regolix.set_input!(engine, %{"user" => "bob"})
      assert is_reference(engine)
    end

    test "raises for non-encodable input" do
      engine = Regolix.new!()

      assert_raise Regolix.Error, ~r/json_error/, fn ->
        Regolix.set_input!(engine, %{"pid" => self()})
      end
    end
  end

  describe "add_data/2" do
    test "adds data document" do
      {:ok, engine} = Regolix.new()

      {:ok, engine} =
        Regolix.add_data(engine, %{
          "users" => %{
            "alice" => %{"role" => "admin"},
            "bob" => %{"role" => "viewer"}
          }
        })

      assert is_reference(engine)
    end

    test "returns error for non-encodable data" do
      {:ok, engine} = Regolix.new()

      assert {:error, %Regolix.Error{type: :json_error}} =
               Regolix.add_data(engine, %{"pid" => self()})
    end
  end

  describe "add_data!/2" do
    test "returns engine directly" do
      engine = Regolix.new!()
      engine = Regolix.add_data!(engine, %{"config" => %{"enabled" => true}})
      assert is_reference(engine)
    end

    test "raises for non-encodable data" do
      engine = Regolix.new!()

      assert_raise Regolix.Error, ~r/json_error/, fn ->
        Regolix.add_data!(engine, %{"pid" => self()})
      end
    end
  end

  describe "eval_query/2" do
    test "evaluates a simple boolean rule" do
      {:ok, engine} = Regolix.new()

      {:ok, engine} =
        Regolix.add_policy(engine, "test.rego", """
        package test
        default allow = false
        allow if input.user == "admin"
        """)

      {:ok, engine} = Regolix.set_input(engine, %{"user" => "admin"})
      assert {:ok, true} = Regolix.eval_query(engine, "data.test.allow")
    end

    test "returns false when rule doesn't match" do
      {:ok, engine} = Regolix.new()

      {:ok, engine} =
        Regolix.add_policy(engine, "test.rego", """
        package test
        default allow = false
        allow if input.user == "admin"
        """)

      {:ok, engine} = Regolix.set_input(engine, %{"user" => "guest"})
      assert {:ok, false} = Regolix.eval_query(engine, "data.test.allow")
    end

    test "returns :undefined for non-existent rule" do
      {:ok, engine} = Regolix.new()

      {:ok, engine} =
        Regolix.add_policy(engine, "test.rego", """
        package test
        """)

      assert {:ok, :undefined} = Regolix.eval_query(engine, "data.test.nonexistent")
    end

    test "returns complex data structures" do
      {:ok, engine} = Regolix.new()

      {:ok, engine} =
        Regolix.add_policy(engine, "test.rego", """
        package test
        user := {"name": "alice", "roles": ["admin", "user"]}
        """)

      {:ok, result} = Regolix.eval_query(engine, "data.test.user")
      assert result["name"] == "alice"
      assert result["roles"] == ["admin", "user"]
    end

    test "verifies set_input actually sets input" do
      engine =
        Regolix.new!()
        |> Regolix.add_policy!("test.rego", """
        package test
        username := input.user
        """)
        |> Regolix.set_input!(%{"user" => "alice"})

      assert {:ok, "alice"} = Regolix.eval_query(engine, "data.test.username")
    end

    test "verifies add_data actually adds data" do
      engine =
        Regolix.new!()
        |> Regolix.add_policy!("test.rego", """
        package test
        admin_role := data.users.alice.role
        """)
        |> Regolix.add_data!(%{"users" => %{"alice" => %{"role" => "admin"}}})

      assert {:ok, "admin"} = Regolix.eval_query(engine, "data.test.admin_role")
    end

    test "returns error for invalid query" do
      {:ok, engine} = Regolix.new()
      assert {:error, %Regolix.Error{type: :eval_error}} = Regolix.eval_query(engine, "invalid[[")
    end
  end

  describe "eval_query!/2" do
    test "returns result directly" do
      {:ok, engine} = Regolix.new()

      {:ok, engine} =
        Regolix.add_policy(engine, "test.rego", """
        package test
        result := 42
        """)

      assert 42 = Regolix.eval_query!(engine, "data.test.result")
    end

    test "raises on error" do
      {:ok, engine} = Regolix.new()

      assert_raise Regolix.Error, ~r/eval_error/, fn ->
        Regolix.eval_query!(engine, "invalid[[")
      end
    end
  end

  describe "clear_data/1" do
    test "clears data but keeps policies" do
      {:ok, engine} = Regolix.new()

      {:ok, engine} =
        Regolix.add_policy(engine, "test.rego", """
        package test
        result := data.config.value
        """)

      {:ok, engine} = Regolix.add_data(engine, %{"config" => %{"value" => 42}})
      assert {:ok, 42} = Regolix.eval_query(engine, "data.test.result")

      {:ok, engine} = Regolix.clear_data(engine)
      assert {:ok, :undefined} = Regolix.eval_query(engine, "data.test.result")

      # Verify policy still works after clear
      assert "data.test" in Regolix.get_packages(engine)
    end
  end

  describe "clear_data!/1" do
    test "returns engine directly" do
      engine = Regolix.new!()
      engine = Regolix.clear_data!(engine)
      assert is_reference(engine)
    end
  end

  describe "integration" do
    test "complete authorization workflow" do
      # Create engine and add policy
      engine =
        Regolix.new!()
        |> Regolix.add_policy!("authz.rego", """
        package authz

        default allow = false

        allow if {
          input.method == "GET"
          input.path == "/public"
        }

        allow if {
          input.user.role == "admin"
        }

        allow if {
          input.user.role == "viewer"
          input.method == "GET"
        }
        """)

      # Test public access
      engine = Regolix.set_input!(engine, %{"method" => "GET", "path" => "/public"})
      assert Regolix.eval_query!(engine, "data.authz.allow") == true

      # Test admin access
      engine = Regolix.set_input!(engine, %{"user" => %{"role" => "admin"}, "method" => "DELETE"})
      assert Regolix.eval_query!(engine, "data.authz.allow") == true

      # Test viewer read access
      engine = Regolix.set_input!(engine, %{"user" => %{"role" => "viewer"}, "method" => "GET"})
      assert Regolix.eval_query!(engine, "data.authz.allow") == true

      # Test viewer write denied
      engine = Regolix.set_input!(engine, %{"user" => %{"role" => "viewer"}, "method" => "POST"})
      assert Regolix.eval_query!(engine, "data.authz.allow") == false
    end

    test "data-driven policy evaluation" do
      engine =
        Regolix.new!()
        |> Regolix.add_policy!("rbac.rego", """
        package rbac

        default allow = false

        allow if {
          some permission in data.users[input.user_id].permissions
          permission == input.permission
        }
        """)
        |> Regolix.add_data!(%{
          "users" => %{
            "u1" => %{"name" => "Alice", "permissions" => ["read", "write"]},
            "u2" => %{"name" => "Bob", "permissions" => ["read"]}
          }
        })

      # Alice can write
      engine = Regolix.set_input!(engine, %{"user_id" => "u1", "permission" => "write"})
      assert Regolix.eval_query!(engine, "data.rbac.allow") == true

      # Bob cannot write
      engine = Regolix.set_input!(engine, %{"user_id" => "u2", "permission" => "write"})
      assert Regolix.eval_query!(engine, "data.rbac.allow") == false

      # Bob can read
      engine = Regolix.set_input!(engine, %{"user_id" => "u2", "permission" => "read"})
      assert Regolix.eval_query!(engine, "data.rbac.allow") == true
    end

    test "pipeline-style API" do
      result =
        Regolix.new!()
        |> Regolix.add_policy!("calc.rego", """
        package calc
        doubled := input.value * 2
        """)
        |> Regolix.set_input!(%{"value" => 21})
        |> Regolix.eval_query!("data.calc.doubled")

      assert result == 42
    end
  end
end
