#!/bin/zsh
# Watches the Apple ID accounts in Xcode's preferences and records evidence when they disappear.
# The refresh install needs an account in Xcode to renew the 7-day profiles; the account list has emptied without a
# known cause (the preferences file looked like after a first launch of Xcode). This script finds out what removes it.
#
# Started by the LaunchAgent de.tagwerk.xcode-account-watch on every change of the preferences file and every 10 minutes.
# Usage: xcode-account-watch.sh
#
# On every run it counts the accounts and compares the count with the previous run:
#   accounts present  copies the preferences file to xcode-prefs-last-good.plist (for comparison, never restored)
#   accounts lost     writes an evidence file (process list, file metadata, recent preference log, both preference
#                     files), logs one line and shows a macOS notification
#
# Files:
#   $STATE_DIR/xcode-account-count       account count of the previous run
#   $STATE_DIR/xcode-prefs-last-good.plist  last preferences file with at least one account
#   $LOG_DIR/xcode-account.log           one line per change of the account count
#   $LOG_DIR/xcode-account-lost-<time>/  evidence of one loss

set -u

XCODE_PREFS="${XCODE_PREFS:-$HOME/Library/Preferences/com.apple.dt.Xcode.plist}"
STATE_DIR="${TAGWERK_STATE_DIR:-$HOME/Library/Application Support/Tagwerk}"
LOG_DIR="${TAGWERK_LOG_DIR:-$HOME/Library/Logs/Tagwerk}"
COUNT_FILE="$STATE_DIR/xcode-account-count"
LAST_GOOD="$STATE_DIR/xcode-prefs-last-good.plist"
LOG="$LOG_DIR/xcode-account.log"

# --- Decision functions (unit-tested in scripts/tests/xcode-account-watch.zsh) ---

# account_count <preferences file>: prints the number of Apple ID accounts; 0 when the file or the list is missing.
account_count() {
  local listing
  listing=$(/usr/libexec/PlistBuddy -c "Print :DVTDeveloperAccountManagerAppleIDLists:IDE.Identifiers.Prod" "$1" 2>/dev/null) \
    || { print 0; return; }
  print -r -- "$listing" | grep -c "identifier = "
}

# account_transition <previous count or empty> <current count>: lost, restored, unchanged or initial.
account_transition() {
  local previous="$1" current="$2"
  if [[ -z "$previous" ]]; then print initial
  elif (( previous > 0 && current == 0 )); then print lost
  elif (( previous == 0 && current > 0 )); then print restored
  else print unchanged
  fi
}

[[ "${TAGWERK_SOURCE_ONLY:-0}" == "1" ]] && return 0

mkdir -p "$STATE_DIR" "$LOG_DIR"

log() {
  print -r -- "$(/bin/date '+%Y-%m-%dT%H:%M:%S') $1" >> "$LOG"
}

notify() {
  [[ "${TAGWERK_QUIET:-0}" == "1" ]] && return 0
  /usr/bin/osascript -e "display notification \"$1\" with title \"Tagwerk\"" >/dev/null 2>&1 || true
}

# record_evidence <folder>: everything that can point to the process that emptied the account list.
record_evidence() {
  local dir="$1"
  mkdir -p "$dir"
  {
    print "time: $(/bin/date '+%Y-%m-%dT%H:%M:%S%z')"
    print "preferences file:"
    /usr/bin/stat -f "  modified %Sm, created %SB, size %z bytes, inode %i" "$XCODE_PREFS" 2>&1
    print "uptime: $(/usr/bin/uptime)"
  } > "$dir/summary.txt"
  # Newest processes last: a process that ran `defaults` or deleted the file is most likely among the recent ones.
  /bin/ps -axww -o pid,ppid,user,lstart,etime,command > "$dir/processes.txt" 2>&1
  [[ -f "$XCODE_PREFS" ]] && cp -p "$XCODE_PREFS" "$dir/current.plist"
  [[ -f "$LAST_GOOD" ]] && cp -p "$LAST_GOOD" "$dir/last-good.plist"
  # The unified log keeps preference writes only briefly; capture them now, bounded in time.
  /usr/bin/log show --last 20m --style compact \
    --predicate 'process == "cfprefsd" OR process == "defaults" OR process == "Xcode" OR process == "xcodebuild" OR eventMessage CONTAINS "com.apple.dt.Xcode"' \
    > "$dir/unified-log.txt" 2>&1 &
  local log_pid=$!
  ( sleep 120; kill $log_pid 2>/dev/null ) &
  wait $log_pid 2>/dev/null
}

current=$(account_count "$XCODE_PREFS")
previous=$(cat "$COUNT_FILE" 2>/dev/null || true)
transition=$(account_transition "$previous" "$current")

case "$transition" in
  lost)
    evidence="$LOG_DIR/xcode-account-lost-$(/bin/date '+%Y%m%d-%H%M%S')"
    record_evidence "$evidence"
    log "accounts: lost ($previous -> 0), evidence in $evidence"
    notify "Xcode hat die Apple-ID verloren. Spuren unter ~/Library/Logs/Tagwerk gesichert."
    ;;
  restored) log "accounts: restored (0 -> $current)" ;;
  initial) log "accounts: watching ($current)" ;;
esac

if (( current > 0 )); then
  cp -p "$XCODE_PREFS" "$LAST_GOOD.tmp" 2>/dev/null && mv -f "$LAST_GOOD.tmp" "$LAST_GOOD"
fi
print -r -- "$current" > "$COUNT_FILE"
exit 0
