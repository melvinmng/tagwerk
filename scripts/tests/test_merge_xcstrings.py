"""Tests of scripts/merge-xcstrings.py: the three-way logic and an end-to-end merge with the driver registered in git.

Run: /usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
"""
import copy
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import catalog_format  # noqa: E402
from catalog_format import Style  # noqa: E402

_spec = importlib.util.spec_from_file_location("merge_xcstrings", SCRIPTS / "merge-xcstrings.py")
merge_xcstrings = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(merge_xcstrings)

PYTHON = "/usr/bin/python3" if os.path.exists("/usr/bin/python3") else sys.executable


def entry(german, english, state="translated"):
    """A catalog entry with a German source string and an English translation."""
    return {"localizations": {"de": {"stringUnit": {"state": "new", "value": german}},
                              "en": {"stringUnit": {"state": state, "value": english}}}}


def catalog(**strings):
    return {"sourceLanguage": "de", "strings": dict(strings), "version": "1.0"}


def merge(base, ours, theirs):
    merged, conflicts = merge_xcstrings.merge_documents(base, ours, theirs)
    return merged, [merge_xcstrings._describe(path) for path, _, _ in conflicts]


class ThreeWayLogicTests(unittest.TestCase):
    def setUp(self):
        self.base = catalog(A=entry("A", "a"), B=entry("B", "b"))

    def test_different_keys_added_on_both_sides_are_both_kept(self):
        ours, theirs = copy.deepcopy(self.base), copy.deepcopy(self.base)
        ours["strings"]["C"] = entry("C", "c")
        theirs["strings"]["D"] = entry("D", "d")
        merged, conflicts = merge(self.base, ours, theirs)
        self.assertEqual(conflicts, [])
        self.assertEqual(set(merged["strings"]), {"A", "B", "C", "D"})
        self.assertEqual(merged["sourceLanguage"], "de")
        self.assertEqual(merged["version"], "1.0")

    def test_key_added_on_one_side_only_is_taken(self):
        theirs = copy.deepcopy(self.base)
        theirs["strings"]["C"] = entry("C", "c")
        merged, conflicts = merge(self.base, self.base, theirs)
        self.assertEqual((merged, conflicts), (theirs, []))

    def test_removal_on_one_side_with_the_other_unchanged_removes_the_key(self):
        theirs = copy.deepcopy(self.base)
        del theirs["strings"]["B"]
        for ours, other in ((self.base, theirs), (theirs, self.base)):
            merged, conflicts = merge(self.base, ours, other)
            self.assertEqual(conflicts, [])
            self.assertEqual(set(merged["strings"]), {"A"})

    def test_removal_against_a_change_of_the_same_key_is_a_conflict(self):
        ours, theirs = copy.deepcopy(self.base), copy.deepcopy(self.base)
        del ours["strings"]["B"]
        theirs["strings"]["B"]["localizations"]["en"]["stringUnit"]["value"] = "bee"
        _, conflicts = merge(self.base, ours, theirs)
        self.assertEqual(conflicts, ['"strings" / "B"'])

    def test_same_key_added_with_the_same_value_on_both_sides_is_taken_once(self):
        ours, theirs = copy.deepcopy(self.base), copy.deepcopy(self.base)
        ours["strings"]["C"] = theirs["strings"]["C"] = entry("C", "c")
        merged, conflicts = merge(self.base, ours, theirs)
        self.assertEqual(conflicts, [])
        self.assertEqual(merged["strings"]["C"], entry("C", "c"))

    def test_same_key_added_with_different_values_is_a_conflict_on_that_leaf(self):
        ours, theirs = copy.deepcopy(self.base), copy.deepcopy(self.base)
        ours["strings"]["C"] = entry("C", "see")
        theirs["strings"]["C"] = entry("C", "sea")
        _, conflicts = merge(self.base, ours, theirs)
        self.assertEqual(conflicts, ['"strings" / "C" / "localizations" / "en" / "stringUnit" / "value"'])

    def test_same_key_changed_in_different_leaves_merges(self):
        ours, theirs = copy.deepcopy(self.base), copy.deepcopy(self.base)
        ours["strings"]["A"]["localizations"]["en"]["stringUnit"]["value"] = "ay"
        theirs["strings"]["A"]["localizations"]["fr"] = {"stringUnit": {"state": "translated", "value": "a"}}
        merged, conflicts = merge(self.base, ours, theirs)
        self.assertEqual(conflicts, [])
        localizations = merged["strings"]["A"]["localizations"]
        self.assertEqual(localizations["en"]["stringUnit"]["value"], "ay")
        self.assertIn("fr", localizations)

    def test_same_leaf_changed_differently_is_a_conflict(self):
        ours, theirs = copy.deepcopy(self.base), copy.deepcopy(self.base)
        ours["strings"]["A"]["localizations"]["en"]["stringUnit"]["value"] = "ay"
        theirs["strings"]["A"]["localizations"]["en"]["stringUnit"]["value"] = "eh"
        _, conflicts = merge(self.base, ours, theirs)
        self.assertEqual(conflicts, ['"strings" / "A" / "localizations" / "en" / "stringUnit" / "value"'])

    def test_same_leaf_changed_identically_is_not_a_conflict(self):
        ours, theirs = copy.deepcopy(self.base), copy.deepcopy(self.base)
        for side in (ours, theirs):
            side["strings"]["A"]["localizations"]["en"]["stringUnit"]["state"] = "needs_review"
        merged, conflicts = merge(self.base, ours, theirs)
        self.assertEqual((merged, conflicts), (ours, []))

    def test_a_boolean_is_not_equal_to_a_number(self):
        base = {"flag": False}
        _, conflicts = merge(base, {"flag": 0}, {"flag": 1})
        self.assertEqual(conflicts, ['"flag"'])
        merged, conflicts = merge(base, {"flag": False}, {"flag": 0})
        self.assertEqual((merged, conflicts), ({"flag": 0}, []))

    def test_flat_dictionary_keeps_the_keys_of_ours_first_and_appends_the_new_keys_of_theirs(self):
        base = {"z": "1", "a": "2"}
        ours = {"z": "1", "a": "2", "m": "3"}
        theirs = {"z": "1", "a": "2", "b": "4"}
        merged, conflicts = merge(base, ours, theirs)
        self.assertEqual(conflicts, [])
        self.assertEqual(list(merged), ["z", "a", "m", "b"])


