# Adapting the toolkit to a project

The skill and the agents are generic. All project knowledge lives in two facts files:

| Tool | Facts file (in the target repo) | Template |
|------|----------------------------------|----------|
| `e2e-test-generation` skill | `.claude/skills/e2e-test-generation/PROJECT.md` | `skills/e2e-test-generation/PROJECT.template.md` |
| `qa-tester` + `qa-reviewer` agents | `.claude/qa/QA_CONTEXT.md` | `qa/QA_CONTEXT.template.md` |

You can fill them in by hand, or ask Claude Code to do it: open Claude Code at the target repo
root and say "Follow docs/ADAPT.md from the qa-ai-toolkit to fill in PROJECT.md and QA_CONTEXT.md".
This file is written so an agent can follow it step by step.

---

## Ground rules

1. **Do not invent facts.** Every path, command, helper, env var, URL, role, or label written into
   a facts file must be verified in the repo (read it or run it). If you cannot verify it, write
   `TODO(verify): <what is unknown>` and list it in the report.
2. **Do not change the generic files** (`SKILL.md`, the method files, the agent files) to hold
   project facts. Facts go into the two facts files only.
3. **Do not change app code, tests, config, or CI** while adapting.
4. **Keep the agents' `tools:` lines.** `qa-reviewer` stays without Write/Edit (read-only critic).
5. **Plan first, then wait for approval. Ask before any git commit.** Never push without asking.

---

## Step 0 - Install

From the target repo root:

```bash
mkdir -p .claude/skills .claude/agents .claude/qa
cp -r <toolkit>/skills/e2e-test-generation .claude/skills/
cp <toolkit>/agents/qa-tester.md <toolkit>/agents/qa-reviewer.md .claude/agents/
cp .claude/skills/e2e-test-generation/PROJECT.template.md .claude/skills/e2e-test-generation/PROJECT.md
cp <toolkit>/qa/QA_CONTEXT.template.md .claude/qa/QA_CONTEXT.md
```

- Run from the repo root (Claude Code finds `.claude/` there).
- If the repo has no e2e setup at all, stop: both tools need Playwright (or another e2e framework,
  with the templates rewritten for it).
- Tracker MCP: the skill's `allowed-tools` lists `mcp__claude_ai_Atlassian__*` (Jira). If your
  tracker MCP has another prefix, change that one entry in `SKILL.md`. Without a tracker MCP, the
  user pastes the ticket.

## Step 1 - Discover the facts (read-only)

Find each item and note the file you found it in.

| # | What to find | Where to look | Goes to |
|---|---|---|---|
| 1 | e2e framework + version; config files | `package.json`, `playwright.config.*` | PROJECT 1, QA 3 |
| 2 | e2e folders, file naming, tags | existing test folders and specs | PROJECT 5, QA 7 |
| 3 | How to run one spec / all specs | `package.json` scripts, Makefile, README | PROJECT 1, QA 3 |
| 4 | Targets: local URL / port; cloud QA URL + env var names; local-only config (e.g. proxy or bypass flags) | `.env.example`, config `baseURL`/`webServer`, `process.env.*`, `.gitignore`, docs | PROJECT 1, QA 3 |
| 5 | How tests sign in (helper, UI, API token, storage state); roles/users; where the app stores auth | e2e setup/auth helpers, the app's auth store | PROJECT 3, QA 4 |
| 6 | Feature flags and which users see them | flag config, auth helpers, docs | PROJECT 3, QA 4 |
| 7 | How tests get data (seed, API bootstrap, data file + format, fixtures, reset); required values and derived fields | e2e `support/`, `common/`, `fixtures/`, global setup | PROJECT 4, QA 5 |
| 8 | Is the backend shared? Does setup reset it? Safe worker count? | setup helpers, config `workers`, docs | QA 6 |
| 9 | How to force error / empty states | mock scenarios, route helpers | PROJECT 4, QA 5 |
| 10 | Date handling (relative-date helper?) | data helpers | PROJECT 4, QA 5 |
| 11 | Shared helpers, locator files, import aliases | e2e folder, `tsconfig` paths, `package.json` `imports` | PROJECT 6, QA 8 |
| 12 | Banned / required patterns (networkidle, XPath, mocking, snapshots); does the app use `data-testid`? | `CLAUDE.md`, rules, lint config, `grep data-testid` | PROJECT 8, QA 11 |
| 13 | App source folders tests must never modify | repo layout | PROJECT 7 |
| 14 | Timers: toasts, countdowns, polling, retries, reconnects | `grep setTimeout setInterval refetchInterval retry` | PROJECT 9 |
| 15 | Where failure evidence is written | config `outputDir`, reporters; run one failing probe test outside the repo to see the files | QA 9 |
| 16 | e2e docs and which rules file wins | `CLAUDE.md`, `docs/`, `.claude/rules/` | QA 10 |
| 17 | Known flaky / unreachable areas; copy quirks; scope cuts | docs, known-gaps files, ask the user | QA 12, 13 |
| 18 | Ticket tracker, key format, MCP tool name | session tool list, `.mcp.json`, ask the user | PROJECT 2, QA 2 |
| 19 | How to inspect the UI: the inspect-script command (URL, auth key/value, wait text) or a browser MCP | items 4 + 5; session tool list | PROJECT 10 |

## Step 2 - Plan (show the user, then wait)

Show a table: `facts file | section | value | source file`, with `TODO(verify)` rows marked. Wait
for approval.

## Step 3 - Write the facts files

Fill in both files with the approved values. Keep the section headings and numbers. Leave
PROJECT.md section 12 (example spec) for after the first passing run, or write one short spec and
run it to prove it.

## Step 4 - Verify

- Every path in both files exists (`ls`); every helper is exported where the file says.
- Every command works: run it with `--list` (Playwright), or as a dry run.
- Run the inspect script once on one page and check `aria.yml` and `page.png` are written.
- Optional but strong: write one short spec from the facts, run it twice, lint it, then delete it
  or keep it as PROJECT.md section 12.
- No `TODO(verify)` left that blocks a run; list the rest for the user.

## Step 5 - Report

1. What was filled in, per section, and the source of each fact.
2. The remaining `TODO(verify)` items and what the user must answer.
3. Claude Code loads agents and skills at session start - start a new session before using them.
4. Suggested first run: `/e2e-test-generation` on one small ticket, then `qa-tester` on the same
   ticket, then `qa-reviewer` on its report.
5. Ask whether to commit (and on which branch).
