#!/usr/bin/env bash
# Phase 5 acceptance on a throwaway repo with the `sh` adapter: red, proven,
# green-no-red-observed, flaky-refused — plus the guards around them.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

R="$WORK/repo"
mkdir -p "$R/tests"
git -C "$R" init -q -b main
git -C "$R" config user.email test@example.invalid
git -C "$R" config user.name test
echo "off" >"$R/feature.txt"
cat >"$R/tests/feature-on.sh" <<'EOF'
# @agent-trusted
grep -qx on feature.txt
EOF
cat >"$R/tests/always.sh" <<'EOF'
# @agent-trusted
true
EOF
cat >"$R/tests/untagged.sh" <<'EOF'
true
EOF
# Flaky by design: its result comes from a file outside the worktree.
cat >"$R/tests/flaky.sh" <<EOF
# @agent-trusted
[[ -f "$WORK/flaky-pass" ]]
EOF
cat >"$R/tests/broken.sh" <<'EOF'
# @agent-trusted
exit 3
EOF
cat >"$R/tests/slow.sh" <<'EOF'
# @agent-trusted
sleep 20
EOF
git -C "$R" add -A
git -C "$R" commit -qm init

proof() { "$SCRIPTS/adlc-proof.sh" --repo "$R" --ticket DEMO-1 --runner sh --location tests "$@"; }
log() { cat "$ADLC_LOG_HOME"/*/proof-log.jsonl 2>/dev/null; }
lines() { log | wc -l | tr -d ' '; }

echo "the four acceptance checks"
expect 1 "RESULT=red" "1. failing test -> red, exit 1" -- proof --ac AC1.logic --test feature-on.sh --break-note "feature.txt says off"
[[ "$(lines)" -eq 1 ]] && ok "   exactly one log line" || not_ok "   expected one log line, got $(lines)"
echo "on" >"$R/feature.txt"
expect 0 "RESULT=proven" "2. code fixed, same test -> proven, exit 0" -- proof --ac AC1.logic --test feature-on.sh
log | tail -n 1 | grep -q '"prior_red_hash":"[0-9a-f]\{40\}"' && ok "   proven line names the prior red's tree" || not_ok "   proven line has no prior_red_hash"
expect 0 "RESULT=green-no-red-observed" "3. always-passing test, no prior red -> green-no-red-observed" -- proof --ac AC2.logic --test always.sh
rm -f "$WORK/flaky-pass"
expect 1 "RESULT=red" "4a. flaky test fails" -- proof --ac AC3.logic --test flaky.sh
touch "$WORK/flaky-pass"
expect 1 "RESULT=flaky-refused" "4b. same tree, now green -> flaky-refused" -- proof --ac AC3.logic --test flaky.sh
expect 0 "RESULT=green-no-red-observed" "4c. accept-green on a same-tree red with no red elsewhere is still not proven" -- proof --ac AC3.logic --test flaky.sh --accept-green "flaky.sh reads an external flag file by design"
log | tail -n 1 | grep -q '"override_kind":"accept-green"' && ok "   the override is logged" || not_ok "   the override was not logged"

echo "guards"
n="$(lines)"
expect 2 "--ac is required" "no --ac -> exit 2" -- proof --test always.sh
expect 2 "not tagged @agent-trusted" "untagged test cannot be selected" -- proof --ac AC2.logic --test untagged.sh
expect 2 "needs real prose" "override with no prose is refused" -- proof --ac AC3.logic --test flaky.sh --accept-green "ok"
expect 2 "only one override" "two overrides in one dispatch are refused" -- proof --ac AC3.logic --test flaky.sh --accept-green "a long enough reason to pass" --no-red-reason "another long enough reason"
[[ "$(lines)" -eq "$n" ]] && ok "   refused dispatches log nothing" || not_ok "   a refused dispatch wrote to the log"

expect 1 "RESULT=build-error" "a build error is not a red" -- proof --ac AC4.logic --test broken.sh
printf '# @agent-trusted\ntrue\n' >"$R/tests/broken.sh"
expect 0 "RESULT=green-no-red-observed" "   ...and never counts as a prior red" -- proof --ac AC4.logic --test broken.sh

expect 1 "RESULT=timed-out" "wall-clock bound -> timed-out" -- proof --ac AC5.logic --test slow.sh --timeout-secs 1
printf '# @agent-trusted\ntrue\n' >"$R/tests/slow.sh"
expect 0 "RESULT=green-no-red-observed" "   ...and a timeout never counts as a prior red" -- proof --ac AC5.logic --test slow.sh


expect 0 "RESULT=proven" "--no-red-reason promotes green-no-red-observed to proven" -- proof --ac AC2.logic --test always.sh --no-red-reason "always.sh is a fixture; non-vacuity argued in the test plan"
log | tail -n 1 | grep -q '"override_kind":"no-red-reason","override_reason":"always.sh is a fixture' && ok "   the prose is in the log" || not_ok "   the prose is not in the log"

rm -f "$WORK/flaky-pass"
expect 0 "RESULT=infra-exempt" "--infra-exempt forces a red to infra-exempt" -- proof --ac AC3.logic --test flaky.sh --infra-exempt "the flag file lives on a mount that was offline"

echo "tree identity"
h1="$(log | tail -n 1 | sed -n 's/.*"worktree_hash":"\([0-9a-f]*\)".*/\1/p')"
echo "scratch" >"$R/untracked.txt"
proof --ac AC2.logic --test always.sh >/dev/null 2>&1
h2="$(log | tail -n 1 | sed -n 's/.*"worktree_hash":"\([0-9a-f]*\)".*/\1/p')"
[[ -n "$h1" && "$h1" != "$h2" ]] && ok "an untracked file moves the worktree hash" || not_ok "worktree hash did not move ($h1 vs $h2)"
log | tail -n 1 | grep -q '"tree_dirty":true' && ok "uncommitted content is marked tree_dirty" || not_ok "tree_dirty not set"
git -C "$R" status --porcelain | grep -q '^?? untracked.txt' && ok "the real index is untouched (file still untracked)" || not_ok "the real index was changed"

echo "the log survives the worktree"
git -C "$R" clean -fdxq
git -C "$R" checkout -q -- .
[[ "$(lines)" -gt 10 ]] && ok "git clean does not erase the log" || not_ok "log lost after git clean"
case "$(dirname "$(ls "$ADLC_LOG_HOME"/*/proof-log.jsonl)")" in
  "$R"*) not_ok "the log is inside the worktree" ;;
  *) ok "the log lives outside the worktree" ;;
esac
git -C "$R" worktree add -q "$WORK/wt2" -b other
echo "off" >"$WORK/wt2/feature.txt"
"$SCRIPTS/adlc-proof.sh" --repo "$WORK/wt2" --ticket DEMO-1 --runner sh --location tests --ac AC1.logic --test feature-on.sh >/dev/null 2>&1
[[ "$(ls "$ADLC_LOG_HOME"/*/proof-log.jsonl | wc -l)" -eq 1 ]] && ok "a second worktree of the same repo writes to the same log" || not_ok "a second worktree got its own log"

finish
