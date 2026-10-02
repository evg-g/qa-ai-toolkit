#!/usr/bin/env bash
# adlc-heartbeat.sh <ticket-key> <repo-path> <phase> [note]
#
# Appends one line to a heartbeat file outside the worktree, so a human can tell a working
# run from a hung one during a long silent stretch. Best-effort: it always exits 0, and a
# missing heartbeat never flags a criterion.
#
#   adlc-heartbeat.sh --path <ticket-key> <repo-path>   print the heartbeat file path
set -uo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh" 2>/dev/null || exit 0

if [[ "${1:-}" == "--path" ]]; then
  [[ $# -eq 3 ]] || { echo "usage: adlc-heartbeat.sh --path <ticket-key> <repo-path>" >&2; exit 2; }
  dir="$(adlc_state_dir "$3")" || exit 2
  printf '%s/heartbeat-%s.log\n' "$dir" "$2"
  exit 0
fi
[[ $# -ge 3 ]] || { echo "usage: adlc-heartbeat.sh <ticket-key> <repo-path> <phase> [note]" >&2; exit 0; }
{
  dir="$(adlc_state_dir "$2")" &&
    adlc_append_line "$dir/heartbeat-$1.log" "$(adlc_now) $3${4:+ — $4}"
} 2>/dev/null || true
exit 0
