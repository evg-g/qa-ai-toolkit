---
name: refine
description: Turn one ticket written for a human into a ticket written for a human AND an agent - worked examples, settled design decisions, surface tags, bindings to real test commands, and a sealed machine block - then mark it Ready-for-Agent. User-invoked only.
argument-hint: <ticket-key>
disable-model-invocation: true
---

# /refine <ticket-key>

You turn one ticket into a **Ready-for-Agent** ticket: the human prose stays the source, and
you derive from it one sealed machine block that `/implement` can prove criterion by criterion.

This is an **interview, not a form**. You read the ticket and the code, ask the engineer only
what you cannot determine, and emit the block. A badly-run interview produces a ticket that
looks refined and is not.

The contract is in [`../../shared/acceptance-schema.md`](../../shared/acceptance-schema.md).
Read it before step 1.

## Step 0 — Resolve the tools (always first)

```bash
ADLC="<this skill's base directory>/../../scripts"   # absolute path; check it with: ls "$ADLC"
ROOT="$(cd <project root> && pwd)"                    # the folder holding .claude/adlc-config.md
```

Run every script below as `"$ADLC/<script>"` from `$ROOT`. **Deterministic work stays in bash
(Rule 5):** never compute a seal, lint a block, derive a branch name, or talk to the tracker
yourself — call the script and read its exit code.

| need | script |
|---|---|
| any tracker action | `adlc-tracker.sh <action> <KEY> …` (fetch, baseline, claim, status, transition, read-block, write-block, append, comment) |
| the shared branch name | `adlc-story-branch.sh <KEY>` |
| a worktree on that branch | `adlc-worktree.sh <repo-path> <KEY> <base>` |
| seal | `adlc-seal.sh write\|check <file>` |
| lint | `adlc-lint.sh <file>` (`--no-seal` only on the draft before sealing) |

If `.claude/adlc-config.md` is missing, stop and tell the engineer to create it from
`templates/adlc-config.template.md` in the plugin.

## How you talk to the engineer

- Plain, direct English. Short sentences, one idea each.
- **One question per message.** Ask, wait, then ask the next. Use plain chat messages, not a
  multiple-choice widget.
- **Number every question across the whole session** — Q1, Q2, … Never restart the count,
  never reuse a number.
- **Options before the recommendation.** Letter the candidates `A`, `B`, `C` on their own
  lines, each with its cost and benefit. Then open the recommendation with the letter it
  picks: "Recommend B: …". A recommendation read before the alternatives is a nudge, not a
  decision.
- Drop the letters only where one candidate genuinely exists, or it is a plain yes/no. A second
  option invented to fill the list is as bad as hiding the first.

## Step 1 — Intake

1. `adlc-tracker.sh fetch <KEY>` and read it whole.
2. `adlc-tracker.sh claim <KEY>`, then `adlc-tracker.sh transition <KEY> in-refinement`.
3. `adlc-tracker.sh baseline <KEY>` — the description verbatim, saved outside the repo before
   anything edits it. Keep the printed path; you diff against it at the end.
4. Confirm the repo scope (which repos from `.claude/adlc-config.md` this ticket touches) and
   the base ref per repo. One question if it is not obvious from the ticket and the code.
5. In each repo in scope, read: `CLAUDE.md`, `CONTEXT.md`, `docs/adr/`, and
   `.claude/surface-bindings.json`. If a repo in scope has no bindings file, stop: the ticket
   cannot bind. Say which repo.
6. If a machine block already exists (`read-block` exits 0), this is a re-refine: read it, but
   you will regenerate the whole block from the prose, not patch it.

## Step 2 — Product pass

Turn each abstract criterion into **worked examples**: enumerate the scenarios, set the
expected outcome of each, and record the enumeration boundary (which partition is covered,
what is out of scope).

Ration questions with the **knob razor**: a question earns an interactive turn only when a
wrong answer cannot later be fixed by changing a value.

- Wrong and adjustable → a **knob**. Set it, pin it in a worked example, record it under
  `defaulted:`. Do not ask.
- Wrong and ships something irreversible (mail, money, notifications, third-party writes, data
  loss, a public contract) → **not a knob. Ask.**

