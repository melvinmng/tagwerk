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

exit $(( failures > 0 ))
