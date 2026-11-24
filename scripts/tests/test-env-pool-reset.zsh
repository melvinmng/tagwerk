#!/bin/zsh
# Tests for the reset of pool simulators in scripts/test-env.sh (run: zsh scripts/tests/test-env-pool-reset.zsh).
# xcrun is replaced by a stub that records its arguments, so no simulator is touched. The checks cover that a pool
# simulator is erased before it is handed out (no app store of an earlier run or another branch survives), that a booted
# simulator is shut down first, that a failing reset aborts, and that TAGWERK_TEST_SIMULATOR is never erased.
set -u
ROOT="${0:A:h:h:h}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

failures=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1"$'\n'"     expected: $2"$'\n'"     actual:   $3"; failures=$((failures + 1)); fi
}

STUB_BIN="$WORK_DIR/bin"
mkdir -p "$STUB_BIN"
# STUB_BOOTED=1 makes `simctl erase` fail until the simulator was shut down, as the real simctl does for a booted
# simulator; STUB_ERASE_FAIL=1 makes it fail always.
cat > "$STUB_BIN/xcrun" <<'STUB'
#!/bin/zsh
print -r -- "$*" >> "$STUB_XCRUN_CALLS"
case "$*" in
  "simctl list devices available -j") cat "$STUB_DEVICES_JSON" ;;
  "simctl create "*) print "CREATED-UDID" ;;
  "simctl shutdown "*) rm -f "$STUB_BOOTED_FLAG" ;;
  "simctl erase "*)
    [[ -z "${STUB_ERASE_FAIL:-}" ]] || exit 1
    [[ ! -e "$STUB_BOOTED_FLAG" ]] || exit 1
    ;;
esac
STUB
chmod +x "$STUB_BIN/xcrun"
export PATH="$STUB_BIN:$PATH"
export STUB_XCRUN_CALLS="$WORK_DIR/xcrun-calls.txt"
export STUB_DEVICES_JSON="$WORK_DIR/devices.json"
export STUB_BOOTED_FLAG="$WORK_DIR/booted"
cat > "$STUB_DEVICES_JSON" <<'JSON'
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-2": [
  {"name": "Tagwerk Tests Slot 1", "udid": "UDID-SLOT-1", "state": "Shutdown"},
  {"name": "Tagwerk Tests Slot 2", "udid": "UDID-SLOT-2", "state": "Shutdown"}
]}}
JSON

export TAGWERK_LOCK_DIR="$WORK_DIR/locks" TAGWERK_TEST_LOG_DIR="$WORK_DIR/logs" TAGWERK_TEST_DERIVED_DATA="$WORK_DIR/derived"
export TAGWERK_SLOT_WAIT_SECONDS=2 TAGWERK_LOCK_POLL_SECONDS=1
unset TAGWERK_TEST_SIMULATOR
source "$ROOT/scripts/test-env.sh"

calls_matching() { grep -c "$1" "$STUB_XCRUN_CALLS" || true; }
reset_state() { : > "$STUB_XCRUN_CALLS"; rm -rf "$TAGWERK_LOCK_DIR" "$STUB_BOOTED_FLAG"; unset STUB_ERASE_FAIL TAGWERK_TEST_SIMULATOR; }

print -- "-- a pool simulator is erased before the destination is printed"
reset_state
destination=$(tagwerk_test_destination 2>/dev/null)
check "the destination is the simulator of slot 1" "platform=iOS Simulator,id=UDID-SLOT-1" "$destination"
check "the simulator was erased" "1" "$(calls_matching '^simctl erase UDID-SLOT-1$')"
check "the other slot was not touched" "0" "$(calls_matching 'UDID-SLOT-2')"
check "a shut down simulator needs no extra shutdown" "0" "$(calls_matching '^simctl shutdown')"
check "the erase happens after the slot is chosen and before any boot" "0" "$(calls_matching '^simctl boot')"
tagwerk_release_simulator_slot

print -- "-- a booted simulator is shut down, then erased"
reset_state
: > "$STUB_BOOTED_FLAG"
destination=$(tagwerk_test_destination 2>/dev/null)
check "the destination is still printed" "platform=iOS Simulator,id=UDID-SLOT-1" "$destination"
check "erase, shutdown, erase in this order" "simctl erase UDID-SLOT-1|simctl shutdown UDID-SLOT-1|simctl erase UDID-SLOT-1" \
  "$(grep -E '^simctl (erase|shutdown)' "$STUB_XCRUN_CALLS" | paste -sd'|' -)"
tagwerk_release_simulator_slot

print -- "-- a simulator that cannot be erased aborts the destination"
reset_state
export STUB_ERASE_FAIL=1
destination=$(tagwerk_test_destination 2>"$WORK_DIR/stderr.txt"); rc=$?
check "the call fails" "1" "$rc"
check "no destination is printed" "" "$destination"
check "the message names the simulator" "1" "$(grep -c 'Could not reset the pool simulator UDID-SLOT-1' "$WORK_DIR/stderr.txt")"
tagwerk_release_simulator_slot

print -- "-- TAGWERK_TEST_SIMULATOR is never erased"
reset_state
export TAGWERK_TEST_SIMULATOR=0A1B2C3D-0000-1111-2222-333344445555
destination=$(tagwerk_test_destination 2>/dev/null)
check "its destination is used" "platform=iOS Simulator,id=0A1B2C3D-0000-1111-2222-333344445555" "$destination"
check "no simctl call at all" "0" "$(wc -l < "$STUB_XCRUN_CALLS" | tr -d ' ')"
unset TAGWERK_TEST_SIMULATOR

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