The pass closes when **every criterion has a confirmed example ledger** — not when your
question list is empty. The initial list is a floor, never a ceiling. Show the ledger for a
criterion and get a yes before you move on from it.

A criterion that is defective (two behaviours in one line, untestable wording, contradicts
another) may be amended in place in the prose, with the visible marker
`_(amended by /refine: <why>)_` — only after the engineer agrees. Never silently.

## Step 3 — Design pass

Settle every technical decision an implementing agent would otherwise have to stop and ask
about: data shape, migrations, endpoint and contract changes, error semantics, where state
lives, which component owns what, feature flags, stubs for irreversible effects.

**No razor applies here — grill every flagged decision.** Technical judgment is the scarce
input, and this is where it belongs. The pass closes on the engineer's own judgment that
nothing is left open; ask "Is anything still open?" and take the answer literally.

## Step 4 — Tag and bind

1. Give each criterion a surface tag. **Decompose** a criterion that crosses surfaces into one
   entry per surface: `AC1.data`, `AC1.api`, `AC1.ui`.
2. Bind each entry to a method in that repo's `surface-bindings.json` whose `surface` list
   covers it. `[component]`/`[ui]` need a real browser binding; a jsdom runner is `[logic]` only.
3. A criterion that binds to nothing is **flagged now**: tell the engineer, and either change
   the criterion, add a harness later, or bind it as `method: unbound` with a `reason:`. An
   unbound entry is carried, flagged in the report, and never reported proven.
4. Set `irreversible: true` for anything that escapes the system boundary. When unsure, `true`.

## Step 5 — Deposit

For each repo whose design decisions you settled:

1. `WT="$("$ADLC/adlc-worktree.sh" <repo-path> <KEY> <base>)"` — the shared branch
   `story/<KEY>`, never a separate design branch. That is what lets one PR carry both the
   design and the code.
2. Write each decision as an ADR under `$WT/docs/adr/` (follow the repo's numbering and
   template if it has one; otherwise `NNNN-<slug>.md` with Context / Decision / Consequences).
   Update `$WT/CONTEXT.md` (create it if missing: a short glossary of the domain terms this
   ticket uses).
3. Commit in `$WT` with a conventional message (`docs(<scope>): ADRs for <KEY>`), then
   `git -C "$WT" push -u origin story/<KEY>`. Ask before the first push in a session.
4. Append the links to the human zone: write a `## Links` section (ADR paths, branch) and, if
   any, `## Open decisions` (things deliberately deferred, each with an owner) to a temp file
   and run `adlc-tracker.sh append <KEY> <file>`.

Skip the worktree for repos with nothing to deposit.

## Step 6 — Emit, seal, lint

1. Write the **whole** block to `~/.adlc/tickets/<KEY>/block.md` as a ```` ```adlc ```` fence,
   exactly in the format of the schema. Without the `seal:` line.
2. `adlc-lint.sh <file> --no-seal` — fix every message, re-run until exit 0. The messages name
   the entry and the field; fix the data, never the lint.
3. `adlc-seal.sh write <file>`, then `adlc-lint.sh <file>` — must exit 0 with the seal checked.
4. `adlc-tracker.sh write-block <KEY> <file>` (it refuses an unsealed block).
5. Round trip: `adlc-tracker.sh read-block <KEY> <tmp>` then `adlc-lint.sh <tmp>` — must exit
   0. This proves the tracker stored the block verbatim.

A lint failure is fixed **before** the ticket is marked ready, never after.

## Step 7 — Mark ready

Only now: `adlc-tracker.sh transition <KEY> ready-for-agent`.

Then tell the engineer, in a few lines: the criteria count per surface and repo, every
`defaulted:` knob, every flagged/unbound entry and why, the ADRs written, and that the
prose changed only by appends (diff the human zone against the baseline file — show any
in-place amendment).

## Never

- Never hand-edit a sealed block, and never "fix" one by resealing a hand edit. Regenerate.
- Never mark a ticket ready with a lint failure, an unbound entry the engineer has not seen,
  or an open design question.
- Never write code or tests here. `/implement` does that.
