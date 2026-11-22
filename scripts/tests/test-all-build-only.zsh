#!/bin/zsh
# Tests for TAGWERK_BUILD_ONLY in app/test-all.sh (run: zsh scripts/tests/test-all-build-only.zsh).
# xcodebuild, xcodegen and xcrun are replaced by stubs that only record their arguments, so no build, simulator or test
# runs. The checks cover which xcodebuild calls the build-only mode makes for the CI jobs "fast" and "ui", and that a
# normal test run builds the app and UI schemes with exactly the same build-for-testing calls.
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
  test*) [[ -z "${STUB_XCODEBUILD_FAIL:-}" ]] || { print "error: stubbed failure"; exit 65; }; print "✔ Test run with 1 test in 1 suite passed after 0.001 seconds." ;;
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
    export TAGWERK_LOCK_DIR="$WORK_DIR/locks"
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
# Package stages: a package that declares a macOS platform is built for the Mac, a package whose tests run in the app scheme
# (app/project.yml) has no stage of its own, every other package is built for the simulator. None passes a derived data
# path (the packages build in the default DerivedData folder).
package_stages=0
for package_dir in "$ROOT"/app/Packages/*(/N); do
  [[ -d "$package_dir/Tests" ]] || continue
  package_name="${package_dir:t}"
  if grep -qE "package: *$package_name/${package_name}Tests" "$ROOT/app/project.yml"; then
    check "fast: $package_name has no package stage (its tests run in the app scheme)" "0" \
      "$(print -r -- "$fast_calls" | grep -c -- "-scheme $package_name-Package")"
    continue
  fi
  if grep -q '\.macOS(' "$package_dir/Package.swift"; then
    expected_destination="platform=macOS"
  else
    expected_destination="$DESTINATION"
  fi
  package_stages=$((package_stages + 1))
  check "fast: $package_name is built for ${expected_destination%%,*}, without derived data path" "1" \
    "$(print -r -- "$fast_calls" | grep -cxF "build-for-testing -scheme $package_name-Package -destination $expected_destination")"
done
check "fast: one call per package stage plus the app" "$(( package_stages + 1 ))" "$(print -r -- "$fast_calls" | grep -c '^build-for-testing ')"
check "app scheme Tagwerk runs the tests of AIKit (project.yml)" "1" "$(grep -cE 'package: *AIKit/AIKitTests' "$ROOT/app/project.yml")"
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

# A test run builds the app and UI schemes with the very same build-for-testing calls as the build-only mode (that is what
# the CI cache jobs rely on) and then tests without building; the tests never repeat the build.
normal_fast=$(run_script TAGWERK_SKIP_UI_TESTS=1)
normal_ui=$(run_script TAGWERK_ONLY_UI_TESTS=1)
check "fast: the app build of a test run equals the build-only call" "$(print -r -- "$fast_calls" | grep -E '^build-for-testing -project ')" \
  "$(print -r -- "$normal_fast" | grep -E '^build-for-testing -project ')"
check "fast: the app tests run without building, with the test language" "1" \
  "$(print -r -- "$normal_fast" | grep -cxF "test-without-building -testLanguage de -testRegion DE -project Tagwerk.xcodeproj -scheme Tagwerk -destination $DESTINATION -derivedDataPath $DERIVED_DIR")"
check "fast: no stage after the build repeats it" "0" "$(print -r -- "$normal_fast" | grep -c '^test .*-scheme Tagwerk ')"
check "ui: the UI build of a test run equals the build-only call" "$expected_ui" \
  "$(print -r -- "$normal_ui" | grep -E '^build-for-testing ')"$'\nrc=0'
check "ui: the UI tests run without building" "1" \
  "$(print -r -- "$normal_ui" | grep -cE "^test-without-building -testLanguage de -testRegion DE -project Tagwerk.xcodeproj -scheme TagwerkUITests ")"
check "ui: the build comes before the simulator is touched, the tests come last" "build-for-testing xcrun test-without-building" \
  "$(print -r -- "$normal_ui" | grep -oE '^(build-for-testing|xcrun|test-without-building)' | uniq | tr '\n' ' ' | sed 's/ $//')"

# A failing build fails the script and names the build, not the tests.
failed=$(run_script TAGWERK_BUILD_ONLY=1 TAGWERK_ONLY_UI_TESTS=1 STUB_XCODEBUILD_FAIL=1)
check "failure: exit code" "rc=1" "$(print -r -- "$failed" | tail -n 1)"
check "failure: message" "1" "$(grep -c '^BUILD FAILED in stage: app UI tests$' "$WORK_DIR/output.txt")"
# The same in a test run: a failing build is reported as a build failure, a failing test run as a test failure.
failed=$(run_script TAGWERK_ONLY_UI_TESTS=1 STUB_XCODEBUILD_FAIL=1)
check "failure in a test run: the build fails first" "1" "$(grep -c '^BUILD FAILED in stage: app UI tests$' "$WORK_DIR/output.txt")"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
