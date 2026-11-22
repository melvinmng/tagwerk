#!/bin/zsh
# Tests for the simulator pool in app/test-all.sh (run: zsh scripts/tests/test-all-simulator-pool.zsh).
# xcodebuild, xcodegen and xcrun are replaced by stubs, so no build, simulator or test runs. The checks cover which slot a
# run takes, when the UI stage lock is held, that the simulator is shut down at the end and that TAGWERK_TEST_SIMULATOR,
# TAGWERK_KEEP_SIMULATOR and a failing stage behave as documented. The lock logic itself is covered by test-env-locks.zsh.
set -u
ROOT="${0:A:h:h:h}"
WORK_DIR=$(mktemp -d)
LIVE_PIDS=()
cleanup() {
  local pid
  for pid in "${LIVE_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

failures=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1"$'\n'"     expected: $2"$'\n'"     actual:   $3"; failures=$((failures + 1)); fi
}

STUB_BIN="$WORK_DIR/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/xcodebuild" <<'STUB'
#!/bin/zsh
print -r -- "xcodebuild $*" >> "$STUB_CALLS"
case "$*" in
  *-list*) print '{"workspace": {"schemes": []}}' ;;
  *-showBuildSettings*) print '    PRODUCT_BUNDLE_IDENTIFIER = de.tagwerk.stub' ;;
  test*)
    # Records which locks exist while a test stage runs, then reports one executed test.
    case "$*" in
      *TagwerkUITests*) print "ui-stage lock during the UI tests: $(cat "$TAGWERK_LOCK_DIR/ui-stage.lock/pid" 2>/dev/null || print none)" >> "$STUB_CALLS" ;;
    esac
    [[ -z "${STUB_XCODEBUILD_FAIL:-}" ]] || { print "error: stubbed failure"; exit 65; }
    print "✔ Test run with 1 test in 1 suite passed after 0.001 seconds."
    ;;
esac
STUB
cat > "$STUB_BIN/xcodegen" <<'STUB'
#!/bin/zsh
STUB
cat > "$STUB_BIN/xcrun" <<'STUB'
#!/bin/zsh
print -r -- "xcrun $*" >> "$STUB_CALLS"
case "$*" in
  "simctl list devices available -j") cat "$STUB_DEVICES_JSON" ;;
  "simctl create "*) print "CREATED-UDID" ;;
