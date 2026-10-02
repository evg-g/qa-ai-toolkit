# shellcheck shell=bash
# Plain shell-script adapter: TEST_ID is a script under LOCATION. Isolation: the script must
# carry a line containing "@agent-trusted". Exit 0 = pass, 1 = fail, 77 = environment fault
# (the autotools "skip" code), anything else = build error.

adapter_build_cmd() {
  local f="${LOCATION:+$LOCATION/}$TEST_ID"
  [[ "$TEST_ID" != *..* && "$TEST_ID" != /* ]] || { echo "sh adapter: test id must be a relative path without '..'" >&2; return 1; }
  [[ -f "$WT/$f" ]] || { echo "sh adapter: no test script $WT/$f" >&2; return 1; }
  grep -q '@agent-trusted' "$WT/$f" || { echo "sh adapter: $f is not tagged @agent-trusted" >&2; return 1; }
  CMD=(bash "$f" ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"})
}

adapter_classify() {
  case "$1" in
    0) echo "pass" ;;
    1) echo "fail" ;;
    77) echo "infra:the script reported an environment fault (exit 77)" ;;
    *) echo "build-error:script exit $1" ;;
  esac
}
