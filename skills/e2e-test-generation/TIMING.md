# Time-Sensitive Elements & Rules

When inspecting UI and planning tests, be aware of ALL these time-based behaviors in the app.

## CRITICAL: Browser Inspection Timing Blindspot

**Problem**: When inspecting UI in the browser, clicking slowly (screenshot -> wait -> click -> wait) masks time-sensitive behaviors. A 10-second timer in the app will seem instant if your inspection already took 10+ seconds between actions.

**Risk**: Writing tests with wrong timing expectations (assuming immediate behavior when there's actually a delay).

**Solution**:
- **Ask the user** about timers/delays between actions during planning
- **Check source code** for timeouts (search for `setTimeout`, `timer`, countdown components)
- **Don't trust slow inspection** for understanding timing behavior
- When you see a redirect or state change during inspection, ask: "Was this immediate or was there a delay?"

## This Project's Timers

The project's known timers (UI timers, polling, retries, reconnects) and the timeout advice for
them are listed in PROJECT.md section 9. Before planning, search the code again for new ones:
`setTimeout`, `setInterval`, `refetchInterval`, `staleTime`, `retry`, countdown or toast
components.

## Test Timeout Guidelines

| Scenario | Guidance | Reason |
|----------|----------|--------|
| Initial page load | Use the suite's default `expect` timeout first | Raise it only with a reason in a comment |
| A UI element that auto-dismisses | Act well before its timeout | It disappears on its own |
| An auto-redirect or auto-advance | Timeout = countdown + buffer | Waiting less makes a false failure |
| An error state behind a retry | Timeout = retries x delay + buffer | The first failure is retried before the error shows |
| Polling / refetch updates | Timeout > one polling interval | The new value only appears on the next poll |

## Planning Checklist for Time-Sensitive Tests

- [ ] If the test acts on something that auto-dismisses (e.g. a toast "Undo"): plan to act within its timeout
- [ ] If the flow auto-advances or auto-redirects: decide whether to test the manual click or the auto path
- [ ] For auto-advance or polling tests: set the timeout above the countdown / interval (PROJECT.md section 9)
- [ ] Add comments explaining any `timeout` values in assertions
- [ ] When you see a redirect during browser inspection: **Ask user if it was immediate or delayed**
