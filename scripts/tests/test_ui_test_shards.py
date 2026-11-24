"""Tests of the distribution of the UI test classes into shards (scripts/ui-test-shards.py).

Run: /usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
"""
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
spec = importlib.util.spec_from_file_location("ui_test_shards", ROOT / "scripts" / "ui-test-shards.py")
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)

TESTS_DIR = ROOT / "app" / "TagwerkUITests"


class ReadClassesTests(unittest.TestCase):
    def read(self, sources):
        with tempfile.TemporaryDirectory() as folder:
            for name, text in sources.items():
                (Path(folder) / name).write_text(text)
            return shards.read_classes(folder)

    def test_classesWithTests_areFound_baseClassesWithoutTests_are_not(self):
        classes = self.read({
            "Base.swift": "class UITestCase: XCTestCase {\n  func helper() {}\n}\n",
            "A.swift": "final class AUITests: UITestCase {\n  func testOne() {}\n  @MainActor func testTwo() throws {}\n  func notATest() {}\n}\n",
            "B.swift": "class BUITests: UITestCase {\n  func testOnly() {}\n}\nfinal class CUITests: UITestCase {\n  func testC() {}\n}\n",
        })
        self.assertEqual(classes, {"AUITests": ["testOne", "testTwo"], "BUITests": ["testOnly"], "CUITests": ["testC"]})

    def test_inheritedTests_countForTheSubclass(self):
        classes = self.read({"A.swift": "class AUITests: UITestCase {\n  func testBase() {}\n}\nfinal class ALargeUITests: AUITests {\n}\n"})
        self.assertEqual(classes["ALargeUITests"], ["testBase"])


class WideningTests(unittest.TestCase):
    def test_attributesModifiersAndExtensions(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "A.swift").write_text(
                "@MainActor final class AUITests: UITestCase {\n  func testA() {}\n}\n"
                "public final class BUITests: UITestCase {\n  func testB() {}\n}\n"
                "@MainActor\nfinal class CUITests: UITestCase {\n}\n"
                "extension CUITests {\n  func testFromExtension() {}\n}\n")
            (Path(folder) / "B.swift").write_text("extension DUITests {\n  func testEarly() {}\n}\nclass DUITests: UITestCase {\n}\n")
            self.assertEqual(shards.read_classes(folder), {"AUITests": ["testA"], "BUITests": ["testB"],
                                                           "CUITests": ["testFromExtension"], "DUITests": ["testEarly"]})


class SelectionTests(unittest.TestCase):
    classes = {"A": ["testA1", "testA2"], "B": ["testB"], "C": ["testC"]}

    def test_fullSet_keepsEverything(self):
        self.assertEqual(shards.selected_classes(self.classes, "full", ["B"]), self.classes)

    def test_prSet_dropsClassesWhoseTestsAreAllSkipped(self):
        selected = shards.selected_classes(self.classes, "pr", ["B", "C/testC", "A/testA1"])
        self.assertEqual(selected, {"A": ["testA2"]})


class PartitionTests(unittest.TestCase):
    def test_longestFirstToTheLightestShard(self):
        result = shards.partition({"a": 100, "b": 90, "c": 60, "d": 50, "e": 10}, 2)
        self.assertEqual(result, [["a", "d", "e"], ["b", "c"]])

    def test_everyClassExactlyOnce_andDeterministic(self):
        weights = {f"Class{number}": float(number % 7 + 1) for number in range(23)}
        for count in (1, 2, 3, 5):
            result = shards.partition(weights, count)
            self.assertEqual(sorted(name for shard in result for name in shard), sorted(weights))
            self.assertEqual(result, shards.partition(dict(reversed(list(weights.items()))), count))

    def test_unlistedClasses_getTheMeanWeight(self):
        weights, unlisted = shards.weights_for(["a", "b", "c"], {"a": 10.0, "b": 30.0})
        self.assertEqual(weights, {"a": 10.0, "b": 30.0, "c": 20.0})
        self.assertEqual(unlisted, ["c"])

    def test_nothingListed_usesOneMinuteEach(self):
        weights, unlisted = shards.weights_for(["a"], {})
        self.assertEqual(weights, {"a": 60.0})


class FileFormatTests(unittest.TestCase):
    def test_durationsFile_commentsAndBlankLinesAreIgnored(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "d.txt"
            path.write_text("# comment\n\nA 12.5  # trailing\nB 3\n")
            self.assertEqual(shards.read_durations(path), {"A": 12.5, "B": 3.0})
            path.write_text("A twelve\n")
            with self.assertRaises(ValueError):
                shards.read_durations(path)

    def test_missingFiles_giveEmptyResults(self):
        self.assertEqual(shards.read_durations("/nonexistent/file"), {})
        self.assertEqual(shards.read_entries("/nonexistent/file"), [])


class RepositoryTests(unittest.TestCase):
    """The real UI test sources and the real weights."""

    def plan(self, count, test_set):
        return shards.build_plan(TESTS_DIR, TESTS_DIR / "ui-test-durations.txt", TESTS_DIR / "nightly-only.txt", test_set, count)

    def test_theShardsTogetherAreTheWholeSet_withoutOverlap(self):
        for test_set in ("pr", "full"):
            classes = shards.selected_classes(shards.read_classes(TESTS_DIR), test_set, shards.read_entries(TESTS_DIR / "nightly-only.txt"))
            for count in (1, 2, 3):
                with self.subTest(test_set=test_set, count=count):
                    result, _, _ = self.plan(count, test_set)
                    self.assertEqual(sorted(name for shard in result for name in shard), sorted(classes))
                    self.assertTrue(all(shard for shard in result))

    def test_twoShardsOfThePullRequestSet_areBalanced(self):
        result, weights, _ = self.plan(2, "pr")
        totals = [sum(weights[name] for name in shard) for shard in result]
        self.assertLess(max(totals) / min(totals), 1.1, totals)

    def test_everyClassHasADuration(self):
        _, _, unlisted = self.plan(2, "full")
        self.assertEqual(unlisted, [], f"add {unlisted} to app/TagwerkUITests/ui-test-durations.txt")

    def test_commandLine_printsTheClassesOfTheShard(self):
        outputs = []
        for index in (1, 2):
            result = subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / "ui-test-shards.py"), "shard", f"{index}/2", "--set", "pr"],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs.append(result.stdout.split())
        self.assertFalse(set(outputs[0]) & set(outputs[1]))
        self.assertTrue(outputs[0] and outputs[1])

    def test_commandLine_othersAreTheComplementOfTheShard(self):
        def classes(mode, spec):
            result = subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / "ui-test-shards.py"), mode, spec, "--set", "pr"],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.split()
        everything = classes("shard", "1/1")
        self.assertEqual(sorted(classes("others", "2/2")), sorted(classes("shard", "1/2")))
        self.assertEqual(sorted(classes("others", "1/2") + classes("shard", "1/2")), sorted(everything))
        self.assertEqual(classes("others", "1/1"), [])

    def test_commandLine_rejectsInvalidShards(self):
        for spec_text in ("0/2", "3/2", "2", "1/9", "a/b"):
            result = subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / "ui-test-shards.py"), "shard", spec_text],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, spec_text)


if __name__ == "__main__":
    unittest.main()
