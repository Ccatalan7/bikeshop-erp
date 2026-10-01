#!/usr/bin/env bash
#
# Two real connections against the synthetic LOCAL stack, for the race of
# 20260929010000: two windows (or a window and the outbox resume) send the
# same job creation at the same time.
#
#   connection A (hold)  creates the job inside a transaction and holds it
#                        15 seconds before committing;
#   connection B (race)  starts meanwhile and sends the same creation (same
#                        key, same content).
#
# `create_mechanic_job_v1` takes an advisory lock per job id before reading
# its receipt, so B waits for A, then finds A's receipt and returns it as a
# replay (`replayed: true`) without writing. End state: one job, one
# «Trabajo creado» event, one receipt.
#
# Without the lock B would not see A's uncommitted receipt, would try to
# insert the same job, and would fail on the primary key (23505) once A
# committed: the window would show an error for a creation that happened.
#
# Local only; never a hosted project. The cleanup also runs first.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
query="$here/query.sh"
probes="$here/../../supabase/manual_checks/probes"
tmp_dir="$here/../../.tmp/db"
mkdir -p "$tmp_dir"
hold_log="$tmp_dir/job-creation-race-hold.log"
race_log="$tmp_dir/job-creation-race-race.log"

for file in job_creation_race_seed job_creation_race_hold \
  job_creation_race_race job_creation_race_readback \
  job_creation_race_cleanup; do
  [[ -f "$probes/$file.sql" ]] || {
    echo "probe missing: $file.sql" >&2
    exit 2
  }
done

cleanup() {
  bash "$query" local --format csv --file "$probes/job_creation_race_cleanup.sql" 2>/dev/null | tail -1
}
fail() {
  echo "FAIL: $*" >&2
  cleanup >/dev/null
  exit 1
}

echo "== 1/4 seeding a workshop, an employee and a bike (local)"
cleanup >/dev/null
bash "$query" local --file "$probes/job_creation_race_seed.sql" >/dev/null 2>&1

echo "== 2/4 window A creates the job and holds it"
bash "$query" local --file "$probes/job_creation_race_hold.sql" >"$hold_log" 2>&1 &
hold_pid=$!
sleep 3

echo "== 3/4 window B sends the same creation while A holds it"
bash "$query" local --file "$probes/job_creation_race_race.sql" >"$race_log" 2>&1 ||
  fail "window B failed. Log: $race_log"
if kill -0 "$hold_pid" 2>/dev/null; then
  a_still_holding=yes
else
  a_still_holding=no
fi
wait "$hold_pid" || fail "window A did not commit. Log: $hold_log"
grep -qF 'A:false' "$hold_log" ||
  fail "window A did not create the job. Log: $hold_log"
grep -qF 'B:true' "$race_log" ||
  fail "window B did not get A's receipt as a replay. Log: $race_log"
# B answers only after A commits, so A has usually just finished when B
# returns; what proves the overlap is that B sent while A was holding.
b_sent="$(grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}' "$race_log" | head -1)"
a_committed="$(grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}' "$hold_log" | tail -1)"
[[ -n "$b_sent" && -n "$a_committed" && "$b_sent" < "$a_committed" ]] ||
  fail "B sent at $b_sent and A committed at $a_committed: the run proves nothing about the lock (A still holding when B returned: $a_still_holding)"

echo "== 4/4 reading back jobs, events and receipts"
readback="$(bash "$query" local --format csv \
  --file "$probes/job_creation_race_readback.sql" | tail -1)"
left_over="$(cleanup)"
[[ "$readback" == "1,1,1" ]] ||
  fail "expected one job, one «Trabajo creado» and one receipt; read back $readback"
[[ "$left_over" == "0" ]] ||
  fail "the cleanup left $left_over rows of the probe tenant"

echo "PASS: window B sent the same creation while A held it, waited, and got"
echo "A's receipt as a replay. One job, one «Trabajo creado», one receipt."
echo "B sent at $b_sent, A committed at $a_committed."
