#!/usr/bin/env python3
"""Git merge driver for the String Catalogs (*.xcstrings) and scripts/translations/en.json of Tagwerk.

Two branches that add different keys to the same catalog change neighbouring or identical lines of the file, so a text
merge reports a conflict although nothing contradicts. This driver merges the JSON content instead: a three-way merge
on the level of single keys and, below a key, on the level of single values (localizations, string units, ...).

Rules, applied recursively to every object (a list or a scalar counts as one value):
  - only one side changed an entry (added, changed or removed it): that side wins
  - both sides made the same change: take it
  - both sides changed an object entry differently: merge its content again, with the base content (empty if the entry
    is new on both sides) as the common ancestor
  - both sides changed the same value differently, or one side changed a value the other removed: real conflict

The result is written in the format of the file (scripts/catalog_format.py): String Catalogs sorted by code point,
en.json in insertion order (keys that only "theirs" added follow the keys of "ours"). A merge that changes nothing on
our side leaves the file byte for byte as it was. The format comes from --format or, with "auto", from the content of
the file (a String Catalog has the top-level keys "sourceLanguage" and "strings"), never from the file name: git passes
temporary file names, and the path argument (%P) is optional.

On a real conflict the driver reports the conflicting paths on stderr, writes the merged file with standard conflict
markers around the conflicting values only (everything else is merged already) and exits with 1.

Usage (git merge driver protocol, see scripts/setup-git-merge-drivers.sh):
  scripts/merge-xcstrings.py [--format auto|xcstrings|ordered-json] BASE OURS THEIRS [PATH]
BASE, OURS and THEIRS are the temporary files git passes as %O, %A and %B; the result is written to OURS. PATH (%P) only
names the file in messages and serves as a fallback for the format ("auto": a document that looks like a String Catalog
is sorted; otherwise *.xcstrings are sorted and everything else keeps its order).
Exit codes: 0 merged cleanly, 1 conflict (markers in OURS), 2 usage error.
"""
import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import catalog_format

MISSING = object()


def _same(left, right):
    """Equality that tells booleans from numbers (Python compares True == 1) and handles the MISSING marker."""
    if left is MISSING or right is MISSING:
        return left is right
    if isinstance(left, dict) and isinstance(right, dict):
        return left.keys() == right.keys() and all(_same(left[key], right[key]) for key in left)
    if isinstance(left, list) and isinstance(right, list):
        return len(left) == len(right) and all(_same(a, b) for a, b in zip(left, right))
    if isinstance(left, (dict, list)) or isinstance(right, (dict, list)):
        return False
    return type(left) is type(right) and left == right


def _describe(path):
    """Location of a conflict as quoted keys, because keys of a String Catalog are free text (dots, slashes, spaces)."""
    return " / ".join(json.dumps(step, ensure_ascii=False) for step in path) or "(whole file)"


def merge_nodes(base, ours, theirs, path, conflicts, choice="ours"):
    """Three-way merge of one node; returns the merged node or MISSING. Conflicts are appended as (path, ours, theirs).

    A conflicting value is replaced by the value of the side named in `choice` ("base", "ours" or "theirs"); merging
    three times gives three documents that differ only in the conflicting values (see _conflict_merge).
    """
    if _same(ours, theirs):
        return ours
    if _same(ours, base):
        return theirs
    if _same(theirs, base):
        return ours
    if isinstance(ours, dict) and isinstance(theirs, dict):
        base_object = base if isinstance(base, dict) else {}
        merged = {}
        # Keys of "ours" first, then the keys only "theirs" has: appended entries of both sides keep a stable order.
        for key in list(ours) + [key for key in theirs if key not in ours]:
            value = merge_nodes(base_object.get(key, MISSING), ours.get(key, MISSING), theirs.get(key, MISSING),
                                path + [key], conflicts, choice)
            if value is not MISSING:
                merged[key] = value
        return merged
    conflicts.append((path, ours, theirs))
    return {"base": base, "ours": ours, "theirs": theirs}[choice]


def merge_documents(base, ours, theirs, choice="ours"):
    """Returns (merged content, conflicts)."""
    conflicts = []
    merged = merge_nodes(base, ours, theirs, [], conflicts, choice)
    return merged, conflicts


def _shorten(value, limit=80):
    text = "<absent>" if value is MISSING else json.dumps(value, ensure_ascii=False)
    return text if len(text) <= limit else text[:limit - 1] + "…"


def _read_text(path):
    return Path(path).read_bytes().decode("utf-8")


def _write_text(path, text):
    Path(path).write_bytes(text.encode("utf-8"))


