# QA Context - <app name> (`<repo name>`)

The project facts file for the `qa-tester` and `qa-reviewer` agents. Copy it to
`.claude/qa/QA_CONTEXT.md` in your repo and fill in every section. Do NOT put it in
`.claude/agents/` - every `.md` there is loaded as an agent.

Write only facts you verified (you read the file or ran the command). Unknown? Write
`TODO(verify): <what>` - the agents stop and ask instead of guessing. Keep the section numbers:
the agents refer to them. See `docs/ADAPT.md` for how to find each fact, and
`examples/aurora/QA_CONTEXT.md` for a filled-in example.

## 1. Product and repo
- <product name, what the app does, main branch name>

## 2. Ticket source
- <tracker (Jira / GitHub / Linear / pasted), how to fetch a ticket, key format>

## 3. Targets and how to run
| Target | URL / how it is served | Run command | Notes |
|--------|------------------------|-------------|-------|
| Local | <e.g. http://localhost:3000, started by the config or `npm run dev`> | <command with a path> | <...> |
| Cloud QA (optional) | <URL or env var, e.g. UI_BASE_URL in .env> | <command, e.g. with --config=...> | <local-only config files, proxy/bypass flags - never committed> |

## 4. Auth, roles, feature flags
- <how a test signs in (helper / UI / API / storage state), roles and users, password source>
- <role-gated areas, feature flags and which user sees them>

## 5. Test data and seeding
- <mechanism (seed / API bootstrap / data file / fixtures), its format and required values>
- <derived-field rules, e.g. "displayName = first + last">
- <how to force error / empty states>
- <date rules (relative-date helper?)>

## 6. Shared backend and parallelism
- <is the test backend shared? does setup reset it? safe worker count?>

## 7. Folders and naming
- <story folder per ticket, file naming, other test folders (reference only)>

## 8. Helpers and locators
- <shared helper / locator files, import style, input helpers if the UI needs them>

## 9. Failure evidence
- <where Playwright writes it: test-results/<test>/error-context.md, test-failed-*.png, video, trace>

## 10. Project docs and precedence
- <e2e docs to read first; which file wins when they conflict>

## 11. Banned and required patterns
- <e.g. no networkidle, no XPath, mocking rules, snapshot rules, data-testid availability>

## 12. Known flaky / unreachable areas (gate, don't fail)
- None recorded yet - add them as you find them.

## 13. Known copy quirks and scope cuts
- <UI labels that differ from the PRD; deliberate gaps that are not bugs>
