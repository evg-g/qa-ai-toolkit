# shellcheck shell=bash
# Playwright adapter. Isolation: the adapter builds the only --grep, and it requires both the
# @agent-trusted tag and the test title, so an untagged test cannot be selected. Retries are
# forced to 0: a retried green is exactly what no-retry-to-green forbids.

_pw_regex_escape() {
  printf '%s' "$1" | sed -e 's/[][\\.^$*+?(){}|\/]/\\&/g'
}

adapter_build_cmd() {
  local a
  for a in ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; do
    case "$a" in
      -g | -g* | --grep | --grep=* | --grep-invert* | --retries* | --last-failed | --only-changed* | --repeat-each* | --pass-with-no-tests)
        echo "playwright adapter: '$a' is not allowed; the adapter owns selection and retries" >&2
        return 1
        ;;
    esac
  done
  local prefix=(${PREFIX[@]+"${PREFIX[@]}"})
  [[ ${#prefix[@]} -gt 0 ]] || prefix=(npx)
  CMD=("${prefix[@]}" playwright test ${LOCATION:+"$LOCATION"}
    --grep "(?=.*@agent-trusted)(?=.*$(_pw_regex_escape "$TEST_ID"))"
    --retries=0 --reporter=list --workers=1
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"})
}

adapter_classify() {
  local rc="$1" out="$2" passed failed flaky
  if grep -qE "Executable doesn't exist at|browserType\.launch: .*(Host system is missing dependencies|error while loading shared libraries)|Please run the following command to download new browsers" "$out"; then
    echo "infra:the browser is not installed or cannot start"
    return
  fi
  if grep -qE '^Error: No tests found' "$out"; then
    echo "build-error:selected no test (is the title tagged @agent-trusted?)"
    return
  fi
  passed="$(grep -E '^ *[0-9]+ passed' "$out" | tail -n 1 | sed -nE 's/^ *([0-9]+) passed.*/\1/p')"
  failed="$(grep -E '^ *[0-9]+ failed' "$out" | tail -n 1 | sed -nE 's/^ *([0-9]+) failed.*/\1/p')"
  flaky="$(grep -E '^ *[0-9]+ flaky' "$out" | tail -n 1 | sed -nE 's/^ *([0-9]+) flaky.*/\1/p')"
  passed="${passed:-0}" failed="${failed:-0}" flaky="${flaky:-0}"
  if [[ "$flaky" -gt 0 ]]; then
    echo "build-error:a test reported flaky although retries were 0"
  elif [[ $((passed + failed)) -eq 0 ]]; then
    echo "build-error:no test ran (compile error, webServer failure, or no match)"
  elif [[ $((passed + failed)) -gt 1 ]]; then
    echo "build-error:selected $((passed + failed)) tests (all projects count); a proof selects exactly one — pin --project"
  elif [[ "$failed" -eq 1 && "$rc" -ne 0 ]]; then
    echo "fail"
  elif [[ "$passed" -eq 1 && "$rc" -eq 0 ]]; then
    echo "pass"
  else
    echo "build-error:playwright exit $rc does not match its summary"
  fi
}
