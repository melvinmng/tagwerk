#!/bin/zsh
# Tests for scripts/ci-collect-artifacts.sh (run: zsh scripts/tests/ci-collect-artifacts.zsh).
# A sleep process stands in for the orphans of a hung run; nothing else is touched.
set -u
ROOT="${0:A:h:h:h}"
WORK_DIR=$(mktemp -d)
trap 'pkill -f "^sleep 4343" 2> /dev/null; rm -rf "$WORK_DIR"' EXIT

failures=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1"$'\n'"     expected: $2"$'\n'"     actual:   $3"; failures=$((failures + 1)); fi
}
SCRIPT="$ROOT/scripts/ci-collect-artifacts.sh"
mkdir -p "$WORK_DIR/logs/watchdog-ui-120000" "$WORK_DIR/results"
print "log line" > "$WORK_DIR/logs/app-UI-tests.log"
print "summary" > "$WORK_DIR/logs/watchdog-ui-120000/summary.txt"
print "bundle" > "$WORK_DIR/results/app-UI-tests.xcresult"

# Outside GitHub Actions and without --force, no process is stopped.
sleep 4343 &
orphan=$!
env -u GITHUB_ACTIONS "$SCRIPT" --kill-pattern '^sleep 4343' "$WORK_DIR/a.tar.gz" "$WORK_DIR/logs" "$WORK_DIR/results" > "$WORK_DIR/out1.txt" 2>&1
check "exit code 0" "0" "$?"
check "without --force the process is left alone" "1" "$(kill -0 $orphan 2> /dev/null && print 1 || print 0)"

# With --force it is stopped, and the archive holds both folders.
GITHUB_OUTPUT="$WORK_DIR/output.txt" "$SCRIPT" --force --kill-pattern '^sleep 4343' "$WORK_DIR/b.tar.gz" "$WORK_DIR/logs" "$WORK_DIR/missing" "$WORK_DIR/results" > "$WORK_DIR/out2.txt" 2>&1
check "exit code 0 with --force" "0" "$?"
wait $orphan 2> /dev/null
check "with --force the leftover process is stopped" "0" "$(kill -0 $orphan 2> /dev/null && print 1 || print 0)"
check "the output names the stopped process" "1" "$(grep -c 'sleep 4343' "$WORK_DIR/out2.txt")"
listing=$(tar -tzf "$WORK_DIR/b.tar.gz")
check "the archive holds the logs" "1" "$(print -r -- "$listing" | grep -c 'logs/app-UI-tests.log$')"
check "the archive holds the diagnostics" "1" "$(print -r -- "$listing" | grep -c 'watchdog-ui-120000/summary.txt$')"
check "the archive holds the result bundle" "1" "$(print -r -- "$listing" | grep -c 'results/app-UI-tests.xcresult$')"
check "diagnostics are reported to the workflow" "diagnostics=true" "$(cat "$WORK_DIR/output.txt")"

# Without diagnostics the output says false; without any folder there is no archive.
rm -rf "$WORK_DIR/logs/watchdog-ui-120000"
: > "$WORK_DIR/output.txt"
GITHUB_OUTPUT="$WORK_DIR/output.txt" "$SCRIPT" --force --kill-pattern '^sleep 4343' "$WORK_DIR/c.tar.gz" "$WORK_DIR/logs" > /dev/null 2>&1
check "no diagnostics: false" "diagnostics=false" "$(cat "$WORK_DIR/output.txt")"
"$SCRIPT" --force --kill-pattern '^sleep 4343' "$WORK_DIR/d.tar.gz" "$WORK_DIR/none" > /dev/null 2>&1
check "no folder: no archive, exit code 0" "0 0" "$? $([[ -e "$WORK_DIR/d.tar.gz" ]] && print 1 || print 0)"

check "too few arguments: usage error" "64" "$("$SCRIPT" "$WORK_DIR/e.tar.gz" > /dev/null 2>&1; print $?)"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
