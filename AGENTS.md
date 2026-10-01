# AGENTS.md

This file provides guidance when working with code in this repository.

## Development Commands

### Build and Run
- `cargo run` / `./script/run` - Build and run the GUI desktop app locally
- `cargo bundle --bin warp-oss` - Bundle the main (GUI) app

### Testing
- `cargo nextest run --no-fail-fast --workspace` - Run tests with nextest
- `cargo test --doc` - Run doc tests
- `cargo nextest run -p <package>` - Run tests for an individual package

### Linting and Formatting
- `./script/presubmit` - Run the full local presubmit only when explicitly requested
- `./script/format` - Format code
- `cargo clippy -p <package> --all-targets --tests -- -D warnings` - Run targeted Clippy
- `./script/run-clang-format.py -r --extensions 'c,h,cpp,m' ./crates/warpui/src/ ./app/src/` - Check C/C++/Obj-C formatting
- `./script/run-clang-format.py -i -r --extensions 'c,h,cpp,m' ./crates/warpui/src/ ./app/src/` - Format C/C++/Obj-C code in place
- `find . -name "*.wgsl" -exec wgslfmt --check {} +` - Check WGSL shader formatting
- `find . -name "*.wgsl" -exec wgslfmt {} +` - Format WGSL shaders in place

### Implementation Validation Order
Optimize for fast delivery and let CI catch uncommon failures outside targeted local coverage.

1. While editing, run only the smallest targeted `cargo check` or `cargo nextest` command that gives useful feedback; defer checks and tests until after implementation where possible.
2. Once the code and self-review are complete, run the relevant tests and fix the code until they pass.
3. Run the relevant Clippy and other lint, typecheck, or build checks and fix their findings. Return to affected tests only when a fix materially changes behavior.
4. Run every applicable mutating formatter once, after all other code changes are complete.
5. Open or update the PR without rerunning tests or lint after formatting and without adding a full `./script/presubmit` run.

Run the full presubmit only when the user, task, or approved spec explicitly requires it. For agent-driven implementation, this section replaces the broader pre-push presubmit guidance in `CONTRIBUTING.md`; that document still describes the human contributor workflow. A later source, test, manifest, generated-code, or configuration change creates a new candidate: rerun the affected portion of the sequence and finish with the applicable formatter. Local commits are checkpoints rather than validation boundaries and do not each need to pass independently. PR text, comments, labels, and other metadata do not invalidate code validation.

### Platform Setup
- `./script/install_cargo_build_deps` - Install Cargo build dependencies
- `./script/install_cargo_test_deps` - Install Cargo test dependencies

## Architecture Overview

This is a Rust-based, fully offline terminal emulator with a custom UI framework called **WarpUI**. It has no accounts, no built-in AI or agents, no cloud sync, no telemetry or crash reporting and no autoupdate; `CHANGES.md` records each removal. The only network access left is opt-in language server downloads, links the user opens, the opt-in loopback `warpctrl` local control, and the user's own `git` remotes and GitHub through `gh`, which run only while a pull request chip is showing in the selected tab (the chip is in neither the default prompt nor the default CLI-agent footer, so users opt in by adding it; a full-screen program, a running command or a maximized sibling pane hides it and `gh` stops after a grace period), the code-review panel is open in the selected tab, or the vertical tabs panel shows pull request badges in its current row mode, or on an explicit user action such as push or create pull request (a repository terminal with neither runs no `gh` or remote `git`). Command completions run only the completion generators on the reviewed allow-list in `crates/warp_completer/src/signatures/legacy/generator_policy/allowed.rs`: a generator, and an alias generator, must never execute shell syntax derived from the typed tokens, touch a network, or execute code the project controls. The `ALLOWED_WHEN_ISOLATED` list in `allowed.rs` runs only where `GeneratorContext::network_isolated()` is true (macOS and Linux local sessions), and a pair is added to it only with a real-tool fixture in `restored_generators_tests.rs`. Typed words reach a generator's command only through the token gate (`generator_policy/token_gate.rs`: a generator that takes tokens is `Strict` unless it is listed there, and every word must be inert); anything else is denied with a class in `denied.rs`; the drift test forces a decision for every new generator, and the injection corpus in `generator_policy_tests.rs` runs hostile tokens through every allowed token-taking generator in real shells, and every generator subprocess gets the offline environment table in `app/src/terminal/model/session/command_executor/offline_environment.rs` (applied by the local, WSL, MSYS2 and, for bash and zsh, in-band executors; a new variable goes there with a real-tool test or the label "documented, unverified"), and, on macOS and Linux, runs inside the network sandbox in `app/src/terminal/model/session/command_executor/network_sandbox.rs` (a `sandbox-exec` profile or a seccomp filter; it fails closed, and an executor that cannot sandbox reports `network_isolated() == false`). `script/offline_audit` enforces that. Do not add code that calls a server. Third-party CLI agents (Claude Code, Codex, Gemini CLI, OpenCode) run inside the terminal, and the UI for them is kept.

