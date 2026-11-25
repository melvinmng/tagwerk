#!/bin/zsh
# Runs all test stages: every local Swift package under app/Packages, the app scheme and the UI tests.
# Stops at the first failing stage and reports which one failed.
#
# Package tests run on the Mac (destination platform=macOS) where the package builds for macOS without conditional code,
# and in the iOS simulator otherwise; PACKAGE_TEST_PLATFORM below lists the choice per package. The app stage builds all
# packages for iOS in any case, so they stay compilable for the phone.
#
# The app and UI stages build once with "xcodebuild build-for-testing" and run the tests with "xcodebuild
# test-without-building" (the same arguments, the same DerivedData folder). The UI build runs before the UI stage lock is
# taken, so the lock only covers the test run. TAGWERK_BUILD_ONLY runs exactly the build half of every stage.
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
#   TAGWERK_TEST_RESULTS_DIR   folder for the .xcresult bundles: one per stage for the tests (<stage>.xcresult) and one for
#                              the build of a stage that builds separately (<stage>-build.xcresult)
#   TAGWERK_TEST_SIMULATOR     simulator name or UDID instead of a slot of the simulator pool (see scripts/test-env.sh)
#   TAGWERK_KEEP_SIMULATOR=1   leave the pool simulator booted at the end of the run (it is shut down otherwise)
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
#   TAGWERK_UI_TEST_RETRIES    "1" (default when unset, locally and on GitHub for pull requests): the tests that failed in the
#                              UI stage run once more, alone, in a second xcodebuild call (-only-testing, own log
#                              app-UI-tests-retry.log and result bundle); the stage is green when all of them pass the second time
#                              and red when one fails twice. At most 5 failed tests are retried: more is not a flake. The tests
#                              that only passed on the second attempt are listed under "RETRIED UI TESTS". "0" or empty: no
#                              retry (nightly and manual runs, so wobbling tests stay visible). UI stage only; the package and
#                              app unit stages never retry. The retry is a call of its own because xcodebuild's
#                              -retry-tests-on-failure did not repeat tests that failed an assertion (the runner process ends after the
#                              failure of a test with continueAfterFailure = false).
#   TAGWERK_NIGHTLY_ONLY_FILE  alternative path of the nightly-only list (used by scripts/tests/test-all-ui-selection.zsh)
#   TAGWERK_UI_SHARD           "I/N" (for example 1/2): run only shard I of N of the UI test classes. The classes are read from the
#                              sources of the UI test target and distributed by their measured durations
#                              (scripts/ui-test-shards.py, app/TagwerkUITests/ui-test-durations.txt); the shards of one run
#                              together are the selection of TAGWERK_UI_TEST_SET. Excludes TAGWERK_UI_ONLY. CI runs one job per shard.
#
# Watchdog (every xcodebuild call runs under scripts/ui-watchdog.py): the log of the call is followed, the test progress
# (Test Case started/passed/failed) and a heartbeat go to stdout, and a call that stays silent or runs too long is stopped after
# diagnostics were written into the log folder (watchdog-<phase>-<time>/: ps, simctl, samples, simulator log). 0 switches a limit off.
#   TAGWERK_UI_SILENCE_SECONDS     seconds without a new log line before the UI test run is stopped (default 600)
#   TAGWERK_UI_MAX_SECONDS         run time limit of one UI test call, in seconds (default 0 = off: a full local run under load
#                                  takes well over an hour; CI sets 3600)
#   TAGWERK_STAGE_SILENCE_SECONDS  the same silence limit for builds and the other test calls (default 900)
#   TAGWERK_STAGE_MAX_SECONDS      run time limit of one build or other test call (default 0 = off; CI sets 1800 to 2700)
#   TAGWERK_HEARTBEAT_SECONDS      interval of the heartbeat line (default 300)
#   TAGWERK_BOOT_TIMEOUT_SECONDS   limit for the boot of the simulator before the UI tests (default 600, see scripts/test-env.sh)

