#!/usr/bin/env bash
# Installed public C2 RPC: backup-row and customer-writer contention must
# return a bounded, atomic refusal. Local synthetic namespace only.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
query="$root/scripts/db/query.sh"
probes="$root/supabase/manual_checks/probes"
logs="$root/.tmp/db"
hold_pid=''
cleanup() {
  if [[ -n "$hold_pid" ]]; then wait "$hold_pid" || true; hold_pid=''; fi
  bash "$query" local --write --file "$probes/restore_merge_race_cleanup.sql" > "$logs/restore-merge-race-cleanup.log" 2>&1
}
trap cleanup EXIT
cleanup
bash "$query" local --write --file "$probes/restore_merge_race_seed.sql" > "$logs/restore-merge-race-seed.log" 2>&1
for path in backup customer; do
  hold_log="$logs/restore-merge-race-hold-$path.log"
  call_log="$logs/restore-merge-race-$path-call.log"
  bash "$query" local --write --file "$probes/restore_merge_race_hold_$path.sql" > "$hold_log" 2>&1 &
  hold_pid=$!
  ready=false
  for round in {1..100}; do
    if rg -q 'HOLD_READY' "$hold_log"; then ready=true; break; fi
    if ! kill -0 "$hold_pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  [[ "$ready" == true ]] || { echo "No held lock: $hold_log" >&2; exit 1; }
  bash "$query" local --write --file "$probes/restore_merge_race_call.sql" > "$call_log" 2>&1
  kill -0 "$hold_pid" 2>/dev/null || { echo 'Holder ended before the refusal; no race proof' >&2; exit 1; }
  rg -q 'restore_merge_busy' "$call_log"
  wait "$hold_pid"
  hold_pid=''
  echo "PASS: $path lock refused recovery before the holder ended; no data or restore report written."
done
cleanup
trap - EXIT
rg -q 'cleanup_verified' "$logs/restore-merge-race-cleanup.log"
echo 'PASS: exact synthetic fixture removed.'
