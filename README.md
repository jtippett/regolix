# Regolix

Elixir wrapper for [Regorus](https://github.com/microsoft/regorus), a fast Rego policy engine written in Rust.

## Installation

Add `regolix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:regolix, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
# Create a new engine
{:ok, engine} = Regolix.new()

# Add a policy
{:ok, engine} = Regolix.add_policy(engine, "authz.rego", """
  package authz
  default allow = false
  allow if input.user == "admin"
""")

# Set input data
{:ok, engine} = Regolix.set_input(engine, %{"user" => "admin"})

# Evaluate a query
{:ok, true} = Regolix.eval_query(engine, "data.authz.allow")
```

### Bang Variants

All functions have bang variants that raise on error:

```elixir
engine =
  Regolix.new!()
  |> Regolix.add_policy!("authz.rego", policy)
  |> Regolix.set_input!(%{"user" => "admin"})

result = Regolix.eval_query!(engine, "data.authz.allow")
```

### Adding Data

Use `add_data/2` to provide external data to your policies:

```elixir
{:ok, engine} = Regolix.add_data(engine, %{
  "users" => %{
    "alice" => %{"role" => "admin"},
    "bob" => %{"role" => "viewer"}
  }
})
```

### Clearing Data

Clear all data while keeping policies loaded:

```elixir
{:ok, engine} = Regolix.clear_data(engine)
```

### Introspection

Check which packages are loaded:

```elixir
packages = Regolix.get_packages(engine)
# => ["data.authz", "data.rbac"]
```

## API Reference

- `new/0` - Create a new policy engine
- `add_policy/3` - Add a Rego policy
- `add_data/2` - Add data document (merges with existing)
- `set_input/2` - Set input document (replaces previous)
- `eval_query/2` - Evaluate a Rego query
- `clear_data/1` - Clear all data (keeps policies)
- `get_packages/1` - List loaded package names

All functions return `{:ok, result}` or `{:error, %Regolix.Error{}}`. Bang variants (`new!`, `add_policy!`, etc.) return the result directly or raise.

## Rego Syntax

Regolix uses Regorus which implements Rego v1 syntax. Rules require the `if` keyword:

```rego
package authz

default allow = false

allow if {
  input.user.role == "admin"
}

allow if {
  input.user.role == "viewer"
  input.method == "GET"
}
```

## License

MIT
