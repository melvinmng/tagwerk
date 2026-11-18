#!/bin/zsh
# Runs all test stages: every local Swift package under app/Packages, then the app scheme.
# Stops at the first failing stage and reports which one failed.

set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

SCRIPT_DIR="${0:A:h}"
DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro'
CURRENT_STAGE="setup"

# Reports the failing stage and stops the script.
stage_failed() {
  echo "TESTS FAILED in stage: $CURRENT_STAGE" >&2
  exit 1
}

LOG_DIR="${TMPDIR:-/tmp}/tagwerk-tests"
# The app stage builds here, so the String Catalog check can reuse its .stringsdata.
DERIVED="$HOME/Library/Developer/Tagwerk/DerivedData-tests"
mkdir -p "$LOG_DIR"

# Runs xcodebuild test, keeps the full log and fails when no test was executed.
run_tests() {
  local log="$LOG_DIR/${CURRENT_STAGE// /-}.log"
  # German is the source language; tests expect German texts and formats (plan english-app, Task 1).
  if ! xcodebuild test -testLanguage de -testRegion DE "$@" > "$log" 2>&1; then
    grep -E "error:|✘|failed" "$log" | tail -n 30 >&2 || true
    echo "Full log: $log" >&2
    return 1
  fi
  local summary
  summary=$(grep -E "Test run with [0-9]+ tests?" "$log" | tail -n 1 || true)
  if [[ -z "$summary" || "$summary" == *"with 0 tests"* ]]; then
    echo "No tests were executed (log: $log)" >&2
    return 1
  fi
  echo "    ${summary##*] }"
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

CURRENT_STAGE="string catalogs"
echo "==> $CURRENT_STAGE"
/usr/bin/python3 "$SCRIPT_DIR/../scripts/check-strings.py" --require-english || stage_failed
"$SCRIPT_DIR/../scripts/sync-strings.sh" --check --no-build --derived-data "$DERIVED" || stage_failed
echo "    catalogs match the source code"

CURRENT_STAGE="done"
echo "ALL TESTS PASSED"
