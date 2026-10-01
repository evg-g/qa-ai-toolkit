# Project Facts - Aurora Clinic web (`appointments-web`)

Every project-specific fact the skill needs lives in this file. The other skill files are
generic and point here. To reuse the skill on another app, copy the skill folder and rewrite only
this file, keeping the same section headings. If a section is empty or wrong, ask the user - do
not guess.

All facts below were verified in this repo on 2026-10-01.

## 1. App and how tests run

| Fact | Value |
|------|-------|
| Framework | Playwright 1.63 (`@playwright/test`), config `playwright.config.ts` |
| App under test | The production build with the app's own typed MSW mock backend (`VITE_ENABLE_MSW=true`) |
| Base URL | `http://localhost:4173` (set as `baseURL`; use relative paths in `page.goto`) |
| Start the app | Nothing to start: the config runs `npm run build:e2e && npm run preview:e2e` itself. Locally it reuses a server already on :4173 - stop a stale preview after changing app code |
| Run one story | `npx playwright test e2e/stories/<TICKET> --project=chromium` |
| Run everything | `npm run e2e` (or `make e2e`) |
| Visual / debug | add `--headed` or `--debug`; `npx playwright show-report` for the HTML report |
| Second target | The composed real stack (API + Postgres + Redis): `make e2e-composed-all`. It only runs `e2e/journeys/`, so stories are not run there |
| CI | The same suite runs on Chromium and WebKit (`PW_ALL_BROWSERS=1`); avoid Chromium-only behavior |
| Locale / time zone | Pinned to `en-US` / `UTC` in the config |

## 2. Ticket source

- Usually a Jira user story with acceptance criteria. Fetch it with the Atlassian connector
  (`mcp__claude_ai_Atlassian__getJiraIssue`, issue key such as `ABC-123`) when it is connected.
- Otherwise the user pastes the story, or gives a GitHub issue (`gh issue view <n>`).
- `<TICKET>` in paths is the ticket key, e.g. `ABC-123`.

## 3. Auth and roles

- Sign in with `seedSession(page, role)` from `e2e/support/helpers.ts`, BEFORE `page.goto`.
  Roles: `PATIENT`, `CLINICIAN`, `PLATFORM_ADMIN`. All accounts use the password `password123`.
- Use `loginViaForm(page, role)` only when the login form itself is under test.
- What `seedSession` stores (for manual inspection): localStorage key `aurora.auth`, value
  `{"accessToken":"mock-access-<ROLE>-1","refreshToken":"mock-refresh-<ROLE>-1","expiresAt":4102444800000}`.
- Role-gated areas: cold chain = `CLINICIAN` and admins; `/admin` = admins only. A disallowed role
  is redirected to the dashboard (see `e2e/journeys/auth.spec.ts`). There are no feature flags.

## 4. Test data

- No data file. The backend is the in-memory seed in `src/mocks/db.ts`, created fresh on every
  page load and separate for each browser page, so tests cannot clobber each other (and nothing
  persists across a full navigation).
- Seeded labels to select by: clinics "Aurora Downtown" and "Aurora Riverside"; the clinician with
  specialty "General practice"; services "Standard consultation" and "Extended review"; devices
  "Vaccine fridge - main" (shown with an em dash in the UI: copy it from the aria snapshot) with
  one open high excursion, and "Vaccine fridge - annex" (provisioned, no readings); audit entries
  `appointment.confirmed`, `device.provisioned`, `excursion.raised`.
- The appointment list starts EMPTY in e2e (the larger demo dataset, `VITE_MSW_DEMO_DATA`, is not
  loaded). Create what a test needs through the UI, e.g. `bookAppointment(page)`.
- Error / empty states: only through named MSW scenarios - `bootScenario(page, name)` for an
  initial-load state, `useScenario(page, name)` mid-journey. Allowed names are `ScenarioName` in
  `e2e/support/helpers.ts`: `bookingConflict`, `appointmentsError`, `appointmentsEmpty`,
  `clinicsError`, `devicesError`, `acknowledgeFails`. If a state has no scenario, report it as a
  gap - adding one means editing `src/mocks/handlers.ts`, which this skill must not do.
- Dates: there is no relative-date helper. Seed timestamps are relative to `Date.now()`. For
  booking use `bookableDay()` / `BOOKABLE_DAY` (a fixed Monday; the mock availability ignores
  "now"). Never hard-code "today".

## 5. Folders and file naming

| Folder | Purpose |
|--------|---------|
| `e2e/stories/<TICKET>/` | Tests this skill generates: `<feature>.spec.ts` (+ optional `locators.ts`) |
| `e2e/journeys/` | Core user journeys (also run against the composed stack) - reference only |
| `e2e/a11y/`, `e2e/visual/`, `e2e/layout/` | axe sweep, visual baselines, layout rules - reference only |
| `e2e/showcase/`, `e2e/pages/` | README screenshots and the Pages build, own configs - never put tests here |

No test tags are used.

## 6. Helpers and imports