set -euo pipefail

export DEVELOPER_DIR="${TAGWERK_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

SCRIPT_DIR="${0:A:h}"
CURRENT_STAGE="setup"

# Test target that contains the UI tests; -only-testing and -skip-testing entries are prefixed with it.
UI_TEST_TARGET="TagwerkUITests"

# Where the tests of each package run:
#   macos        xcodebuild test with the destination platform=macOS, no simulator needed; the package must declare
#                .macOS(...) in its Package.swift and build without conditional code for it
#   app-scheme   the package test target is part of the scheme Tagwerk (app/project.yml, "package: <Name>/<Name>Tests") and
#                runs in the simulator together with the app tests: one build graph and one DerivedData folder
#   simulator    xcodebuild test in the iOS simulator of the run (default for packages that are not listed)
#   AIKit needs the simulator: Sources/AIKit/ChatGPTLogin.swift imports UIKit (ASWebAuthenticationSession presentation).
typeset -A PACKAGE_TEST_PLATFORM
PACKAGE_TEST_PLATFORM=(
  TagwerkCore macos
  GitHubKit macos
  RemindersKit macos
  HealthBridge macos
  AIKit app-scheme
)
MACOS_DESTINATION="platform=macOS"

# Xcode embeds a copy of every SwiftPM resource bundle (<Package>_<Target>.bundle) in the test bundles and apps that use it,
# and Bundle.module looks at that copy first. With a DerivedData folder restored from the CI build cache, the copy step is
# not repeated when a resource file was added to the package after the cached build, so a test run reads the stale copy
# and does not find the new file (the Bible verse table was reported missing this way). Deleting the embedded copies before
# the build forces Xcode to copy the current bundle again; the cost is one small copy per bundle.
#
# App extensions embedded in the app (Tagwerk.app/PlugIns/*.appex) are different: Xcode copies the extension as one unit, and
# the incremental build does not notice that a bundle inside the copy is gone, so deleting only the bundle leaves the
# extension without it (TagwerkWidget then crashed at NSBundle.module in IntakeFormat.liters). The embedded extension is
# therefore deleted as a whole, which makes Xcode embed it again with all of its resource bundles.
#
# The state before the deletion is recorded in EMBEDDED_BUNDLES_BEFORE (paths relative to the products folder), and
# verify_embedded_resource_bundles checks after the build that every recorded bundle is back, so a missing bundle fails the
# stage with a clear message instead of crashing a test host later. Only apps and extensions are recorded: the UI scheme does
# not build the unit test bundles, so their copies stay absent until the next run of the app scheme, which is no error.
typeset -a EMBEDDED_BUNDLES_BEFORE
EMBEDDED_BUNDLES_BEFORE=()

# Usage: remove_embedded_resource_bundles PRODUCTS_FOLDER
remove_embedded_resource_bundles() {
  local products_folder="$1"
  EMBEDDED_BUNDLES_BEFORE=()
  [[ -d "$products_folder" ]] || return 0
  local bundle
  while IFS= read -r bundle; do
    [[ -n "$bundle" ]] && EMBEDDED_BUNDLES_BEFORE+=("${bundle#$products_folder/}")
  done < <(find "$products_folder" -mindepth 2 -type d -name "*_*.bundle" ! -path "*.xctest/*" \
    \( -path "*.app/*" -o -path "*.appex/*" \) -prune 2> /dev/null | sort)
  # Embedded extensions first, as a whole; their bundles are gone with them.
  find "$products_folder" -mindepth 3 -type d -name "*.appex" -path "*.app/PlugIns/*" -prune \
    -exec rm -rf {} + 2> /dev/null || true
  find "$products_folder" -mindepth 2 -type d -name "*_*.bundle" \
    \( -path "*.xctest/*" -o -path "*.app/*" -o -path "*.appex/*" \) -prune \
    -exec rm -rf {} + 2> /dev/null || true
}

