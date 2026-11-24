"""Tests of the changes decision of the CI workflow (scripts/ci-changes.py).

Run: /usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
"""
import importlib.util
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
spec = importlib.util.spec_from_file_location("ci_changes", ROOT / "scripts" / "ci-changes.py")
ci_changes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci_changes)


def decide(files, event="pull_request"):
    result = ci_changes.decide(event, files)
    return result["run_fast"] == "true", result["run_ui"] == "true", result["run_scripts"] == "true"


class PullRequestDecisionTests(unittest.TestCase):
    def test_documentationOnly_runsNothing(self):
        self.assertEqual(decide(["docs/plan.md", "README.md", "TODO.md", "app/README.md"]), (False, False, False))
        self.assertIn("only documentation (4 files", ci_changes.decide("pull_request", ["docs/a.md", "b.md", "c.md", "d.md"])["reason"])

    def test_appSources_runFastAndUiButNoScriptTests(self):
        self.assertEqual(decide(["app/Tagwerk/Plan/PlanView.swift"]), (True, True, False))
        self.assertEqual(decide(["app/project.yml"]), (True, True, False))
        self.assertEqual(decide(["app/Packages/AIKit/Sources/AIKit/Client.swift", "docs/x.md"]), (True, True, False))
        self.assertEqual(decide(["app/TagwerkUITests/NotesUITests.swift"]), (True, True, False))

    def test_testScriptAndSelectionFilesOfTheApp_alsoRunScriptTests(self):
        self.assertEqual(decide(["app/test-all.sh"]), (True, True, True))
        self.assertEqual(decide(["app/TagwerkUITests/nightly-only.txt"]), (True, True, True))
        self.assertEqual(decide(["app/TagwerkUITests/ui-test-durations.txt"]), (True, True, True))

    def test_workflowAndTheScriptsOfTheTestRun_runEverything(self):
        for path in [".github/workflows/tests.yml", ".github/actions/x/action.yml", "scripts/test-env.sh", "scripts/ui-hang-sampler.py",
                     "scripts/ui-test-log.py", "scripts/ui-test-shards.py", "scripts/ui-watchdog.py", "scripts/ci-restore-mtimes.py",
                     "scripts/ci-collect-artifacts.sh", "scripts/ci-changes.py", "scripts/run-script-tests.sh"]:
            with self.subTest(path=path):
                self.assertEqual(decide([path]), (True, True, True))

    def test_stringCheckScripts_runFastButNotUi(self):
        for path in ["scripts/check-strings.py", "scripts/check-colors.py", "scripts/sync-strings.sh", "scripts/catalog_format.py",
                     "scripts/translations/en.json"]:
            with self.subTest(path=path):
                self.assertEqual(decide([path]), (True, False, True))

    def test_otherScripts_runOnlyTheScriptTests(self):
        for path in ["scripts/refresh-install.sh", "scripts/install-dev.sh", "scripts/stress-audits.sh", "scripts/tests/test_x.py",
                     "scripts/merge-xcstrings.py", "scripts/README.md"[:-3] + ".txt"]:
            with self.subTest(path=path):
                self.assertEqual(decide([path]), (False, False, True))

    def test_documentationNextToOtherScripts_changesNothingAboutTheDecision(self):
        self.assertEqual(decide(["scripts/README.md", "scripts/refresh-install.sh"]), (False, False, True))

    def test_theUnionOverAllFilesDecides(self):
        self.assertEqual(decide(["scripts/refresh-install.sh", "app/Tagwerk/A.swift"]), (True, True, True))
        self.assertEqual(decide(["scripts/check-colors.py", "scripts/refresh-install.sh"]), (True, False, True))

    def test_unknownPaths_runEverything(self):
        self.assertEqual(decide(["Package.swift"]), (True, True, True))
        self.assertEqual(decide(["spike/Sources/main.swift"]), (True, True, True))
        self.assertEqual(decide([".gitattributes"]), (True, True, True))

    def test_noReadableFiles_runEverything(self):
        self.assertEqual(decide([]), (True, True, True))
        self.assertEqual(decide(["", "  "]), (True, True, True))

    def test_blankLinesAndWhitespaceAreIgnored(self):
        self.assertEqual(decide(["", "docs/a.md  ", ""]), (False, False, False))


