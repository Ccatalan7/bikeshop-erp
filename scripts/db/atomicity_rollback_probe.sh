#!/usr/bin/env bash
#
# Reproducible atomicity proof for the transactional migration mechanism
# (Codex review 2026-07-30, PAYROLL_COMPLETION_PLAN.md F2.4/F2.5/F2.6).
#
# Both probes run through the EXACT deployment path
# (scripts/db/query.sh --write --file) against the synthetic LOCAL stack:
#   1. failure probe — a deliberate error BETWEEN two objects must abort with
#      a non-zero exit AND print the probe's own marker (so an infrastructure
#      failure can never masquerade as a passed rollback test), and a second
#      independent invocation must read back that nothing survived;
#   2. success control — the same transactional shape without the injected
#      failure must commit, survive a read-back, and be cleaned up.
# Never touches a hosted environment.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
query="$here/query.sh"
fail_probe="$here/probes/atomicity_rollback_probe.sql"
commit_probe="$here/probes/atomicity_commit_probe.sql"
[[ -f "$query" && -f "$fail_probe" && -f "$commit_probe" ]] || {
  echo "probe or query wrapper missing" >&2
  exit 2
}

marker='atomicity probe: deliberate failure between two objects'
tmp_dir="$here/../../.tmp/db"
mkdir -p "$tmp_dir"
fail_log="$tmp_dir/atomicity-probe-fail.log"

echo "== 1/4 deliberately failing probe through the deploy mechanism (local)"
status=0
bash "$query" local --write --file "$fail_probe" >"$fail_log" 2>&1 || status=$?
if [[ "$status" -eq 0 ]]; then
  echo "FAIL: the probe was expected to abort with a non-zero exit" >&2
  exit 1
fi
if ! grep -qF "$marker" "$fail_log"; then
  echo "FAIL: non-zero exit without the deliberate-failure marker; this is" >&2
  echo "an infrastructure failure, not a rollback proof. Log: $fail_log" >&2
  exit 1
fi
echo "   probe aborted with its own marker as required (exit $status)"

echo "== 2/4 second invocation: read back that nothing survived"
readback="$(bash "$query" local --format csv --sql \
  "select coalesce(to_regclass('public._payroll_atomicity_probe_first')::text, 'ABSENT') as first_object, coalesce(to_regclass('public._payroll_atomicity_probe_second')::text, 'ABSENT') as second_object")"
echo "$readback"
if ! printf '%s' "$readback" | grep -q 'ABSENT,ABSENT'; then
  echo "FAIL: a probe object survived the aborted transaction" >&2
  exit 1
fi

echo "== 3/4 success control: the same shape without the failure commits"
bash "$query" local --write --file "$commit_probe" >/dev/null
commit_readback="$(bash "$query" local --format csv --sql \
  "select coalesce(to_regclass('public._payroll_atomicity_probe_commit')::text, 'ABSENT') as committed_object")"
echo "$commit_readback"
if ! printf '%s' "$commit_readback" | grep -q '_payroll_atomicity_probe_commit'; then
  echo "FAIL: the success control did not commit its object" >&2
  exit 1
fi

echo "== 4/4 cleanup"
cleanup_sql="$tmp_dir/atomicity-probe-cleanup.sql"
cat >"$cleanup_sql" <<'SQL'
begin;
drop table if exists public._payroll_atomicity_probe_first;
drop table if exists public._payroll_atomicity_probe_second;
drop table if exists public._payroll_atomicity_probe_commit;
commit;
SQL
bash "$query" local --write --file "$cleanup_sql" >/dev/null
rm -f "$cleanup_sql"

echo "PASS: failure rolls back completely and the success control commits"
echo "through the exact query.sh deployment path"
