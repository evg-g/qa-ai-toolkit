#!/usr/bin/env bash
# adlc-report.sh — build one repo's proof report from the proof log (Rules 3 and 4).
#
#   adlc-report.sh --ticket <KEY> --block <block-file> --repo <worktree> --out <file.md>
#                  [--repo-name <name>] [--final-tree <tree>]
#                  [--downgrade "<AC-id>=<why>"]...   (a confirmed test-review flag)
#                  [--finding "<text>"]...            (a confirmed review defect)
#
# The log is the source of truth, never an agent's summary. For each criterion of this repo
# in the sealed block, the verdict is the LAST log line for (ticket, criterion):
#   - proven only if that line says proven AND it ran against --final-tree (default: the
#     worktree's HEAD tree) with a clean tree; a proof against any other tree is stale;
#   - a criterion with no log line, an unbound one, or any non-proven verdict is FLAGGED —
#     reported, never dropped;
#   - --downgrade turns a proven criterion into needs-human until a person looks.
#
# Writes the Markdown report to --out and prints, on stdout:
#   PROVEN=<n> FLAGGED=<n> PR_STATE=ready|draft
# PR_STATE is draft when any criterion is not proven or any --finding was given.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  sed -n '3,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

TICKET="" BLOCK="" WT="" OUTFILE="" REPO_NAME="" FINAL_TREE=""
DOWN_AC=() DOWN_WHY=() FINDINGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ticket) TICKET="${2:-}"; shift 2 ;;
    --block) BLOCK="${2:-}"; shift 2 ;;
    --repo) WT="${2:-}"; shift 2 ;;
    --out) OUTFILE="${2:-}"; shift 2 ;;
    --repo-name) REPO_NAME="${2:-}"; shift 2 ;;
    --final-tree) FINAL_TREE="${2:-}"; shift 2 ;;
    --downgrade)
      [[ "${2:-}" == AC*=* ]] || usage
      DOWN_AC+=("${2%%=*}")
      DOWN_WHY+=("${2#*=}")
      shift 2
      ;;
    --finding) FINDINGS+=("${2:-}"); shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$TICKET" && -n "$BLOCK" && -n "$WT" && -n "$OUTFILE" ]] || usage
WT="$(cd "$WT" && pwd)"
[[ -n "$REPO_NAME" ]] || REPO_NAME="$(basename "$(adlc_main_checkout "$WT")")"
[[ -n "$FINAL_TREE" ]] || FINAL_TREE="$(git -C "$WT" rev-parse 'HEAD^{tree}')"
LOG="$(adlc_state_dir "$WT")/proof-log.jsonl"
touch "$LOG"
BODY="$(adlc_extract_block "$BLOCK")" || exit 2

