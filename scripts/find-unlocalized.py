#!/usr/bin/env python3
"""Lists string literals that look like German UI text but are not in any String Catalog (plan english-app, Task 3).

Uses `xcstringstool extract --all-potential-swift-keys`, which reports every literal that could be a localization
key, and removes keys already in a catalog, identifiers and files that stay German on purpose.

Usage: scripts/find-unlocalized.py [--summary] [paths …]
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"

# Developer tools, model-facing prompts and demo content stay German (plan english-app, decision 10).
EXCLUDED = [
    "Tagwerk/AI/VoiceDiagnostics.swift", "Tagwerk/AI/RealtimeProbe.swift", "Tagwerk/Voice/RecognitionSpikeView.swift",
    "Tagwerk/Voice/ConversationSpikeView.swift", "Tagwerk/AI/PlanningDiagnostics.swift",
    "Tagwerk/Settings/CalendarDiagnosticsView.swift", "Tagwerk/App/DemoData.swift", "Tagwerk/AI/DemoAITransport.swift",
    "Tagwerk/AI/AppTools+Definitions.swift",
]


def main(arguments):
    summary = "--summary" in arguments
    roots = [a for a in arguments if not a.startswith("--")] or ["Tagwerk", "TagwerkWidget", "Packages"]
    sources = [p for r in roots for p in (APP / r).rglob("*.swift") if "/Tests/" not in str(p)]
    sources = [p for p in sources if not any(str(p).endswith(e) for e in EXCLUDED)]
    known = {}
    for catalog in APP.rglob("*.xcstrings"):
        known.update(json.load(open(catalog, encoding="utf-8"))["strings"])
    with tempfile.TemporaryDirectory() as out:
        env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
        subprocess.run(["xcrun", "xcstringstool", "extract", "--all-potential-swift-keys", *map(str, sources),
                        "--output-directory", out], check=True, capture_output=True, env=env)
        hits = {}
        for path in glob.glob(f"{out}/*.stringsdata"):
            data = json.load(open(path, encoding="utf-8"))
            for entry in data["tables"].get("__PotentialKeys", []):
                key = entry["key"]
                if key in known or not re.search(r"[a-zäöüß]{3,}", key):
                    continue
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.:\-/]*", key):
                    continue
                source = os.path.relpath(data["source"], APP)
                hits.setdefault(source, []).append((entry["location"]["startingLine"], key))
    total = sum(len(v) for v in hits.values())
    for source, entries in sorted(hits.items()):
        if summary:
            print(f"{len(entries):4} {source}")
        else:
            for line, key in sorted(entries):
                print(f"{source}:{line}: {key}")
    print(f"{total} candidates in {len(hits)} files", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])
