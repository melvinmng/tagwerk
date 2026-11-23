#!/bin/zsh
# Shared test settings for app/test-all.sh, scripts/stress-audits.sh and scripts/sync-strings.sh.
# Sourced, not executed. Every checkout (main checkout or worktree) gets its own derived data folder and log folder.
# Simulators come from a small machine-wide pool ("Tagwerk Tests Slot 1" to "Tagwerk Tests Slot 3"): a test run takes
# a free slot for its whole duration and shuts the simulator down at the end, so the number of simulators (and with
# it memory and disk use) does not grow with the number of worktrees. At most one UI test stage runs on the machine at
# a time. A pool simulator is erased (app stores, containers, permissions) before each run, so data of an earlier run or
# another branch cannot break the test host.
#
# Environment overrides:
#   TAGWERK_TEST_SIMULATOR     simulator name or UDID to use instead of a pool slot (never shut down by the scripts)
#   TAGWERK_TEST_DERIVED_DATA  derived data folder for the app build
#   TAGWERK_TEST_LOG_DIR       log folder (the CI workflow sets it to find the logs for the artifact upload)
#   TAGWERK_KEEP_SIMULATOR=1   leave the pool simulator booted at the end of the run
#   TAGWERK_LOCK_DIR           folder of the machine-wide locks (default ~/Library/Developer/Tagwerk/locks)
#   TAGWERK_SIMULATOR_SLOTS    number of pool slots (default 3)
#   TAGWERK_SLOT_WAIT_SECONDS  how long to wait for a free slot before giving up with exit code 2 (default 1800)
#   TAGWERK_UI_LOCK_WAIT_SECONDS  how long to wait for the UI stage lock (default 3600)
#   TAGWERK_LOCK_POLL_SECONDS  polling interval while waiting for a lock (default 5)
#
# Sets: TAGWERK_CHECKOUT_KEY, TAGWERK_TEST_DERIVED, TAGWERK_TEST_LOG_DIR
# Provides: tagwerk_test_destination (prints the xcodebuild destination; takes a pool slot and creates its simulator if
#             needed),
#           tagwerk_prepare_ui_simulator (boots the simulator and grants the UI test permissions),
#           tagwerk_acquire_run_lock / tagwerk_release_run_lock (one test run per checkout),
#           tagwerk_acquire_simulator_slot / tagwerk_release_simulator_slot (pool slots, machine-wide),
#           tagwerk_acquire_ui_lock / tagwerk_release_ui_lock (one UI test stage on the machine),
#           tagwerk_cleanup_run (shuts the pool simulator down and releases all locks; scripts call it from
#             `trap tagwerk_cleanup_run EXIT`, plus `trap 'exit 130' INT` and `trap 'exit 143' TERM HUP` so that Ctrl-C and
#             termination run it too; the traps are set in the script itself because zsh runs an EXIT trap that a
#             function sets when the function returns),
#           tagwerk_checkout_key_for (the checkout key of a folder, also used by scripts/clean-test-env.sh)

# Device type of the pool simulators; the tests were written against this model.
TAGWERK_TEST_DEVICE_TYPE="iPhone 18 Pro"
TAGWERK_SIMULATOR_SLOTS="${TAGWERK_SIMULATOR_SLOTS:-3}"
TAGWERK_SLOT_WAIT_SECONDS="${TAGWERK_SLOT_WAIT_SECONDS:-1800}"
TAGWERK_UI_LOCK_WAIT_SECONDS="${TAGWERK_UI_LOCK_WAIT_SECONDS:-3600}"
TAGWERK_LOCK_POLL_SECONDS="${TAGWERK_LOCK_POLL_SECONDS:-5}"
TAGWERK_LOCK_DIR="${TAGWERK_LOCK_DIR:-$HOME/Library/Developer/Tagwerk/locks}"

# Stable key per checkout folder: folder name plus a short hash of the full path (worktree folders can share names).
tagwerk_checkout_key_for() {
  print -r -- "${1:t}-$(print -rn -- "$1" | /usr/bin/shasum | cut -c1-8)"
}

_tagwerk_repo_root="${${(%):-%x}:A:h:h}"
TAGWERK_CHECKOUT_KEY=$(tagwerk_checkout_key_for "$_tagwerk_repo_root")

TAGWERK_TEST_DERIVED="${TAGWERK_TEST_DERIVED_DATA:-$HOME/Library/Developer/Tagwerk/DerivedData-tests-$TAGWERK_CHECKOUT_KEY}"
TAGWERK_TEST_LOG_DIR="${TAGWERK_TEST_LOG_DIR:-${TMPDIR:-/tmp}/tagwerk-tests/$TAGWERK_CHECKOUT_KEY}"

