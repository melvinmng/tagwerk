#!/bin/zsh
# Tests for resolve_package_scheme in app/test-all.sh (run: zsh scripts/tests/test-all-package-scheme.zsh).
# xcodebuild is replaced by a shell function; no build or simulator is started.
set -u
ROOT="${0:A:h:h:h}"

failures=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1"$'\n'"     expected: $2"$'\n'"     actual:   $3"; failures=$((failures + 1)); fi
}

# Runs resolve_package_scheme with the given xcodebuild stub body; prints "<stdout>|rc=<code>|<first line of stderr>".
run_resolve() {
  (
    export TAGWERK_SOURCE_ONLY=1
    source "$ROOT/app/test-all.sh"
    eval "xcodebuild() { $1 }"
    local errors_file=$(mktemp) output rc=0
    output=$(resolve_package_scheme Kit 2> "$errors_file") || rc=$?
    print -r -- "$output|rc=$rc|$(head -n 1 "$errors_file")"
    rm -f "$errors_file"
  )
}

check "the plain scheme is used when it exists" "Kit|rc=0|" \
  "$(run_resolve 'print -r -- "{\"workspace\":{\"schemes\":[\"Kit\",\"Other\"]}}"')"
check "the package scheme is used otherwise" "Kit-Package|rc=0|" \
  "$(run_resolve 'print -r -- "{\"workspace\":{\"schemes\":[\"Kit-Package\"]}}"')"
check "a failing xcodebuild stops with a clear message" "|rc=1|xcodebuild -list -json failed in $PWD while resolving the scheme of package Kit:" \
  "$(run_resolve 'echo "no workspace" >&2; return 66')"
check "invalid JSON stops with a clear message" "|rc=1|xcodebuild -list -json returned no usable scheme list for package Kit (JSONDecodeError: Expecting value: line 1 column 1 (char 0))" \
  "$(run_resolve 'print -r -- "not json"')"
check "JSON without a workspace stops with a clear message" "|rc=1|xcodebuild -list -json returned no usable scheme list for package Kit (KeyError: 'workspace')" \
  "$(run_resolve 'print -r -- "{\"project\":{}}"')"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
