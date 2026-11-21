#!/bin/zsh
# Tests for TAGWERK_BUILD_ONLY in app/test-all.sh (run: zsh scripts/tests/test-all-build-only.zsh).
# xcodebuild, xcodegen and xcrun are replaced by stubs that only record their arguments, so no build, simulator or test
# runs. The checks cover which xcodebuild calls the build-only mode makes for the CI jobs "fast" and "ui".
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
  *) [[ -z "${STUB_XCODEBUILD_FAIL:-}" ]] || { print "error: stubbed failure"; exit 65; } ;;
esac
STUB
cat > "$STUB_BIN/xcodegen" <<'STUB'
#!/bin/zsh
print -r -- "xcodegen $*" >> "$STUB_XCODEBUILD_CALLS"
STUB
cat > "$STUB_BIN/xcrun" <<'STUB'
#!/bin/zsh
print -r -- "xcrun $*" >> "$STUB_XCODEBUILD_CALLS"
STUB
chmod +x "$STUB_BIN"/*

SIMULATOR_ID="00000000-0000-0000-0000-000000000000"
DERIVED_DIR="$WORK_DIR/derived"

# Runs app/test-all.sh with the stubs and the given environment assignments. Prints the recorded calls (xcodebuild
# -list, -showBuildSettings and xcodegen are dropped) with the repository path abbreviated, then "rc=<exit code>".
# The script output is written to $WORK_DIR/output.txt.
run_script() {
  local calls="$WORK_DIR/calls.txt" assignment
  : > "$calls"
  (
    unset TAGWERK_SKIP_UI_TESTS TAGWERK_ONLY_UI_TESTS TAGWERK_UI_ONLY TAGWERK_UI_TEST_SET TAGWERK_UI_TEST_RETRIES TAGWERK_BUILD_ONLY
    export PATH="$STUB_BIN:$PATH" STUB_XCODEBUILD_CALLS="$calls"
    export TAGWERK_TEST_SIMULATOR="$SIMULATOR_ID" TAGWERK_TEST_DERIVED_DATA="$DERIVED_DIR" TAGWERK_TEST_LOG_DIR="$WORK_DIR/logs"
    for assignment in "$@"; do export "$assignment"; done
    "$ROOT/app/test-all.sh" > "$WORK_DIR/output.txt" 2>&1
  )
  local rc=$?
  grep -vE '^(xcodegen|-list|-project .* -scheme [^ ]+ -showBuildSettings)' "$calls" | sed "s#$ROOT/app/##g" || true
  print "rc=$rc"
}

DESTINATION="platform=iOS Simulator,id=$SIMULATOR_ID"

# Job "fast": package stages and app scheme as build-for-testing, nothing else.
fast_calls=$(run_script TAGWERK_BUILD_ONLY=1 TAGWERK_SKIP_UI_TESTS=1)
check "fast: only build-for-testing calls" "0" "$(print -r -- "$fast_calls" | grep -vcE '^(build-for-testing |rc=)')"
check "fast: app scheme as the test run builds it" "1" \
  "$(print -r -- "$fast_calls" | grep -cxF "build-for-testing -project Tagwerk.xcodeproj -scheme Tagwerk -destination $DESTINATION -derivedDataPath $DERIVED_DIR")"
check "fast: package stages use the destination without derived data path" "0" \
  "$(print -r -- "$fast_calls" | grep -E '^build-for-testing -scheme ' | grep -vcxE "build-for-testing -scheme [A-Za-z0-9_-]+ -destination ${DESTINATION//\//\\/}")"
check "fast: one call per package with tests plus the app" \
  "$(( $(ls -d "$ROOT"/app/Packages/*/Tests 2>/dev/null | wc -l) + 1 ))" \
  "$(print -r -- "$fast_calls" | grep -c '^build-for-testing ')"
check "fast: no UI test runner build" "0" "$(print -r -- "$fast_calls" | grep -c 'TagwerkUITests')"
check "fast: no test language or test verb" "0" "$(print -r -- "$fast_calls" | grep -cE '(^| )test( |$)|-testLanguage')"
check "fast: succeeds" "rc=0" "$(print -r -- "$fast_calls" | tail -n 1)"
check "fast: reports a build-only success" "1" "$(grep -c '^ALL BUILDS SUCCEEDED (build only, no tests were run)$' "$WORK_DIR/output.txt")"
check "fast: string catalog check skipped" "1" "$(grep -c 'skipped (TAGWERK_BUILD_ONLY)' "$WORK_DIR/output.txt")"

# Job "ui": a single build of the UI test scheme; the test selection and retry variables change nothing.
expected_ui=$'build-for-testing -project Tagwerk.xcodeproj -scheme TagwerkUITests -destination '"$DESTINATION -derivedDataPath $DERIVED_DIR"$'\nrc=0'
check "ui: one build-for-testing call of the UI scheme" "$expected_ui" "$(run_script TAGWERK_BUILD_ONLY=1 TAGWERK_ONLY_UI_TESTS=1)"
check "ui: selection and retries are ignored" "$expected_ui" \
  "$(run_script TAGWERK_BUILD_ONLY=1 TAGWERK_ONLY_UI_TESTS=1 TAGWERK_UI_TEST_SET=pr TAGWERK_UI_TEST_RETRIES=1)"
check "ui: no simulator command" "0" "$(grep -c '^xcrun' "$WORK_DIR/calls.txt")"

# A failing build fails the script and names the build, not the tests.
failed=$(run_script TAGWERK_BUILD_ONLY=1 TAGWERK_ONLY_UI_TESTS=1 STUB_XCODEBUILD_FAIL=1)
check "failure: exit code" "rc=1" "$(print -r -- "$failed" | tail -n 1)"
check "failure: message" "1" "$(grep -c '^BUILD FAILED in stage: app UI tests$' "$WORK_DIR/output.txt")"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
