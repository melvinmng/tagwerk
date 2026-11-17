#!/bin/zsh
# Rebuilds the Tagwerk app with a fresh free-team provisioning profile and installs it
# on the iPhone before the 7-day profile expires. Intended to run hourly via launchd.
#
# Usage: refresh-install.sh [--dry-run] [--force]
#   --dry-run  only report profile expiry, due state, device reachability and signing identity
#   --force    install now, regardless of the remaining profile lifetime
#   TAGWERK_FORCE=1 in the environment has the same effect as --force
#
# Exit codes: 0 installed or not due, 1 build failed, 2 device unreachable, 3 signing failed

set -u

SCHEME="TagwerkSpike"
BUNDLE_ID="com.melvinmng.tagwerk.spike"
PROJECT_DIR_NAME="spike"
BRANCH="${TAGWERK_BRANCH:-main}"
DUE_WITHIN_SECONDS=$(( 3 * 86400 ))   # refresh when less than 3 days of profile lifetime remain
WARN_WITHIN_SECONDS=$(( 2 * 86400 ))  # notify about failures when less than 2 days remain

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

BASE="$HOME/Library/Developer/Tagwerk"
SRC="$BASE/src"
DERIVED="$BASE/DerivedData-refresh"
STATE_DIR="$HOME/Library/Application Support/Tagwerk"
CONFIG_FILE="$STATE_DIR/config"
EXPIRY_FILE="$STATE_DIR/profile-expiry"
LOG_DIR="$HOME/Library/Logs/Tagwerk"
LOG="$LOG_DIR/refresh.log"
BUILD_LOG="$LOG_DIR/build.log"
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

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

[[ "${TAGWERK_SOURCE_ONLY:-0}" == "1" ]] && return 0

# --- Runtime ---

mkdir -p "$STATE_DIR" "$LOG_DIR"

# Device identifiers stay out of the repository; the config file defines DEVICE_ID.
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing $CONFIG_FILE with DEVICE_ID=<UDID> (see scripts/README.md)" >&2
  exit 64
fi
source "$CONFIG_FILE"
: "${DEVICE_ID:?DEVICE_ID must be set in $CONFIG_FILE}"

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

# fail <exit code> <log message> <notification text>: every failure notifies once the profile is close to expiry.
fail() {
  log "$2"
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
# soon after the install. Removing the cached profiles of this app forces a new 7-day profile.
remove_cached_profiles() {
  local file plist app
  for file in "$PROFILES_DIR"/*.mobileprovision(N); do
    plist=$(/usr/bin/security cms -D -i "$file" 2>/dev/null) || continue
    app=$(print -r -- "$plist" | /usr/bin/plutil -extract Entitlements.application-identifier raw - 2>/dev/null)
    [[ "$app" == *".$BUNDLE_ID" ]] || continue
    rm -f -- "$file" && log "profile: removed cached profile $(basename "$file")"
  done
}

embedded_profile_expiry() {
  local raw
  raw=$(/usr/bin/security cms -D -i "$1/embedded.mobileprovision" 2>/dev/null | /usr/bin/plutil -extract ExpirationDate raw - 2>/dev/null) || return 1
  /bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$raw" '+%s'
}

due=$(is_due "$expiry" "$now")
(( force == 1 )) && due=yes

if (( dry_run == 1 )); then
  if [[ -n "$expiry" ]]; then echo "profile expires: $(/bin/date -r "$expiry" '+%Y-%m-%d %H:%M')"; else echo "profile expires: unknown"; fi
  echo "due: $due"
  if device_reachable; then echo "device: reachable"; else echo "device: unreachable"; fi
  if signing_identity_present; then echo "signing identity: present"; else echo "signing identity: missing"; fi
  exit 0
fi

[[ "$due" == "yes" ]] || exit 0

device_reachable || fail 2 "device: unreachable" "App läuft bald ab: iPhone ins gleiche WLAN bringen und Mac wach lassen."

log "refresh: starting (branch $BRANCH)"

{ git -C "$SRC" fetch -q origin "$BRANCH" && git -C "$SRC" checkout -q "$BRANCH" && git -C "$SRC" merge -q --ff-only "origin/$BRANCH"; } \
  || fail 1 "build: git update failed" "Neuinstallation fehlgeschlagen (Git). Details: ~/Library/Logs/Tagwerk/refresh.log"

( cd "$SRC/$PROJECT_DIR_NAME" && xcodegen -q ) \
  || fail 1 "build: xcodegen failed" "Neuinstallation fehlgeschlagen (XcodeGen). Details im Log."

remove_cached_profiles

if ! xcodebuild -project "$SRC/$PROJECT_DIR_NAME/$SCHEME.xcodeproj" -scheme "$SCHEME" \
    -destination "id=$DEVICE_ID" -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates build > "$BUILD_LOG" 2>&1; then
  if grep -qE "error: .*([Pp]rovisioning|[Ss]igning|certificate)" "$BUILD_LOG"; then
    fail 3 "build: signing failed (see $BUILD_LOG)" "Signierung fehlgeschlagen: Xcode öffnen und Apple-ID-Anmeldung prüfen."
  fi
  fail 1 "build: failed (see $BUILD_LOG)" "Neuinstallation fehlgeschlagen (Build). Details im Log."
fi

APP_PATH="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" >> "$BUILD_LOG" 2>&1 \
  || fail 2 "install: failed (see $BUILD_LOG)" "Installation auf dem iPhone fehlgeschlagen. Details im Log."

new_expiry=$(embedded_profile_expiry "$APP_PATH") || new_expiry=""
[[ -n "$new_expiry" ]] && print -r -- "$new_expiry" > "$EXPIRY_FILE"
log "install: ok (profile expires $([[ -n "$new_expiry" ]] && /bin/date -r "$new_expiry" '+%Y-%m-%d %H:%M' || echo unknown))"
exit 0
