# The ticket contract

This is the seam between `/refine` and `/implement`. Both read it. `adlc-lint.sh` enforces it.

## Two zones

**Human zone** — the ticket description. One acceptance criterion per line, numbered from 1,
with no tags and no verification markers. A human wrote it and a human owns it.

**Machine zone** — exactly one fenced block, emitted by `/refine`, read by `/implement`, never
edited by hand. Where it lives depends on the tracker:

| tracker | where the block lives |
|---|---|
| `markdown` | the end of `<tickets_dir>/<KEY>.md`, after the marker comment, as a ```` ```adlc ```` fence |
| `jira` | one dedicated comment whose whole body is a `{noformat}` panel holding the block |

The relationship is one way: the prose is the source, the block is derived from it. `/refine`
regenerates the whole block on every run and never rewrites the prose. It may only **append**
to the prose (a Links section, an Open decisions section) or amend a defective criterion in
place with a visible marker: `_(amended by /refine: <why>)_`.

## Block format

Strict, flat, line-oriented YAML. Two-space indent, block style only, no flow `{}` or `[]`,
no comments, no blank lines, double-quoted strings where the table says "quoted".

```yaml
feature: "<ticket key and title>"
repos:
  - <repo-name>
acceptance:
  - id: "AC1.api"
    surface: api
    repo: <repo-name>
    assertion: "A newly created user has notifications disabled."
    enum_boundary: "default-state partition {unset->off, on->on, off->off}; auth failures out of scope."
    irreversible: false
    defaulted:
      - "page size: 50"
    binding:
      method: <a key of the repo's .claude/surface-bindings.json, or unbound>
    examples:
      - scenario: "Create a user, set no preference"
        outcome: "GET /preferences returns notificationsEnabled == false"
seal: "sha256:<64 hex>"
```

| field | required | kind | meaning |
|---|---|---|---|
| `feature` | yes | quoted | Ticket key and title. First line. |
| `repos` | yes | list of bare words | Every repo this ticket touches. One PR per repo. |
| `id` | yes | quoted | `AC<n>.<surface>`. One product criterion crossing three surfaces becomes `AC1.data`, `AC1.api`, `AC1.ui`. `<n>` is the criterion's number in the prose. |
| `surface` | yes | bare | One of `api data logic component ui design`. Must match the id suffix. |
| `repo` | yes | bare | Must appear in `repos`. |
| `assertion` | yes | quoted | Self-contained restatement. A reader who has not seen the prose must understand it. |
| `enum_boundary` | yes | quoted | Which partition this criterion covers, and what is out of scope. |
| `irreversible` | yes | `true`/`false` | `true` when a wrong result escapes the system boundary — sends mail, charges, notifies, writes to a third party. Default `true` when unsure. `/implement` proves it against a stub and never fires the real effect. |
| `defaulted` | no | list of quoted | Knobs `/refine` set without asking (wrong but adjustable later). Each is pinned in an example. |
| `binding.method` | yes | bare | A key from the repo's `.claude/surface-bindings.json` whose `surface` list covers this entry's surface — or `unbound`. |
| `binding.reason` | with `unbound` only | quoted | Why no binding can prove it. `/implement` flags it; it is never skipped and never reported proven. |
| `examples` | yes, ≥ 1 | list | Each is `scenario` then `outcome`, both quoted. |
| `seal` | yes | quoted | `sha256:` over the block body with the `seal:` line removed. Written by `adlc-seal.sh write`. Last line. |

**A data field carries data. It never argues for itself.** An example is a scenario and an
outcome — not why it was chosen or what it demonstrates. `enum_boundary` names the boundary;
it does not restate the assertion or justify the scope. This is about content, not length:
the fix for a bloated block is deleting what does not belong in it.

## The surface tags

| tag | asserts | typical proof |
|---|---|---|
| `[api]` | A request produces a response | integration test against a running service |
| `[data]` | State persists correctly | assertion against the real database |
| `[logic]` | A pure function or rule is correct | unit test |
| `[component]` | A component renders and behaves | component test in a **real browser** |
| `[ui]` | A user journey works end to end | browser test against the live app |
| `[design]` | The rendered structure matches an approved design | capture judged against the reference — only where approved designs exist |

A DOM-only environment (jsdom, happy-dom) neither lays out nor paints. It can prove what is in
the DOM, never what the user sees, so it is bound to `[logic]` only, never `[component]`/`[ui]`.

## Surface bindings — `<repo>/.claude/surface-bindings.json`

One per repo, committed. It maps a binding method to a real harness.

```json
{
  "repo": "my-api",
  "bindings": {
    "pytest-integration": {
      "surface": ["api", "data"],
      "runner": "pytest",
      "prefix": ["uv", "run"],
      "location": "tests/integration",
      "args": [],
      "env": { "CI": "1" },
      "selector": "documentation only: -m agent_trusted -k <TEST_NAME>"
    }
  }
}
```

| field | meaning |
|---|---|
| `surface` | Surfaces this method can prove. |
| `runner` | The proof adapter in `scripts/lib/proof-adapters/` (`pytest`, `vitest`, `playwright`, `sh`). |
| `prefix` | Words run before the tool (`["uv","run"]`, `["npx"]`). Optional. |
| `location` | The folder the proof tests live in. |
| `args` | Extra fixed arguments, e.g. `["--project=chromium"]`. Optional. |
| `env` | Environment variables set for the run, e.g. `{"CI": "1"}` so Playwright never reuses a server some other checkout started. Optional. |
| `selector` | Human-readable note only. |

**Isolation is built into the adapter, not the JSON.** The adapter always adds the filter —
pytest `-m agent_trusted`, Playwright and Vitest `(?=.*@agent-trusted)(?=.*<title>)` — and
refuses arguments that would widen or replace it. A test not tagged agent-trusted cannot be
selected as a proof, whatever a binding or an agent passes.

## Canonical ticket states

`draft` → `in-refinement` → `ready-for-agent` → `in-progress` → `in-review` → `done`.
The config's `statuses:` map gives each one the tracker's own name.
