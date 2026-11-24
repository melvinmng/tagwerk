#!/usr/bin/python3
"""Reads the results of UI tests from xcodebuild logs (used by app/test-all.sh).

  ui-test-log.py failed LOG
      Prints the tests whose last result in LOG is "failed", one `Class/method` per line (the form that -only-testing takes).
  ui-test-log.py retried LOG [LOG ...]
      Reads the logs in the order of the attempts and prints the tests that failed in an earlier attempt and passed in the last one,
      one `Class/method` per line. When the logs report failed attempts but no test name can be read, it prints UNPARSED.

Both read the classic XCTest lines (`Test Case '-[Module.Class method]' failed (1.0 seconds).`) and the newer ones
(`Test case 'Class.method()' failed on 'iPhone' (1.0 seconds)`).
"""
import re
import sys

RESULT_LINE = re.compile(r"Test [Cc]ase '([^']+)' (passed|failed)")
FAILURE_SUMMARY = re.compile(r"Executed \d+ tests?, with ([1-9]\d*) failures?")


def test_name(raw):
    """`Class/method` of the name in a result line."""
    if raw.startswith("-["):
        suite, _, method = raw[2:-1].partition(" ")
    else:
        suite, _, method = raw.rstrip("()").rpartition(".")
    return suite.split(".")[-1] + "/" + method


def read_logs(paths):
    """Returns (last result per test, tests that failed at least once, number of failure summaries)."""
    results = {}
    failed_once = set()
    summary_failures = 0
    for path in paths:
        with open(path, errors="replace") as handle:
            for line in handle:
                match = RESULT_LINE.search(line)
                if match:
                    raw, outcome = match.groups()
                    name = test_name(raw)
                    results[name] = outcome
                    if outcome == "failed":
                        failed_once.add(name)
                elif FAILURE_SUMMARY.search(line):
                    summary_failures += 1
    return results, failed_once, summary_failures


def main(argv):
    if len(argv) < 2 or argv[0] not in ("failed", "retried"):
        print(__doc__, file=sys.stderr)
        return 2
    results, failed_once, summary_failures = read_logs(argv[1:])
    if argv[0] == "failed":
        for name in sorted(failed_once):
            if results.get(name) == "failed":
                print(name)
        return 0
    for name in sorted(failed_once):
        if results.get(name) == "passed":
            print(name)
    if not failed_once and summary_failures:
        print("UNPARSED")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
