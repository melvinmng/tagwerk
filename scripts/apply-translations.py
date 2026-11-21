#!/usr/bin/env python3
"""Writes translations from a JSON file into the Localizable String Catalogs of Tagwerk.

Usage: scripts/apply-translations.py [--language en] [--translations FILE] [--dry-run]

The translations file maps the German key to one of
  "text"                                  a plain value
  {"one": "text", "other": "text"}        plural variations (written as variations.plural)
  {"shouldTranslate": false}              developer or diagnostic text that stays German

Only the target language entry of a key is replaced; German values and variations, comments and
extraction states are kept. Keys that are in a catalog but not in the file are reported, and so are
keys in the file that no catalog contains. A catalog is written in the format it already has (separator,
final line break; see scripts/catalog_format.py) and only when its content changes, so only the lines of
changed entries differ. Run scripts/check-strings.py --require-english afterwards to verify the result.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import catalog_format  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
DEFAULT_TRANSLATIONS = ROOT / "scripts" / "translations" / "en.json"
PLURAL_CATEGORIES = ("zero", "one", "two", "few", "many", "other")


def string_unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value):
    """Builds the localization node for a plain or plural value."""
    if isinstance(value, str):
        return string_unit(value)
    plural = {}
    for category in PLURAL_CATEGORIES:
        if category in value:
            plural[category] = string_unit(value[category])
    if "other" not in plural:
        raise ValueError(f"plural value without 'other': {value!r}")
    return {"variations": {"plural": plural}}


def localizable_catalogs():
    return sorted(
        path
        for path in APP.rglob("Localizable.xcstrings")
        if ".build" not in path.parts and "DerivedData" not in str(path)
    )


def apply_to_catalog(path, translations, language, seen):
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    written = excluded = 0
    missing = []
    for key, entry in data.get("strings", {}).items():
        if key == "":
            continue
        value = translations.get(key)
        if value is None:
            missing.append(key)
            continue
        seen.add(key)
        if isinstance(value, dict) and value.get("shouldTranslate") is False:
            entry["shouldTranslate"] = False
            entry.get("localizations", {}).pop(language, None)
            if not entry.get("localizations"):
                entry.pop("localizations", None)
            excluded += 1
            continue
        entry.pop("shouldTranslate", None)
        entry.setdefault("localizations", {})[language] = localization(value)
        written += 1
    return data, written, excluded, missing


def write_catalog(path, data):
    """Writes the catalog in its own format; the file stays untouched when the content did not change."""
    original_text = Path(path).read_text(encoding="utf-8")
    result = catalog_format.adopt(original_text, json.dumps(data))
    if result is not None:
        Path(path).write_text(result, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--language", default="en")
    parser.add_argument("--translations", type=Path, default=DEFAULT_TRANSLATIONS)
    parser.add_argument("--dry-run", action="store_true", help="report only, do not write the catalogs")
    arguments = parser.parse_args()

    with open(arguments.translations, encoding="utf-8") as handle:
        translations = json.load(handle)

    seen = set()
    total_missing = 0
    for path in localizable_catalogs():
        data, written, excluded, missing = apply_to_catalog(path, translations, arguments.language, seen)
        relative = path.relative_to(ROOT)
        print(f"{relative}: {written} translated, {excluded} marked shouldTranslate false, {len(missing)} without translation")
        for key in missing:
            print(f"    missing: {key!r}", file=sys.stderr)
        total_missing += len(missing)
        if not arguments.dry_run:
            write_catalog(path, data)

    unused = sorted(set(translations) - seen)
    for key in unused:
        print(f"unused translation key: {key!r}", file=sys.stderr)
    return 1 if total_missing else 0


if __name__ == "__main__":
    sys.exit(main())
