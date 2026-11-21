#!/bin/zsh
# Brings the String Catalogs in line with the source code (plan english-app, Task 1).
#
# App and widget: the keys come from the .stringsdata files the compiler writes during a build.
# Packages: the keys come from the .stringsdata of the package targets in the same build.
# Hand-maintained catalogs (InfoPlist, AppShortcuts) are not touched.
#
# The format of each catalog stays as it is: xcstringstool rewrites a whole file in its own style, so it only ever
# writes into a copy, and scripts/catalog_format.py takes over the content in the style of the checked-in file. A tree
# without changes gives no diff, one new text gives one new line.
#
# Usage: scripts/sync-strings.sh [--check] [--derived-data PATH] [--no-build]
#        scripts/sync-strings.sh [--check] --sync-one CATALOG STRINGSDATA...
#   --check        fail when the synced content differs from the checked-in catalogs; nothing is written
#   --no-build     reuse the .stringsdata of an earlier build in the derived data folder
#   --sync-one     test entry point (scripts/tests/sync-strings-format.zsh): syncs only this catalog with the given
#                  .stringsdata files, without a build and without a search in the derived data folder
# Exit codes: 0 in sync (or synced), 1 catalogs differ (--check), 2 build or tool failure

set -euo pipefail

# TAGWERK_DEVELOPER_DIR selects another Xcode (used by the CI workflow); unset keeps the default.
export DEVELOPER_DIR="${TAGWERK_DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

REPO_ROOT="${0:A:h:h}"
APP_DIR="$REPO_ROOT/app"
source "$REPO_ROOT/scripts/test-env.sh"
DERIVED="$TAGWERK_TEST_DERIVED"
CHECK=0
BUILD=1
SYNC_ONE=()

while (( $# > 0 )); do
  case "$1" in
    --check) CHECK=1 ;;
    --no-build) BUILD=0 ;;
    --derived-data) shift; DERIVED="$1" ;;
    --sync-one) shift; SYNC_ONE=("$@"); break ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if (( BUILD && ${#SYNC_ONE} == 0 )); then
  DESTINATION=$(tagwerk_test_destination) || exit 2
  if ! xcodebuild build-for-testing -project "$APP_DIR/Tagwerk.xcodeproj" -scheme Tagwerk -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED" > "$WORK/build.log" 2>&1; then
    tail -n 20 "$WORK/build.log" >&2
    exit 2
  fi
fi

# Syncs one catalog with the given .stringsdata files. xcstringstool writes into a copy; the checked-in catalog is only
# touched in write mode, and only when the content changes (scripts/catalog_format.py keeps the format of the file).
sync_catalog() {
  local catalog="$1"; shift
  # The file name is the table name, so the copy keeps it.
  local folder="$WORK/sync/${${catalog:h}//\//_}"
  mkdir -p "$folder"
  local target="$folder/${catalog:t}"
  cp "$catalog" "$target"
  local arguments=()
  for file in "$@"; do
    # Incremental builds keep .stringsdata of deleted sources; they would hide keys that are no longer used.
    if /usr/bin/python3 -c 'import json, os, sys; sys.exit(0 if os.path.exists(json.load(open(sys.argv[1]))["source"]) else 1)' "$file"; then
      arguments+=(--stringsdata "$file")
    fi
  done
  if (( ${#arguments} == 0 )); then
    # A catalog without any extracted text means the build output is missing, not that everything matches.
    echo "No .stringsdata for ${catalog#$REPO_ROOT/} in $DERIVED" >&2
    exit 2
  fi
  if ! xcrun xcstringstool sync "$target" "${arguments[@]}" >/dev/null; then
    echo "xcstringstool sync failed for ${catalog#$REPO_ROOT/}" >&2
    exit 2
  fi
  if (( CHECK )); then
    /usr/bin/python3 "$REPO_ROOT/scripts/check-strings.py" --same "$catalog" "$target" || DIFFERENT=1
  else
    /usr/bin/python3 "$REPO_ROOT/scripts/catalog_format.py" adopt "$catalog" "$target" || exit 2
  fi
}

DIFFERENT=0
if (( ${#SYNC_ONE} > 0 )); then
  sync_catalog "${SYNC_ONE[@]}"
  (( CHECK && DIFFERENT )) && exit 1
  exit 0
fi
INTERMEDIATES="$DERIVED/Build/Intermediates.noindex/Tagwerk.build"

for target in Tagwerk TagwerkWidget TagwerkShare; do
  catalog="$APP_DIR/$target/Localizable.xcstrings"
  [[ -f "$catalog" ]] || continue
  files=("$INTERMEDIATES"/*-iphonesimulator/$target.build/Objects-normal/*/*.stringsdata(N))
  files=(${files:#*ExtractedAppShortcutsMetadata*})
  sync_catalog "$catalog" "${files[@]}"
done

for package_dir in "$APP_DIR"/Packages/*(/N); do
  name="${package_dir:t}"
  catalog="$package_dir/Sources/$name/Resources/Localizable.xcstrings"
  [[ -f "$catalog" ]] || continue
  # The app build compiles the packages with SWIFT_EMIT_LOC_STRINGS too; unlike `xcstringstool extract` on the
  # sources, these .stringsdata carry the typed placeholders (%lld, %@) that the runtime lookup uses.
  files=("$DERIVED/Build/Intermediates.noindex/$name.build"/*-iphonesimulator/$name-t.build/Objects-normal/*/*.stringsdata(N))
  sync_catalog "$catalog" "${files[@]}"
done

if (( CHECK && DIFFERENT )); then
  echo "String Catalogs are out of date: run scripts/sync-strings.sh and add the new texts." >&2
  exit 1
fi
