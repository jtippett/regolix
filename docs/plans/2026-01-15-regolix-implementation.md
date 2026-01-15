# Regolix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an Elixir wrapper for Microsoft's Regorus Rego interpreter using Rustler NIFs.

**Architecture:** Rustler NIF wraps regorus::Engine in a ResourceArc with RwLock for thread-safe access. Elixir layer provides ergonomic API with tagged tuples and bang variants. JSON encoding handled at Elixir boundary using Jason.

**Tech Stack:** Elixir 1.19+, Rust (edition 2021), Rustler 0.37, Regorus 0.5, Jason 1.4

---

### Task 1: Add Dependencies

**Files:**
- Modify: `mix.exs`

**Step 1: Update mix.exs with dependencies**

```elixir
defp deps do
  [
    {:rustler, "~> 0.37.1"},
    {:jason, "~> 1.4"}
  ]
end
```

**Step 2: Fetch dependencies**

Run: `mix deps.get`
Expected: Dependencies fetched successfully

**Step 3: Commit**

```bash
git add mix.exs mix.lock
git commit -m "deps: add rustler and jason"
```

---

### Task 2: Generate Rustler NIF Scaffold

**Files:**
- Create: `native/regolix/` directory structure

**Step 1: Run Rustler generator**

Run: `mix rustler.new`
When prompted:
- Module name: `Regolix.Native`
- Library name: `regolix`

Expected: Creates `native/regolix/` with Cargo.toml and src/lib.rs

**Step 2: Add regorus dependency to Cargo.toml**

Modify `native/regolix/Cargo.toml` to have these dependencies:

```toml
[dependencies]
rustler = "0.37"
regorus = "0.5"
```

**Step 3: Verify Rust compiles**

Run: `mix compile`
Expected: Rust code compiles, NIF loads successfully

**Step 4: Commit**

```bash
git add native/ lib/regolix/native.ex
git commit -m "feat: scaffold rustler NIF with regorus dependency"
```

---

### Task 3: Create Error Module

**Files:**
- Create: `lib/regolix/error.ex`
- Test: `test/regolix/error_test.exs`

**Step 1: Write the failing test**

Create `test/regolix/error_test.exs`:

```elixir
defmodule Regolix.ErrorTest do
  use ExUnit.Case

  alias Regolix.Error

  test "error struct has type and message fields" do
    error = %Error{type: :parse_error, message: "bad syntax"}
    assert error.type == :parse_error
    assert error.message == "bad syntax"
  end

  test "error is an exception" do
    error = %Error{type: :eval_error, message: "undefined variable"}
    assert Exception.exception?(error)
  end

  test "error message/1 formats correctly" do
    error = %Error{type: :parse_error, message: "unexpected token"}
    assert Exception.message(error) == "parse_error: unexpected token"
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/regolix/error_test.exs`
Expected: FAIL with "Regolix.Error.__struct__/1 is undefined"

**Step 3: Write minimal implementation**

Create `lib/regolix/error.ex`:

```elixir
defmodule Regolix.Error do
  @type error_type :: :parse_error | :eval_error | :json_error | :engine_error

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t()
        }

  defexception [:type, :message]

  @impl true
  def message(%__MODULE__{type: type, message: msg}) do
    "#{type}: #{msg}"
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/regolix/error_test.exs`
Expected: 3 tests, 0 failures

**Step 5: Commit**

```bash
git add lib/regolix/error.ex test/regolix/error_test.exs
git commit -m "feat: add Regolix.Error exception struct"
```

---

### Task 4: Implement Rust Engine Resource

**Files:**
- Modify: `native/regolix/src/lib.rs`

**Step 1: Replace lib.rs with engine resource implementation**

Replace contents of `native/regolix/src/lib.rs`:

```rust
use regorus::Engine;
use rustler::{Atom, Env, ResourceArc, Term};
use std::sync::RwLock;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        undefined,
        parse_error,
        eval_error,
        json_error,
        engine_error,
    }
}

pub struct EngineResource {
    engine: RwLock<Engine>,
}

#[rustler::resource_impl]
impl rustler::Resource for EngineResource {}

#[rustler::nif]
fn native_new() -> ResourceArc<EngineResource> {
    ResourceArc::new(EngineResource {
        engine: RwLock::new(Engine::new()),
    })
}

rustler::init!("Elixir.Regolix.Native", [native_new]);
```

