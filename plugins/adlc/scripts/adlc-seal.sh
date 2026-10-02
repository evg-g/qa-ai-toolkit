#!/usr/bin/env bash
# adlc-seal.sh — the sha256 seal over a ticket's machine block (Rule 1).
#
#   adlc-seal.sh write <file>    compute the seal and set the seal: line
#   adlc-seal.sh check <file>    recompute and compare: exit 0 match, 1 mismatch
#   adlc-seal.sh compute <file>  print "sha256:<hex>" for the current body
#
# <file> holds exactly one ```adlc fenced block (a Markdown ticket, or the block file a
# tracker adapter wrote). The seal covers the block body between the fences with every
# `seal:` line removed. Trailing CR is ignored so a CRLF round trip does not break it.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  echo "usage: adlc-seal.sh write|check|compute <file>" >&2
  exit 2
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

compute() {
  local body
  body="$(adlc_extract_block "$1")" || exit 2
  printf '%s\n' "$body" | grep -vE '^seal:' | sha256_stdin | sed 's/^/sha256:/'
}

[[ $# -eq 2 ]] || usage
cmd="$1"
file="$2"

case "$cmd" in
  compute)
    compute "$file"
    ;;
  check)
    want="$(compute "$file")"
    lines="$(adlc_extract_block "$file" | grep -cE '^seal:' || true)"
    if [[ "$lines" -eq 0 ]]; then
      echo "adlc-seal: $file: the block has no seal: line (expected seal: \"$want\")" >&2
      exit 1
    fi
    if [[ "$lines" -gt 1 ]]; then
      echo "adlc-seal: $file: the block has $lines seal: lines; exactly one is allowed" >&2
      exit 1
    fi
    have="$(adlc_extract_block "$file" | grep -E '^seal:' | sed -E 's/^seal:[ ]*//')"
    have="$(adlc_unquote "$have")"
    if [[ "$have" != "$want" ]]; then
      echo "adlc-seal: $file: seal mismatch — the block was edited after /refine emitted it." >&2
      echo "adlc-seal:   recorded: $have" >&2
      echo "adlc-seal:   computed: $want" >&2
      echo "adlc-seal: Re-run /refine to regenerate the block; never hand-edit it." >&2
      exit 1
    fi
    echo "adlc-seal: $file: seal ok ($want)"
    ;;
  write)
    seal="$(compute "$file")"
    tmp="$(mktemp "${file}.XXXXXX")"
    awk -v seal="$seal" '
      { line = $0; sub(/\r$/, "", line) }
      !inside && line ~ /^```adlc[ \t]*$/ { inside = 1; print line; next }
      inside && line ~ /^```[ \t]*$/ { print "seal: \"" seal "\""; inside = 0; print line; next }
      inside && line ~ /^seal:/ { next }
      inside { print line; next }
      { print }
    ' "$file" >"$tmp"
    # Copy back rather than mv, so the file keeps its own permissions.
    cat "$tmp" >"$file"
    rm -f "$tmp"
    echo "adlc-seal: $file: sealed ($seal)"
    ;;
  *)
    usage
    ;;
esac
