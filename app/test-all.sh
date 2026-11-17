#!/bin/zsh
# Runs all test stages: every local Swift package under app/Packages, then the app scheme.
# Stops at the first failing stage and reports which one failed.

set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

SCRIPT_DIR="${0:A:h}"
DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro'
CURRENT_STAGE="setup"

on_exit() {
  local exit_code=$?
  if (( exit_code != 0 )); then
    echo "TESTS FAILED in stage: $CURRENT_STAGE" >&2
  fi
}
trap on_exit EXIT

# Resolves the scheme to test: "<Pkg>" if the package exposes a single product, else "<Pkg>-Package".
resolve_package_scheme() {
  local package_name="$1"
  local schemes_json
  schemes_json=$(xcodebuild -list -json 2>/dev/null)
  print -r -- "$schemes_json" | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
schemes = json.load(sys.stdin)["workspace"]["schemes"]
print(name if name in schemes else name + "-Package")
' "$package_name"
}

for package_dir in "$SCRIPT_DIR"/Packages/*(/N); do
  package_name="${package_dir:t}"
  CURRENT_STAGE="package $package_name"
  echo "==> $CURRENT_STAGE"
  cd "$package_dir"
  scheme=$(resolve_package_scheme "$package_name")
  xcodebuild test -scheme "$scheme" -destination "$DESTINATION" -quiet
done

CURRENT_STAGE="app (xcodegen)"
echo "==> $CURRENT_STAGE"
cd "$SCRIPT_DIR"
xcodegen --quiet

CURRENT_STAGE="app scheme Tagwerk"
echo "==> $CURRENT_STAGE"
xcodebuild test -project "$SCRIPT_DIR/Tagwerk.xcodeproj" -scheme Tagwerk -destination "$DESTINATION" -quiet

CURRENT_STAGE="done"
echo "ALL TESTS PASSED"
