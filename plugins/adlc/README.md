# ADLC — the /refine → /implement proof loop

ADLC (Agentic Development LifeCycle) turns a ticket into merged-ready code with proof, without
a human watching each step:

```
/refine  →  a Ready-for-Agent ticket  →  /implement  →  one PR per repo, with proof
```

- `/refine <KEY>` interviews you and turns a ticket written for a human into one written for a
  human **and** an agent: worked examples, settled design decisions (ADRs), surface tags,
  bindings to real test commands, and a **sealed** machine block.
- `/implement <KEY>` proves every acceptance criterion with a durable test, through a proof
  runner that will not count a green it never saw fail, and opens one PR per repo with the
  evidence. A flagged criterion or a confirmed review defect makes the PR a draft.

This is the core loop only (the "walking skeleton"). See [What is left out](#what-is-left-out).

## The five rules

| # | rule | enforced by |
|---|---|---|
| 1 | The ticket has two zones; the machine zone is sealed (`sha256`) and never hand-edited. | `adlc-seal.sh`, checked at the `/implement` gate |
| 2 | Every criterion names its surface and a binding that maps to a real test command. | `adlc-lint.sh` against `.claude/surface-bindings.json` |
| 3 | A test must be seen failing before its pass counts. No retry-to-green. The log lives outside the worktree. | `adlc-proof.sh` (tree hash + append-only log) |
| 4 | An unprovable criterion is flagged, never skipped. Only a false claim stops the run. | `adlc-report.sh` builds the PR body from the log |
| 5 | Deterministic work stays in bash; judgment stays in the model. | everything in `scripts/` |

## What is in it

```
plugins/adlc/
├── .claude-plugin/plugin.json
├── skills/refine/SKILL.md          /refine  (user-invoked only)
├── skills/implement/SKILL.md       /implement (user-invoked only, unattended)
├── agents/                         implement-repo (depth 1), implement-prover (depth 2),
│                                   standards-review, test-review, code-review (depth 2),
│                                   proof-investigator (depth 3)
├── scripts/
│   ├── adlc-seal.sh                write / check the seal
│   ├── adlc-lint.sh                structural lint of the block (pure bash, no jq/yq/node)
│   ├── adlc-proof.sh               the proof runner: the only way a test becomes a verdict
│   ├── adlc-report.sh              per-repo report + PR state, from the log
│   ├── adlc-evidence.sh            one criterion's red/green evidence (for test-review)
│   ├── adlc-tracker.sh             the one door to the tracker
│   ├── adlc-story-branch.sh        the one home of the branch name: story/<KEY>
│   ├── adlc-worktree.sh            create/reuse the ticket's worktree outside the repo
│   ├── adlc-heartbeat.sh           "still alive" lines outside the worktree
│   └── lib/
│       ├── proof-adapters/         pytest, vitest, playwright, sh  (+ README: how to add one)
│       └── trackers/               markdown.sh, jira.py            (see below: how to add one)
├── shared/acceptance-schema.md     the ticket contract: block format, surfaces, bindings
├── templates/                      adlc-config.template.md, ticket.template.md
└── tests/                          self-tests: run-all.sh (98 checks, incl. a fake Jira)
```

## Install

From this repo (the marketplace is the repo root):

```bash
claude plugin marketplace add evg-g/qa-ai-toolkit        # or a local path to a clone
cd <project-root>                                        # where .claude/adlc-config.md will live
claude plugin install adlc@qa-ai-toolkit --scope project
```

Start a new Claude Code session at the project root. `/adlc:refine` and `/adlc:implement`
appear in the skill list (also as `/refine` and `/implement` when no other skill has the name).

Requirements: bash, git, POSIX awk/sed/grep, coreutils `timeout` (`gtimeout` on macOS), `gh`
for PRs, `python3` for the Jira adapter only.

## Adapt it to a project (a new job, a new codebase)

Ask Claude Code at the project root: *"Follow plugins/adlc/README.md from qa-ai-toolkit to set
up ADLC here."* It must do Phase 0 first — ask, do not guess.

1. **Phase 0 — ask the engineer**, one question per message, options before the
   recommendation:
   1. Issue tracker — Jira, Markdown files (`docs/tickets/`), or another (→ write an adapter).
   2. Repo layout — one repo or several that ship together (local paths).
   3. Test harness per surface — the exact command that runs **one** named test.
   4. Proof test isolation — the marker/tag (`agent_trusted` / `@agent-trusted`).
   5. Base branch and CI — what must pass before merge.
2. **Config.** Copy `templates/adlc-config.template.md` to `<root>/.claude/adlc-config.md` and
   fill in the block and the five answers.
3. **Bindings.** In each repo, write `.claude/surface-bindings.json` (format in
   `shared/acceptance-schema.md`) and commit it. Python repos with `--strict-markers` must
   register the `agent_trusted` marker in `pyproject.toml`/`pytest.ini`.
4. **Check each binding by hand** (Phase 3): tag one existing test, run
   `adlc-proof.sh --repo <repo> --ticket SETUP --ac AC1.<surface> --binding <method> --test <name>`.
   It must select exactly that test (`green-no-red-observed`), go `red` when you break it, and
   read `proven` once fixed. Untag the test afterwards. Use `ADLC_LOG_HOME=/tmp/x` so the setup
   runs do not land in the real log.
5. Refine one small real ticket, implement it, and run the Phase 8 checks (below).

### Jira

Set `tracker: jira` and map `statuses:` to your workflow's status names
(e.g. `ready_for_agent: "Ready for Agent"`; add that status to the workflow if it is missing).
Then, in the environment (never in a file you commit):

```bash
export JIRA_BASE_URL=https://<company>.atlassian.net
export JIRA_EMAIL=<you>@<company>   JIRA_API_TOKEN=<token>      # Jira Cloud
# or: export JIRA_PAT=<personal access token>                   # Jira Server / Data Center
```

The adapter uses the REST API v2 directly — no MCP connector needed. The machine block goes
in one dedicated comment as a `{noformat}` panel, which keeps the text verbatim so the seal
survives. Check it once on a real instance: `adlc-tracker.sh write-block`, then `read-block`,
then `adlc-seal.sh check` on the result. It is tested here against `tests/fake_jira.py` only.

### Another tracker (GitHub Issues, Linear, Azure Boards, …)

Add `scripts/lib/trackers/<name>.sh` (or `.py`) and set `tracker: <name>`. It is called as
`<adapter> <action> <KEY> [file]` with these actions and exit codes:

| action | does | exit |
|---|---|---|
| `fetch KEY` | print the ticket's human zone as Markdown | 0 / 1 |
| `status KEY` | print the canonical state, or `other:<name>` | 0 / 1 |
| `transition KEY STATE` | move to the tracker status named by `$ADLC_STATUS_<STATE>` | 0 / 1 |
| `claim KEY` | assign to the current user | 0 / 1 |
| `read-block KEY OUT` | write the block to OUT as a ```` ```adlc ```` fence | 0, 3 none, 4 several |
| `write-block KEY FILE` | store the block from FILE, replacing the old one (one per ticket) | 0 / 1 |
| `append KEY FILE` | append FILE to the human zone; never rewrite it | 0 / 1 |
| `comment KEY FILE` | add FILE as a comment | 0 / 1 |

`adlc-tracker.sh` does the rest (argument checks, the seal check before `write-block`,
`baseline`). Copy `tests/test-trackers.sh`'s Jira section to test it against a fake.

### Another test harness

Add `scripts/lib/proof-adapters/<runner>.sh` — see the README in that folder. The core never
changes.

## Using it

```bash
# write docs/tickets/PROJ-7.md from templates/ticket.template.md (Markdown tracker), then:
/refine PROJ-7        # interview → ADRs on story/PROJ-7 → sealed block → ready-for-agent
/implement PROJ-7     # gate → one repo agent per repo → proofs → reviews → PRs → in-review
```

Where things are:

| what | where |
|---|---|
| proof log (append-only, per repo) | `~/.adlc/<repo-path>/proof-log.jsonl` (set `ADLC_LOG_HOME` to move it) |
| each dispatch's full output | `~/.adlc/<repo-path>/runs/` |
| heartbeat | `~/.adlc/<repo-path>/heartbeat-<KEY>.log` |
| worktrees | `~/.adlc/worktrees/<repo>/<KEY>` |
| ticket working files (block, reports, baselines) | `~/.adlc/tickets/<KEY>/` |

## Verify the loop end to end (Phase 8)

1. **The seal is load-bearing.** Edit one character in the stored block. `/implement` must
   refuse at the gate.
2. **Non-vacuity is real.** Pick a `proven` criterion; find its red in the proof log at a
   different `worktree_hash`, before the green.
3. **The report matches the log.** Every criterion in the PR body has a log line.
4. **A flagged criterion survives.** One unprovable criterion: the run completes, opens a
   (draft) PR, and names it.
5. **A defect drafts the PR.** Swallow an error into an empty success response; the PR opens
   as a draft and the finding names it.

If 2 or 3 fails, stop and fix the runner.

## Design notes

- **Isolation by construction.** The adapter adds the agent-trusted filter itself and refuses
  arguments that would widen it, so a proof can never select a pre-existing passing test.
- **Tree hash.** `git add -A` + `write-tree` in a throwaway index: it moves on any change
  (including untracked files) without touching your index. It is a tripwire, not a commit
  tree. `head_tree` is the commit-comparable anchor; the report accepts a proof only at the
  final committed tree with a clean worktree.
- **Exactly one test.** A selection that runs zero or several tests is a `build-error`, never
  a red or a green.
- **Overrides** (`--no-red-reason`, `--accept-green`, `--infra-exempt`) need 20+ characters of
  prose, apply to one dispatch, are logged, and are shown in the report. Agents are told never
  to use them; a human does.
- **Drafts.** The PR is a draft when any criterion is not proven (flagged, stale, unbound,
  downgraded by test-review) or any review defect is confirmed. A clean run opens a ready PR.
- **Nesting.** The repo agent spawns provers. If the runtime does not allow a subagent to
  spawn subagents, the repo agent returns `NESTING-UNAVAILABLE` and the orchestrator runs the
  slices itself, keeping "a child returns a verdict, never a transcript".

## What is left out

Add these only when their absence hurts, in this order:

1. `/drift-report` — cold-read the diff for structural decisions no spec dictated.
2. `/repo-map-update` — carry the machinery lessons of a run into `docs/agents/repo-map.md`.
3. `visual-review` — judge screenshots against an approved design (`[design]` surface).
4. Epic-level skills — `/prd`, `/to-epics`, `/to-stories`, `/tech-design`.
5. `/work-queue` — a pull-based queue for the product decisions `/refine` flagged.

Two things to resist: **do not soften Rule 3** (use a logged override with prose instead), and
**do not let the model do what bash should**.
