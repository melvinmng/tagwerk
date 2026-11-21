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
check "foreign bundle does not match"     no  "$(is_tagwerk_profile "$team.org.example.other" $team $bundle)"
check "prefix lookalike does not match"   no  "$(is_tagwerk_profile "$team.${bundle}x" $team $bundle)"
check "prefix lookalike widget no match"  no  "$(is_tagwerk_profile "$team.${bundle}x.widget" $team $bundle)"
check "other team does not match"         no  "$(is_tagwerk_profile "ZZZZZ99999.$bundle" $team $bundle)"
check "other team widget does not match"  no  "$(is_tagwerk_profile "ZZZZZ99999.$bundle.widget" $team $bundle)"
check "empty identifier does not match"   no  "$(is_tagwerk_profile "" $team $bundle)"
check "team only does not match"          no  "$(is_tagwerk_profile "$team" $team $bundle)"
check "trailing dot only does not match"  no  "$(is_tagwerk_profile "$team.$bundle." $team $bundle)"
check "dot in bundle is literal"          no  "$(is_tagwerk_profile "$team.orgXexample.tagwerk" $team $bundle)"

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

# should_install <due> <remote head> <last installed> <last good> <last failed>
check "nothing new, profile fine"         no  "$(should_install no new1 new1 new1 "")"
check "new main on the device's old state" yes "$(should_install no new2 old1 old1 "")"
check "new main, markers differ"          yes "$(should_install no new2 old1 other "")"
check "profile due without new commit"    yes "$(should_install yes new1 new1 new1 "")"
check "profile due with new commit"       yes "$(should_install yes new2 old1 old1 "")"
check "profile due, head is last failed"  yes "$(should_install yes bad1 old1 old1 bad1)"
check "after install-dev, main unchanged" no  "$(should_install no main1 dev main1 "")"
check "after install-dev, main moved on"  yes "$(should_install no main2 dev main1 "")"
check "after install-dev, no last good"   yes "$(should_install no main1 dev "" "")"
check "no marker, main unchanged"         no  "$(should_install no main1 "" main1 "")"
check "no marker, nothing known"          yes "$(should_install no main1 "" "" "")"
check "failed commit is not retried"      no  "$(should_install no bad1 old1 old1 bad1)"
check "failed commit not retried after dev" no "$(should_install no bad1 dev old1 bad1)"
check "main changed after a failure"      yes "$(should_install no fix1 old1 old1 bad1)"
check "unknown remote head installs nothing" no "$(should_install no "" old1 old1 "")"
check "unknown remote head, profile due"  yes "$(should_install yes "" old1 old1 "")"

# Load guard: threshold is LOAD_SKIP_PER_CPU x CPU count; a due profile refresh is never postponed.
check "load threshold is 3 per CPU"       3   "$LOAD_SKIP_PER_CPU"
check "load below threshold runs"         no  "$(should_skip_for_load no 11.99 4)"
check "load at threshold runs"            no  "$(should_skip_for_load no 12.00 4)"
check "load above threshold skips"        yes "$(should_skip_for_load no 12.01 4)"
check "high load, profile due, runs"      no  "$(should_skip_for_load yes 40.0 4)"
check "integer load is accepted"          yes "$(should_skip_for_load no 13 4)"
check "unreadable load never skips"       no  "$(should_skip_for_load no "" 4)"
check "non-numeric load never skips"      no  "$(should_skip_for_load no abc 4)"
check "unknown CPU count never skips"     no  "$(should_skip_for_load no 99.0 "")"
check "zero CPU count never skips"        no  "$(should_skip_for_load no 99.0 0)"
check "parses 5-minute load"              1.80 "$(load_average_5min '{ 1.52 1.80 1.90 }')"
check "parses comma decimal separator"    1.80 "$(load_average_5min '{ 1,52 1,80 1,90 }')"
check "unparsable load is empty"          ""  "$(load_average_5min 'garbage')"
check "empty load output is empty"        ""  "$(load_average_5min '')"

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
