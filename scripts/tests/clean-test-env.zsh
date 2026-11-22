#!/bin/zsh
# Tests for scripts/clean-test-env.sh (run: zsh scripts/tests/clean-test-env.zsh).
# git and xcrun are replaced by stubs: git reports a fixed worktree list, xcrun a fixed simulator list and records the
# deletions. Folders live in a temporary directory, so nothing outside it is touched.
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

source "$ROOT/scripts/test-env.sh" # only for tagwerk_checkout_key_for

MAIN_CHECKOUT="$WORK_DIR/checkouts/main-checkout"
LIVE_WORKTREE="$WORK_DIR/checkouts/live-worktree"
REMOVED_WORKTREE="$WORK_DIR/checkouts/removed-worktree"   # listed by git, folder is gone (prunable)
mkdir -p "$MAIN_CHECKOUT" "$LIVE_WORKTREE"
MAIN_KEY=$(tagwerk_checkout_key_for "$MAIN_CHECKOUT")
LIVE_KEY=$(tagwerk_checkout_key_for "$LIVE_WORKTREE")
REMOVED_KEY=$(tagwerk_checkout_key_for "$REMOVED_WORKTREE")
ORPHAN_KEY="orphan-tree-11111111"
BUSY_KEY="busy-tree-22222222"
BOOTED_KEY="booted-tree-33333333"

STUB_BIN="$WORK_DIR/bin"
mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/git" <<STUB
#!/bin/zsh
cat <<'LIST'
worktree $MAIN_CHECKOUT
HEAD 0000000000000000000000000000000000000000
branch refs/heads/main

worktree $LIVE_WORKTREE
HEAD 0000000000000000000000000000000000000000
branch refs/heads/feature

worktree $REMOVED_WORKTREE
HEAD 0000000000000000000000000000000000000000
branch refs/heads/old
prunable gitdir file points to non-existent location
LIST
STUB
cat > "$STUB_BIN/xcrun" <<STUB
#!/bin/zsh
print -r -- "\$*" >> "\$STUB_XCRUN_CALLS"
case "\$*" in
  "simctl list devices available -j") cat <<'JSON'
{"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-2": [
  {"name": "Tagwerk Tests Slot 1", "udid": "UDID-SLOT-1", "state": "Shutdown"},
  {"name": "Tagwerk Tests $LIVE_KEY", "udid": "UDID-LIVE", "state": "Shutdown"},
  {"name": "Tagwerk Tests $REMOVED_KEY", "udid": "UDID-REMOVED", "state": "Shutdown"},
  {"name": "Tagwerk Tests $ORPHAN_KEY", "udid": "UDID-ORPHAN", "state": "Shutdown"},
  {"name": "Tagwerk Tests $BUSY_KEY", "udid": "UDID-BUSY", "state": "Shutdown"},
  {"name": "Tagwerk Tests $BOOTED_KEY", "udid": "UDID-BOOTED", "state": "Booted"},
  {"name": "iPhone 18 Pro", "udid": "UDID-OTHER", "state": "Shutdown"}
]}}
JSON
  ;;
