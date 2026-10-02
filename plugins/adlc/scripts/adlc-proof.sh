#!/usr/bin/env bash
# adlc-proof.sh — the only way a test becomes a verdict (Rule 3).
#
#   adlc-proof.sh --repo <worktree> --ticket <KEY> --ac <AC-id> --test <test-id>
#                 (--binding <method> | --runner <adapter> [--location <path>])
#                 [--break-note "<what was made false to earn this red>"]
#                 [--no-red-reason "<prose>" | --accept-green "<prose>" | --infra-exempt "<prose>"]
#                 [--timeout-secs <n>] [-- <extra adapter args>]
#
# The core owns the tree hash, the log, no-retry-to-green, non-vacuity and classification.
# A per-harness adapter (lib/proof-adapters/<runner>.sh) only builds the command for one
# selected test — always with the isolation filter, by construction — and says whether the
# run passed, failed, did not build, or hit an environment fault.
#
# Prints RESULT=<token> (and OUTPUT=<run log>) on stdout and appends one JSON line to
#   ${ADLC_LOG_HOME:-$HOME/.adlc}/<sanitized-main-checkout-path>/proof-log.jsonl
# which lives outside every worktree, so git clean, a branch switch or a fresh worktree
# cannot erase the evidence.
#
#   token                  exit  meaning
#   proven                 0     green here, after a genuine red for this test at another tree
#   green-no-red-observed  0     green, but this test never logged a genuine red
#   red                    1     the test ran and failed
#   flaky-refused          1     green refused: the same test went red at this same tree
#   build-error            1     did not compile/load, or selected no test / several tests
#   infra-exempt           0     the harness demonstrably did not run (environment fault)
#   timed-out              1     killed at the wall-clock bound
# Exit 2 is a usage error; nothing is logged.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  sed -n '3,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

WT="" TICKET="" AC="" TEST_ID="" BINDING="" RUNNER="" LOCATION="" BREAK_NOTE=""
OVERRIDE_KIND="" OVERRIDE_REASON="" TIMEOUT_SECS=1800
EXTRA_ARGS=()
set_override() {
  [[ -z "$OVERRIDE_KIND" ]] || adlc_die 2 "only one override per dispatch (already have --$OVERRIDE_KIND)"
  OVERRIDE_KIND="$1"
  OVERRIDE_REASON="$2"
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) WT="${2:-}"; shift 2 ;;
    --ticket) TICKET="${2:-}"; shift 2 ;;
    --ac) AC="${2:-}"; shift 2 ;;
    --test) TEST_ID="${2:-}"; shift 2 ;;
    --binding) BINDING="${2:-}"; shift 2 ;;
    --runner) RUNNER="${2:-}"; shift 2 ;;
    --location) LOCATION="${2:-}"; shift 2 ;;
    --break-note) BREAK_NOTE="${2:-}"; shift 2 ;;
    --no-red-reason) set_override no-red-reason "${2:-}"; shift 2 ;;
    --accept-green) set_override accept-green "${2:-}"; shift 2 ;;
    --infra-exempt) set_override infra-exempt "${2:-}"; shift 2 ;;
    --timeout-secs) TIMEOUT_SECS="${2:-}"; shift 2 ;;
    --) shift; EXTRA_ARGS=("$@"); break ;;
    -h | --help) usage ;;
    *) echo "adlc-proof: unknown option: $1" >&2; usage ;;
  esac
done

