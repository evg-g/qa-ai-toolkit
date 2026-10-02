# shellcheck shell=bash
# Vitest adapter. Isolation: the adapter builds the only -t pattern, and it requires both the
# @agent-trusted tag and the test name. Retries are forced to 0.
# Note: Vitest in jsdom proves only what is in the DOM. Bind it to [logic], not [component]/[ui].

_vt_regex_escape() {
  printf '%s' "$1" | sed -e 's/[][\\.^$*+?(){}|\/]/\\&/g'
}

adapter_build_cmd() {
  local a
  for a in ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}; do
    case "$a" in
      -t | -t* | --testNamePattern* | --retry* | --changed* | --passWithNoTests | --allowOnly)
        echo "vitest adapter: '$a' is not allowed; the adapter owns selection and retries" >&2
        return 1
        ;;
    esac
  done
  local prefix=(${PREFIX[@]+"${PREFIX[@]}"})
  [[ ${#prefix[@]} -gt 0 ]] || prefix=(npx)
  CMD=("${prefix[@]}" vitest run ${LOCATION:+"$LOCATION"}
    -t "(?=.*@agent-trusted)(?=.*$(_vt_regex_escape "$TEST_ID"))"
    --retry=0 --reporter=default
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"})
}

adapter_classify() {
  local rc="$1" out="$2" line passed failed
  line="$(grep -E '^ *Tests +' "$out" | tail -n 1)"
  if [[ -z "$line" ]]; then
    if grep -qE 'No test files found' "$out"; then
      echo "build-error:selected no test file"
    else
      echo "build-error:no test summary (compile or config error)"
    fi
    return
  fi
  passed="$(sed -nE 's/.*[^0-9]([0-9]+) passed.*/\1/p' <<<"$line")"
  failed="$(sed -nE 's/.*[^0-9]([0-9]+) failed.*/\1/p' <<<"$line")"
  passed="${passed:-0}" failed="${failed:-0}"
  if grep -qE '^ *Test Files +.*[0-9]+ failed' "$out" && [[ "$failed" -eq 0 ]]; then
    echo "build-error:a test file failed to load"
  elif [[ $((passed + failed)) -eq 0 ]]; then
    echo "build-error:selected no test (is the name tagged @agent-trusted?)"
  elif [[ $((passed + failed)) -gt 1 ]]; then
    echo "build-error:selected $((passed + failed)) tests; a proof selects exactly one"
  elif [[ "$failed" -eq 1 && "$rc" -ne 0 ]]; then
    echo "fail"
  elif [[ "$passed" -eq 1 && "$rc" -eq 0 ]]; then
    echo "pass"
  else
    echo "build-error:vitest exit $rc does not match its summary ($line)"
  fi
}