esac
STUB
chmod +x "$STUB_BIN"/*

cat > "$WORK_DIR/devices.json" <<'JSON'
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-2": [
  {"name": "Tagwerk Tests Slot 1", "udid": "UDID-SLOT-1", "state": "Shutdown"},
  {"name": "Tagwerk Tests Slot 2", "udid": "UDID-SLOT-2", "state": "Shutdown"},
  {"name": "Tagwerk Tests Slot 3", "udid": "UDID-SLOT-3", "state": "Shutdown"}
]}}
JSON

LOCK_DIR="$WORK_DIR/locks"
sleep 120 &
OTHER_PID=$!
LIVE_PIDS+=("$OTHER_PID")

# Runs app/test-all.sh with the stubs and the given environment assignments; the recorded calls end up in
# $WORK_DIR/calls.txt and the output in $WORK_DIR/output.txt. Prints the exit code. A stubbed build leaves no
# .stringsdata, so the String Catalog check at the very end fails by design; a run that gets that far and fails there
# counts as 0 (all test stages passed).
run_script() {
  : > "$WORK_DIR/calls.txt"
  rm -rf "$WORK_DIR/logs"
  (
    unset TAGWERK_SKIP_UI_TESTS TAGWERK_ONLY_UI_TESTS TAGWERK_UI_ONLY TAGWERK_UI_TEST_SET TAGWERK_UI_TEST_RETRIES TAGWERK_BUILD_ONLY \
      TAGWERK_TEST_SIMULATOR TAGWERK_KEEP_SIMULATOR
    export PATH="$STUB_BIN:$PATH" STUB_CALLS="$WORK_DIR/calls.txt" STUB_DEVICES_JSON="$WORK_DIR/devices.json"
    export TAGWERK_LOCK_DIR="$LOCK_DIR" TAGWERK_TEST_DERIVED_DATA="$WORK_DIR/derived" TAGWERK_TEST_LOG_DIR="$WORK_DIR/logs"
    export TAGWERK_SLOT_WAIT_SECONDS=2 TAGWERK_UI_LOCK_WAIT_SECONDS=2 TAGWERK_LOCK_POLL_SECONDS=1
    for assignment in "$@"; do export "$assignment"; done
    "$ROOT/app/test-all.sh" > "$WORK_DIR/output.txt" 2>&1
  )
  local rc=$?
  if (( rc == 1 )) && grep -q '^TESTS FAILED in stage: string catalogs$' "$WORK_DIR/output.txt"; then rc=0; fi
  print $rc
}
calls_matching() { grep -c "$1" "$WORK_DIR/calls.txt" || true; }
holder_of() { cat "$LOCK_DIR/$1/pid" 2>/dev/null || print "none"; }
hold() { mkdir -p "$LOCK_DIR/$1"; print -r -- "$2" > "$LOCK_DIR/$1/pid"; }

print -- "-- a full run takes slot 1, runs the UI stage under the UI lock and shuts the simulator down"
rm -rf "$LOCK_DIR"
check "run succeeds" "0" "$(run_script)"
check "the destination is the simulator of slot 1" "1" "$(grep -c 'setup: platform=iOS Simulator,id=UDID-SLOT-1' "$WORK_DIR/output.txt")"
check "the app stage uses it" "1" "$(calls_matching "xcodebuild test .*-scheme Tagwerk -destination platform=iOS Simulator,id=UDID-SLOT-1")"
check "package stages for macOS do not use it" "0" "$(calls_matching "xcodebuild test -testLanguage de -testRegion DE -scheme TagwerkCore -destination platform=iOS")"
check "the UI stage runs while this run holds the UI lock" "1" "$(calls_matching 'ui-stage lock during the UI tests: [0-9]')"
check "the simulator is booted for the UI stage" "1" "$(calls_matching 'xcrun simctl boot UDID-SLOT-1')"
check "the simulator is shut down at the end" "1" "$(calls_matching 'xcrun simctl shutdown UDID-SLOT-1')"
check "slot, UI lock and run lock are released" "none none no" \
  "$(holder_of slot-1.lock) $(holder_of ui-stage.lock) $([[ -d "$WORK_DIR/logs/run.lock" ]] && print yes || print no)"

print -- "-- a busy slot is skipped"
rm -rf "$LOCK_DIR"; hold slot-1.lock "$OTHER_PID"
check "run succeeds with slot 1 held elsewhere" "0" "$(run_script TAGWERK_SKIP_UI_TESTS=1)"
check "it takes slot 2" "1" "$(grep -c 'setup: platform=iOS Simulator,id=UDID-SLOT-2' "$WORK_DIR/output.txt")"
check "only its own simulator is shut down" "0 1" "$(calls_matching 'simctl shutdown UDID-SLOT-1') $(calls_matching 'simctl shutdown UDID-SLOT-2')"
check "the other holder keeps slot 1" "$OTHER_PID" "$(holder_of slot-1.lock)"

print -- "-- all slots busy"
rm -rf "$LOCK_DIR"; hold slot-1.lock "$OTHER_PID"; hold slot-2.lock "$OTHER_PID"; hold slot-3.lock "$OTHER_PID"
check "the run gives up with exit code 2" "2" "$(run_script TAGWERK_SKIP_UI_TESTS=1)"
check "no build or test ran" "0" "$(calls_matching 'xcodebuild test')"
check "the message names the full pool" "1" "$(grep -c 'All 3 simulator slots are in use' "$WORK_DIR/output.txt")"

print -- "-- the UI stage waits for another UI stage"
rm -rf "$LOCK_DIR"; hold ui-stage.lock "$OTHER_PID"
check "the run gives up with exit code 2" "2" "$(run_script TAGWERK_ONLY_UI_TESTS=1)"
check "the UI tests did not start" "0" "$(calls_matching 'xcodebuild test .*TagwerkUITests')"
check "the simulator of the run is still shut down" "1" "$(calls_matching 'xcrun simctl shutdown UDID-SLOT-1')"
check "the foreign UI lock is untouched" "$OTHER_PID" "$(holder_of ui-stage.lock)"
check "the run without UI stage does not wait for it" "0" "$(run_script TAGWERK_SKIP_UI_TESTS=1)"

print -- "-- TAGWERK_KEEP_SIMULATOR, TAGWERK_TEST_SIMULATOR and failures"
rm -rf "$LOCK_DIR"
check "keep: run succeeds" "0" "$(run_script TAGWERK_SKIP_UI_TESTS=1 TAGWERK_KEEP_SIMULATOR=1)"
check "keep: the simulator is not shut down" "0" "$(calls_matching 'simctl shutdown')"
check "keep: the slot is released" "none" "$(holder_of slot-1.lock)"
check "own simulator: run succeeds" "0" "$(run_script TAGWERK_SKIP_UI_TESTS=1 TAGWERK_TEST_SIMULATOR=0A1B2C3D-0000-1111-2222-333344445555)"
check "own simulator: no slot is taken" "0 0" "$(calls_matching 'simctl list') $(calls_matching 'simctl shutdown')"
check "own simulator: its destination is used" "1" "$(grep -c 'setup: platform=iOS Simulator,id=0A1B2C3D-0000-1111-2222-333344445555' "$WORK_DIR/output.txt")"
check "failing stage: exit code 1" "1" "$(run_script TAGWERK_SKIP_UI_TESTS=1 STUB_XCODEBUILD_FAIL=1)"
check "failing stage: simulator shut down and slot released" "1 none" "$(calls_matching 'simctl shutdown UDID-SLOT-1') $(holder_of slot-1.lock)"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
