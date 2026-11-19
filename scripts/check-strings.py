#!/usr/bin/env python3
"""Checks the String Catalogs of Tagwerk (plan english-app, Task 1).

Default: structure checks of every catalog in app/
  - placeholders (%@, %lld, %1$@ …) of the English value match the German key
  - every App Shortcuts phrase names the app (${applicationName})
  - the German usage texts in InfoPlist.xcstrings equal those in app/project.yml
--require-english: additionally every key that should be translated has a translated English value
--same A B: exits 1 when two catalogs differ (used by sync-strings.sh --check)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|llu|ld|lu|lf|d|i|u|s|@|f|\.\d+f|%)")


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def catalogs():
    return sorted(p for p in APP.rglob("*.xcstrings") if ".build" not in p.parts and "DerivedData" not in str(p))


def english_values(entry):
    """All English strings of an entry, including plural and device variations."""
    unit = entry.get("localizations", {}).get("en")
    if not unit:
        return []
    values = []

    def walk(node, in_plural=False):
        if isinstance(node, dict):
            if "stringUnit" in node:
                values.append(dict(node["stringUnit"], _plural=in_plural))
            for key, value in node.items():
                walk(value, in_plural or key == "plural")

    walk(unit)
    return values


def placeholders(text):
    """Placeholder types of a text; positional indexes (%1$@) count like their plain form (%@)."""
    return sorted(re.sub(r"\d+\$", "", match) for match in PLACEHOLDER.findall(text))


def placeholders_compatible(value, source, is_plural_form):
    """A plural form such as "one" may leave out the counted number ("Every year")."""
    found, expected = placeholders(value), placeholders(source)
    if found == expected:
        return True
    if not is_plural_form:
        return False
    remaining = list(expected)
    for item in found:
        if item not in remaining:
            return False
        remaining.remove(item)
    return True


def check_structure(path, data, require_english, problems):
    name = path.name
    for key, entry in data.get("strings", {}).items():
        if entry.get("shouldTranslate") is False:
            continue
        units = english_values(entry)
        source = entry.get("localizations", {}).get("de", {}).get("stringUnit", {}).get("value", key)
        if name == "AppShortcuts.xcstrings":
            for unit in units:
                if "${applicationName}" not in unit.get("value", ""):
                    problems.append(f"{path.relative_to(ROOT)}: phrase without app name: {unit.get('value')!r}")
        if name != "InfoPlist.xcstrings":
            for unit in units:
                value = unit.get("value", "")
                if not placeholders_compatible(value, source, unit.get("_plural", False)):
                    problems.append(f"{path.relative_to(ROOT)}: placeholders differ: {key!r} -> {value!r}")
        if require_english and not key.strip() == "":
            translated = [u for u in units if u.get("state") == "translated" and u.get("value", "").strip()]
            if not translated or len(translated) != len(units):
                problems.append(f"{path.relative_to(ROOT)}: no complete English value: {key!r}")
        localizations = entry.get("localizations", {})
        english_plural = "plural" in localizations.get("en", {}).get("variations", {})
        german_plural = "plural" in localizations.get("de", {}).get("variations", {})
        if english_plural and not german_plural:
            # Without German variations the German UI shows "1 Termine".
            problems.append(f"{path.relative_to(ROOT)}: English plural without German plural: {key!r}")


def check_info_plist(problems):
    project = (APP / "project.yml").read_text(encoding="utf-8")
    for path in catalogs():
        if path.name != "InfoPlist.xcstrings":
            continue
        for key, entry in load(path).get("strings", {}).items():
            match = re.search(rf'^\s*{re.escape(key)}:\s*"(.*)"\s*$', project, re.MULTILINE)
            german = entry.get("localizations", {}).get("de", {}).get("stringUnit", {}).get("value")
            if match and german is not None and german != match.group(1):
                problems.append(f"{path.relative_to(ROOT)}: German {key} differs from project.yml")


def same(first, second):
    a, b = load(first), load(second)
    if a == b:
        return 0
    keys_a, keys_b = set(a.get("strings", {})), set(b.get("strings", {}))
    added = sorted(keys_b - keys_a)
    changed = sorted(k for k in keys_a & keys_b if a["strings"][k] != b["strings"][k])
    print(f"{Path(first).relative_to(ROOT)}: {len(added)} new, {len(changed)} changed", file=sys.stderr)
    for key in (added + changed)[:20]:
        print(f"  {key!r}", file=sys.stderr)
    return 1


def main(arguments):
    if arguments[:1] == ["--same"]:
        return same(arguments[1], arguments[2])
    require_english = "--require-english" in arguments
    problems = []
    for path in catalogs():
        check_structure(path, load(path), require_english, problems)
    check_info_plist(problems)
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"{len(problems)} problem(s) in the String Catalogs", file=sys.stderr)
        return 1
    print(f"    {len(catalogs())} String Catalogs checked")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
