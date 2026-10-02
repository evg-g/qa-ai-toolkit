#!/usr/bin/env bash
# Both tracker adapters through the one interface (adlc-tracker.sh): Markdown on a temp
# project, Jira against tests/fake_jira.py.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

P="$WORK/project"
mkdir -p "$P/.claude" "$P/docs/tickets"
git -C "$P" init -q
git -C "$P" config user.name "Test Person"
write_config() {
  cat >"$P/.claude/adlc-config.md" <<EOF
# test config
\`\`\`adlc-config
tracker: $1
tickets_dir: "docs/tickets"
statuses:
  draft: "$2"
  in_refinement: "Refining"
  ready_for_agent: "Ready for Agent"
  in_progress: "In Progress"
  in_review: "In Review"
  done: "Done"
repos:
  - name: demo-api
    path: "demo-api"
    base: main
\`\`\`
EOF
}
T() { (cd "$P" && "$SCRIPTS/adlc-tracker.sh" "$@"); }

# A sealed block to store.
BLOCK="$WORK/block.md"
awk '/^```adlc/,/^```$/' "$FIX/valid-ticket.md" >"$BLOCK"
"$SCRIPTS/adlc-seal.sh" check "$BLOCK" >/dev/null || not_ok "fixture block is not sealed"
BAD="$WORK/bad-block.md"
sed 's/notifications disabled/notifications enabled/' "$BLOCK" >"$BAD"
printf '## Links\n\n- ADR: docs/adr/0001-x.md\n' >"$WORK/append.md"

echo "markdown"
write_config markdown draft
sed 's/PROJ-1/DEMO-1/g' "$TESTS_DIR/../templates/ticket.template.md" >"$P/docs/tickets/DEMO-1.md"
expect 0 "^draft$" "status reads the front matter" -- T status DEMO-1
expect 0 "assigned to Test Person" "claim assigns to the git user" -- T claim DEMO-1
grep -q '^assignee: "Test Person"$' "$P/docs/tickets/DEMO-1.md" && ok "   assignee written" || not_ok "   assignee not written"
expect 3 "no machine block" "read-block before refine -> exit 3" -- T read-block DEMO-1 "$WORK/out.md"
expect 1 "refusing to store a block whose seal does not verify" "write-block refuses an unsealed block" -- T write-block DEMO-1 "$BAD"
expect 0 "machine block written" "write-block stores a sealed block" -- T write-block DEMO-1 "$BLOCK"
expect 0 "machine block written" "write-block again replaces it (still one block)" -- T write-block DEMO-1 "$BLOCK"
[[ "$(grep -c '^```adlc' "$P/docs/tickets/DEMO-1.md")" -eq 1 ]] && ok "   exactly one block in the file" || not_ok "   block duplicated"
expect 0 "appended" "append adds to the human zone" -- T append DEMO-1 "$WORK/append.md"
awk '/^## Links/ { l = NR } /^```adlc/ { b = NR } END { exit !(l && b && l < b) }' "$P/docs/tickets/DEMO-1.md" && ok "   appended text sits above the machine zone" || not_ok "   appended text is not above the machine zone"
grep -q '^1. One criterion per line' "$P/docs/tickets/DEMO-1.md" && ok "   the original prose is untouched" || not_ok "   the prose changed"
expect 0 "-" "read-block returns the block" -- T read-block DEMO-1 "$WORK/out.md"
expect 0 "seal ok" "   and its seal still verifies" -- "$SCRIPTS/adlc-seal.sh" check "$WORK/out.md"
expect 0 "-> ready-for-agent" "transition writes the state" -- T transition DEMO-1 ready-for-agent
expect 0 "^ready-for-agent$" "   status reads it back" -- T status DEMO-1
expect 2 "unknown state" "an unknown state is refused" -- T transition DEMO-1 shipped
expect 0 "- Assignee|DEMO-1: Short title" "fetch prints the human zone" -- T fetch DEMO-1
T fetch DEMO-1 | grep -q 'sha256' && not_ok "   fetch leaked the machine zone" || ok "   fetch leaves out the machine zone"
expect 0 "baseline-" "baseline saves the description verbatim outside the repo" -- T baseline DEMO-1

echo "jira (fake server)"
write_config jira "To Do"
PORTF="$WORK/port"
python3 "$TESTS_DIR/fake_jira.py" "$PORTF" &
FAKE=$!
trap 'kill $FAKE 2>/dev/null; rm -rf "$WORK"' EXIT
for _ in $(seq 50); do [[ -s "$PORTF" ]] && break; sleep 0.1; done
export JIRA_BASE_URL="http://127.0.0.1:$(cat "$PORTF")" JIRA_EMAIL=me@example.invalid JIRA_API_TOKEN=secret
expect 0 "Export a CSV of fridge readings" "fetch" -- T fetch DEMO-7
expect 0 "^draft$" "status maps 'To Do' back to draft" -- T status DEMO-7
expect 0 "assigned to Test User" "claim" -- T claim DEMO-7
expect 3 "no machine-block comment" "read-block before refine -> exit 3" -- T read-block DEMO-7 "$WORK/j.md"
expect 0 "new comment" "write-block posts one comment" -- T write-block DEMO-7 "$BLOCK"
expect 0 "-" "read-block" -- T read-block DEMO-7 "$WORK/j.md"
expect 0 "seal ok" "   the seal survives the round trip (CRLF included)" -- "$SCRIPTS/adlc-seal.sh" check "$WORK/j.md"
expect 0 "updated in comment" "write-block again updates the same comment" -- T write-block DEMO-7 "$BLOCK"
expect 0 "-> Refining" "transition to in-refinement uses the mapped name" -- T transition DEMO-7 in-refinement
expect 1 "no transition .* 'Done'" "an impossible transition names the available ones" -- T transition DEMO-7 done
expect 0 "-> Ready for Agent" "transition to ready-for-agent" -- T transition DEMO-7 ready-for-agent
expect 0 "^ready-for-agent$" "   status reads it back" -- T status DEMO-7
expect 0 "appended" "append to the description" -- T append DEMO-7 "$WORK/append.md"
expect 0 "comment [0-9]+ added" "comment" -- T comment DEMO-7 "$WORK/append.md"
JIRA_API_TOKEN=wrong expect 1 "HTTP 401" "bad credentials fail loudly" -- T fetch DEMO-7
expect 1 "HTTP 404" "unknown issue fails loudly" -- T fetch DEMO-99

finish
