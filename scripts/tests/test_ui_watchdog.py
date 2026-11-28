"""Tests of scripts/ui-watchdog.py with fake commands (no xcodebuild, no simulator).

Run: /usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
"""
import argparse
import contextlib
import importlib.util
import io
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

spec = importlib.util.spec_from_file_location("ui_watchdog", WATCHDOG)
watchdog_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(watchdog_module)


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

    @staticmethod
    def in_process_arguments(**overrides):
        values = dict(phase="ui tests", log="", diag_dir="", append=False, silence=0, max_seconds=0, heartbeat=0,
                      simulator_id="", shutdown_simulator=False, grace=1.0, poll=0.05)
        values.update(overrides)
        return argparse.Namespace(**values)

    def test_appendMode_doesNotSkipOutputWrittenBeforePopenReturns(self):
        # The child writes to the log before subprocess.Popen returns to the watchdog; the read offset must already be
        # fixed at the old end of the file, so that output still reaches the progress display.
        self.log.write_text("Test Case 'Old.old' passed\n")
        real_popen = subprocess.Popen

        def popen_with_immediate_output(command, **kwargs):
            kwargs["stdout"].write(b"Test Case 'Early.early' passed (0.1 seconds).\n")
            kwargs["stdout"].flush()
            return real_popen(command, **kwargs)

        arguments = self.in_process_arguments(log=str(self.log), append=True)
        captured = io.StringIO()
        original = watchdog_module.subprocess.Popen
        watchdog_module.subprocess.Popen = popen_with_immediate_output
        try:
            with contextlib.redirect_stdout(captured):
                status = watchdog_module.Watchdog(arguments, ["/bin/sh", "-c", "exit 0"]).run()
        finally:
            watchdog_module.subprocess.Popen = original
        self.assertEqual(status, 0)
        self.assertIn("Early.early", captured.getvalue())
        self.assertNotIn("Old.old", captured.getvalue())

    def test_testmanagerdIsSampledWithoutTheSimulatorIdInItsCommandLine(self):
        udid = "CCCCCCCC-0000-0000-0000-000000000000"
        table = [
            (101, 1, "/Library/Developer/CoreSimulator/Volumes/runtime/usr/libexec/testmanagerd"),
            (102, 1, "/other/path/Tagwerk.app/Tagwerk"),
            (103, 1, f"/Devices/{udid}/data/Tagwerk.app/Tagwerk"),
            (104, 1, "/somewhere/TagwerkUITests-Runner"),
            (105, 1, f"/Devices/{udid}/TagwerkUITests-Runner"),
        ]
        watchdog = watchdog_module.Watchdog(self.in_process_arguments(simulator_id=udid), ["true"])
        self.assertEqual(watchdog.processes_to_sample(table, []),
                         [(101, "testmanagerd"), (103, "app"), (105, "runner")])
        unrestricted = watchdog_module.Watchdog(self.in_process_arguments(), ["true"])
        self.assertEqual([pid for pid, _ in unrestricted.processes_to_sample(table, [])], [101, 102, 103, 104, 105])

    def test_descendantsGetTheGracePeriodWhenTheParentExitsAtOnce(self):
        # The parent exits on TERM immediately; the descendant needs 0.5 s to finish its cleanup. Without waiting for the
        # descendant, the KILL would follow at once and the cleanup marker would never be written.
        marker = self.work / "cleanup-done"
        ready = self.work / "child-ready"
        child = (
            "import signal, sys, time, pathlib\n"
            f"def on_term(signum, frame):\n    time.sleep(0.5)\n    pathlib.Path({str(marker)!r}).write_text('done')\n    sys.exit(0)\n"
            "signal.signal(signal.SIGTERM, on_term)\n"
            f"pathlib.Path({str(ready)!r}).write_text('ready')\n"
            "time.sleep(60)\n"
        )
        child_file = self.work / "slow_child.py"
        child_file.write_text(child)
        parent = f"trap 'exit 0' TERM; {sys.executable} {child_file} & wait"
        process = subprocess.Popen(["/bin/sh", "-c", parent], start_new_session=True)
        self.addCleanup(lambda: os.killpg(process.pid, 9) if process.poll() is None else None)
        deadline = time.monotonic() + 10
        while not ready.exists() and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertTrue(ready.exists(), "the helper process did not start")
        watchdog = watchdog_module.Watchdog(self.in_process_arguments(grace=5.0), ["unused"])
        watchdog.process = process
        watchdog.terminate_command()
        self.assertTrue(marker.exists(), "the descendant was killed before its grace period ended")


if __name__ == "__main__":
    unittest.main()
