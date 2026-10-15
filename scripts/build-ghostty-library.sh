#!/usr/bin/env bash
# Builds libghostty-vt as an XCFramework from one pinned Ghostty commit.
# Package.swift names the output path. Run this once before `swift build`,
# and again whenever the pinned commit changes. It is safe to run again.
set -euo pipefail

# Pin an exact commit so every build uses the same terminal behavior.
# libghostty-vt signatures and the snapshot format still change upstream.
GHOSTTY_COMMIT="a2e440396403385680008e456a741a7776091412"
GHOSTTY_REPOSITORY="https://github.com/ghostty-org/ghostty"
# The mode that Ghostty ships. Zig's default is Debug, which turns on safety
# checks and takes minutes to parse 16 MB of text. Change this only with the
# measured throughput of the session tests in hand.
OPTIMIZE_MODE="ReleaseFast"

# Ghostty accepts one Zig version, and this script accepts only that exact
# release. The checksums live here, not in a file the download supplies: a
# download can only be as trustworthy as the values that check it. Each
# platform has two: the archive that ziglang.org serves, and the `zig` program
# inside it, which checks the program after the archive is extracted.
# To change the version, take the values from https://ziglang.org/download/
# and hash the program in each extracted archive with `shasum -a 256`.
ZIG_VERSION="0.16.0"
# OTHER_PROCESSOR means the Intel processor (x86_64), the only one besides Apple silicon.
ZIG_ARCHIVE_CHECKSUM_APPLE_SILICON="b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489"
ZIG_PROGRAM_CHECKSUM_APPLE_SILICON="e6cd688d25664983833aae272f501d4bceeae304875b8f1741209d15fd13a4ec"
ZIG_ARCHIVE_CHECKSUM_OTHER_PROCESSOR="0387557ed1877bc6a2e1802c8391953baddba76081876301c522f52977b52ba7"
ZIG_PROGRAM_CHECKSUM_OTHER_PROCESSOR="5597fba0eb9d8f1f5331e3e5822e7e96e4a12eeb6f4939781bd8e2c13b15e8b5"

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
libraries_folder="$repository_root/Libraries"
source_folder="$libraries_folder/ghostty"
zig_folder="$libraries_folder/zig"
framework_path="$libraries_folder/ghostty-vt.xcframework"
# Names the mode of the framework that is in place now. Zig caches by mode, but
# its output folder keeps the last result, and this script must not leave a
# framework of the wrong mode behind.
mode_stamp="$libraries_folder/ghostty-vt.optimize-mode"

step() { printf '\n==> %s\n' "$*"; }

checksum_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# Sets the platform name and the two checksums for this processor.
choose_zig_platform() {
  case "$(uname -m)" in
    arm64)
      zig_platform="aarch64-macos"
      zig_archive_checksum="$ZIG_ARCHIVE_CHECKSUM_APPLE_SILICON"
      zig_program_checksum="$ZIG_PROGRAM_CHECKSUM_APPLE_SILICON" ;;
    x86_64)
      zig_platform="x86_64-macos"
      zig_archive_checksum="$ZIG_ARCHIVE_CHECKSUM_OTHER_PROCESSOR"
      zig_program_checksum="$ZIG_PROGRAM_CHECKSUM_OTHER_PROCESSOR" ;;
    *) echo "Unsupported processor: $(uname -m)" >&2; return 1 ;;
  esac
}

# Succeeds when the file is the pinned Zig program. It hashes the file before
# anything runs it, so a Zig that is not the pinned release never executes.
# The program is only part of Zig: the standard library sits beside it. So
# `install_pinned_zig` never trusts a tree that an earlier run left behind.
is_pinned_zig() {
  [ -f "$1" ] && [ -x "$1" ] || return 1
  [ "$(checksum_of "$1")" = "$zig_program_checksum" ] || return 1
  [ "$("$1" version)" = "$ZIG_VERSION" ]
}

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

