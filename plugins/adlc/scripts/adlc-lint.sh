#!/usr/bin/env bash
# adlc-lint.sh — structural lint of a ticket's machine block (Rules 1 and 2).
#
#   adlc-lint.sh <file> [--bindings <repo>=<surface-bindings.json>]... [--no-seal]
#
# <file> holds exactly one ```adlc fenced block. Without --bindings, each repo's bindings
# file is found through .claude/adlc-config.md as <repo-path>/.claude/surface-bindings.json.
# --no-seal skips the seal check; /refine uses it only on the draft it is about to seal.
#
# Exit 0 clean. Exit 1 with one line per problem, each naming the entry and the field —
# the reader is an agent that must fix it, so "validation failed" alone is never enough.
# Exit 2 on a usage error or an unreadable file.
#
# Pure bash 3.2+ with POSIX awk/sed/grep: no jq, no yq, no node, no associative arrays.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  echo "usage: adlc-lint.sh <file> [--bindings <repo>=<surface-bindings.json>]... [--no-seal]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
FILE="$1"
shift
CHECK_SEAL=1
BIND_REPOS=()
BIND_FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bindings)
      [[ $# -ge 2 && "$2" == *=* ]] || usage
      BIND_REPOS+=("${2%%=*}")
      BIND_FILES+=("${2#*=}")
      shift 2
      ;;
    --no-seal)
      CHECK_SEAL=0
      shift
      ;;
    *) usage ;;
  esac
done

BODY="$(adlc_extract_block "$FILE")" || exit 2

SURFACES="api data logic component ui design"
QUOTED='^"([^"\\]|\\.)*"$'
BARE='^[A-Za-z0-9._-]+$'
ERRORS=()
err() { ERRORS+=("$*"); }

# ----- parse ------------------------------------------------------------------------------

FEATURE=""
SEAL=""
SEEN_TOP=""
REPOS=()
N=0 # entries
E_ID=() E_SURFACE=() E_REPO=() E_ASSERT=() E_ENUM=() E_IRREV=() E_METHOD=() E_REASON=()
E_EX=() E_LINE=() E_BINDING=() E_EXAMPLES=()
SECTION="" # repos | acceptance | done
SUB=""     # binding | examples | defaulted
EX_OPEN=0  # an example has a scenario and still needs its outcome
LN=0

# entry label for messages
label() {
  local i="$1"
  if [[ -n "${E_ID[$i]}" ]]; then
    printf 'entry %s' "$(adlc_unquote "${E_ID[$i]}")"
  else
    printf 'entry #%d (line %d)' "$((i + 1))" "${E_LINE[$i]}"
  fi
}

# check_value <where> <field> <kind> <value>   kind: quoted | bare | bool
check_value() {
  local where="$1" field="$2" kind="$3" v="$4"
  case "$v" in
    \{* | \[*)
      err "$where: field '$field' uses flow style ($v); use block style"
      return 1
      ;;
  esac
  case "$kind" in
    quoted)
      if ! [[ "$v" =~ $QUOTED ]]; then
        err "$where: field '$field' must be a double-quoted string, got: $v"
        return 1
      fi
      if [[ "$v" == '""' ]]; then
        err "$where: field '$field' is empty"
        return 1
      fi
      ;;
    bare)
      if ! [[ "$v" =~ $BARE ]]; then
        err "$where: field '$field' must be a bare word [A-Za-z0-9._-], got: $v"
        return 1
      fi
      ;;
    bool)
      if [[ "$v" != "true" && "$v" != "false" ]]; then
        err "$where: field '$field' must be true or false, got: $v"
        return 1
      fi
      ;;
  esac
  return 0
}

close_example() {
  if [[ $EX_OPEN -eq 1 ]]; then
    err "$(label $((N - 1))): an example has a scenario but no outcome"
    EX_OPEN=0
  fi
}