[[ -n "$AC" ]] || adlc_die 2 "--ac is required: a verdict must be attributed to one criterion"
[[ "$AC" =~ ^AC[1-9][0-9]*\.[a-z]+$ ]] || adlc_die 2 "--ac must look like AC1.api, got: $AC"
[[ -n "$TICKET" ]] || adlc_die 2 "--ticket is required"
[[ -n "$TEST_ID" ]] || adlc_die 2 "--test is required: name the one test this dispatch selects"
[[ -n "$WT" && -d "$WT" ]] || adlc_die 2 "--repo must be an existing worktree directory"
[[ "$TIMEOUT_SECS" =~ ^[1-9][0-9]*$ ]] || adlc_die 2 "--timeout-secs must be a positive integer"
if [[ -n "$OVERRIDE_KIND" ]]; then
  trimmed="${OVERRIDE_REASON//[[:space:]]/}"
  [[ ${#trimmed} -ge 20 ]] || adlc_die 2 "--$OVERRIDE_KIND needs real prose (20+ characters): an override with no reason is a bypass"
fi
WT="$(cd "$WT" && pwd)"
git -C "$WT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || adlc_die 2 "not a git worktree: $WT"

# ----- resolve the adapter ---------------------------------------------------------------

PREFIX=()
RUN_ENV=()
if [[ -n "$BINDING" ]]; then
  BF="$WT/.claude/surface-bindings.json"
  [[ -f "$BF" ]] || adlc_die 2 "no $BF; --binding needs the repo's surface-bindings.json"
  flat="$(adlc_json_flat "$BF")" || adlc_die 2 "cannot parse $BF"
  grep -q "^bindings/$BINDING/" <<<"$flat" || adlc_die 2 "binding '$BINDING' is not in $BF"
  b_runner="$(awk -F'\t' -v k="bindings/$BINDING/runner" '$1 == k { print $2; exit }' <<<"$flat")"
  [[ -z "$RUNNER" || "$RUNNER" == "$b_runner" ]] || adlc_die 2 "--runner $RUNNER contradicts binding '$BINDING' (runner $b_runner)"
  RUNNER="$b_runner"
  [[ -n "$LOCATION" ]] || LOCATION="$(awk -F'\t' -v k="bindings/$BINDING/location" '$1 == k { print $2; exit }' <<<"$flat")"
  while IFS= read -r w; do PREFIX+=("$w"); done < <(awk -F'\t' -v k="bindings/$BINDING/prefix/" 'index($1, k) == 1 { print $2 }' <<<"$flat")
  b_args=()
  while IFS= read -r w; do b_args+=("$w"); done < <(awk -F'\t' -v k="bindings/$BINDING/args/" 'index($1, k) == 1 { print $2 }' <<<"$flat")
  EXTRA_ARGS=(${b_args[@]+"${b_args[@]}"} ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"})
  while IFS=$'\t' read -r k v; do
    [[ -z "$k" ]] && continue
    k="${k#bindings/"$BINDING"/env/}"
    [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || adlc_die 2 "binding '$BINDING' has a bad env name: $k"
    RUN_ENV+=("$k=$v")
  done < <(awk -F'\t' -v k="bindings/$BINDING/env/" 'index($1, k) == 1 { print }' <<<"$flat")
fi
[[ -n "$RUNNER" ]] || adlc_die 2 "give --binding <method> or --runner <adapter>"
[[ "$RUNNER" =~ ^[a-z0-9-]+$ ]] || adlc_die 2 "bad runner name: $RUNNER"
ADAPTER="$ADLC_LIB_DIR/proof-adapters/$RUNNER.sh"
[[ -f "$ADAPTER" ]] || adlc_die 2 "no adapter for runner '$RUNNER' ($ADAPTER)"
# shellcheck source=/dev/null
source "$ADAPTER"

CMD=()
adapter_build_cmd || adlc_die 2 "adapter '$RUNNER' refused the dispatch (see above)"
[[ ${#CMD[@]} -gt 0 ]] || adlc_die 2 "adapter '$RUNNER' built no command"

TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
[[ -n "$TIMEOUT_BIN" ]] || adlc_die 2 "needs coreutils 'timeout' (or 'gtimeout') for the wall-clock bound"

# ----- tree identity ---------------------------------------------------------------------

# worktree_hash: git add -A + write-tree over the whole working tree, in a throwaway index,
# so it moves on ANY change (uncommitted edits, untracked files) without touching the real
# index. It is a tripwire for no-retry-to-green, not a commit tree: never compare the two.
worktree_hash() {
  local idx real
  idx="$(mktemp "${TMPDIR:-/tmp}/adlc-index.XXXXXX")"
  real="$(git -C "$WT" rev-parse --path-format=absolute --git-path index)"
  if [[ -f "$real" ]]; then cp "$real" "$idx"; else rm -f "$idx"; fi
  GIT_INDEX_FILE="$idx" git -C "$WT" add -A >/dev/null 2>&1
  GIT_INDEX_FILE="$idx" git -C "$WT" write-tree
  rm -f "$idx"
}
WT_HASH="$(worktree_hash)" || adlc_die 2 "cannot compute the worktree hash in $WT"
HEAD_TREE="$(git -C "$WT" rev-parse 'HEAD^{tree}' 2>/dev/null || echo none)"
TREE_DIRTY=false
[[ "$WT_HASH" == "$HEAD_TREE" ]] || TREE_DIRTY=true

STATE="$(adlc_state_dir "$WT")"
LOG="$STATE/proof-log.jsonl"
RUNS="$STATE/runs"
mkdir -p "$RUNS"
touch "$LOG"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$RUNS/$STAMP-$TICKET-$AC-$$.log"

# ----- run -------------------------------------------------------------------------------

START=$(date +%s)
RC=0
(
  cd "$WT"
  export NO_COLOR=1 FORCE_COLOR=0
  for kv in ${RUN_ENV[@]+"${RUN_ENV[@]}"}; do export "${kv?}"; done
  "$TIMEOUT_BIN" --signal=TERM --kill-after=30 "$TIMEOUT_SECS" "${CMD[@]}"
) >"$OUT" 2>&1 </dev/null || RC=$?
DURATION=$(($(date +%s) - START))

# ANSI colour codes would break the adapters' parsing.
sed -i.bak 's/\x1b\[[0-9;]*[A-Za-z]//g' "$OUT" 2>/dev/null && rm -f "$OUT.bak"

if [[ $RC -eq 124 || $RC -eq 137 ]] && [[ $DURATION -ge $TIMEOUT_SECS ]]; then
  RAW="timeout"
else
  RAW="$(adapter_classify "$RC" "$OUT")"
fi

# ----- classify --------------------------------------------------------------------------

# Prior genuine reds for this test in this repo's log: their worktree hashes, one per line.
key_test="\"runner\":\"$(adlc_json_escape "$RUNNER")\",\"test_id\":\"$(adlc_json_escape "$TEST_ID")\""
prior_red_hashes() {
  grep -F "$key_test" "$LOG" | grep -F '"result":"red"' |
    sed -n 's/.*"worktree_hash":"\([0-9a-f]*\)".*/\1/p' || true
}
REDS="$(prior_red_hashes)"
RED_HERE=0
RED_ELSEWHERE=""
while IFS= read -r h; do
  [[ -z "$h" ]] && continue
  if [[ "$h" == "$WT_HASH" ]]; then RED_HERE=1; else RED_ELSEWHERE="$h"; fi
done <<<"$REDS"

DETAIL=""
OVERRIDE_USED=""
case "$RAW" in
  pass)
    if [[ $RED_HERE -eq 1 && "$OVERRIDE_KIND" != "accept-green" ]]; then
      RESULT="flaky-refused"
      DETAIL="this test went red at this same worktree hash earlier; no-retry-to-green"
    elif [[ -n "$RED_ELSEWHERE" ]]; then
      RESULT="proven"
      [[ $RED_HERE -eq 1 ]] && OVERRIDE_USED="accept-green"
    elif [[ "$OVERRIDE_KIND" == "no-red-reason" ]]; then
      RESULT="proven"
      OVERRIDE_USED="no-red-reason"
      DETAIL="non-vacuity argued in prose, not observed"
    else
      RESULT="green-no-red-observed"
      DETAIL="no genuine red for this test at another tree; non-vacuity not shown"
      [[ $RED_HERE -eq 1 ]] && OVERRIDE_USED="accept-green"
    fi
    ;;
  fail)
    if [[ "$OVERRIDE_KIND" == "infra-exempt" ]]; then
      RESULT="infra-exempt"
      OVERRIDE_USED="infra-exempt"
      DETAIL="red forced to infra-exempt by override"
    else
      RESULT="red"
    fi
    ;;
  build-error*)
    RESULT="build-error"
    DETAIL="${RAW#build-error}"
    DETAIL="${DETAIL#:}"
    ;;
  infra*)
    RESULT="infra-exempt"
    DETAIL="${RAW#infra}"
    DETAIL="${DETAIL#:}"
    ;;
  timeout)
    RESULT="timed-out"
    DETAIL="killed after ${TIMEOUT_SECS}s"
    ;;
  *)
    RESULT="build-error"
    DETAIL="adapter returned an unknown outcome: $RAW"
    ;;
esac
if [[ -n "$OVERRIDE_KIND" && -z "$OVERRIDE_USED" ]]; then
  DETAIL="${DETAIL:+$DETAIL; }--$OVERRIDE_KIND given but not applicable to this outcome"
fi

case "$RESULT" in
  proven | green-no-red-observed | infra-exempt) EXIT=0 ;;
  *) EXIT=1 ;;