The desktop app is the `app/` crate on the WarpUI pixel/GPU framework (`warpui`, `crates/warpui_core`): `Element`/`View` layout, GPU/WGSL rendering, mouse input, `.app` bundles. Run with `cargo run` / `./script/run`; verify visually with the real-display integration framework (`crates/integration`).

### Key Components

**UI core** (`crates/warpui`, `crates/warpui_core`):
- Entity-Component-Handle pattern: a global `App` object owns all views/models (entities); views hold `ViewHandle<T>` references to other views; `AppContext` provides temporary access to handles during render/events.
- Actions system for event handling.

**Rendering** (WarpUI elements):
- `Element`s describe visual layout (Flutter-inspired), rendered on the GPU (WGSL).
- Mouse input uses `MouseStateHandle`: create it once during construction and reference/clone it wherever mouse input is tracked. An inline `MouseStateHandle::default()` while rendering means no mouse interactions work.

**Main app** (`app/`):
- Terminal emulation, blocks, the input editor and shell management (`terminal/`)
- Windows, tabs, panes and sessions (`workspace/`, `pane_group/`, `tab_configs/`, `launch_configs/`)
- Local workflows (`workflows/`) and the markdown file viewer (`notebooks/`)
- Code editor, file tree, code review and global search (`code/`, `code_review/`, `editor/`, `search/`)
- Settings and preferences (`settings/`, `settings_view/`)
- Local persistence in SQLite (`persistence/`)
- Third-party CLI-agent notifications and status (`agent_notifications/`)
- `warpctrl` local control server (`local_control/`)

**Core Libraries**:
- `crates/warp_core/` - Core utilities, platform abstractions and channel state (shared)
- `crates/warp_features/` - The `FeatureFlag` enum
- `crates/warp_terminal/` - Terminal model, grid and PTY handling
- `crates/editor/` - Text editing functionality
- `crates/warpui/` and `crates/warpui_core/` - Custom UI framework
- `crates/lsp/` and `crates/node_runtime/` - Language servers; a missing server or runtime is downloaded only when `code.language_servers.allow_downloads` is on
- `crates/repo_metadata/`, `crates/code_outline/`, `crates/warp_ripgrep/` - Repository tree, symbol outlines and search
- `crates/persistence/` - Diesel models, schema and migrations
- `crates/local_control/` and `crates/warp_cli/` - The `warpctrl` protocol and command line
- `crates/ipc/` - Inter-process communication
- `crates/integration/` - Integration test framework

**Channels and binaries**: `Channel` is `Oss` or `Integration`. The binaries are `warp-oss` (`app/src/bin/oss.rs`) and `integration` (`app/src/bin/integration.rs`).

### Key Architectural Patterns

1. **Entity-Handle System**: Views reference other views via handles, not direct ownership
2. **Modular Structure**: Workspace contains multiple workspace configurations, each with terminals, code editors, etc.
3. **Cross-Platform**: Native implementations for macOS, Windows and Linux. The `cfg(target_family = "wasm")` branches that remain are dormant: there is no web build.

