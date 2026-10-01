# Planning Test Data

How to decide what data a test needs and where it comes from. The project's actual mechanism
(seed, scenarios, helpers, data file if any) is in PROJECT.md section 4.

## Why data comes first

Inspect the UI only after the data is in place. An empty list shows the empty state, not the
rows, badges, and buttons the test will use - so you would pick selectors for the wrong screen.

## Where the data can come from

Pick the first option that gives the state the acceptance criteria need:

| Source | Use when | Watch out for |
|--------|----------|---------------|
| **Existing seed** (data the test backend always starts with) | The seed already has the records the ticket talks about | Select by stable seeded labels, never by row position alone |
| **Created through the UI** in the test | The ticket is about creating or changing data, or the seed lacks it | Makes the test longer; reuse a shared helper if one exists |
| **API seeding** before the test | Many records, or states the UI cannot reach quickly | Needs auth for the API; clean up or use unique values |
| **Data file** read by a setup step | The project already uses one | Follow its format exactly; do not invent fields |
| **Named error / empty scenario** | The ticket covers loading errors, empty lists, conflicts | Use only scenarios that exist; a missing one is a gap to report, not something to add to app code |

## Rules for any source

- **Unique values** for anything a test creates (e.g. a name with a short random suffix), so
  tests and re-runs cannot collide.
- **Relative dates** only (see RULES.md). Prefer the project's date helper.
- **One state per test**: each test sets up what it asserts on; do not depend on another test's
  leftovers or on test order.
- **Shared backends**: if the project's test backend is shared (PROJECT.md section 4 says so),
  run serially and never reset data another run may be using.

## Record it in the test plan

In the test plan (CHECKLIST.md template), list for each scenario: the role, the records it needs,
where each comes from (seed / UI / API / file / scenario), and any dates.
