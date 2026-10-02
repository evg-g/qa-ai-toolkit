#!/usr/bin/env bash
# The report is built from the log: proven only with a log line at the final tree; every
# other criterion is flagged and named; any flag or finding makes the PR a draft.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

R="$WORK/demo-api"
mkdir -p "$R/tests" "$R/.claude"
git -C "$R" init -q -b main
git -C "$R" config user.email test@example.invalid
git -C "$R" config user.name test
echo off >"$R/feature.txt"
printf '# @agent-trusted\ngrep -qx on feature.txt\n' >"$R/tests/feature-on.sh"
printf '# @agent-trusted\ntrue\n' >"$R/tests/always.sh"
cat >"$R/.claude/surface-bindings.json" <<'EOF'
{ "repo": "demo-api", "bindings": { "sh-logic": { "surface": ["logic"], "runner": "sh", "location": "tests" } } }
EOF
git -C "$R" add -A && git -C "$R" commit -qm init

T="$WORK/ticket.md"
cat >"$T" <<'EOF'
```adlc
feature: "DEMO-2 report"
repos:
  - demo-api
acceptance:
  - id: "AC1.logic"
    surface: logic
    repo: demo-api
    assertion: "The feature flag reads on."
    enum_boundary: "flag file only."
    irreversible: false
    binding:
      method: sh-logic
    examples:
      - scenario: "flag file says on"
        outcome: "test passes"
  - id: "AC2.logic"
    surface: logic
    repo: demo-api
    assertion: "Always true."
    enum_boundary: "none."
    irreversible: false
    binding:
      method: sh-logic
    examples:
      - scenario: "any"
        outcome: "true"
  - id: "AC3.logic"
    surface: logic
    repo: demo-api
    assertion: "A mail is sent."
    enum_boundary: "outbound mail only."
    irreversible: true
    binding:
      method: unbound
      reason: "No harness reaches the mail relay."
    examples:
      - scenario: "user signs up"
        outcome: "one mail queued"
  - id: "AC4.logic"
    surface: logic
    repo: demo-api
    assertion: "Never dispatched."
    enum_boundary: "none."
    irreversible: false
    binding:
      method: sh-logic
    examples:
      - scenario: "any"
        outcome: "any"
```
EOF
"$SCRIPTS/adlc-seal.sh" write "$T" >/dev/null
expect 0 "ok \(4 criteria" "the report fixture lints clean" -- "$SCRIPTS/adlc-lint.sh" "$T" --bindings "demo-api=$R/.claude/surface-bindings.json"

p() { "$SCRIPTS/adlc-proof.sh" --repo "$R" --ticket DEMO-2 --binding sh-logic "$@" >/dev/null 2>&1; }
p --ac AC1.logic --test feature-on.sh --break-note "flag file still says off"
echo on >"$R/feature.txt"
git -C "$R" commit -qam "turn it on"
p --ac AC1.logic --test feature-on.sh
p --ac AC2.logic --test always.sh

rep() { "$SCRIPTS/adlc-report.sh" --ticket DEMO-2 --block "$T" --repo "$R" --out "$WORK/report.md" "$@"; }
expect 0 "PROVEN=1 FLAGGED=3 PR_STATE=draft" "one proven, three flagged, draft" -- rep
grep -q '| AC1.logic | `\[logic\]` .* | proven | red at ' "$WORK/report.md" && ok "AC1 proven with red->green evidence" || not_ok "AC1 row wrong"
grep -q 'red because: flag file still says off' "$WORK/report.md" && ok "the red's break_note reaches the report" || not_ok "break_note missing"
grep -q '| AC2.logic .*FLAGGED: green-no-red-observed' "$WORK/report.md" && ok "AC2 green-no-red-observed is flagged, not rounded up" || not_ok "AC2 row wrong"
grep -q '| AC3.logic .*FLAGGED: unbound | No harness reaches the mail relay.' "$WORK/report.md" && ok "AC3 unbound is named with its reason" || not_ok "AC3 row wrong"
grep -q '| AC4.logic .*FLAGGED: no verdict in the proof log' "$WORK/report.md" && ok "AC4 with no log line is flagged" || not_ok "AC4 row wrong"

echo "change" >>"$R/feature.txt"
git -C "$R" commit -qam "later change"
expect 0 "PROVEN=0 FLAGGED=4" "a proof from an older tree is stale" -- rep
grep -q 'AC1.logic .*FLAGGED: stale proof' "$WORK/report.md" && ok "AC1 now reads stale" || not_ok "AC1 should be stale"
p --ac AC1.logic --test feature-on.sh
expect 0 "PROVEN=1" "re-dispatching at the final tree proves it again" -- rep
expect 0 "PROVEN=0 FLAGGED=4 PR_STATE=draft" "a test-review downgrade makes it needs-human" -- rep --downgrade "AC1.logic=assertion only checks the file exists"
grep -q 'needs-human (test-review: assertion only checks the file exists)' "$WORK/report.md" && ok "the downgrade reason is shown" || not_ok "downgrade reason missing"

finish
