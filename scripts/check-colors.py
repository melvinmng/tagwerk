#!/usr/bin/env python3
"""Checks that the app does not use the system grey or a system colour as the colour of text (strand K, plan g3-system-anbindungen).

The accessibility audit measures text colours on the app's backgrounds. The system grey (.secondary) and the system colours red,
orange, green and purple are too light as text in the light appearance, so text uses the named tones of `Common/TextTones.swift`:
`.secondaryText`, `.redText`, `.orangeText`, `.greenText`, `.purpleText`.

Reported in the targets Tagwerk and TagwerkShare (the widget keeps the system styles; the files that are compiled into the widget too
are left out):
  1. `.foregroundStyle(...)` or `.foregroundColor(...)` with `.secondary` or `Color.secondary` - for text and for symbols of a text
     line alike (a `Label` shares one style).
  2. `.foregroundStyle(...)` with `.red`, `.orange`, `.green` or `.purple` on a `Text(` or `Label(` of the same statement. Symbols,
     bars, dots and fills keep the system colour.
  3. In the files of `SECTION_TONE_SCOPE` (the pages of decision D1: settings, recipes, Siri, backup, voice, evening sheet): a `Text(`
     in a `header:` or `footer:` closure of a `Section` without `.foregroundStyle(...)`, and a `Section("Title")` / `Section(title)`
     initialiser, whose header the system draws in its own grey (3.3:1 on the grouped background in the light appearance). Use
     `Section { ... } header: { Text("Title").foregroundStyle(.secondaryText) }`.
A line that carries the comment `// system-colour: <reason>` is exempt (the reason says why the system colour stays).

Usage: scripts/check-colors.py [--report]
  --report   only count the findings per folder, always exit 0 (used while the replacement is in progress)
Exit codes: 0 no findings (or --report), 1 findings
"""
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
TARGET_FOLDERS = [APP / "Tagwerk", APP / "TagwerkShare"]
# Compiled into the widget as well (project.yml): the widget has no text tones.
WIDGET_SHARED = [APP / "Tagwerk" / "Focus" / "Shared", APP / "Tagwerk" / "Controls" / "Shared", APP / "Tagwerk" / "App" / "Color+Hex.swift"]

# The pages whose section headers and footers are in the tone `secondaryText` (decision D1 of the audit allowlist council, 2026-11-25).
# Other screens still use the system grey for headers and footers; add them here when they are converted.
SECTION_TONE_SCOPE = [
    "Tagwerk/Settings/*.swift", "Tagwerk/Backup/*.swift", "Tagwerk/Voice/VoiceSettingsView.swift", "Tagwerk/Voice/VoiceChoiceView.swift",
    "Tagwerk/Routines/EveningSheet.swift", "Tagwerk/Routines/NoteField.swift", "Tagwerk/Routines/TimeWithGodSection.swift",
    "Tagwerk/Shopping/Recipe*.swift", "Tagwerk/Shopping/ShoppingTranslationSheets.swift", "Tagwerk/Shopping/ShoppingSettingsView.swift",
    "Tagwerk/Shopping/ShoppingCategoriesView.swift", "Tagwerk/Notes/RecipeTranslationSheet.swift", "Tagwerk/Common/PreviewFollowUpSection.swift",
]
SECTION_CLOSURE = re.compile(r"\b(?:header|footer): \{")
SECTION_TITLE_INITIALISER = re.compile(r"\bSection\((?:\"[^\"\n]*\"|[A-Za-z_][\w.]*)\) \{")
TEXT_START = re.compile(r"(?<![\w.])Text\(")

FOREGROUND = re.compile(r"\.foreground(?:Style|Color)\(")
GREY = re.compile(r"(?<![\w.])(?:Color)?\.secondary(?![\w])")
SYSTEM_COLOUR = re.compile(r"(?<![\w.])(?:Color)?\.(red|orange|green|purple)(?![\w])")
EXEMPT = re.compile(r"//\s*system-colour:")
# What a statement starts with decides whether a colour is the colour of text or of a symbol, fill or bar.
TEXT_ROOT = re.compile(r"\b(Text|Label)\(")


def swift_files():
    for folder in TARGET_FOLDERS:
        for path in sorted(folder.rglob("*.swift")):
            if any(path == shared or shared in path.parents for shared in WIDGET_SHARED):
                continue
            yield path