while IFS= read -r line || [[ -n "$line" ]]; do
  LN=$((LN + 1))
  where="line $LN"
  if [[ -z "${line// /}" ]]; then
    err "$where: blank line; the block allows none"
    continue
  fi
  if [[ "$line" == *$'\t'* ]]; then
    err "$where: tab character; use two-space indentation"
    continue
  fi
  if [[ "$line" =~ ^[[:space:]]*# ]]; then
    err "$where: comment; the block allows none"
    continue
  fi
  indent="${line%%[! ]*}"
  ind=${#indent}
  text="${line#"$indent"}"
  if [[ $((ind % 2)) -ne 0 ]]; then
    err "$where: indent of $ind spaces; use multiples of two"
    continue
  fi
  if [[ "$text" == *": "* ]]; then
    key="${text%%: *}"
    val="${text#*: }"
  elif [[ "$text" == *":" ]]; then
    key="${text%:}"
    val=""
  else
    key=""
    val="$text"
  fi

  # --- top level
  if [[ $ind -eq 0 ]]; then
    [[ $N -gt 0 ]] && close_example
    SUB=""
    case "$key" in
      feature)
        [[ -z "$SEEN_TOP" ]] || err "$where: 'feature' must be the first key"
        check_value "$where" feature quoted "$val" && FEATURE="$val"
        SEEN_TOP="$SEEN_TOP feature"
        SECTION=""
        ;;
      repos)
        [[ -z "$val" ]] || err "$where: 'repos' must be a block list, got: $val"
        [[ "$SEEN_TOP" == " feature" ]] || err "$where: 'repos' must follow 'feature'"
        SEEN_TOP="$SEEN_TOP repos"
        SECTION="repos"
        ;;
      acceptance)
        [[ -z "$val" ]] || err "$where: 'acceptance' must be a block list, got: $val"
        [[ "$SEEN_TOP" == " feature repos" ]] || err "$where: 'acceptance' must follow 'repos'"
        SEEN_TOP="$SEEN_TOP acceptance"
        SECTION="acceptance"
        ;;
      seal)
        [[ "$SEEN_TOP" == " feature repos acceptance" ]] || err "$where: 'seal' must be the last key, after 'acceptance'"
        if check_value "$where" seal quoted "$val"; then
          SEAL="$(adlc_unquote "$val")"
          [[ "$SEAL" =~ ^sha256:[0-9a-f]{64}$ ]] || err "$where: seal must be \"sha256:<64 hex>\", got: $val"
        fi
        SEEN_TOP="$SEEN_TOP seal"
        SECTION="done"
        ;;
      *)
        err "$where: unknown top-level key '${key:-$text}'; allowed: feature, repos, acceptance, seal"
        ;;
    esac
    continue
  fi

  case "$SECTION" in
    repos)
      if [[ $ind -eq 2 && "$text" == "- "* ]]; then
        r="${text#- }"
        if check_value "$where" "repos[]" bare "$r"; then
          for x in ${REPOS[@]+"${REPOS[@]}"}; do
            [[ "$x" == "$r" ]] && err "$where: repo '$r' is listed twice in 'repos'"
          done
          REPOS+=("$r")
        fi
      else
        err "$where: 'repos' entries must be '  - <repo-name>'"
      fi
      continue
      ;;
    acceptance) ;;
    *)
      err "$where: indented line outside any section"
      continue
      ;;
  esac

  # --- acceptance entries
  if [[ $ind -eq 2 ]]; then
    if [[ "$text" == "- id: "* ]]; then
      [[ $N -gt 0 ]] && close_example
      E_ID[$N]=""
      E_SURFACE[$N]="" E_REPO[$N]="" E_ASSERT[$N]="" E_ENUM[$N]="" E_IRREV[$N]=""
      E_METHOD[$N]="" E_REASON[$N]="" E_EX[$N]=0 E_LINE[$N]=$LN E_BINDING[$N]=0 E_EXAMPLES[$N]=0
      v="${text#- id: }"
      check_value "$where" id quoted "$v" && E_ID[$N]="$v"
      N=$((N + 1))
      SUB=""
    else
      err "$where: each acceptance entry must start with '  - id: \"AC<n>.<surface>\"'"
    fi
    continue
  fi
  if [[ $N -eq 0 ]]; then
    err "$where: field before the first '  - id:' entry"
    continue
  fi
  i=$((N - 1))
  W="$(label "$i") ($where)"

  if [[ $ind -eq 4 ]]; then
    close_example
    SUB=""
    case "$key" in
      surface) check_value "$W" surface bare "$val" && E_SURFACE[$i]="$val" ;;
      repo) check_value "$W" repo bare "$val" && E_REPO[$i]="$val" ;;
      assertion) check_value "$W" assertion quoted "$val" && E_ASSERT[$i]="$val" ;;
      enum_boundary) check_value "$W" enum_boundary quoted "$val" && E_ENUM[$i]="$val" ;;
      irreversible) check_value "$W" irreversible bool "$val" && E_IRREV[$i]="$val" ;;
      binding)
        [[ -z "$val" ]] || err "$W: 'binding' must be a block map, got: $val"
        E_BINDING[$i]=1
        SUB="binding"
        ;;
      examples)
        [[ -z "$val" ]] || err "$W: 'examples' must be a block list, got: $val"
        E_EXAMPLES[$i]=1
        SUB="examples"
        ;;
      defaulted)
        [[ -z "$val" ]] || err "$W: 'defaulted' must be a block list, got: $val"
        SUB="defaulted"
        ;;
      *)
        err "$W: unknown field '${key:-$text}'"
        ;;
    esac
    continue
  fi

  case "$SUB" in
    binding)
      if [[ $ind -eq 6 && "$key" == "method" ]]; then
        check_value "$W" binding.method bare "$val" && E_METHOD[$i]="$val"
      elif [[ $ind -eq 6 && "$key" == "reason" ]]; then
        check_value "$W" binding.reason quoted "$val" && E_REASON[$i]="$val"
      else
        err "$W: 'binding' allows only '      method:' and '      reason:'"
      fi
      ;;
    examples)
      if [[ $ind -eq 6 && "$text" == "- scenario: "* ]]; then
        close_example
        check_value "$W" examples[].scenario quoted "${text#- scenario: }"
        EX_OPEN=1
      elif [[ $ind -eq 8 && "$key" == "outcome" ]]; then
        if [[ $EX_OPEN -eq 1 ]]; then
          check_value "$W" examples[].outcome quoted "$val"
          E_EX[$i]=$((E_EX[i] + 1))
          EX_OPEN=0
        else
          err "$W: 'outcome' without a 'scenario' before it"
        fi
      else
        err "$W: examples must be '      - scenario: \"...\"' then '        outcome: \"...\"'"
      fi
      ;;
    defaulted)
      if [[ $ind -eq 6 && "$text" == "- "* ]]; then
        check_value "$W" "defaulted[]" quoted "${text#- }"
      else
        err "$W: 'defaulted' entries must be '      - \"<knob>: <value>\"'"
      fi
      ;;
    *)
      err "$W: unexpected line: $text"
      ;;
  esac
