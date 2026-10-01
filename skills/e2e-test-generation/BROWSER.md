# Browser Inspection Guide

How to look at the real UI, with test data visible, to discover selectors before writing tests.
The project's URL, auth values, and inspection command are in PROJECT.md section 10.

## Prerequisites

1. The app is running (PROJECT.md section 1 / 10)
2. The test data plan is done (DATA.md) - inspect the state the test will see, not an empty page
3. You know the role / user to sign in as (PROJECT.md section 3)

## Workflow Overview

**IMPORTANT**: Set up test data BEFORE browser inspection!

```
Phase 1: Data + auth (BEFORE the browser)
1. Confirm the needed data exists in the seed, or create it (DATA.md)
2. Get the auth value for the role (PROJECT.md section 3)

Phase 2: Browser inspection
3. Open the page as that role (inspect script, or a browser MCP if the project has one)
4. Take a screenshot to understand the layout
5. Read the accessibility tree to find elements (roles + accessible names)
6. List test IDs, if the app has any
7. Identify optimal selectors
8. Document the selectors for the spec / locators.ts
```

---

## Option A (default): the inspect script

`scripts/inspect.mjs` drives a real Chromium with Playwright. It is generic; every project value
comes from its arguments. Run it from the repo root:

```bash
node .claude/skills/e2e-test-generation/scripts/inspect.mjs \
  --url <base-url> --route <path> --out <dir> \
  [--storage-key <key> --storage-value <json-string>] \
  [--init <js-file>] [--wait-text <text>] [--headed]
```

| Argument | Meaning |
|----------|---------|
| `--url`, `--route` | The running app and the page to open |
| `--storage-key`, `--storage-value` | Seeds localStorage before any page script runs (how many apps keep a session) |
| `--init <js-file>` | Any other init script, e.g. to switch on a mock scenario |
| `--wait-text` | Wait until this text is visible (default: the first `h1`) |
| `--headed` | Show the browser |

It writes:
- `aria.yml` - the accessibility tree: every role and accessible name, i.e. what `getByRole`,
  `getByLabel`, and `getByText` will match
- `page.png` - a full-page screenshot (read it with the Read tool)
- `testids.txt` - every `data-testid` on the page (empty if the app has none)

To inspect a later state (after clicking through a wizard, opening a dialog), write a short
throwaway Playwright test outside the repo's test folders that reaches the state and calls
`await page.locator("body").ariaSnapshot()`, or step there with `npx playwright test --debug`.

## Option B: a browser MCP

If the session has a browser-control MCP (check the available tools), the same steps apply:
open a tab, set the auth value, navigate, screenshot, read the accessibility tree, search for
elements. Use the tool names the session actually lists.

---

## Selector Discovery Process

### 1. Identify Element Type

From the accessibility tree, note:
- **Role**: button, link, textbox, combobox, cell, heading, etc.
- **Name**: Text label or accessible name
- **Test ID**: data-testid attribute (if present)

### 2. Choose Selector Strategy

| Priority | Strategy | Example |
|----------|----------|---------|
| 1 | Test ID | `page.getByTestId("submit-btn")` |
| 2 | Role + Name | `page.getByRole("button", { name: "Submit" })` |
| 3 | Label | `page.getByLabel("Email")` |
| 4 | Placeholder | `page.getByPlaceholder("Search...")` |
| 5 | Text | `page.getByText("Error", { exact: true })` |

### 3. Test Selector Stability

- Prefer names copied from `aria.yml` exactly (watch for special characters such as dashes).
- Check uniqueness: a role + name that appears twice (e.g. a link in the header and on the page)
  needs scoping, e.g. `page.getByRole("main").getByRole("link", { name: "..." })`.
- Re-run the inspect script on a second state (after filtering, with an error scenario) to make
  sure the selector still means the same element.

---

## Example: Reading the Accessibility Tree

A snippet of `aria.yml`:

```yaml
- main:
  - heading "Orders" [level=1]
  - combobox "Status":
    - option "All" [selected]
    - option "Open"
  - button "Apply filters"
  - table:
    - rowgroup:
      - row "Order 1001 Open":
        - cell "Order 1001"
```

Locators that follow from it:

```typescript
export const pageHeading = (page: Page) => page.getByRole("heading", { level: 1, name: "Orders" });
export const statusFilter = (page: Page) => page.getByRole("combobox", { name: "Status" });
export const applyButton = (page: Page) => page.getByRole("button", { name: "Apply filters" });
export const orderCell = (page: Page, id: string) => page.getByRole("cell", { name: `Order ${id}` });
```

---

## Common Element Patterns in This App

See PROJECT.md section 11. None recorded yet - add patterns as you discover them.

---

## Playwright Docs Reference

For best practices, fetch the Playwright docs with WebFetch, e.g.:
- https://playwright.dev/docs/locators - locator strategies
- https://playwright.dev/docs/test-assertions - assertion patterns
- https://playwright.dev/docs/aria-snapshots - accessibility snapshots
- https://playwright.dev/docs/best-practices - test isolation and best practices

---

## Troubleshooting

### Element Not Found

1. Check if element is visible (may need scroll)
2. Check if element requires interaction to appear
3. Check if element is inside iframe
4. Verify selector matches exactly (compare with `aria.yml`)
5. Check you are signed in as a role that can see the page (a redirect shows a different page)

### Multiple Elements Match

1. Be more specific with name/label
2. Scope to a parent (`page.getByRole("main")`, a dialog, a row)
3. Use `.first()` or `.nth(n)` only if order is guaranteed

### Dynamic Elements

1. Use regex patterns: `/Button Text/i`
2. Use partial matching: `{ name: /partial/i }`
3. Wait with a web-first assertion: `await expect(element).toBeVisible()`
