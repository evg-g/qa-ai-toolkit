# shellcheck shell=bash
# pytest adapter. Isolation: the marker expression must be `agent_trusted` or start with
# `agent_trusted and `. TEST_ID is a -k name, or a node id (path::test) when it has "::".

adapter_build_cmd() {
  local marker="agent_trusted" a i=0 rest=()
  local n=${#EXTRA_ARGS[@]}
  while [[ $i -lt $n ]]; do
    a="${EXTRA_ARGS[$i]}"
    case "$a" in
      -m)
        marker="${EXTRA_ARGS[$((i + 1))]:-}"
        i=$((i + 2))
        continue
        ;;
      -m*) marker="${a#-m}" ;;
      -k | -k* | --lf | --last-failed | --ff | --sw | --stepwise | --reruns* | --count*)
        echo "pytest adapter: '$a' is not allowed; the adapter owns test selection and retries" >&2
        return 1
        ;;
      *) rest+=("$a") ;;
    esac
    i=$((i + 1))
  done
  if [[ "$marker" != "agent_trusted" && "$marker" != "agent_trusted and "* ]]; then
    echo "pytest adapter: marker '$marker' must be 'agent_trusted' or start with 'agent_trusted and '" >&2
    return 1
  fi
  CMD=(${PREFIX[@]+"${PREFIX[@]}"} pytest -q -p no:cacheprovider -m "$marker")
  if [[ "$TEST_ID" == *"::"* ]]; then
    CMD+=("$TEST_ID")
  else
    CMD+=(${LOCATION:+"$LOCATION"} -k "$TEST_ID")
  fi
  CMD+=(${rest[@]+"${rest[@]}"})
}

adapter_classify() {
  local rc="$1" out="$2" summary passed failed errors
  if grep -qE 'Cannot connect to the Docker daemon|docker\.errors\.DockerException|Error while fetching server API version|Is the docker daemon running' "$out"; then
    echo "infra:docker is not reachable"
    return
  fi
  case "$rc" in
    5) echo "build-error:selected no test (pytest exit 5)"; return ;;
    2 | 3 | 4) echo "build-error:pytest exit $rc (interrupted, internal or usage error)"; return ;;
  esac
  summary="$(grep -E '[0-9]+ (passed|failed|errors?|deselected|skipped)' "$out" | tail -n 1)"
  passed="$(sed -nE 's/(^|.*[^0-9])([0-9]+) passed.*/\2/p' <<<"$summary")"
  failed="$(sed -nE 's/(^|.*[^0-9])([0-9]+) failed.*/\2/p' <<<"$summary")"
  errors="$(sed -nE 's/(^|.*[^0-9])([0-9]+) errors?.*/\2/p' <<<"$summary")"
  passed="${passed:-0}" failed="${failed:-0}" errors="${errors:-0}"
  if [[ "$errors" -gt 0 ]]; then
    echo "build-error:$errors setup/collection error(s); a test that did not run is not a red"
  elif [[ $((passed + failed)) -eq 0 ]]; then
    echo "build-error:selected no test"
  elif [[ $((passed + failed)) -gt 1 ]]; then
    echo "build-error:selected $((passed + failed)) tests; a proof selects exactly one"
  elif [[ "$failed" -eq 1 && "$rc" -eq 1 ]]; then
    echo "fail"
  elif [[ "$passed" -eq 1 && "$rc" -eq 0 ]]; then
    echo "pass"
  else
    echo "build-error:pytest exit $rc does not match its summary ($summary)"
  fi
}