class DriverFilesTests(unittest.TestCase):
    """The driver as git calls it: three files in, result in OURS, exit code."""

    def setUp(self):
        self.directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory, True)

    def write(self, name, text):
        path = self.directory / name
        path.write_bytes(text.encode("utf-8"))
        return str(path)

    def run_driver(self, base, ours, theirs, path="Localizable.xcstrings"):
        paths = [self.write("base", base), self.write("ours", ours), self.write("theirs", theirs)]
        result = subprocess.run([PYTHON, str(SCRIPTS / "merge-xcstrings.py"), *paths, path],
                                capture_output=True, text=True)
        return result, (self.directory / "ours").read_bytes().decode("utf-8")

    def test_merge_that_changes_nothing_keeps_the_file_byte_for_byte_in_both_styles(self):
        base = catalog(A=entry("A", "a"), Empty={})
        for style in (Style(": ", True), Style(" : ", False)):
            text = catalog_format.serialize(base, style)
            theirs = copy.deepcopy(base)
            theirs["strings"]["B"] = entry("B", "b")
            # Theirs is unchanged against the base: nothing to take over.
            result, merged_text = self.run_driver(text, text, text)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(merged_text, text)
            # Ours has an extra key, theirs is the base: ours stays as it is.
            ours_text = catalog_format.serialize(theirs, style)
            result, merged_text = self.run_driver(text, ours_text, text)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(merged_text, ours_text)

    def test_merged_catalog_is_written_in_the_style_of_ours(self):
        base = catalog(A=entry("A", "a"))
        ours, theirs = copy.deepcopy(base), copy.deepcopy(base)
        ours["strings"]["Zeta"] = entry("Zeta", "zeta")
        theirs["strings"]["Alpha"] = entry("Alpha", "alpha")
        style = Style(" : ", False)
        result, merged_text = self.run_driver(catalog_format.serialize(base, style), catalog_format.serialize(ours, style),
                                              catalog_format.serialize(theirs, Style(": ", True)))
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = copy.deepcopy(ours)
        expected["strings"]["Alpha"] = entry("Alpha", "alpha")
        self.assertEqual(merged_text, catalog_format.serialize(expected, style))
        self.assertTrue(catalog_format.is_canonical(merged_text))

    def test_catalog_is_sorted_whatever_the_file_name_or_missing_path_argument(self):
        """Regression: the driver command without %P left the temporary file name as the path, and the catalog was merged
        in insertion order (keys of theirs appended at the end) instead of sorted."""
        base = catalog(M=entry("M", "m"))
        ours, theirs = copy.deepcopy(base), copy.deepcopy(base)
        ours["strings"]["Z"] = entry("Z", "z")
        theirs["strings"]["A"] = entry("A", "a")
        style = Style(" : ", False)
        texts = [catalog_format.serialize(side, style) for side in (base, ours, theirs)]
        for path in (None, ".merge_file_a1b2c3", "ours", "scripts/translations/en.json"):
            with self.subTest(path=path):
                arguments = [self.write("base", texts[0]), self.write("ours", texts[1]), self.write("theirs", texts[2])]
                if path:
                    arguments.append(path)
                result = subprocess.run([PYTHON, str(SCRIPTS / "merge-xcstrings.py"), *arguments], capture_output=True, text=True)
                merged_text = (self.directory / "ours").read_bytes().decode("utf-8")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(catalog_format.is_canonical(merged_text), merged_text)
                self.assertEqual(list(json.loads(merged_text)["strings"]), ["A", "M", "Z"])

    def test_explicit_format_overrides_the_detection(self):
        base = {"strings": {"m": "1"}, "sourceLanguage": "de"}
        ours = {"strings": {"m": "1", "z": "2"}, "sourceLanguage": "de"}
        theirs = {"strings": {"m": "1", "a": "3"}, "sourceLanguage": "de"}
        paths = [self.write(name, catalog_format.serialize(side, Style(": ", True), sort_keys=False))
                 for name, side in (("base", base), ("ours", ours), ("theirs", theirs))]
        result = subprocess.run([PYTHON, str(SCRIPTS / "merge-xcstrings.py"), "--format", "ordered-json", *paths],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        merged = json.loads((self.directory / "ours").read_text(encoding="utf-8"))
        self.assertEqual(list(merged["strings"]), ["m", "z", "a"])

    def test_en_json_keeps_its_insertion_order_and_final_line_break(self):
        base = {"Zebra": "zebra", "Apfel": "apple"}
        ours = {**base, "Müll": "waste"}
        theirs = {**base, "Käse": "cheese"}
        style = Style(": ", True)
        result, merged_text = self.run_driver(*(catalog_format.serialize(side, style, sort_keys=False)
                                                for side in (base, ours, theirs)), path="scripts/translations/en.json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(merged_text, catalog_format.serialize({**ours, "Käse": "cheese"}, style, sort_keys=False))
        self.assertEqual(list(json.loads(merged_text)), ["Zebra", "Apfel", "Müll", "Käse"])

    def test_conflict_reports_the_path_writes_markers_and_exits_with_one(self):
        base = catalog(A=entry("A", "a"))
        ours, theirs = copy.deepcopy(base), copy.deepcopy(base)
        ours["strings"]["A"]["localizations"]["en"]["stringUnit"]["value"] = "ay"
        theirs["strings"]["A"]["localizations"]["en"]["stringUnit"]["value"] = "eh"
        style = Style(": ", True)
        result, merged_text = self.run_driver(*(catalog_format.serialize(side, style) for side in (base, ours, theirs)))
        self.assertEqual(result.returncode, 1)
        self.assertIn('"strings" / "A" / "localizations" / "en" / "stringUnit" / "value"', result.stderr)
        self.assertIn("<<<<<<< ours", merged_text)
        self.assertIn(">>>>>>> theirs", merged_text)

    def test_conflict_markers_surround_only_the_conflicting_values_and_clean_keys_are_merged(self):
        base = catalog(A=entry("A", "a"))
        ours, theirs = copy.deepcopy(base), copy.deepcopy(base)
        ours["strings"]["Conflict"] = entry("Conflict", "ours value")
        theirs["strings"]["Conflict"] = entry("Conflict", "theirs value")
        ours["strings"]["OnlyOurs"] = entry("OnlyOurs", "x")
        theirs["strings"]["OnlyTheirs"] = entry("OnlyTheirs", "y")
        style = Style(": ", True)
        result, merged_text = self.run_driver(*(catalog_format.serialize(side, style) for side in (base, ours, theirs)))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(merged_text.count("<<<<<<<"), 1)
        self.assertEqual(merged_text.count(">>>>>>>"), 1)
        before, rest = merged_text.split("<<<<<<< ours\n")
        conflict_block, after = rest.split(">>>>>>> theirs\n")
        self.assertIn("ours value", conflict_block)
        self.assertIn("theirs value", conflict_block)
        for key in ("OnlyOurs", "OnlyTheirs"):
            self.assertIn(f'"{key}"', before + after)
            self.assertNotIn(f'"{key}"', conflict_block)

    def test_en_json_conflict_has_markers_around_the_conflicting_entry_only(self):
        base = {"Alt": "old"}
        ours = {**base, "Neu": "ours", "Nur ours": "o"}
        theirs = {**base, "Neu": "theirs", "Nur theirs": "t"}
        style = Style(": ", True)
        result, merged_text = self.run_driver(*(catalog_format.serialize(side, style, sort_keys=False)
                                                for side in (base, ours, theirs)), path="scripts/translations/en.json")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(merged_text.count("<<<<<<<"), 1)
        self.assertIn('"Nur ours"', merged_text)
        self.assertIn('"Nur theirs"', merged_text)

    def test_invalid_json_falls_back_to_the_text_merge(self):
        result, merged_text = self.run_driver("a\nb\n", "a\nb\nc\n", "a\nb\nd\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn("<<<<<<< ours", merged_text)


_REPOSITORY_VARIABLES = ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
                         "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_PREFIX")


def isolated_environment():
    """Environment for git in the temporary repository: never the repository that runs the tests (git hooks and
    `rebase --exec` export GIT_DIR and friends) and never a global or system configuration."""
    environment = {name: value for name, value in os.environ.items() if name not in _REPOSITORY_VARIABLES}
    environment.update(GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null", GIT_CONFIG_NOSYSTEM="1",
                       GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.com",
                       GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.com")
    return environment


def git(directory, *arguments, check=True):
    return subprocess.run(["git", *arguments], cwd=directory, env=isolated_environment(), check=check,
                          capture_output=True, text=True)


class EndToEndTests(unittest.TestCase):
    """Two branches add different keys to a small catalog; git merges them with the registered driver."""

    def setUp(self):
        self.directory = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.directory, True)
        (self.directory / "scripts" / "translations").mkdir(parents=True)
        for name in ("merge-xcstrings.py", "catalog_format.py", "setup-git-merge-drivers.sh"):
            shutil.copy(SCRIPTS / name, self.directory / "scripts" / name)
        shutil.copy(ROOT / ".gitattributes", self.directory / ".gitattributes")
        git(self.directory, "init", "--quiet", "--initial-branch=main")
        self.catalog_path = self.directory / "app" / "Localizable.xcstrings"
        self.catalog_path.parent.mkdir()
        self.translations_path = self.directory / "scripts" / "translations" / "en.json"
        self.style = Style(" : ", False)
        self.save(catalog(Anfang=entry("Anfang", "Start")), {"Anfang": "Start"})
        self.commit("initial")

    def save(self, content, translations):
        self.catalog_path.write_bytes(catalog_format.serialize(content, self.style).encode("utf-8"))
        self.translations_path.write_bytes(catalog_format.serialize(translations, Style(": ", True), sort_keys=False).encode("utf-8"))

    def commit(self, message):
        git(self.directory, "add", "-A")
        git(self.directory, "commit", "--quiet", "-m", message)

    def read(self):
        return (json.loads(self.catalog_path.read_text(encoding="utf-8")),
                json.loads(self.translations_path.read_text(encoding="utf-8")))

    def register_drivers(self):
        result = subprocess.run(["zsh", "scripts/setup-git-merge-drivers.sh"], cwd=self.directory, capture_output=True, text=True,
                                env=isolated_environment())
        self.assertEqual(result.returncode, 0, result.stderr)

    def branch_with_new_key(self, branch, key, english):
        git(self.directory, "checkout", "--quiet", "-b", branch, "main")
        content, translations = self.read()
        content["strings"][key] = entry(key, english)
        translations[key] = english
        self.save(content, translations)
        self.commit(f"add {key}")

    def test_branches_that_add_different_keys_merge_cleanly_with_the_driver(self):
        self.register_drivers()
        self.register_drivers()  # idempotent: same configuration, no error
        self.branch_with_new_key("feature-a", "Zebra", "zebra")
        self.branch_with_new_key("feature-b", "Apfel", "apple")
        merge = git(self.directory, "merge", "--no-edit", "feature-a", check=False)
        self.assertEqual(merge.returncode, 0, merge.stdout + merge.stderr)
        content, translations = self.read()
        self.assertEqual(set(content["strings"]), {"Anfang", "Zebra", "Apfel"})
        self.assertEqual(list(translations), ["Anfang", "Apfel", "Zebra"])
        self.assertTrue(catalog_format.is_canonical(self.catalog_path.read_text(encoding="utf-8")))
        self.assertEqual(git(self.directory, "status", "--porcelain").stdout, "")

    def test_driver_command_without_the_path_argument_writes_the_canonical_format(self):
        """Regression: `git -c merge.xcstrings.driver="python3 scripts/merge-xcstrings.py %O %A %B" merge …` (no %P) wrote the
        keys of the other side at the end of the catalog, and check-strings.py rejected the result."""
        # The key of theirs sorts before the key of ours: appending it instead of sorting is visible.
        self.branch_with_new_key("feature-a", "Apfel", "apple")
        self.branch_with_new_key("feature-b", "Zebra", "zebra")
        driver = f"{PYTHON} scripts/merge-xcstrings.py %O %A %B"
        translations_driver = f"{PYTHON} scripts/merge-xcstrings.py --format ordered-json %O %A %B"
        merge = git(self.directory, "-c", f"merge.xcstrings.driver={driver}",
                    "-c", f"merge.translationsjson.driver={translations_driver}", "merge", "--no-edit", "feature-a", check=False)
        self.assertEqual(merge.returncode, 0, merge.stdout + merge.stderr)
        text = self.catalog_path.read_text(encoding="utf-8")
        self.assertTrue(catalog_format.is_canonical(text), text)
        self.assertEqual(list(json.loads(text)["strings"]), ["Anfang", "Apfel", "Zebra"])

    def make_old_branch_and_advanced_main(self):
        """A branch cut before the driver existed (no .gitattributes) and a main that moved on with a new key."""
        self.register_drivers()
        git(self.directory, "checkout", "--quiet", "-b", "old-feature", "main")
        git(self.directory, "rm", "--quiet", ".gitattributes")
        content, translations = self.read()
        content["strings"]["Apfel"] = entry("Apfel", "apple")
        translations["Apfel"] = "apple"
        self.save(content, translations)
        self.commit("old branch adds a key")
        git(self.directory, "checkout", "--quiet", "main")
        content, translations = self.read()
        content["strings"]["Zebra"] = entry("Zebra", "zebra")
        translations["Zebra"] = "zebra"
        self.save(content, translations)
        self.commit("main adds a key")
        git(self.directory, "checkout", "--quiet", "old-feature")

    def test_merging_main_into_a_branch_without_gitattributes_still_conflicts_once(self):
        """Git reads .gitattributes from the checked-out side, so a branch cut before the driver existed text-merges once."""
        self.make_old_branch_and_advanced_main()
        merge = git(self.directory, "merge", "--no-edit", "main", check=False)
        self.assertNotEqual(merge.returncode, 0)

    def test_rebasing_a_branch_without_gitattributes_onto_main_uses_the_driver(self):
        self.make_old_branch_and_advanced_main()
        rebase = git(self.directory, "rebase", "main", check=False)
        self.assertEqual(rebase.returncode, 0, rebase.stdout + rebase.stderr)
        content, _ = self.read()
        self.assertEqual(set(content["strings"]), {"Anfang", "Apfel", "Zebra"})

    def test_the_same_merge_conflicts_without_the_driver(self):
        self.branch_with_new_key("feature-a", "Zebra", "zebra")
        self.branch_with_new_key("feature-b", "Apfel", "apple")
        merge = git(self.directory, "merge", "--no-edit", "feature-a", check=False)
        self.assertNotEqual(merge.returncode, 0)

    def test_a_real_conflict_stays_a_conflict_with_the_driver(self):
        self.register_drivers()
        self.branch_with_new_key("feature-a", "Zebra", "zebra")
        self.branch_with_new_key("feature-b", "Zebra", "zebu")
        merge = git(self.directory, "merge", "--no-edit", "feature-a", check=False)
        self.assertNotEqual(merge.returncode, 0)
        self.assertIn("<<<<<<<", self.catalog_path.read_text(encoding="utf-8"))
        self.assertIn("conflict", (merge.stdout + merge.stderr).lower())


if __name__ == "__main__":
    unittest.main()
