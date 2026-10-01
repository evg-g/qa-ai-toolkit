# E2E Test Generation Checklist

Use this checklist to track progress through the 4-phase workflow.

## Phase 0: Project Facts

- [ ] Read PROJECT.md; ask the user about any missing or wrong fact

## Phase 1: Plan

- [ ] Fetch the ticket details (tracker from PROJECT.md section 2) and list the acceptance criteria
- [ ] Draft the test-data plan (DATA.md)
- [ ] Identify time-sensitive elements (TIMING.md, PROJECT.md section 9)
- [ ] Create test plan with `test.step()` structure (use template below)
- [ ] Get user approval for test plan
- [ ] Ask about folder placement (new or existing story folder)

## Phase 2: Set Up Test Data

- [ ] Pick the role / user (PROJECT.md section 3)
- [ ] Confirm each record exists in the seed, or plan how the test creates it
- [ ] Pick the named error / empty scenario, if needed
- [ ] Make sure the app is running for inspection

## Phase 3: Browser Inspection

- [ ] Open the page as that role (inspect script or browser MCP - BROWSER.md)
- [ ] Inspect UI elements for selectors (prefer testid > role > label > text)
- [ ] Note time-sensitive elements (polling, retries, auto-dismiss)
- [ ] Reference Playwright docs for patterns (WebFetch on playwright.dev)

## Phase 4: Generate Files

- [ ] Generate `{feature}.spec.ts` - Test implementation with `test.step()`
- [ ] Generate `locators.ts` - only if selectors are reused across tests
- [ ] Generate a test-data file - only if the project uses one
- [ ] Run lint / format on the new files
- [ ] Ask if user wants to run tests (command: PROJECT.md section 1)

---

## Test Plan Template

Present this format to user for approval:

```markdown
## E2E Test Plan for [TICKET-ID]: [Ticket Title]

### Ticket Summary
[Brief description from the ticket]

### Acceptance Criteria -> Scenarios
- AC1: [text] -> Scenario 1
- AC2: [text] -> Scenario 2

### Test Scenarios
(Each scenario becomes a `test()`, each step becomes a `test.step()`)

- [ ] **Scenario 1**: [Description]
  - Setup: [Required test data]
  - Steps (each -> test.step):
    1. [User action 1]
    2. [User action 2]
  - Expected: [Assertions]

### Test Data Plan (DATA.md)
- Role: [e.g. admin]
- Records needed: [what] -> from [seed / created in UI / API / file / scenario]
- Dates: [relative to today, or the project's date helper]

### Identified Selectors
- `someButton` -> `getByRole("button", { name: "Button Text" })`
- `resultCell` -> `getByRole("cell", { name: "Result" })`

### Recommended Folder
`<story folder from PROJECT.md section 5>/<TICKET>/`

**Approve this plan?**
```
