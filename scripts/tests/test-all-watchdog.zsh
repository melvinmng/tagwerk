#!/bin/zsh
# Tests for the watchdog of app/test-all.sh (run: zsh scripts/tests/test-all-watchdog.zsh).
# xcodebuild, xcodegen and xcrun are replaced by stubs: with STUB_HANG=1 the UI test call prints one line and then stays silent.
# No build, simulator or test runs.
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
cat > "$STUB_BIN/xcodebuild" <<'STUB'
#!/bin/zsh
print -r -- "$*" >> "$STUB_XCODEBUILD_CALLS"
case "$*" in
  *-list*) print '{"workspace": {"schemes": []}}' ;;
  *-showBuildSettings*) print '    PRODUCT_BUNDLE_IDENTIFIER = de.tagwerk.stub' ;;
  test-without-building*-scheme\ TagwerkUITests*)
    print "Test Case '-[TagwerkUITests.StableUITests testStable]' started."
    print "Test Case '-[TagwerkUITests.StableUITests testStable]' passed (1.0 seconds)."
    if [[ -n "${STUB_HANG:-}" ]]; then
      print "Test Case '-[TagwerkUITests.HangUITests testHang]' started."
      sleep 4242
    fi
    print "Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.0) seconds" ;;
  *) ;;
esac
STUB
for tool in xcodegen xcrun; do print '#!/bin/zsh' > "$STUB_BIN/$tool"; done
chmod +x "$STUB_BIN"/*

SIMULATOR_ID="00000000-0000-0000-0000-000000000000"
run_ui_stage() {
  : > "$WORK_DIR/calls.txt"
  rm -rf "$WORK_DIR/logs"
  (
    unset TAGWERK_SKIP_UI_TESTS TAGWERK_UI_ONLY TAGWERK_UI_TEST_SET TAGWERK_UI_TEST_RETRIES TAGWERK_BUILD_ONLY STUB_HANG
    export PATH="$STUB_BIN:$PATH" STUB_XCODEBUILD_CALLS="$WORK_DIR/calls.txt" TAGWERK_ONLY_UI_TESTS=1
    export TAGWERK_TEST_SIMULATOR="$SIMULATOR_ID" TAGWERK_TEST_DERIVED_DATA="$WORK_DIR/derived" TAGWERK_TEST_LOG_DIR="$WORK_DIR/logs"
    export TAGWERK_LOCK_DIR="$WORK_DIR/locks" TAGWERK_HEARTBEAT_SECONDS=1
    local assignment
    for assignment in "$@"; do export "$assignment"; done
    "$ROOT/app/test-all.sh" > "$WORK_DIR/output.txt" 2> "$WORK_DIR/errors.txt"
  )
  print "rc=$?"
}

check "a healthy run is green" "rc=0" "$(run_ui_stage)"
check "the progress of the tests is on stdout" "1" "$(grep -c 'passed  -\[TagwerkUITests.StableUITests testStable\]' "$WORK_DIR/output.txt")"
check "a phase line announces the test call" "1" "$(grep -c 'app UI tests: xcodebuild test-without-building started' "$WORK_DIR/output.txt")"
check "no diagnostics without a hang" "0" "$(print -l "$WORK_DIR"/logs/watchdog-*(N) | grep -c . || true)"

check "a silent test run is stopped: red" "rc=1" "$(run_ui_stage STUB_HANG=1 TAGWERK_UI_SILENCE_SECONDS=2)"
check "the failure names the stage and the watchdog" "1" "$(grep -c '^HUNG in stage: app UI tests' "$WORK_DIR/errors.txt")"
check "the message names the phase and the reason" "1" "$(grep -c 'WATCHDOG: phase "app UI tests: app-UI-tests test-without-building" stopped: no log output for' "$WORK_DIR/errors.txt")"
check "the diagnostics are written" "1" "$([[ -s "$(ls -d "$WORK_DIR"/logs/watchdog-*/summary.txt | head -n 1)" ]] && print 1 || print 0)"
check "the diagnostics name the running test" "1" "$(grep -c 'current: .*HangUITests testHang' "$WORK_DIR"/logs/watchdog-*/summary.txt)"
check "a hang is not retried" "1" "$(grep -c '^test-without-building ' "$WORK_DIR/calls.txt")"
check "the stopped command is gone" "" "$(pgrep -f 'sleep 4242' || true)"
check "a test run that was never stopped by the watchdog is not marked as a hang" "0" "$(grep -c '^TESTS FAILED' "$WORK_DIR/errors.txt")"

check "a run time limit stops the run as well" "rc=1" "$(run_ui_stage STUB_HANG=1 TAGWERK_UI_SILENCE_SECONDS=0 TAGWERK_UI_MAX_SECONDS=2)"
check "the run time limit is named" "1" "$(grep -c 'run time limit of 2 s reached' "$WORK_DIR/errors.txt")"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
