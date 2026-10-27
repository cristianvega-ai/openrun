#!/bin/bash
# The manual check of the launch agent before each milestone review. The
# owner runs it by hand in Terminal, because it registers a launch agent and
# asks about the prompts of macOS. It uses trial names, a trial home folder
# and a trial bundle, so it never touches /Applications/OpenRun.app.
#
# Usage: scripts/check-launch-agent.sh   (OPENRUN_SIGNING_IDENTITY as for
# scripts/build-application.sh)
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
trial="$HOME/.openrun-trial"
application="$trial/OpenRunTrial.app"
label=ai.cristianvega.openrun.trial.session
domain="gui/$(id -u)"
# A short home folder, because a socket path holds 103 bytes.
export CFFIXED_USER_HOME="$trial/home" OPENRUN_TEST_WAKE_SERVICE_NAME="$label"
openrun="$application/Contents/Helpers/openrun"
failures=0

step() { printf '\n=== %s %s\n' "$(date '+%H:%M:%S')" "$*"; }
run() { echo "\$ $*"; "$@"; echo "[exit $?]"; }
state() { launchctl print "$domain/$label" 2>&1 | grep -E '^	(state|pid|runs|last exit code|last terminating signal|immediate reason) =' | tr -d '\t' | tr '\n' ';'; echo; }
agent_pid() { launchctl print "$domain/$label" 2>/dev/null | awk '$1 == "pid" {print $3}'; }
expect() { if eval "$2"; then echo "PASS: $1"; else echo "FAIL: $1"; failures=$((failures + 1)); fi; }
code_hash() { codesign -dvvv "$application/Contents/MacOS/openrun-session" 2>&1 | sed -n 's/^CDHash=//p'; }

# Builds OpenRun.app, gives it the trial names, signs it again with the same
# identity, and replaces each file of the trial bundle by a rename, as
# scripts/build-application.sh does.
build_trial() {
  "$root/scripts/build-application.sh" "$trial/build" >"$trial/build.log" 2>&1 || { tail -5 "$trial/build.log"; exit 1; }
  local staging="$trial/staging/OpenRunTrial.app" identity
  rm -rf "$trial/staging"; mkdir -p "$trial/staging"
  ditto "$trial/build/OpenRun.app" "$staging"
  identity="$(codesign -dvv "$staging" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
  local agent="$staging/Contents/Library/LaunchAgents/ai.cristianvega.openrun.session.plist"
  plutil -replace CFBundleIdentifier -string ai.cristianvega.openrun.trial "$staging/Contents/Info.plist"
  plutil -replace CFBundleName -string "OpenRun Trial" "$staging/Contents/Info.plist"
  plutil -replace Label -string "$label" "$agent"
  plutil -replace MachServices -json "{\"$label\": true}" "$agent"
  plutil -replace AssociatedBundleIdentifiers -json '["ai.cristianvega.openrun.trial"]' "$agent"
  plutil -replace EnvironmentVariables -json "{\"CFFIXED_USER_HOME\": \"$CFFIXED_USER_HOME\", \"OPENRUN_TEST_WAKE_SERVICE_NAME\": \"$label\"}" "$agent"
  codesign --force --sign "${identity:--}" --identifier "$label" "$staging/Contents/MacOS/openrun-session"
  codesign --force --sign "${identity:--}" --identifier ai.cristianvega.openrun.trial.tool "$staging/Contents/Helpers/openrun"
  codesign --force --sign "${identity:--}" "$staging"
  (cd "$staging" && find . -type f) | while read -r file; do
    mkdir -p "$(dirname "$application/$file")"; mv -f "$staging/$file" "$application/$file"
  done
  run codesign --verify --strict --deep "$application"
}

step "0. No trial agent is loaded"
mkdir -p -m 700 "$trial/home"
expect "launchctl does not know $label" "! launchctl print $domain/$label >/dev/null 2>&1"

step "1. Build the trial bundle, then open it: the app registers the agent"
build_trial
run open -n --env "CFFIXED_USER_HOME=$CFFIXED_USER_HOME" --env "OPENRUN_TEST_WAKE_SERVICE_NAME=$label" "$application"
sleep 5; state
expect "the app registered the agent, and it runs" '[ -n "$(agent_pid)" ]'
pkill -f "$application/Contents/MacOS/OpenRun"

step "2. openrun connects, and the prompt of macOS"
# The trial socket is outside the real ~/Library/Application Support, so
# also watch for the prompt with /Applications/OpenRun.app.
run "$openrun" list
read -r -p "Did macOS ask to let openrun access data from other apps? Type yes or no: " prompt
echo "prompt: $prompt"

step "3. A crash after 10 seconds of run time: launchd starts the agent again"
"$openrun" new -- /bin/sleep 600 >/dev/null; sleep 12; before="$(agent_pid)"
kill -SEGV "$before"; sleep 3; state
expect "a new process runs after the crash" '[ -n "$(agent_pid)" ] && [ "$(agent_pid)" != "$before" ]'

step "4. The idle exit: no session and no client for 30 seconds"
sleep 35; state
expect "the agent stopped with status 0" 'launchctl print $domain/$label | grep -q "last exit code = 0" && [ -z "$(agent_pid)" ]'

step "5. A new build while the agent runs: a shell starts, and the next wake works"
"$openrun" new -- /bin/sleep 600 >/dev/null; running="$(agent_pid)"; hash="$(code_hash)"
read -r -p "Change a text in Sources/SessionProcess, so that openrun-session changes. Then press Return. " _
build_trial
expect "openrun-session has a new code hash" '[ "$(code_hash)" != "$hash" ]'
shell="$("$openrun" new -- /bin/sh -c 'echo shell-started; exec sleep 600')"; sleep 2
expect "the old process ($running) starts a shell" '[ "$(agent_pid)" = "$running" ] && "$openrun" read "$shell" | grep -q shell-started'
for session in $("$openrun" list | cut -f1); do "$openrun" kill "$session"; done
sleep 35
expect "the new build starts at the next wake, without a new registration" '"$openrun" list >/dev/null && [ "$(agent_pid)" != "$running" ]'
echo "Undo the change in Sources/SessionProcess."

step "6. Remove the trial agent"
for session in $("$openrun" list | cut -f1); do "$openrun" kill "$session"; done
run launchctl bootout "$domain/$label"
rm -rf "$trial"
expect "launchctl does not know $label" "! launchctl print $domain/$label >/dev/null 2>&1"
echo "If System Settings, General, Login Items & Extensions still lists OpenRun Trial, turn it off."
echo "failures: $failures, prompt: $prompt"
[ "$failures" -eq 0 ]
