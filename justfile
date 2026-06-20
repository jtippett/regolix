# Project commands. Run `just --list` to see them all.

# Interactive release: pick patch/minor/major, roll the CHANGELOG, tag & push.
release:
    elixir scripts/release.exs

# Run the test suite (builds the NIF locally).
test:
    REGOLIX_BUILD=1 mix test

# Format Elixir + Rust (the crate is a member of the root Cargo workspace).
fmt:
    mix format
    cargo fmt
