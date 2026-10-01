# Code Templates

Generic templates for the files generated for each story. Replace every `<...>` placeholder
with the project's real value from PROJECT.md - never leave a placeholder or invent a helper.
For a complete, verified example in this project's style, see PROJECT.md section 12.

## File Structure

```
<story folder from PROJECT.md section 5>/<TICKET>/
|-- <feature>.spec.ts    # Test implementation (always)
|-- locators.ts          # Story-specific selectors (optional, when several tests reuse them)
```

Add a test-data file only if the project uses one (PROJECT.md section 4), in exactly the
project's format.

---

## Template: locators.ts (optional)

```typescript
import type { Page } from "@playwright/test";

// =============================================================================
// Story-specific locators for <TICKET> <Feature Name>
// Names copied from the accessibility tree (aria.yml) during inspection.
// =============================================================================

// Headings (premise checks)
export const pageHeading = (page: Page) =>
  page.getByRole("heading", { level: 1, name: "<Page Title>" });

// Buttons
export const primaryActionButton = (page: Page) =>
  page.getByRole("button", { name: "<Primary Action>" });

// Form elements
export const inputField = (page: Page) => page.getByLabel("<Field Label>");
export const dropdown = (page: Page) => page.getByRole("combobox", { name: "<Dropdown Label>" });

// Data display
export const rowByName = (page: Page, name: string) => page.getByRole("row", { name });
export const cellByName = (page: Page, name: string) => page.getByRole("cell", { name });

// Messages / alerts
export const errorAlert = (page: Page) => page.getByRole("alert");

// Dialogs
export const dialog = (page: Page) => page.getByRole("dialog");
export const confirmButton = (page: Page) =>
  dialog(page).getByRole("button", { name: "<Confirm>" });
```

---

## Template: <feature>.spec.ts

```typescript
import { expect, test } from "@playwright/test";

// The sign-in / data helpers from PROJECT.md section 6, with the project's import style.
import { <signInHelper> } from "<path to shared helpers>";

import { pageHeading, primaryActionButton } from "./locators";

// <TICKET>: <one-line story summary>
test.describe("<TICKET> <Feature Name>", () => {
  test.beforeEach(async ({ page }) => {
    // Sign in as the role the story is about (PROJECT.md section 3).
    await <signInHelper>(page, "<ROLE>");
    await page.goto("<route>");
    // Premise: we are on the intended page with the expected data.
    await expect(pageHeading(page)).toBeVisible();
  });

  test("<AC 1 in plain words>", async ({ page }) => {
    await test.step("<User action>", async () => {
      await primaryActionButton(page).click();
    });

    await test.step("<Verify the outcome>", async () => {
      // An assertion that would FAIL if the behavior were missing.
      await expect(page.getByRole("<role>", { name: "<expected>" })).toBeVisible();
    });
  });

  test("<AC 2: an error or empty state>", async ({ page }) => {
    await test.step("Force the state", async () => {
      // Only a named scenario / mechanism from PROJECT.md section 4 - never a hand-made mock.
    });

    await test.step("Verify the designed state", async () => {
      await expect(page.getByRole("alert")).toBeVisible();
    });
  });
});
```

### Template notes

- Use the per-test `page` fixture. Each test gets a fresh browser context, so tests stay
  independent and can run in parallel. Share a page across tests (`beforeAll`) only if
  PROJECT.md says the project's setup requires it.
- Put the sign-in and navigation in `beforeEach`, and assert the premise there.
- Keep locators that only one test uses inline; move them to `locators.ts` when reused.
- Follow the project's lint and format rules (PROJECT.md section 6), and run them on new files.

---

## Import Paths Reference

Use the project's real import style from PROJECT.md section 6:

```typescript
// Playwright
import { expect, test } from "@playwright/test";
import type { Page } from "@playwright/test";

// Shared helpers (path and names: PROJECT.md section 6)
import { <helper> } from "<path to shared helpers>";

// Story-specific locators (relative, same folder)
import { ... } from "./locators";
```
