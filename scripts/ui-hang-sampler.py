#!/usr/bin/python3
"""Takes a stack sample of the app process when a UI test run shows that the app does not answer.

Started in the background by app/test-all.sh for the UI test stage. It follows the xcodebuild log of the stage and, when a line
shows a hang, runs `sample` on the app process of the simulator and writes the result to hang-<time>-<test>.txt in the log folder
(the CI workflow uploads that folder with the other logs). The samples show the stack of the main thread, which tells whether the app
waits for the system or runs code of its own. At most one sample per test; the script never changes the test result, takes no part
in the run, and ends when the stop file appears or the parent process ends.

Hang signs in the log (the text of the XCTest message, one line each):
  Checking existence of ... (retry 2)        a wait for an element that did not find it on the first query
  Failed to get matching snapshots: Timed out while evaluating UI query     the app did not answer an accessibility query

Usage: ui-hang-sampler.py LOG OUTPUT_DIR STOP_FILE [--simulator-id UDID] [--duration SECONDS] [--poll SECONDS]
"""
import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HANG_PATTERNS = [
    re.compile(r"Checking existence of .*\(retry 2\)"),
    re.compile(r"Failed to get matching snapshots: Timed out while evaluating UI query"),
]
TEST_STARTED = re.compile(r"Test [Cc]ase '([^']+)' started")


def hang_line(line):
    """True when the log line shows that the app does not answer."""
    return any(pattern.search(line) for pattern in HANG_PATTERNS)


def started_test(line):
    """The name of the test that the line reports as started, else None."""
    match = TEST_STARTED.search(line)
    return match.group(1) if match else None


class HangDetector:
    """Feeds on log lines and says for which of them a sample is due: the first hang line of each test."""

    def __init__(self):
        self.current_test = None
        self.sampled_tests = set()

    def feed(self, line):
        """Returns the name to use for the sample (the current test) or None when no sample is due."""
        name = started_test(line)
        if name is not None:
            self.current_test = name
            return None
        if not hang_line(line):
            return None
        key = self.current_test or "unknown-test"
        if key in self.sampled_tests:
            return None
        self.sampled_tests.add(key)
        return key


def app_process_ids(simulator_id):
    """Process ids of the app in the simulator (the app runs as a process of the Mac)."""
    pattern = r"Tagwerk\.app/Tagwerk"
    if simulator_id:
        pattern = rf"Devices/{re.escape(simulator_id)}/.*{pattern}"
    result = subprocess.run(["/usr/bin/pgrep", "-f", pattern], capture_output=True, text=True)
    return [int(value) for value in result.stdout.split()]


def safe_file_part(text):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", text).strip("_")[:80] or "test"


def take_samples(test_name, output_dir, simulator_id, duration):
    stamp = time.strftime("%H%M%S")
    for process_id in app_process_ids(simulator_id):
        target = Path(output_dir) / f"hang-{stamp}-{safe_file_part(test_name)}-{process_id}.txt"
        print(f"ui-hang-sampler: sampling process {process_id} for {test_name} -> {target.name}", flush=True)
        subprocess.run(["/usr/bin/sample", str(process_id), str(duration), "-file", str(target)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def follow(log, stop_file, parent_process_id, poll):
    """Yields the lines that are appended to `log` from now on, until the stop file exists or the parent process ends."""
    while not os.path.exists(log):
        if os.path.exists(stop_file) or os.getppid() != parent_process_id:
            return
        time.sleep(poll)
    with open(log, errors="replace") as handle:
        handle.seek(0, os.SEEK_END)
        pending = ""
        while True:
            chunk = handle.read()
            if chunk:
                pending += chunk
                *lines, pending = pending.split("\n")
                yield from lines
                continue
            if os.path.exists(stop_file) or os.getppid() != parent_process_id:
                return
            time.sleep(poll)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log")
    parser.add_argument("output_dir")
    parser.add_argument("stop_file")
    parser.add_argument("--simulator-id", default="")
    parser.add_argument("--duration", type=int, default=3)
    parser.add_argument("--poll", type=float, default=1.0)
    arguments = parser.parse_args(argv)
    detector = HangDetector()
    for line in follow(arguments.log, arguments.stop_file, os.getppid(), arguments.poll):
        test_name = detector.feed(line)
        if test_name is not None:
            take_samples(test_name, arguments.output_dir, arguments.simulator_id, arguments.duration)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
