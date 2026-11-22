#!/bin/zsh
# Repeats the accessibility audit UI tests and reports which tests or findings are not stable.
#
# Every iteration is a run of its own (own log, own collect file), without retry on failure and without stopping
# at the first failure, so each repetition counts. Run it when audits, UITestMode, DemoData or the app start change;
# it takes many times as long as app/test-all.sh. One test run per checkout: the script takes the same lock as
# app/test-all.sh.
#
# Usage: scripts/stress-audits.sh [--collect] [iterations] [only-testing ...]
#   iterations     number of repetitions (default 10)
#   only-testing   test selectors relative to the UI test bundle, e.g. AccessibilityAuditRecipesUITests/testAuditCreateRecipe;
#                  default: all audit classes
#   --collect      collect mode (TEST_RUNNER_AUDIT_COLLECT_FILE): the audits do not fail, every finding that is not on the
#                  allowlist is written to a file per iteration; the report lists each finding with the number of iterations it
#                  appeared in. Findings that do not appear in every iteration are the flaky ones. With the default test
#                  selection the report also lists the allowlist entries that no finding matched in any iteration (dead entries).
# Exit codes: 0 all repetitions passed (collect mode: always), 1 at least one failure, 2 setup failure or another run is active

set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

REPO_ROOT="${0:A:h:h}"
APP_DIR="$REPO_ROOT/app"
source "$REPO_ROOT/scripts/test-env.sh"

