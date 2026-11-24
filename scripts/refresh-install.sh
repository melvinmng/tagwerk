#!/bin/zsh
# Keeps the Tagwerk app on the iPhone current. Intended to run hourly via launchd.
# Every run installs a fresh build in one of two cases:
#   1. Profile refresh: the free-team provisioning profile (7 days) expires within 3 days or its expiry is unknown.
#   2. New commit: origin/main has a commit that is not on the device (see should_install for the exact rule).
# Otherwise the run ends after a cheap "git fetch" without checkout or build.
#
# Usage: refresh-install.sh [--dry-run] [--force]
#   --dry-run  only report profile expiry, due state, the install decision (from the last fetched origin/main,
#              without fetching), load average, device reachability and signing identity
#   --force    install now, regardless of the remaining profile lifetime and of the installed commit
#   TAGWERK_FORCE=1 in the environment has the same effect as --force
#
# Install decision (should_install), evaluated after the fetch:
#   - profile due (or --force)                          -> install
#   - origin/main equals the commit on the device       -> nothing to do
#   - origin/main equals the last failed commit         -> skip until origin/main changes (no hourly retry)
#   - device state unknown ("dev" after scripts/install-dev.sh, or no marker)
#       -> install only if origin/main differs from last-good-commit; a dev build therefore stays on the phone
#          until main moves on (or the profile is due, or --force is used)
#   - otherwise (a different commit is on the device)   -> install
# Skips that do not install (logged, never notified): 5-minute load average above LOAD_SKIP_PER_CPU x CPU count
# while the profile is not due; device unreachable or fetch failed while the profile is not due (logged once per
# episode). Notifications only for a failed install of a new commit, near profile expiry, and for the fallback.
#
# Exit codes: 0 installed, nothing to do or skipped, 1 build failed, 2 device unreachable or install failed,
#             3 signing failed, 4 new state failed to build or sign and the last good commit was reinstalled instead
#             (only when the profile was due), 64 configuration invalid
#
# State files in $STATE_DIR (suffix: bundle ID):
#   profile-expiry.<bundle>    earliest expiry epoch of the app and extension profiles of the installed build
#   last-good-commit.<bundle>  commit of the last successful refresh install
#   last-installed.<bundle>    commit currently on the device ("dev" after scripts/install-dev.sh, state unknown)
#   last-failed-commit.<bundle> commit whose build or signing failed last; removed after the next successful install
#   skip-note.<bundle>         reason of the last quiet skip, so a repeating reason is logged only once
#   account-notice.<bundle>    epoch of the last "Apple ID missing" notification

set -u

SCHEME="Tagwerk"
PROJECT_DIR_NAME="app"
BRANCH="${TAGWERK_BRANCH:-main}"
DUE_WITHIN_SECONDS=$(( 3 * 86400 ))   # refresh when less than 3 days of profile lifetime remain
WARN_WITHIN_SECONDS=$(( 2 * 86400 ))  # notify about failures when less than 2 days remain
LOAD_SKIP_PER_CPU=3                   # skip a run when the 5-minute load average exceeds this many times the CPU count

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

BASE="$HOME/Library/Developer/Tagwerk"
SRC="$BASE/src"
DERIVED="$BASE/DerivedData-refresh"
STATE_DIR="$HOME/Library/Application Support/Tagwerk"
LOG_DIR="$HOME/Library/Logs/Tagwerk"
LOG="$LOG_DIR/refresh.log"
BUILD_LOG="$LOG_DIR/build.log"
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
PROFILES_ASIDE_DIR="$BASE/profiles-aside"

# --- Decision functions (unit-tested in scripts/tests/refresh-decisions.zsh) ---

# is_due <profile expiry epoch or empty> <now epoch> -> yes|no
is_due() {
  [[ -z "$1" ]] && { print yes; return; }
  (( $1 - $2 < DUE_WITHIN_SECONDS )) && print yes || print no
}