done <<<"$BODY"
[[ $N -gt 0 ]] && close_example

# ----- whole-block checks ----------------------------------------------------------------

[[ -n "$FEATURE" ]] || err "block: missing top-level 'feature'"
[[ ${#REPOS[@]} -gt 0 ]] || err "block: 'repos' is missing or empty"
[[ $N -gt 0 ]] || err "block: 'acceptance' is missing or has no entries"
[[ "$SEEN_TOP" == *seal* ]] || err "block: missing 'seal' line (run adlc-seal.sh write)"

bindings_for() {
  # prints the bindings file for a repo name, or nothing
  local r="$1" k=0
  while [[ $k -lt ${#BIND_REPOS[@]} ]]; do
    if [[ "${BIND_REPOS[$k]}" == "$r" ]]; then
      printf '%s' "${BIND_FILES[$k]}"
      return 0
    fi
    k=$((k + 1))
  done
  local p
  p="$( (adlc_repo_path "$r") 2>/dev/null)" || return 0
  printf '%s' "$p/.claude/surface-bindings.json"
}

i=0
while [[ $i -lt $N ]]; do
  L="$(label "$i")"
  id="$(adlc_unquote "${E_ID[$i]}")"
  surface="${E_SURFACE[$i]}"
  repo="${E_REPO[$i]}"

  [[ -n "$id" ]] || err "$L: missing required field 'id'"
  [[ -n "$surface" ]] || err "$L: missing required field 'surface'"
  [[ -n "$repo" ]] || err "$L: missing required field 'repo'"
  [[ -n "${E_ASSERT[$i]}" ]] || err "$L: missing required field 'assertion'"
  [[ -n "${E_ENUM[$i]}" ]] || err "$L: missing required field 'enum_boundary'"
  [[ -n "${E_IRREV[$i]}" ]] || err "$L: missing required field 'irreversible'"
  [[ "${E_BINDING[$i]}" -eq 1 ]] || err "$L: missing required field 'binding'"
  if [[ "${E_BINDING[$i]}" -eq 1 && -z "${E_METHOD[$i]}" ]]; then
    err "$L: missing required field 'binding.method'"
  fi
  if [[ "${E_EXAMPLES[$i]}" -eq 0 ]]; then
    err "$L: missing required field 'examples'"
  elif [[ "${E_EX[$i]}" -eq 0 ]]; then
    err "$L: 'examples' has zero complete {scenario, outcome} pairs; at least one is required"
  fi

  if [[ -n "$surface" && " $SURFACES " != *" $surface "* ]]; then
    err "$L: surface '$surface' is not one of: $SURFACES"
  fi
  if [[ -n "$id" ]]; then
    if ! [[ "$id" =~ ^AC[1-9][0-9]*\.[a-z]+$ ]]; then
      err "$L: id must be AC<n>.<surface> (e.g. AC1.api), got: $id"
    elif [[ -n "$surface" && "${id#*.}" != "$surface" ]]; then
      err "$L: id suffix '.${id#*.}' does not match surface '$surface'"
    fi
    j=0
    while [[ $j -lt $i ]]; do
      if [[ "$(adlc_unquote "${E_ID[$j]}")" == "$id" ]]; then
        err "$L: duplicate id '$id' (first used at line ${E_LINE[$j]})"
      fi
      j=$((j + 1))
    done
  fi

  if [[ -n "$repo" ]]; then
    found=0
    for x in ${REPOS[@]+"${REPOS[@]}"}; do [[ "$x" == "$repo" ]] && found=1; done
    [[ $found -eq 1 ]] || err "$L: repo '$repo' is not listed in top-level 'repos'"
  fi

  method="${E_METHOD[$i]}"
  if [[ "$method" == "unbound" ]]; then
    [[ -n "${E_REASON[$i]}" ]] || err "$L: binding.method 'unbound' needs a binding.reason saying why it cannot be proven"
  elif [[ -n "$method" ]]; then
    [[ -z "${E_REASON[$i]}" ]] || err "$L: binding.reason is only allowed with method 'unbound'"
    if [[ -n "$repo" ]]; then
      bf="$(bindings_for "$repo")"
      if [[ -z "$bf" || ! -f "$bf" ]]; then
        err "$L: binding.method '$method': no surface-bindings.json found for repo '$repo'${bf:+ (looked at $bf)}"
      elif ! methods="$(adlc_binding_methods "$bf" 2>&1)"; then
        err "$L: binding.method '$method': cannot parse $bf: $methods"
      elif ! grep -qxF "$method" <<<"$methods"; then
        err "$L: binding.method '$method' is not in $bf (known: $(tr '\n' ' ' <<<"$methods"))"
      elif [[ -n "$surface" ]] && ! adlc_binding_surfaces "$bf" "$method" | grep -qxF "$surface"; then
        err "$L: binding.method '$method' in $bf does not cover surface '$surface'"
      fi
    fi
  fi
  i=$((i + 1))
done

if [[ $CHECK_SEAL -eq 1 && "$SEEN_TOP" == *seal* ]]; then
  if ! seal_out="$("$ADLC_SCRIPTS_DIR/adlc-seal.sh" check "$FILE" 2>&1)"; then
    err "block: seal does not verify — $(head -n 1 <<<"$seal_out" | sed 's/^adlc-seal: //')"
  fi
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  printf 'adlc-lint: %s\n' "${ERRORS[@]}" >&2
  echo "adlc-lint: $FILE: ${#ERRORS[@]} problem(s)" >&2
  exit 1
fi
echo "adlc-lint: $FILE: ok ($N criteria, repos: ${REPOS[*]})"
