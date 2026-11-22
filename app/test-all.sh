#!/bin/zsh
# Runs all test stages: every local Swift package under app/Packages, the app scheme and the UI tests.
# Stops at the first failing stage and reports which one failed.
#
# Gate rule: CI (GitHub Actions, jobs "Tests (fast)" and "Tests (ui)") is the gate before a merge.
# Locally, run the fast stages after every commit (TAGWERK_SKIP_UI_TESTS=1) and, while working on a screen, only the
# UI test classes the change touches (TAGWERK_UI_ONLY). The full local UI run is only the fallback when CI is
# unavailable (GitHub outage, queue longer than 30 minutes).
#
# Environment overrides (unset means the local behaviour):
#   TAGWERK_SKIP_UI_TESTS=1    skip the UI test stage (fast local iterations)
#   TAGWERK_DEVELOPER_DIR      Xcode developer directory instead of /Applications/Xcode.app
#   TAGWERK_ONLY_UI_TESTS=1    run only the UI test stage (no package stages, no app unit tests, no String Catalog check)
#   TAGWERK_TEST_RESULTS_DIR   folder for one .xcresult bundle per stage (see run_tests)
#   TAGWERK_BUILD_ONLY=1       build, do not test: every stage that would run tests runs xcodebuild build-for-testing
#                              instead, with the same schemes, destination and derived data folders, so the build
#                              products are the ones a test run would produce. Used by CI to refresh the build cache
#                              after a merge. Combines with TAGWERK_SKIP_UI_TESTS and TAGWERK_ONLY_UI_TESTS to select
#                              the stages (packages and app, or only the UI test runner). The simulator is not
#                              booted, no permissions are granted, the String Catalog check is skipped, and the UI
#                              test selection variables below are ignored (they only choose which tests run).
#
# UI test selection (only affects the "app UI tests" stage):
#   TAGWERK_UI_TEST_SET        "full" (default): all UI tests; "pr": skips the tests listed in
#                              app/TagwerkUITests/nightly-only.txt (one test class or Class/testMethod per line,
#                              empty lines and lines starting with # are ignored). CI uses "pr" for pull requests
#                              and "full" for the nightly and manual runs.
#   TAGWERK_UI_ONLY            space-separated test classes or Class/testMethod entries to run (-only-testing);
#                              implies TAGWERK_ONLY_UI_TESTS=1 and takes precedence over TAGWERK_UI_TEST_SET
#   TAGWERK_UI_TEST_RETRIES=1  retry each failed UI test once (-retry-tests-on-failure -test-iterations 2) and list the
#                              tests that only passed on the second attempt under "RETRIED UI TESTS". UI stage only;
#                              the package and app unit stages never retry.
#   TAGWERK_NIGHTLY_ONLY_FILE  alternative path of the nightly-only list (used by scripts/tests/test-all-ui-selection.zsh)

set -euo pipefail

export DEVELOPER_DIR="${TAGWERK_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SCRIPT_DIR="${0:A:h}"
CURRENT_STAGE="setup"

# Test target that contains the UI tests; -only-testing and -skip-testing entries are prefixed with it.
UI_TEST_TARGET="TagwerkUITests"