**Step 2: Verify it compiles**

Run: `mix compile`
Expected: Compiles successfully

**Step 3: Commit**

```bash
git add native/regolix/src/lib.rs
git commit -m "feat: implement engine resource with native_new"
```

---

### Task 5: Implement new/0 in Elixir

**Files:**
- Modify: `lib/regolix/native.ex`
- Modify: `lib/regolix.ex`
- Test: `test/regolix_test.exs`

**Step 1: Write the failing test**

Replace `test/regolix_test.exs`:

```elixir
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
```

**Step 2: Run test to verify it fails**

Run: `mix test test/regolix_test.exs`
Expected: FAIL with "function Regolix.new/0 is undefined"

**Step 3: Update Native module**

Replace `lib/regolix/native.ex`:

```elixir
defmodule Regolix.Native do
  use Rustler, otp_app: :regolix, crate: "regolix"

  @spec native_new() :: reference()
  def native_new(), do: :erlang.nif_error(:nif_not_loaded)
end
```

**Step 4: Implement Regolix.new/0**

Replace `lib/regolix.ex`:

```elixir
defmodule Regolix do
  @moduledoc """
  Elixir wrapper for the Regorus Rego policy engine.
  """

  alias Regolix.{Error, Native}

  @type engine :: reference()
  @type json_encodable :: map() | list() | String.t() | number() | boolean() | nil
  @type eval_result :: json_encodable() | :undefined

  @doc """
  Creates a new Rego policy engine.

  ## Examples

      {:ok, engine} = Regolix.new()
  """
  @spec new() :: {:ok, engine()}
  def new do
    {:ok, Native.native_new()}
  end

  @doc """
  Creates a new Rego policy engine. Raises on error.
  """
  @spec new!() :: engine()
  def new! do
    Native.native_new()
  end
end
```

**Step 5: Run test to verify it passes**

Run: `mix test test/regolix_test.exs`
Expected: 2 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/regolix.ex lib/regolix/native.ex test/regolix_test.exs
git commit -m "feat: implement Regolix.new/0 and new!/0"
```

---

### Task 6: Implement add_policy in Rust

**Files:**
- Modify: `native/regolix/src/lib.rs`

**Step 1: Add native_add_policy function to lib.rs**

Add after `native_new` function:

```rust
#[rustler::nif]
fn native_add_policy(
    resource: ResourceArc<EngineResource>,
    name: String,
    source: String,
) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    engine
        .add_policy(name, source)
        .map_err(|e| (atoms::parse_error(), e.to_string()))
}
```

**Step 2: Update init! macro**

```rust
rustler::init!("Elixir.Regolix.Native", [native_new, native_add_policy]);
```

**Step 3: Verify it compiles**

Run: `mix compile`
Expected: Compiles successfully

**Step 4: Commit**

```bash
git add native/regolix/src/lib.rs
git commit -m "feat: add native_add_policy NIF"
```

---

### Task 7: Implement add_policy/3 in Elixir

**Files:**
- Modify: `lib/regolix/native.ex`
- Modify: `lib/regolix.ex`
- Modify: `test/regolix_test.exs`

**Step 1: Write the failing test**

Add to `test/regolix_test.exs`:

```elixir
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
```

**Step 2: Run test to verify it fails**

Run: `mix test test/regolix_test.exs`
Expected: FAIL with "function Regolix.add_policy/3 is undefined"

**Step 3: Update Native module**

Add to `lib/regolix/native.ex`:

```elixir
@spec native_add_policy(reference(), String.t(), String.t()) ::
        :ok | {:error, {atom(), String.t()}}
