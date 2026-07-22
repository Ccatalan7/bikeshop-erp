#!/bin/bash

set -euo pipefail

flutter_bin="${1:-flutter}"
test_log="$(mktemp "${TMPDIR:-/tmp}/vinabike-flutter-test.XXXXXX")"
diagnostics="$(mktemp "${TMPDIR:-/tmp}/vinabike-flutter-test-diagnostics.XXXXXX")"

trap 'rm -f -- "$test_log" "$diagnostics"' EXIT

printf '\n[flutter-test-gate] Running the complete Flutter test suite\n'

set +e
"$flutter_bin" test --machine >"$test_log" 2>&1
test_status=$?
set -e

if [[ "$test_status" -eq 0 ]]; then
  echo '[flutter-test-gate] All Flutter tests passed.'
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
  | (($failure.error // "Unknown failure")
      | split("\n  Actual:")[0]
      | gsub("[\\r\\n\\t ]+"; " ")
      | .[0:600]) as $expected
  | (($failure.stackTrace // "")
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