# Prints the UDID of the available simulator with exactly this name (nothing if there is none). Prefers the newest runtime.
_tagwerk_simulator_udid() {
  xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if device["name"] == name:
            print(device["udid"])
            sys.exit(0)
' "$1"
}

# Prints the UDID of the simulator with this name and creates it from the default device type if it does not exist.
_tagwerk_find_or_create_simulator() {
  local simulator_name="$1" udid
  udid=$(_tagwerk_simulator_udid "$simulator_name") || return 1
  if [[ -z "$udid" ]]; then
    udid=$(xcrun simctl create "$simulator_name" "$TAGWERK_TEST_DEVICE_TYPE") || {
      echo "Could not create simulator \"$simulator_name\" ($TAGWERK_TEST_DEVICE_TYPE)" >&2
      return 1
    }
    echo "    created simulator \"$simulator_name\" ($udid)" >&2
  fi
  print -r -- "$udid"
}

# Erases the content and settings of a pool simulator, so every run starts without an app store, app container or
# permission left behind by an earlier run (possibly from another branch with a different data model). A booted simulator
# cannot be erased, so it is shut down first if the plain erase is refused. Only called for a pool slot this process holds.
_tagwerk_reset_pool_simulator() {
  local udid="$1"
  if ! xcrun simctl erase "$udid" > /dev/null 2>&1; then
    xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
    xcrun simctl erase "$udid" || {
      echo "Could not reset the pool simulator $udid" >&2
      return 1
    }
  fi
}

# Prints the destination for xcodebuild. Without TAGWERK_TEST_SIMULATOR it takes a free pool slot (waiting for one if
# all are in use, see tagwerk_acquire_simulator_slot) and prints the destination of its simulator "Tagwerk Tests Slot N",
# which is created from the default device type on first use and reset to a clean state (_tagwerk_reset_pool_simulator)
# before every run. A simulator chosen with TAGWERK_TEST_SIMULATOR is never reset. The slot stays taken until the process ends or calls
# tagwerk_release_simulator_slot, so call this from the main script, not from a background job.
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

  local slot udid
  slot=$(tagwerk_acquire_simulator_slot) || return $?
  udid=$(_tagwerk_find_or_create_simulator "Tagwerk Tests Slot $slot") || return 1
  _tagwerk_reset_pool_simulator "$udid" || return 1
  print -r -- "platform=iOS Simulator,id=$udid"
}

# Boots the simulator of the destination and grants calendar and reminders access to the app, so no system dialog can
# interrupt a UI test. The simulator stays booted until the end of the run (tagwerk_cleanup_run). Usage: tagwerk_prepare_ui_simulator DESTINATION PROJECT_PATH
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

# Takes the lock folder <lock> for this process: the folder holds the process ID of its owner. Returns 0 when the lock
# is taken and 1 when another live process holds it. A lock whose owner no longer exists (crashed run) is taken over
# with a message; a lock folder without a process ID file younger than 10 seconds belongs to an owner that is still
# starting and counts as held.
_tagwerk_try_lock() {
  local lock="$1" holder modified
  mkdir -p "${lock:h}" || return 1
  if ! mkdir "$lock" 2>/dev/null; then
    holder=$(cat "$lock/pid" 2>/dev/null || true)
    if [[ -n "$holder" ]]; then
      kill -0 "$holder" 2>/dev/null && return 1
    else
      modified=$(stat -f %m "$lock" 2>/dev/null || date +%s)
      (( $(date +%s) - modified < 10 )) && return 1
    fi
    echo "Taking over the stale lock ${lock:t} (process ${holder:-unknown} no longer exists)." >&2
    rm -rf "$lock"
    mkdir "$lock" 2>/dev/null || return 1
  fi
  print -r -- "$$" > "$lock/pid"
}

# Removes the lock folder <lock> if this process owns it.
_tagwerk_release_lock() {
  local lock="$1"
  if [[ "$(cat "$lock/pid" 2>/dev/null || true)" == "$$" ]]; then
    rm -rf "$lock"
  fi
}

