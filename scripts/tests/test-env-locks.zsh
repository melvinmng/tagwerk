#!/bin/zsh
# Tests for the simulator pool and the locks in scripts/test-env.sh (run: zsh scripts/tests/test-env-locks.zsh).
# xcrun is replaced by a stub that records its arguments and answers from a JSON file, so no simulator is touched. Other
# lock owners are simulated with lock folders that name a live (sleep) or a dead process.
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
cat > "$STUB_BIN/xcrun" <<'STUB'
#!/bin/zsh
print -r -- "$*" >> "$STUB_XCRUN_CALLS"
case "$*" in
  "simctl list devices available -j") cat "$STUB_DEVICES_JSON" ;;
  "simctl create "*) print "CREATED-UDID" ;;
esac
STUB
chmod +x "$STUB_BIN/xcrun"
export PATH="$STUB_BIN:$PATH"
export STUB_XCRUN_CALLS="$WORK_DIR/xcrun-calls.txt"
export STUB_DEVICES_JSON="$WORK_DIR/devices.json"
: > "$STUB_XCRUN_CALLS"
cat > "$STUB_DEVICES_JSON" <<'JSON'
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-2": [
  {"name": "Tagwerk Tests Slot 1", "udid": "UDID-SLOT-1", "state": "Booted"},
  {"name": "Tagwerk Tests Slot 2", "udid": "UDID-SLOT-2", "state": "Booted"},
  {"name": "Tagwerk Tests some-checkout-1234abcd", "udid": "UDID-LEGACY", "state": "Shutdown"}
]}}
JSON

export TAGWERK_LOCK_DIR="$WORK_DIR/locks"
export TAGWERK_TEST_LOG_DIR="$WORK_DIR/logs"
export TAGWERK_SIMULATOR_SLOTS=3
export TAGWERK_SLOT_WAIT_SECONDS=2
export TAGWERK_UI_LOCK_WAIT_SECONDS=2
export TAGWERK_LOCK_POLL_SECONDS=1
unset TAGWERK_TEST_SIMULATOR TAGWERK_KEEP_SIMULATOR
source "$ROOT/scripts/test-env.sh"

# A live process that is not this one, and a process that no longer exists.
sleep 120 &
OTHER_PID=$!
LIVE_PIDS+=("$OTHER_PID")
sleep 120 &
THIRD_PID=$!
LIVE_PIDS+=("$THIRD_PID")
true &
DEAD_PID=$!
wait "$DEAD_PID" 2>/dev/null

hold() { # lock-name pid: another process holds the lock
  mkdir -p "$TAGWERK_LOCK_DIR/$1"
  print -r -- "$2" > "$TAGWERK_LOCK_DIR/$1/pid"
}
reset_locks() { rm -rf "$TAGWERK_LOCK_DIR"; : > "$STUB_XCRUN_CALLS"; }
holder_of() { cat "$TAGWERK_LOCK_DIR/$1/pid" 2>/dev/null || print "none"; }

print -- "-- checkout key"
check "key is folder name plus 8 hex digits" "1" "$([[ "$(tagwerk_checkout_key_for /a/b/my-tree)" =~ '^my-tree-[0-9a-f]{8}$' ]] && print 1 || print 0)"
check "key differs for the same folder name in another place" "1" \
  "$([[ "$(tagwerk_checkout_key_for /a/b/my-tree)" != "$(tagwerk_checkout_key_for /c/my-tree)" ]] && print 1 || print 0)"

print -- "-- simulator slots"
reset_locks
slot=$(tagwerk_acquire_simulator_slot); rc=$?
check "first slot is 1" "1:0" "$slot:$rc"
check "slot lock names this process" "$$" "$(holder_of slot-1.lock)"
check "a process that holds a slot gets the same one again" "1" "$(tagwerk_acquire_simulator_slot)"
check "no second slot is taken" "none" "$(holder_of slot-2.lock)"
tagwerk_release_simulator_slot
check "release removes the own slot" "none" "$(holder_of slot-1.lock)"

reset_locks
hold slot-1.lock "$OTHER_PID"
check "a slot held by another live process is skipped" "2" "$(tagwerk_acquire_simulator_slot)"
check "the other holder keeps its slot" "$OTHER_PID" "$(holder_of slot-1.lock)"
tagwerk_release_simulator_slot
check "release leaves foreign slots alone" "$OTHER_PID" "$(holder_of slot-1.lock)"