def native_add_policy(_engine, _name, _source), do: :erlang.nif_error(:nif_not_loaded)
```

**Step 4: Implement add_policy/3 in Regolix**

Add to `lib/regolix.ex`:

```elixir
@doc """
Adds a Rego policy to the engine.

## Examples

    {:ok, engine} = Regolix.add_policy(engine, "authz.rego", "package authz")
"""
@spec add_policy(engine(), String.t(), String.t()) :: {:ok, engine()} | {:error, Error.t()}
def add_policy(engine, name, source) do
  case Native.native_add_policy(engine, name, source) do
    :ok -> {:ok, engine}
    {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
  end
end

@doc """
Adds a Rego policy to the engine. Raises on error.
"""
@spec add_policy!(engine(), String.t(), String.t()) :: engine()
def add_policy!(engine, name, source) do
  case add_policy(engine, name, source) do
    {:ok, engine} -> engine
    {:error, error} -> raise error
  end
end
```

**Step 5: Run test to verify it passes**

Run: `mix test test/regolix_test.exs`
Expected: 6 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/regolix.ex lib/regolix/native.ex test/regolix_test.exs
git commit -m "feat: implement add_policy/3 and add_policy!/3"
```

---

### Task 8: Implement set_input in Rust

**Files:**
- Modify: `native/regolix/src/lib.rs`

**Step 1: Add native_set_input function**

Add after `native_add_policy`:

```rust
#[rustler::nif]
fn native_set_input(
    resource: ResourceArc<EngineResource>,
    json_input: String,
) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    let value: regorus::Value = regorus::Value::from_json_str(&json_input)
        .map_err(|e| (atoms::json_error(), e.to_string()))?;

    engine
        .set_input(value);

    Ok(())
}
```

**Step 2: Update init! macro**

```rust
rustler::init!("Elixir.Regolix.Native", [native_new, native_add_policy, native_set_input]);
```

**Step 3: Verify it compiles**

Run: `mix compile`
Expected: Compiles successfully

**Step 4: Commit**

```bash
git add native/regolix/src/lib.rs
git commit -m "feat: add native_set_input NIF"
```

---

### Task 9: Implement set_input/2 in Elixir

**Files:**
- Modify: `lib/regolix/native.ex`
- Modify: `lib/regolix.ex`
- Modify: `test/regolix_test.exs`

**Step 1: Write the failing test**

Add to `test/regolix_test.exs`:

```elixir
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
end

describe "set_input!/2" do
  test "returns engine directly" do
    engine = Regolix.new!()
    engine = Regolix.set_input!(engine, %{"user" => "bob"})
    assert is_reference(engine)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/regolix_test.exs`
Expected: FAIL with "function Regolix.set_input/2 is undefined"

**Step 3: Update Native module**

Add to `lib/regolix/native.ex`:

```elixir
@spec native_set_input(reference(), String.t()) :: :ok | {:error, {atom(), String.t()}}
def native_set_input(_engine, _json), do: :erlang.nif_error(:nif_not_loaded)
```

**Step 4: Implement set_input/2 in Regolix**

Add to `lib/regolix.ex`:

```elixir
@doc """
Sets the input document for policy evaluation.

Accepts Elixir terms (maps, lists, etc.) which are automatically JSON-encoded.

## Examples

    {:ok, engine} = Regolix.set_input(engine, %{"user" => "alice"})
"""
@spec set_input(engine(), json_encodable()) :: {:ok, engine()} | {:error, Error.t()}
def set_input(engine, input) do
  with {:ok, json} <- encode_json(input),
       :ok <- Native.native_set_input(engine, json) do
    {:ok, engine}
  else
    {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
    {:error, %Jason.EncodeError{} = e} -> {:error, %Error{type: :json_error, message: Exception.message(e)}}
  end
end

@doc """
Sets the input document. Raises on error.
"""
@spec set_input!(engine(), json_encodable()) :: engine()
def set_input!(engine, input) do
  case set_input(engine, input) do
    {:ok, engine} -> engine
    {:error, error} -> raise error
  end
end

defp encode_json(term) do
  Jason.encode(term)
end
```

**Step 5: Run test to verify it passes**

Run: `mix test test/regolix_test.exs`
Expected: 9 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/regolix.ex lib/regolix/native.ex test/regolix_test.exs
git commit -m "feat: implement set_input/2 and set_input!/2"
```

---

### Task 10: Implement add_data in Rust

**Files:**
- Modify: `native/regolix/src/lib.rs`

**Step 1: Add native_add_data function**

Add after `native_set_input`:

```rust
#[rustler::nif]
fn native_add_data(
    resource: ResourceArc<EngineResource>,
    json_data: String,
) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    let value: regorus::Value = regorus::Value::from_json_str(&json_data)
        .map_err(|e| (atoms::json_error(), e.to_string()))?;

    engine
        .add_data(value)
        .map_err(|e| (atoms::engine_error(), e.to_string()))
}
```

**Step 2: Update init! macro**

```rust
rustler::init!("Elixir.Regolix.Native", [
    native_new,
    native_add_policy,
    native_set_input,
    native_add_data
]);
```

**Step 3: Verify it compiles**

Run: `mix compile`
Expected: Compiles successfully

**Step 4: Commit**

```bash
git add native/regolix/src/lib.rs
git commit -m "feat: add native_add_data NIF"
```

---

### Task 11: Implement add_data/2 in Elixir

**Files:**
- Modify: `lib/regolix/native.ex`
- Modify: `lib/regolix.ex`
- Modify: `test/regolix_test.exs`

**Step 1: Write the failing test**

Add to `test/regolix_test.exs`:

```elixir
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
end

