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

# Cached profiles of the app and its widget extension are recognised exactly, not by prefix.
team=ABCDE12345
bundle=org.example.tagwerk
check "app profile matches"               yes "$(is_tagwerk_profile "$team.$bundle" $team $bundle)"
check "widget profile matches"            yes "$(is_tagwerk_profile "$team.$bundle.widget" $team $bundle)"
check "other suffix matches"              yes "$(is_tagwerk_profile "$team.$bundle.other" $team $bundle)"
check "watch app profile matches"         yes "$(is_tagwerk_profile "$team.$bundle.watchkitapp" $team $bundle)"
check "watch widget profile matches"      yes "$(is_tagwerk_profile "$team.$bundle.watchkitapp.widget" $team $bundle)"
check "lookalike watch widget no match"   no  "$(is_tagwerk_profile "$team.${bundle}x.watchkitapp.widget" $team $bundle)"
check "foreign bundle does not match"     no  "$(is_tagwerk_profile "$team.org.example.other" $team $bundle)"
check "prefix lookalike does not match"   no  "$(is_tagwerk_profile "$team.${bundle}x" $team $bundle)"
check "prefix lookalike widget no match"  no  "$(is_tagwerk_profile "$team.${bundle}x.widget" $team $bundle)"
check "other team does not match"         no  "$(is_tagwerk_profile "ZZZZZ99999.$bundle" $team $bundle)"
check "other team widget does not match"  no  "$(is_tagwerk_profile "ZZZZZ99999.$bundle.widget" $team $bundle)"
check "empty identifier does not match"   no  "$(is_tagwerk_profile "" $team $bundle)"
check "team only does not match"          no  "$(is_tagwerk_profile "$team" $team $bundle)"
check "trailing dot only does not match"  no  "$(is_tagwerk_profile "$team.$bundle." $team $bundle)"
check "dot in bundle is literal"          no  "$(is_tagwerk_profile "$team.orgXexample.tagwerk" $team $bundle)"

# The installed app carries profiles in the app, its extensions, the embedded watch app and the watch app's extension.
fake_app="$(mktemp -d)/Tagwerk.app"
mkdir -p "$fake_app/PlugIns/TagwerkWidget.appex" "$fake_app/PlugIns/TagwerkShare.appex" \
  "$fake_app/Watch/TagwerkWatch.app/PlugIns/TagwerkWatchWidget.appex"
bundles=("${(@f)$(installed_profile_bundles "$fake_app")}")
check "profile bundles: count"            5 "${#bundles}"
check "profile bundles: app first"        "$fake_app" "${bundles[1]}"
check "profile bundles: watch app listed" yes "$([[ "${bundles[(r)$fake_app/Watch/TagwerkWatch.app]}" == "$fake_app/Watch/TagwerkWatch.app" ]] && print yes || print no)"
check "profile bundles: watch widget listed" yes "$([[ "${bundles[(r)$fake_app/Watch/TagwerkWatch.app/PlugIns/TagwerkWatchWidget.appex]}" != "" ]] && print yes || print no)"
mkdir -p "${fake_app:h}/Plain.app"
check "profile bundles: plain app only"   1 "$(installed_profile_bundles "${fake_app:h}/Plain.app" | wc -l | tr -d ' ')"
rm -rf "${fake_app:h}"

# The earliest expiry of app and extension profiles decides; unknown input stays unknown.
check "earliest of three"                 100 "$(earliest_expiry 300 100 200)"
check "single value"                      500 "$(earliest_expiry 500)"
check "empty argument means unknown"      ""  "$(earliest_expiry 300 "" 200)"
check "only empty argument is unknown"    ""  "$(earliest_expiry "")"
check "no arguments is unknown"           ""  "$(earliest_expiry)"
check "non-numeric argument is unknown"   ""  "$(earliest_expiry 300 abc)"

# The fallback only targets a commit that is known to be installed and differs from the current state.
check "fallback to last good commit"      abc123 "$(fallback_commit abc123 abc123 def456)"
check "no fallback without last good"     ""  "$(fallback_commit "" "" def456)"
check "no fallback when dev build is on"  ""  "$(fallback_commit abc123 dev def456)"
check "no fallback when marker missing"   ""  "$(fallback_commit abc123 "" def456)"
check "no fallback when installed differs" "" "$(fallback_commit abc123 xyz789 def456)"
check "no fallback when head is last good" "" "$(fallback_commit abc123 abc123 abc123)"

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