def _text_merge(base_path, ours_path, theirs_path, marker_size):
    """Ordinary three-way text merge into OURS (conflict markers included); returns git's exit status."""
    command = ["git", "merge-file", f"--marker-size={marker_size}", "-L", "ours", "-L", "base", "-L", "theirs",
               ours_path, base_path, theirs_path]
    try:
        return subprocess.run(command, check=False).returncode
    except OSError as error:
        print(f"merge-xcstrings: cannot run git merge-file: {error}", file=sys.stderr)
        return 255


def _conflict_merge(base, ours, theirs, ours_path, ours_text, file_format, marker_size):
    """Writes the merged file with conflict markers around the conflicting values only.

    Everything that merged cleanly is the same in three documents; the conflicting values are the base, ours and theirs
    value in one document each. A text merge of these three puts markers exactly around the conflicts.
    """
    style = catalog_format.detect_style(ours_text)
    sort_keys = file_format == "xcstrings"
    documents = {}
    for choice in ("base", "ours", "theirs"):
        document, _ = merge_documents(base, ours, theirs, choice)
        if document is MISSING:
            return  # the whole file is one conflicting value (never the case for a catalog): leave ours as it is
        documents[choice] = catalog_format.serialize(document, style, sort_keys=sort_keys)
    with tempfile.TemporaryDirectory() as directory:
        paths = {}
        for choice, text in documents.items():
            paths[choice] = str(Path(directory) / choice)
            _write_text(paths[choice], text)
        _text_merge(paths["base"], paths["ours"], paths["theirs"], marker_size)
        _write_text(ours_path, _read_text(paths["ours"]))


def looks_like_string_catalog(document):
    """True for the top level of a String Catalog: an object with "sourceLanguage" and an object "strings"."""
    return isinstance(document, dict) and "sourceLanguage" in document and isinstance(document.get("strings"), dict)


def resolve_format(requested, display_path, documents=()):
    """Format of the file: an explicit request wins; "auto" looks at the content first and at the file name second.

    The content decides because the file name is unreliable: without %P in the driver command git only hands over
    temporary names, and a catalog would be written in insertion order instead of sorted.
    """
    if requested != "auto":
        return requested
    if any(looks_like_string_catalog(document) for document in documents):
        return "xcstrings"
    return "xcstrings" if str(display_path).endswith(".xcstrings") else "ordered-json"


def run(base_path, ours_path, theirs_path, display_path, file_format, marker_size=7):
    """Merges the three files into `ours_path`. Returns the exit code of the driver.

    `file_format` is "xcstrings", "ordered-json" or "auto" (decided from the content once the files are parsed).
    """
    ours_text = _read_text(ours_path)
    try:
        base = json.loads(_read_text(base_path))
        ours = json.loads(ours_text)
        theirs = json.loads(_read_text(theirs_path))
    except ValueError as error:
        print(f"merge-xcstrings: {display_path}: not valid JSON ({error}); falling back to the text merge", file=sys.stderr)
        return 1 if _text_merge(base_path, ours_path, theirs_path, marker_size) != 0 else 0

    file_format = resolve_format(file_format, display_path, (ours, theirs, base))
    merged, conflicts = merge_documents(base, ours, theirs)
    if conflicts:
        print(f"merge-xcstrings: {display_path}: {len(conflicts)} conflict(s) that need a decision:", file=sys.stderr)
        for path, ours_value, theirs_value in conflicts:
            print(f"  {_describe(path)}\n    ours:   {_shorten(ours_value)}\n    theirs: {_shorten(theirs_value)}",
                  file=sys.stderr)
        _conflict_merge(base, ours, theirs, ours_path, ours_text, file_format, marker_size)
        return 1

    if not _same(merged, ours):
        style = catalog_format.detect_style(ours_text)
        _write_text(ours_path, catalog_format.serialize(merged, style, sort_keys=(file_format == "xcstrings")))
    return 0


def main(arguments):
    parser = argparse.ArgumentParser(description="Git merge driver for String Catalogs and en.json.")
    parser.add_argument("--format", choices=["auto", "xcstrings", "ordered-json"], default="auto")
    parser.add_argument("--marker-size", type=int, default=7, help="length of conflict markers (git's %%L)")
    parser.add_argument("base")
    parser.add_argument("ours")
    parser.add_argument("theirs")
    parser.add_argument("path", nargs="?", default=None)
    options = parser.parse_args(arguments)
    display_path = options.path or options.ours
    return run(options.base, options.ours, options.theirs, display_path, options.format, options.marker_size)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
