# Project Facts - <app name> (`<repo name>`)

Copy this file to `PROJECT.md` in the same folder and fill in every section for your project.
The other skill files are generic and refer to these section numbers, so keep the headings and
their order. Write only facts you verified in the repo (you read the file or ran the command).
Unknown? Write `TODO(verify): <what>` - the skill will stop and ask instead of guessing.

See `docs/ADAPT.md` for how to discover each fact, and `examples/aurora/PROJECT.md` for a filled-in
example.

## 1. App and how tests run

| Fact | Value |
|------|-------|
| Framework | <Playwright version, config file> |
| App under test | <what the tests open: dev server, production build, mock backend, real API?> |
| Base URL | <e.g. http://localhost:3000, or the env var that sets it> |
| Start the app | <command, or "started by the test config"> |
| Run one story | <command with a path> |
| Run everything | <command> |
| Visual / debug | <--headed / --debug / report command> |
| Second target (optional) | <e.g. a cloud QA env or a composed real stack, and what runs there> |
| CI | <which browsers / projects run in CI> |
| Locale / time zone | <pinned values, if any> |

## 2. Ticket source

- <tracker (Jira / GitHub / Linear / pasted text), the MCP tool to fetch it, the key format>

## 3. Auth and roles

- <how a test signs in: helper, UI login, API token, storage state>
- <the roles / users and their passwords or where they come from>
- <for manual inspection: the localStorage key + value, cookie, or login steps>
- <role-gated areas and feature flags>

## 4. Test data

- <the mechanism: seed, API seeding, data file + format, fixtures, DB reset>
- <is the test backend shared? does setup reset it?>
- <seeded labels / records tests can select by>
- <how to force error / empty states>
- <date handling: relative-date helper or rule>

## 5. Folders and file naming

| Folder | Purpose |
|--------|---------|
| <story folder>/<TICKET>/ | Tests this skill generates |
| <other test folders> | <purpose> - reference only |

<tags used, if any>

## 6. Helpers and imports

- <shared helper files and the functions in them>
- <import style / path aliases for test code>
- <shared locator files, if any>
- <lint / format / type-check rules that cover test files>
- <where API models / generated clients live (never edited by tests)>

## 7. Protected app code (never modify)

<app source folders the skill must never touch>

## 8. Banned and required patterns

- <locator rules; does the app have data-testid attributes?>
- <banned waits or patterns, e.g. networkidle, waitForTimeout, XPath>
- <mocking rules>
- <snapshot rules>
- <which repo rules file wins>

## 9. Timers and time-sensitive UI

| Behavior | Timing | File |
|----------|--------|------|
| <toast, countdown, polling, retry, reconnect> | <duration> | <path> |

## 10. How to inspect the UI (Phase 3)

<the exact inspect-script command for this app (URL, auth key/value, wait text), or the browser
MCP to use; where the Playwright docs come from>

## 11. Known UI patterns

None recorded yet - add patterns as you discover them.

## 12. Example spec

<one short, passing spec in this project's style - write it after the first successful run>
