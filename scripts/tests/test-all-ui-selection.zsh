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
    unset TAGWERK_UI_TEST_SET TAGWERK_UI_ONLY TAGWERK_UI_TEST_RETRIES TAGWERK_SKIP_UI_TESTS TAGWERK_ONLY_UI_TESTS TAGWERK_UI_SHARD
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

# The real list of the repository. The expected arguments come from the file itself (one -skip-testing per entry), so the check
# keeps working when a test moves to the nightly list; what it proves is the translation, not the content of the list.
skip_arguments=$(grep -vE '^[[:space:]]*(#|$)' "$ROOT/app/TagwerkUITests/nightly-only.txt" | sed -e 's/[[:space:]]//g' -e 's#^#-skip-testing:TagwerkUITests/#')
check "the repository list is not empty" "1" "$([[ -n "$skip_arguments" ]] && print 1 || print 0)"
check "pr set from the repository list" "$skip_arguments"$'\nrc=0' "$(selection TAGWERK_UI_TEST_SET=pr)"
# The retry is a second xcodebuild call (run_ui_tests), no longer an argument of the first one.
check "retries add no selection argument"  "$skip_arguments"$'\nrc=0' "$(selection TAGWERK_UI_TEST_SET=pr TAGWERK_UI_TEST_RETRIES=1)"
check "retries are on without the variable" "1" "$( (unset TAGWERK_UI_TEST_RETRIES; export TAGWERK_SOURCE_ONLY=1; source "$ROOT/app/test-all.sh"; ui_retries_enabled && print 1 || print 0) )"
check "retries are on with 1"  "1" "$( (export TAGWERK_UI_TEST_RETRIES=1 TAGWERK_SOURCE_ONLY=1; source "$ROOT/app/test-all.sh"; ui_retries_enabled && print 1 || print 0) )"
check "retries are off with 0"  "0" "$( (export TAGWERK_UI_TEST_RETRIES=0 TAGWERK_SOURCE_ONLY=1; source "$ROOT/app/test-all.sh"; ui_retries_enabled && print 1 || print 0) )"
check "retries are off when empty" "0" "$( (export TAGWERK_UI_TEST_RETRIES= TAGWERK_SOURCE_ONLY=1; source "$ROOT/app/test-all.sh"; ui_retries_enabled && print 1 || print 0) )"

# Shards (TAGWERK_UI_SHARD): shards 1 to N-1 select their classes (-only-testing); the last shard skips the classes of all the others
# (-skip-testing), so a class that the source scan does not see still runs in the last shard. Together the shards cover the set, and
# the nightly-only entries of the pull request set still apply (as -skip-testing) in every shard.
shard_args() { selection "$@" | grep -E '^-(only|skip)-testing:TagwerkUITests/[A-Za-z0-9_]+(/[A-Za-z0-9_]+)?$' | sort; }
for test_set in pr full; do
  first=$(shard_args TAGWERK_UI_TEST_SET=$test_set TAGWERK_UI_SHARD=1/2 | grep '^-only-testing:')
  last_skips=$(shard_args TAGWERK_UI_TEST_SET=$test_set TAGWERK_UI_SHARD=2/2 | grep '^-skip-testing:' | sed 's/^-skip-/-only-/')
  expected_first=$(/usr/bin/python3 -I "$ROOT/scripts/ui-test-shards.py" shard 1/2 --set $test_set | sed 's#^#-only-testing:TagwerkUITests/#' | sort)
  check "shard $test_set: shard 1 selects its classes" "$expected_first" "$first"
  check "shard $test_set: shard 1 has classes" "1" "$([[ -n "$first" ]] && print 1 || print 0)"
  check "shard $test_set: the last shard has no -only-testing" "" "$(selection TAGWERK_UI_TEST_SET=$test_set TAGWERK_UI_SHARD=2/2 | grep '^-only-testing:')"
  if [[ "$test_set" == "pr" ]]; then
    # The skips of the last shard are the classes of shard 1 plus the nightly-only entries (classes among them are listed twice).
    check "shard $test_set: the last shard skips shard 1 and the nightly-only entries" "$(print -r -- "$first"$'\n'"$(print -r -- "$skip_arguments" | sed 's/^-skip-/-only-/')" | sort -u)" \
      "$(print -r -- "$last_skips" | sort -u)"
  else
    check "shard $test_set: the last shard skips exactly shard 1" "$first" "$last_skips"
  fi
done
check "shard pr: the nightly-only entries are skipped inside shard 1" "$skip_arguments" \
  "$(selection TAGWERK_UI_TEST_SET=pr TAGWERK_UI_SHARD=1/2 | grep '^-skip-testing:')"
check "shard full: shard 1 has no skip arguments" "" "$(selection TAGWERK_UI_TEST_SET=full TAGWERK_UI_SHARD=1/2 | grep '^-skip-testing:')"
check "shard and TAGWERK_UI_ONLY exclude each other" "rc=1" "$(selection TAGWERK_UI_SHARD=1/2 TAGWERK_UI_ONLY=NotesUITests)"
check "shard 3/2 is invalid" "rc=1" "$(selection TAGWERK_UI_SHARD=3/2)"
check "shard 0/2 is invalid" "rc=1" "$(selection TAGWERK_UI_SHARD=0/2)"
check "shard without a slash is invalid" "rc=1" "$(selection TAGWERK_UI_SHARD=2)"

# Every entry of the repository list must name an existing UI test class (a typo would silently skip nothing).
missing_classes=""
while IFS= read -r line || [[ -n "$line" ]]; do
  entry="${line//[[:space:]]/}"
  [[ -z "$entry" || "$entry" == \#* ]] && continue
  grep -qE "^(final )?class ${entry%%/*}\b" "$ROOT"/app/TagwerkUITests/*.swift || missing_classes+="$entry "
done < "$ROOT/app/TagwerkUITests/nightly-only.txt"
check "nightly-only entries name existing classes" "" "$missing_classes"

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
    report_retried_ui_tests "$WORK_DIR/report.md" "$@"
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

# Two attempts in two logs (the retry of the UI stage): failed in the first, passed in the second.
cat > "$WORK_DIR/log-first.txt" <<'LOG'
Test Case '-[TagwerkUITests.TaskFlowUITests testFlaky]' failed (12.3 seconds).
Test Case '-[TagwerkUITests.TaskFlowUITests testBroken]' failed (12.3 seconds).
Test Case '-[TagwerkUITests.TaskFlowUITests testStable]' passed (9.0 seconds).
LOG
cat > "$WORK_DIR/log-second.txt" <<'LOG'
Test Case '-[TagwerkUITests.TaskFlowUITests testFlaky]' passed (10.1 seconds).
Test Case '-[TagwerkUITests.TaskFlowUITests testBroken]' failed (12.0 seconds).
LOG
check "retry report over two attempts" \
  $'RETRIED UI TESTS\n  - TaskFlowUITests/testFlaky' \
  "$(report_output "$WORK_DIR/log-first.txt" "$WORK_DIR/log-second.txt")"

# The tests that failed (last result) are the ones to run again: both log styles, passed tests and retried tests excluded.
failed_of() { /usr/bin/python3 -I "$ROOT/scripts/ui-test-log.py" failed "$@"; }
check "failed tests of a log" "SearchUITests/testBroken" "$(failed_of "$WORK_DIR/log-retry.txt")"
check "failed tests over two attempts" "TaskFlowUITests/testBroken" "$(failed_of "$WORK_DIR/log-first.txt" "$WORK_DIR/log-second.txt")"
check "failed tests of a clean log" "" "$(failed_of "$WORK_DIR/log-clean.txt")"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