def arguments_of_foreground(line):
    """The text inside every `.foregroundStyle(...)` / `.foregroundColor(...)` of the line (balanced parentheses)."""
    result = []
    for match in FOREGROUND.finditer(line):
        depth, start = 1, match.end()
        for index in range(start, len(line)):
            depth += {"(": 1, ")": -1}.get(line[index], 0)
            if depth == 0:
                result.append(line[start:index])
                break
        else:
            result.append(line[start:])
    return result


CONTINUATION = re.compile(r"^(\.|\w+:\s|\} \w+:)")


def statement_head(lines, index):
    """The statements `lines[index]` belongs to, from its first line: a modifier line (starting with a dot) and a continued argument
    list (a line that starts with `label:` or `} icon:`) belong to the line above."""
    start = index
    while start > 0 and CONTINUATION.match(lines[start].lstrip()) and index - start < 14:
        start -= 1
    return " ".join(line.strip() for line in lines[start:index + 1])


def findings(path):
    lines = path.read_text(encoding="utf-8").split("\n")
    for index, line in enumerate(lines):
        if EXEMPT.search(line) or not FOREGROUND.search(line):
            continue
        arguments = " ".join(arguments_of_foreground(line))
        if GREY.search(arguments):
            yield index + 1, "system grey as foreground", line.strip()
        elif SYSTEM_COLOUR.search(arguments) and TEXT_ROOT.search(statement_head(lines, index)):
            yield index + 1, "system colour on text", line.strip()


def balanced_end(text, start, opening, closing):
    """Index of the bracket that closes `text[start]`; string literals (with interpolations) are skipped."""
    depth, index = 0, start
    while index < len(text):
        char = text[index]
        if char == '"':
            index += 1
            while index < len(text) and text[index] != '"':
                if text[index] == "\\" and text[index + 1] == "(":
                    index = balanced_end(text, index + 1, "(", ")")
                elif text[index] == "\\":
                    index += 1
                index += 1
        elif char == opening:
            depth += 1
        elif char == closing:
            depth -= 1
            if depth == 0:
                return index
        index += 1
    return len(text) - 1


def modifier_chain_end(text, index):
    """End of the modifier chain (`.font(...)`, `.foregroundStyle(...)`, ...) that follows a call ending before `index`."""
    while True:
        match = re.match(r"\s*\.[a-zA-Z]+", text[index:])
        if not match:
            return index
        index += match.end()
        if index < len(text) and text[index] in "({":
            closing = ")" if text[index] == "(" else "}"
            index = balanced_end(text, index, text[index], closing) + 1


def section_tone_findings(path):
    """Headers and footers of a `Section` in the files of decision D1 that keep the system grey."""
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    line_of = lambda offset: text.count("\n", 0, offset) + 1
    for match in SECTION_TITLE_INITIALISER.finditer(text):
        number = line_of(match.start())
        if not EXEMPT.search(lines[number - 1]):
            yield number, "section title in the system grey (use `header:` with `.secondaryText`)", lines[number - 1].strip()
    for match in SECTION_CLOSURE.finditer(text):
        end = balanced_end(text, match.end() - 1, "{", "}")
        body = text[match.end():end]
        for call in TEXT_START.finditer(body):
            start = match.end() + call.start()
            call_end = balanced_end(text, start + 4, "(", ")") + 1
            chain = text[call_end:modifier_chain_end(text, call_end)]
            number = line_of(start)
            if "foregroundStyle" in chain or "foregroundColor" in chain or EXEMPT.search(lines[number - 1]):
                continue
            yield number, "header or footer text in the system grey (add `.foregroundStyle(.secondaryText)`)", lines[number - 1].strip()


def main(argv):
    report_only = "--report" in argv
    counts = Counter()
    problems = []
    scoped = {path for pattern in SECTION_TONE_SCOPE for path in APP.glob(pattern)}
    for path in swift_files():
        found = list(findings(path))
        if path in scoped:
            found += list(section_tone_findings(path))
        for number, kind, text in found:
            counts[path.relative_to(APP).parts[1] if len(path.relative_to(APP).parts) > 2 else path.relative_to(APP).parts[0]] += 1
            problems.append(f"{path.relative_to(ROOT)}:{number}: {kind}: {text}")
    if report_only:
        print(f"{len(problems)} place(s) still use a system colour as text colour")
        for folder, count in sorted(counts.items(), key=lambda item: (-item[1], item[0])):
            print(f"  {count:>4}  {folder}")
        return 0
    for problem in problems:
        print(problem)
    if problems:
        print(f"{len(problems)} place(s): use the tones of Common/TextTones.swift, or add `// system-colour: <reason>`")
        return 1
    print("no system colour as text colour")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
