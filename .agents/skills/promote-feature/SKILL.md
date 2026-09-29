---
name: promote-feature
description: Make a feature permanent in the Warp codebase. Use when a feature behind a FeatureFlag should now always be on.
---

# promote-feature

There is nothing to promote a flag through. This build ships one stream (`Channel::Oss`, plus
`Channel::Integration` for tests) and has no Dogfood, Preview or Release channel lists, so a flag has no rollout
stages and no per-flag Cargo feature.

To make a gated feature permanent, fold its enabled arm into the code and delete the flag. Follow the
`remove-feature-flag` skill.

To ship a feature that should only be on for some platforms or builds, keep the flag and enable it in
`enabled_features()` in `app/src/features.rs` (or `DEBUG_FLAGS` in `crates/warp_features/src/lib.rs`). See the
`add-feature-flag` skill.