# should_warn <profile expiry epoch or empty> <now epoch> -> yes|no
should_warn() {
  [[ -z "$1" ]] && { print yes; return; }
  (( $1 - $2 < WARN_WITHIN_SECONDS )) && print yes || print no
}

# should_install <due> <remote head> <last installed> <last good> <last failed> -> yes|no
# Decides whether this run builds and installs. <due> is the profile-refresh state (yes|no, yes with --force).
# <last installed> is "dev" or empty when the device state is unknown (scripts/install-dev.sh, missing marker).
should_install() {
  local due="$1" head="$2" last_installed="$3" last_good="$4" last_failed="$5"
  [[ "$due" == "yes" ]] && { print yes; return; }
  [[ -n "$head" ]] || { print no; return; }
  [[ "$head" == "$last_failed" ]] && { print no; return; }
  [[ "$head" == "$last_installed" ]] && { print no; return; }
  if [[ -z "$last_installed" || "$last_installed" == "dev" ]]; then
    # Unknown device state: install origin/main unless it is the commit the last refresh install already put on the phone.
    [[ "$head" == "$last_good" ]] && print no || print yes
    return
  fi
  print yes
}

# load_average_5min <raw output of "sysctl -n vm.loadavg"> -> 5-minute load average with a dot as decimal
# separator ("{ 1.52 1.80 1.90 }" -> 1.80), or empty output if it cannot be parsed.
load_average_5min() {
  local -a fields
  local value
  fields=(${=1})
  value="${fields[3]:-}"
  value="${value//,/.}"
  [[ "$value" =~ '^[0-9]+(\.[0-9]+)?$' ]] && print -r -- "$value"
  return 0
}

# should_skip_for_load <due> <5-minute load average> <CPU count> -> yes|no
# A due profile refresh is never postponed; unreadable load data never blocks a run.
should_skip_for_load() {
  local due="$1" load="$2" cpus="$3"
  [[ "$due" == "yes" ]] && { print no; return; }
  [[ "$load" =~ '^[0-9]+(\.[0-9]+)?$' && "$cpus" == <-> ]] || { print no; return; }
  (( cpus > 0 )) || { print no; return; }
  (( load > LOAD_SKIP_PER_CPU * cpus )) && print yes || print no
}

# is_tagwerk_profile <application-identifier> <team> <bundle> -> yes|no
# yes for exactly <team>.<bundle> (app) and <team>.<bundle>.<suffix> (extensions such as .widget).
is_tagwerk_profile() {
  local identifier="$1" team="$2" bundle="$3"
  [[ -n "$identifier" && -n "$team" && -n "$bundle" ]] || { print no; return; }
  local prefix="$team.$bundle"
  if [[ "$identifier" == "$prefix" || "$identifier" == "$prefix".?* ]]; then print yes; else print no; fi
}

