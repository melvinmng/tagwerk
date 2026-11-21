#!/bin/zsh
# Tests for the UI test selection and retry reporting of app/test-all.sh (run: zsh scripts/tests/test-all-ui-selection.zsh).
# Only the argument building and the log parsing run; no xcodebuild, simulator or test stage is started.
set -u
ROOT="${0:A:h:h:h}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

failures=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1"$'\n'"     expected: $2"$'\n'"     actual:   $3"; failures=$((failures + 1)); fi
}

# Runs build_ui_selection_args in a clean subshell with the given environment assignments and prints the arguments,
# one per line, followed by "rc=<exit code>". The one-line summary on stdout is dropped.
selection() {
  (
    unset TAGWERK_UI_TEST_SET TAGWERK_UI_ONLY TAGWERK_UI_TEST_RETRIES TAGWERK_SKIP_UI_TESTS TAGWERK_ONLY_UI_TESTS
    export TAGWERK_SOURCE_ONLY=1
    local assignment
    for assignment in "$@"; do export "$assignment"; done
    source "$ROOT/app/test-all.sh"
    local rc=0
    build_ui_selection_args > /dev/null 2>&1 || rc=$?
    (( ${#UI_SELECTION_ARGS} == 0 )) || print -rl -- "${UI_SELECTION_ARGS[@]}"
    print "rc=$rc"
  )
}

# Defaults keep the local behaviour: no selection arguments at all.
check "no variables"                  "rc=0" "$(selection)"
check "full set"                      "rc=0" "$(selection TAGWERK_UI_TEST_SET=full)"
check "retries off with 0"            "rc=0" "$(selection TAGWERK_UI_TEST_RETRIES=0)"

# The real list of the repository.
expected_pr=$'-skip-testing:TagwerkUITests/AccessibilityAuditRecipesLargeTextUITests\nrc=0'
check "pr set from the repository list" "$expected_pr" "$(selection TAGWERK_UI_TEST_SET=pr)"
check "pr set with one retry" \
  $'-skip-testing:TagwerkUITests/AccessibilityAuditRecipesLargeTextUITests\n-retry-tests-on-failure\n-test-iterations\n2\nrc=0' \
  "$(selection TAGWERK_UI_TEST_SET=pr TAGWERK_UI_TEST_RETRIES=1)"
check "full set with one retry" \
  $'-retry-tests-on-failure\n-test-iterations\n2\nrc=0' \
  "$(selection TAGWERK_UI_TEST_RETRIES=1)"

# A synthetic list: comments, empty lines, whitespace and CRLF line endings are tolerated, the last line has no newline.
print -n $'# comment\n\n  ClassA  \r\nClassB/testOne\n   # indented comment\nClassC' > "$WORK_DIR/list.txt"
check "list parsing" \
  $'-skip-testing:TagwerkUITests/ClassA\n-skip-testing:TagwerkUITests/ClassB/testOne\n-skip-testing:TagwerkUITests/ClassC\nrc=0' \
  "$(selection TAGWERK_UI_TEST_SET=pr TAGWERK_NIGHTLY_ONLY_FILE=$WORK_DIR/list.txt)"
: > "$WORK_DIR/empty.txt"
check "empty list skips nothing"      "rc=0" "$(selection TAGWERK_UI_TEST_SET=pr TAGWERK_NIGHTLY_ONLY_FILE=$WORK_DIR/empty.txt)"
check "missing list fails the pr set" "rc=1" "$(selection TAGWERK_UI_TEST_SET=pr TAGWERK_NIGHTLY_ONLY_FILE=$WORK_DIR/missing.txt)"
check "missing list is ignored in the full set" "rc=0" "$(selection TAGWERK_UI_TEST_SET=full TAGWERK_NIGHTLY_ONLY_FILE=$WORK_DIR/missing.txt)"
print -n 'Bad Entry:x' > "$WORK_DIR/bad.txt"
check "invalid list entry fails"      "rc=1" "$(selection TAGWERK_UI_TEST_SET=pr TAGWERK_NIGHTLY_ONLY_FILE=$WORK_DIR/bad.txt)"

# TAGWERK_UI_ONLY wins over the set and does not apply the nightly list.
check "only, two entries" \
  $'-only-testing:TagwerkUITests/TaskFlowUITests\n-only-testing:TagwerkUITests/SearchUITests/testFoo\nrc=0' \
  "$(selection 'TAGWERK_UI_ONLY=TaskFlowUITests   SearchUITests/testFoo')"
check "only wins over the pr set" \
  $'-only-testing:TagwerkUITests/AccessibilityAuditRecipesLargeTextUITests\nrc=0' \
  "$(selection TAGWERK_UI_TEST_SET=pr TAGWERK_UI_ONLY=AccessibilityAuditRecipesLargeTextUITests)"
check "invalid only entry fails"      "rc=1" "$(selection 'TAGWERK_UI_ONLY=Class;rm')"
check "invalid set fails"             "rc=1" "$(selection TAGWERK_UI_TEST_SET=nightly)"
check "invalid retries fail"          "rc=1" "$(selection TAGWERK_UI_TEST_RETRIES=2)"

# TAGWERK_UI_ONLY implies TAGWERK_ONLY_UI_TESTS and excludes the skip switch.
check "only implies the UI-only mode" "1" "$(
  unset TAGWERK_SKIP_UI_TESTS TAGWERK_ONLY_UI_TESTS; TAGWERK_SOURCE_ONLY=1 TAGWERK_UI_ONLY=TaskFlowUITests
  export TAGWERK_SOURCE_ONLY TAGWERK_UI_ONLY; source "$ROOT/app/test-all.sh"; print -r -- "${TAGWERK_ONLY_UI_TESTS:-}")"
check "only and skip conflict" "1" "$(
  (export TAGWERK_SOURCE_ONLY=1 TAGWERK_UI_ONLY=TaskFlowUITests TAGWERK_SKIP_UI_TESTS=1; source "$ROOT/app/test-all.sh") > /dev/null 2>&1; print -r -- $?)"

# Retry report: classic XCTest lines and the newer "passed on <device>" lines.
cat > "$WORK_DIR/log-retry.txt" <<'LOG'
Test Suite 'TaskFlowUITests' started
Test Case '-[TagwerkUITests.TaskFlowUITests testFlaky]' started.
Test Case '-[TagwerkUITests.TaskFlowUITests testFlaky]' failed (12.3 seconds).
Test Case '-[TagwerkUITests.TaskFlowUITests testFlaky]' started.
Test Case '-[TagwerkUITests.TaskFlowUITests testFlaky]' passed (10.1 seconds).
Test Case '-[TagwerkUITests.TaskFlowUITests testStable]' passed (9.0 seconds).
Test case 'SearchUITests.testNewStyle()' failed on 'Clone 1 of iPhone 18 Pro - Tagwerk' (8.0 seconds)
Test case 'SearchUITests.testNewStyle()' passed on 'Clone 1 of iPhone 18 Pro - Tagwerk' (7.5 seconds)
Test case 'SearchUITests.testBroken()' failed on 'iPhone 18 Pro' (8.0 seconds)
Test case 'SearchUITests.testBroken()' failed on 'iPhone 18 Pro' (8.0 seconds)
LOG
report_output() { # log
  (
    export TAGWERK_SOURCE_ONLY=1
    source "$ROOT/app/test-all.sh"
    report_retried_ui_tests "$1" "$WORK_DIR/report.md"
  )
}
check "retry report lists flaky tests only" \
  $'RETRIED UI TESTS\n  - SearchUITests/testNewStyle\n  - TaskFlowUITests/testFlaky' \
  "$(report_output "$WORK_DIR/log-retry.txt")"
check "retry report file matches the output" "$(report_output "$WORK_DIR/log-retry.txt")" "$(cat "$WORK_DIR/report.md")"
print -n $'Test Case \'-[TagwerkUITests.TaskFlowUITests testStable]\' passed (9.0 seconds).\n' > "$WORK_DIR/log-clean.txt"
check "retry report without retries" $'RETRIED UI TESTS\n  none' "$(report_output "$WORK_DIR/log-clean.txt")"
print -n $'Executed 20 tests, with 1 failure (0 unexpected) in 100.0 (100.1) seconds\n' > "$WORK_DIR/log-unparsed.txt"
check "retry report flags unreadable logs" \
  $'RETRIED UI TESTS\n  The log reports failed attempts, but no test names could be read from it (log: '"$WORK_DIR/log-unparsed.txt)" \
  "$(report_output "$WORK_DIR/log-unparsed.txt")"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
