#!/bin/zsh
# Unit tests for the decision functions of refresh-install.sh (run: zsh scripts/tests/refresh-decisions.zsh).
set -u
TAGWERK_SOURCE_ONLY=1 source "${0:A:h}/../refresh-install.sh"

failures=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1: expected '$2', got '$3'"; failures=$((failures + 1)); fi
}

now=1000000000
day=86400

# Due is derived from the installed profile's expiry, not from the install date.
check "no state is due"                   yes "$(is_due "" $now)"
check "6 days left is not due"            no  "$(is_due $((now + 6 * day)) $now)"
check "2 days left is due"                yes "$(is_due $((now + 2 * day)) $now)"
check "just under 3 days left is due"    yes "$(is_due $((now + 3 * day - 1)) $now)"
check "4 days left is not due"            no  "$(is_due $((now + 4 * day)) $now)"
check "expired is due"                    yes "$(is_due $((now - day)) $now)"

# Warnings depend on the remaining profile lifetime as well.
check "3 days left does not warn"         no  "$(should_warn $((now + 3 * day)) $now)"
check "1 day left warns"                  yes "$(should_warn $((now + day)) $now)"
check "no state warns"                    yes "$(should_warn "" $now)"

# The refresh still targets the real app.
check "builds the Tagwerk scheme"         Tagwerk "$SCHEME"
check "builds from app/"                  app "$PROJECT_DIR_NAME"

test_home=$(mktemp -d) || exit 1
trap 'rm -rf -- "$test_home"' EXIT
export HOME="$test_home"
mkdir -p "$HOME/Library/Application Support/Tagwerk"
cat > "$HOME/Library/Application Support/Tagwerk/config" <<'EOF'
DEVICE_ID=example-device
DEVELOPMENT_TEAM=ABCDE12345
TAGWERK_BUNDLE_ID=org.example.tagwerk
GITHUB_CLIENT_ID=example-client
EOF
source "${0:A:h}/../install-config.zsh" || exit 1
check "uses the local signing team"       DEVELOPMENT_TEAM=ABCDE12345 "${BUILD_SETTINGS[1]}"
check "uses the local bundle ID"          TAGWERK_BUNDLE_ID=org.example.tagwerk "${BUILD_SETTINGS[2]}"
check "uses the local GitHub client ID"   GITHUB_CLIENT_ID=example-client "${BUILD_SETTINGS[3]}"

echo 'DEVICE_ID=example-device' > "$CONFIG_FILE"
check "missing team fails locally"        64 "$(zsh -c 'source "$1"; print $?' _ "${0:A:h}/../install-config.zsh" 2>/dev/null)"
echo 'DEVELOPMENT_TEAM=ABCDE12345' >> "$CONFIG_FILE"
check "missing bundle ID fails locally"   64 "$(zsh -c 'source "$1"; print $?' _ "${0:A:h}/../install-config.zsh" 2>/dev/null)"

exit $(( failures > 0 ))
