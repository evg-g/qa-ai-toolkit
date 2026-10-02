# ADLC config — Aurora Clinic

ADLC (the `/refine` → `/implement` proof loop) comes from the `adlc` plugin in
[qa-ai-toolkit](https://github.com/evg-g/qa-ai-toolkit). This file is Aurora's only
project-level ADLC setting. Start Claude Code in this folder (`~/aurora`), the parent of the
three product repos.

The scripts read only the fenced block below.

```adlc-config
tracker: markdown
tickets_dir: "docs/tickets"
statuses:
  draft: "draft"
  in_refinement: "in-refinement"
  ready_for_agent: "ready-for-agent"
  in_progress: "in-progress"
  in_review: "in-review"
  done: "done"
repos:
  - name: appointments-api
    path: "appointments-api"
    base: main
  - name: appointments-web
    path: "appointments-web"
    base: main
  - name: aurora-sensor-agent
    path: "aurora-sensor-agent"
    base: main
```

## Phase 0 answers (2026-10-02)

1. **Issue tracker:** Markdown files in this repo, `docs/tickets/<KEY>.md`, keys `AURORA-<n>`.
   Aurora is a portfolio project with no tracker. The plugin also ships a Jira adapter for
   projects that use Jira.
2. **Repo layout:** three repos that ship together — `appointments-api` (FastAPI),
   `appointments-web` (React), `aurora-sensor-agent` (Python IoT agent). One PR per repo, all
   on the shared branch `story/<KEY>`.
3. **Test harness per surface** (one named test; the adapter adds the tag filter):

   | repo | surface | binding | command the adapter runs |
   |---|---|---|---|
   | api | `[api]` `[data]` | `pytest-integration` | `uv run pytest -q -m agent_trusted tests/integration -k <NAME>` (Docker: real Postgres + Redis via testcontainers) |
   | api | `[logic]` | `pytest-unit` | `uv run pytest -q -m agent_trusted tests/unit -k <NAME>` |
   | sensor-agent | `[logic]` | `pytest-unit` | `uv run pytest -q -m "agent_trusted and not hil and not sil" tests -k <NAME>` |
   | web | `[logic]` | `vitest-unit` | `npx vitest run src -t "(?=.*@agent-trusted)(?=.*<NAME>)"` |
   | web | `[component]` `[ui]` | `playwright` | `CI=1 npx playwright test e2e --grep "(?=.*@agent-trusted)(?=.*<TITLE>)" --project=chromium` |
   | — | `[design]` | none | no approved design references exist |

   Web Vitest runs in jsdom (DOM only), so it is bound to `[logic]` only. `[component]` and
   `[ui]` run in real Chromium against the MSW build. `CI=1` stops Playwright reusing a server
   another checkout started on port 4173.
4. **Proof test isolation:** pytest marker `agent_trusted` (registered in each Python repo's
   `pyproject.toml`); the title tag `@agent-trusted` for Playwright and Vitest.
5. **Base branch and CI:** `main` in all three repos. A PR must pass that repo's `ci.yml`
   (lint, typecheck, tests, contract gates; web also e2e, a11y, visual, budgets).

## Not bound yet

- Device SIL tier (`aurora-sensor-agent` `tests/sil`, needs Docker + the API image) and the
  composed-stack web E2E are not ADLC bindings yet. Criteria that need them are flagged by
  `/refine`, or proven at `[logic]`/`[api]` plus a manual check.
