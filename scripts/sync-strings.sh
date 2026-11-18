#!/bin/zsh
# Brings the String Catalogs in line with the source code (plan english-app, Task 1).
#
# App and widget: the keys come from the .stringsdata files the compiler writes during a build.
# Packages: the keys come from `xcstringstool extract` on the package sources (no .stringsdata there).
# Hand-maintained catalogs (InfoPlist, AppShortcuts) are not touched.
#
# Usage: scripts/sync-strings.sh [--check] [--derived-data PATH] [--no-build]
#   --check        sync into a temporary copy and fail when it differs from the checked-in catalogs
#   --no-build     reuse the .stringsdata of an earlier build in the derived data folder
# Exit codes: 0 in sync (or synced), 1 catalogs differ (--check), 2 build or tool failure

set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

REPO_ROOT="${0:A:h:h}"
APP_DIR="$REPO_ROOT/app"
DERIVED="$HOME/Library/Developer/Tagwerk/DerivedData-tests"
DESTINATION='platform=iOS Simulator,name=iPhone 18 Pro'
CHECK=0
BUILD=1

while (( $# > 0 )); do
  case "$1" in
    --check) CHECK=1 ;;
    --no-build) BUILD=0 ;;
    --derived-data) shift; DERIVED="$1" ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if (( BUILD )); then
  if ! xcodebuild build-for-testing -project "$APP_DIR/Tagwerk.xcodeproj" -scheme Tagwerk -destination "$DESTINATION" \
      -derivedDataPath "$DERIVED" > "$WORK/build.log" 2>&1; then
    tail -n 20 "$WORK/build.log" >&2
    exit 2
  fi
fi

# Syncs one catalog with the given .stringsdata files; in check mode into a copy that is compared afterwards.
sync_catalog() {
  local catalog="$1"; shift
  local target="$catalog"
  if (( CHECK )); then
    # The file name is the table name, so the copy keeps it.
    local folder="$WORK/check/${${catalog:h}//\//_}"
    mkdir -p "$folder"
    target="$folder/${catalog:t}"
    cp "$catalog" "$target"
  fi
  local arguments=()
  for file in "$@"; do arguments+=(--stringsdata "$file"); done
  # A package without String(localized:) yet has nothing to sync.
  (( ${#arguments} > 0 )) || return 0
  xcrun xcstringstool sync "$target" "${arguments[@]}" >/dev/null
  if (( CHECK )) && ! /usr/bin/python3 "$REPO_ROOT/scripts/check-strings.py" --same "$catalog" "$target"; then
    DIFFERENT=1
  fi
}

DIFFERENT=0
INTERMEDIATES="$DERIVED/Build/Intermediates.noindex/Tagwerk.build"

for target in Tagwerk TagwerkWidget; do
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
  out="$WORK/extract-$name"
  mkdir -p "$out"
  xcrun xcstringstool extract --modern-localizable-strings $package_dir/Sources/$name/**/*.swift --output-directory "$out" >/dev/null
  sync_catalog "$catalog" "$out"/*.stringsdata(N)
done

if (( CHECK && DIFFERENT )); then
  echo "String Catalogs are out of date: run scripts/sync-strings.sh and add the new texts." >&2
  exit 1
fi
