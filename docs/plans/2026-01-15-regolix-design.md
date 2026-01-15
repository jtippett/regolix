# Regolix Design

Elixir wrapper for Microsoft's Regorus Rego interpreter via Rustler NIFs.

## Goals

- Provide an ergonomic Elixir API for evaluating Rego policies
- Use Rustler for safe Rust-to-Elixir NIF bindings
- Support the core Regorus workflow: creating an engine, adding policies, setting data/input, and evaluating queries
- Handle errors gracefully by converting Rust errors to Elixir tagged tuples
- Be memory-safe using Rustler's ResourceArc

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Elixir Layer                      │
│  ┌───────────────────────────────────────────────┐  │
│  │              Regolix (main module)            │  │
│  │  new/0, add_policy/3, set_input/2, eval/2    │  │
│  └───────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────┐  │
│  │              Regolix.Native                   │  │
│  │         NIF function definitions              │  │
│  └───────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────┐  │
│  │              Regolix.Error                    │  │
│  │      Structured error with type + message     │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                         │ Rustler NIF
┌─────────────────────────────────────────────────────┐
│                    Rust Layer                       │
│  ┌───────────────────────────────────────────────┐  │
│  │         ResourceArc<EngineResource>           │  │
│  │    Contains RwLock<Engine> for thread-safety  │  │
│  └───────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────┐  │
│  │              regorus::Engine                  │  │
│  │           The actual Rego interpreter         │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Public API

```elixir
defmodule Regolix do
  @type engine :: reference()
  @type json_encodable :: map() | list() | String.t() | number() | boolean() | nil
  @type eval_result :: json_encodable | :undefined

  # Create a new engine
  @spec new() :: {:ok, engine} | {:error, Error.t()}
  @spec new!() :: engine

  # Add a Rego policy (can be called multiple times)
  @spec add_policy(engine, name :: String.t(), rego_source :: String.t())
        :: {:ok, engine} | {:error, Error.t()}
  @spec add_policy!(engine, String.t(), String.t()) :: engine

  # Set the data document (merges with existing data)
  @spec add_data(engine, data :: json_encodable)
        :: {:ok, engine} | {:error, Error.t()}
  @spec add_data!(engine, json_encodable) :: engine

  # Set the input document (replaces previous input)
  @spec set_input(engine, input :: json_encodable)
        :: {:ok, engine} | {:error, Error.t()}
  @spec set_input!(engine, json_encodable) :: engine

  # Evaluate a query
  @spec eval_query(engine, query :: String.t())
        :: {:ok, eval_result} | {:error, Error.t()}
  @spec eval_query!(engine, String.t()) :: eval_result

  # Clear all data (keeps policies)
  @spec clear_data(engine) :: {:ok, engine}
  @spec clear_data!(engine) :: engine
end
```

## Error Handling

```elixir
defmodule Regolix.Error do
  @type error_type :: :parse_error | :eval_error | :json_error | :engine_error

  defexception [:type, :message]

  @type t :: %__MODULE__{
    type: error_type,
    message: String.t()
  }
end
```

Error types:
- `:parse_error` - Invalid Rego syntax in policy
- `:eval_error` - Runtime error during query evaluation
- `:json_error` - Invalid JSON encoding/decoding
- `:engine_error` - Internal Regorus engine failure

## Rust NIF Layer

```rust
use regorus::Engine;
use rustler::{Env, NifResult, ResourceArc};
use std::sync::RwLock;

pub struct EngineResource {
    engine: RwLock<Engine>,
}

#[rustler::resource_impl]
impl rustler::Resource for EngineResource {}

#[rustler::nif]
fn new() -> ResourceArc<EngineResource> {
    ResourceArc::new(EngineResource {
        engine: RwLock::new(Engine::new()),
    })
}

#[rustler::nif]
fn add_policy(
    resource: ResourceArc<EngineResource>,
    name: String,
    source: String,
) -> Result<(), (rustler::Atom, String)> {
    let mut engine = resource.engine.write().unwrap();
    match engine.add_policy(name, source) {
        Ok(_) => Ok(()),
        Err(e) => Err((atoms::parse_error(), e.to_string())),
    }
}

#[rustler::nif]
fn eval_query(
    env: Env,
    resource: ResourceArc<EngineResource>,
    query: String,
) -> Result<Term, (rustler::Atom, String)> {
    let mut engine = resource.engine.write().unwrap();
    match engine.eval_query(query) {
        Ok(value) => Ok(value_to_term(env, value)),
        Err(e) => Err((atoms::eval_error(), e.to_string())),
    }
}
```

## Project Structure

```
regolix/
├── lib/
│   ├── regolix.ex              # Main public API
│   ├── regolix/
│   │   ├── native.ex           # NIF function declarations
│   │   └── error.ex            # Error struct
├── native/
│   └── regolix/
│       ├── Cargo.toml          # Rust dependencies
│       └── src/
│           └── lib.rs          # Rust NIF implementation
├── test/
│   └── regolix_test.exs        # Tests
└── mix.exs                     # Elixir project config
```

## Dependencies

Elixir (`mix.exs`):
```elixir
defp deps do
  [
    {:rustler, "~> 0.37.1"},
    {:jason, "~> 1.4"}
  ]
end
```

Rust (`native/regolix/Cargo.toml`):
```toml
[package]
name = "regolix"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
rustler = "0.37"
regorus = "0.5"
```

## Usage Example

```elixir
{:ok, engine} = Regolix.new()
{:ok, engine} = Regolix.add_policy(engine, "authz.rego", """
  package authz
  default allow = false
  allow { input.user == "admin" }
""")
{:ok, engine} = Regolix.set_input(engine, %{"user" => "admin"})
{:ok, true} = Regolix.eval_query(engine, "data.authz.allow")
```
