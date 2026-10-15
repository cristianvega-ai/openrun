#!/usr/bin/env bash
set -euo pipefail

# Pin an exact commit so every build uses the same terminal behavior.
# libghostty-vt signatures and the snapshot format still change upstream.
GHOSTTY_COMMIT="a2e440396403385680008e456a741a7776091412"
GHOSTTY_REPOSITORY="https://github.com/ghostty-org/ghostty"

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
libraries_folder="$repository_root/Libraries"
source_folder="$libraries_folder/ghostty"

step() { printf '\n==> %s\n' "$*"; }


# Refuses a Ghostty tree with changes, because the library would then not be
# the pinned commit. A previous build leaves only ignored files behind.
refuse_dirty_tree() {
  local changes
  changes="$(git -C "$1" status --porcelain)"
  if [ -n "$changes" ]; then
    echo "The Ghostty tree at $1 has changes, so it is not the pinned commit:" >&2
    echo "$changes" | head -10 >&2
    echo "Commit or discard the changes, or remove the folder, and run this script again." >&2
    return 1
  fi
}


build_library() {
  step "Fetching Ghostty at $GHOSTTY_COMMIT"
  if [ ! -d "$source_folder/.git" ]; then
    git init --quiet "$source_folder"
    git -C "$source_folder" remote add origin "$GHOSTTY_REPOSITORY"
  fi
  # Before any fetch or checkout: a forced checkout would discard the edits
  # that this check exists to find.
  refuse_dirty_tree "$source_folder"
  if [ "$(git -C "$source_folder" rev-parse --verify --quiet HEAD || true)" = "$GHOSTTY_COMMIT" ]; then
    echo "Ghostty is already at the pinned commit."
  else
    git -C "$source_folder" fetch --quiet --depth 1 origin "$GHOSTTY_COMMIT"
    git -C "$source_folder" checkout --quiet --force FETCH_HEAD
  fi
  git -C "$source_folder" log --oneline -1
  refuse_dirty_tree "$source_folder"
}

# A test can source this file to call the functions above.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  build_library
fi
