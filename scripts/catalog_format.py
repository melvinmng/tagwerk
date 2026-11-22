#!/usr/bin/env python3
"""Reads and writes the String Catalogs (.xcstrings) of Tagwerk in the format of each file.

The catalogs in the repository are JSON, written as json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True):
keys sorted by code point at every level, two-space indent, empty objects as "{}", no escaped "/". Two details
differ per file, and this module keeps them as they are, so a change of one entry changes only the lines of that entry:
  - the separator after a key: ": " or " : " (Xcode writes " : ")
  - whether the file ends with a line break

"xcstringstool sync" rewrites a whole catalog in its own style (" : ", empty objects on two lines, no final line break),
which turns a one-key change into thousands of changed lines. sync-strings.sh therefore lets the tool write into a copy
and takes over only the content, in the style of the original (command "adopt"). The sorting by code point is the
state of the repository; Xcode sorts differently when it saves a catalog in the user interface and then rewrites the file.

Usage:
  scripts/catalog_format.py adopt <catalog> <synced-copy>   write the content of the copy into the catalog, in the catalog's style,
                                                            only if the content differs; prints "N new, M changed, K removed"
  scripts/catalog_format.py check <catalog>...              exit 1 if a catalog is not in the repository format
"""
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

_FIRST_KEY_LINE = re.compile(r'^ *"[^"\\]*"( ?):', re.MULTILINE)


@dataclass(frozen=True)
class Style:
    """The two details of the file format that differ per catalog."""

    separator: str = ": "
    trailing_newline: bool = True


def detect_style(text):
    """Takes the separator from the first line that holds a key and the line break from the end of the file."""
    match = _FIRST_KEY_LINE.search(text)
    separator = " : " if match and match.group(1) == " " else ": "
    return Style(separator=separator, trailing_newline=text.endswith("\n"))


def serialize(data, style, sort_keys=True):
    """Serializes the content in the repository format with the given style.

    The String Catalogs are always sorted; scripts/translations/en.json keeps its insertion order (sort_keys=False).
    """
    text = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=sort_keys, separators=(",", style.separator))
    return text + "\n" if style.trailing_newline else text


def is_canonical(text):
    """True if re-serializing the content in the detected style gives back exactly this text."""
    return first_difference(text) is None


def first_difference(text):
    """Line number (1-based) of the first line that differs from the canonical form; None if the text is canonical."""
    try:
        canonical = serialize(json.loads(text), detect_style(text))
    except ValueError:
        return 1
    if canonical == text:
        return None
    actual_lines, expected_lines = text.split("\n"), canonical.split("\n")
    for number, (actual, expected) in enumerate(zip(actual_lines, expected_lines), start=1):
        if actual != expected:
            return number
    return min(len(actual_lines), len(expected_lines)) + 1


def adopt(original_text, synced_text):
    """Content of `synced_text` in the style of `original_text`, or None when both hold the same content (nothing to write)."""
    original, synced = json.loads(original_text), json.loads(synced_text)
    if original == synced:
        return None
    return serialize(synced, detect_style(original_text))


def summarize(original, synced):
    """Counts of new, changed and removed keys between two catalog contents."""
    old, new = original.get("strings", {}), synced.get("strings", {})
    added = len(set(new) - set(old))
    removed = len(set(old) - set(new))
    changed = sum(1 for key in set(old) & set(new) if old[key] != new[key])
    return added, changed, removed


def _read(path):
    return Path(path).read_text(encoding="utf-8")


def _command_adopt(catalog, synced_copy):
    original_text, synced_text = _read(catalog), _read(synced_copy)
    result = adopt(original_text, synced_text)
    if result is None:
        return 0
    Path(catalog).write_text(result, encoding="utf-8")
    added, changed, removed = summarize(json.loads(original_text), json.loads(synced_text))
    print(f"{catalog}: {added} new, {changed} changed, {removed} removed")
    return 0


def _command_check(catalogs):
    status = 0
    for catalog in catalogs:
        line = first_difference(_read(catalog))
        if line is not None:
            print(f"{catalog}: not in the repository format (first difference at line {line}); run scripts/sync-strings.sh",
                  file=sys.stderr)
            status = 1
    return status


def main(arguments):
    if len(arguments) == 3 and arguments[0] == "adopt":
        return _command_adopt(arguments[1], arguments[2])
    if len(arguments) >= 2 and arguments[0] == "check":
        return _command_check(arguments[1:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
