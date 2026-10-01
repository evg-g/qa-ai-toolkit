# E2E Test Patterns

This document covers patterns for locators, assertions, and test structure.

## Test Structure Pattern

### Hierarchy
```
test.describe() - Group related tests
  `-- test() - Individual test scenario
        `-- test.step() - Logical step within test
              `-- expect() - Assertions
```

### Example Structure
```typescript
test.describe("Feature Name", () => {
  test("user can complete action", async () => {
    await test.step("Navigate to page", async () => {
      // Navigation code
    });

    await test.step("Perform action", async () => {
      // Action code
    });

    await test.step("Verify result", async () => {
      // Assertions
    });
  });
});
```

---

## Locator Patterns

### Priority Order (use in this order)

1. **`getByTestId()`** - Most stable, doesn't break with UI changes (only if the app has test
   IDs - PROJECT.md section 8)
2. **`getByRole()`** - Semantic, accessible
3. **`getByLabel()`** - For form inputs
4. **`getByText()`** - Last resort

### Locator Function Pattern

Always create locator functions that take `Page` as parameter:

```typescript
import type { Page } from "@playwright/test";

// Buttons
export const submitButton = (page: Page) => page.getByRole("button", { name: "Submit" });
export const cancelButton = (page: Page) => page.getByRole("button", { name: /Cancel/i });

// Test IDs
export const resultsTable = (page: Page) => page.getByTestId("results-table");
export const resultRow = (page: Page) => page.getByTestId("result-row");

// Form inputs
export const emailInput = (page: Page) => page.getByLabel("Email");
export const searchInput = (page: Page) => page.getByPlaceholder("Search...");

// Text content
export const errorMessage = (page: Page) => page.getByText("Error occurred", { exact: true });
export const statusBadge = (page: Page) => page.getByText(/Confirmed/i);

// Combining locators
export const tableRows = (page: Page) => page.getByRole("rowgroup").last().getByRole("row");
export const firstRow = (page: Page) => page.getByRole("row").nth(1);
```

### Role Types Reference

| Role | Elements |
|------|----------|
| `button` | `<button>`, `<input type="button">` |
| `link` | `<a>` |
| `textbox` | `<input type="text">`, `<textarea>` |
| `checkbox` | `<input type="checkbox">` |
| `radio` | `<input type="radio">` |
| `combobox` | `<select>` |
| `row` | `<tr>` |
| `cell` | `<td>` |
| `heading` | `<h1>` - `<h6>` |
| `tab` | Tab panels |
| `dialog` | Modal dialogs |

---

## Assertion Patterns

### Visibility Assertions
```typescript
await expect(element(page)).toBeVisible();
await expect(element(page)).toBeHidden();
await expect(element(page)).not.toBeVisible();
```

### Count Assertions
```typescript
await expect(rows(page)).toHaveCount(5);
await expect(page.getByText("Item")).toHaveCount(3);
```

### Text Assertions
```typescript
await expect(element(page)).toHaveText("Expected text");
await expect(element(page)).toContainText("partial");
await expect(element(page)).toHaveText(/regex pattern/i);
```

### Attribute Assertions
```typescript
await expect(element(page)).toHaveAttribute("disabled", "");
await expect(element(page)).toHaveClass(/active/);
await expect(input(page)).toHaveValue("input value");
```

### URL Assertions
```typescript
await expect(page).toHaveURL(/\/orders\/[^/]+$/);
await expect(page).toHaveURL("/orders"); // relative to baseURL
```

### State Assertions
```typescript
await expect(button(page)).toBeEnabled();
await expect(button(page)).toBeDisabled();
await expect(checkbox(page)).toBeChecked();
await expect(input(page)).toBeFocused();
```

---

## Action Patterns

### Click Actions
```typescript
await button(page).click();
await link(page).click();
await row(page).nth(1).click();  // Click second row
```

### Input Actions
```typescript
await input(page).fill("text value");
await input(page).clear();
await input(page).pressSequentially("typed text");  // Simulates typing
```

### Checkbox/Radio Actions
```typescript
await checkbox(page).check();
await checkbox(page).uncheck();
await checkbox(page).setChecked(true);
await checkbox(page).setChecked(false);
```

### Select Actions
```typescript
await select(page).selectOption("value");
await select(page).selectOption({ label: "Option Text" });
```

### Wait Patterns
```typescript
await page.waitForURL(/expected-url/);
await expect(element(page)).toBeVisible(); // web-first: retries until visible
// Avoid waitForLoadState("networkidle"): pages with live streams or polling never go idle.
```

---

## Common Test Patterns

### Filter Test Pattern
```typescript
test("should filter results", async () => {
  await test.step("Open filters", async () => {
    await filtersButton(page).click();
  });

  await test.step("Apply filter", async () => {
    await dropdown(page).click();
    await option(page).click();
    await applyButton(page).click();
  });

  await test.step("Verify filtered results", async () => {
    const rows = tableRows(page);
    await expect(rows).toHaveCount(expectedCount);
  });
});
```

### Navigation Test Pattern
```typescript
test("should navigate to detail page", async () => {
  await test.step("Click on item", async () => {
    await row(page).first().click();
  });

  await test.step("Verify navigation", async () => {
    await expect(page).toHaveURL(/detail/);
    await expect(detailHeader(page)).toBeVisible();
  });
});
```

### Form Submission Pattern
```typescript
test("should submit form", async () => {
  await test.step("Fill form", async () => {
    await nameInput(page).fill(`Test user ${Date.now()}`); // unique per run
    await emailInput(page).fill(`user.${Date.now()}@example.com`);
  });

  await test.step("Submit form", async () => {
    await submitButton(page).click();
  });

  await test.step("Verify success", async () => {
    await expect(successMessage(page)).toBeVisible();
  });
});
```

### Undo Action Pattern
```typescript
test("should undo action", async () => {
  await test.step("Perform action", async () => {
    await actionButton(page).click();
    await expect(resultElement(page)).toBeVisible();
  });

  await test.step("Undo action", async () => {
    await undoButton(page).click();
  });

  await test.step("Verify undo", async () => {
    await expect(resultElement(page)).not.toBeVisible();
  });
});
```

---

## Anti-Patterns to Avoid

### Don't Hard-Code Waits
```typescript
// Bad
await page.waitForTimeout(2000);

// Good
await element(page).waitFor({ state: "visible" });
```

### Don't Use CSS Selectors When Roles Available
```typescript
// Bad
export const btn = (page: Page) => page.locator(".btn-primary");

// Good
export const btn = (page: Page) => page.getByRole("button", { name: "Submit" });
```

### Don't Duplicate Locators
```typescript
// Bad - duplicating in tests
await page.getByRole("button", { name: "Submit" }).click();
await page.getByRole("button", { name: "Submit" }).waitFor();

// Good - use locators.ts
await submitButton(page).click();
await submitButton(page).waitFor();
```
