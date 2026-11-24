#!/usr/bin/env python3
"""Compare the shipped verse table with the independent sources and report every difference.

The table is app/Packages/TagwerkCore/Sources/TagwerkCore/Resources/schlachter2000-verses.json. The sources are the
count files in docs/research/data (written by scripts/extract-verse-counts.py). Only numbers are compared.

Usage
  python3 -I scripts/check-verse-table.py                         structure checks and comparison with the source files
  python3 -I scripts/check-verse-table.py --reference KJV         additionally list the differences to another edition

Exit status: 0 when the table is intact and equals every source file, 1 otherwise. Differences to a reference edition
(--reference) are informational and never change the exit status. NOTE: the table is provisional; none of the sources is
the Schlachter 2000 itself (see docs/research/2026-11-20-schlachter-2000-verszahlen.md).
"""

import argparse
import hashlib
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.path.join(ROOT, "app/Packages/TagwerkCore/Sources/TagwerkCore/Resources/schlachter2000-verses.json")
DATA = os.path.join(ROOT, "docs/research/data")
# The table is generated from the first file; the second (another edition with the same numbering) must agree with it.
SOURCES = ["luther-1545-bolsinger.json", "textbibel-1906.json"]
REFERENCES = {
    "KJV": "english-kjv.json",
    "Elberfelder1905": "elberfelder-1905.json",
    "Schlachter1951-scrollmapper": "schlachter-1951.json",
    "Schlachter1951-eBible": "ebible-deu1951.json",
}

# German book names in canon order, for readable output only.
NAMES = [
    "1. Mose", "2. Mose", "3. Mose", "4. Mose", "5. Mose", "Josua", "Richter", "Rut", "1. Samuel", "2. Samuel",
    "1. Könige", "2. Könige", "1. Chronik", "2. Chronik", "Esra", "Nehemia", "Ester", "Hiob", "Psalmen", "Sprüche",
    "Prediger", "Hohelied", "Jesaja", "Jeremia", "Klagelieder", "Hesekiel", "Daniel", "Hosea", "Joel", "Amos",
    "Obadja", "Jona", "Micha", "Nahum", "Habakuk", "Zefanja", "Haggai", "Sacharja", "Maleachi", "Matthäus",
    "Markus", "Lukas", "Johannes", "Apostelgeschichte", "Römer", "1. Korinther", "2. Korinther", "Galater", "Epheser",
    "Philipper", "Kolosser", "1. Thessalonicher", "2. Thessalonicher", "1. Timotheus", "2. Timotheus", "Titus",
    "Philemon", "Hebräer", "Jakobus", "1. Petrus", "2. Petrus", "1. Johannes", "2. Johannes", "3. Johannes", "Judas",
    "Offenbarung",
]


def load_counts(path):
    with open(path, encoding="utf-8") as handle:
        document = json.load(handle)
    return [book["counts"] for book in sorted(document["books"], key=lambda book: book["book"])], document


def differences(table, other):
    """Yields (book number, chapter, table value, other value); a missing chapter has the value None."""
    for index in range(max(len(table), len(other))):
        mine = table[index] if index < len(table) else []
        theirs = other[index] if index < len(other) else []
        for chapter in range(max(len(mine), len(theirs))):
            left = mine[chapter] if chapter < len(mine) else None
            right = theirs[chapter] if chapter < len(theirs) else None
            if left != right:
                yield index + 1, chapter + 1, left, right


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--reference", action="append", choices=sorted(REFERENCES), default=[],
                        help="list the differences to this edition too (informational)")
    arguments = parser.parse_args()

    with open(TABLE, "rb") as handle:
        raw = handle.read()
    table = json.loads(raw)["books"]
    failed = False

    print(f"table: {os.path.relpath(TABLE, ROOT)}")
    print(f"sha256: {hashlib.sha256(raw).hexdigest()}")
    chapters = sum(len(book) for book in table)
    verses = sum(sum(book) for book in table)
    print(f"books: {len(table)}, chapters: {chapters}, verses: {verses}")
    if len(table) != 66 or any(not book or min(book) < 1 for book in table):
        print("STRUCTURE ERROR: the table needs 66 books and no empty chapter")
        failed = True

    for name in SOURCES:
        path = os.path.join(DATA, name)
        if not os.path.exists(path):
            print(f"MISSING SOURCE: {name}")
            failed = True
            continue
        counts, document = load_counts(path)
        found = list(differences(table, counts))
        print(f"\n{name}  ({document['source']}): {len(found)} difference(s)")
        for book, chapter, mine, theirs in found:
            print(f"  {NAMES[book - 1]} {chapter}: table {mine}, source {theirs}")
        failed = failed or bool(found)
        gaps = [(book["book"], chapter, verses) for book in document["books"] for chapter, verses in book["gaps"].items()]
        for book, chapter, missing in gaps:
            print(f"  gap in the verse sequence of the source: {NAMES[book - 1]} {chapter}, missing {missing}")

    for key in arguments.reference:
        path = os.path.join(DATA, REFERENCES[key])
        if not os.path.exists(path):
            print(f"\nMISSING REFERENCE: {REFERENCES[key]}")
            continue
        counts, document = load_counts(path)
        found = list(differences(table, counts))
        print(f"\nreference {key}  ({document['source']}): {len(found)} difference(s), informational")
        for book, chapter, mine, theirs in found:
            print(f"  {NAMES[book - 1]} {chapter}: table {mine}, {key} {theirs}")

    print("\nRESULT:", "FAILED" if failed else "table equals all sources")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
