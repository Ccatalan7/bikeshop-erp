#!/usr/bin/env bash
#
# Two real connections against the synthetic LOCAL stack, for the race of
# 20260928120000: two jobs of the same bike finish at the same time, one with
# a Shimano HG cassette and one with a threaded freewheel, and the bike's
# ficha does not know its driver yet.
#
#   connection A (hold)  finishes job A inside a transaction: the applier
#                        takes the bike and its ficha and declares Shimano HG;
#                        A holds that for 15 seconds before committing;
#   connection B (race)  starts meanwhile and finishes job B.
#
# B cannot read the ficha while A holds it. The transition command waits at
# most 750 ms for the bike (`lock_timeout`, 20260928060000), so B reports the
# freewheel as rejected with 55P03 in its response, writes nothing, and job B
# still finishes. Its retry notice does not reach the bike's history either:
# that insert also needs the bike's row, and the notice is best effort by
# design (20260928060000: the response carries it and the next call
# recomputes it). The retry after A committed (saving job B) meets the
# Shimano HG that A declared and reports the freewheel as incompatible. End
# state: one driver (Shimano HG, from job_completion), one receipt that wrote
# it, one incompatible notice, no retry notice.
#
# If B could read the ficha without the bike's lock it would see no driver
# too, declare the freewheel, and whichever committed last would stay with
# no notice.
#
# Local only; never a hosted project. The product reader is replaced for the
# fixture and put back by the cleanup, which also runs first.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
query="$here/query.sh"
probes="$here/../../supabase/manual_checks/probes"
tmp_dir="$here/../../.tmp/db"
mkdir -p "$tmp_dir"
hold_log="$tmp_dir/rear-cogs-race-hold.log"
race_log="$tmp_dir/rear-cogs-race-race.log"
retry_log="$tmp_dir/rear-cogs-race-retry.log"

for file in rear_cogs_race_seed rear_cogs_race_hold rear_cogs_race_race \
  rear_cogs_race_retry rear_cogs_race_readback rear_cogs_race_cleanup; do
  [[ -f "$probes/$file.sql" ]] || {
    echo "probe missing: $file.sql" >&2
    exit 2
  }
done

cleanup() {
  bash "$query" local --format csv --file "$probes/rear_cogs_race_cleanup.sql" 2>/dev/null | tail -1
}
fail() {
  echo "FAIL: $*" >&2
  cleanup >/dev/null
  exit 1
}

echo "== 1/5 seeding two open jobs of the same bike (local)"
cleanup >/dev/null
bash "$query" local --file "$probes/rear_cogs_race_seed.sql" >/dev/null 2>&1

echo "== 2/5 job A finishes and holds the bike"
bash "$query" local --file "$probes/rear_cogs_race_hold.sql" >"$hold_log" 2>&1 &
hold_pid=$!
sleep 3

echo "== 3/5 job B finishes while A holds the bike"
bash "$query" local --file "$probes/rear_cogs_race_race.sql" >"$race_log" 2>&1 ||
  fail "job B did not finish. Log: $race_log"
if kill -0 "$hold_pid" 2>/dev/null; then
  a_still_holding=yes
else
  a_still_holding=no
fi
wait "$hold_pid" || fail "job A did not commit. Log: $hold_log"
[[ "$a_still_holding" == yes ]] ||
  fail "job A committed before B finished, so the run proves nothing about the lock"
grep -qF '"reason": "rejected"' "$race_log" && grep -qF '55P03' "$race_log" ||
  fail "job B was not held off the bike (expected rejected, 55P03). Log: $race_log"

echo "== 4/5 retrying job B after A committed"
bash "$query" local --file "$probes/rear_cogs_race_retry.sql" >"$retry_log" 2>&1 ||
  fail "the retry failed. Log: $retry_log"
grep -qF '"reason": "incompatible"' "$retry_log" ||
  fail "the retry did not report the freewheel as incompatible. Log: $retry_log"

echo "== 5/5 reading back what the ficha kept"
readback="$(bash "$query" local --format csv \
  --file "$probes/rear_cogs_race_readback.sql" | tail -1)"
restored="$(cleanup)"
[[ "$readback" == "shimano_hg,job_completion,1,1,0,FINALIZADO" ]] ||
  fail "expected Shimano HG from job A, one writing receipt, one incompatible notice, no retry notice and job B finished; read back $readback"
[[ "$restored" == "0,t" ]] ||
  fail "the cleanup did not restore the product reader or left the fixture: $restored"

echo "PASS: job B cannot read the ficha while A holds the bike; it writes"
echo "nothing and is retried; the retry meets the Shimano HG from job A and"
echo "reports the freewheel as incompatible. One driver, one receipt."
