# QA AI Toolkit

A reusable kit for AI-assisted test automation with [Claude Code](https://claude.com/claude-code):
one **skill** that writes Playwright e2e tests from a user story, and two **agents** that test a
feature and then independently review that testing. It is generic: you adapt it to any web
project by filling in two facts files, with a guide that tells you (or Claude) exactly how.

Designed by me, built with Claude Code, and proven on a real project:
[Aurora Clinic](https://github.com/evg-g/aurora) (its facts files are in `examples/aurora/`).

## What is in it

| Tool | What it does | Use it for |
|------|--------------|------------|
| `skills/e2e-test-generation` | Reads a ticket (Jira or pasted), plans the tests and waits for your approval, inspects the real UI in a browser to pick selectors, then writes the spec | Writing new e2e tests, mostly against a local build |
| `agents/qa-tester` | Writes and runs e2e tests for a merged feature on a local or cloud QA target, reconciles every failure against the captured DOM, and reports passing tests, candidate bugs with evidence, and coverage gaps | Verifying a feature on a QA environment |
| `agents/qa-reviewer` | A read-only critic: re-checks each test (would it fail if the feature broke?) and gives each reported bug a verdict (CONFIRMED / PLAUSIBLE / REFUTED) | A second, independent pair of eyes before results are trusted |

The ideas behind it:
- **A green test is not a verified feature; a red test is not a confirmed bug.** Every failure is
  reconciled against the real DOM and screenshot before it is called a product bug.
- **The author and the critic are separate.** The reviewer cannot edit, so it cannot quietly fix
  what it should flag.
- **No guessing.** Every project fact (URLs, roles, test data, helpers, banned patterns) comes from
  a verified facts file; a missing fact stops the tool and makes it ask.
- **Humans decide.** The tools draft and report; nothing is merged or declared "bug-free" on its own.

## Layout

```
skills/e2e-test-generation/   SKILL.md + method files + PROJECT.template.md + scripts/inspect.mjs
agents/                       qa-tester.md, qa-reviewer.md
qa/QA_CONTEXT.template.md     the facts file both agents read
docs/ADAPT.md                 how to install and adapt the kit to a project
examples/aurora/              filled-in PROJECT.md and QA_CONTEXT.md for a real app
```

## Quick start

1. Copy the kit into your repo and create the two facts files - see
   [docs/ADAPT.md](docs/ADAPT.md), Step 0.
2. Fill them in. Easiest: open Claude Code at your repo root and say
   *"Follow docs/ADAPT.md from the qa-ai-toolkit to fill in PROJECT.md and QA_CONTEXT.md."*
3. Start a new Claude Code session (skills and agents load at session start).
4. Try it on one small ticket:
   - `/e2e-test-generation ABC-123` - writes the tests
   - "use qa-tester on ABC-123" - runs and reports
   - "use qa-reviewer on that report" - independent verdicts

## Requirements

- Claude Code
- Playwright in the target repo (the templates are Playwright-specific)
- Optional: a tracker MCP (Jira via Atlassian) - otherwise paste the ticket text

## License

MIT - see [LICENSE](LICENSE).
