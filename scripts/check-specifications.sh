#!/bin/sh
# Checks the TLA+ models in specifications/ with TLC. A model that has a
# control must still fail the way its row says, so a change to a model only
# counts when the matching control still fails. Exits 0 only when every
# outcome is the expected one. Run it with --all to add the long runs.
set -eu

# Pin the exact release, and check the file before each use, because a
# download can only be as trustworthy as the value that checks it.
TOOLS_ADDRESS="https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar"
TOOLS_CHECKSUM="936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"

# Each row: model, configuration, expected outcome, size of the run.
# An outcome is no-error, invariant:<name>, action:<name> or
# temporal-violation. TLC does not name the temporal property that fails,
# so each control with that outcome checks one property.
EXPECTED_OUTCOMES="AttachSequence AttachSequence no-error quick
AttachSequence AttachSequenceWithoutRestoredSize invariant:NoRefusedSize quick
AttachSequence AttachSequenceAnnouncementWithoutRestoredSize invariant:NoRefusedAnnouncement quick
AttachSequence AttachSequenceSizePolicy no-error quick
AttachSequence AttachSequenceEarlyResize invariant:QuiescentSizeAgreement quick
AttachSequence AttachSequenceWithoutResizeConfirmation invariant:SizeOrder quick
AttachSequence AttachSequenceWithoutResizeConfirmationAgreement invariant:ConfirmedSizeAgreement quick
AttachSequence AttachSequenceWithoutOutputRoomWait invariant:OutputWaitBoundsQueue quick
AttachSequence AttachSequenceWithoutPrecedence action:NoNewPauseWhileViewerKeepsUp quick
AttachSequence AttachSequenceWithoutDrainWake invariant:NoPauseWhileViewerKeepsUp quick
AttachSequence AttachSequenceLiveness no-error quick
AttachSequence AttachSequenceWithoutRoomWake temporal-violation quick
AttachSequence AttachSequenceLivenessWithoutParsing temporal-violation quick
AttachSequence AttachSequenceThreeClients no-error long
AttachSequence AttachSequenceThreeClientsLiveness no-error long
ResizeWait ResizeWait no-error quick
ResizeWait ResizeWaitAttached no-error quick
ResizeWait ResizeWaitAttachedOutput no-error quick
ResizeWait ResizeWaitMultipleClients no-error quick
ResizeWait ResizeWaitRows no-error quick
ResizeWait ResizeWaitBothDimensions no-error quick
ResizeWait ResizeWaitThreeWidths no-error quick
ResizeWait ResizeWaitLiveness no-error quick
ResizeWait ResizeWaitWithoutEditorDetection invariant:WaitOnlyForEditor quick
ResizeWait ResizeWaitWithoutCorrectSizeAnswer invariant:CorrectSizeAnswers quick
ResizeWait ResizeWaitWithoutConfirmation invariant:ConfirmationsTracked quick
ResizeWait ResizeWaitWithoutCursorRule invariant:ScreenCopiesAgree quick
ResizeWait ResizeWaitWithoutNewestRequest invariant:SettledSizeAgreement quick
ResizeWait ResizeWaitWithoutEraseRequirement invariant:CursorRuleFollowsErase quick
LocalDelivery LocalDelivery no-error quick
LocalDelivery LocalDeliveryWithoutOrder invariant:ApplicationOrder quick
LocalDelivery LocalDeliveryWithoutQuiescence invariant:ServerOnlySizeAgreement quick
LocalDelivery LocalDeliveryWithoutSizeOrder invariant:SizeOrder quick
LocalDelivery LocalDeliveryThreeClients no-error long
SessionLifecycle SessionLifecycle no-error quick
SessionLifecycle SessionLifecycleWithoutStoppingState invariant:NoSessionStartsDuringShutdown quick
SessionLifecycle SessionLifecycleLiveness no-error quick
SessionLifecycle SessionLifecycleIdleExit no-error quick
SessionLifecycle SessionLifecycleWithoutIdleCheck invariant:IdleExitEndsNoSession quick
InputBacklog InputBacklog no-error quick
InputBacklog InputBacklogWithoutWithdrawal invariant:NoByteAfterWithdraw quick
InputBacklog InputBacklogLiveness no-error quick
InputBacklog InputBacklogThreeOwners no-error quick
LocalScreen LocalScreen no-error quick
LocalScreen LocalScreenWithoutResize invariant:LocalCopyMatchesWindow quick"

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
specifications_folder="$repository_root/specifications"
tools_path="$repository_root/Libraries/tla2tools.jar"
includes_long_runs=no
case "${1:-}" in "") ;; --all) includes_long_runs=yes ;; *) echo "Usage: $0 [--all]" >&2; exit 2 ;; esac

