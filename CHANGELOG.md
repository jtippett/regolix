# Changelog

## [Unreleased]

### Changed

- **Ship precompiled NIFs.** Switched from `Rustler` (compile-from-source on the
  consumer's machine) to `RustlerPrecompiled`. Installing regolix no longer
  requires a Rust toolchain — a prebuilt NIF is downloaded for the user's
  platform (`{x86_64,aarch64}-{apple-darwin,unknown-linux-gnu}`). Set
  `REGOLIX_BUILD=1` to force a from-source build for local development.
- Updated `rustler` 0.37 → **0.38**, added `rustler_precompiled` ~> 0.9, and
  bumped `ex_doc` to ~> 0.40.

### Added

- CI (`mix test`, format, clippy) and an automated, approval-gated release
  pipeline (build precompiled NIFs for all targets → GitHub release → generate
  checksums → publish to Hex). See the "Releasing" section in the README.