# Fails when a resource bundle that was embedded before remove_embedded_resource_bundles is missing after the build.
# Usage: verify_embedded_resource_bundles PRODUCTS_FOLDER
verify_embedded_resource_bundles() {
  local products_folder="$1" relative_path missing=()
  for relative_path in "${EMBEDDED_BUNDLES_BEFORE[@]}"; do
    [[ -d "$products_folder/$relative_path" ]] || missing+=("$relative_path")
  done
  (( ${#missing} == 0 )) && return 0
  echo "Resource bundles are missing after the build (they were embedded before it):" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "A target without its resource bundle crashes at Bundle.module. Delete $products_folder and run again." >&2
  return 1
}

# Prints the DerivedData folder Xcode uses for the package or project at the given path (xcodebuild without
# -derivedDataPath keeps one folder per path, named <Name>-<hash>, and records the path in its info.plist); nothing when
# there is none yet.
# Usage: default_derived_data_folder WORKSPACE_PATH
default_derived_data_folder() {
  local workspace_path="$1" info_plist recorded_path
  for info_plist in "$HOME"/Library/Developer/Xcode/DerivedData/*/info.plist(N); do
    recorded_path=$(/usr/bin/plutil -extract WorkspacePath raw -o - "$info_plist" 2> /dev/null) || continue
    if [[ "$recorded_path" == "$workspace_path" ]]; then
      print -r -- "${info_plist:h}"
      return 0
    fi
  done
}

# More failed UI tests than this are not retried: that is a broken change or a broken runner, not a flake.
MAX_RETRIED_UI_TESTS=5

# True when failed UI tests run once more: TAGWERK_UI_TEST_RETRIES is 1 or not set (see the header).
ui_retries_enabled() {
  [[ "${TAGWERK_UI_TEST_RETRIES-1}" == "1" ]]
}

# Fills UI_SELECTION_ARGS with the xcodebuild arguments that select UI tests from the environment (TAGWERK_UI_ONLY,
# TAGWERK_UI_TEST_SET) and checks TAGWERK_UI_TEST_RETRIES. Prints a one-line summary on stdout.
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
  case "${TAGWERK_UI_TEST_RETRIES-1}" in
    ""|0|1) ;;
    *) echo "Invalid TAGWERK_UI_TEST_RETRIES \"$TAGWERK_UI_TEST_RETRIES\" (expected empty, 0 or 1)" >&2; return 1 ;;
  esac

  if [[ -n "${TAGWERK_UI_SHARD:-}" ]]; then
    if [[ -n "${TAGWERK_UI_ONLY:-}" ]]; then
      echo "TAGWERK_UI_SHARD and TAGWERK_UI_ONLY exclude each other" >&2
      return 1
    fi
    # Shards 1 to N-1 select their classes; the last shard skips the classes of all the others instead, so a class that the
    # source scan of scripts/ui-test-shards.py does not see still runs (in the last shard) and is never left out of every shard.
    local shard_classes shard_class shard_mode="shard" shard_flag="-only-testing"
    local shard_index="${TAGWERK_UI_SHARD%%/*}" shard_total="${TAGWERK_UI_SHARD##*/}"
    if [[ "$shard_index" == "$shard_total" && "$shard_total" =~ '^[0-9]+$' && "$shard_total" -gt 1 ]]; then
      shard_mode="others"
      shard_flag="-skip-testing"
    fi
    shard_classes=$(/usr/bin/python3 -I "$SCRIPT_DIR/../scripts/ui-test-shards.py" "$shard_mode" "$TAGWERK_UI_SHARD" \
      --tests-dir "$SCRIPT_DIR/TagwerkUITests" --nightly-only-file "$nightly_file" --set "$test_set") || return 1
    for shard_class in ${(f)shard_classes}; do
      UI_SELECTION_ARGS+=("$shard_flag:$UI_TEST_TARGET/$shard_class")
      entries=$((entries + 1))
    done
    # The nightly-only entries of the pull request set still apply inside the classes of the shard.
    if [[ "$test_set" == "pr" && -f "$nightly_file" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        identifier="${line//[[:space:]]/}"
        [[ -z "$identifier" || "$identifier" == \#* ]] && continue
        UI_SELECTION_ARGS+=("-skip-testing:$UI_TEST_TARGET/$identifier")
      done < "$nightly_file"
    fi
    summary="shard $TAGWERK_UI_SHARD of the $test_set set ($shard_flag for $entries test classes)"
  elif [[ -n "${TAGWERK_UI_ONLY:-}" ]]; then
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

  if ui_retries_enabled; then
    summary="$summary, one retry per failed test (up to $MAX_RETRIED_UI_TESTS tests)"
  fi
  echo "    UI tests: $summary"
}

# Lists the UI tests that failed in an attempt and passed in the last one, based on the logs of the attempts (first
# attempt first), under the heading "RETRIED UI TESTS". The list is also written to <report> (the CI workflow copies it
# into the job summary). Usage: report_retried_ui_tests REPORT LOG...
report_retried_ui_tests() {
  local report="$1"; shift
  local retried
  retried=$(/usr/bin/python3 -I "$SCRIPT_DIR/../scripts/ui-test-log.py" retried "$@") || retried=""

  {
    echo "RETRIED UI TESTS"
    if [[ -z "$retried" ]]; then
      echo "  none"
    elif [[ "$retried" == "UNPARSED" ]]; then
      echo "  The log reports failed attempts, but no test names could be read from it (log: $*)"
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

# Sourced by scripts/tests/test-all-ui-selection.zsh and test-all-resource-bundles.zsh: only the functions above are needed, not the test run.
if [[ -n "${TAGWERK_SOURCE_ONLY:-}" ]]; then return 0; fi

# Phase of the last failed xcodebuild call ("build" or "test"), set by build_for_testing and run_tests.
FAILED_PHASE=""

# Reports the failing stage and stops the script.
stage_failed() {
  if [[ "$FAILED_PHASE" == "hang" ]]; then
    echo "HUNG in stage: $CURRENT_STAGE (stopped by the watchdog, diagnostics in $LOG_DIR/watchdog-*)" >&2
  elif [[ -n "${TAGWERK_BUILD_ONLY:-}" || "$FAILED_PHASE" == "build" ]]; then
    echo "BUILD FAILED in stage: $CURRENT_STAGE" >&2
  else
    echo "TESTS FAILED in stage: $CURRENT_STAGE" >&2
  fi
  exit 1
}

# Per-checkout derived data and logs, simulator from the machine-wide pool, so several checkouts can test at the same time.
source "$SCRIPT_DIR/../scripts/test-env.sh"
# One run per checkout; a second run would share the derived data folder.
tagwerk_acquire_run_lock || exit 2
# At the end of the run (also after Ctrl-C or a termination signal) the UI stage lock, the pool slot and the run lock are
# released and the pool simulator is shut down, unless TAGWERK_KEEP_SIMULATOR=1.
trap tagwerk_cleanup_run EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
# Takes a free pool slot (waits up to 30 minutes, then exits with code 2); TAGWERK_TEST_SIMULATOR bypasses the pool.
DESTINATION=$(tagwerk_test_destination) || exit 2
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

# Runs "xcodebuild VERB ARGS..." under scripts/ui-watchdog.py (see "Watchdog" in the header): the output goes to LOG (appended or
# truncated first), the progress goes to stdout, and the call is stopped with status 124 when it stays silent or runs too long.
# The limits are the UI ones for the test run of the UI stage and the stage ones for everything else.
# Usage: run_xcodebuild_watched PHASE LOG append|truncate VERB ARGS...
run_xcodebuild_watched() {
  local phase="$1" log="$2" mode="$3" verb="$4"; shift 4
  local silence="${TAGWERK_STAGE_SILENCE_SECONDS:-900}" max_seconds="${TAGWERK_STAGE_MAX_SECONDS:-0}"
  local options=(--heartbeat "${TAGWERK_HEARTBEAT_SECONDS:-300}") simulator_id=""
  if [[ "$verb" == "test-without-building" && "$CURRENT_STAGE" == "app UI tests" ]]; then
    silence="${TAGWERK_UI_SILENCE_SECONDS:-600}"
    max_seconds="${TAGWERK_UI_MAX_SECONDS:-0}"
  fi
  [[ "$mode" == "append" ]] && options+=(--append)
  # Only the stages that use the simulator get its diagnostics; a simulator chosen with TAGWERK_TEST_SIMULATOR is never shut down.
  if [[ "$CURRENT_STAGE" == app* && "$DESTINATION" == *id=* ]]; then
    simulator_id="${${DESTINATION#*id=}%%,*}"
    [[ -n "${TAGWERK_TEST_SIMULATOR:-}" ]] || options+=(--shutdown-simulator)
  fi
  local watched_status=0
  /usr/bin/python3 -I "$SCRIPT_DIR/../scripts/ui-watchdog.py" --phase "$phase" --log "$log" --diag-dir "$LOG_DIR" \
    --silence "$silence" --max-seconds "$max_seconds" --simulator-id "$simulator_id" "${options[@]}" \
    -- xcodebuild "$verb" "$@" || watched_status=$?
  if (( watched_status == 124 )); then
    echo "STOPPED BY THE WATCHDOG in phase \"$phase\": see the diagnostics folder watchdog-* in $LOG_DIR" >&2
  fi
  return $watched_status
}

# Runs xcodebuild <verb> for the tests of a stage, keeps the full log and fails when no test was executed. The verb is
# "test" (build and test in one call, used for the package stages) or "test-without-building" (the test half after
# build_for_testing, which started the log of the stage; this output is appended to it). The log and the result bundle are named
# after the stage, or after RUN_TESTS_LABEL when it is set (the retry of the UI stage has files of its own and starts a new log).
# Usage: run_tests VERB ARGS...
run_tests() {
  local verb="$1"; shift
  local label="${RUN_TESTS_LABEL:-${CURRENT_STAGE// /-}}"
  local log="$LOG_DIR/$label.log"
  # The result bundle name is unique per stage because xcodebuild refuses to overwrite an existing bundle.
  local result_args=()
  if [[ -n "$RESULTS_DIR" ]]; then
    result_args=(-resultBundlePath "$RESULTS_DIR/$label.xcresult")
  fi
  [[ "$verb" == "test-without-building" && -z "${RUN_TESTS_LABEL:-}" ]] || : > "$log"
  local started=$SECONDS watchdog_status=0
  # German is the source language; tests expect German texts and formats (plan english-app, Task 1).
  echo "    $CURRENT_STAGE: xcodebuild $verb started (log: $log)"
  run_xcodebuild_watched "$CURRENT_STAGE: $label $verb" "$log" append "$verb" -testLanguage de -testRegion DE "${result_args[@]}" "$@" || watchdog_status=$?
  if (( watchdog_status != 0 )); then
    FAILED_PHASE="test"
    (( watchdog_status != 124 )) || FAILED_PHASE="hang"
    grep -E "error:|✘|failed" "$log" | tail -n 30 >&2 || true
    echo "Full log: $log" >&2
    return 1
  fi
  local elapsed=$((SECONDS - started))
  # Swift Testing prints "Test run with N tests", XCTest prints "Executed N tests". A bundle can print both, one of
  # them with 0 (e.g. UI tests: XCTest only), so the run counts as empty only when no summary reports a test. A scheme
  # with several test bundles prints one summary per bundle: all of them are listed, followed by the total.
  local line count summaries=() total=0
  while IFS= read -r line; do
    count=$(print -r -- "$line" | sed -nE 's/.*Test run with ([0-9]+) tests?.*/\1/p; s/.*Executed ([0-9]+) tests?,.*/\1/p' | head -n 1)
    if [[ -n "$count" && "$count" -gt 0 ]]; then
      line="${line##*] }"
      summaries+=("${line//$'\t'/}")
      total=$((total + count))
    fi
  done < <(grep -E "Test run with [0-9]+ tests?|Executed [0-9]+ tests?," "$log" | grep -v "Test Suite")
  if (( ${#summaries} == 0 )); then
    FAILED_PHASE="test"
    echo "No tests were executed (log: $log)" >&2
    return 1
  fi
  for line in "${summaries[@]}"; do echo "    $line"; done
  if (( ${#summaries} > 1 )); then echo "    $total tests in ${#summaries} test bundles in total"; fi
  echo "    test run took $elapsed s"
}

# Runs xcodebuild build-for-testing and keeps the full log of the stage (it starts the log; run_tests appends the test
# output to it). Both the test runs and TAGWERK_BUILD_ONLY (the CI jobs that refresh the build cache) use this one
# function with the same arguments, so the build products and the DerivedData state are the ones a test run needs.
# Usage: build_for_testing ARGS...
build_for_testing() {
  local log="$LOG_DIR/${CURRENT_STAGE// /-}.log"
  local result_args=()
  if [[ -n "$RESULTS_DIR" ]]; then
    result_args=(-resultBundlePath "$RESULTS_DIR/${CURRENT_STAGE// /-}-build.xcresult")
  fi
  local started=$SECONDS watchdog_status=0
  echo "    $CURRENT_STAGE: xcodebuild build-for-testing started (log: $log)"
  run_xcodebuild_watched "$CURRENT_STAGE: build" "$log" truncate build-for-testing "${result_args[@]}" "$@" || watchdog_status=$?
  if (( watchdog_status != 0 )); then
    FAILED_PHASE="build"
    (( watchdog_status != 124 )) || FAILED_PHASE="hang"
    grep -E "error:|✘|failed" "$log" | tail -n 30 >&2 || true
    echo "Full log: $log" >&2
    return 1
  fi
  echo "    build succeeded in $((SECONDS - started)) s (log: $log)"
}

# Takes a stack sample of the app process when a UI test shows that the app does not answer (scripts/ui-hang-sampler.py reads
# the log of the run in the background and writes hang-*.txt into the log folder, which CI uploads). It only watches: it changes no
# test result, and a hang-free run costs one idle process that reads the log once per second.
# Usage: start_ui_hang_sampler LOG, then stop_ui_hang_sampler
start_ui_hang_sampler() {
  local log="$1" simulator_id=""
  [[ "$DESTINATION" == *id=* ]] && simulator_id="${${DESTINATION#*id=}%%,*}"
  UI_HANG_STOP_FILE="$LOG_DIR/.ui-hang-sampler-stop"
  rm -f "$UI_HANG_STOP_FILE"
  /usr/bin/python3 -I "$SCRIPT_DIR/../scripts/ui-hang-sampler.py" "$log" "$LOG_DIR" "$UI_HANG_STOP_FILE" \
    --simulator-id "$simulator_id" >> "$LOG_DIR/ui-hang-sampler.log" 2>&1 &
  UI_HANG_SAMPLER_PID=$!
}

stop_ui_hang_sampler() {
  [[ -n "${UI_HANG_SAMPLER_PID:-}" ]] || return 0
  : > "$UI_HANG_STOP_FILE"
  # The sampler ends after its current sample (3 seconds at most) once it sees the stop file.
  wait "$UI_HANG_SAMPLER_PID" 2> /dev/null || true
  UI_HANG_SAMPLER_PID=""
}

# Runs the UI tests of the stage and, when some fail, those tests once more alone (see TAGWERK_UI_TEST_RETRIES in the header).
# Returns the status of the last attempt: 0 when every test passed, in the first or in the second attempt.
# The retry is a second xcodebuild call, not -retry-tests-on-failure: a failed assertion ends the runner process, and
# xcodebuild then did not repeat the test (the retry list stayed empty in every pull request run of 2026-11-23).
# Usage: run_ui_tests XCODEBUILD_ARGS...
run_ui_tests() {
  local first_log="$LOG_DIR/${CURRENT_STAGE// /-}.log"
  local retry_label="${CURRENT_STAGE// /-}-retry"
  local retry_log="$LOG_DIR/$retry_label.log"
  local attempt_status=0

  rm -f "$retry_log"
  start_ui_hang_sampler "$first_log"
  run_tests test-without-building "$@" "${UI_SELECTION_ARGS[@]}" || attempt_status=$?
  stop_ui_hang_sampler
  if (( attempt_status == 0 )) || ! ui_retries_enabled; then return $attempt_status; fi
  # A run stopped by the watchdog is a hang, not a flaky test: it is reported as it is, without a second attempt.
  if [[ "$FAILED_PHASE" == "hang" ]]; then return $attempt_status; fi

  local failed_tests=() failed_test retry_args=()
  failed_tests=(${(f)"$(/usr/bin/python3 -I "$SCRIPT_DIR/../scripts/ui-test-log.py" failed "$first_log")"})
  if (( ${#failed_tests} == 0 )); then
    echo "    no failed test could be read from the log, so nothing is retried (log: $first_log)" >&2
    return $attempt_status
  fi
  if (( ${#failed_tests} > MAX_RETRIED_UI_TESTS )); then
    echo "    ${#failed_tests} UI tests failed (more than $MAX_RETRIED_UI_TESTS): not a flake, nothing is retried" >&2
    return $attempt_status
  fi
  for failed_test in $failed_tests; do
    if [[ ! "$failed_test" =~ '^[A-Za-z0-9_]+/[A-Za-z0-9_]+$' ]]; then
      echo "    unexpected test name \"$failed_test\" in the log, so nothing is retried" >&2
      return $attempt_status
    fi
    retry_args+=("-only-testing:$UI_TEST_TARGET/$failed_test")
  done
  echo "    ${#failed_tests} UI test(s) failed, running them once more: ${failed_tests[*]}"

  attempt_status=0
  : > "$retry_log"
  start_ui_hang_sampler "$retry_log"
  RUN_TESTS_LABEL="$retry_label" run_tests test-without-building "$@" "${retry_args[@]}" || attempt_status=$?
  stop_ui_hang_sampler
  return $attempt_status
}

# Runs a package stage: build and test in one xcodebuild call, only the build with TAGWERK_BUILD_ONLY=1. A package has its
# own build graph, so there is nothing to share and nothing to do between build and test.
run_stage() {
  if [[ -n "${TAGWERK_BUILD_ONLY:-}" ]]; then
    build_for_testing "$@"
  else
    run_tests test "$@"
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
  package_destination="$DESTINATION"
  case "${PACKAGE_TEST_PLATFORM[$package_name]:-simulator}" in
    macos)
      if ! grep -q '\.macOS(' "$package_dir/Package.swift"; then
        echo "    $package_name is listed for macOS in PACKAGE_TEST_PLATFORM but Package.swift declares no macOS platform" >&2
        stage_failed
      fi
      package_destination="$MACOS_DESTINATION"
      echo "    tests run on macOS (no simulator)"
      ;;
    app-scheme)
      if ! grep -qE "package: *$package_name/${package_name}Tests" "$SCRIPT_DIR/project.yml"; then
        echo "    $package_name is listed for the app scheme in PACKAGE_TEST_PLATFORM but app/project.yml does not run ${package_name}Tests in the scheme Tagwerk" >&2
        stage_failed
      fi
      echo "    tests run in the app scheme (stage app scheme Tagwerk)"
      continue
      ;;
  esac
  scheme=$(resolve_package_scheme "$package_name") || stage_failed
  package_derived_data=$(default_derived_data_folder "$package_dir")
  [[ -z "$package_derived_data" ]] || remove_embedded_resource_bundles "$package_derived_data/Build/Products"
  run_stage -scheme "$scheme" -destination "$package_destination" || stage_failed
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
  # The scheme also runs the tests of the packages that need the simulator (AIKit). One build, then the tests.
  APP_ARGS=(-project "$SCRIPT_DIR/Tagwerk.xcodeproj" -scheme Tagwerk -destination "$DESTINATION" -derivedDataPath "$DERIVED")
  remove_embedded_resource_bundles "$DERIVED/Build/Products"
  build_for_testing "${APP_ARGS[@]}" || stage_failed
  verify_embedded_resource_bundles "$DERIVED/Build/Products" || { FAILED_PHASE="build"; stage_failed; }
  if [[ -z "${TAGWERK_BUILD_ONLY:-}" ]]; then
    run_tests test-without-building "${APP_ARGS[@]}" || stage_failed
  fi
fi

CURRENT_STAGE="app UI tests"
echo "==> $CURRENT_STAGE"
if [[ -n "${TAGWERK_SKIP_UI_TESTS:-}" ]]; then
  echo "    skipped (TAGWERK_SKIP_UI_TESTS)"
else
  # Same scheme, destination and derived data folder for the build and the test run. The build comes first and without
  # the UI stage lock: waiting for another UI stage does not delay it, and the lock only covers the test run. With
  # TAGWERK_BUILD_ONLY nothing else happens (no simulator boot, permissions or test selection: nothing is executed).
  UI_ARGS=(-project "$SCRIPT_DIR/Tagwerk.xcodeproj" -scheme TagwerkUITests -destination "$DESTINATION" -derivedDataPath "$DERIVED")
  # An invalid selection is reported before the build, not after it.
  if [[ -z "${TAGWERK_BUILD_ONLY:-}" ]]; then build_ui_selection_args || stage_failed; fi
  remove_embedded_resource_bundles "$DERIVED/Build/Products"
  build_for_testing "${UI_ARGS[@]}" || stage_failed
  verify_embedded_resource_bundles "$DERIVED/Build/Products" || { FAILED_PHASE="build"; stage_failed; }
  if [[ -z "${TAGWERK_BUILD_ONLY:-}" ]]; then
    # Only one UI test stage runs on the machine at a time (waits up to 60 minutes, then exits with code 2).
    echo "    taking the UI stage lock"
    tagwerk_acquire_ui_lock || exit 2
    # The UI tests read the demo data from the Calendar and Reminders stores; the permissions are granted
    # beforehand, so no system dialog can interrupt a test. The simulator is booted for this (the end of the run shuts it down).
    echo "    preparing the simulator for the UI tests"
    tagwerk_prepare_ui_simulator "$DESTINATION" "$SCRIPT_DIR/Tagwerk.xcodeproj" || stage_failed
    echo "    running the UI tests"
    ui_status=0
    run_ui_tests "${UI_ARGS[@]}" || ui_status=$?
    # The list is reported even when the stage fails: a test that wobbles is worth knowing about.
    if ui_retries_enabled; then
      retry_logs=("$LOG_DIR/app-UI-tests.log")
      [[ ! -s "$LOG_DIR/app-UI-tests-retry.log" ]] || retry_logs+=("$LOG_DIR/app-UI-tests-retry.log")
      report_retried_ui_tests "$LOG_DIR/retried-ui-tests.md" "${retry_logs[@]}"
    fi
    tagwerk_release_ui_lock
    (( ui_status == 0 )) || stage_failed
  fi
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