class OtherEventTests(unittest.TestCase):
    def test_scheduleAndManualRuns_runEverything(self):
        self.assertEqual(decide([], "schedule"), (True, True, True))
        self.assertEqual(decide(["docs/a.md"], "workflow_dispatch"), (True, True, True))

    def test_push_buildsFastAndUiWithoutScriptTests(self):
        self.assertEqual(decide(["docs/a.md"], "push"), (True, True, False))


class CommandLineTests(unittest.TestCase):
    def run_script(self, event, files):
        return subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / "ci-changes.py"), event], input=files,
                              capture_output=True, text=True)

    def test_outputFormatIsNameEqualsValueLines(self):
        result = self.run_script("pull_request", "scripts/refresh-install.sh\n")
        self.assertEqual(result.returncode, 0)
        lines = dict(line.split("=", 1) for line in result.stdout.splitlines())
        self.assertEqual({key: lines[key] for key in ("run_fast", "run_ui", "run_scripts")},
                         {"run_fast": "false", "run_ui": "false", "run_scripts": "true"})
        self.assertIn("only helper scripts", lines["reason"])

    def test_missingEventIsAnError(self):
        self.assertEqual(subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / "ci-changes.py")], input="",
                                        capture_output=True, text=True).returncode, 2)


class ClassificationMatchesTheScriptsInUseTests(unittest.TestCase):
    """A script that the test run or the workflow references must not be classified as "only script tests"."""

    def referenced_scripts(self):
        sources = [ROOT / "app" / "test-all.sh", ROOT / "scripts" / "test-env.sh", ROOT / ".github" / "workflows" / "tests.yml",
                   ROOT / "scripts" / "sync-strings.sh", ROOT / "app" / "project.yml",
                   ROOT / ".github" / "actions" / "prepare-xcode-job" / "action.yml"]
        found = set()
        for source in sources:
            if not source.exists():
                continue
            # Comments only mention scripts (the header of test-env.sh names the scripts that source it); they do not run them.
            code = "\n".join(re.sub(r"\s#\s.*$", "", line) for line in source.read_text().splitlines()
                             if not line.lstrip().startswith("#"))
            for match in re.finditer(r"scripts/((?!tests/)[A-Za-z0-9_.-]+\.(?:py|sh))", code):
                found.add("scripts/" + match.group(1))
        return found

    def test_everyReferencedScriptRunsTheFastOrTheUiJob(self):
        referenced = self.referenced_scripts()
        self.assertIn("scripts/ui-watchdog.py", referenced)
        for path in sorted(referenced):
            with self.subTest(path=path):
                self.assertTrue((ROOT / path).exists(), f"{path} is referenced but does not exist")
                self.assertNotEqual(ci_changes.classify(path), "scripts",
                                    f"{path} is used by the test run: add it to UI_RUN_SCRIPTS or STRING_CHECK_SCRIPTS in scripts/ci-changes.py")

    def test_scriptsOfTheUiRunAreNeverOnlyStringChecks(self):
        for path in ["scripts/test-env.sh", "scripts/ui-hang-sampler.py", "scripts/ui-test-log.py", "scripts/ui-test-shards.py",
                     "scripts/ui-watchdog.py", "scripts/ci-restore-mtimes.py"]:
            self.assertEqual(ci_changes.classify(path), "everything", path)

    def test_listedScriptsExist(self):
        for path in ci_changes.UI_RUN_SCRIPTS + [p for p in ci_changes.STRING_CHECK_SCRIPTS if "*" not in p]:
            self.assertTrue((ROOT / path).exists(), f"{path} is listed in scripts/ci-changes.py but does not exist")


if __name__ == "__main__":
    unittest.main()
