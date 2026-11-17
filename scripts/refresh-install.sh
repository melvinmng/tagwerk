#!/bin/zsh
# Rebuilds the Tagwerk app with a fresh free-team provisioning profile and installs it
# on the iPhone before the 7-day profile expires. Intended to run hourly via launchd.
#
# Usage: refresh-install.sh [--dry-run] [--force]
#   --dry-run  only report due state, device reachability and signing identity
#   --force    install even if the last install is less than REFRESH_AFTER_DAYS old
#   TAGWERK_FORCE=1 in the environment has the same effect as --force
#
# Exit codes: 0 installed or not due, 1 build failed, 2 device unreachable, 3 signing failed

set -u

SCHEME="TagwerkSpike"
PROJECT_DIR_NAME="spike"
BRANCH="${TAGWERK_BRANCH:-spike/feasibility}"
REFRESH_AFTER_DAYS=5
WARN_AFTER_DAYS=6

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

BASE="$HOME/Library/Developer/Tagwerk"
SRC="$BASE/src"
DERIVED="$BASE/DerivedData-refresh"
STATE_DIR="$HOME/Library/Application Support/Tagwerk"
STATE_FILE="$STATE_DIR/last-install"
LOG_DIR="$HOME/Library/Logs/Tagwerk"
LOG="$LOG_DIR/refresh.log"
BUILD_LOG="$LOG_DIR/build.log"

CONFIG_FILE="$STATE_DIR/config"

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

days_since_last_install() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo 999
    return
  fi
  local last now
  last=$(/bin/date -j -f '%Y-%m-%dT%H:%M:%S' "$(cat "$STATE_FILE")" '+%s' 2>/dev/null || echo 0)
  now=$(/bin/date '+%s')
  echo $(( (now - last) / 86400 ))
}

device_reachable() {
  # Opening a device info session establishes the tunnel (wired or Wi-Fi) if the device is reachable.
  xcrun devicectl device info details --device "$DEVICE_ID" --timeout 30 >/dev/null 2>&1
}

signing_identity_present() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"
}

age=$(days_since_last_install)
due=0
(( age >= REFRESH_AFTER_DAYS )) && due=1
(( force == 1 )) && due=1

if (( dry_run == 1 )); then
  echo "last install: $(cat "$STATE_FILE" 2>/dev/null || echo never) (${age} days ago)"
  echo "due: $([[ $due == 1 ]] && echo yes || echo no)"
  if device_reachable; then echo "device: reachable"; else echo "device: unreachable"; fi
  if signing_identity_present; then echo "signing identity: present"; else echo "signing identity: missing"; fi
  exit 0
fi

if (( due == 0 )); then
  exit 0
fi

if ! device_reachable; then
  log "device: unreachable (last install ${age} days ago)"
  if (( age >= WARN_AFTER_DAYS )); then
    notify "App läuft bald ab: iPhone ins gleiche WLAN bringen und Mac wach lassen."
  fi
  exit 2
fi

log "refresh: starting (last install ${age} days ago, branch $BRANCH)"

if ! git -C "$SRC" fetch -q origin "$BRANCH" || ! git -C "$SRC" checkout -q "$BRANCH" || ! git -C "$SRC" merge -q --ff-only "origin/$BRANCH"; then
  log "build: git update failed"
  exit 1
fi

( cd "$SRC/$PROJECT_DIR_NAME" && xcodegen -q ) || { log "build: xcodegen failed"; exit 1; }

if ! xcodebuild -project "$SRC/$PROJECT_DIR_NAME/$SCHEME.xcodeproj" -scheme "$SCHEME" \
    -destination "id=$DEVICE_ID" -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates build > "$BUILD_LOG" 2>&1; then
  if grep -qiE "provisioning profile|signing certificate|code ?sign" "$BUILD_LOG"; then
    log "build: signing failed (see $BUILD_LOG)"
    notify "Signierung fehlgeschlagen: Xcode öffnen und Apple-ID-Anmeldung prüfen."
    exit 3
  fi
  log "build: failed (see $BUILD_LOG)"
  exit 1
fi

APP_PATH="$DERIVED/Build/Products/Debug-iphoneos/$SCHEME.app"
if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" >> "$BUILD_LOG" 2>&1; then
  log "install: failed (see $BUILD_LOG)"
  exit 2
fi

/bin/date '+%Y-%m-%dT%H:%M:%S' > "$STATE_FILE"
log "install: ok"
exit 0