- Shared helpers: `e2e/support/helpers.ts` - `seedSession`, `loginViaForm`, `bootScenario`,
  `useScenario`, `walkBookingToConfirm`, `bookAppointment`, `bookableDay`, `BOOKABLE_DAY`,
  `ACCOUNTS`, and the `Role` / `ScenarioName` types.
- Imports are relative; from a story: `import { seedSession } from "../../support/helpers";`.
  There is no path alias for e2e code (`@/` is app code only).
- There are no shared locator files. Keep story locators in the spec, or in a local
  `locators.ts` when several tests reuse them.
- e2e files are linted (ESLint + Prettier, `make lint`); they are not in the `tsc` include.
- API models: the app client is generated from `contracts/openapi.json` (types in `src/api/`).
  That is app code - never edit it from a test. If the API changes, only the tests follow.

## 7. Protected app code (never modify)

`src/` (including `src/mocks/`) and `public/`. Tests use what the UI already exposes.

## 8. Banned and required patterns

- Query by role and label first (`getByRole`, `getByLabel`). The app has NO `data-testid`
  attributes today, so the test-id step of the locator priority does not apply.
- No `networkidle`: the cold-chain page holds a live SSE stream open, so it never goes idle.
- No hand-rolled mocks or `page.route()` in a story: use the named scenarios (CLAUDE.md rule).
- No XPath, no CSS chains on Tailwind classes, no `waitForTimeout`.
- Never run `--update-snapshots` to make a test pass; a visual baseline change is a human decision.
- Repo rules in `CLAUDE.md` win over anything in this skill.

## 9. Timers and time-sensitive UI

| Behavior | Timing | File |
|----------|--------|------|
| Device health tile refetch (cold-chain page) | every 15 s | `src/features/cold-chain/DeviceHealthTile.tsx` |
| Dashboard cold-chain card refetch | every 30 s | `src/features/cold-chain/ColdChainSummary.tsx` |
| Live telemetry stream reconnect | back-off 1 s doubling to 15 s | `src/api/sse.ts` |
| Query cache freshness | `staleTime` 30 s; failed reads retry once | `src/app/query-client.ts` |

No toasts or auto-advancing buttons. Because reads retry once, an error state can take a few
seconds to show - give error-state assertions a longer timeout (the suite default is 7.5 s).

## 10. How to inspect the UI (Phase 3)

There is no browser MCP here. Use the skill's Playwright script against the running preview
(start it with `npm run build:e2e && npm run preview:e2e` if :4173 is not up), from the repo root:

```bash
node .claude/skills/e2e-test-generation/scripts/inspect.mjs \
  --url http://localhost:4173 --route /admin/audit --out /tmp/inspect \
  --storage-key aurora.auth \
  --storage-value '{"accessToken":"mock-access-PLATFORM_ADMIN-1","refreshToken":"mock-refresh-PLATFORM_ADMIN-1","expiresAt":4102444800000}' \
  --wait-text "appointment.confirmed"
```

Then read `aria.yml` (roles and names), `page.png`, and `testids.txt`. Add `--headed` to watch.
Playwright docs: fetch pages from https://playwright.dev/docs/ with WebFetch.

## 11. Known UI patterns

None recorded yet - add patterns as you discover them.

## 12. Example spec (verified: passes, lint-clean)

`e2e/stories/DEMO-1/audit-filter.spec.ts`:

```typescript
import { expect, test } from "@playwright/test";

import { seedSession } from "../../support/helpers";

// DEMO-1: an admin can filter the audit log by entity type.
test.describe("DEMO-1 audit log filter", () => {
  test.beforeEach(async ({ page }) => {
    await seedSession(page, "PLATFORM_ADMIN");
    await page.goto("/admin/audit");
    // Premise: the audit log has loaded with its seeded entries.
    await expect(page.getByRole("heading", { level: 1, name: "Admin" })).toBeVisible();
    await expect(page.getByRole("cell", { name: "appointment.confirmed" })).toBeVisible();
  });

  test("shows only device entries after filtering by device", async ({ page }) => {
    await test.step("Filter by entity type", async () => {
      await page.getByRole("combobox", { name: "Entity type" }).selectOption("device");
      await page.getByRole("button", { name: "Apply filters" }).click();
    });

    await test.step("Verify only device entries remain", async () => {
      await expect(page.getByRole("cell", { name: "device.provisioned" })).toBeVisible();
      await expect(page.getByRole("cell", { name: "appointment.confirmed" })).toHaveCount(0);
    });
  });

  test("clears the filter and shows every entry again", async ({ page }) => {
    await test.step("Filter, then clear", async () => {
      await page.getByRole("combobox", { name: "Entity type" }).selectOption("device");
      await page.getByRole("button", { name: "Apply filters" }).click();
      await expect(page.getByRole("cell", { name: "appointment.confirmed" })).toHaveCount(0);
      await page.getByRole("button", { name: "Clear" }).click();
    });

    await test.step("Verify all entries are back", async () => {
      await expect(page.getByRole("cell", { name: "appointment.confirmed" })).toBeVisible();
      await expect(page.getByRole("cell", { name: "device.provisioned" })).toBeVisible();
    });
  });
});
```
