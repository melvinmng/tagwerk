#!/bin/zsh
# Tests that scripts/sync-strings.sh keeps the format of the String Catalogs: no diff on an unchanged tree, one added
# line for one new text, no further change on a second run, and --check before and after. Needs xcrun xcstringstool,
# but no build and no simulator. Run: zsh scripts/tests/sync-strings-format.zsh

set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

REPO_ROOT="${0:A:h:h:h}"
SYNC="$REPO_ROOT/scripts/sync-strings.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILED=0

check() {
  local description="$1"; shift
  if "$@"; then
    echo "ok      $description"
  else
    echo "FAILED  $description" >&2
    FAILED=1
  fi
}

# (The new key sorts near the start, so the previous line keeps its comma: the diff is one line.)
# Writes a .stringsdata that names every key of the catalog that is not stale, plus the extra keys.
write_stringsdata() {
  local catalog="$1" output="$2" source_file="$3"; shift 3
  /usr/bin/python3 - "$catalog" "$output" "$source_file" "$@" <<'PYTHON'
import json, sys
catalog, output, source_file, extra = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
with open(catalog, encoding="utf-8") as handle:
    strings = json.load(handle)["strings"]
keys = [key for key, entry in strings.items() if key != "" and entry.get("extractionState") != "stale"] + extra
data = {"source": source_file, "tables": {"Localizable": [
    {"comment": "", "key": key, "location": {"startingColumn": 1, "startingLine": 1}} for key in keys]}, "version": 1}
with open(output, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
PYTHON
}

SOURCE_FILE="$WORK/Source.swift"
: > "$SOURCE_FILE"

# One catalog per style: separator ": " (TagwerkCore) and " : " (RemindersKit).
for original in \
    "$REPO_ROOT/app/Packages/TagwerkCore/Sources/TagwerkCore/Resources/Localizable.xcstrings" \
    "$REPO_ROOT/app/Packages/RemindersKit/Sources/RemindersKit/Resources/Localizable.xcstrings"; do
  name="${original:h:h:h:h:t}"
  echo "== $name"
  folder="$WORK/$name"
  mkdir -p "$folder"
  catalog="$folder/Localizable.xcstrings"
  cp "$original" "$catalog"
  cp "$original" "$folder/original.xcstrings"
  write_stringsdata "$catalog" "$folder/unchanged.stringsdata" "$SOURCE_FILE"
  write_stringsdata "$catalog" "$folder/new-key.stringsdata" "$SOURCE_FILE" "A new text for the test"

  "$SYNC" --sync-one "$catalog" "$folder/unchanged.stringsdata"
  check "$name: unchanged tree leaves the catalog byte for byte as it was" cmp -s "$catalog" "$folder/original.xcstrings"

  check "$name: --check on the unchanged tree succeeds" "$SYNC" --check --sync-one "$catalog" "$folder/unchanged.stringsdata"

  if "$SYNC" --check --sync-one "$catalog" "$folder/new-key.stringsdata" 2>/dev/null; then check "$name: --check fails before the write" false
  else check "$name: --check fails before the write" true; fi

  "$SYNC" --sync-one "$catalog" "$folder/new-key.stringsdata"
  diff "$folder/original.xcstrings" "$catalog" > "$folder/diff.txt" || true
  added=$(grep -c '^>' "$folder/diff.txt" || true)
  removed=$(grep -c '^<' "$folder/diff.txt" || true)
  check "$name: one new text adds exactly one line and removes none (added $added, removed $removed)" test "$added" -eq 1 -a "$removed" -eq 0

  cp "$catalog" "$folder/after-first.xcstrings"
  "$SYNC" --sync-one "$catalog" "$folder/new-key.stringsdata"
  check "$name: a second run changes nothing" cmp -s "$catalog" "$folder/after-first.xcstrings"

  check "$name: --check after the write succeeds" "$SYNC" --check --sync-one "$catalog" "$folder/new-key.stringsdata"
done

if (( FAILED )); then echo "sync-strings format tests FAILED" >&2; exit 1; fi
echo "sync-strings format tests passed"
