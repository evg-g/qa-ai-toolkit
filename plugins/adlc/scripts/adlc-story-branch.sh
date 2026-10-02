#!/usr/bin/env bash
# The ONE home for the shared feature-branch name. /refine pushes this branch,
# /implement continues it. Two prose-driven skills deriving the name separately
# would silently split the work across two branches.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "usage: adlc-story-branch.sh <ticket-key>" >&2; exit 2; }
KEY="$1"
[[ -n "${KEY// /}" ]] || { echo "usage: adlc-story-branch.sh <ticket-key>" >&2; exit 2; }
[[ "$KEY" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "ref-unsafe ticket key: $KEY" >&2; exit 2; }
printf 'story/%s\n' "$KEY"
