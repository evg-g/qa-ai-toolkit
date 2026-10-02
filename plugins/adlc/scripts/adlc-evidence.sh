#!/usr/bin/env bash
# adlc-evidence.sh <ticket> <worktree> <AC-id>
#
# Prints the proof-log evidence for one criterion, for test-review and for humans:
#   log=<path of the proof log>
#   last_result=<token of the last dispatch>  test_id=<…>
#   red_tree=<worktree hash of the red that proved non-vacuity>
#   red_break_note=<what was made false>      red_output=<run log of that red>
# Exit 0 when the criterion has at least one log line, 3 when it has none.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
[[ $# -eq 3 ]] || { echo "usage: adlc-evidence.sh <ticket> <worktree> <AC-id>" >&2; exit 2; }
TICKET="$1" WT="$2" AC="$3"
LOG="$(adlc_state_dir "$WT")/proof-log.jsonl"
echo "log=$LOG"
jf() { sed -nE 's/.*"'"$2"'":"(([^"\\]|\\.)*)".*/\1/p' <<<"$1" | head -n 1; }
last="$(grep -F "\"ticket\":\"$(adlc_json_escape "$TICKET")\",\"ac\":\"$AC\"" "$LOG" 2>/dev/null | tail -n 1 || true)"
[[ -n "$last" ]] || { echo "last_result=none"; exit 3; }
echo "last_result=$(jf "$last" result)  test_id=$(jf "$last" test_id)"
red="$(jf "$last" prior_red_hash)"
if [[ -z "$red" ]]; then
  # Not proven yet: show the latest genuine red for this criterion, if any.
  redline="$(grep -F "\"ticket\":\"$(adlc_json_escape "$TICKET")\",\"ac\":\"$AC\"" "$LOG" | grep -F '"result":"red"' | tail -n 1 || true)"
else
  redline="$(grep -F "\"worktree_hash\":\"$red\"" "$LOG" | grep -F "\"test_id\":\"$(jf "$last" test_id)\"" | grep -F '"result":"red"' | tail -n 1 || true)"
fi
echo "red_tree=$(jf "$redline" worktree_hash)"
echo "red_break_note=$(jf "$redline" break_note)"
echo "red_output=$(jf "$redline" output)"
