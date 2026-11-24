#!/usr/bin/python3
"""Decides which jobs of .github/workflows/tests.yml have to run for a set of changed files.

The "changes" job of the workflow calls this script with the changed files of a pull request (one path per line on stdin) and
the event name. The result is written as `name=value` lines (the format of $GITHUB_OUTPUT) to stdout:

  run_fast     the macOS job "Tests (fast)" runs the package tests, the app unit tests and the String Catalog checks
  run_ui       the macOS jobs "UI shard (n/N)" run the UI tests
  run_scripts  the macOS job "Script tests" runs the tests of the helper scripts in scripts/tests
  reason       one sentence for the job summary

Rules for a pull request (every changed file is classified; the decision is the union over all files):
  documentation   docs/**, *.md                                         no job
  test run        app/**, .github/**, scripts that the test run uses     fast + ui + script tests
                  (see UI_RUN_SCRIPTS and EVERYTHING_SCRIPTS)
  string checks   scripts that only the String Catalog stage uses        fast + script tests
  other scripts   everything else below scripts/**                       script tests only
  unknown         any other path (root files, spike/, ...)               fast + ui + script tests (the safe default)
Other events: schedule and workflow_dispatch run everything, push (cache refresh after a merge) builds fast and ui.

The lists below are checked against the scripts that app/test-all.sh, scripts/test-env.sh and the workflow reference by
scripts/tests/test_ci_changes.py, so a new script that the test run needs cannot be forgotten silently.

Usage: git diff --name-only --no-renames HEAD^1 HEAD | ci-changes.py EVENT_NAME
"""
import fnmatch
import sys

# Scripts that the UI test run uses (test-all.sh sources test-env.sh, starts the sampler, the watchdog and the log reader, the
# workflow runs the mtime restore and the artifact collection). A change runs fast, ui and script tests.
UI_RUN_SCRIPTS = [
    "scripts/test-env.sh",
    "scripts/ui-hang-sampler.py",
    "scripts/ui-test-log.py",
    "scripts/ui-test-shards.py",
    "scripts/ui-watchdog.py",
    "scripts/ci-restore-mtimes.py",
    "scripts/ci-collect-artifacts.sh",
    "scripts/ci-changes.py",
    "scripts/run-script-tests.sh",
]

# Scripts that change the decision itself or the run of every job: treated like the workflow file.
EVERYTHING_SCRIPTS = UI_RUN_SCRIPTS

# Scripts of the String Catalog stage of test-all.sh (fast job only; the UI tests do not read them).
STRING_CHECK_SCRIPTS = [
    "scripts/check-strings.py",
    "scripts/check-colors.py",
    "scripts/sync-strings.sh",
    "scripts/catalog_format.py",
    "scripts/translations/*",
]

DOCUMENTATION_PATTERNS = ["docs/*", "*.md"]
EVERYTHING_PATTERNS = ["app/*", ".github/*"]


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def classify(path):
    """Returns the class of a changed path: docs, everything, string-checks or scripts."""
    if matches(path, DOCUMENTATION_PATTERNS):
        return "docs"
    if matches(path, EVERYTHING_PATTERNS) or path in EVERYTHING_SCRIPTS:
        return "everything"
    if matches(path, STRING_CHECK_SCRIPTS):
        return "string-checks"
    if path.startswith("scripts/"):
        return "scripts"
    return "everything"


def affects_script_tests(path, kind):
    """True when a change can alter the result of scripts/tests: scripts, the workflow, the test script and its selection files.
    A pure app change (Swift sources, project.yml, packages) cannot."""
    if kind == "docs":
        return False
    if path.startswith("app/"):
        return path == "app/test-all.sh" or path.startswith("app/TagwerkUITests/") and not path.endswith(".swift")
    return True


def decide(event_name, changed_files):
    """Returns the outputs (run_fast, run_ui, run_scripts, reason) as a dict of strings."""
    if event_name == "push":
        return outputs(True, True, False, "Push to main: build only, refreshes the build caches. No tests run.")
    if event_name != "pull_request":
        return outputs(True, True, True, "Full run: every job runs.")

    files = [path.strip() for path in changed_files if path.strip()]
    classes = {path: classify(path) for path in files}
    if not files:
        return outputs(True, True, True, "No changed files could be read: every job runs.")
    if all(kind == "docs" for kind in classes.values()):
        return outputs(False, False, False,
                       f"Tests skipped: the pull request changes only documentation ({len(files)} files: docs/**, *.md, TODO.md).")

    kinds = set(classes.values())
    run_ui = "everything" in kinds
    run_fast = run_ui or "string-checks" in kinds
    run_scripts = any(affects_script_tests(path, kind) for path, kind in classes.items())
    if run_ui:
        reason = "Tests run: the pull request changes the app or the files its test run uses."
    elif run_fast:
        reason = "UI tests skipped: only scripts of the String Catalog checks changed (fast tests and script tests run)."
    else:
        reason = "UI tests and fast tests skipped: only helper scripts changed (script tests run)."
    return outputs(run_fast, run_ui, run_scripts, reason)


def outputs(run_fast, run_ui, run_scripts, reason):
    return {
        "run_fast": "true" if run_fast else "false",
        "run_ui": "true" if run_ui else "false",
        "run_scripts": "true" if run_scripts else "false",
        "reason": reason,
    }


def main(argv):
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    result = decide(argv[0], sys.stdin.read().splitlines())
    for name, value in result.items():
        print(f"{name}={value}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
