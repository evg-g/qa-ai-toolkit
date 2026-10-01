# QA Context - Aurora Clinic web (`appointments-web`)

Worked example of `qa/QA_CONTEXT.template.md`, filled in for
[evg-g/appointments-web](https://github.com/evg-g/appointments-web). In that repo it lives at
`.claude/qa/QA_CONTEXT.md`. All facts verified on 2026-10-01.

## 1. Product and repo
- Aurora Clinic: appointment booking plus cold-chain (medication fridge) monitoring. React 19 +
  TypeScript, Vite. Main branch: `main`.

## 2. Ticket source
- A user story with acceptance criteria: Jira (`ABC-123`) via the Atlassian MCP when connected, a
  GitHub issue (`gh issue view <n>`), or text pasted by the user.

## 3. Targets and how to run
| Target | URL / how it is served | Run command | Notes |
|--------|------------------------|-------------|-------|
| Local (default) | `http://localhost:4173`: the production build with the app's MSW mock backend, built and served by the config itself (`npm run build:e2e && npm run preview:e2e`) | `npx playwright test e2e/stories/<TICKET> --project=chromium --workers=1` | Locally it reuses a server already on :4173 - stop a stale preview after changing app code |
| Composed real stack | `E2E_BASE_URL` (default `http://localhost:8080`): real API + Postgres + Redis behind nginx; needs Docker and `../appointments-api` | `make e2e-composed-all` (up -> seed -> run -> down) or `npm run e2e:composed` | Only runs `e2e/journeys/`; stories are not run there - say so in the report |

There is no remote cloud QA env. CI also runs the suite on WebKit (`PW_ALL_BROWSERS=1`).

## 4. Auth, roles, feature flags
- `seedSession(page, role)` from `e2e/support/helpers.ts`, before `page.goto`. Roles: `PATIENT`,
  `CLINICIAN`, `PLATFORM_ADMIN`; password `password123`. `loginViaForm` only when the login form is
  under test.
- Cold chain: clinician and admins. `/admin`: admins only. A disallowed role is redirected to the
  dashboard (`e2e/journeys/auth.spec.ts`). No feature flags.

## 5. Test data and seeding
- Mock mode: the in-memory seed in `src/mocks/db.ts`, fresh on every page load. The demo dataset
  is not loaded in e2e, so the appointment list starts empty - create bookings through the UI
  (`bookAppointment(page)`).
- Select by seeded labels: "Aurora Downtown", the "General practice" clinician, the seeded audit
  actions. Unique text for anything a test creates. Dates render in en-US / UTC.
- Error / empty states only through named MSW scenarios: `bootScenario` / `useScenario` with a
  `ScenarioName` from `e2e/support/helpers.ts`. Never hand-roll a mock or `page.route()`. A missing
  scenario is a gap to report - do not edit `src/`.
- Booking dates: `bookableDay()` / `BOOKABLE_DAY` (a fixed Monday).

## 6. Shared backend and parallelism
- Mock mode: each browser page has its own backend - parallel runs are safe; nothing persists
  across a full navigation.
- Composed mode: one shared real database, 1 worker (enforced by its config). Never run two at once.

## 7. Folders and naming
- Stories: `e2e/stories/<TICKET>/<feature>.spec.ts`. Reference only: `e2e/journeys/`, `e2e/a11y/`,
  `e2e/visual/`, `e2e/layout/`. Never in `e2e/showcase/` or `e2e/pages/` (own configs).

## 8. Helpers and locators
- `e2e/support/helpers.ts`: `seedSession`, `loginViaForm`, `bootScenario`, `useScenario`,
  `walkBookingToConfirm`, `bookAppointment`, `bookableDay`. Relative imports
  (`../../support/helpers`). Plain `fill()` works with the forms (no input helpers needed).

## 9. Failure evidence
- `test-results/<test>/error-context.md` (aria snapshot), `test-failed-1.png`, `video.webm`; the
  trace only on retry.

## 10. Project docs and precedence
- `CLAUDE.md` (Testing), `docs/BROWSER_TESTING.md`, `docs/adr/0006-browser-test-tiers.md`,
  `docs/adr/0007-composed-e2e-and-delivery.md`, `docs/KNOWN_GAPS.md`. `CLAUDE.md` rules win.

## 11. Banned and required patterns
- Query by role and label; no `data-testid` exists. No XPath, no Tailwind-class CSS chains, no
  `networkidle` (the cold-chain page holds a live SSE stream open). Never `--update-snapshots` to
  make a test pass.

## 12. Known flaky / unreachable areas (gate, don't fail)
- None recorded yet.
- Known limits, not flakes: the cold-chain chart is never pixel-snapshotted (stream-driven); the
  visual tests allow a 2% pixel difference, so assert content with a locator, not only a screenshot.

## 13. Known copy quirks and scope cuts
- Deliberate scope cuts are listed in `docs/KNOWN_GAPS.md` - not bugs.
