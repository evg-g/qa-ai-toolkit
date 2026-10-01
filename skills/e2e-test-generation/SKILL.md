---
name: e2e-test-generation
description: Generate Playwright e2e tests from a ticket (a user story with acceptance criteria - from Jira via MCP, or pasted). Inspects the real UI in a browser to pick selectors, follows the project facts in PROJECT.md, and references Playwright docs for best practices.
allowed-tools: Read, Grep, Glob, Edit, Write, Bash, AskUserQuestion, WebFetch, mcp__claude_ai_Atlassian__*
---

# E2E Test Generation Skill

Generate Playwright e2e tests from a ticket, with browser inspection for selector discovery.

The method in this skill is generic. **Every project-specific fact** (how to run the app and the
tests, auth, test data, folders, helpers, protected code, banned patterns, timers, how to inspect)
lives in [PROJECT.md](PROJECT.md).

## Phase 0: Load the project facts (always first)

1. Read [PROJECT.md](PROJECT.md) in full.
2. If it is missing, STOP: tell the user to copy `PROJECT.template.md` to `PROJECT.md` and fill it
   in (the toolkit's `docs/ADAPT.md` explains how). If a section you need is empty, says
   `TODO(verify)`, or contradicts the repo, STOP and ask the user for the fact. Never guess a path,
   command, helper, URL, or label.
3. Read the repo rules it points to (e.g. `CLAUDE.md`). Repo rules win over this skill.

## Prerequisites

- Whatever PROJECT.md section 1 says must be running (or is started by the test config).
- A ticket: fetched through the tracker MCP named in PROJECT.md section 2, or pasted by the user.

## Quick Reference

| Topic | File |
|-------|------|
| Project facts (read first) | [PROJECT.md](PROJECT.md) (from [PROJECT.template.md](PROJECT.template.md)) |
| Locators & assertions | [PATTERNS.md](PATTERNS.md) |
| Planning test data | [DATA.md](DATA.md) |
| Full code templates | [TEMPLATES.md](TEMPLATES.md) |
| Browser inspection & selector discovery | [BROWSER.md](BROWSER.md) |
| Time-sensitive elements & timing rules | [TIMING.md](TIMING.md) |
| Phase checklists & test plan template | [CHECKLIST.md](CHECKLIST.md) |
| Important rules (no UI mods, locator priority) | [RULES.md](RULES.md) |
| Inspection script | `scripts/inspect.mjs` |

## Workflow Overview (4 Phases)

```
Phase 1: Understand & Plan
1. User provides the ticket ID (or pastes the story)
2. Fetch the ticket details (tracker MCP from PROJECT.md section 2), list the acceptance criteria
3. Analyze the ticket; draft the test plan and the test-data plan (DATA.md)
4. Present the test plan for user approval (see CHECKLIST.md for the template)
5. Ask: new story folder or an existing one? (folders: PROJECT.md section 5)

Phase 2: Set Up Test Data (BEFORE the browser)
6. Pick the role / user the test signs in as (PROJECT.md section 3)
7. Find the data the test needs in the project's seed, or plan how the test creates it
   (PROJECT.md section 4, DATA.md)
8. Pick the named error / empty scenario, if the ticket needs one
9. Make sure the app is running for inspection (PROJECT.md section 10)

Phase 3: Browser Inspection (WITH test data visible)
10. Open the relevant page as that role (BROWSER.md, PROJECT.md section 10)
11. Inspect the UI with the actual test data visible: accessibility tree + screenshot
12. Identify selectors (testids, roles, labels) - see PATTERNS.md
13. Check for time-sensitive elements - see TIMING.md and PROJECT.md section 9

Phase 4: Generate Files
14. Generate the spec (and an optional locators file) - see TEMPLATES.md
15. Ask if the user wants to run the tests (command: PROJECT.md section 1)
```

## Key Files to Reference

- The shared helpers and imports listed in PROJECT.md section 6.
- The example spec in PROJECT.md section 12 - a verified, passing test in the project's style.
