#!/usr/bin/env bash
# adlc-tracker.sh — the one door to the issue tracker. /refine and /implement never talk to
# a tracker directly; they call this, and this calls the adapter named by `tracker:` in
# .claude/adlc-config.md (lib/trackers/<tracker>.sh or <tracker>.py).
#
#   adlc-tracker.sh fetch       <KEY>               print the ticket (human zone) as Markdown
#   adlc-tracker.sh baseline    <KEY>               save the description verbatim; print the file
#   adlc-tracker.sh read-block  <KEY> <out-file>    write the machine block (```adlc fence); exit 3 if none
#   adlc-tracker.sh write-block <KEY> <block-file>  store the block; refuses a block whose seal does not verify
#   adlc-tracker.sh claim       <KEY>               assign the ticket to the person running the session
#   adlc-tracker.sh status      <KEY>               print the canonical state (see below) or other:<name>
#   adlc-tracker.sh transition  <KEY> <state>       move the ticket to a canonical state
#   adlc-tracker.sh append      <KEY> <md-file>     append to the human zone (never rewrites it)
#   adlc-tracker.sh comment     <KEY> <md-file>     add a comment (hand-off notes, PR links)
#
# Canonical states: draft in-refinement ready-for-agent in-progress in-review done.
# The config's `statuses:` map gives each one the tracker's own status name.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  sed -n '6,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

STATES="draft in-refinement ready-for-agent in-progress in-review done"
[[ $# -ge 2 ]] || usage
ACTION="$1"
KEY="$2"
shift 2
[[ "$KEY" =~ ^[A-Za-z0-9._-]+$ ]] || adlc_die 2 "ref-unsafe ticket key: $KEY"

ROOT="$(adlc_find_root)"
TRACKER="$(adlc_cfg tracker)"
[[ -n "$TRACKER" ]] || adlc_die 2 "no 'tracker:' in $ROOT/.claude/adlc-config.md"
[[ "$TRACKER" =~ ^[a-z0-9-]+$ ]] || adlc_die 2 "bad tracker name: $TRACKER"

export ADLC_PROJECT_ROOT="$ROOT"
export ADLC_TICKETS_DIR="$(adlc_cfg tickets_dir)"
for s in $STATES; do
  var="ADLC_STATUS_$(tr 'a-z-' 'A-Z_' <<<"$s")"
  name="$(adlc_cfg_map statuses "${s//-/_}")"
  export "$var=${name:-$s}"
done

run_adapter() {
  local base="$ADLC_LIB_DIR/trackers/$TRACKER"
  if [[ -f "$base.sh" ]]; then
    bash "$base.sh" "$@"
  elif [[ -f "$base.py" ]]; then
    python3 "$base.py" "$@"
  else
    adlc_die 2 "no tracker adapter '$TRACKER' (looked for $base.sh and $base.py)"
  fi
}

case "$ACTION" in
  fetch | claim | status)
    [[ $# -eq 0 ]] || usage
    run_adapter "$ACTION" "$KEY"
    ;;
  baseline)
    [[ $# -eq 0 ]] || usage
    dir="$(adlc_home)/tickets/$KEY"
    mkdir -p "$dir"
    f="$dir/baseline-$(date -u +%Y%m%dT%H%M%SZ).md"
    run_adapter fetch "$KEY" >"$f"
    printf '%s\n' "$f"
    ;;
  read-block)
    [[ $# -eq 1 ]] || usage
    run_adapter read-block "$KEY" "$1"
    ;;
  write-block)
    [[ $# -eq 1 && -f "$1" ]] || usage
    "$ADLC_SCRIPTS_DIR/adlc-seal.sh" check "$1" >/dev/null ||
      adlc_die 1 "refusing to store a block whose seal does not verify; run adlc-seal.sh write, then adlc-lint.sh"
    run_adapter write-block "$KEY" "$1"
    ;;
  transition)
    [[ $# -eq 1 ]] || usage
    [[ " $STATES " == *" $1 "* ]] || adlc_die 2 "unknown state '$1'; use one of: $STATES"
    run_adapter transition "$KEY" "$1"
    ;;
  append | comment)
    [[ $# -eq 1 && -f "$1" ]] || usage
    run_adapter "$ACTION" "$KEY" "$1"
    ;;
  *)
    usage
    ;;
esac
