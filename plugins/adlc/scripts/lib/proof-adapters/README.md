# Proof adapters

One file per test harness. `adlc-proof.sh` sources the file named by the binding's `runner`
and calls two functions. The core owns everything else (tree hash, log, no-retry-to-green,
non-vacuity, classification, the timeout). Adding a harness means adding a file here, never
touching the core.

## Inputs (globals set by the core)

| name | meaning |
|---|---|
| `TEST_ID` | the one test to select (a name, a title, or a file) |
| `LOCATION` | the binding's `location` (folder the tests live in); may be empty |
| `PREFIX` | array: the binding's `prefix`, e.g. `("uv" "run")` or `("npx")`; may be empty |
| `EXTRA_ARGS` | array: the binding's `args` plus anything after `--` |
| `WT` | the worktree the command runs in (it is the working directory) |

## `adapter_build_cmd`

Fill the array `CMD` with the full command. It **must** add the isolation filter itself, so a
test that is not tagged agent-trusted cannot be selected, whatever the arguments say. If the
arguments try to widen or replace the filter (another grep, another marker expression,
retries), print why on stderr and return 1. The core then exits 2 and logs nothing.

## `adapter_classify <exit-code> <output-file>`

Print exactly one outcome:

| outcome | when |
|---|---|
| `pass` | exactly one selected test ran, and it passed |
| `fail` | exactly one selected test ran, and it failed |
| `build-error:<detail>` | compile/collection/load error, or the selection matched zero tests or more than one |
| `infra:<detail>` | the harness demonstrably did not run (Docker down, browser not installed, …) |

A test that never ran is never `fail`. When unsure between `fail` and `build-error`, pick
`build-error`: a false red would let a later green count as proof.