# Fills UI_SELECTION_ARGS with the xcodebuild arguments that select and retry UI tests from the environment
# (TAGWERK_UI_ONLY, TAGWERK_UI_TEST_SET, TAGWERK_UI_TEST_RETRIES). Prints a one-line summary on stdout.
# Without any of these variables the array stays empty, so the UI stage runs every UI test once.
build_ui_selection_args() {
  UI_SELECTION_ARGS=()
  local test_set="${TAGWERK_UI_TEST_SET:-full}"
  local nightly_file="${TAGWERK_NIGHTLY_ONLY_FILE:-$SCRIPT_DIR/TagwerkUITests/nightly-only.txt}"
  local identifier line entries=0 summary

  case "$test_set" in
    pr|full) ;;
    *) echo "Invalid TAGWERK_UI_TEST_SET \"$test_set\" (expected \"pr\" or \"full\")" >&2; return 1 ;;
  esac
  case "${TAGWERK_UI_TEST_RETRIES:-}" in
    ""|0|1) ;;
    *) echo "Invalid TAGWERK_UI_TEST_RETRIES \"$TAGWERK_UI_TEST_RETRIES\" (expected empty, 0 or 1)" >&2; return 1 ;;
  esac

  if [[ -n "${TAGWERK_UI_ONLY:-}" ]]; then
    for identifier in ${=TAGWERK_UI_ONLY}; do
      if [[ ! "$identifier" =~ '^[A-Za-z0-9_]+(/[A-Za-z0-9_]+)?$' ]]; then
        echo "Invalid TAGWERK_UI_ONLY entry \"$identifier\" (expected Class or Class/testMethod)" >&2
        return 1
      fi
      UI_SELECTION_ARGS+=("-only-testing:$UI_TEST_TARGET/$identifier")
      entries=$((entries + 1))
    done
    summary="only $entries selected entries (TAGWERK_UI_ONLY: ${=TAGWERK_UI_ONLY})"
  elif [[ "$test_set" == "pr" ]]; then
    if [[ ! -f "$nightly_file" ]]; then
      echo "TAGWERK_UI_TEST_SET=pr needs the nightly-only list, but $nightly_file does not exist" >&2
      return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
      identifier="${line//[[:space:]]/}"
      [[ -z "$identifier" || "$identifier" == \#* ]] && continue
      if [[ ! "$identifier" =~ '^[A-Za-z0-9_]+(/[A-Za-z0-9_]+)?$' ]]; then
        echo "Invalid entry \"$identifier\" in $nightly_file (expected Class or Class/testMethod)" >&2
        return 1
      fi
      UI_SELECTION_ARGS+=("-skip-testing:$UI_TEST_TARGET/$identifier")
      entries=$((entries + 1))
    done < "$nightly_file"
    summary="pr set, $entries nightly-only entries skipped (${nightly_file:t})"
  else
    summary="full set"
  fi

  if [[ "${TAGWERK_UI_TEST_RETRIES:-}" == "1" ]]; then
    UI_SELECTION_ARGS+=(-retry-tests-on-failure -test-iterations 2)
    summary="$summary, one retry per failed test"
  fi
  echo "    UI tests: $summary"
}

# Lists the UI tests that failed at least once and passed in the end, based on the stage log, under the heading
# "RETRIED UI TESTS". The list is also written to <log dir>/retried-ui-tests.md (the CI workflow copies it into the job
# summary). A test counts as retried when its last reported result is "passed" and an earlier attempt failed.
report_retried_ui_tests() {
  local log="$1" report="$2"
  local retried
  retried=$(/usr/bin/python3 -c '
import re, sys
results = {}
failed_once = set()
summary_failures = 0
pattern = re.compile(r"Test [Cc]ase \x27([^\x27]+)\x27 (passed|failed)")
failure_summary = re.compile(r"Executed \d+ tests?, with ([1-9]\d*) failures?")
with open(sys.argv[1], errors="replace") as handle:
    for line in handle:
        match = pattern.search(line)
        if match:
            raw, outcome = match.groups()
            if raw.startswith("-["):
                suite, _, method = raw[2:-1].partition(" ")
            else:
                suite, _, method = raw.rstrip("()").rpartition(".")
            name = suite.split(".")[-1] + "/" + method
            results[name] = outcome
            if outcome == "failed":
                failed_once.add(name)
        elif failure_summary.search(line):
            summary_failures += 1
for name in sorted(failed_once):
    if results.get(name) == "passed":
        print(name)
if not failed_once and summary_failures:
    print("UNPARSED")
' "$log") || retried=""

  {
    echo "RETRIED UI TESTS"
    if [[ -z "$retried" ]]; then
      echo "  none"
    elif [[ "$retried" == "UNPARSED" ]]; then
      echo "  The log reports failed attempts, but no test names could be read from it (log: $log)"
    else
      print -r -- "$retried" | sed 's/^/  - /'
    fi
  } | tee "$report"
}

# TAGWERK_UI_ONLY selects UI tests, so the other stages are skipped; combining it with the skip switch is a mistake.
if [[ -n "${TAGWERK_UI_ONLY:-}" ]]; then
  if [[ -n "${TAGWERK_SKIP_UI_TESTS:-}" ]]; then
    echo "TAGWERK_UI_ONLY and TAGWERK_SKIP_UI_TESTS exclude each other" >&2
    exit 1
  fi
  TAGWERK_ONLY_UI_TESTS=1
fi

# Sourced by scripts/tests/test-all-ui-selection.zsh: only the functions above are needed, not the test run.
if [[ -n "${TAGWERK_SOURCE_ONLY:-}" ]]; then return 0; fi

# Reports the failing stage and stops the script.
stage_failed() {
  if [[ -n "${TAGWERK_BUILD_ONLY:-}" ]]; then
    echo "BUILD FAILED in stage: $CURRENT_STAGE" >&2
  else
    echo "TESTS FAILED in stage: $CURRENT_STAGE" >&2
  fi
  exit 1
}

# Per-checkout simulator, derived data and logs, so several checkouts can test at the same time.
source "$SCRIPT_DIR/../scripts/test-env.sh"
# One run per checkout; a second run would share the simulator and the derived data folder.
tagwerk_acquire_run_lock || exit 2
trap tagwerk_release_run_lock EXIT
DESTINATION=$(tagwerk_test_destination) || stage_failed
LOG_DIR="$TAGWERK_TEST_LOG_DIR"
# The app stage builds here, so the String Catalog check can reuse its .stringsdata.
DERIVED="$TAGWERK_TEST_DERIVED"
mkdir -p "$LOG_DIR"
RESULTS_DIR="${TAGWERK_TEST_RESULTS_DIR:-}"
[[ -z "$RESULTS_DIR" ]] || mkdir -p "$RESULTS_DIR"
echo "==> setup: $DESTINATION, derived data $DERIVED"
if [[ -n "${TAGWERK_BUILD_ONLY:-}" ]]; then
  echo "    build only (TAGWERK_BUILD_ONLY): build-for-testing, no tests are run"
fi

# Runs xcodebuild test, keeps the full log and fails when no test was executed.
run_tests() {
  local log="$LOG_DIR/${CURRENT_STAGE// /-}.log"
  # The result bundle name is unique per stage because xcodebuild refuses to overwrite an existing bundle.
  local result_args=()
  if [[ -n "$RESULTS_DIR" ]]; then
    result_args=(-resultBundlePath "$RESULTS_DIR/${CURRENT_STAGE// /-}.xcresult")
  fi
  # German is the source language; tests expect German texts and formats (plan english-app, Task 1).
  if ! xcodebuild test -testLanguage de -testRegion DE "${result_args[@]}" "$@" > "$log" 2>&1; then
    grep -E "error:|✘|failed" "$log" | tail -n 30 >&2 || true
    echo "Full log: $log" >&2
    return 1
  fi
  # Swift Testing prints "Test run with N tests", XCTest prints "Executed N tests". A bundle can print both, one of
  # them with 0 (e.g. UI tests: XCTest only), so the run counts as empty only when no summary reports a test.
  local summary="" line count
  while IFS= read -r line; do
    count=$(print -r -- "$line" | sed -nE 's/.*Test run with ([0-9]+) tests?.*/\1/p; s/.*Executed ([0-9]+) tests?,.*/\1/p' | head -n 1)
    if [[ -n "$count" && "$count" -gt 0 ]]; then summary="$line"; fi
  done < <(grep -E "Test run with [0-9]+ tests?|Executed [0-9]+ tests?," "$log" | grep -v "Test Suite")
  if [[ -z "$summary" ]]; then
    echo "No tests were executed (log: $log)" >&2
    return 1
  fi
  summary="${summary##*] }"
  echo "    ${summary//$'\t'/}"
}

# Build-only counterpart of run_tests: xcodebuild build-for-testing with the same arguments, log file and result bundle
# naming. "xcodebuild test" is "build-for-testing" followed by "test-without-building", so the build products and the
# DerivedData state are the same; only the test execution (and the test language and region it needs) is left out.
build_for_testing() {
  local log="$LOG_DIR/${CURRENT_STAGE// /-}.log"
  local result_args=()
  if [[ -n "$RESULTS_DIR" ]]; then
    result_args=(-resultBundlePath "$RESULTS_DIR/${CURRENT_STAGE// /-}.xcresult")
  fi
  if ! xcodebuild build-for-testing "${result_args[@]}" "$@" > "$log" 2>&1; then
    grep -E "error:|✘|failed" "$log" | tail -n 30 >&2 || true
    echo "Full log: $log" >&2
    return 1
  fi
  echo "    build succeeded (log: $log)"
}

# Runs a stage: tests normally, only the build with TAGWERK_BUILD_ONLY=1. Takes the xcodebuild arguments of the stage.
run_stage() {
  if [[ -n "${TAGWERK_BUILD_ONLY:-}" ]]; then
    build_for_testing "$@"
  else
    run_tests "$@"
  fi
}

# Resolves the scheme to test: "<Pkg>" if the package exposes a single product, else "<Pkg>-Package".
resolve_package_scheme() {
  local package_name="$1"
  local schemes_json
  schemes_json=$(xcodebuild -list -json 2>/dev/null)
  print -r -- "$schemes_json" | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
try:
    schemes = json.load(sys.stdin)["workspace"]["schemes"]
except (ValueError, KeyError):
    schemes = [name]
print(name if name in schemes else name + "-Package")
' "$package_name"
}

for package_dir in "$SCRIPT_DIR"/Packages/*(/N); do
  [[ -z "${TAGWERK_ONLY_UI_TESTS:-}" ]] || break
  package_name="${package_dir:t}"
  CURRENT_STAGE="package $package_name"
  echo "==> $CURRENT_STAGE"
  if [[ ! -d "$package_dir/Tests" ]]; then
    echo "    no Tests directory, covered by the app test bundle"
    continue
  fi
  cd "$package_dir"
  scheme=$(resolve_package_scheme "$package_name") || stage_failed
  run_stage -scheme "$scheme" -destination "$DESTINATION" || stage_failed
done

CURRENT_STAGE="app (xcodegen)"
echo "==> $CURRENT_STAGE"
cd "$SCRIPT_DIR"
xcodegen --quiet || stage_failed

CURRENT_STAGE="app scheme Tagwerk"
echo "==> $CURRENT_STAGE"
if [[ -n "${TAGWERK_ONLY_UI_TESTS:-}" ]]; then
  echo "    skipped (TAGWERK_ONLY_UI_TESTS)"
else
  run_stage -project "$SCRIPT_DIR/Tagwerk.xcodeproj" -scheme Tagwerk -destination "$DESTINATION" -derivedDataPath "$DERIVED" || stage_failed
fi

CURRENT_STAGE="app UI tests"
echo "==> $CURRENT_STAGE"
if [[ -n "${TAGWERK_SKIP_UI_TESTS:-}" ]]; then
  echo "    skipped (TAGWERK_SKIP_UI_TESTS)"
elif [[ -n "${TAGWERK_BUILD_ONLY:-}" ]]; then
  # Same scheme, destination and derived data folder as the test run below, so it builds the app and the UI test runner
  # exactly as the test run would. No simulator boot, permissions or test selection: nothing is executed.
  build_for_testing -project "$SCRIPT_DIR/Tagwerk.xcodeproj" -scheme TagwerkUITests -destination "$DESTINATION" -derivedDataPath "$DERIVED" || stage_failed
else
  # The UI tests read the demo data from the Calendar and Reminders stores; the permissions are granted
  # beforehand, so no system dialog can interrupt a test. The simulator is booted for this (it keeps running).
  tagwerk_prepare_ui_simulator "$DESTINATION" "$SCRIPT_DIR/Tagwerk.xcodeproj" || stage_failed
  build_ui_selection_args || stage_failed
  ui_status=0
  run_tests -project "$SCRIPT_DIR/Tagwerk.xcodeproj" -scheme TagwerkUITests -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
    "${UI_SELECTION_ARGS[@]}" || ui_status=$?
  # The list is reported even when the stage fails: a test that wobbles twice in one run is worth knowing about.
  if [[ "${TAGWERK_UI_TEST_RETRIES:-}" == "1" ]]; then
    report_retried_ui_tests "$LOG_DIR/app-UI-tests.log" "$LOG_DIR/retried-ui-tests.md"
  fi
  (( ui_status == 0 )) || stage_failed
fi

CURRENT_STAGE="string catalogs"
echo "==> $CURRENT_STAGE"
if [[ -n "${TAGWERK_ONLY_UI_TESTS:-}" ]]; then
  echo "    skipped (TAGWERK_ONLY_UI_TESTS)"
elif [[ -n "${TAGWERK_BUILD_ONLY:-}" ]]; then
  echo "    skipped (TAGWERK_BUILD_ONLY)"
else
  /usr/bin/python3 "$SCRIPT_DIR/../scripts/check-strings.py" --require-english || stage_failed
  # Text colours: the named tones of Common/TextTones.swift instead of the system grey and system colours (strand K).
  /usr/bin/python3 "$SCRIPT_DIR/../scripts/check-colors.py" || stage_failed
  "$SCRIPT_DIR/../scripts/sync-strings.sh" --check --no-build --derived-data "$DERIVED" || stage_failed
  echo "    catalogs match the source code"
fi

CURRENT_STAGE="done"
if [[ -n "${TAGWERK_BUILD_ONLY:-}" ]]; then
  echo "ALL BUILDS SUCCEEDED (build only, no tests were run)"
else
  echo "ALL TESTS PASSED"
fi
