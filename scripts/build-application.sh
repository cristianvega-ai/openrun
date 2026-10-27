#!/bin/sh
# Builds OpenRun.app in one step: swift build in release mode, then a bundle
# with the app, the session process, openrun and the property list of the
# launch agent, signed from the inside out.
#
# Usage: scripts/build-application.sh OUTPUT-FOLDER
#
# OPENRUN_SIGNING_IDENTITY names the signing identity. Without it, the script
# uses the one Apple Development identity of the keychain. "-" signs ad hoc:
# launchd then ties the launch agent to the code hash, so each build that
# changes openrun-session needs a new registration.
set -eu

[ $# -eq 1 ] || { echo "Usage: $0 OUTPUT-FOLDER" >&2; exit 2; }
repository_root="$(cd "$(dirname "$0")/.." && pwd)"
agent=ai.cristianvega.openrun.session.plist

# Each row: the product of swift build, its place in the bundle, and its
# signing identifier. The bundle signature covers the app program.
PROGRAMS="openrun-application Contents/MacOS/OpenRun -
openrun-session Contents/MacOS/openrun-session ai.cristianvega.openrun.session
openrun Contents/Helpers/openrun ai.cristianvega.openrun.tool"

# The volume of a Mac ignores case, so such names would be one file.
duplicates="$(printf '%s\n' "$PROGRAMS" | cut -d' ' -f2 | tr '[:upper:]' '[:lower:]' | sort | uniq -d)"
[ -z "$duplicates" ] || { echo "These places in the bundle differ only in case: $duplicates" >&2; exit 1; }

identity="${OPENRUN_SIGNING_IDENTITY:-}"
if [ -z "$identity" ]; then
  identity="$(security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) \([0-9A-F]*\) "Apple Development: .*/\1/p')"
  count="$(printf '%s' "$identity" | grep -c . || true)"
  if [ "$count" -ne 1 ]; then
    echo "The keychain has $count Apple Development identities, and the script needs exactly one." >&2
    echo "Set OPENRUN_SIGNING_IDENTITY to the identity, or to - for an ad hoc signature." >&2
    exit 1
  fi
fi

mkdir -p "$1"
output_folder="$(cd "$1" && pwd)"
application="$output_folder/OpenRun.app"
staging="$output_folder/.staging/OpenRun.app"
swift build --package-path "$repository_root" --configuration release
binaries="$(swift build --package-path "$repository_root" --configuration release --show-bin-path)"

# The bundle is assembled and signed in a staging folder.
rm -rf "$output_folder/.staging"
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Helpers" "$staging/Contents/Library/LaunchAgents"
cp "$repository_root/Bundle/Info.plist" "$staging/Contents/Info.plist"
cp "$repository_root/Bundle/$agent" "$staging/Contents/Library/LaunchAgents/$agent"
plutil -lint "$staging/Contents/Info.plist" "$staging/Contents/Library/LaunchAgents/$agent"
printf '%s\n' "$PROGRAMS" | while read -r product place identifier; do
  cp "$binaries/$product" "$staging/$place"
  [ "$identifier" = - ] || codesign --force --sign "$identity" --identifier "$identifier" "$staging/$place"
done
codesign --force --sign "$identity" "$staging"

# Each file takes the place of the old one by a rename. The bundle folder
# stays, and a program that runs from an old file keeps that file, because a
# rename replaces only the name. A file of an older layout goes away.
files="$(cd "$staging" && find . -type f | sort)"
printf '%s\n' "$files" | while read -r file; do
  mkdir -p "$(dirname "$application/$file")"
  mv -f "$staging/$file" "$application/$file"
done
(cd "$application" && find . -type f) | while read -r file; do
  printf '%s\n' "$files" | grep -qxF "$file" || rm -f "$application/$file"
done
rm -rf "$output_folder/.staging"
codesign --verify --strict --deep --verbose=2 "$application"
echo "Built $application"
