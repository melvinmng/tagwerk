#!/bin/zsh
# Builds the Tagwerk app from the current working tree and installs it on the iPhone.
# Signing settings and the device identifier are read from the local config file.
#
# Usage: scripts/install-dev.sh
# Exit codes: 0 installed, 1 build failed, 2 install failed, 64 configuration missing
# On success it sets last-installed.<bundle> to "dev", which disables the refresh fallback until the next refresh install.

set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

REPO_ROOT="${0:A:h:h}"
DERIVED="$HOME/Library/Developer/Tagwerk/DerivedData-dev"
LOG_DIR="$HOME/Library/Logs/Tagwerk"
STATE_DIR="$HOME/Library/Application Support/Tagwerk"
BUILD_LOG="$LOG_DIR/install-dev-build.log"
INSTALL_LOG="$LOG_DIR/install-dev-install.log"

source "$REPO_ROOT/scripts/install-config.zsh" || exit 64

mkdir -p "$LOG_DIR" "$STATE_DIR"

# Removes the device identifier from any text passed through the pipe.
redact_device_id() {
  sed "s/$DEVICE_ID/<device>/g"
}

echo "==> Generating Xcode project"
(cd "$REPO_ROOT/app" && xcodegen --quiet)

echo "==> Building for device (log: $BUILD_LOG)"
if ! xcodebuild -project "$REPO_ROOT/app/Tagwerk.xcodeproj" -scheme Tagwerk \
    -destination "id=$DEVICE_ID" -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    "${BUILD_SETTINGS[@]}" build 2>&1 | redact_device_id > "$BUILD_LOG"; then
  echo "Build failed. Last lines of the log:" >&2
  tail -n 20 "$BUILD_LOG" >&2
  exit 1
fi
grep -E "BUILD (SUCCEEDED|FAILED)" "$BUILD_LOG" || true

APP_PATH="$DERIVED/Build/Products/Debug-iphoneos/Tagwerk.app"

echo "==> Installing on device (log: $INSTALL_LOG)"
if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1 | redact_device_id > "$INSTALL_LOG"; then
  echo "Install failed. Last lines of the log:" >&2
  tail -n 10 "$INSTALL_LOG" >&2
  exit 2
fi
# The working tree is installed, so the installed commit is unknown to the refresh fallback.
print -r -- dev > "$STATE_DIR/last-installed.$TAGWERK_BUNDLE_ID"
echo "Install OK: Tagwerk is on the device."
