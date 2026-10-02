# ADLC config — <project name>

Copy this file to `<project-root>/.claude/adlc-config.md` and fill it in. The project root is
where you start Claude Code; for a multi-repo product it is the folder that holds the repos.

The scripts read only the fenced `adlc-config` block below. Keep it flat: two-space indent,
`key: value`, no flow `{}` or `[]`. The prose around it is for humans.

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
  - name: my-api
    path: "my-api"
    base: main
  - name: my-web
    path: "my-web"
    base: main
```

## Fields

| field | meaning |
|---|---|
| `tracker` | `markdown` or `jira` (an adapter in `scripts/lib/trackers/`). |
| `tickets_dir` | Markdown tracker only: folder of `<KEY>.md` files, relative to the project root. |
| `statuses` | The tracker's own status name for each canonical state. For Jira, use the names in your workflow, e.g. `ready_for_agent: "Ready for Agent"`. |
| `repos` | Every repo a ticket may touch. `path` is relative to the project root (or absolute). `base` is the branch PRs target. Each repo needs its own `.claude/surface-bindings.json`. |

Jira needs `JIRA_BASE_URL` plus `JIRA_EMAIL` + `JIRA_API_TOKEN` (Cloud) or `JIRA_PAT`
(Server/Data Center) in the environment. Never commit them.

## Phase 0 answers

Record the five answers from the build order here, in prose, so the next person knows why.

1. **Issue tracker:**
2. **Repo layout:**
3. **Test harness per surface:** (the exact command that runs ONE named test)
4. **Proof test isolation:** (the tag or marker)
5. **Base branch and CI:**
