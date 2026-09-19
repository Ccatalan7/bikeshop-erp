#!/usr/bin/env bash
#
# Two real connections against the synthetic LOCAL stack, for the race
# Codex has asked about since its first pass: a bank review pays a payroll
# line while Nómina records a payment on the same line.
#
#   connection A (hold)  confirms the week, registers $20.000 through the
#                        canonical Nómina command and holds its settlement
#                        lock for five seconds before committing;
#   connection B (race)  starts a second later and applies a reconciliation
#                        that was built when the week owed $100.000.
#
# B must come back as `bank_reconciliation_payroll_line_changed` and leave
# nothing behind: it waits for A's lock, reads the balance A left and sees
# that the week it reviewed is not the week it is paying.
#
# Without that lock B reads the old balance, passes its own check and only
# Nómina's optimistic version stops it, from inside the canonical command
# and after the review already acted — `payroll_payment_version_conflict`.
# No money is paid twice either way; what is lost is the review's own
# protection, which is why this probe asserts the exact error.
#
# A control run afterwards pays the balance A left, so a refusal can never
# pass for a broken fixture. Local only; never a hosted project.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
query="$here/query.sh"
probes="$here/../../supabase/manual_checks/probes"
tmp_dir="$here/../../.tmp/db"
mkdir -p "$tmp_dir"
hold_log="$tmp_dir/payroll-lock-hold.log"
race_log="$tmp_dir/payroll-lock-race.log"

for file in payroll_lock_seed payroll_lock_hold payroll_lock_race \
  payroll_lock_readback; do
  [[ -f "$probes/$file.sql" ]] || {
    echo "probe missing: $file.sql" >&2
    exit 2
  }
done

echo "== 1/5 seeding the week and the statement (local)"
bash "$query" local --file "$probes/payroll_lock_seed.sql" >/dev/null

echo "== 2/5 Nómina pays \$20.000 and holds its lock"
bash "$query" local --file "$probes/payroll_lock_hold.sql" >"$hold_log" 2>&1 &
hold_pid=$!
sleep 1

echo "== 3/5 the review applies its \$40.000 against the old balance"
status=0
bash "$query" local --file "$probes/payroll_lock_race.sql" >"$race_log" 2>&1 ||
  status=$?
wait "$hold_pid" || {
  echo "FAIL: Nómina's own payment did not commit. Log: $hold_log" >&2
  exit 1
}

if [[ "$status" -eq 0 ]]; then
  echo "FAIL: the review paid a week that changed under it; the balance was" >&2
  echo "read before the settlement lock. Log: $race_log" >&2
  exit 1
fi
if ! grep -qF 'bank_reconciliation_payroll_line_changed' "$race_log"; then
  echo "FAIL: the review failed for another reason, which proves nothing" >&2
  echo "about the lock. Log: $race_log" >&2
  exit 1
fi

echo "== 4/5 reading back what the week kept"
readback="$(bash "$query" local --format csv \
  --file "$probes/payroll_lock_readback.sql" | tail -1)"
if [[ "$readback" != "1,20000.00,0,1" ]]; then
  echo "FAIL: expected only Nómina's payment, no decision and just the" >&2
  echo "import's own operation; read back" >&2
  echo "$readback" >&2
  exit 1
fi

echo "== 5/5 control: the same review, against the balance A left"
control="$(sed 's/'\''expected_amount'\'', 100000/'\''expected_amount'\'', 80000/;
  s/payroll-lock-probe:review-pays/payroll-lock-probe:review-pays-control/' \
  "$probes/payroll_lock_race.sql")"
control_file="$tmp_dir/payroll-lock-control.sql"
printf '%s\n' "$control" >"$control_file"
bash "$query" local --file "$control_file" >/dev/null
readback="$(bash "$query" local --format csv \
  --file "$probes/payroll_lock_readback.sql" | tail -1)"
if [[ "$readback" != "2,60000.00,1,2" ]]; then
  echo "FAIL: the control run did not pay the balance Nómina left; read back" >&2
  echo "$readback" >&2
  exit 1
fi

echo "== cleaning the fixture out of the local stack"
bash "$query" local --file "$probes/payroll_lock_cleanup.sql" >/dev/null

echo "PASS: the review waits for Nómina's lock, sees the week it changed and"
echo "refuses; with the balance it left, the same payment goes through."
