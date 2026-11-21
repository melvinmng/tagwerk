#!/bin/zsh
# Runs all test stages: every local Swift package under app/Packages, the app scheme and the UI tests.
# Stops at the first failing stage and reports which one failed.
# TAGWERK_SKIP_UI_TESTS=1 skips the UI test stage (quick iterations only; the full run is required before a merge).

set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

SCRIPT_DIR="${0:A:h}"
CURRENT_STAGE="setup"

# Reports the failing stage and stops the script.
stage_failed() {
  echo "TESTS FAILED in stage: $CURRENT_STAGE" >&2
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
echo "==> setup: $DESTINATION, derived data $DERIVED"

# Runs xcodebuild test, keeps the full log and fails when no test was executed.
run_tests() {
  local log="$LOG_DIR/${CURRENT_STAGE// /-}.log"
  # German is the source language; tests expect German texts and formats (plan english-app, Task 1).
  if ! xcodebuild test -testLanguage de -testRegion DE "$@" > "$log" 2>&1; then
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
  package_name="${package_dir:t}"
  CURRENT_STAGE="package $package_name"
  echo "==> $CURRENT_STAGE"
  if [[ ! -d "$package_dir/Tests" ]]; then
    echo "    no Tests directory, covered by the app test bundle"
    continue
  fi
  cd "$package_dir"
  scheme=$(resolve_package_scheme "$package_name") || stage_failed
  run_tests -scheme "$scheme" -destination "$DESTINATION" || stage_failed
done

CURRENT_STAGE="app (xcodegen)"
echo "==> $CURRENT_STAGE"
cd "$SCRIPT_DIR"
xcodegen --quiet || stage_failed

CURRENT_STAGE="app scheme Tagwerk"
echo "==> $CURRENT_STAGE"
run_tests -project "$SCRIPT_DIR/Tagwerk.xcodeproj" -scheme Tagwerk -destination "$DESTINATION" -derivedDataPath "$DERIVED" || stage_failed

CURRENT_STAGE="app UI tests"
echo "==> $CURRENT_STAGE"
if [[ -n "${TAGWERK_SKIP_UI_TESTS:-}" ]]; then
  echo "    skipped (TAGWERK_SKIP_UI_TESTS)"
else
  # The UI tests read the demo data from the Calendar and Reminders stores; the permissions are granted
  # beforehand, so no system dialog can interrupt a test. The simulator is booted for this (it keeps running).
  tagwerk_prepare_ui_simulator "$DESTINATION" "$SCRIPT_DIR/Tagwerk.xcodeproj" || stage_failed
  run_tests -project "$SCRIPT_DIR/Tagwerk.xcodeproj" -scheme TagwerkUITests -destination "$DESTINATION" -derivedDataPath "$DERIVED" || stage_failed
fi

CURRENT_STAGE="string catalogs"
echo "==> $CURRENT_STAGE"
/usr/bin/python3 "$SCRIPT_DIR/../scripts/check-strings.py" --require-english || stage_failed
# Text colours: the named tones of Common/TextTones.swift instead of the system grey and system colours (strand K).
/usr/bin/python3 "$SCRIPT_DIR/../scripts/check-colors.py" || stage_failed
"$SCRIPT_DIR/../scripts/sync-strings.sh" --check --no-build --derived-data "$DERIVED" || stage_failed
echo "    catalogs match the source code"

CURRENT_STAGE="done"
echo "ALL TESTS PASSED"
