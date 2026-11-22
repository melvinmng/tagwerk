#!/bin/zsh
# Finds the test environments of checkouts that no longer exist and removes them on request.
#
# Every worktree used to get its own simulator "Tagwerk Tests <checkout key>" and its own derived data folder
# ~/Library/Developer/Tagwerk/DerivedData-tests-<checkout key> (see scripts/test-env.sh). Simulators now come from a pool
# ("Tagwerk Tests Slot N"), but derived data is still kept per checkout, and removed worktrees leave both behind.
#
# Usage: scripts/clean-test-env.sh [--apply] [--legacy-simulators]
#   (no option)           dry run: lists what would be deleted, deletes nothing
#   --apply               deletes the listed simulators and derived data folders
#   --legacy-simulators   also lists the per-checkout simulators of worktrees that still exist; the pool replaces them
#
# What counts as an orphan: a simulator "Tagwerk Tests <checkout key>" or a folder DerivedData-tests-<checkout key> whose
# key belongs to none of the worktrees that `git worktree list` reports for this repository (the main checkout included).
# Never touched: the pool simulators "Tagwerk Tests Slot N", simulators that are booted or booting (shut them down first),
# and the environment of a checkout whose test run is active (its run lock names a live process). The script never ends
# a process. Other clones of the repository are not worktrees of this one, so their environments count as orphans too;
# they are rebuilt on the next run.
#
# Environment (for the tests in scripts/tests/clean-test-env.zsh): TAGWERK_CLEAN_ROOT replaces ~/Library/Developer/Tagwerk.
# Exit codes: 0 done (or nothing to do), 1 a deletion failed, 2 usage error or the worktree list could not be read.

set -uo pipefail

export DEVELOPER_DIR="${TAGWERK_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

REPO_ROOT="${0:A:h:h}"
# Only the helper functions are needed, not the checkout settings; sourcing the file is harmless.
source "$REPO_ROOT/scripts/test-env.sh"

APPLY=0
LEGACY=0
for argument in "$@"; do
  case "$argument" in
    --apply) APPLY=1 ;;
    --legacy-simulators) LEGACY=1 ;;
    *) echo "Usage: scripts/clean-test-env.sh [--apply] [--legacy-simulators]" >&2; exit 2 ;;
  esac
done

DERIVED_ROOT="${TAGWERK_CLEAN_ROOT:-$HOME/Library/Developer/Tagwerk}"
LOG_ROOT="${TMPDIR:-/tmp}/tagwerk-tests"

# Checkout keys of all worktrees that exist: the key is the folder name plus a hash of the full path.
if ! worktree_list=$(git -C "$REPO_ROOT" worktree list --porcelain 2>&1); then
  echo "Could not read the worktree list: $worktree_list" >&2
  exit 2
fi
typeset -A live_keys
worktree_path=""
prunable=0
flush_worktree() {
  if [[ -n "$worktree_path" && "$prunable" == 0 && -d "$worktree_path" ]]; then
    live_keys[$(tagwerk_checkout_key_for "$worktree_path")]=1
  fi
  worktree_path=""
  prunable=0
}
while IFS= read -r line; do
  case "$line" in
    "worktree "*) flush_worktree; worktree_path="${line#worktree }" ;;
    prunable*) prunable=1 ;;
  esac
done <<<"$worktree_list"
flush_worktree
echo "Worktrees found: ${#live_keys}"

# True when a test run of this checkout key is active (its run lock names a live process).
run_is_active() {
  local holder
  holder=$(cat "$LOG_ROOT/$1/run.lock/pid" 2>/dev/null || true)
  [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null
}

failures=0
simulators_listed=0
folders_listed=0

echo
echo "Pool slots (kept):"
pool_found=0
while IFS='|' read -r udid state name; do
  [[ "$name" == "Tagwerk Tests Slot "* ]] || continue
  echo "  $name ($state)"
  pool_found=1
done < <(xcrun simctl list devices available -j 2>/dev/null | /usr/bin/python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        print("|".join([device["udid"], device["state"], device["name"]]))
')
(( pool_found )) || echo "  none yet"

echo
echo "Simulators:"
while IFS='|' read -r udid state name; do
  [[ "$name" == "Tagwerk Tests "* && "$name" != "Tagwerk Tests Slot "* ]] || continue
  key="${name#Tagwerk Tests }"
  if [[ -n "${live_keys[$key]:-}" ]]; then
    (( LEGACY )) || continue
    reason="per-checkout simulator of an existing worktree, replaced by the pool"
  else
    reason="no worktree"
  fi
  if [[ "$state" != "Shutdown" ]]; then
    echo "  skipped  $name ($state, shut it down first)"
    continue
  fi
  if run_is_active "$key"; then
    echo "  skipped  $name (a test run of this checkout is active)"
    continue
  fi
  simulators_listed=$((simulators_listed + 1))
  if (( APPLY )); then
    if xcrun simctl delete "$udid" > /dev/null 2>&1; then
      echo "  deleted  $name ($udid, $reason)"
    else
      echo "  FAILED   $name ($udid): simctl delete failed" >&2
      failures=$((failures + 1))
    fi
  else
    echo "  would delete  $name ($udid, $reason)"
  fi
done < <(xcrun simctl list devices available -j 2>/dev/null | /usr/bin/python3 -c '
import json, sys
for devices in json.load(sys.stdin)["devices"].values():
    for device in devices:
        print("|".join([device["udid"], device["state"], device["name"]]))
')
(( simulators_listed > 0 )) || echo "  nothing to delete"

echo
echo "DerivedData folders ($DERIVED_ROOT):"
for folder in "$DERIVED_ROOT"/DerivedData-tests-*(/N); do
  key="${folder:t}"
  key="${key#DerivedData-tests-}"
  [[ -n "$key" ]] || continue
  [[ -z "${live_keys[$key]:-}" ]] || continue
  if run_is_active "$key"; then
    echo "  skipped  ${folder:t} (a test run of this checkout is active)"
    continue
  fi
  folders_listed=$((folders_listed + 1))
  size=$(du -sh "$folder" 2>/dev/null | cut -f1)
  if (( APPLY )); then
    if rm -rf "$folder"; then
      echo "  deleted  ${folder:t} (${size:-?}, no worktree)"
    else
      echo "  FAILED   ${folder:t}: rm failed" >&2
      failures=$((failures + 1))
    fi
  else
    echo "  would delete  ${folder:t} (${size:-?}, no worktree)"
  fi
done
(( folders_listed > 0 )) || echo "  nothing to delete"

echo
if (( APPLY )); then
  echo "Done: $simulators_listed simulator(s) and $folders_listed folder(s) processed, $failures failure(s)."
else
  echo "Dry run: $simulators_listed simulator(s) and $folders_listed folder(s) would be deleted. Run with --apply to delete them."
fi
(( failures == 0 )) || exit 1
