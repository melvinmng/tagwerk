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
# Provides: tagwerk_test_destination (prints the xcodebuild destination, creates the simulator if needed)

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