COLLECT=0
if [[ "${1:-}" == "--collect" ]]; then COLLECT=1; shift; fi
ITERATIONS="${1:-10}"
(( $# > 0 )) && shift
if ! [[ "$ITERATIONS" =~ '^[1-9][0-9]*$' ]]; then
  echo "Usage: scripts/stress-audits.sh [--collect] [iterations] [only-testing ...]" >&2
  exit 2
fi
SELECTORS=("$@")
ALL_CLASSES=0
if (( ${#SELECTORS} == 0 )); then
  SELECTORS=(AccessibilityAuditUITests AccessibilityAuditLargeTextUITests AccessibilityAuditRecipesUITests AccessibilityAuditRecipesLargeTextUITests
             AccessibilityAuditEveningUITests AccessibilityAuditEveningLargeTextUITests)
  ALL_CLASSES=1
fi

tagwerk_acquire_run_lock || exit 2
trap tagwerk_release_run_lock EXIT

DESTINATION=$(tagwerk_test_destination) || exit 2
RUN_DIR="$TAGWERK_TEST_LOG_DIR/stress-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN_DIR"
echo "==> stress run: $ITERATIONS iteration(s), $DESTINATION, logs in $RUN_DIR"

echo "==> xcodegen"
(cd "$APP_DIR" && xcodegen --quiet) || exit 2
tagwerk_prepare_ui_simulator "$DESTINATION" "$APP_DIR/Tagwerk.xcodeproj" || exit 2

echo "==> build-for-testing"
if ! xcodebuild build-for-testing -project "$APP_DIR/Tagwerk.xcodeproj" -scheme TagwerkUITests -destination "$DESTINATION" \
    -derivedDataPath "$TAGWERK_TEST_DERIVED" -testLanguage de -testRegion DE > "$RUN_DIR/build.log" 2>&1; then
  grep -E "error:" "$RUN_DIR/build.log" | tail -n 20 >&2 || true
  echo "Build failed (log: $RUN_DIR/build.log)" >&2
  exit 2
fi

ONLY_ARGUMENTS=()
for selector in "${SELECTORS[@]}"; do ONLY_ARGUMENTS+=("-only-testing:TagwerkUITests/$selector"); done

for iteration in {1..$ITERATIONS}; do
  log="$RUN_DIR/iteration-$iteration.log"
  started=$SECONDS
  if (( COLLECT )); then
    export TEST_RUNNER_AUDIT_COLLECT_FILE="$RUN_DIR/collect-$iteration.txt"
    : > "$TEST_RUNNER_AUDIT_COLLECT_FILE"
  fi
  # A failing run is expected data here: the exit code is not evaluated, the log is.
  xcodebuild test-without-building -project "$APP_DIR/Tagwerk.xcodeproj" -scheme TagwerkUITests -destination "$DESTINATION" \
    -derivedDataPath "$TAGWERK_TEST_DERIVED" -testLanguage de -testRegion DE "${ONLY_ARGUMENTS[@]}" > "$log" 2>&1 || true
  echo "    iteration $iteration/$ITERATIONS: $((SECONDS - started)) s, $(grep -c "^Test Case .* failed" "$log" || true) failed test(s)"
done

echo "==> report"
/usr/bin/python3 - "$RUN_DIR" "$COLLECT" "$ALL_CLASSES" <<'PYTHON'
import collections
import glob
import os
import re
import sys

run_dir, collect, all_classes = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1"
logs = sorted(glob.glob(os.path.join(run_dir, "iteration-*.log")), key=lambda path: int(re.findall(r"\d+", os.path.basename(path))[0]))
start_pattern = re.compile(r"^Test Case '-\[(?:\S+\.)?(\S+) (\S+)\]' started\.")
case_pattern = re.compile(r"^Test Case '-\[(?:\S+\.)?(\S+) (\S+)\]' (passed|failed) \(([\d.]+) seconds\)")
error_pattern = re.compile(r"error: -\[(?:\S+\.)?(\S+) (\S+)\] : (.*)")

runs = collections.Counter()
aborted = collections.Counter()
starts = collections.Counter()
failures = collections.Counter()
seconds = collections.defaultdict(float)
messages = collections.defaultdict(collections.Counter)
timeouts = 0
for path in logs:
    with open(path, errors="replace") as handle:
        for line in handle:
            match = start_pattern.match(line)
            if match:
                starts[f"{match.group(1)}/{match.group(2)}"] += 1
                continue
            match = case_pattern.match(line)
            if match:
                name = f"{match.group(1)}/{match.group(2)}"
                runs[name] += 1
                seconds[name] += float(match.group(4))
                if match.group(3) == "failed":
                    failures[name] += 1
                continue
            match = error_pattern.search(line)
            if match:
                text = re.sub(r"0x[0-9a-f]+|\d+(\.\d+)?", "N", match.group(3))[:200]
                messages[f"{match.group(1)}/{match.group(2)}"][text] += 1
            if "Accessibility audit timed out" in line:
                timeouts += 1

# A test that started but has no result line was cut off (crash or test timeout: "Restarting after unexpected exit, crash, or test
# timeout"); it counts as a failed run.
for name in starts:
    aborted[name] = max(0, starts[name] - runs[name])
print(f"Iterations: {len(logs)}")
print(f"{'test':<95} {'runs':>5} {'failed':>7} {'aborted':>8} {'mean s':>7}")
for name in sorted(starts):
    mean = seconds[name] / runs[name] if runs[name] else 0.0
    print(f"{name:<95} {starts[name]:>5} {failures[name]:>7} {aborted[name]:>8} {mean:>7.1f}")
print(f"Audit timeout repetitions (\"Accessibility audit timed out\"): {timeouts}")
total_failed = sum(failures.values()) + sum(aborted.values())
print(f"Failed or aborted test runs in total: {total_failed} of {sum(starts.values())}")

if messages:
    print("\nFailure messages, grouped (digits replaced by N):")
    for name, counter in sorted(messages.items()):
        for text, count in counter.most_common():
            print(f"  {count:>3}x {name}: {text}")

if collect:
    findings = collections.defaultdict(set)
    defined, hit = {}, set()
    files = sorted(glob.glob(os.path.join(run_dir, "collect-*.txt")))
    for path in files:
        iteration = int(re.findall(r"\d+", os.path.basename(path))[0])
        with open(path, errors="replace") as handle:
            for line in handle:
                if line.startswith("ENTRY-DEFINED "):
                    index, _, description = line[len("ENTRY-DEFINED "):].strip().partition(" | ")
                    defined[int(index)] = description
                    continue
                if line.startswith("ENTRY-HIT "):
                    hit.add(int(line.split()[1]))
                    continue
                # The frame is left out: a changing frame is part of what makes a finding flaky, not a different finding.
                key = re.sub(r" frame=.*$", "", line.strip())
                findings[key].add(iteration)
    total = len(files)
    print(f"\nCollected findings that are not on the allowlist, by number of iterations (of {total}):")
    for key, iterations in sorted(findings.items(), key=lambda item: (len(item[1]), item[0])):
        marker = "STABLE" if len(iterations) == total else "FLAKY "
        print(f"  {marker} {len(iterations):>3}/{total}  {key}")
    if not findings:
        print("  none")
    if all_classes:
        dead = [index for index in sorted(defined) if index not in hit]
        print(f"\nAllowlist entries that no finding matched in any iteration ({len(dead)} of {len(defined)}; index | type | screens | first labels):")
        for index in dead:
            print(f"  [{index}] {defined[index]}")
    sys.exit(0)

sys.exit(1 if total_failed else 0)
PYTHON
