#!/usr/bin/env bash
#
# Two real connections against the synthetic LOCAL stack, for the race Codex
# raised in its C–F review (2026-09-27): a finished job is cancelled while its
# wheel line writes to the bike's ficha what it installed.
#
#   connection A (hold)  cancels the job holding its row `for update`, as
#                        transition_mechanic_job_status does, for 15 seconds;
#   connection B (race)  starts meanwhile and calls
#                        patch_bike_technical_facts_v1 with source
#                        `job_completion` for the job's Enrayado line (28H).
#
# B must come back with «Installed parts change the bicycle only when the job
# is finished» and leave the ficha at 32H with no receipt: since
# 20260928010000 it takes the job `for share` before the bike, waits for A and
# sees the job cancelled.
#
# With the body of 20260927050000 (status read without a lock) B waited on
# the foreign-key check of its receipt, then wrote 28H anyway: CANCELADO, 28H,
# one receipt. That run is the evidence the lock was needed.
#
# A control run afterwards finishes the job again and the same line writes its
# 28H, so a refusal can never pass for a broken fixture. Local only; never a
# hosted project.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
query="$here/query.sh"
probes="$here/../../supabase/manual_checks/probes"
tmp_dir="$here/../../.tmp/db"
mkdir -p "$tmp_dir"
hold_log="$tmp_dir/bike-fact-lock-hold.log"
race_log="$tmp_dir/bike-fact-lock-race.log"

for file in bike_fact_lock_seed bike_fact_lock_hold bike_fact_lock_race \
  bike_fact_lock_readback bike_fact_lock_reopen bike_fact_lock_cleanup; do
  [[ -f "$probes/$file.sql" ]] || {
    echo "probe missing: $file.sql" >&2
    exit 2
  }
done

echo "== 1/5 seeding a finished job with its wheel line (local)"
bash "$query" local --file "$probes/bike_fact_lock_cleanup.sql" >/dev/null
bash "$query" local --file "$probes/bike_fact_lock_seed.sql" >/dev/null

echo "== 2/5 cancelling the job and holding its row"
bash "$query" local --file "$probes/bike_fact_lock_hold.sql" >"$hold_log" 2>&1 &
hold_pid=$!
sleep 3

echo "== 3/5 the wheel line writes its 28H while the job is being cancelled"
status=0
bash "$query" local --file "$probes/bike_fact_lock_race.sql" >"$race_log" 2>&1 ||
  status=$?
wait "$hold_pid" || {
  echo "FAIL: the cancellation did not commit. Log: $hold_log" >&2
  exit 1
}

if [[ "$status" -eq 0 ]] && ! grep -qF 'ERROR' "$race_log"; then
  echo "FAIL: a cancelled job changed the bike; the job status was read" >&2
  echo "without a lock. Log: $race_log" >&2
  exit 1
fi
if ! grep -qF 'Installed parts change the bicycle only when the job is finished' \
  "$race_log"; then
  echo "FAIL: the write failed for another reason, which proves nothing" >&2
  echo "about the lock. Log: $race_log" >&2
  exit 1
fi

echo "== 4/5 reading back what the ficha kept"
readback="$(bash "$query" local --format csv \
  --file "$probes/bike_fact_lock_readback.sql" | tail -1)"
if [[ "$readback" != "CANCELADO,32,0" ]]; then
  echo "FAIL: expected the cancelled job, 32H and no receipt; read back" >&2
  echo "$readback" >&2
  exit 1
fi

echo "== 5/5 control: the job finished again, the same line writes"
bash "$query" local --file "$probes/bike_fact_lock_reopen.sql" >/dev/null
bash "$query" local --file "$probes/bike_fact_lock_race.sql" >/dev/null
readback="$(bash "$query" local --format csv \
  --file "$probes/bike_fact_lock_readback.sql" | tail -1)"
if [[ "$readback" != "FINALIZADO,28,1" ]]; then
  echo "FAIL: the control run did not write the installed 28H; read back" >&2
  echo "$readback" >&2
  exit 1
fi

echo "== cleaning the fixture out of the local stack"
bash "$query" local --file "$probes/bike_fact_lock_cleanup.sql" >/dev/null

echo "PASS: the installed write waits for the cancellation, sees the job"
echo "cancelled and refuses; finished again, the same line writes its 28H."