### Development Guidelines

**Workspace Structure**:
- This is a Cargo workspace with 60+ member crates
- Main binary is in `app/`, UI framework in `crates/warpui/`
- Platform-specific code is conditionally compiled
- Integration tests are in `crates/integration/`

**Coding Style Preferences**:
- Avoid unnecessary type annotations, especially in closure params.
- Avoid using too many Rust path qualifiers and use imports for concision. Place import statements at the top of the file as per convention.
  An exception to this is inside cfg-guarded code branches. In those cases, you can either embed the import into the relevant scope or just use an absolute path for one-offs.
- If a function takes a context parameter (`AppContext`, `ViewContext`, or `ModelContext`), it should be named `ctx` and go last. The one exception is for
  functions that take a closure parameter, in which case the closure should be last.
- Always remove unused parameters completely rather than prefixing them with `_`. Update the function signature and all call sites accordingly.
- Prefer inline format arguments in macros like `println!`, `eprintln!`, and `format!` (for example, `eprintln!("{message}")` instead of `eprintln!("{}", message)`) to satisfy Clippy's `uninlined_format_args` lint.
- Do not pass `Itertools::format` results directly to logging macros (`log::*`, `safe_*`, etc.). `Itertools::format` produces a single-use formatter, while logging implementations may format a message more than once. Use a reusable `String` such as `iter.join(", ")` for logging arguments instead. Direct use in `format!` or `write!` is fine.
- When adding a toggleable setting, also add the matching Command Palette enable/disable entry and any required context flags so the setting is discoverable outside Settings.

**Comments**:
Comments have a cost. They carry a maintenance burden, because they must be kept in sync
with the code they describe. It is tempting to assume that more comments is always better,
but be judicious about when a comment is actually necessary because the code cannot speak
for itself.
- **Minimalist Comments**: Assume the reader is a Senior Software Engineer. Never comment
  to explain WHAT or HOW code works if self-documenting names accomplish that.
- **Strictly "Why" Only**: Reserve inline comments strictly for non-obvious business
  rationale, workarounds for third-party bugs, complex algorithms, unidiomatic code, or
  unexpected edge cases.
- **No Line-by-Line Narrations**: Never add comments restating the syntax (e.g., omit
  `# Initialize array`, `# Loop over users`).
- **Clean Docstrings**: Keep doc comments concise. Document public APIs, arguments, types,
  and returns. Do not narrate the method's internal implementation steps.
- **Single-source of documentation**: For items/members that have a doc comment explaining
  their purpose, you do not need to repeat that explanation anywhere else. A good example
  is a float const specifying an amount of spacing. You may use a doc comment on the
  declaration if necessary, but do not repeat that where the const is *referenced*. Another
  example is function call sites. Function doc comments explain what they do. Do not repeat
  the explanation at the call site.
- **Container docs describe the whole, member docs describe the parts**: A field's, variant's,
  or parameter's own doc comment is where that member gets explained. A container's item-level
  doc comment (struct, enum, trait) describes the item as a whole and must not enumerate or
  re-explain its members. Do not name members in the container's doc comment just to describe
  them, and do not restate in a member's doc comment what the container's doc comment already
  said. Behavior genuinely shared by several members belongs in exactly one place, not both.
- **Don't enumerate function call sites in doc comments**: Function doc comments should
  document their behavior and NOT their callers, e.g. it should never say things like,
  "this is used by [certain callers]" or "this is used when...".
- **No "transformation comments"**: Do not add comments that explain *your edits*. Comments
  only need explain the *current state* of the code. Explanations of edits belong in pull
  request comments instead. You shouldn't add comments with phrases like, "this used to do
  so-and-so".
- Do not remove existing comments when making unrelated changes. Only remove or modify a
  comment if the logic it describes has changed.
