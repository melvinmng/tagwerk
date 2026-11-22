#!/bin/zsh
# Registers the git merge drivers for the String Catalogs and scripts/translations/en.json in the local repository config.
#
# .gitattributes assigns the drivers (merge=xcstrings, merge=translationsjson); the commands live in the repository
# config, which git never takes over from a clone, so every clone runs this script once. Worktrees share the config of
# their repository: one run covers the main checkout and every worktree. Running it again rewrites the same values.
# Nothing else depends on it: a clone without the drivers merges these files as text, as before.
#
# Usage: scripts/setup-git-merge-drivers.sh [--unset]
#   --unset   removes the driver entries again
# The driver itself is scripts/merge-xcstrings.py; git runs it from the top of the checkout that merges.

set -euo pipefail

REPO_ROOT="${0:A:h:h}"
cd "$REPO_ROOT"

PYTHON=/usr/bin/python3
DRIVER_SCRIPT="scripts/merge-xcstrings.py"

if [[ "${1:-}" == "--unset" ]]; then
  for driver in xcstrings translationsjson; do
    git config --local --remove-section "merge.$driver" 2>/dev/null || true
  done
  echo "Removed the merge drivers xcstrings and translationsjson from the local git config."
  exit 0
elif [[ $# -gt 0 ]]; then
  echo "usage: scripts/setup-git-merge-drivers.sh [--unset]" >&2
  exit 2
fi

[[ -f "$DRIVER_SCRIPT" ]] || { echo "error: $DRIVER_SCRIPT not found in $REPO_ROOT" >&2; exit 1; }

git config --local merge.xcstrings.name "Tagwerk String Catalog (key-level three-way merge)"
git config --local merge.xcstrings.driver "$PYTHON $DRIVER_SCRIPT --marker-size %L %O %A %B %P"
git config --local merge.translationsjson.name "Tagwerk translations en.json (key-level three-way merge)"
git config --local merge.translationsjson.driver "$PYTHON $DRIVER_SCRIPT --format ordered-json --marker-size %L %O %A %B %P"

echo "Registered the merge drivers in $(git rev-parse --git-common-dir)/config:"
git config --local --get-regexp '^merge\.(xcstrings|translationsjson)\.' | sed 's/^/  /'