describe "add_data!/2" do
  test "returns engine directly" do
    engine = Regolix.new!()
    engine = Regolix.add_data!(engine, %{"config" => %{"enabled" => true}})
    assert is_reference(engine)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/regolix_test.exs`
Expected: FAIL with "function Regolix.add_data/2 is undefined"

**Step 3: Update Native module**

Add to `lib/regolix/native.ex`:

```elixir
@spec native_add_data(reference(), String.t()) :: :ok | {:error, {atom(), String.t()}}
def native_add_data(_engine, _json), do: :erlang.nif_error(:nif_not_loaded)
```

**Step 4: Implement add_data/2 in Regolix**

Add to `lib/regolix.ex`:

```elixir
@doc """
Adds data to the engine's data document.

Can be called multiple times to merge data.

## Examples

    {:ok, engine} = Regolix.add_data(engine, %{"users" => %{"alice" => %{"role" => "admin"}}})
"""
@spec add_data(engine(), json_encodable()) :: {:ok, engine()} | {:error, Error.t()}
def add_data(engine, data) do
  with {:ok, json} <- encode_json(data),
       :ok <- Native.native_add_data(engine, json) do
    {:ok, engine}
  else
    {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
    {:error, %Jason.EncodeError{} = e} -> {:error, %Error{type: :json_error, message: Exception.message(e)}}
  end
end

@doc """
Adds data to the engine. Raises on error.
"""
@spec add_data!(engine(), json_encodable()) :: engine()
def add_data!(engine, data) do
  case add_data(engine, data) do
    {:ok, engine} -> engine
    {:error, error} -> raise error
  end
end
```

**Step 5: Run test to verify it passes**

Run: `mix test test/regolix_test.exs`
Expected: 11 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/regolix.ex lib/regolix/native.ex test/regolix_test.exs
git commit -m "feat: implement add_data/2 and add_data!/2"
```

---

### Task 12: Implement eval_query in Rust

**Files:**
- Modify: `native/regolix/src/lib.rs`

**Step 1: Add value_to_term helper and native_eval_query**

Add after `native_add_data`:

```rust
fn value_to_term<'a>(env: Env<'a>, value: regorus::Value) -> Term<'a> {
    match value {
        regorus::Value::Undefined => atoms::undefined().encode(env),
        regorus::Value::Null => rustler::types::atom::nil().encode(env),
        regorus::Value::Bool(b) => b.encode(env),
        regorus::Value::String(s) => s.encode(env),
        regorus::Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                i.encode(env)
            } else if let Some(f) = n.as_f64() {
                f.encode(env)
            } else {
                atoms::undefined().encode(env)
            }
        }
        regorus::Value::Array(arr) => {
            let terms: Vec<Term<'a>> = arr
                .into_iter()
                .map(|v| value_to_term(env, v))
                .collect();
            terms.encode(env)
        }
        regorus::Value::Object(obj) => {
            let pairs: Vec<(Term<'a>, Term<'a>)> = obj
                .into_iter()
                .map(|(k, v)| {
                    let key: Term<'a> = k.encode(env);
                    let val: Term<'a> = value_to_term(env, v);
                    (key, val)
                })
                .collect();
            Term::map_from_pairs(env, &pairs).unwrap()
        }
        regorus::Value::Set(set) => {
            let terms: Vec<Term<'a>> = set
                .into_iter()
                .map(|v| value_to_term(env, v))
                .collect();
            terms.encode(env)
        }
    }
}

#[rustler::nif]
fn native_eval_query<'a>(
    env: Env<'a>,
    resource: ResourceArc<EngineResource>,
    query: String,
) -> Result<Term<'a>, (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    let results = engine
        .eval_query(query, false)
        .map_err(|e| (atoms::eval_error(), e.to_string()))?;

    // Return the first result's first expression value, or undefined
    if let Some(result) = results.result.into_iter().next() {
        if let Some(expr) = result.expressions.into_iter().next() {
            return Ok(value_to_term(env, expr.value));
        }
    }

    Ok(atoms::undefined().encode(env))
}
```

**Step 2: Update init! macro**

```rust
rustler::init!("Elixir.Regolix.Native", [
    native_new,
    native_add_policy,
    native_set_input,
    native_add_data,
    native_eval_query
]);
```

**Step 3: Verify it compiles**

Run: `mix compile`
Expected: Compiles successfully

**Step 4: Commit**

```bash
git add native/regolix/src/lib.rs
git commit -m "feat: add native_eval_query NIF with value conversion"
```

---

### Task 13: Implement eval_query/2 in Elixir

**Files:**
- Modify: `lib/regolix/native.ex`
- Modify: `lib/regolix.ex`
- Modify: `test/regolix_test.exs`

**Step 1: Write the failing test**

Add to `test/regolix_test.exs`:

```elixir
describe "eval_query/2" do
  test "evaluates a simple boolean rule" do
    {:ok, engine} = Regolix.new()

    {:ok, engine} =
      Regolix.add_policy(engine, "test.rego", """
      package test
      default allow = false
      allow { input.user == "admin" }
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
      allow { input.user == "admin" }
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

    assert {:ok, %{"name" => "alice", "roles" => ["admin", "user"]}} =
             Regolix.eval_query(engine, "data.test.user")
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
```

**Step 2: Run test to verify it fails**

Run: `mix test test/regolix_test.exs`
Expected: FAIL with "function Regolix.eval_query/2 is undefined"

**Step 3: Update Native module**

Add to `lib/regolix/native.ex`:

```elixir
@spec native_eval_query(reference(), String.t()) :: {:ok, term()} | {:error, {atom(), String.t()}}
def native_eval_query(_engine, _query), do: :erlang.nif_error(:nif_not_loaded)
```

**Step 4: Implement eval_query/2 in Regolix**

Add to `lib/regolix.ex`:

```elixir
@doc """
Evaluates a Rego query against the engine.

Returns the result as Elixir terms, or `:undefined` if the query has no result.

## Examples

    {:ok, true} = Regolix.eval_query(engine, "data.authz.allow")
    {:ok, :undefined} = Regolix.eval_query(engine, "data.authz.nonexistent")
"""
@spec eval_query(engine(), String.t()) :: {:ok, eval_result()} | {:error, Error.t()}
def eval_query(engine, query) do
  case Native.native_eval_query(engine, query) do
    {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
    result -> {:ok, result}
  end
end

@doc """
Evaluates a Rego query. Raises on error.
"""
@spec eval_query!(engine(), String.t()) :: eval_result()
def eval_query!(engine, query) do
  case eval_query(engine, query) do
    {:ok, result} -> result
    {:error, error} -> raise error
  end
end
```

**Step 5: Run test to verify it passes**

Run: `mix test test/regolix_test.exs`
Expected: 18 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/regolix.ex lib/regolix/native.ex test/regolix_test.exs
git commit -m "feat: implement eval_query/2 and eval_query!/2"
```

---

### Task 14: Implement clear_data in Rust

**Files:**
- Modify: `native/regolix/src/lib.rs`

**Step 1: Add native_clear_data function**

Add after `native_eval_query`:

```rust
#[rustler::nif]
fn native_clear_data(resource: ResourceArc<EngineResource>) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    engine.clear_data();
    Ok(())
}
```

**Step 2: Update init! macro**

```rust
rustler::init!("Elixir.Regolix.Native", [
    native_new,
    native_add_policy,
    native_set_input,
    native_add_data,
    native_eval_query,
    native_clear_data
]);
```

**Step 3: Verify it compiles**

Run: `mix compile`
Expected: Compiles successfully

**Step 4: Commit**

```bash
git add native/regolix/src/lib.rs
git commit -m "feat: add native_clear_data NIF"
```

---

### Task 15: Implement clear_data/1 in Elixir

**Files:**
- Modify: `lib/regolix/native.ex`
- Modify: `lib/regolix.ex`
- Modify: `test/regolix_test.exs`

**Step 1: Write the failing test**

Add to `test/regolix_test.exs`:

```elixir
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
  end