esac

# ----- log -------------------------------------------------------------------------------

j() { printf '"%s":"%s"' "$1" "$(adlc_json_escape "$2")"; }
CMD_STR="$(printf '%q ' ${RUN_ENV[@]+"${RUN_ENV[@]}"} "${CMD[@]}")"
LINE="{$(j ts "$(adlc_now)"),$(j ticket "$TICKET"),$(j ac "$AC"),$(j runner "$RUNNER"),$(j test_id "$TEST_ID")"
LINE+=",$(j result "$RESULT"),$(j raw "$RAW"),\"exit_code\":$RC,\"duration_s\":$DURATION"
LINE+=",$(j worktree "$WT"),$(j worktree_hash "$WT_HASH"),$(j head_tree "$HEAD_TREE"),\"tree_dirty\":$TREE_DIRTY"
LINE+=",$(j prior_red_hash "$([[ "$RESULT" == proven ]] && printf '%s' "$RED_ELSEWHERE")")"
LINE+=",$(j binding "$BINDING"),$(j break_note "$BREAK_NOTE")"
LINE+=",$(j override_kind "$OVERRIDE_USED"),$(j override_reason "$([[ -n "$OVERRIDE_USED" ]] && printf '%s' "$OVERRIDE_REASON")")"
LINE+=",$(j detail "$DETAIL"),$(j command "${CMD_STR% }"),$(j output "$OUT")}"
adlc_append_line "$LOG" "$LINE"

{
  echo "adlc-proof: $TICKET $AC $RUNNER '$TEST_ID' -> $RESULT${DETAIL:+ ($DETAIL)}"
  echo "adlc-proof: worktree_hash=$WT_HASH head_tree=$HEAD_TREE tree_dirty=$TREE_DIRTY"
  if [[ "$RESULT" != "proven" && "$RESULT" != "green-no-red-observed" ]]; then
    echo "adlc-proof: last lines of the run output:"
    tail -n 40 "$OUT" | sed 's/^/  | /'
  fi
} >&2
echo "RESULT=$RESULT"
echo "OUTPUT=$OUT"
exit "$EXIT"
