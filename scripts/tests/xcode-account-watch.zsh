#!/bin/zsh
# Unit tests for the decision functions of xcode-account-watch.sh (run: zsh scripts/tests/xcode-account-watch.zsh).
set -u
TAGWERK_SOURCE_ONLY=1 source "${0:A:h}/../xcode-account-watch.sh"

failures=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1: expected '$2', got '$3'"; failures=$((failures + 1)); fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# make_prefs <file> <number of accounts>: a preferences file shaped like Xcode's.
make_prefs() {
  local file="$1" count="$2" i
  /usr/libexec/PlistBuddy -c "Add :DVTDeveloperAccountManagerAppleIDLists dict" \
    -c "Add :DVTDeveloperAccountManagerAppleIDLists:IDE.Identifiers.Prod array" "$file" >/dev/null
  for (( i = 0; i < count; i++ )); do
    /usr/libexec/PlistBuddy -c "Add :DVTDeveloperAccountManagerAppleIDLists:IDE.Identifiers.Prod:$i dict" \
      -c "Add :DVTDeveloperAccountManagerAppleIDLists:IDE.Identifiers.Prod:$i:identifier string ID-$i" "$file" >/dev/null
  done
}

make_prefs "$work/one.plist" 1
make_prefs "$work/two.plist" 2
make_prefs "$work/empty.plist" 0
/usr/libexec/PlistBuddy -c "Add :IDELastViewedSettingsPane string Accounts" "$work/fresh.plist" >/dev/null

check "one account"                     1 "$(account_count "$work/one.plist")"
check "two accounts"                    2 "$(account_count "$work/two.plist")"
check "empty list"                      0 "$(account_count "$work/empty.plist")"
check "list missing (first launch)"     0 "$(account_count "$work/fresh.plist")"
check "file missing"                    0 "$(account_count "$work/none.plist")"

check "first run"                       initial   "$(account_transition "" 1)"
check "first run without account"      initial   "$(account_transition "" 0)"
check "account lost"                    lost      "$(account_transition 1 0)"
check "one of two lost is no loss"      unchanged "$(account_transition 2 1)"
check "account restored"                restored  "$(account_transition 0 1)"
check "still present"                   unchanged "$(account_transition 1 1)"
check "still missing"                   unchanged "$(account_transition 0 0)"

(( failures == 0 )) && print "all passed" || { print "$failures failed"; exit 1; }