reset_locks
hold slot-1.lock "$OTHER_PID"; hold slot-2.lock "$THIRD_PID"; hold slot-3.lock "$OTHER_PID"
started=$SECONDS
output=$(tagwerk_acquire_simulator_slot 2>&1); rc=$?
elapsed=$((SECONDS - started))
check "all slots busy: gives up with exit code 2" "2" "$rc"
check "all slots busy: waited for the limit" "1" "$(( elapsed >= 2 && elapsed <= 5 ? 1 : 0 ))"
check "all slots busy: message names the wait and the holders" "1" \
  "$([[ "$output" == *"All 3 simulator slots are in use (processes: $OTHER_PID $THIRD_PID $OTHER_PID)"* && "$output" == *"No simulator slot became free"* ]] && print 1 || print 0)"

reset_locks
hold slot-1.lock "$DEAD_PID"
output=$(tagwerk_acquire_simulator_slot 2>&1)
check "a slot of a crashed run is taken over" "1" "$([[ "$output" == *"Taking over the stale lock slot-1.lock"* && "$output" == *1 ]] && print 1 || print 0)"
check "the taken-over slot names this process" "$$" "$(holder_of slot-1.lock)"

reset_locks
mkdir -p "$TAGWERK_LOCK_DIR/slot-1.lock"
check "a fresh lock folder without a process ID counts as held (the next slot is taken)" "2" "$(tagwerk_acquire_simulator_slot 2>/dev/null)"
tagwerk_release_simulator_slot
touch -t 202001010000 "$TAGWERK_LOCK_DIR/slot-1.lock"
check "an old lock folder without a process ID is taken over" "1" "$(tagwerk_acquire_simulator_slot 2>/dev/null)"
reset_locks

# A slot freed while another run waits: the waiting run takes it.
hold slot-1.lock "$OTHER_PID"; hold slot-2.lock "$OTHER_PID"; hold slot-3.lock "$OTHER_PID"
( sleep 1; rm -rf "$TAGWERK_LOCK_DIR/slot-2.lock" ) &
FREEING_PID=$!
check "a waiting run takes the slot that becomes free" "2" "$(TAGWERK_SLOT_WAIT_SECONDS=10 tagwerk_acquire_simulator_slot 2>/dev/null)"
wait "$FREEING_PID"
reset_locks

print -- "-- destination"
check "TAGWERK_TEST_SIMULATOR takes no slot" "platform=iOS Simulator,name=My Phone:none" \
  "$(TAGWERK_TEST_SIMULATOR="My Phone" tagwerk_test_destination):$(holder_of slot-1.lock)"
check "TAGWERK_TEST_SIMULATOR with a UDID" "platform=iOS Simulator,id=0A1B2C3D-0000-1111-2222-333344445555" \
  "$(TAGWERK_TEST_SIMULATOR=0A1B2C3D-0000-1111-2222-333344445555 tagwerk_test_destination)"
destination=$(tagwerk_test_destination 2>/dev/null)
check "pool destination uses the simulator of the slot" "platform=iOS Simulator,id=UDID-SLOT-1" "$destination"
check "the slot is held by this process" "$$" "$(holder_of slot-1.lock)"
check "an existing slot simulator is not created again" "0" "$(grep -c 'simctl create' "$STUB_XCRUN_CALLS")"
tagwerk_release_simulator_slot
hold slot-1.lock "$OTHER_PID"; hold slot-2.lock "$OTHER_PID"
destination=$(tagwerk_test_destination 2>/dev/null)
check "a missing slot simulator is created with its slot name" "platform=iOS Simulator,id=CREATED-UDID:1" \
  "$destination:$(grep -c 'simctl create Tagwerk Tests Slot 3 iPhone 18 Pro' "$STUB_XCRUN_CALLS")"
reset_locks

print -- "-- UI stage lock"
ui_status() { tagwerk_acquire_ui_lock 2>/dev/null; print $?; }
check "free UI lock is taken" "0:$$" "$(ui_status):$(holder_of ui-stage.lock)"
check "the holder takes it again without waiting" "0" "$(ui_status)"
tagwerk_release_ui_lock
check "release frees the UI lock" "none" "$(holder_of ui-stage.lock)"
hold ui-stage.lock "$OTHER_PID"
started=$SECONDS
output=$(tagwerk_acquire_ui_lock 2>&1); rc=$?
check "another UI stage runs: waits, then exit code 2" "2" "$rc"
check "the wait lasted the limit" "1" "$(( SECONDS - started >= 2 ? 1 : 0 ))"
check "message names the other process" "1" "$([[ "$output" == *"process $OTHER_PID"* ]] && print 1 || print 0)"
tagwerk_release_ui_lock
check "release leaves a foreign UI lock alone" "$OTHER_PID" "$(holder_of ui-stage.lock)"
hold ui-stage.lock "$DEAD_PID"
check "a UI lock of a crashed run is taken over" "0:$$" "$(ui_status):$(holder_of ui-stage.lock)"
reset_locks

