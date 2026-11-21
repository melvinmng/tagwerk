"""Tests of scripts/catalog_format.py against the String Catalogs of the repository.

Run: /usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v
"""
import contextlib
import copy
import importlib.util
import difflib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import catalog_format  # noqa: E402
from catalog_format import Style  # noqa: E402

APP = ROOT / "app"
COLON_CATALOG = APP / "Packages/TagwerkCore/Sources/TagwerkCore/Resources/Localizable.xcstrings"
SPACED_CATALOG = APP / "Packages/RemindersKit/Sources/RemindersKit/Resources/Localizable.xcstrings"


def all_catalogs():
    return sorted(path for path in APP.rglob("*.xcstrings") if ".build" not in path.parts and "DerivedData" not in str(path))


def xcode_style(data):
    """Imitates what xcstringstool writes: " : " separator, empty objects on two lines, no final line break, other key order."""
    text = json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : "))
    return text.replace("{}", "{\n\n}")


def changed_lines(before, after):
    """(removed, added) lines of a diff without context."""
    removed, added = [], []
    for line in difflib.unified_diff(before.splitlines(), after.splitlines(), lineterm="", n=0):
        if line.startswith(("---", "+++", "@@")):
            continue
        (removed if line.startswith("-") else added).append(line[1:])
    return removed, added


def reversed_keys(node):
    """Same content with the keys of every object in reverse order (the content compares equal, the text does not)."""
    if isinstance(node, dict):
        return {key: reversed_keys(node[key]) for key in reversed(list(node))}
    if isinstance(node, list):
        return [reversed_keys(item) for item in node]
    return node


class CatalogsInRepositoryTests(unittest.TestCase):
    def test_every_catalog_round_trips_byte_for_byte(self):
        catalogs = all_catalogs()
        self.assertGreaterEqual(len(catalogs), 11)
        for path in catalogs:
            text = path.read_text(encoding="utf-8")
            with self.subTest(catalog=str(path.relative_to(ROOT))):
                self.assertEqual(catalog_format.serialize(json.loads(text), catalog_format.detect_style(text)), text)
                self.assertTrue(catalog_format.is_canonical(text))


class DetectStyleTests(unittest.TestCase):
    def test_four_combinations(self):
        for separator in (": ", " : "):
            for trailing_newline in (True, False):
                data = {"sourceLanguage": "de", "strings": {"a": {}}, "version": "1.0"}
                text = catalog_format.serialize(data, Style(separator, trailing_newline))
                with self.subTest(separator=separator, trailing_newline=trailing_newline):
                    self.assertEqual(catalog_format.detect_style(text), Style(separator, trailing_newline))

    def test_separator_inside_a_text_does_not_count(self):
        text = '{\n  "sourceLanguage": "de",\n  "strings": {\n    "a : b": {}\n  },\n  "version": "1.0"\n}\n'
        self.assertEqual(catalog_format.detect_style(text).separator, ": ")