- The formatter (`./script/format`) is configured with a `max_width` (max line length) of
  100. Flow (reflow) comment line-wrapping to fill that full width rather than wrapping
  early at a narrower column, so comments span as few lines as possible.

**Terminal Model Locking**:
- Be extremely careful when calling `model.lock()` on the terminal model (`TerminalModel`). Acquiring multiple locks on the same model from different call sites can cause a deadlock, resulting in a UI freeze (beach ball on macOS).
- Before adding a new `model.lock()` call, verify that no caller in the current call stack already holds the lock.
- Prefer passing already-locked model references down the call stack rather than acquiring new locks.
- If you must lock the model, keep the lock scope as short as possible and avoid calling other functions that might also attempt to lock.

**Testing**:
- Use `cargo nextest` for parallel test execution
- Integration tests use the custom framework in `crates/integration/`.
- Follow the Implementation Validation Order above; do not add a full presubmit run after targeted tests unless it was explicitly required.
- Unit tests should be placed in separate files using the naming convention `${filename}_tests.rs` or `mod_test.rs`
- Test files should be included at the end of their corresponding module with:
  ```rust
  #[cfg(test)]
  #[path = "filename_tests.rs"]  // or "mod_test.rs"
  mod tests;
  ```

**Pull Request Workflow**:
- Follow the Implementation Validation Order before opening a PR or pushing a code update. Do not repeat validation when the candidate has not changed.
- CI is the broad cross-platform and workspace gate. Push once the targeted tests and lint checks pass and the formatter has run; address a later CI failure as a new revision.
- Do not create public pull requests or public issues that disclose a non-public security vulnerability. Refer users to `SECURITY.md` for the proper disclosure methods instead.
- Run `script/offline_audit` when a change touches networking, dependencies or hosts; new findings are regressions. Run `script/offline_audit --self-test` when you change the audit or its allowlist, and keep allowlist entries to one file and one reviewed construct.
 - When opening PRs, use the PR template at `.github/pull_request_template.md`
 - If the PR removes or changes a feature, add a section to `CHANGES.md` (template at its top) and a bullet to its Contents list.

**Database**:
- Uses Diesel ORM with SQLite
- Migrations in `crates/persistence/migrations/`
- Schema defined in `crates/persistence/src/schema.rs`

### Feature Flags

There is one release stream (`Channel::Oss`, plus `Channel::Integration` for tests), so behavior that is the same
everywhere is written directly, not put behind a flag. `FeatureFlag` (in `crates/warp_features/src/lib.rs`) is a
small runtime layer for behavior that depends on the platform or the build profile, such as `ITermImages`,
`KittyImages` and `DebugMode`.

How to add a feature flag:
- Add a new variant to the `FeatureFlag` enum in `crates/warp_features/src/lib.rs`
- Enable it in `enabled_features()` in `app/src/features.rs` (with a `#[cfg(...)]` on the platform or build condition), or list it in `DEBUG_FLAGS`
- Gate code paths with `FeatureFlag::YourFlag.is_enabled()`
- There is no Cargo feature per flag, and there are no Dogfood/Preview/Release lists

Best practices:
- **Prefer runtime checks over cfg directives**: Prefer `FeatureFlag::YourFlag.is_enabled()` over `#[cfg(...)]` compile-time directives when both arms compile everywhere. Use `#[cfg(...)]` only when the code cannot compile without them (for example, platform-specific code or dependencies that do not exist when the feature is disabled).
- Keep flags high-level and product-focused rather than per-call-site
- Remove the flag and dead branches once its value no longer varies
- In tests, use `FeatureFlag::YourFlag.override_enabled(true)`

Example:
```rust
#[derive(Sequence)]
pub enum FeatureFlag {
    YourNewFeature,
}

// Use in code
if FeatureFlag::YourNewFeature.is_enabled() {
    // gated behavior
}
```

### Exhaustive Matching

When adding/editing match statements, avoid using the wildcard _ when at all possible. Exhaustive matching is helpful for ensuring that all variants are handled, especially when adding new variants to enums in the future.
