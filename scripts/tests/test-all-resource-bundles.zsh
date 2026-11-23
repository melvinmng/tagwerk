#!/bin/zsh
# Tests for the handling of embedded SwiftPM resource bundles in app/test-all.sh (run: zsh scripts/tests/test-all-resource-bundles.zsh).
# Only the two helper functions run, on a fake products folder; no xcodebuild, simulator or test stage is started.
set -u
ROOT="${0:A:h:h:h}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

failures=0
check() { # name expected actual
  if [[ "$2" == "$3" ]]; then print "ok   $1"; else print "FAIL $1"$'\n'"     expected: $2"$'\n'"     actual:   $3"; failures=$((failures + 1)); fi
}

PRODUCTS="$WORK_DIR/Products/Debug-iphonesimulator"

# Builds the layout of a finished simulator build: package bundles next to the products, in the app, in the extensions
# (top-level and embedded in the app) and in the unit test bundle.
make_products() {
  rm -rf "$WORK_DIR/Products"
  mkdir -p "$PRODUCTS/Core_Core.bundle" \
    "$PRODUCTS/Tagwerk.app/Core_Core.bundle" \
    "$PRODUCTS/Tagwerk.app/PlugIns/Widget.appex/Core_Core.bundle" \
    "$PRODUCTS/Tagwerk.app/PlugIns/Share.appex/Core_Core.bundle" \
    "$PRODUCTS/Tagwerk.app/PlugIns/Tests.xctest/Core_Core.bundle" \
    "$PRODUCTS/Widget.appex/Core_Core.bundle"
  touch "$PRODUCTS/Tagwerk.app/PlugIns/Widget.appex/Widget" "$PRODUCTS/Widget.appex/Widget" "$PRODUCTS/Tagwerk.app/Tagwerk"
}

# Runs the helpers in a subshell with the products folder of make_products; the argument is a shell snippet that runs between
# the removal and the verification (it plays the role of the build). Prints the verification output and "rc=<exit code>".
run_cycle() {
  (
    export TAGWERK_SOURCE_ONLY=1
    source "$ROOT/app/test-all.sh"
    remove_embedded_resource_bundles "$WORK_DIR/Products"
    eval "$1"
    local rc=0
    verify_embedded_resource_bundles "$WORK_DIR/Products" 2>&1 || rc=$?
    print "rc=$rc"
  )
}

# The removal leaves the package bundle next to the products and deletes every embedded copy, an embedded extension as a whole.
make_products
(export TAGWERK_SOURCE_ONLY=1; source "$ROOT/app/test-all.sh"; remove_embedded_resource_bundles "$WORK_DIR/Products")
check "the product bundle stays" "1" "$([[ -d "$PRODUCTS/Core_Core.bundle" ]] && print 1 || print 0)"
check "the embedded app bundle is removed" "0" "$([[ -d "$PRODUCTS/Tagwerk.app/Core_Core.bundle" ]] && print 1 || print 0)"
check "the embedded extensions are removed as a whole" "0" "$([[ -e "$PRODUCTS/Tagwerk.app/PlugIns/Widget.appex" || -e "$PRODUCTS/Tagwerk.app/PlugIns/Share.appex" ]] && print 1 || print 0)"
check "the test bundle copy is removed" "0" "$([[ -d "$PRODUCTS/Tagwerk.app/PlugIns/Tests.xctest/Core_Core.bundle" ]] && print 1 || print 0)"
check "the extension product loses only its bundle" "1 0" \
  "$([[ -f "$PRODUCTS/Widget.appex/Widget" ]] && print -n 1) $([[ -d "$PRODUCTS/Widget.appex/Core_Core.bundle" ]] && print 1 || print 0)"

# A build that puts everything back passes the verification.
make_products
restore_all='
  mkdir -p "$PRODUCTS/Tagwerk.app/Core_Core.bundle" "$PRODUCTS/Tagwerk.app/PlugIns/Widget.appex/Core_Core.bundle" \
    "$PRODUCTS/Tagwerk.app/PlugIns/Share.appex/Core_Core.bundle" "$PRODUCTS/Tagwerk.app/PlugIns/Tests.xctest/Core_Core.bundle" \
    "$PRODUCTS/Widget.appex/Core_Core.bundle"'
check "all bundles are back" "rc=0" "$(run_cycle "$restore_all")"

# The UI scheme does not build the unit test bundles: their copies stay absent, which is not an error.
make_products
restore_without_tests='
  mkdir -p "$PRODUCTS/Tagwerk.app/Core_Core.bundle" "$PRODUCTS/Tagwerk.app/PlugIns/Widget.appex/Core_Core.bundle" \
    "$PRODUCTS/Tagwerk.app/PlugIns/Share.appex/Core_Core.bundle" "$PRODUCTS/Widget.appex/Core_Core.bundle"'
check "unit test bundles are not verified" "rc=0" "$(run_cycle "$restore_without_tests")"

# The reported case: the incremental build restores the app but not the embedded extension.
make_products
restore_without_widget='
  mkdir -p "$PRODUCTS/Tagwerk.app/Core_Core.bundle" "$PRODUCTS/Tagwerk.app/PlugIns/Share.appex/Core_Core.bundle" \
    "$PRODUCTS/Widget.appex/Core_Core.bundle"'
expected_failure=$'Resource bundles are missing after the build (they were embedded before it):\n  Debug-iphonesimulator/Tagwerk.app/PlugIns/Widget.appex/Core_Core.bundle\n'
expected_failure+="A target without its resource bundle crashes at Bundle.module. Delete $WORK_DIR/Products and run again."$'\nrc=1'
check "a missing extension bundle fails loudly" "$expected_failure" "$(run_cycle "$restore_without_widget")"

# Nothing embedded before the build (first run in a fresh folder): nothing to verify.
rm -rf "$WORK_DIR/Products"
mkdir -p "$PRODUCTS"
check "an empty products folder passes" "rc=0" "$(run_cycle ':')"

if (( failures > 0 )); then print "$failures check(s) failed"; exit 1; fi
print "all checks passed"
