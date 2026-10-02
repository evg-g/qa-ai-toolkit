#!/usr/bin/env bash
# adlc-worktree.sh <repo-path> <ticket-key> <base-branch>
#
# Creates (or reuses) the worktree for a ticket, outside the repo, on the shared branch from
# adlc-story-branch.sh, and prints its absolute path. If the branch exists locally or on
# origin (for example /refine already pushed ADRs to it), the worktree continues it;
# otherwise the branch starts from origin/<base> (or <base> when there is no origin).
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

[[ $# -eq 3 ]] || { echo "usage: adlc-worktree.sh <repo-path> <ticket-key> <base-branch>" >&2; exit 2; }
REPO="$(cd "$1" && pwd)"
KEY="$2"
BASE="$3"
BRANCH="$("$ADLC_SCRIPTS_DIR/adlc-story-branch.sh" "$KEY")"
MAIN="$(adlc_main_checkout "$REPO")"
WT="${ADLC_WORKTREE_HOME:-$(adlc_home)/worktrees}/$(basename "$MAIN")/$KEY"

# Reuse a worktree that already has this branch checked out.
existing="$(git -C "$MAIN" worktree list --porcelain | awk -v b="refs/heads/$BRANCH" '
  /^worktree / { wt = substr($0, 10) } $0 == "branch " b { print wt; exit }')"
if [[ -n "$existing" ]]; then
  printf '%s\n' "$existing"
  exit 0
fi

git -C "$MAIN" fetch --quiet origin 2>/dev/null || true
mkdir -p "$(dirname "$WT")"
if git -C "$MAIN" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git -C "$MAIN" worktree add --quiet "$WT" "$BRANCH" >&2
elif git -C "$MAIN" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
  git -C "$MAIN" worktree add --quiet -b "$BRANCH" "$WT" "origin/$BRANCH" >&2
elif git -C "$MAIN" show-ref --verify --quiet "refs/remotes/origin/$BASE"; then
  git -C "$MAIN" worktree add --quiet --no-track -b "$BRANCH" "$WT" "origin/$BASE" >&2
else
  git -C "$MAIN" worktree add --quiet -b "$BRANCH" "$WT" "$BASE" >&2
fi
printf '%s\n' "$WT"