# earliest_expiry <epoch>... -> smallest epoch; empty output if there is no argument or any argument is
# empty or not a number (unknown expiry must never be reported more optimistically than it may be).
earliest_expiry() {
  local earliest="" value
  (( $# > 0 )) || return 0
  for value in "$@"; do
    [[ "$value" == <-> ]] || return 0
    if [[ -z "$earliest" ]] || (( value < earliest )); then earliest="$value"; fi
  done
  print -r -- "$earliest"
}

# fallback_commit <last good commit> <last installed marker> <current HEAD> -> commit to reinstall, or empty.
# Allowed only if the last good commit is known, is what is installed on the device, and differs from HEAD.
fallback_commit() {
  local last_good="$1" last_installed="$2" current_head="$3"
  if [[ -n "$last_good" && "$last_installed" == "$last_good" && "$last_good" != "$current_head" ]]; then
    print -r -- "$last_good"
  fi
  return 0
}

# Signing related build errors, including those of the widget extension (profile, App Group entitlement).
SIGNING_ERROR_PATTERN='error: .*([Pp]rovisioning|[Pp]rofile|[Ss]igning|[Cc]ertificate|[Ee]ntitlement|application-groups|App Group|TagwerkWidget.*(sign|profile|group))|Command CodeSign failed'

# build_log_has_signing_error <build log> -> yes|no
# Compiler errors ("<file>.swift:<line>:<col>: error: ...") never count, even when they name a profile or a group.
build_log_has_signing_error() {
  if [[ -r "$1" ]] && grep -vE '\.swift:[0-9]+:[0-9]+: error:' "$1" | grep -qE "$SIGNING_ERROR_PATTERN"; then print yes; else print no; fi
}

# build_log_missing_account <build log> -> yes|no
# Xcode reports "No Accounts" or "No Account for Team" when the Apple ID is missing from Xcode › Settings › Accounts.
build_log_missing_account() {
  if [[ -r "$1" ]] && grep -vE '\.swift:[0-9]+:[0-9]+: error:' "$1" | grep -qE 'error: No Accounts?( for Team|:)'; then
    print yes
  else
    print no
  fi
}

NOTICE_REPEAT_SECONDS=$(( 12 * 3600 ))

# should_repeat_notice <epoch of the last notice or empty> <now epoch> -> yes|no
should_repeat_notice() {
  [[ "$1" == <-> ]] || { print yes; return; }
  (( $2 - $1 >= NOTICE_REPEAT_SECONDS )) && print yes || print no
}

# restore_profiles <aside dir> <profiles dir>: moves profiles set aside before a build back.
# A profile of the same name that Xcode created meanwhile is newer and stays; the set-aside copy is dropped.
restore_profiles() {
  local aside="$1" target="$2" file
  [[ -d "$aside" ]] || return 0
  mkdir -p "$target"
  for file in "$aside"/*.mobileprovision(N); do
    if [[ -e "$target/${file:t}" ]]; then rm -f -- "$file"; else mv -f -- "$file" "$target/"; fi
  done
  return 0
}

[[ "${TAGWERK_SOURCE_ONLY:-0}" == "1" ]] && return 0

# --- Runtime ---

mkdir -p "$STATE_DIR" "$LOG_DIR"

source "${0:A:h}/install-config.zsh" || exit 64
EXPIRY_FILE="$STATE_DIR/profile-expiry.$TAGWERK_BUNDLE_ID"
LAST_GOOD_FILE="$STATE_DIR/last-good-commit.$TAGWERK_BUNDLE_ID"
LAST_INSTALLED_FILE="$STATE_DIR/last-installed.$TAGWERK_BUNDLE_ID"
ACCOUNT_NOTICE_FILE="$STATE_DIR/account-notice.$TAGWERK_BUNDLE_ID"
LAST_FAILED_FILE="$STATE_DIR/last-failed-commit.$TAGWERK_BUNDLE_ID"
SKIP_NOTE_FILE="$STATE_DIR/skip-note.$TAGWERK_BUNDLE_ID"
FALLBACK_DIR="$BASE/fallback"
FALLBACK_DERIVED="$BASE/DerivedData-fallback"
FALLBACK_BUILD_LOG="$LOG_DIR/build-fallback.log"

dry_run=0
force=0
[[ "${TAGWERK_FORCE:-0}" == "1" ]] && force=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    --force) force=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 64 ;;
  esac
done

log() { print -r -- "$(date '+%Y-%m-%dT%H:%M:%S') $*" | tee -a "$LOG"; }

notify() {
  /usr/bin/osascript -e "display notification \"$1\" with title \"Tagwerk\"" >/dev/null 2>&1 || true
}

now=$(/bin/date '+%s')
expiry=$(cat "$EXPIRY_FILE" 2>/dev/null || true)
last_good=$(cat "$LAST_GOOD_FILE" 2>/dev/null || true)
last_installed=$(cat "$LAST_INSTALLED_FILE" 2>/dev/null || true)
last_failed=$(cat "$LAST_FAILED_FILE" 2>/dev/null || true)

# Cached profiles are only set aside (forcing fresh 7-day profiles) for a profile refresh; an install of a new
# commit while the profile is still valid reuses the cached profile and leaves the expiry untouched.
RENEW_PROFILES=1

# note_skip <reason>: logs a quiet skip, but only if the previous run skipped for a different reason.
note_skip() {
  [[ "$(cat "$SKIP_NOTE_FILE" 2>/dev/null || true)" == "$1" ]] || log "skip: $1"
  print -r -- "$1" > "$SKIP_NOTE_FILE"
}

clear_skip_note() { rm -f -- "$SKIP_NOTE_FILE"; }

# fail <exit code> <log message or empty> <notification text>: every failure notifies once the profile is close to expiry.
fail() {
  [[ -n "$2" ]] && log "$2"
  if [[ "$(should_warn "$expiry" "$now")" == "yes" ]]; then
    notify "$3"
  fi
  exit "$1"
}

device_reachable() {
  # Opening a device info session establishes the tunnel (wired or Wi-Fi) if the device is reachable.
  xcrun devicectl device info details --device "$DEVICE_ID" --timeout 30 >/dev/null 2>&1
}

signing_identity_present() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"
}

# Xcode reuses a cached profile while it is valid, which would embed a profile that expires
# soon after the install. Setting the cached profiles of the app and its extensions aside forces new 7-day profiles.
# They are only set aside, not deleted: after a failed build they come back (restore_profiles), so a missing
# Xcode account does not also take away the profiles that scripts/install-dev.sh can still sign with.
set_aside_cached_profiles() {
  local file plist app
  restore_profiles "$PROFILES_ASIDE_DIR" "$PROFILES_DIR"
  mkdir -p "$PROFILES_ASIDE_DIR"
  for file in "$PROFILES_DIR"/*.mobileprovision(N); do
    plist=$(/usr/bin/security cms -D -i "$file" 2>/dev/null) || continue
    app=$(print -r -- "$plist" | /usr/bin/plutil -extract Entitlements.application-identifier raw - 2>/dev/null)
    [[ "$(is_tagwerk_profile "$app" "$DEVELOPMENT_TEAM" "$TAGWERK_BUNDLE_ID")" == "yes" ]] || continue
    mv -f -- "$file" "$PROFILES_ASIDE_DIR/" && log "profile: set cached profile aside"
  done
}

discard_set_aside_profiles() {
  [[ -n "$PROFILES_ASIDE_DIR" && -d "$PROFILES_ASIDE_DIR" ]] || return 0
  rm -f -- "$PROFILES_ASIDE_DIR"/*.mobileprovision(N)
}

embedded_profile_expiry() {
  local raw
  raw=$(/usr/bin/security cms -D -i "$1/embedded.mobileprovision" 2>/dev/null | /usr/bin/plutil -extract ExpirationDate raw - 2>/dev/null) || return 1
  /bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$raw" '+%s'
}

# compute_installed_expiry <app bundle>: sets computed_expiry to the earliest expiry of the app profile and all
# PlugIns/*.appex profiles, or to empty if any of them is unreadable (unknown).
# An unreadable profile is logged and notified, and the earliest readable expiry is kept: storing nothing would make
# every hourly run due and reinstall the app each hour.
compute_installed_expiry() {
  local app_path="$1" value appex
  local -a values readable
  value=$(embedded_profile_expiry "$app_path") || value=""
  values=("$value")
  for appex in "$app_path"/PlugIns/*.appex(N/); do
    value=$(embedded_profile_expiry "$appex") || { log "profile: cannot read expiry of $(basename "$appex")"; value=""; }
    values+=("$value")
  done
  computed_expiry=$(earliest_expiry "${values[@]}")
  if [[ -z "$computed_expiry" ]]; then
    readable=(${values:#})
    if (( ${#readable} > 0 )); then
      computed_expiry=$(earliest_expiry "${readable[@]}")
      notify "Ablaufdatum eines Profils ist unbekannt; Tagwerk nimmt das der App. Details im Log."
    fi
  fi
}

format_epoch() {
  if [[ -n "$1" ]]; then /bin/date -r "$1" '+%Y-%m-%d %H:%M'; else echo unknown; fi
}

# attempt_install <source root> <derived data path> <build log>
# Generates the project, builds, signs and installs. Returns 0 on success, 1 build/project generation failed,
# 2 installation on the device failed, 3 signing failed. Sets attempt_message, attempt_notice, attempt_app_path
# and attempt_account_missing (1 when Xcode has no account to sign with). Cached profiles set aside for the build
# are restored after any failure and dropped after a success.
attempt_install() {
  local result
  attempt_build_and_install "$@"
  result=$?
  if (( result == 0 )); then discard_set_aside_profiles; else restore_profiles "$PROFILES_ASIDE_DIR" "$PROFILES_DIR"; fi
  return $result
}

attempt_build_and_install() {
  local root="$1" derived="$2" build_log="$3"
  attempt_message="" attempt_notice="" attempt_app_path="" attempt_account_missing=0

  if ! ( cd "$root/$PROJECT_DIR_NAME" && xcodegen -q ); then
    attempt_message="build: xcodegen failed"
    attempt_notice="Neuinstallation fehlgeschlagen (XcodeGen). Details im Log."
    return 1
  fi

  if (( RENEW_PROFILES == 1 )); then
    set_aside_cached_profiles
  else
    restore_profiles "$PROFILES_ASIDE_DIR" "$PROFILES_DIR"
  fi

  if ! xcodebuild -project "$root/$PROJECT_DIR_NAME/$SCHEME.xcodeproj" -scheme "$SCHEME" \
      -destination "id=$DEVICE_ID" -derivedDataPath "$derived" \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      "${BUILD_SETTINGS[@]}" build > "$build_log" 2>&1; then
    if [[ "$(build_log_missing_account "$build_log")" == "yes" ]]; then
      attempt_account_missing=1
      attempt_message="build: signing failed, no account in Xcode (see $build_log)"
      if [[ -n "$expiry" ]]; then
        attempt_notice="Apple-ID fehlt in Xcode (Settings › Accounts). Ohne sie läuft die App am $(format_epoch "$expiry") ab."
      else
        attempt_notice="Apple-ID fehlt in Xcode (Settings › Accounts). Ohne sie lässt sich die App nicht verlängern."
      fi
      return 3
    fi
    if [[ "$(build_log_has_signing_error "$build_log")" == "yes" ]]; then
      attempt_message="build: signing failed (see $build_log)"
      attempt_notice="Signierung fehlgeschlagen: Xcode öffnen und Apple-ID-Anmeldung prüfen."
      return 3
    fi
    attempt_message="build: failed (see $build_log)"
    attempt_notice="Neuinstallation fehlgeschlagen (Build). Details im Log."
    return 1
  fi

  attempt_app_path="$derived/Build/Products/Debug-iphoneos/$SCHEME.app"
  if ! xcrun devicectl device install app --device "$DEVICE_ID" "$attempt_app_path" >> "$build_log" 2>&1; then
    attempt_message="install: failed (see $build_log)"
    attempt_notice="Installation auf dem iPhone fehlgeschlagen. Details im Log."
    return 2
  fi
  return 0
}

# Removes the fallback worktree and its registration. Never touches the checkout of $SRC.
cleanup_fallback_worktree() {
  git -C "$SRC" worktree remove --force "$FALLBACK_DIR" >/dev/null 2>&1 || true
  [[ -n "$FALLBACK_DIR" && "$FALLBACK_DIR" == "$BASE/fallback" ]] && rm -rf -- "$FALLBACK_DIR"
  git -C "$SRC" worktree prune >/dev/null 2>&1 || true
}

# run_fallback <commit>: builds and installs the given commit from a separate detached worktree.
# Returns 0 on success. On success the expiry file is updated from the installed fallback build;
# on failure it stays untouched. The worktree is always removed.
run_fallback() {
  local commit="$1" result=1
  cleanup_fallback_worktree
  if git -C "$SRC" worktree add -q --detach "$FALLBACK_DIR" "$commit" >> "$FALLBACK_BUILD_LOG" 2>&1; then
    attempt_install "$FALLBACK_DIR" "$FALLBACK_DERIVED" "$FALLBACK_BUILD_LOG"
    result=$?
    if (( result == 0 )); then
      compute_installed_expiry "$attempt_app_path"
      [[ -n "$computed_expiry" ]] && print -r -- "$computed_expiry" > "$EXPIRY_FILE"
      log "fallback: installed $commit (profile expires $(format_epoch "$computed_expiry"))"
    else
      log "fallback: failed with $attempt_message"
    fi
  else
    log "fallback: could not create worktree for $commit (see $FALLBACK_BUILD_LOG)"
  fi
  cleanup_fallback_worktree
  return $result
}

due=$(is_due "$expiry" "$now")
(( force == 1 )) && due=yes

remote_head=$(git -C "$SRC" rev-parse --verify -q "origin/$BRANCH^{commit}" 2>/dev/null || true)

if (( dry_run == 1 )); then
  load_5min=$(load_average_5min "$(/usr/sbin/sysctl -n vm.loadavg 2>/dev/null)")
  cpu_count=$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null || true)
  if [[ -n "$expiry" ]]; then echo "profile expires: $(format_epoch "$expiry")"; else echo "profile expires: unknown"; fi
  echo "due: $due"
  echo "origin/$BRANCH (last fetched, no fetch in dry run): ${remote_head:-unknown}"
  echo "installed on device: ${last_installed:-unknown}"
  echo "last good commit: ${last_good:-unknown}"
  echo "last failed commit: ${last_failed:-none}"
  echo "install decision: $(should_install "$due" "$remote_head" "$last_installed" "$last_good" "$last_failed")"
  echo "load (5 min): ${load_5min:-unknown}, CPUs: ${cpu_count:-unknown}, skip above ${LOAD_SKIP_PER_CPU} x CPUs: $(should_skip_for_load "$due" "$load_5min" "$cpu_count")"
  if device_reachable; then echo "device: reachable"; else echo "device: unreachable"; fi
  if signing_identity_present; then echo "signing identity: present"; else echo "signing identity: missing"; fi
  exit 0
fi

if [[ "${TAGWERK_REEXECED:-0}" != "1" ]]; then
  # Stage 1: cheap check. Only a fetch; checkout and build happen only if this run installs.
  if ! git -C "$SRC" fetch -q origin "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}" 2>> "$LOG"; then
    if [[ "$due" == "yes" ]]; then
      fail 1 "build: git update failed" "Neuinstallation fehlgeschlagen (Git). Details: ~/Library/Logs/Tagwerk/refresh.log"
    fi
    note_skip "git fetch failed, trying again next run"
    exit 0
  fi
  remote_head=$(git -C "$SRC" rev-parse --verify -q "origin/$BRANCH^{commit}" 2>/dev/null || true)

  if [[ "$(should_install "$due" "$remote_head" "$last_installed" "$last_good" "$last_failed")" != "yes" ]]; then
    clear_skip_note
    exit 0
  fi

  if [[ "$(should_skip_for_load "$due" "$(load_average_5min "$(/usr/sbin/sysctl -n vm.loadavg 2>/dev/null)")" "$(/usr/sbin/sysctl -n hw.logicalcpu 2>/dev/null)")" == "yes" ]]; then
    log "skip: load average above ${LOAD_SKIP_PER_CPU} x CPU count, trying again next run"
    exit 0
  fi

  if ! device_reachable; then
    [[ "$due" == "yes" ]] || { note_skip "device unreachable, trying again next run"; exit 0; }
    fail 2 "device: unreachable" "App läuft bald ab: iPhone ins gleiche WLAN bringen und Mac wach lassen."
  fi
  clear_skip_note

  if [[ "$due" == "yes" ]]; then
    install_reason="profile refresh"
  else
    install_reason="new commit ${remote_head[1,12]} (on device: ${last_installed[1,12]:-unknown})"
  fi
  log "refresh: starting (branch $BRANCH, $install_reason)"

  { git -C "$SRC" checkout -q "$BRANCH" && git -C "$SRC" merge -q --ff-only "origin/$BRANCH"; } \
    || fail 1 "build: git update failed" "Neuinstallation fehlgeschlagen (Git). Details: ~/Library/Logs/Tagwerk/refresh.log"

  # Continue with the freshly fetched script so that a changed version applies to this run.
  # TAGWERK_REEXECED prevents a second restart; a script that does not parse is not executed.
  new_script="$SRC/scripts/refresh-install.sh"
  if [[ -x "$new_script" ]] && /bin/zsh -n "$new_script" 2>/dev/null; then
    log "refresh: restarting with the updated script"
    export TAGWERK_REEXECED=1
    exec "$new_script" "$@"
  fi
  log "refresh: updated script not usable, continuing with the current one"
else
  # Stage 2: the decision to install was made by stage 1 (possibly by an older script that only ran when due).
  log "refresh: restarted with the updated script"
fi

[[ "$due" == "yes" ]] || RENEW_PROFILES=0

head_commit=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)

attempt_install "$SRC" "$DERIVED" "$BUILD_LOG"
attempt_status=$?

# Without an account the fallback cannot renew the profile either; it would only install older code.
# The notice comes at once instead of only near expiry, at most every 12 hours. The commit is not marked as failed:
# the cause is the missing account, so the next hourly run retries as soon as the account is back.
if (( attempt_account_missing == 1 )); then
  log "$attempt_message"
  last_notice=$(cat "$ACCOUNT_NOTICE_FILE" 2>/dev/null || true)
  if [[ "$(should_repeat_notice "$last_notice" "$now")" == "yes" ]]; then
    notify "$attempt_notice"
    print -r -- "$now" > "$ACCOUNT_NOTICE_FILE"
  fi
  exit 3
fi

# An install the device rejects (status 2 while the device is still reachable) gets the fallback too.
if (( attempt_status == 1 || attempt_status == 3 )) || { (( attempt_status == 2 )) && device_reachable; }; then
  log "$attempt_message"
  # Remember the failed commit so that the following hourly runs do not build it again until origin/main changes.
  [[ -n "$head_commit" ]] && print -r -- "$head_commit" > "$LAST_FAILED_FILE"
  fallback_target=""
  # The fallback reinstalls the last good commit with a fresh profile; without a due profile it would change nothing.
  [[ "$due" == "yes" ]] && fallback_target=$(fallback_commit "$last_good" "$last_installed" "$head_commit")
  if [[ "$fallback_target" =~ '^[0-9a-f]{7,64}$' ]]; then
    log "fallback: new state ${head_commit[1,12]} failed, reinstalling last good commit ${fallback_target[1,12]}"
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    trap cleanup_fallback_worktree EXIT
    if run_fallback "$fallback_target"; then
      log "fallback: done"
      notify "Neuer Stand ließ sich nicht installieren; der letzte funktionierende Stand wurde neu installiert. Details im Log."
      exit 4
    fi
  fi
  # A failed install of a new commit is reported once (the failed commit is not retried); near expiry fail() notifies.
  [[ "$due" == "yes" ]] || notify "$attempt_notice"
  fail "$attempt_status" "" "$attempt_notice"
fi

(( attempt_status == 0 )) || fail "$attempt_status" "$attempt_message" "$attempt_notice"

compute_installed_expiry "$attempt_app_path"
[[ -n "$computed_expiry" ]] && print -r -- "$computed_expiry" > "$EXPIRY_FILE"
rm -f -- "$ACCOUNT_NOTICE_FILE" "$LAST_FAILED_FILE"

# Remember the installed commit; without it the fallback must stay disabled.
if [[ -n "$head_commit" ]]; then
  print -r -- "$head_commit" > "$LAST_GOOD_FILE"
  print -r -- "$head_commit" > "$LAST_INSTALLED_FILE"
else
  log "state: could not determine the installed commit, fallback disabled"
  rm -f -- "$LAST_GOOD_FILE" "$LAST_INSTALLED_FILE"
fi

log "install: ok (profile expires $(format_epoch "$computed_expiry"))"
exit 0