# Extracts the pinned Zig into a fresh folder and sets `installed_zig_command`
# to its program. Every run does this, so the standard library that the build
# uses always comes from an archive whose checksum matched the pin. A copy of
# Zig that sits elsewhere, or that an earlier run extracted, is not trusted:
# its checksum covers the program and not the files beside it.
install_pinned_zig() {
  choose_zig_platform
  mkdir -p "$zig_folder"
  local archive_path="$zig_folder/zig-$zig_platform-$ZIG_VERSION.tar.xz"
  local actual_checksum=""
  if [ -f "$archive_path" ]; then
    actual_checksum="$(checksum_of "$archive_path")"
  fi
  if [ "$actual_checksum" = "$zig_archive_checksum" ]; then
    echo "Using the Zig archive in $archive_path (checksum verified)"
  else
    if [ -f "$archive_path" ]; then
      echo "Skipping $archive_path: its checksum is not the pinned one."
    fi
    step "Downloading Zig $ZIG_VERSION from ziglang.org"
    # A partial download never takes the place of the archive in the folder.
    local incoming_archive_path="$archive_path.download"
    rm -f "$incoming_archive_path"
    curl --fail --silent --show-error --location \
      "https://ziglang.org/download/$ZIG_VERSION/zig-$zig_platform-$ZIG_VERSION.tar.xz" --output "$incoming_archive_path"
    actual_checksum="$(checksum_of "$incoming_archive_path")"
    if [ "$actual_checksum" != "$zig_archive_checksum" ]; then
      echo "Checksum mismatch for the downloaded Zig archive" >&2
      echo "  expected $zig_archive_checksum" >&2
      echo "  actual   $actual_checksum" >&2
      rm -f "$incoming_archive_path"
      return 1
    fi
    echo "Checksum verified: $actual_checksum"
    mv -f "$incoming_archive_path" "$archive_path"
  fi

  local extracted_folder="$zig_folder/zig-$ZIG_VERSION"
  rm -rf "$extracted_folder"
  mkdir -p "$extracted_folder"
  tar -xf "$archive_path" -C "$extracted_folder" --strip-components 1
  installed_zig_command="$extracted_folder/zig"
  if ! is_pinned_zig "$installed_zig_command"; then
    echo "The Zig program in the archive is not the pinned release." >&2
    return 1
  fi
  echo "Extracted Zig $ZIG_VERSION at $installed_zig_command"
}

build_library() {
  # Keep every cache inside the repository so a build never touches the
  # user's global Zig cache, and a clean checkout starts from nothing.
  export ZIG_GLOBAL_CACHE_DIR="$libraries_folder/cache/global"
  export ZIG_LOCAL_CACHE_DIR="$libraries_folder/cache/local"
  mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"

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

  # Ghostty names the Zig version it needs. The pin in this script must agree,
  # or the checksums above belong to the wrong release.
  step "Choosing a Zig compiler"
  choose_zig_platform
  local needed_version
  needed_version="$(sed -n 's/.*\.minimum_zig_version = "\([0-9.]*\)".*/\1/p' "$source_folder/build.zig.zon")"
  if [ "$needed_version" != "$ZIG_VERSION" ]; then
    echo "Ghostty at $GHOSTTY_COMMIT needs Zig $needed_version, and this script pins Zig $ZIG_VERSION." >&2
    echo "Update ZIG_VERSION and the four checksums together." >&2
    return 1
  fi

  install_pinned_zig
  local zig_command="$installed_zig_command"

  step "Building libghostty-vt in $OPTIMIZE_MODE mode"
  if [ "$(cat "$mode_stamp" 2>/dev/null || true)" != "$OPTIMIZE_MODE" ]; then
    echo "The framework in place was not built in $OPTIMIZE_MODE mode. Building again."
    rm -rf "$source_folder/zig-out" "$framework_path" "$mode_stamp"
  fi
  (cd "$source_folder" && "$zig_command" build -Demit-lib-vt -Doptimize="$OPTIMIZE_MODE")

  step "Placing the XCFramework at $framework_path"
  rm -rf "$framework_path"
  cp -R "$source_folder/zig-out/lib/ghostty-vt.xcframework" "$framework_path"
  printf '%s\n' "$OPTIMIZE_MODE" > "$mode_stamp"
  ls "$framework_path"
  echo
  echo "Done. Run swift build next."
}

# A test can source this file to call the functions above.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  build_library
fi
