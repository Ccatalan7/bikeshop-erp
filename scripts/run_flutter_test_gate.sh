#!/bin/bash

set -euo pipefail

flutter_bin="${1:-flutter}"
# Reparto opcional de la suite entre varios corredores. Sin estas variables el
# script corre todo, que es lo que hace un desarrollador en su máquina; el gate
# de CI las usa para partir ~9 minutos de pruebas en trabajos paralelos.
shard_index="${FLUTTER_TEST_SHARD_INDEX:-}"
shard_total="${FLUTTER_TEST_SHARD_TOTAL:-}"
shard_args=()
shard_label='la suite completa'
if [[ -n "$shard_total" ]]; then
  if [[ ! "$shard_total" =~ ^[0-9]+$ ]] || (( shard_total < 1 )); then
    echo "FLUTTER_TEST_SHARD_TOTAL invalido: $shard_total" >&2
    exit 64
  fi
  if [[ ! "$shard_index" =~ ^[0-9]+$ ]] || (( shard_index >= shard_total )); then
    echo "FLUTTER_TEST_SHARD_INDEX invalido: $shard_index de $shard_total" >&2
    exit 64
  fi
  shard_args=(--total-shards "$shard_total" --shard-index "$shard_index")
  shard_label="la parte $((shard_index + 1)) de $shard_total"
fi
test_log="$(mktemp "${TMPDIR:-/tmp}/vinabike-flutter-test.XXXXXX")"
diagnostics="$(mktemp "${TMPDIR:-/tmp}/vinabike-flutter-test-diagnostics.XXXXXX")"

trap 'rm -f -- "$test_log" "$diagnostics"' EXIT

printf '\n[flutter-test-gate] Corriendo %s de pruebas Flutter\n' "$shard_label"

set +e
"$flutter_bin" test --machine "${shard_args[@]+"${shard_args[@]}"}" >"$test_log" 2>&1
test_status=$?
set -e

if [[ "$test_status" -eq 0 ]]; then
  if [[ -z "$shard_total" || "$shard_index" == "0" ]]; then
    printf '\n[flutter-test-gate] Running browser-only Web Locks tests in Chrome\n'
    "$flutter_bin" test --platform chrome test/unit/cart_lock_web_test.dart
  fi
  echo '[flutter-test-gate] All Flutter and browser-only tests passed.'
  exit 0
fi

jq -Rrs '
  [
    split("\n")[]
    | fromjson?
    | if type == "array" then .[] else . end
    | select(type == "object")
  ] as $events
  | (reduce ($events[] | select(.type == "testStart")) as $event
      ({}; .[($event.test.id | tostring)] = $event.test)) as $tests
  | [
      $events[]
      | select(.type == "error" and (.isFailure // true))
    ]
  | unique_by(.testID)
  | .[]
  | . as $failure
  | ($tests[($failure.testID | tostring)] // {}) as $test
  | (($test.root_url // $test.url // "unknown") | sub("^file://"; "")) as $path
  | ([
      $events[]
      | select(.type == "print")
      | select((.testID | tostring) == ($failure.testID | tostring))
      | select((.message // "") | contains("EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK"))
      | .message
    ] | last // "") as $framework_exception
  | (if (($failure.error // "") | startswith("Test failed. See exception logs above"))
      and $framework_exception != ""
    then $framework_exception
    else ($failure.error // "Unknown failure")
    end) as $diagnostic_source
  | ($diagnostic_source
      | gsub("═+╡?"; " ")
      | gsub("[\\r\\n\\t ]+"; " ")
      | .[0:1200]) as $expected
  | ((($failure.stackTrace // "") + "\n" + $framework_exception)
      | split("\n")
      | map(select(test("(^|/)test/")))
      | .[0] // "") as $location
  | "FAILED: \($test.name // "Unknown test")\n"
    + "  File: \($path):\($test.root_line // $test.line // "?"):\($test.root_column // $test.column // "?")\n"
    + "  \($expected)"
    + (if $location == "" then "" else "\n  At: \($location)" end)
' "$test_log" >"$diagnostics" || true

printf '\n[flutter-test-gate] Flutter tests failed. Exact failure summary:\n\n' >&2
if [[ -s "$diagnostics" ]]; then
  cat "$diagnostics" >&2
else
  echo 'The machine-readable result could not be summarized; showing the final test output.' >&2
  tail -n 120 "$test_log" >&2
fi
printf '\n[flutter-test-gate] Nothing was published. Fix the failure above and run the task again.\n' >&2

exit "$test_status"