# Takes a free pool slot and prints its number (1 to TAGWERK_SIMULATOR_SLOTS). A slot is a lock folder in
# TAGWERK_LOCK_DIR, so it is shared by all checkouts of the machine. When all slots are in use the call waits (a message
# names the holders) for at most TAGWERK_SLOT_WAIT_SECONDS and then returns 2. A process that already holds a slot gets
# the same one again.
tagwerk_acquire_simulator_slot() {
  local slot holders deadline=$(( SECONDS + TAGWERK_SLOT_WAIT_SECONDS )) announced=0
  for slot in {1..$TAGWERK_SIMULATOR_SLOTS}; do
    if [[ "$(cat "$TAGWERK_LOCK_DIR/slot-$slot.lock/pid" 2>/dev/null || true)" == "$$" ]]; then
      print -r -- "$slot"
      return 0
    fi
  done
  while true; do
    for slot in {1..$TAGWERK_SIMULATOR_SLOTS}; do
      if _tagwerk_try_lock "$TAGWERK_LOCK_DIR/slot-$slot.lock"; then
        print -r -- "$slot"
        return 0
      fi
    done
    if (( SECONDS >= deadline )); then
      echo "No simulator slot became free within $TAGWERK_SLOT_WAIT_SECONDS s (locks: $TAGWERK_LOCK_DIR)." >&2
      return 2
    fi
    if (( ! announced )); then
      holders=""
      for slot in {1..$TAGWERK_SIMULATOR_SLOTS}; do
        holders+=" $(cat "$TAGWERK_LOCK_DIR/slot-$slot.lock/pid" 2>/dev/null || true)"
      done
      echo "All $TAGWERK_SIMULATOR_SLOTS simulator slots are in use (processes:$holders); waiting up to $(( TAGWERK_SLOT_WAIT_SECONDS / 60 )) min for a free one." >&2
      announced=1
    fi
    sleep "$TAGWERK_LOCK_POLL_SECONDS"
  done
}

# Prints the numbers of the pool slots this process holds, one per line.
_tagwerk_own_slots() {
  local slot
  for slot in {1..$TAGWERK_SIMULATOR_SLOTS}; do
    if [[ "$(cat "$TAGWERK_LOCK_DIR/slot-$slot.lock/pid" 2>/dev/null || true)" == "$$" ]]; then
      print -r -- "$slot"
    fi
  done
}

# Gives the pool slots of this process back (the simulators are not touched).
tagwerk_release_simulator_slot() {
  local slot
  for slot in $(_tagwerk_own_slots); do
    _tagwerk_release_lock "$TAGWERK_LOCK_DIR/slot-$slot.lock"
  done
}

# Shuts down the simulators of the pool slots this process holds. Never touches other simulators, so simulators of
# other runs and a simulator chosen with TAGWERK_TEST_SIMULATOR keep running.
tagwerk_shutdown_pool_simulator() {
  local slot udid
  for slot in $(_tagwerk_own_slots); do
    udid=$(_tagwerk_simulator_udid "Tagwerk Tests Slot $slot" 2>/dev/null || true)
    [[ -n "$udid" ]] || continue
    # A simulator that is not booted answers with an error; that is the state we want.
    xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
  done
}

# Only one UI test stage runs on the machine at a time: UI tests are the main load and several at once make each other
# flaky. Waits up to TAGWERK_UI_LOCK_WAIT_SECONDS and then returns 2. A process that holds the lock keeps it.
tagwerk_acquire_ui_lock() {
  local lock="$TAGWERK_LOCK_DIR/ui-stage.lock" deadline=$(( SECONDS + TAGWERK_UI_LOCK_WAIT_SECONDS )) announced=0
  if [[ "$(cat "$lock/pid" 2>/dev/null || true)" == "$$" ]]; then return 0; fi
  while ! _tagwerk_try_lock "$lock"; do
    if (( SECONDS >= deadline )); then
      echo "The UI test stage lock did not become free within $TAGWERK_UI_LOCK_WAIT_SECONDS s (process $(cat "$lock/pid" 2>/dev/null || true), lock: $lock)." >&2
      return 2
    fi
    if (( ! announced )); then
      echo "Another UI test stage (process $(cat "$lock/pid" 2>/dev/null || true)) is running; waiting up to $(( TAGWERK_UI_LOCK_WAIT_SECONDS / 60 )) min for it to finish." >&2
      announced=1
    fi
    sleep "$TAGWERK_LOCK_POLL_SECONDS"
  done
}

tagwerk_release_ui_lock() {
  _tagwerk_release_lock "$TAGWERK_LOCK_DIR/ui-stage.lock"
}

# Everything a test run holds: the UI stage lock, the pool simulator (shut down unless TAGWERK_KEEP_SIMULATOR is set),
# the pool slot and the per-checkout run lock. Safe to call more than once. Use it as the EXIT trap of the script.
tagwerk_cleanup_run() {
  tagwerk_release_ui_lock
  if [[ -z "${TAGWERK_KEEP_SIMULATOR:-}" ]]; then
    tagwerk_shutdown_pool_simulator
  fi
  tagwerk_release_simulator_slot
  tagwerk_release_run_lock
}
