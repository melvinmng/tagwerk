#!/usr/bin/env python3
"""Checks the String Catalogs of Tagwerk (plan english-app, Task 1).

Default: structure checks of every catalog in app/
  - placeholders (%@, %lld, %1$@ …) of the English value match the German key
  - every App Shortcuts phrase names the app (${applicationName})
  - the phrases in TagwerkIntents.swift and AppShortcuts.xcstrings match in both directions, and every phrase
    shown on the page "Siri & Kurzbefehle" (`phrase:` and `alternative:` in SiriPhraseCatalog.swift) is a real phrase
  - the German usage texts in InfoPlist.xcstrings equal those in app/project.yml
  - no source key of a catalog contains the English word "Project"/"Projects" (German UI text says "Projekt"/"Projekte")
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


SHORTCUT_PHRASES_SOURCE = APP / "Tagwerk" / "Intents" / "TagwerkIntents.swift"
SHORTCUT_SETTINGS_SOURCE = APP / "Tagwerk" / "Intents" / "SiriPhraseCatalog.swift"


def source_phrases(text):
    """Phrases of the AppShortcut(...) definitions, written like the catalog keys: \\(.applicationName) -> ${applicationName}."""
    phrases = []
    for block in re.findall(r"phrases:\s*\[(.*?)\]", text, re.DOTALL):
        for literal in re.findall(r'"((?:[^"\\]|\\.)*)"', block):
            phrase = literal.replace("\\(.applicationName)", "${applicationName}")
            phrase = re.sub(r"\\\(\\\.\$(\w+)\)", r"${\1}", phrase)
            phrases.append(phrase)
    return phrases


def check_shortcut_phrases(problems):
    """The code is the source of truth: the hand-maintained catalog must not miss or keep a phrase, and the settings list must not name an unknown one."""
    catalog = ROOT / "app" / "Tagwerk" / "AppShortcuts.xcstrings"
    if not SHORTCUT_PHRASES_SOURCE.exists() or not catalog.exists():
        return
    phrases = source_phrases(SHORTCUT_PHRASES_SOURCE.read_text(encoding="utf-8"))
    keys = set(load(catalog).get("strings", {}))
    for phrase in phrases:
        if phrase not in keys:
            problems.append(f"{catalog.relative_to(ROOT)}: phrase missing in the catalog: {phrase!r}")
    for key in sorted(keys - set(phrases)):
        problems.append(f"{catalog.relative_to(ROOT)}: key without phrase in {SHORTCUT_PHRASES_SOURCE.name}: {key!r}")
    if len(phrases) != len(set(phrases)):
        problems.append(f"{SHORTCUT_PHRASES_SOURCE.relative_to(ROOT)}: duplicate App Shortcuts phrase")
    if SHORTCUT_SETTINGS_SOURCE.exists():
        patterns = []
        for phrase in phrases:
            pattern = re.escape(phrase).replace(re.escape("${applicationName}"), "Tagwerk")
            patterns.append(re.compile("^" + re.sub(r"\\\$\\\{\w+\\\}", ".+", pattern) + "$"))
        # Both `phrase:` and `alternative:` of a `SiriPhrase` are shown on the page, so both must be registered phrases.
        shown = re.findall(r'\b(?:phrase|alternative):\s*"([^"]+)"', SHORTCUT_SETTINGS_SOURCE.read_text(encoding="utf-8"))
        if not shown:
            problems.append(f"{SHORTCUT_SETTINGS_SOURCE.relative_to(ROOT)}: no phrase found, the pattern in check-strings.py no longer matches")
        for text in shown:
            if not any(pattern.match(text.rstrip("?")) for pattern in patterns):
                problems.append(f"{SHORTCUT_SETTINGS_SOURCE.relative_to(ROOT)}: listed phrase is not an App Shortcuts phrase: {text!r}")


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


PROJECT_WORD = re.compile(r"\bProjects?\b")


def check_project_wording(problems):
    """German UI text says "Projekt"/"Projekte" for GitHub projects; the English value stays "Project".

    Stale entries (kept by the sync for keys that are no longer in the source) are skipped."""
    for path in catalogs():
        if path.name == "InfoPlist.xcstrings" or path.name == "AppShortcuts.xcstrings":
            continue
        for key, entry in load(path).get("strings", {}).items():
            if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
                continue
            source = entry.get("localizations", {}).get("de", {}).get("stringUnit", {}).get("value", key)
            if PROJECT_WORD.search(source):
                problems.append(f"{path.relative_to(ROOT)}: German text says \"Project\" instead of \"Projekt\": {key!r}")


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
    check_shortcut_phrases(problems)
    check_project_wording(problems)
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        print(f"{len(problems)} problem(s) in the String Catalogs", file=sys.stderr)
        return 1
    print(f"    {len(catalogs())} String Catalogs checked")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
