#!/bin/zsh
# CI only: stops the test processes that a hung or cancelled test step left behind and packs the logs and result bundles into one
# tar.gz archive for the artifact upload.
#
# After a step timeout or a cancelled run, xcodebuild, the UI test runner, the hang sampler and the helpers of Xcode (DTServiceHub)
# keep running as orphans. They keep writing into the log folder while actions/upload-artifact zips it, which made the upload of a
# hung run fail with a zip error. The processes are stopped first, then the folders are packed into a single file that nothing
# writes to any more.
#
# Usage: scripts/ci-collect-artifacts.sh [--force] [--kill-pattern REGEX] ARCHIVE FOLDER...  (absolute paths)
#   ARCHIVE         the tar.gz file to create (its folder must exist)
#   FOLDER          log folder, result folder, ...; folders that do not exist are skipped
#   --force         stop the processes also outside GitHub Actions (without it, they are only stopped when GITHUB_ACTIONS is set,
#                   so a developer machine is never touched; the runner of a job is a machine of its own)
#   --kill-pattern  regular expression for the command lines of the processes to stop (default: the test processes)
# Writes "diagnostics=true" to $GITHUB_OUTPUT when the folders contain diagnostics of a hang (hang-*, watchdog-*).
# Always exits 0 when the archive was written: this is a cleanup step, it must not hide the result of the test step.
set -u

force=""
kill_pattern='app/test-all\.sh|ui-watchdog\.py|ui-hang-sampler\.py|xcodebuild|xctest|Tagwerk\.app/Tagwerk|TagwerkUITests-Runner|DTServiceHub'
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --force) force=1; shift ;;
    --kill-pattern) kill_pattern="$2"; shift 2 ;;
    *) echo "Unknown option $1" >&2; exit 64 ;;
  esac
done
if (( $# < 2 )); then
  echo "Usage: ci-collect-artifacts.sh [--force] [--kill-pattern REGEX] ARCHIVE FOLDER..." >&2
  exit 64
fi
archive="$1"; shift

# Process ids of this script and its parents must survive: the step shell and the runner match no pattern, but be explicit.
protected_pids() {
  local pid=$$
  while [[ -n "$pid" && "$pid" != 0 && "$pid" != 1 ]]; do
    print -r -- "$pid"
    pid=$(ps -o ppid= -p "$pid" 2> /dev/null | tr -d ' ')
  done
}

matching_pids() {
  local protected=(${(f)"$(protected_pids)"}) pid
  for pid in $(pgrep -f "$kill_pattern" 2> /dev/null || true); do
    (( ${protected[(Ie)$pid]} )) || print -r -- "$pid"
  done
}

if [[ -n "$force" || -n "${GITHUB_ACTIONS:-}" ]]; then
  leftovers=(${(f)"$(matching_pids)"})
  if (( ${#leftovers} > 0 )); then
    echo "Stopping ${#leftovers} leftover test process(es):"
    ps -o pid=,command= -p "${(j:,:)leftovers}" 2> /dev/null | cut -c1-160 | sed 's/^/  /'
    # Booted simulators go first: their processes (app, runner, testmanagerd) end with them. On a CI runner only this job uses them.
    if [[ -z "${GITHUB_ACTIONS:-}" ]]; then :; else
      for udid in $(xcrun simctl list devices booted -j 2> /dev/null | /usr/bin/python3 -c '
import json, sys
try:
    for devices in json.load(sys.stdin)["devices"].values():
        for device in devices:
            print(device["udid"])
except ValueError:
    pass'); do
        echo "  shutting down simulator $udid"
        xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
      done
    fi
    kill -TERM "${leftovers[@]}" 2> /dev/null || true
    sleep 5
    survivors=(${(f)"$(matching_pids)"})
    if (( ${#survivors} > 0 )); then
      echo "  ${#survivors} process(es) ignored TERM, sending KILL"
      kill -KILL "${survivors[@]}" 2> /dev/null || true
      sleep 1
    fi
  else
    echo "No leftover test processes."
  fi
else
  echo "Not on GitHub Actions: leftover processes are not stopped (use --force)."
fi

existing=() diagnostics=false
for folder in "$@"; do
  [[ -d "$folder" ]] || continue
  existing+=("$folder")
  if [[ -n "$(find "$folder" -maxdepth 2 \( -name 'hang-*' -o -name 'watchdog-*' \) -print -quit 2> /dev/null)" ]]; then
    diagnostics=true
  fi
done
if (( ${#existing} == 0 )); then
  echo "No folder to pack."
  [[ -z "${GITHUB_OUTPUT:-}" ]] || echo "diagnostics=false" >> "$GITHUB_OUTPUT"
  rm -f "$archive"
  exit 0
fi

# tar exits with 1 when a file changed while it was read; the archive is still usable then.
tar_status=0
relative_folders=()
for folder in "${existing[@]}"; do relative_folders+=("${folder#/}"); done
tar -czf "$archive" -C / "${relative_folders[@]}" 2> "$archive.errors" || tar_status=$?
if (( tar_status > 1 )); then
  echo "tar failed with status $tar_status:" >&2
  cat "$archive.errors" >&2
fi
rm -f "$archive.errors"
echo "Packed ${existing[*]} into $archive ($(du -h "$archive" 2> /dev/null | cut -f1))"
[[ -z "${GITHUB_OUTPUT:-}" ]] || echo "diagnostics=$diagnostics" >> "$GITHUB_OUTPUT"
exit 0
