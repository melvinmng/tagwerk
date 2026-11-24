#!/bin/zsh
# Tests for the retry of failed UI tests in app/test-all.sh (run: zsh scripts/tests/test-all-ui-retry.zsh).
# xcodebuild, xcodegen and xcrun are replaced by stubs: the first UI test call reports the tests named in STUB_FIRST_FAILURES
# as failed, a call with -only-testing reports the tests named in STUB_RETRY_FAILURES as failed and every other one as passed.
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
report() { # outcome tests...
  local outcome="$1" name; shift
  for name in "$@"; do print "Test Case '-[TagwerkUITests.${name%%/*} ${name##*/}]' $outcome (1.0 seconds)."; done
}
case "$*" in
  *-list*) print '{"workspace": {"schemes": []}}' ;;
  *-showBuildSettings*) print '    PRODUCT_BUNDLE_IDENTIFIER = de.tagwerk.stub' ;;
  test-without-building*-scheme\ TagwerkUITests*)
    if [[ "$*" == *-only-testing:* ]]; then
      local entries=(${(M)${=*}:#-only-testing:*}) entry failed=(${=STUB_RETRY_FAILURES:-}) tests=()
      for entry in $entries; do tests+=("${entry#-only-testing:TagwerkUITests/}"); done
      report passed ${tests:|failed}
      if (( ${#failed} > 0 )); then report failed $failed; print "Executed ${#tests} tests, with ${#failed} failures (0 unexpected) in 1.0 (1.0) seconds"; exit 65; fi
      print "Executed ${#tests} tests, with 0 failures (0 unexpected) in 1.0 (1.0) seconds"
    else
      local failed=(${=STUB_FIRST_FAILURES:-})
      report passed StableUITests/testStable
      if (( ${#failed} > 0 )); then report failed $failed; print "Executed 3 tests, with ${#failed} failures (0 unexpected) in 1.0 (1.0) seconds"; exit 65; fi
      print "Executed 3 tests, with 0 failures (0 unexpected) in 1.0 (1.0) seconds"
    fi ;;
  *) ;;
esac
STUB
cat > "$STUB_BIN/xcodegen" <<'STUB'
#!/bin/zsh
STUB
cat > "$STUB_BIN/xcrun" <<'STUB'
#!/bin/zsh
STUB
chmod +x "$STUB_BIN"/*

SIMULATOR_ID="00000000-0000-0000-0000-000000000000"

# Runs the UI stage with the stubs and the given environment assignments; prints "rc=<exit code>". The output of the script is
# in $WORK_DIR/output.txt, the xcodebuild calls in $WORK_DIR/calls.txt and the logs in $WORK_DIR/logs.
run_ui_stage() {
  local assignment
  : > "$WORK_DIR/calls.txt"
  rm -rf "$WORK_DIR/logs"
  (
    unset TAGWERK_SKIP_UI_TESTS TAGWERK_UI_ONLY TAGWERK_UI_TEST_SET TAGWERK_UI_TEST_RETRIES TAGWERK_BUILD_ONLY STUB_FIRST_FAILURES STUB_RETRY_FAILURES
    export PATH="$STUB_BIN:$PATH" STUB_XCODEBUILD_CALLS="$WORK_DIR/calls.txt" TAGWERK_ONLY_UI_TESTS=1
    export TAGWERK_TEST_SIMULATOR="$SIMULATOR_ID" TAGWERK_TEST_DERIVED_DATA="$WORK_DIR/derived" TAGWERK_TEST_LOG_DIR="$WORK_DIR/logs"
    export TAGWERK_LOCK_DIR="$WORK_DIR/locks"
    for assignment in "$@"; do export "$assignment"; done
    "$ROOT/app/test-all.sh" > "$WORK_DIR/output.txt" 2>&1
  )
  print "rc=$?"
}
test_calls() { grep -c '^test-without-building ' "$WORK_DIR/calls.txt"; }

check "no failure: green, one test call, nothing retried" $'rc=0\n1\nRETRIED UI TESTS\n  none' \
  "$(run_ui_stage; test_calls; cat "$WORK_DIR/logs/retried-ui-tests.md")"

check "a flaky test: the second call runs only that test and the stage is green" "rc=0" \
  "$(run_ui_stage 'STUB_FIRST_FAILURES=FlakyUITests/testFlaky')"
check "a flaky test: two test calls" "2" "$(test_calls)"
check "a flaky test: the second call selects the failed test only" "1" \
  "$(grep '^test-without-building ' "$WORK_DIR/calls.txt" | tail -n 1 | grep -cE -- '-only-testing:TagwerkUITests/FlakyUITests/testFlaky( |$)')"
check "a flaky test: the second call selects nothing else" "1" \
  "$(grep '^test-without-building ' "$WORK_DIR/calls.txt" | tail -n 1 | grep -o -- '-only-testing:[^ ]*' | wc -l | tr -d ' ')"
check "a flaky test: the second attempt has its own log and result name" "1" "$([[ -s "$WORK_DIR/logs/app-UI-tests-retry.log" ]] && print 1 || print 0)"
check "a flaky test: the report lists it" $'RETRIED UI TESTS\n  - FlakyUITests/testFlaky' "$(cat "$WORK_DIR/logs/retried-ui-tests.md")"

check "a test that fails twice: red" "rc=1" "$(run_ui_stage 'STUB_FIRST_FAILURES=FlakyUITests/testFlaky BrokenUITests/testBroken' 'STUB_RETRY_FAILURES=BrokenUITests/testBroken')"
check "a test that fails twice: both were run again" "2" "$(test_calls)"
check "a test that fails twice: only the one that failed twice is not reported as retried" $'RETRIED UI TESTS\n  - FlakyUITests/testFlaky' "$(cat "$WORK_DIR/logs/retried-ui-tests.md")"
check "a test that fails twice: the failure is named" "1" "$(grep -c '^TESTS FAILED in stage: app UI tests$' "$WORK_DIR/output.txt")"

check "more than five failed tests: red, not retried" "rc=1" \
  "$(run_ui_stage 'STUB_FIRST_FAILURES=A/testA B/testB C/testC D/testD E/testE F/testF')"
check "more than five failed tests: one test call" "1" "$(test_calls)"

check "retries off with 0: red, one test call" $'rc=1\n1' "$(run_ui_stage 'TAGWERK_UI_TEST_RETRIES=0' 'STUB_FIRST_FAILURES=FlakyUITests/testFlaky'; test_calls)"
check "retries off when empty: red, one test call" $'rc=1\n1' "$(run_ui_stage 'TAGWERK_UI_TEST_RETRIES=' 'STUB_FIRST_FAILURES=FlakyUITests/testFlaky'; test_calls)"
check "no retry argument of xcodebuild is used" "0" "$(grep -c -- '-retry-tests-on-failure\|-test-iterations' "$WORK_DIR/calls.txt")"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
