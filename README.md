# Regolix

Elixir wrapper for [Regorus](https://github.com/microsoft/regorus), a fast Rego policy engine written in Rust.

## Installation

Add `regolix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:regolix, "~> 0.3.0"}
  ]
end
```

A precompiled NIF is downloaded for your platform — **no Rust toolchain required**
to use the library. Supported targets: `{x86_64,aarch64}-apple-darwin` and
`{x86_64,aarch64}-unknown-linux-gnu`. To build from source instead, set
`REGOLIX_BUILD=1` before compiling.

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

Get metadata about rules defined in policies:

```elixir
{:ok, rules} = Regolix.get_rules(engine)
# => %{
#   "authz.rego" => [
#     %{name: "allow", description: "Allow admin users", start_line: 5, end_line: 8}
#   ]
# }
```

This is useful for mapping coverage line numbers to human-readable rule names.

### Coverage Tracking

Track which policy lines are executed during evaluation:

```elixir
{result, coverage} = Regolix.with_coverage(engine, fn e ->
  Regolix.eval_query!(e, "data.authz.allow")
end)

# coverage => %{"authz.rego" => %{covered: [1, 2, 5], not_covered: [9, 10]}}
```

For multi-query accumulation, use the raw primitives:

```elixir
engine = Regolix.enable_coverage!(engine)
Regolix.eval_query!(engine, "data.authz.allow")
Regolix.eval_query!(engine, "data.rbac.check")
coverage = Regolix.get_coverage_report!(engine)
engine = Regolix.disable_coverage!(engine)
```

## API Reference

- `new/0` - Create a new policy engine
- `add_policy/3` - Add a Rego policy
- `add_data/2` - Add data document (merges with existing)
- `set_input/2` - Set input document (replaces previous)
- `eval_query/2` - Evaluate a Rego query
- `clear_data/1` - Clear all data (keeps policies)
- `get_packages/1` - List loaded package names
- `get_rules/1` - Get rule metadata (names, descriptions, line ranges)
- `with_coverage/2` - Execute with coverage tracking
- `enable_coverage!/1` - Start recording coverage
- `disable_coverage!/1` - Stop recording coverage
- `get_coverage_report/1` - Get coverage data
- `clear_coverage!/1` - Clear coverage data

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

## Releasing

Releases are automated. Pushing a `vX.Y.Z` tag builds the precompiled NIFs,
creates a GitHub release, and publishes to Hex — **pausing for a manual approval
before anything ships**. You never hand-build checksums or re-tag.

**One-time setup.** Hex no longer mints API keys from the CLI (auth is OAuth);
generate one at [hex.pm/dashboard/keys](https://hex.pm/dashboard/keys) with the
`api` permission, then store it scoped to the `hex` environment:

```bash
gh secret set HEX_API_KEY --env hex --repo jtippett/regolix
```

**To cut a release**, run the release assistant from `master` and follow the
prompts:

```bash
just release          # or, without just:  elixir scripts/release.exs
```

It shows the current and published versions, asks for a **patch / minor / major**
bump (you pick the level — no version numbers to type), rolls the
`CHANGELOG.md` `[Unreleased]` section into the new version, then commits, tags,
and pushes. That kicks off `release.yml`, which builds NIFs for all four targets
and creates the GitHub release. (The first precompiled release must be a new
version — `0.3.0` is already on Hex as a source build.)

Then **approve the publish**: open the workflow run → *Review deployments* →
approve the **`hex`** environment. On approval it generates
`checksum-Elixir.Regolix.Native.exs` from the released artifacts and runs
`mix hex.publish`.

Keep notes under `## [Unreleased]` in `CHANGELOG.md` as you work — the assistant
rolls them into each release. Don't commit the checksum file or move a published
tag by hand; the pipeline owns both.

## License

MIT