# Signing errors of the widget extension count as signing failures, compile errors do not.
sign_log="$test_home/build.log"
print -r -- 'error: Signing for "TagwerkWidget" requires a development team.' > "$sign_log"
check "extension signing error detected"  yes "$(build_log_has_signing_error "$sign_log")"
print -r -- 'error: Provisioning profile "x" doesn'"'"'t match the entitlements file'"'"'s value for the com.apple.security.application-groups entitlement.' > "$sign_log"
check "application-groups error detected" yes "$(build_log_has_signing_error "$sign_log")"
print -r -- 'error: Provisioning profile "iOS Team Provisioning Profile: org.example.tagwerk" is not available.' > "$sign_log"
check "app provisioning error detected"   yes "$(build_log_has_signing_error "$sign_log")"
print -r -- 'error: Signing for "TagwerkWatchWidget" requires a development team.' > "$sign_log"
check "watch extension signing detected"  yes "$(build_log_has_signing_error "$sign_log")"
print -r -- 'error: Provisioning profile "x" doesn'"'"'t include the application-groups entitlement (in target '"'"'TagwerkWatch'"'"')' > "$sign_log"
check "watch app group error detected"    yes "$(build_log_has_signing_error "$sign_log")"
print -r -- '/src/TagwerkWatch/WatchStore.swift:9:5: error: cannot find type '"'"'Foo'"'"' in scope' > "$sign_log"
check "watch compile error is no signing" no "$(build_log_has_signing_error "$sign_log")"
print -r -- '/src/TagwerkWidget/Widget.swift:12:5: error: cannot find type '"'"'Foo'"'"' in scope' > "$sign_log"
check "widget compile error is no signing" no "$(build_log_has_signing_error "$sign_log")"
print -r -- '/src/Tagwerk/Settings/ProfileView.swift:3:1: error: cannot find '"'"'ProfileView'"'"' in scope' > "$sign_log"
check "compile error naming a profile is no signing" no "$(build_log_has_signing_error "$sign_log")"
check "missing log is no signing error"   no  "$(build_log_has_signing_error "$test_home/does-not-exist.log")"

# A missing Xcode account is told apart from other signing errors.
print -r -- 'app/Tagwerk.xcodeproj: error: No Accounts: Add a new account in Accounts settings. (in target '"'"'Tagwerk'"'"')' > "$sign_log"
check "missing account detected"          yes "$(build_log_missing_account "$sign_log")"
print -r -- 'error: No Account for Team "ABCDE12345". Add a new account in Accounts settings.' > "$sign_log"
check "missing team account detected"     yes "$(build_log_missing_account "$sign_log")"
print -r -- 'error: Signing for "TagwerkWidget" requires a development team.' > "$sign_log"
check "other signing error is no account" no  "$(build_log_missing_account "$sign_log")"
print -r -- '/src/Tagwerk/Settings/AccountView.swift:3:1: error: No Accounts view in scope' > "$sign_log"
check "compile error is no account"       no  "$(build_log_missing_account "$sign_log")"
check "missing log is no account"         no  "$(build_log_missing_account "$test_home/does-not-exist.log")"

# The account notice repeats at most every 12 hours.
check "first account notice"              yes "$(should_repeat_notice "" $now)"
check "notice 1 hour later is quiet"      no  "$(should_repeat_notice $((now - 3600)) $now)"
check "notice 12 hours later repeats"     yes "$(should_repeat_notice $((now - 12 * 3600)) $now)"
check "invalid stamp repeats"             yes "$(should_repeat_notice abc $now)"

# Profiles set aside before a build come back after a failure; a newer profile of the same name is kept.
aside="$test_home/aside" profiles="$test_home/profiles"
mkdir -p "$aside" "$profiles"
print old-app > "$aside/app.mobileprovision"
print old-widget > "$aside/widget.mobileprovision"
print new-widget > "$profiles/widget.mobileprovision"
restore_profiles "$aside" "$profiles"
check "set-aside profile restored"        old-app "$(cat "$profiles/app.mobileprovision")"
check "newer profile kept"                new-widget "$(cat "$profiles/widget.mobileprovision")"
check "aside folder emptied"              0 "$(ls "$aside" | wc -l | tr -d ' ')"
restore_profiles "$test_home/missing" "$profiles"
check "missing aside folder is harmless"  0 "$?"

echo 'DEVICE_ID=example-device' > "$CONFIG_FILE"
check "missing team fails locally"        64 "$(zsh -c 'source "$1"; print $?' _ "${0:A:h}/../install-config.zsh" 2>/dev/null)"
echo 'DEVELOPMENT_TEAM=ABCDE12345' >> "$CONFIG_FILE"
check "missing bundle ID fails locally"   64 "$(zsh -c 'source "$1"; print $?' _ "${0:A:h}/../install-config.zsh" 2>/dev/null)"

exit $(( failures > 0 ))
