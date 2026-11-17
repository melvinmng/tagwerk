# Loads the local configuration shared by both device installers.
CONFIG_FILE="$HOME/Library/Application Support/Tagwerk/config"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing $CONFIG_FILE. Follow the iPhone setup in the repository README." >&2
  return 64
fi
source "$CONFIG_FILE" || return 64

if [[ -z "${DEVICE_ID:-}" ]] || [[ ! "${DEVELOPMENT_TEAM:-}" =~ '^[A-Z0-9]{10}$' ]]; then
  echo "Set DEVICE_ID and a 10-character DEVELOPMENT_TEAM in $CONFIG_FILE." >&2
  return 64
fi

if [[ ! "${TAGWERK_BUNDLE_ID:-}" =~ '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$' ]]; then
  echo "Set a valid TAGWERK_BUNDLE_ID in $CONFIG_FILE." >&2
  return 64
fi

BUILD_SETTINGS=(
  "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
  "TAGWERK_BUNDLE_ID=$TAGWERK_BUNDLE_ID"
  "GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID:-}"
)