class AdoptTests(unittest.TestCase):
    def load(self, path):
        text = path.read_text(encoding="utf-8")
        return text, json.loads(text)

    def new_key_position(self, data):
        """A key that sorts into the middle of the strings, so no comma of a neighbouring line changes."""
        keys = sorted(data["strings"])
        key = keys[len(keys) // 2] + " neu"
        self.assertLess(sorted(keys + [key]).index(key), len(keys))
        return key

    def test_unchanged_tree_gives_nothing_to_write(self):
        for path in (COLON_CATALOG, SPACED_CATALOG):
            text, data = self.load(path)
            synced = xcode_style(reversed_keys(data))
            with self.subTest(catalog=path.name, style=catalog_format.detect_style(text)):
                self.assertIsNone(catalog_format.adopt(text, synced))

    def test_one_new_key_changes_exactly_one_line(self):
        for path in (COLON_CATALOG, SPACED_CATALOG):
            text, data = self.load(path)
            key = self.new_key_position(data)
            synced_data = copy.deepcopy(data)
            synced_data["strings"][key] = {}
            result = catalog_format.adopt(text, xcode_style(reversed_keys(synced_data)))
            removed, added = changed_lines(text, result)
            with self.subTest(catalog=path.name):
                self.assertEqual(removed, [])
                self.assertEqual(added, [f"    {json.dumps(key, ensure_ascii=False)}{catalog_format.detect_style(text).separator}{{}},"])

    def test_changed_english_value_changes_one_line_pair(self):
        text, data = self.load(COLON_CATALOG)
        key, entry = next((key, entry) for key, entry in data["strings"].items()
                          if "stringUnit" in entry.get("localizations", {}).get("en", {}))
        synced_data = copy.deepcopy(data)
        synced_data["strings"][key]["localizations"]["en"]["stringUnit"]["value"] += " changed"
        result = catalog_format.adopt(text, xcode_style(synced_data))
        removed, added = changed_lines(text, result)
        self.assertEqual((len(removed), len(added)), (1, 1))
        self.assertTrue(added[0].rstrip().endswith(' changed"') or added[0].rstrip().endswith(' changed",'))

    def test_stale_marker_adds_only_its_own_line(self):
        for path in (COLON_CATALOG, SPACED_CATALOG):
            text, data = self.load(path)
            style = catalog_format.detect_style(text)
            key = next(key for key, entry in data["strings"].items()
                       if "localizations" in entry and "extractionState" not in entry and key != "")
            synced_data = copy.deepcopy(data)
            synced_data["strings"][key]["extractionState"] = "stale"
            result = catalog_format.adopt(text, xcode_style(synced_data))
            removed, added = changed_lines(text, result)
            with self.subTest(catalog=path.name):
                self.assertEqual(removed, [])
                self.assertEqual(added, [f'      "extractionState"{style.separator}"stale",'])

    def test_removed_key_removes_only_its_lines(self):
        for path in (COLON_CATALOG, SPACED_CATALOG):
            text, data = self.load(path)
            keys = sorted(data["strings"])
            key = keys[len(keys) // 2]
            synced_data = copy.deepcopy(data)
            entry = synced_data["strings"].pop(key)
            result = catalog_format.adopt(text, xcode_style(synced_data))
            removed, added = changed_lines(text, result)
            with self.subTest(catalog=path.name):
                self.assertEqual(added, [])
                # The lines of the entry (key line included) are the only ones that disappear.
                self.assertEqual(len(removed), len(json.dumps(entry, ensure_ascii=False, indent=2).split("\n")))

    def test_special_characters_stay_as_in_the_original(self):
        data = {"sourceLanguage": "de", "strings": {
            "Größe: „ändern“ / %1$@": {"localizations": {"en": {"stringUnit": {"state": "translated", "value": 'Line\n"quoted" a/b'}}}},
        }, "version": "1.0"}
        for style in (Style(": ", True), Style(" : ", False)):
            text = catalog_format.serialize(data, style)
            with self.subTest(style=style):
                self.assertIn("Größe: „ändern“ / %1$@", text)
                self.assertIn(r'"Line\n\"quoted\" a/b"', text)
                self.assertNotIn("\\/", text)
                self.assertNotIn("\\u", text)
                self.assertTrue(catalog_format.is_canonical(text))
                self.assertEqual(json.loads(text), data)


class CommandLineTests(unittest.TestCase):
    def test_adopt_writes_only_on_change_and_reports_counts(self):
        text = COLON_CATALOG.read_text(encoding="utf-8")
        data = json.loads(text)
        with tempfile.TemporaryDirectory() as folder:
            catalog = Path(folder) / "Localizable.xcstrings"
            copy_path = Path(folder) / "synced.xcstrings"
            catalog.write_text(text, encoding="utf-8")
            copy_path.write_text(xcode_style(data), encoding="utf-8")
            self.assertEqual(catalog_format.main(["adopt", str(catalog), str(copy_path)]), 0)
            self.assertEqual(catalog.read_text(encoding="utf-8"), text)
            data["strings"]["zz new key"] = {}
            copy_path.write_text(xcode_style(data), encoding="utf-8")
            with contextlib.redirect_stdout(io.StringIO()) as report:
                self.assertEqual(catalog_format.main(["adopt", str(catalog), str(copy_path)]), 0)
            self.assertIn("1 new, 0 changed, 0 removed", report.getvalue())
            self.assertIn('"zz new key": {}', catalog.read_text(encoding="utf-8"))

    def test_check_reports_the_first_differing_line(self):
        text = COLON_CATALOG.read_text(encoding="utf-8")
        data = json.loads(text)
        with tempfile.TemporaryDirectory() as folder:
            catalog = Path(folder) / "Localizable.xcstrings"
            catalog.write_text(text, encoding="utf-8")
            self.assertEqual(catalog_format.main(["check", str(catalog)]), 0)
            # A key added by hand at the end instead of its sorted position.
            lines = text.split("\n")
            index = next(number for number, line in enumerate(lines) if line.startswith('  "strings"'))
            lines.insert(index + 1, '    "zz handwritten": {},')
            catalog.write_text("\n".join(lines), encoding="utf-8")
            self.assertEqual(catalog_format.first_difference("\n".join(lines)), index + 2)
            with contextlib.redirect_stderr(io.StringIO()) as messages:
                self.assertEqual(catalog_format.main(["check", str(catalog)]), 1)
            self.assertIn(f"first difference at line {index + 2}", messages.getvalue())


def load_apply_translations():
    spec = importlib.util.spec_from_file_location("apply_translations", ROOT / "scripts" / "apply-translations.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ApplyTranslationsTests(unittest.TestCase):
    def apply(self, translations):
        module = load_apply_translations()
        with tempfile.TemporaryDirectory() as folder:
            catalog = Path(folder) / "Localizable.xcstrings"
            before = COLON_CATALOG.read_text(encoding="utf-8")
            catalog.write_text(before, encoding="utf-8")
            data, *_ = module.apply_to_catalog(catalog, translations, "en", set())
            module.write_catalog(catalog, data)
            return before, catalog.read_text(encoding="utf-8")

    def translated_entry(self):
        data = json.loads(COLON_CATALOG.read_text(encoding="utf-8"))
        return next((key, entry["localizations"]["en"]["stringUnit"]["value"]) for key, entry in data["strings"].items()
                    if entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("state") == "translated"
                    and "shouldTranslate" not in entry)

    def test_unchanged_translation_leaves_the_file_byte_for_byte(self):
        key, value = self.translated_entry()
        before, after = self.apply({key: value})
        self.assertEqual(before, after)

    def test_changed_translation_changes_one_line_pair(self):
        key, value = self.translated_entry()
        before, after = self.apply({key: value + " changed"})
        removed, added = changed_lines(before, after)
        self.assertEqual((len(removed), len(added)), (1, 1))
        self.assertIn(" changed", added[0])


if __name__ == "__main__":
    unittest.main()
