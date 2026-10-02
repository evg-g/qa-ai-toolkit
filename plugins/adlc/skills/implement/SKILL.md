---
name: implement
description: Take one Ready-for-Agent ticket, prove every acceptance criterion with a durable test through the proof runner, and open one pull request per repo carrying the evidence. Runs unattended. User-invoked only.
argument-hint: <ticket-key>
disable-model-invocation: true
---

# /implement <ticket-key>

You are the **orchestrator** (depth 0). You claim, gate, dispatch, report, and open PRs. You do
not write product code or tests yourself, and you never prove a criterion inline.

Run unattended: do not stop to ask questions after the claim gate. When something cannot be
done, flag it in the report and carry on.

The contract is in [`../../shared/acceptance-schema.md`](../../shared/acceptance-schema.md).

## The five rules you enforce

1. The machine block is sealed; a seal that does not verify stops the run at the gate.
2. Every criterion has a binding to a real command, or is flagged.
3. A test must be seen failing before its pass counts. Only `RESULT=proven` from
   `adlc-proof.sh` counts. `green-no-red-observed` is not proof and is never rounded up.
4. An unprovable criterion is flagged, never skipped, never quietly rewritten. The only thing
   that stops the whole run after the gate is a **false claim**: a criterion reported proven
   with no `proven` verdict in the log behind it.
5. Deterministic work stays in bash. You call scripts and read exit codes.

## Step 0 — Resolve the tools

```bash
ADLC="<this skill's base directory>/../../scripts"   # absolute; check with: ls "$ADLC"
ROOT="<project root>"                                 # holds .claude/adlc-config.md
KEY="<ticket-key>"
STATE="${ADLC_LOG_HOME:-$HOME/.adlc}/tickets/$KEY"; mkdir -p "$STATE"
```

## Step 1 — Claim: the only hard gate

Run, in order, from `$ROOT`. **Any non-zero exit stops the run here** with the script's own
message shown to the user. Nothing downstream re-checks this gate.

```bash
"$ADLC/adlc-tracker.sh" status "$KEY"                       # must print: ready-for-agent
"$ADLC/adlc-tracker.sh" read-block "$KEY" "$STATE/block.md"
"$ADLC/adlc-lint.sh" "$STATE/block.md"                      # structure + bindings + seal
"$ADLC/adlc-seal.sh" check "$STATE/block.md"                # the seal, explicitly
"$ADLC/adlc-tracker.sh" claim "$KEY"
"$ADLC/adlc-tracker.sh" transition "$KEY" in-progress
```

If the status is not `ready-for-agent`, stop and say: "Run /refine <KEY> first."
If the seal fails, stop and say the block was edited after `/refine` emitted it.

## Step 2 — Group by repo

- Split the criteria by their `repo` field (read them from `$STATE/block.md`).
- `BRANCH="$("$ADLC/adlc-story-branch.sh" "$KEY")"` — never build the name yourself.
- For each repo: its path and `base` from `.claude/adlc-config.md`.
- If a repo's criteria are all `unbound`, it still gets an agent: the report and PR must name
  them.

## Step 3 — Dispatch one repo agent per repo, concurrently

Spawn `adlc:implement-repo` once per repo, **all in one message** so they run in parallel.
Give each one exactly this, with absolute paths:

```
ticket: <KEY>
repo_name: <name>
repo_path: <absolute path of the main checkout>
base: <base branch>
branch: <BRANCH>
block_file: <STATE>/block.md
criteria: <the AC ids of this repo, in order>
adlc_scripts: <absolute $ADLC>
```

Each returns a compact block (see the agent's "Return" section): worktree, pushed head,
per-criterion claim, confirmed review findings, test-review downgrades. **Treat its claims as
claims.** The log decides.

If a repo agent returns `NESTING-UNAVAILABLE` (it could not spawn provers), run that repo's
slices yourself: spawn `adlc:implement-prover` per slice serially, then `adlc:standards-review`,
then `adlc:test-review` and `adlc:code-review`, with the same inputs the repo agent would have
given, then do its final re-proof and push steps. The rule stays the same: each child returns
a verdict, never a transcript.

## Step 4 — Build the report from the proof log

For each repo:

```bash
"$ADLC/adlc-report.sh" --ticket "$KEY" --block "$STATE/block.md" \
  --repo <worktree> --repo-name <name> --out "$STATE/report-<name>.md" \
  [--downgrade "<AC>=<test-review reason>"]... [--finding "<confirmed defect, file:line>"]...
```

It prints `PROVEN=<n> FLAGGED=<n> PR_STATE=ready|draft`. The final tree defaults to the
worktree's `HEAD^{tree}`; a proof against any other tree reads as stale.

Then check two things deterministically:

1. **Pushed = reported.** `git -C <worktree> rev-parse HEAD` equals
   `git -C <worktree> ls-remote origin refs/heads/$BRANCH`. If not, push failed: flag the repo.
2. **No false claims.** Every criterion the repo agent claimed `proven` must read `proven` in
   the report. If any does not, that is a false claim: **stop the run** — do not open PRs, do
   not transition the ticket. Show the user the agent's claim next to the report row, and the
   proof log path.

## Step 5 — Open one PR per repo

From each worktree, with `gh`:

```bash
gh pr create --base <base> --head "$BRANCH" --title "<KEY>: <feature title>" \
  --body-file "$STATE/report-<name>.md" [--draft]
```

- `--draft` when the report says `PR_STATE=draft`: any flagged criterion or any confirmed
  review finding. Nothing is silently dropped and nothing is silently merged.
- If a PR for the branch already exists, update its body (`gh pr edit --body-file`) and, if the
  state must be draft, `gh pr ready --undo`.
- Never merge. Never enable auto-merge.

## Step 6 — Transition and hand off

- `adlc-tracker.sh transition "$KEY" in-review`
- `adlc-tracker.sh comment "$KEY" <file>` with the PR links and the per-repo
  `PROVEN/FLAGGED` counts.
- Tell the user, briefly: PR links, which are drafts and why, every flagged criterion, every
  override used (they are in the report), and the proof log paths.

## Never

- Never prove, write tests, or write product code at depth 0.
- Never edit the block, reseal it, or pass an override flag yourself.
- Never report a criterion proven from an agent's words. Only the report, built from the log.
