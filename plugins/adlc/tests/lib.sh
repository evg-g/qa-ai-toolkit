# shellcheck shell=bash
# Tiny assert helpers for the ADLC self-tests. Source it.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$TESTS_DIR/../scripts" && pwd)"
FIX="$TESTS_DIR/fixtures"
PASS=0
FAIL=0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/adlc-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# Keep every log the tests write out of the real ~/.adlc.
export ADLC_LOG_HOME="$WORK/adlc-home"

ok() {
  PASS=$((PASS + 1))
  echo "  ok   $*"
}

not_ok() {
  FAIL=$((FAIL + 1))
  echo "  FAIL $*"
}

# expect <exit-code> <stderr-or-stdout-regex|-> <description> -- <command...>
# Runs the command, checks its exit code and that its combined output matches the regex.
expect() {
  local want="$1" pattern="$2" desc="$3"
  shift 4
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ "$rc" -ne "$want" ]]; then
    not_ok "$desc (exit $rc, wanted $want)"
    sed 's/^/         | /' <<<"$out"
    return 0
  fi
  if [[ "$pattern" != "-" ]] && ! grep -qE -- "$pattern" <<<"$out"; then
    not_ok "$desc (output does not match /$pattern/)"
    sed 's/^/         | /' <<<"$out"
    return 0
  fi
  ok "$desc"
}

finish() {
  echo "$(basename "$0"): $PASS passed, $FAIL failed"
  [[ "$FAIL" -eq 0 ]]
}
