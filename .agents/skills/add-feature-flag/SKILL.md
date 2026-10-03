---
name: add-feature-flag
description: Add a new runtime feature flag in the Warp codebase, for behavior that genuinely varies by build profile or debug tooling.
---

# add-feature-flag

Add a new `FeatureFlag` variant.

## Overview

This build ships a single stream (`Channel::Oss`, plus `Channel::Integration` for tests). There are no
Dogfood, Preview or Release channel lists, and no per-flag Cargo features. A flag that would simply be
"on" or "off" everywhere is not a flag: write the code (or delete it) directly.

Add a flag only when behavior legitimately depends on something known at startup, for example:

- the build profile or debugging tools (`DebugMode` is enabled through `DEBUG_FLAGS` in debug builds of the
  `warp-oss` binary).

The pieces are:

- `FeatureFlag` (an enum) and its runtime state live in `crates/warp_features/src/lib.rs`. `warp_core::features`
  and `app/src/features.rs` re-export it.
- `init_feature_flags()` in `app/src/features.rs` enables every flag returned by `enabled_features()`. That set is
  `ChannelState::additional_features()` (set by the binary, for example `DEBUG_FLAGS`) plus the flags that
  `enabled_features()` adds itself.

## Steps

### 1. Add the variant
In `crates/warp_features/src/lib.rs`:

```rust
pub enum FeatureFlag {
    /// What the flag gates.
    YourFeatureName,
}
```

### 2. Decide when it is enabled
Add it to `enabled_features()` in `app/src/features.rs`, gated on the condition that matters:

```rust
if condition {
    flags.insert(FeatureFlag::YourFeatureName);
}
```

For something that should only be on in debug builds of `warp-oss`, add it to `DEBUG_FLAGS` in
`crates/warp_features/src/lib.rs` instead.

Do not add a Cargo feature per flag. Cargo features are for optional dependencies and build modes
(`release_bundle`, profiling), not for flags.

### 3. Gate code with runtime checks
```rust
if FeatureFlag::YourFeatureName.is_enabled() {
    // gated behavior
}
```

Prefer runtime checks over `#[cfg(...)]` so both arms always compile; use `cfg` only when the code cannot
compile without the condition (missing dependencies).

### 4. Tests
Flags are all off in unit tests. Turn one on for the duration of a test with the thread-local override
(needs the `test-util` feature of `warp_features`, which the workspace test targets enable):

```rust
let _flag = FeatureFlag::YourFeatureName.override_enabled(true);
```

`set_enabled` panics inside unit tests; use `override_enabled` there.

## Keybindings with feature flags

If an `EditableBinding` or `FixedBinding` belongs to a gated feature, add an enabled predicate so it does not
show up in keyboard settings when the flag is off:

```rust
EditableBinding::new("action:name", "Action description", YourAction::Variant)
    .with_enabled(|| FeatureFlag::YourFeatureName.is_enabled())
    .with_key_binding("cmdorctrl-key")
```

## Best practices

- Keep flags rare. If the answer is the same in every build, do not add one.
- Keep flags high-level and product-focused rather than per-call-site.
- Remove a flag (see the `remove-feature-flag` skill) as soon as the condition it captured goes away.
