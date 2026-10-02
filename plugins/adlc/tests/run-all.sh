#!/usr/bin/env bash
# Runs every ADLC self-test. Needs bash, git, awk, sed, coreutils timeout, python3 (Jira fake).
set -uo pipefail
cd "$(dirname "$0")"
rc=0
for t in test-*.sh; do
  echo "== $t"
  bash "$t" || rc=1
done
[[ $rc -eq 0 ]] && echo "ALL ADLC SELF-TESTS PASSED" || echo "SOME ADLC SELF-TESTS FAILED"
exit $rc
