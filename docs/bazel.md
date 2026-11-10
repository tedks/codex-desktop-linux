# Bazel package graph

The first child-owned Bazel target is `//updater:state_test`. It compiles the existing `updater/src/state.rs` file as a Rust test crate and runs its six compatibility tests. The root module pins Bazel 8.7.0, rules_rust 0.74.0, Rust 1.98.0, and the selected crates from the committed `Cargo.lock` for Linux x86-64. Inputs are the test source, lockfile, module, and dependency archives; no generated desktop application or DMG is involved.

From this repository root, with Bazel 8.7.0 available:

```bash
bazel test //updater:state_test --jobs=2 --local_resources=memory=2048
```

This target neither launches the desktop app nor checks the rest of the updater. `cargo test -p codex-update-manager` remains the native full-crate test. The Nix package and desktop installer flows are separate and are not invoked by Bazel. Bazel's selected crate specs must be reviewed against `updater/Cargo.toml` and the committed Cargo lock after a dependency change; Bazel must never rewrite the native lock. Rerun the test from a fresh cache before qualifying the changed graph on remote workers.