end

describe "clear_data!/1" do
  test "returns engine directly" do
    engine = Regolix.new!()
    engine = Regolix.clear_data!(engine)
    assert is_reference(engine)
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/regolix_test.exs`
Expected: FAIL with "function Regolix.clear_data/1 is undefined"

**Step 3: Update Native module**

Add to `lib/regolix/native.ex`:

```elixir
@spec native_clear_data(reference()) :: :ok | {:error, {atom(), String.t()}}
def native_clear_data(_engine), do: :erlang.nif_error(:nif_not_loaded)
```

**Step 4: Implement clear_data/1 in Regolix**

Add to `lib/regolix.ex`:

```elixir
@doc """
Clears all data from the engine, keeping policies intact.

## Examples

    {:ok, engine} = Regolix.clear_data(engine)
"""
@spec clear_data(engine()) :: {:ok, engine()}
def clear_data(engine) do
  case Native.native_clear_data(engine) do
    :ok -> {:ok, engine}
    {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
  end
end

@doc """
Clears all data from the engine. Raises on error.
"""
@spec clear_data!(engine()) :: engine()
def clear_data!(engine) do
  case clear_data(engine) do
    {:ok, engine} -> engine
    {:error, error} -> raise error
  end
end
```

**Step 5: Run test to verify it passes**

Run: `mix test test/regolix_test.exs`
Expected: 20 tests, 0 failures

**Step 6: Commit**

```bash
git add lib/regolix.ex lib/regolix/native.ex test/regolix_test.exs
git commit -m "feat: implement clear_data/1 and clear_data!/1"
```

---

### Task 16: Final Integration Test and Cleanup

**Files:**
- Modify: `test/regolix_test.exs`

**Step 1: Add comprehensive integration test**

Add to `test/regolix_test.exs`:

```elixir
describe "integration" do
  test "complete authorization workflow" do
    # Create engine and add policy
    engine =
      Regolix.new!()
      |> Regolix.add_policy!("authz.rego", """
      package authz

      default allow = false

      allow {
        input.method == "GET"
        input.path == "/public"
      }

      allow {
        input.user.role == "admin"
      }

      allow {
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

      allow {
        user := data.users[input.user_id]
        user.permissions[_] == input.permission
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
    assert Regolix.eval_query!(engine, "data.rbac.allow") == :undefined
  end
end
```

**Step 2: Run all tests**

Run: `mix test`
Expected: All tests pass (22 tests, 0 failures)

**Step 3: Run formatter**

Run: `mix format`
Expected: No changes needed (or files formatted)

**Step 4: Commit**

```bash
git add -A
git commit -m "test: add comprehensive integration tests"
```

---

### Task 17: Update Documentation

**Files:**
- Modify: `README.md`

**Step 1: Update README with usage documentation**

Replace contents of `README.md`:

```markdown
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
  allow { input.user == "admin" }
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

## API Reference

- `new/0` - Create a new policy engine
- `add_policy/3` - Add a Rego policy
- `add_data/2` - Add data document (merges with existing)
- `set_input/2` - Set input document (replaces previous)
- `eval_query/2` - Evaluate a Rego query
- `clear_data/1` - Clear all data (keeps policies)

All functions return `{:ok, result}` or `{:error, %Regolix.Error{}}`. Bang variants (`new!`, `add_policy!`, etc.) return the result directly or raise.

## License

MIT
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README with usage documentation"
```

---

## Summary

17 tasks implementing Regolix from scratch:

1. Add dependencies
2. Generate Rustler scaffold
3. Create Error module
4. Implement Rust engine resource
5. Implement new/0
6. Implement add_policy in Rust
7. Implement add_policy/3 in Elixir
8. Implement set_input in Rust
9. Implement set_input/2 in Elixir
10. Implement add_data in Rust
11. Implement add_data/2 in Elixir
12. Implement eval_query in Rust
13. Implement eval_query/2 in Elixir
14. Implement clear_data in Rust
15. Implement clear_data/1 in Elixir
16. Final integration tests
17. Update documentation