checksum_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

find_java() {
  for candidate in "${JAVA_HOME:+$JAVA_HOME/bin/java}" /opt/homebrew/opt/openjdk/bin/java "$(command -v java || true)"; do
    # The stub in /usr/bin answers only when a real Java is installed.
    if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -version >/dev/null 2>&1; then
      java_command="$candidate"
      return 0
    fi
  done
  echo "Java was not found. Install it (brew install openjdk) or set JAVA_HOME." >&2
  return 1
}

# Downloads the TLA+ tools when they are missing or are not the pinned file.
ensure_tools() {
  [ -f "$tools_path" ] && [ "$(checksum_of "$tools_path")" = "$TOOLS_CHECKSUM" ] && return 0
  mkdir -p "$(dirname "$tools_path")"
  echo "Downloading the TLA+ tools"
  curl --fail --silent --show-error --location "$TOOLS_ADDRESS" --output "$tools_path.download"
  if [ "$(checksum_of "$tools_path.download")" != "$TOOLS_CHECKSUM" ]; then
    rm -f "$tools_path.download"
    echo "Checksum mismatch for the downloaded TLA+ tools" >&2
    return 1
  fi
  mv -f "$tools_path.download" "$tools_path"
}

# Sets actual_outcome to what TLC reported for one run.
run_configuration() {
  [ "$(checksum_of "$tools_path")" = "$TOOLS_CHECKSUM" ] || { echo "The TLA+ tools changed" >&2; return 1; }
  log_path="$work_folder/$2.log"
  (cd "$specifications_folder" && "$java_command" -XX:+UseParallelGC -cp "$tools_path" tlc2.TLC \
    -metadir "$work_folder/$2" -config "$2.cfg" -workers 4 "$1.tla") >"$log_path" 2>&1 || true
  if grep -q "No error has been found" "$log_path"; then
    actual_outcome="no-error"
  elif grep -q "Temporal properties were violated" "$log_path"; then
    actual_outcome="temporal-violation"
  elif grep -q "Invariant .* is violated" "$log_path"; then
    actual_outcome="invariant:$(sed -n 's/.*Invariant \([A-Za-z]*\) is violated.*/\1/p' "$log_path" | head -1)"
  elif grep -q "Action property .* is violated" "$log_path"; then
    actual_outcome="action:$(sed -n 's/.*Action property \([A-Za-z]*\) is violated.*/\1/p' "$log_path" | head -1)"
  else
    actual_outcome="no-result (see $log_path)"
  fi
}

find_java
ensure_tools
work_folder="$(mktemp -d "${TMPDIR:-/tmp}/check-specifications.XXXXXX")"
# The logs stay unless every outcome is as expected, so a reader can open them.
trap 'echo "The logs stay in $work_folder" >&2' EXIT
mismatch_count=0
while read -r model configuration expected_outcome size; do
  [ "$size" = quick ] || [ "$includes_long_runs" = yes ] || continue
  run_configuration "$model" "$configuration"
  verdict=ok
  [ "$actual_outcome" = "$expected_outcome" ] || { verdict=MISMATCH; mismatch_count=$((mismatch_count + 1)); }
  printf '%-8s %-52s expected %-38s actual %s\n' "$verdict" "$configuration" "$expected_outcome" "$actual_outcome"
done <<EOF
$EXPECTED_OUTCOMES
EOF
if [ "$mismatch_count" -gt 0 ]; then echo "$mismatch_count outcome(s) differ from the table." >&2; exit 1; fi
rm -rf "$work_folder"; trap - EXIT
echo "Every outcome is as expected."
