#!/bin/zsh
# Shared test settings for app/test-all.sh and scripts/sync-strings.sh.
# Sourced, not executed. Gives every checkout (main checkout or worktree) its own simulator,
# derived data folder and log folder, so test runs in several checkouts can run at the same time.
#
# Environment overrides:
#   TAGWERK_TEST_SIMULATOR     simulator name or UDID to use instead of the checkout's own simulator
#   TAGWERK_TEST_DERIVED_DATA  derived data folder for the app build
#
# Sets: TAGWERK_CHECKOUT_KEY, TAGWERK_TEST_DERIVED, TAGWERK_TEST_LOG_DIR
# Provides: tagwerk_test_destination (prints the xcodebuild destination, creates the simulator if needed),
#           tagwerk_prepare_ui_simulator (boots the simulator and grants the UI test permissions),
#           tagwerk_acquire_run_lock / tagwerk_release_run_lock (one test run per checkout)

# Device type of the checkout's own simulator; the tests were written against this model.
TAGWERK_TEST_DEVICE_TYPE="iPhone 18 Pro"

# Stable key per checkout: folder name plus a short hash of the full path (worktree folders can share names).
_tagwerk_repo_root="${${(%):-%x}:A:h:h}"
TAGWERK_CHECKOUT_KEY="${_tagwerk_repo_root:t}-$(print -rn -- "$_tagwerk_repo_root" | /usr/bin/shasum | cut -c1-8)"

TAGWERK_TEST_DERIVED="${TAGWERK_TEST_DERIVED_DATA:-$HOME/Library/Developer/Tagwerk/DerivedData-tests-$TAGWERK_CHECKOUT_KEY}"
TAGWERK_TEST_LOG_DIR="${TMPDIR:-/tmp}/tagwerk-tests/$TAGWERK_CHECKOUT_KEY"

# Prints the destination for xcodebuild. Without TAGWERK_TEST_SIMULATOR it looks up the simulator
# "Tagwerk Tests <checkout key>" and creates it from the default device type on first use.
tagwerk_test_destination() {
  local requested="${TAGWERK_TEST_SIMULATOR:-}"
  if [[ -n "$requested" ]]; then
    if [[ "$requested" =~ '^[0-9A-Fa-f-]{36}$' ]]; then
      print -r -- "platform=iOS Simulator,id=$requested"
    else
      print -r -- "platform=iOS Simulator,name=$requested"
    fi
    return 0
  fi

  local simulator_name="Tagwerk Tests $TAGWERK_CHECKOUT_KEY"
  local udid
  udid=$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if device["name"] == name:
            print(device["udid"])
            sys.exit(0)
' "$simulator_name") || return 1

  if [[ -z "$udid" ]]; then
    udid=$(xcrun simctl create "$simulator_name" "$TAGWERK_TEST_DEVICE_TYPE") || {
      echo "Could not create simulator \"$simulator_name\" ($TAGWERK_TEST_DEVICE_TYPE)" >&2
      return 1
    }
    echo "    created simulator \"$simulator_name\" ($udid)" >&2
  fi
  print -r -- "platform=iOS Simulator,id=$udid"
}

# Boots the simulator of the destination and grants calendar and reminders access to the app, so no system dialog can
# interrupt a UI test. The simulator keeps running afterwards. Usage: tagwerk_prepare_ui_simulator DESTINATION PROJECT_PATH
tagwerk_prepare_ui_simulator() {
  local destination="$1" project="$2" simulator bundle_id
  simulator="${destination##*id=}"
  if [[ "$destination" != *"id="* ]]; then
    simulator=$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        if device["name"] == name:
            print(device["udid"])
            sys.exit(0)
' "${destination##*name=}") || return 1
  fi
  bundle_id=$(xcodebuild -project "$project" -scheme Tagwerk -showBuildSettings 2>/dev/null \
    | sed -nE 's/^ *PRODUCT_BUNDLE_IDENTIFIER = (.*)$/\1/p' | head -n 1)
  if [[ -z "$simulator" || -z "$bundle_id" ]]; then
    echo "Could not resolve the simulator or the bundle ID" >&2
    return 1
  fi
  xcrun simctl boot "$simulator" 2>/dev/null || true
  xcrun simctl bootstatus "$simulator" -b > /dev/null 2>&1 || true
  local service
  for service in calendar reminders; do
    xcrun simctl privacy "$simulator" grant "$service" "$bundle_id" || return 1
  done
}

# One test run per checkout: two runs would share the simulator and the derived data folder. The lock is a folder that
# holds the process ID of its owner; a lock whose owner no longer exists (crashed run) is taken over with a message.
# Returns 2 when another run is active. Callers release the lock with `trap tagwerk_release_run_lock EXIT`.
tagwerk_acquire_run_lock() {
  mkdir -p "$TAGWERK_TEST_LOG_DIR"
  local lock="$TAGWERK_TEST_LOG_DIR/run.lock" holder
  if ! mkdir "$lock" 2>/dev/null; then
    holder=$(cat "$lock/pid" 2>/dev/null || true)
    if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
      echo "Another test run (process $holder) is active in this checkout; wait for it to finish (lock: $lock)." >&2
      return 2
    fi
    echo "Taking over the stale test run lock (process ${holder:-unknown} no longer exists)." >&2
    rm -rf "$lock"
    mkdir "$lock" || return 2
  fi
  print -r -- "$$" > "$lock/pid"
}

# Removes the lock if this process owns it.
tagwerk_release_run_lock() {
  local lock="$TAGWERK_TEST_LOG_DIR/run.lock"
  if [[ "$(cat "$lock/pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -rf "$lock"
  fi
}