# jfield <json-line> <name>  -> the raw (still JSON-escaped) string value of that field
jfield() {
  sed -nE 's/.*"'"$2"'":"(([^"\\]|\\.)*)".*/\1/p' <<<"$1" | head -n 1
}
# junesc <json-string-body>  -> readable text for the Markdown table
junesc() {
  local s="$1"
  s="${s//\\n/ }"
  s="${s//\\t/ }"
  s="${s//\\\"/\"}"
  s="${s//\\\\/\\}"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

# The criteria of this repo, as "id<TAB>surface<TAB>method<TAB>reason<TAB>assertion".
ENTRIES="$(awk -v repo="$REPO_NAME" '
  function unq(v) { sub(/^"/, "", v); sub(/"$/, "", v); return v }
  function flush() { if (id != "" && r == repo) printf "%s\t%s\t%s\t%s\t%s\n", id, s, m, why, a; id = ""; r = ""; s = ""; m = ""; why = ""; a = "" }
  /^  - id: / { flush(); id = unq(substr($0, 10)) }
  /^    surface: / { s = substr($0, 14) }
  /^    repo: / { r = substr($0, 11) }
  /^    assertion: / { a = unq(substr($0, 16)) }
  /^      method: / { m = substr($0, 15) }
  /^      reason: / { why = unq(substr($0, 15)) }
  /^seal:/ { flush() }
  END { flush() }
' <<<"$BODY")"

PROVEN=0
FLAGGED=0
ROWS=""
FLAG_NOTES=""
while IFS=$'\t' read -r id surface method reason assertion; do
  [[ -z "$id" ]] && continue
  verdict="" test="" evidence=""
  if [[ "$method" == "unbound" ]]; then
    verdict="FLAGGED: unbound"
    evidence="$(junesc "$reason")"
  else
    last="$(grep -F "\"ticket\":\"$(adlc_json_escape "$TICKET")\",\"ac\":\"$id\"" "$LOG" | tail -n 1 || true)"
    if [[ -z "$last" ]]; then
      verdict="FLAGGED: no verdict in the proof log"
    else
      result="$(jfield "$last" result)"
      test="$(junesc "$(jfield "$last" test_id)")"
      head_tree="$(jfield "$last" head_tree)"
      wt_hash="$(jfield "$last" worktree_hash)"
      dirty="$(sed -nE 's/.*"tree_dirty":(true|false).*/\1/p' <<<"$last")"
      override="$(jfield "$last" override_kind)"
      evidence="tree \`${wt_hash:0:12}\`"
      if [[ "$result" == "proven" ]]; then
        red="$(jfield "$last" prior_red_hash)"
        if [[ -n "$red" ]]; then
          note="$(grep -F "\"worktree_hash\":\"$red\"" "$LOG" | grep -F "\"test_id\":\"$(jfield "$last" test_id)\"" | grep -F '"result":"red"' | tail -n 1 || true)"
          note="$(junesc "$(jfield "$note" break_note)")"
          evidence="red at \`${red:0:12}\` → green at \`${wt_hash:0:12}\`${note:+; red because: $note}"
        fi
        if [[ -n "$override" ]]; then
          evidence="$evidence; override --$override: $(junesc "$(jfield "$last" override_reason)")"
        fi
        if [[ "$head_tree" != "$FINAL_TREE" || "$dirty" != "false" ]]; then
          verdict="FLAGGED: stale proof (not run against the final committed tree)"
        else
          verdict="proven"
          k=0
          while [[ $k -lt ${#DOWN_AC[@]} ]]; do
            if [[ "${DOWN_AC[$k]}" == "$id" ]]; then
              verdict="FLAGGED: needs-human (test-review: $(junesc "${DOWN_WHY[$k]}"))"
            fi
            k=$((k + 1))
          done
        fi
      else
        verdict="FLAGGED: $result"
        detail="$(junesc "$(jfield "$last" detail)")"
        [[ -n "$detail" ]] && evidence="$evidence; $detail"
      fi
    fi
  fi
  if [[ "$verdict" == "proven" ]]; then
    PROVEN=$((PROVEN + 1))
  else
    FLAGGED=$((FLAGGED + 1))
    FLAG_NOTES+="- **$id** — ${verdict#FLAGGED: }"$'\n'
  fi
  ROWS+="| $id | \`[$surface]\` | $(junesc "$assertion") | ${test:+\`$test\`} | $verdict | $evidence |"$'\n'
done <<<"$ENTRIES"

STATE="ready"
[[ $FLAGGED -gt 0 || ${#FINDINGS[@]} -gt 0 ]] && STATE="draft"

{
  echo "## ADLC proof report — $TICKET — \`$REPO_NAME\`"
  echo
  echo "Built by \`adlc-report.sh\` from the proof log, not from agent summaries."
  echo "Final tree: \`$FINAL_TREE\`. Proven: **$PROVEN**. Flagged: **$FLAGGED**."
  echo
  echo "| criterion | surface | assertion | proof test | verdict | evidence |"
  echo "|---|---|---|---|---|---|"
  printf '%s' "$ROWS"
  if [[ $FLAGGED -gt 0 ]]; then
    echo
    echo "### Flagged — not proven, needs a human"
    echo
    printf '%s' "$FLAG_NOTES"
  fi
  if [[ ${#FINDINGS[@]} -gt 0 ]]; then
    echo
    echo "### Confirmed review findings — this PR is a draft until a human looks"
    echo
    for f in "${FINDINGS[@]}"; do echo "- $f"; done
  fi
  echo
  echo "Proof log: \`$LOG\`"
} >"$OUTFILE"

echo "PROVEN=$PROVEN FLAGGED=$FLAGGED PR_STATE=$STATE"
