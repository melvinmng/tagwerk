#!/bin/zsh
# Runs the tests of the helper scripts (scripts/tests): the Python unit tests and every zsh test. They need no build and no
# simulator; the zsh tests replace xcodebuild, xcodegen and xcrun with stubs. CI runs this in the job "Script tests"; locally it is
# the check for changes below scripts/ and in app/test-all.sh (about one minute).
#
# Usage: scripts/run-script-tests.sh
# Exit code: 0 when everything passed, 1 otherwise (all tests run; the failed ones are listed at the end).
set -u
ROOT="${0:A:h:h}"
cd "$ROOT" || exit 1
failed=()

echo "==> Python unit tests"
/usr/bin/python3 -m unittest discover -s scripts/tests -p 'test_*.py' || failed+=("python unit tests")

for test_script in scripts/tests/*.zsh; do
  echo "==> $test_script"
  started=$SECONDS
  zsh "$test_script" || failed+=("$test_script")
  echo "    $(( SECONDS - started )) s"
done

if (( ${#failed} > 0 )); then
  echo "SCRIPT TESTS FAILED:" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "ALL SCRIPT TESTS PASSED"