print -- "-- run lock"
reset_locks
mkdir -p "$TAGWERK_TEST_LOG_DIR/run.lock"
tagwerk_acquire_run_lock > /dev/null 2>&1; rc=$?
check "a fresh run lock folder without a process ID counts as held" "2" "$rc"
check "the fresh run lock folder is left alone" "yes" "$([[ -d "$TAGWERK_TEST_LOG_DIR/run.lock" && ! -f "$TAGWERK_TEST_LOG_DIR/run.lock/pid" ]] && print yes || print no)"
touch -t 202001010000 "$TAGWERK_TEST_LOG_DIR/run.lock"
tagwerk_acquire_run_lock > /dev/null 2>&1; rc=$?
check "an old run lock folder without a process ID is taken over" "0:$$" "$rc:$(cat "$TAGWERK_TEST_LOG_DIR/run.lock/pid" 2>/dev/null)"
tagwerk_release_run_lock
reset_locks

print -- "-- cleanup at the end of a run"
# The run lock of the checkout, a slot and the UI lock are all held; shut-down must hit only the own slot's simulator.
tagwerk_acquire_run_lock 2>/dev/null
tagwerk_acquire_simulator_slot > /dev/null 2>&1
hold slot-2.lock "$OTHER_PID"
tagwerk_acquire_ui_lock 2>/dev/null
: > "$STUB_XCRUN_CALLS"
tagwerk_cleanup_run
check "cleanup shuts down the own slot's simulator only" "simctl shutdown UDID-SLOT-1" "$(grep 'simctl shutdown' "$STUB_XCRUN_CALLS")"
check "cleanup frees the own slot" "none" "$(holder_of slot-1.lock)"
check "cleanup keeps the foreign slot" "$OTHER_PID" "$(holder_of slot-2.lock)"
check "cleanup frees the UI lock" "none" "$(holder_of ui-stage.lock)"
check "cleanup frees the run lock" "no" "$([[ -d "$TAGWERK_TEST_LOG_DIR/run.lock" ]] && print yes || print no)"
tagwerk_cleanup_run
check "cleanup twice is harmless" "none" "$(holder_of slot-1.lock)"

reset_locks
tagwerk_acquire_simulator_slot > /dev/null 2>&1
: > "$STUB_XCRUN_CALLS"
TAGWERK_KEEP_SIMULATOR=1 tagwerk_cleanup_run
check "TAGWERK_KEEP_SIMULATOR=1 keeps the simulator booted" "0" "$(grep -c 'simctl shutdown' "$STUB_XCRUN_CALLS")"
check "TAGWERK_KEEP_SIMULATOR=1 still frees the slot" "none" "$(holder_of slot-1.lock)"

reset_locks
tagwerk_cleanup_run
check "cleanup without any lock shuts nothing down" "0" "$(grep -c 'simctl shutdown' "$STUB_XCRUN_CALLS")"

print -- "-- the trap runs the cleanup when a script is terminated"
reset_locks
cat > "$WORK_DIR/trapped.zsh" <<'SCRIPT'
#!/bin/zsh
source "$1/scripts/test-env.sh"
tagwerk_acquire_run_lock || exit 2
trap tagwerk_cleanup_run EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
tagwerk_acquire_simulator_slot > /dev/null
print ready
sleep 5 &
wait
SCRIPT
chmod +x "$WORK_DIR/trapped.zsh"
"$WORK_DIR/trapped.zsh" "$ROOT" > "$WORK_DIR/trapped.out" 2>&1 &
TRAPPED_PID=$!
for _ in {1..50}; do grep -q ready "$WORK_DIR/trapped.out" 2>/dev/null && break; sleep 0.1; done
check "the running script holds a slot" "$TRAPPED_PID" "$(holder_of slot-1.lock)"
kill -TERM "$TRAPPED_PID"
wait "$TRAPPED_PID" 2>/dev/null
check "after SIGTERM the slot is free" "none" "$(holder_of slot-1.lock)"
check "after SIGTERM the simulator was shut down" "1" "$(grep -c 'simctl shutdown UDID-SLOT-1' "$STUB_XCRUN_CALLS")"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
