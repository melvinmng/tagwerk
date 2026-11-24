"""Tests of scripts/ui-watchdog.py with fake commands (no xcodebuild, no simulator).

Run: /usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
"""
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
WATCHDOG = ROOT / "scripts" / "ui-watchdog.py"


class WatchdogTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.work = Path(self.folder.name)
        self.log = self.work / "stage.log"
        self.diag = self.work / "diag"
        # Stubs for the diagnostic tools: `sample` writes the file it is given, `xcrun` records its arguments.
        stubs = self.work / "bin"
        stubs.mkdir()
        self.write_executable(stubs / "sample", '#!/bin/sh\necho "stack of $1" > "$4"\n')
        self.write_executable(stubs / "xcrun", f'#!/bin/sh\necho "xcrun $*" >> "{self.work}/xcrun-calls.txt"\necho "xcrun output"\n')
        self.environment = dict(os.environ, PATH=f"{stubs}:{os.environ['PATH']}")

    @staticmethod
    def write_executable(path, text):
        path.write_text(text)
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def run_watchdog(self, command, *options, timeout=60):
        arguments = [sys.executable, "-I", str(WATCHDOG), "--phase", "ui tests", "--log", str(self.log),
                     "--diag-dir", str(self.diag), "--poll", "0.1", "--grace", "1", *options, "--", *command]
        return subprocess.run(arguments, capture_output=True, text=True, env=self.environment, timeout=timeout)

    def diagnostics_folder(self):
        folders = list(self.diag.glob("watchdog-ui_tests-*"))
        self.assertEqual(len(folders), 1, f"expected one diagnostics folder, found {folders}")
        return folders[0]

    def test_exitStatusOfTheCommandIsPassedOn_andOutputGoesToTheLog(self):
        result = self.run_watchdog(["/bin/sh", "-c", "echo to-stdout; echo to-stderr >&2; exit 3"])
        self.assertEqual(result.returncode, 3)
        self.assertEqual(sorted(self.log.read_text().split()), ["to-stderr", "to-stdout"])
        self.assertFalse(self.diag.exists())

    def test_testProgressLinesAreShown(self):
        script = ("echo \"Test Case '-[UI.A testOne]' started.\"; echo \"noise\"; "
                  "echo \"Test Case '-[UI.A testOne]' passed (1.0 seconds).\"; "
                  "echo \"Test Case '-[UI.A testTwo]' started.\"; echo \"Test Case '-[UI.A testTwo]' failed (2.0 seconds).\"")
        result = self.run_watchdog(["/bin/sh", "-c", script])
        self.assertEqual(result.returncode, 0)
        self.assertIn("started -[UI.A testOne]", result.stdout)
        self.assertIn("passed  -[UI.A testOne]", result.stdout)
        self.assertIn("failed  -[UI.A testTwo]", result.stdout)
        self.assertNotIn("noise", result.stdout)

    def test_appendMode_keepsEarlierLogContentAndShowsOnlyNewLines(self):
        self.log.write_text("Test Case 'Old.old' passed\nbuild output\n")
        result = self.run_watchdog(["/bin/sh", "-c", "echo \"Test Case 'New.new' passed\""], "--append")
        self.assertEqual(result.returncode, 0)
        self.assertTrue(self.log.read_text().startswith("Test Case 'Old.old' passed"))
        self.assertIn("New.new", result.stdout)
        self.assertNotIn("Old.old", result.stdout)

    def test_silentCommandIsStopped_withDiagnostics(self):
        marker = "4321"
        started = time.monotonic()
        result = self.run_watchdog(
            ["/bin/sh", "-c", f"echo first line; sleep {marker} & wait"], "--silence", "2", "--simulator-id",
            "AAAAAAAA-0000-0000-0000-000000000000", "--shutdown-simulator")
        self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
        self.assertLess(time.monotonic() - started, 40)
        self.assertIn('WATCHDOG: phase "ui tests" stopped: no log output for', result.stderr)
        folder = self.diagnostics_folder()
        summary = (folder / "summary.txt").read_text()
        self.assertIn("reason: no log output", summary)
        self.assertIn("first line", summary)
        for name in ("ps.txt", "simctl-booted.txt", "simulator-log.txt"):
            self.assertTrue((folder / name).exists(), name)
        calls = (self.work / "xcrun-calls.txt").read_text()
        self.assertIn("simctl list devices booted", calls)
        self.assertIn("simctl spawn AAAAAAAA-0000-0000-0000-000000000000 log show --last 10m --style compact", calls)
        self.assertIn("simctl shutdown AAAAAAAA-0000-0000-0000-000000000000", calls)
        # The command and the process it started (which left no trace in the log) are gone.
        survivors = subprocess.run(["pgrep", "-f", f"sleep {marker}"], capture_output=True, text=True).stdout.split()
        self.assertEqual(survivors, [])

    def test_xcodebuildBelowTheCommandIsSampled(self):
        # A process named xcodebuild below the command gets a stack sample (the stub of `sample` writes the file).
        fake = self.work / "bin" / "xcodebuild"
        self.write_executable(fake, "#!/bin/sh\necho started\nsleep 4343\n")
        result = self.run_watchdog([str(fake)], "--silence", "2")
        self.assertEqual(result.returncode, 124, result.stdout + result.stderr)
        samples = list(self.diagnostics_folder().glob("sample-xcodebuild-*.txt"))
        self.assertTrue(samples, list(self.diagnostics_folder().iterdir()))
        self.assertIn("stack of", samples[0].read_text())
        self.assertEqual(subprocess.run(["pgrep", "-f", "sleep 4343"], capture_output=True, text=True).stdout.split(), [])

    def test_commandThatKeepsWriting_isStoppedByTheHardLimit(self):
        result = self.run_watchdog(["/bin/sh", "-c", "while true; do echo tick; sleep 0.2; done"],
                                   "--silence", "30", "--max-seconds", "2")
        self.assertEqual(result.returncode, 124)
        self.assertIn("run time limit of 2 s reached", result.stderr)
        self.assertIn("reason: run time limit", (self.diagnostics_folder() / "summary.txt").read_text())

    def test_simulatorIsLeftAloneWithoutTheShutdownSwitch(self):
        result = self.run_watchdog(["/bin/sleep", "60"], "--silence", "1", "--simulator-id", "BBBBBBBB-0000-0000-0000-000000000000")
        self.assertEqual(result.returncode, 124)
        self.assertNotIn("simctl shutdown", (self.work / "xcrun-calls.txt").read_text())

    def test_heartbeatReportsTheState(self):
        result = self.run_watchdog(["/bin/sh", "-c", "sleep 2.5"], "--heartbeat", "1")
        self.assertEqual(result.returncode, 0)
        self.assertIn("running; last log output", result.stdout)
        self.assertIn("tests: 0 passed, 0 failed", result.stdout)

    def test_missingCommand_isReported(self):
        result = self.run_watchdog(["/nonexistent/xcodebuild"])
        self.assertEqual(result.returncode, 127)


if __name__ == "__main__":
    unittest.main()
