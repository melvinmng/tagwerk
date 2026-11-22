#!/usr/bin/env python3
"""Extract chapter and verse counts from a scrollmapper JSON file and write the verse table of the app.

Only numbers are written (the highest verse number per chapter and any gaps in the verse sequence); no Bible text.
The input files are the ones of the open project https://github.com/scrollmapper/bible_databases (formats/json/*.json,
repository licence MIT), downloaded by hand, for example with
  gh api -H "Accept: application/vnd.github.raw" repos/scrollmapper/bible_databases/contents/formats/json/GerSch.json > GerSch.json

Usage
  python3 -I scripts/extract-verse-counts.py counts --input GerBoLut.json --out docs/research/data/luther-1545-bolsinger.json
  python3 -I scripts/extract-verse-counts.py usfm   --input deu1951_usfm --out docs/research/data/ebible-deu1951.json
  python3 -I scripts/extract-verse-counts.py table  --input docs/research/data/luther-1545-bolsinger.json \
      --out app/Packages/TagwerkCore/Sources/TagwerkCore/Resources/schlachter2000-verses.json

  usfm    reads a folder of USFM files (for example the eBible.org package deu1951_usfm.zip, unpacked) and writes the
          same count file; only the markers \\c (chapter) and \\v (verse) are read.
  counts  reads a scrollmapper file and writes the count file (per book: chapter counts and gaps, plus the file's SHA-256).
  table   converts a count file into the resource of the app: one list of verse counts per book, nothing else.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import sys

# USFM book codes in canon order (the 66 books of the Protestant canon).
USFM_CODES = (
    "GEN EXO LEV NUM DEU JOS JDG RUT 1SA 2SA 1KI 2KI 1CH 2CH EZR NEH EST JOB PSA PRO ECC SNG ISA JER LAM EZK DAN HOS JOL "
    "AMO OBA JON MIC NAM HAB ZEP HAG ZEC MAL MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP COL 1TH 2TH 1TI 2TI TIT PHM HEB "
    "JAS 1PE 2PE 1JN 2JN 3JN JUD REV"
).split()


def summarize(verse_sets):
    """Per chapter: highest verse number plus the verses missing below it."""
    counts, gaps = [], {}
    for chapter, verses in enumerate(verse_sets, start=1):
        highest = max(verses)
        counts.append(highest)
        missing = sorted(set(range(1, highest + 1)) - verses)
        if missing:
            gaps[str(chapter)] = missing
    return counts, gaps


def counts_command(arguments):
    with open(arguments.input, "rb") as handle:
        raw = handle.read()
    document = json.loads(raw)
    books = []
    for number, book in enumerate(document["books"], start=1):
        chapters = sorted(book["chapters"], key=lambda chapter: chapter["chapter"])
        if [chapter["chapter"] for chapter in chapters] != list(range(1, len(chapters) + 1)):
            raise SystemExit(f"book {number}: chapters are not contiguous")
        counts, gaps = summarize([{verse["verse"] for verse in chapter["verses"]} for chapter in chapters])
        books.append({"book": number, "counts": counts, "gaps": gaps})
    if len(books) != 66:
        raise SystemExit(f"expected 66 books, found {len(books)}")
    result = {
        "source": f"scrollmapper/bible_databases, {arguments.input.rsplit('/', 1)[-1]}: {document.get('translation', '')}",
        "inputSHA256": hashlib.sha256(raw).hexdigest(),
        "books": books,
    }
    with open(arguments.out, "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
    chapters = sum(len(book["counts"]) for book in books)
    verses = sum(sum(book["counts"]) for book in books)
    print(f"wrote {arguments.out}: {len(books)} books, {chapters} chapters, {verses} verses")


def usfm_command(arguments):
    books = []
    digest = hashlib.sha256()
    for number, code in enumerate(USFM_CODES, start=1):
        matches = glob.glob(os.path.join(arguments.input, f"*-{code}*.usfm"))
        if len(matches) != 1:
            raise SystemExit(f"book {number} ({code}): expected one USFM file, found {matches}")
        with open(matches[0], "rb") as handle:
            raw = handle.read()
        digest.update(raw)
        chapters = {}
        current = None
        for line in raw.decode("utf-8-sig").splitlines():
            chapter = re.match(r"\\c\s+(\d+)", line)
            if chapter:
                current = int(chapter.group(1))
                chapters[current] = set()
                continue
            verse = re.match(r"\\v\s+(\d+)(?:-(\d+))?", line)
            if verse and current is not None:
                first, last = int(verse.group(1)), int(verse.group(2) or verse.group(1))
                chapters[current].update(range(first, last + 1))
        if sorted(chapters) != list(range(1, len(chapters) + 1)):
            raise SystemExit(f"book {number}: chapters are not contiguous")
        counts, gaps = summarize([chapters[chapter] for chapter in sorted(chapters)])
        books.append({"book": number, "counts": counts, "gaps": gaps})
    result = {"source": f"USFM folder {os.path.basename(arguments.input.rstrip('/'))}", "inputSHA256": digest.hexdigest(), "books": books}
    with open(arguments.out, "w", encoding="utf-8") as handle:
        json.dump(result, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
    print(f"wrote {arguments.out}: {len(books)} books, {sum(len(b['counts']) for b in books)} chapters, {sum(sum(b['counts']) for b in books)} verses")


def table_command(arguments):
    with open(arguments.input, encoding="utf-8") as handle:
        counts = [book["counts"] for book in sorted(json.load(handle)["books"], key=lambda book: book["book"])]
    lines = ",\n".join("  " + json.dumps(book) for book in counts)
    with open(arguments.out, "w", encoding="utf-8") as handle:
        handle.write('{\n "edition": "German numbering (provisional for Schlachter 2000)",\n "books": [\n' + lines + "\n ]\n}\n")
    print(f"wrote {arguments.out}: {len(counts)} books, {sum(len(book) for book in counts)} chapters")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["counts", "usfm", "table"])
    parser.add_argument("--input", required=True)
    parser.add_argument("--out", required=True)
    arguments = parser.parse_args()
    {"counts": counts_command, "usfm": usfm_command, "table": table_command}[arguments.command](arguments)


if __name__ == "__main__":
    sys.exit(main())
