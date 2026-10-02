# shellcheck shell=bash
# Shared helpers for the ADLC scripts. Source it; do not run it.
#
# Pure bash plus POSIX awk/sed/grep. No jq, no yq, no node: the gates must run on a
# machine with no toolchain installed.

ADLC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADLC_SCRIPTS_DIR="$(cd "$ADLC_LIB_DIR/.." && pwd)"

adlc_die() {
  # adlc_die <exit-code> <message...>
  local code="$1"
  shift
  echo "adlc: $*" >&2
  exit "$code"
}

# ---------------------------------------------------------------------------------------
# Fenced blocks
# ---------------------------------------------------------------------------------------

# adlc_extract_fence <file> <info-string>
# Prints the body between a line "```<info>" and the next line "```".
# Exit 0 found, 3 none, 4 more than one, 5 unterminated.
adlc_extract_fence() {
  local file="$1" info="$2"
  [[ -f "$file" ]] || { echo "adlc: no such file: $file" >&2; return 3; }
  awk -v info="$info" '
    { sub(/\r$/, "") }
    !inside && $0 ~ "^```" info "[ \t]*$" { inside = 1; count++; next }
    inside && /^```[ \t]*$/ { inside = 0; next }
    inside && count == 1 { print }
    END {
      if (count == 0) exit 3
      if (count > 1) exit 4
      if (inside) exit 5
    }
  ' "$file"
}

# adlc_extract_block <file>  -> the machine-zone body (info string "adlc").
adlc_extract_block() {
  local rc=0
  adlc_extract_fence "$1" "adlc" || rc=$?
  case "$rc" in
    0) return 0 ;;
    3) echo "adlc: no \`\`\`adlc block in $1" >&2 ;;
    4) echo "adlc: more than one \`\`\`adlc block in $1; a ticket carries exactly one" >&2 ;;
    5) echo "adlc: the \`\`\`adlc block in $1 has no closing fence" >&2 ;;
  esac
  return "$rc"
}

# ---------------------------------------------------------------------------------------
# Strings
# ---------------------------------------------------------------------------------------

# adlc_unquote <value>  -> strips one pair of surrounding double quotes and unescapes \" \\.
adlc_unquote() {
  local v="$1"
  if [[ "$v" == \"*\" && ${#v} -ge 2 ]]; then
    v="${v:1:${#v}-2}"
    v="${v//\\\"/\"}"
    v="${v//\\\\/\\}"
  fi
  printf '%s' "$v"
}

# adlc_json_escape <string>  -> the string as a JSON string body (no surrounding quotes).
adlc_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  # Drop any other control characters rather than emit invalid JSON.
  s="$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')"
  printf '%s' "$s"
}

# adlc_sanitize_path <path>  -> a single directory name derived from an absolute path.
adlc_sanitize_path() {
  local p="${1#/}"
  p="${p//\//__}"
  p="${p//[^A-Za-z0-9._-]/_}"
  printf '%s' "${p:-root}"
}

# ---------------------------------------------------------------------------------------
# Project config: <project-root>/.claude/adlc-config.md, an ```adlc-config fenced block.
# ---------------------------------------------------------------------------------------

# adlc_find_root  -> the project root (the directory holding .claude/adlc-config.md).
adlc_find_root() {
  if [[ -n "${ADLC_PROJECT_ROOT:-}" ]]; then
    [[ -f "$ADLC_PROJECT_ROOT/.claude/adlc-config.md" ]] \
      || adlc_die 2 "ADLC_PROJECT_ROOT=$ADLC_PROJECT_ROOT has no .claude/adlc-config.md"
    (cd "$ADLC_PROJECT_ROOT" && pwd)
    return 0
  fi
  local d
  d="$(pwd)"
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/.claude/adlc-config.md" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  adlc_die 2 "no .claude/adlc-config.md found from $(pwd) upward; set ADLC_PROJECT_ROOT"
}

# adlc_config_body  -> the body of the ```adlc-config block.
adlc_config_body() {
  local root
  root="$(adlc_find_root)" || return 2
  adlc_extract_fence "$root/.claude/adlc-config.md" "adlc-config" \
    || adlc_die 2 "$root/.claude/adlc-config.md has no single \`\`\`adlc-config block"
}

# adlc_cfg <key>  -> a top-level scalar (unquoted). Empty when absent.
adlc_cfg() {
  local line
  line="$(adlc_config_body | grep -E "^$1:[ ]" | head -n 1)" || true
  adlc_unquote "${line#*: }"
}

# adlc_cfg_map <section> <key>  -> "<section>:\n  <key>: <value>" (unquoted). Empty when absent.
adlc_cfg_map() {
  local v
  v="$(adlc_config_body | awk -v sec="$1" -v key="$2" '
    /^[^ ]/ { insec = ($0 == sec ":") ; next }
    insec && $0 ~ "^  " key ":[ ]" { sub("^  " key ":[ ]", ""); print; exit }
  ')"
  adlc_unquote "$v"
}

# adlc_repo_names  -> one repo name per line.
adlc_repo_names() {
  adlc_config_body | awk '
    /^[^ ]/ { inrepos = ($0 == "repos:"); next }
    inrepos && /^  - name:[ ]/ { sub(/^  - name:[ ]/, ""); gsub(/^"|"$/, ""); print }
  '
}

# adlc_repo_field <repo-name> <field>  -> that field of that repo entry (unquoted).
adlc_repo_field() {
  local v
  v="$(adlc_config_body | awk -v want="$1" -v field="$2" '
    /^[^ ]/ { inrepos = ($0 == "repos:"); next }
    !inrepos { next }
    /^  - name:[ ]/ { n = $0; sub(/^  - name:[ ]/, "", n); gsub(/^"|"$/, "", n); cur = n
                      if (field == "name" && cur == want) { print n; exit } ; next }
    cur == want && $0 ~ "^    " field ":[ ]" { sub("^    " field ":[ ]", ""); print; exit }
  ')"
  adlc_unquote "$v"
}

# adlc_repo_path <repo-name>  -> absolute path of that repo's main checkout.
adlc_repo_path() {
  local root p
  root="$(adlc_find_root)" || return 2
  p="$(adlc_repo_field "$1" path)"
  [[ -n "$p" ]] || adlc_die 2 "repo '$1' is not listed in .claude/adlc-config.md"
  [[ "$p" == /* ]] || p="$root/$p"
  (cd "$p" 2>/dev/null && pwd) || adlc_die 2 "repo '$1' path does not exist: $p"
}

# ---------------------------------------------------------------------------------------
# Logs and state outside every worktree
# ---------------------------------------------------------------------------------------

adlc_home() {
  printf '%s' "${ADLC_LOG_HOME:-$HOME/.adlc}"
}

# adlc_main_checkout <path-inside-a-repo-or-worktree>  -> the main checkout's top level.
# Every worktree of one repo shares one log, so a fresh worktree cannot erase evidence.
adlc_main_checkout() {
  local common
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || adlc_die 2 "not a git repository: $1"
  if [[ "$(basename "$common")" == ".git" ]]; then
    dirname "$common"
  else
    printf '%s\n' "$common"
  fi
}

# adlc_state_dir <path-inside-a-repo-or-worktree>  -> created, absolute.
adlc_state_dir() {
  local main dir
  main="$(adlc_main_checkout "$1")" || return 2
  dir="$(adlc_home)/$(adlc_sanitize_path "$main")"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# adlc_append_line <file> <line>  -> append one line, under flock when available.
adlc_append_line() {
  local file="$1" line="$2"
  if command -v flock >/dev/null 2>&1; then
    {
      flock -x 9
      printf '%s\n' "$line" >>"$file"
    } 9>>"$file.lock"
  else
    printf '%s\n' "$line" >>"$file"
  fi
}

adlc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# ---------------------------------------------------------------------------------------
# Surface bindings: <repo>/.claude/surface-bindings.json
# ---------------------------------------------------------------------------------------

# adlc_json_flat <file>  -> "path<TAB>value" lines (see json-flat.awk).
adlc_json_flat() {
  awk -f "$ADLC_LIB_DIR/json-flat.awk" "$1"
}

# adlc_binding_methods <bindings-file>  -> one method name per line.
adlc_binding_methods() {
  adlc_json_flat "$1" | awk -F'\t' '$1 ~ /^bindings\// { split($1, p, "/"); if (!seen[p[2]]++) print p[2] }'
}

# adlc_binding_get <bindings-file> <method> <field>  -> a scalar field of that binding.
adlc_binding_get() {
  adlc_json_flat "$1" | awk -F'\t' -v k="bindings/$2/$3" '$1 == k { print $2; exit }'
}

# adlc_binding_surfaces <bindings-file> <method>  -> one surface per line.
adlc_binding_surfaces() {
  adlc_json_flat "$1" | awk -F'\t' -v k="bindings/$2/surface/" 'index($1, k) == 1 { print $2 }'
}
