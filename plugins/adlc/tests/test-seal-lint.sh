#!/usr/bin/env bash
# Phase 2 acceptance: a valid block lints clean; each corruption exits 1 and names the problem.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

B="--bindings demo-api=$FIX/bindings.json"

# corrupt <name> <sed-expression> [reseal]  -> path of a corrupted copy of the valid ticket
corrupt() {
  local f="$WORK/$1.md"
  sed -e "$2" "$FIX/valid-ticket.md" >"$f"
  if [[ "${3:-}" == "reseal" ]]; then
    "$SCRIPTS/adlc-seal.sh" write "$f" >/dev/null
  fi
  printf '%s' "$f"
}

echo "seal"
expect 0 "seal ok" "valid ticket: seal check passes" -- "$SCRIPTS/adlc-seal.sh" check "$FIX/valid-ticket.md"
f="$(corrupt edited 's/notifications disabled/notifications enabled/')"
expect 1 "seal mismatch" "one character changed without resealing: seal check fails" -- "$SCRIPTS/adlc-seal.sh" check "$f"
f="$(corrupt noseal '/^seal:/d')"
expect 1 "no seal: line" "seal line removed: seal check fails" -- "$SCRIPTS/adlc-seal.sh" check "$f"
f="$(corrupt crlf 's/$/\r/')"
expect 0 "seal ok" "CRLF line endings: the seal still verifies" -- "$SCRIPTS/adlc-seal.sh" check "$f"
cp "$FIX/valid-ticket.md" "$WORK/twice.md"
"$SCRIPTS/adlc-seal.sh" write "$WORK/twice.md" >/dev/null
expect 0 "seal ok" "write is idempotent" -- "$SCRIPTS/adlc-seal.sh" check "$WORK/twice.md"
if cmp -s "$FIX/valid-ticket.md" "$WORK/twice.md"; then ok "write on a sealed block changes nothing"; else not_ok "write on a sealed block changed the file"; fi

echo "lint: the valid block"
# shellcheck disable=SC2086
expect 0 "ok \(2 criteria" "valid block lints clean" -- "$SCRIPTS/adlc-lint.sh" "$FIX/valid-ticket.md" $B

echo "lint: the four corruptions from the build order"
f="$(corrupt nofield '/enum_boundary: "default-state/d' reseal)"
# shellcheck disable=SC2086
expect 1 "entry AC1.api: missing required field 'enum_boundary'" "required field deleted" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt dupid 's/id: "AC1.data"/id: "AC1.api"/; s/surface: data/surface: api/' reseal)"
# shellcheck disable=SC2086
expect 1 "duplicate id 'AC1.api'" "duplicate id" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt surface 's/id: "AC1.data"/id: "AC1.db"/; s/surface: data/surface: db/' reseal)"
# shellcheck disable=SC2086
expect 1 "surface 'db' is not one of" "unknown surface" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt edited 's/notifications disabled/notifications enabled/')"
# shellcheck disable=SC2086
expect 1 "seal does not verify" "assertion changed without resealing" -- "$SCRIPTS/adlc-lint.sh" "$f" $B

echo "lint: the other blocking rules"
f="$(corrupt flow 's/^    irreversible: false$/    irreversible: {a: 1}/' reseal)"
# shellcheck disable=SC2086
expect 1 "flow style" "flow style" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt unquoted 's/assertion: "A newly created user has notifications disabled."/assertion: A newly created user/' reseal)"
# shellcheck disable=SC2086
expect 1 "entry AC1.api.*'assertion' must be a double-quoted string" "unquoted string" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt indent 's/^    surface: api$/     surface: api/' reseal)"
# shellcheck disable=SC2086
expect 1 "indent of 5 spaces" "bad indent" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt repo 's/^    repo: demo-api$/    repo: other-api/' reseal)"
# shellcheck disable=SC2086
expect 1 "repo 'other-api' is not listed in top-level 'repos'" "repo not in repos" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt noex '0,/- scenario:/{/- scenario:/d}; /outcome: "GET/d' reseal)"
# shellcheck disable=SC2086
expect 1 "entry AC1.api: 'examples' has zero complete" "zero examples" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt method 's/method: pytest-integration/method: cypress/' reseal)"
# shellcheck disable=SC2086
expect 1 "binding.method 'cypress' is not in" "binding method absent from the bindings file" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt wrongsurf '0,/method: pytest-integration/s//method: pytest-unit/' reseal)"
# shellcheck disable=SC2086
expect 1 "does not cover surface 'api'" "binding method that does not cover the surface" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt idsuffix 's/id: "AC1.api"/id: "AC1.ui"/' reseal)"
# shellcheck disable=SC2086
expect 1 "id suffix '.ui' does not match surface 'api'" "id suffix differs from surface" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt blank 's/^    irreversible: false$/    irreversible: false\n/' reseal)"
# shellcheck disable=SC2086
expect 1 "blank line" "blank line inside the block" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt unbound 's/method: pytest-integration/method: unbound/' reseal)"
# shellcheck disable=SC2086
expect 1 "needs a binding.reason" "unbound without a reason" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
f="$(corrupt unboundok '0,/method: pytest-integration/s//method: unbound\n      reason: "No harness reaches the mail relay."/' reseal)"
# shellcheck disable=SC2086
expect 0 "ok" "unbound with a reason is allowed (flagged later, never skipped)" -- "$SCRIPTS/adlc-lint.sh" "$f" $B
cat "$FIX/valid-ticket.md" "$FIX/valid-ticket.md" >"$WORK/two.md"
# shellcheck disable=SC2086
expect 2 "more than one" "two blocks in one ticket" -- "$SCRIPTS/adlc-lint.sh" "$WORK/two.md" $B
expect 1 "no surface-bindings.json found for repo 'demo-api'" "no bindings file for the repo" -- env ADLC_PROJECT_ROOT= "$SCRIPTS/adlc-lint.sh" "$FIX/valid-ticket.md"

finish