esac
STUB
chmod +x "$STUB_BIN"/*

export PATH="$STUB_BIN:$PATH"
export STUB_XCRUN_CALLS="$WORK_DIR/xcrun-calls.txt"
export TMPDIR="$WORK_DIR/tmp"
export TAGWERK_CLEAN_ROOT="$WORK_DIR/Tagwerk"

# A live process that stands for the test run of the busy checkout.
sleep 120 &
RUNNING_PID=$!
LIVE_PIDS+=("$RUNNING_PID")
mkdir -p "$TMPDIR/tagwerk-tests/$BUSY_KEY/run.lock"
print -r -- "$RUNNING_PID" > "$TMPDIR/tagwerk-tests/$BUSY_KEY/run.lock/pid"

reset_folders() {
  rm -rf "$TAGWERK_CLEAN_ROOT"
  local key
  for key in "$MAIN_KEY" "$LIVE_KEY" "$REMOVED_KEY" "$ORPHAN_KEY" "$BUSY_KEY"; do
    mkdir -p "$TAGWERK_CLEAN_ROOT/DerivedData-tests-$key"
    print data > "$TAGWERK_CLEAN_ROOT/DerivedData-tests-$key/file"
  done
  mkdir -p "$TAGWERK_CLEAN_ROOT/DerivedData-dev" "$TAGWERK_CLEAN_ROOT/DerivedData-ci"
  : > "$STUB_XCRUN_CALLS"
}
exists() { [[ -d "$TAGWERK_CLEAN_ROOT/$1" ]] && print yes || print no; }
deleted() { grep -c "simctl delete $1\$" "$STUB_XCRUN_CALLS" || true; }

print -- "-- dry run (default)"
reset_folders
output=$("$ROOT/scripts/clean-test-env.sh" 2>&1); rc=$?
check "dry run succeeds" "0" "$rc"
check "dry run deletes no simulator" "0" "$(grep -c 'simctl delete' "$STUB_XCRUN_CALLS" || true)"
check "dry run keeps every folder" "yes yes yes yes yes" \
  "$(exists DerivedData-tests-$MAIN_KEY) $(exists DerivedData-tests-$LIVE_KEY) $(exists DerivedData-tests-$REMOVED_KEY) $(exists DerivedData-tests-$ORPHAN_KEY) $(exists DerivedData-tests-$BUSY_KEY)"
check "dry run lists the simulator without a worktree" "1" "$([[ "$output" == *"would delete  Tagwerk Tests $ORPHAN_KEY (UDID-ORPHAN"* ]] && print 1 || print 0)"
check "dry run lists the simulator of the removed worktree" "1" "$([[ "$output" == *"would delete  Tagwerk Tests $REMOVED_KEY"* ]] && print 1 || print 0)"
check "dry run lists the orphan folder" "1" "$([[ "$output" == *"would delete  DerivedData-tests-$ORPHAN_KEY"* ]] && print 1 || print 0)"
check "dry run lists the folder of the removed worktree" "1" "$([[ "$output" == *"would delete  DerivedData-tests-$REMOVED_KEY"* ]] && print 1 || print 0)"
check "folders and simulators of existing worktrees are not listed" "0" \
  "$(print -r -- "$output" | grep -cE "would delete .*($MAIN_KEY|$LIVE_KEY)" || true)"
check "pool slots are reported as kept" "1" "$([[ "$output" == *"Tagwerk Tests Slot 1 (Shutdown)"* && "$output" != *"would delete  Tagwerk Tests Slot"* ]] && print 1 || print 0)"
check "a booted simulator is skipped with a hint" "1" "$([[ "$output" == *"skipped  Tagwerk Tests $BOOTED_KEY (Booted, shut it down first)"* ]] && print 1 || print 0)"
check "a checkout with an active run is skipped" "1" \
  "$([[ "$output" == *"skipped  Tagwerk Tests $BUSY_KEY (a test run of this checkout is active)"* && "$output" == *"skipped  DerivedData-tests-$BUSY_KEY (a test run"* ]] && print 1 || print 0)"
check "the summary says it was a dry run" "1" "$([[ "$output" == *"Dry run: 2 simulator(s) and 2 folder(s) would be deleted. Run with --apply"* ]] && print 1 || print 0)"

print -- "-- --apply"
reset_folders
output=$("$ROOT/scripts/clean-test-env.sh" --apply 2>&1); rc=$?
check "apply succeeds" "0" "$rc"
check "apply deletes the simulators without a worktree" "1 1" "$(deleted UDID-ORPHAN) $(deleted UDID-REMOVED)"
check "apply keeps the other simulators" "0 0 0 0 0 0" \
  "$(deleted UDID-LIVE) $(deleted UDID-SLOT-1) $(deleted UDID-BUSY) $(deleted UDID-BOOTED) $(deleted UDID-OTHER) $(grep -c 'simctl shutdown' "$STUB_XCRUN_CALLS" || true)"
check "apply deletes the orphan folders" "no no" "$(exists DerivedData-tests-$ORPHAN_KEY) $(exists DerivedData-tests-$REMOVED_KEY)"
check "apply keeps folders of existing worktrees, the busy checkout and other DerivedData" "yes yes yes yes yes" \
  "$(exists DerivedData-tests-$MAIN_KEY) $(exists DerivedData-tests-$LIVE_KEY) $(exists DerivedData-tests-$BUSY_KEY) $(exists DerivedData-dev) $(exists DerivedData-ci)"
check "the active run is still alive" "1" "$(kill -0 "$RUNNING_PID" 2>/dev/null && print 1 || print 0)"
check "the summary reports the deletions" "1" "$([[ "$output" == *"Done: 2 simulator(s) and 2 folder(s) processed, 0 failure(s)."* ]] && print 1 || print 0)"

print -- "-- --legacy-simulators"
reset_folders
output=$("$ROOT/scripts/clean-test-env.sh" --apply --legacy-simulators 2>&1); rc=$?
check "legacy option also deletes the per-checkout simulator of an existing worktree" "1 1 1" "$(deleted UDID-LIVE) $(deleted UDID-ORPHAN) $(deleted UDID-REMOVED)"
check "legacy option still keeps the pool, the busy and the booted simulator" "0 0 0" "$(deleted UDID-SLOT-1) $(deleted UDID-BUSY) $(deleted UDID-BOOTED)"
check "legacy option leaves the folders of existing worktrees alone" "yes yes" "$(exists DerivedData-tests-$MAIN_KEY) $(exists DerivedData-tests-$LIVE_KEY)"

print -- "-- usage"
"$ROOT/scripts/clean-test-env.sh" --everything > /dev/null 2>&1
check "an unknown option is refused with exit code 2" "2" "$?"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
