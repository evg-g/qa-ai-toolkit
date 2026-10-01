# Important Rules

## CRITICAL: Tests Only - No UI Modifications

**This skill ONLY writes e2e tests. NEVER modify application code.**

- **NEVER** add `data-testid` attributes to components
- **NEVER** modify any files in the protected app folders listed in PROJECT.md section 7
- **NEVER** change UI components, styles, mocks, or behavior
- **ONLY** write tests using **existing selectors** (testids, roles, text, labels)
- If a reliable selector doesn't exist, use combinations of `getByRole()`, `getByText()`, or locator chains

When inspecting UI, work with what's already there. If selectors are fragile, document it in the test comments but do NOT modify the source code. If a test needs app support that does not exist (a test hook, a mock scenario), report it to the user as a gap.

## Test Structure

- Each test scenario -> `test()`
- Each logical step -> `test.step()`
- Group related assertions inside the same `test.step()`
- Assert the premise (you reached the intended page / state) before the main assertion

## Locator Priority

1. `getByTestId()` - Most stable (only if the app has test IDs - see PROJECT.md section 8)
2. `getByRole()` - Accessible and semantic
3. `getByLabel()` - For form inputs
4. `getByText()` - Last resort, use exact matching

## File Placement

Put generated tests in the story folder from PROJECT.md section 5, normally one folder per
ticket (`<TICKET>` = the ticket key). Other folders listed there are for reference; do not add
story tests to them unless the user asks.

### Story Folder Contents

- `{test-name}.spec.ts` - Test cases (e.g., `filter.spec.ts`, `pagination.spec.ts`)
- Optional: `locators.ts` - Story-specific element selectors, when several tests reuse them
  (prefer the shared helpers from PROJECT.md section 6)
- A test-data file only if the project uses one (PROJECT.md section 4)

## Running Tests

After generating files, offer to run them with the command in PROJECT.md section 1, and say what
must be running first (if anything).

## CRITICAL: Always Use Relative Dates

**NEVER hard-code dates in tests or test data.**

Fixed dates like `"2025-08-20T10:00:00.000Z"` make tests fail over time as the data becomes
"overdue" or stale. Compute dates relative to now, or use the project's date helper
(PROJECT.md section 4). If the project has no helper, compute the date in the test
(e.g. `new Date(Date.now() + 7 * 86_400_000)`) and say why in a comment.

## API Model Changes

When the API models change, the test data and any test types must follow. Check where the
project defines them (PROJECT.md sections 4 and 6) and update the test side only - never the
app's generated client or mocks.
