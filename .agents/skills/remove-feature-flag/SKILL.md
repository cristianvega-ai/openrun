---
name: remove-feature-flag
description: Remove a FeatureFlag variant by folding its permanent arm into the code.
---

# remove-feature-flag

Remove a `FeatureFlag` variant whose value no longer varies.

## Overview

A flag can go when its value is the same everywhere it is checked. There is nothing to "promote" first: this
build has one stream, no Dogfood, Preview or Release lists (`DOGFOOD_FLAGS`, `PREVIEW_FLAGS` and
`RELEASE_FLAGS` no longer exist), and flags are not backed by Cargo features. A flag is on when
`enabled_features()` in `app/src/features.rs` (or `ChannelState::additional_features()`) says so, and off
otherwise.

First decide the value the build has today (see `enabled_features()`), then keep that arm so behavior does not
change.

## Steps

### 1. Find every use
The shared `FeatureFlag` is used from `crates/` as well as `app/`:

```bash
rg "FeatureFlag::YourFeatureName" app/ crates/
```

### 2. Fold the checks
If the flag is permanently on, keep the enabled arm; if permanently off, keep the disabled arm.

**Before:**
```rust
if FeatureFlag::YourFeatureName.is_enabled() {
    // new behavior
} else {
    // old behavior
}
```

**After (flag on):**
```rust
// new behavior
```

Remove the dead arm and anything only it used: helper functions, fields, imports, settings, actions, menu
entries and tests.

### 3. Remove keybinding predicates
```rust
EditableBinding::new("action:name", "Action description", YourAction::Variant)
    .with_enabled(|| FeatureFlag::YourFeatureName.is_enabled())   // delete this line
    .with_key_binding("cmdorctrl-key")
```

### 4. Fix the tests
- Delete `FeatureFlag::YourFeatureName.override_enabled(true)` (flag on) from tests that keep the enabled
  behavior.
- Delete tests that only exercise the arm you removed.
- Remove `set_enabled` calls in the integration tests the same way.

### 5. Remove the definition
- Delete the variant from `crates/warp_features/src/lib.rs`.
- Delete its entry in `enabled_features()` in `app/src/features.rs` (and from `DEBUG_FLAGS` if listed).

### 6. Verify
```bash
cargo check --workspace --all-targets
cargo nextest run -p <affected-package>
./script/format
```

The build must produce no new warnings: removing an arm often leaves unused functions and imports.

## Best practices

- Remove ALL related code: checks, dead branches, keybinding predicates, tests.
- Do the flag removal in its own commit for easier review.
