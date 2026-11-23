"""Tests of the log reading of scripts/ui-hang-sampler.py (no sample is taken, no simulator is needed).

Run: /usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
"""
import importlib.util
import os
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
spec = importlib.util.spec_from_file_location("ui_hang_sampler", ROOT / "scripts" / "ui-hang-sampler.py")
sampler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sampler)


class HangLineTests(unittest.TestCase):
    def test_retryTwoOfAnExistenceCheck_isAHang(self):
        self.assertTrue(sampler.hang_line("    t =    61.62s     Checking existence of `Navigation Bar` (retry 2)"))

    def test_snapshotTimeout_isAHang(self):
        self.assertTrue(sampler.hang_line("Failed to get matching snapshots: Timed out while evaluating UI query"))

    def test_firstQueryOfAnExistenceCheck_isNot(self):
        self.assertFalse(sampler.hang_line("    t =    61.62s     Checking existence of `Navigation Bar`"))
        self.assertFalse(sampler.hang_line("    t =    61.62s     Checking existence of `Navigation Bar` (retry 1)"))

    def test_otherLines_areNot(self):
        self.assertFalse(sampler.hang_line("Test Case '-[TagwerkUITests.X testY]' started."))
        self.assertFalse(sampler.hang_line(""))


class HangDetectorTests(unittest.TestCase):
    def test_oneSamplePerTest(self):
        detector = sampler.HangDetector()
        self.assertIsNone(detector.feed("Test Case '-[TagwerkUITests.A testOne]' started."))
        self.assertEqual(detector.feed("Checking existence of `x` (retry 2)"), "-[TagwerkUITests.A testOne]")
        self.assertIsNone(detector.feed("Failed to get matching snapshots: Timed out while evaluating UI query"))
        self.assertIsNone(detector.feed("Checking existence of `y` (retry 2)"))

    def test_nextTestGetsItsOwnSample(self):
        detector = sampler.HangDetector()
        detector.feed("Test case 'A.testOne()' started on 'iPhone'")
        self.assertEqual(detector.feed("Checking existence of `x` (retry 2)"), "A.testOne()")
        detector.feed("Test case 'A.testTwo()' started on 'iPhone'")
        self.assertEqual(detector.feed("Checking existence of `x` (retry 2)"), "A.testTwo()")

    def test_hangBeforeAnyTestStarted_isNamedUnknown(self):
        self.assertEqual(sampler.HangDetector().feed("Checking existence of `x` (retry 2)"), "unknown-test")

    def test_normalLines_giveNoSample(self):
        detector = sampler.HangDetector()
        for line in ["Test Case 'A.testOne()' started", "Checking existence of `x`", "Tap Button", "Test Case 'A.testOne()' passed"]:
            self.assertIsNone(detector.feed(line))


class FollowTests(unittest.TestCase):
    def test_readsOnlyLinesAppendedAfterTheStart_andEndsWithTheStopFile(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "ui.log"
            stop = Path(folder) / "stop"
            log.write_text("old line\n")
            seen = []

            def read():
                seen.extend(sampler.follow(str(log), str(stop), os.getppid(), 0.05))

            reader = threading.Thread(target=read)
            reader.start()
            time.sleep(0.3)
            with log.open("a") as handle:
                handle.write("first\nsecond\npart")
                handle.flush()
                time.sleep(0.3)
                handle.write("ial\n")
            time.sleep(0.3)
            stop.write_text("")
            reader.join(timeout=5)
            self.assertFalse(reader.is_alive())
            self.assertEqual(seen, ["first", "second", "partial"])


if __name__ == "__main__":
    unittest.main()
