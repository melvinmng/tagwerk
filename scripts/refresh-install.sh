#!/bin/zsh
# Rebuilds the Tagwerk app with a fresh free-team provisioning profile and installs it
# on the iPhone before the 7-day profile expires. Intended to run hourly via launchd.
#
# Usage: refresh-install.sh [--dry-run] [--force]
#   --dry-run  only report profile expiry, due state, device reachability and signing identity
#   --force    install now, regardless of the remaining profile lifetime
#   TAGWERK_FORCE=1 in the environment has the same effect as --force
#
# Exit codes: 0 installed or not due, 1 build failed, 2 device unreachable or install failed, 3 signing failed,
#             4 new state failed to build or sign and the last good commit was reinstalled instead,
#             64 configuration invalid
#
# State files in $STATE_DIR (suffix: bundle ID):
#   profile-expiry.<bundle>    earliest expiry epoch of the app and extension profiles of the installed build
#   last-good-commit.<bundle>  commit of the last successful refresh install
#   last-installed.<bundle>    commit currently on the device ("dev" after scripts/install-dev.sh, state unknown)

set -u

SCHEME="Tagwerk"
PROJECT_DIR_NAME="app"
BRANCH="${TAGWERK_BRANCH:-main}"
DUE_WITHIN_SECONDS=$(( 3 * 86400 ))   # refresh when less than 3 days of profile lifetime remain
WARN_WITHIN_SECONDS=$(( 2 * 86400 ))  # notify about failures when less than 2 days remain

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

  set_aside_cached_profiles

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

if (( dry_run == 1 )); then
  if [[ -n "$expiry" ]]; then echo "profile expires: $(format_epoch "$expiry")"; else echo "profile expires: unknown"; fi
  echo "due: $due"
  if device_reachable; then echo "device: reachable"; else echo "device: unreachable"; fi
  if signing_identity_present; then echo "signing identity: present"; else echo "signing identity: missing"; fi
  exit 0
fi

[[ "$due" == "yes" ]] || exit 0

device_reachable || fail 2 "device: unreachable" "App läuft bald ab: iPhone ins gleiche WLAN bringen und Mac wach lassen."

if [[ "${TAGWERK_REEXECED:-0}" != "1" ]]; then
  log "refresh: starting (branch $BRANCH)"

  { git -C "$SRC" fetch -q origin "$BRANCH" && git -C "$SRC" checkout -q "$BRANCH" && git -C "$SRC" merge -q --ff-only "origin/$BRANCH"; } \
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
  log "refresh: restarted with the updated script"
fi

head_commit=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
last_good=$(cat "$LAST_GOOD_FILE" 2>/dev/null || true)
last_installed=$(cat "$LAST_INSTALLED_FILE" 2>/dev/null || true)

attempt_install "$SRC" "$DERIVED" "$BUILD_LOG"
attempt_status=$?

# Without an account the fallback cannot renew the profile either; it would only install older code.
# The notice comes at once instead of only near expiry, at most every 12 hours.
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
  fallback_target=$(fallback_commit "$last_good" "$last_installed" "$head_commit")
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
  fail "$attempt_status" "" "$attempt_notice"
fi

(( attempt_status == 0 )) || fail "$attempt_status" "$attempt_message" "$attempt_notice"

compute_installed_expiry "$attempt_app_path"
[[ -n "$computed_expiry" ]] && print -r -- "$computed_expiry" > "$EXPIRY_FILE"
rm -f -- "$ACCOUNT_NOTICE_FILE"

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
