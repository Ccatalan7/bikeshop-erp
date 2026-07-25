#!/usr/bin/env python3
"""Query live Supabase DB to inspect current schema state."""
import os
import urllib.request
import urllib.parse
import json

KEY = os.environ.get('SUPABASE_SECRET_KEY', '').strip()
if not KEY:
    raise SystemExit(
        "Missing SUPABASE_SECRET_KEY in the process environment. "
        "Inject it from the documented OS credential store."
    )
BASE = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co'

def rest_get(path):
    req = urllib.request.Request(
        f'{BASE}/rest/v1/{path}',
        headers={
            'apikey': KEY,
            'Accept': 'application/json'
        }
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())

def rpc(func_name, params=None):
    data = json.dumps(params or {}).encode()
    req = urllib.request.Request(
        f'{BASE}/rest/v1/rpc/{func_name}',
        data=data,
        headers={
            'apikey': KEY,
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())

# 1. mechanic_jobs columns
print("\n" + "="*60)
print("MECHANIC_JOBS COLUMNS")
print("="*60)
rows = rest_get('mechanic_jobs?select=*&limit=0')
# Use a different approach - query via a known RPC or use the header
# Actually with limit=0 we won't get column info, let's try a single row
try:
    rows = rest_get('mechanic_jobs?select=*&limit=1')
    if rows:
        for col in rows[0].keys():
            print(f"  {col}")
    else:
        print("  (no rows found - will check via pg_catalog via RPC)")
except Exception as e:
    print(f"  Error: {e}")

# 2. Check if job_subjects table exists
print("\n" + "="*60)
print("CHECK: job_subjects table")
print("="*60)
try:
    rows = rest_get('job_subjects?limit=1')
    print("  EXISTS - rows:", rows)
except Exception as e:
    print(f"  NOT FOUND: {e}")

# 3. Check mechanic_jobs for job_type column (try select)
print("\n" + "="*60)
print("CHECK: job_type column exists on mechanic_jobs")
print("="*60)
try:
    rows = rest_get('mechanic_jobs?select=job_type&limit=1')
    print("  EXISTS:", rows)
except Exception as e:
    print(f"  NOT FOUND: {e}")

# 4. Check if service_profiles table exists (from migration file open in editor)
print("\n" + "="*60)
print("CHECK: service_profiles table")
print("="*60)
try:
    rows = rest_get('service_profiles?limit=3')
    print(f"  EXISTS - {len(rows)} rows found")
    if rows:
        print("  Sample:", list(rows[0].keys()))
except Exception as e:
    print(f"  NOT FOUND: {e}")

# 5. Check bikes table columns
print("\n" + "="*60)
print("BIKES TABLE - sample columns")
print("="*60)
try:
    rows = rest_get('bikes?select=*&limit=1')
    if rows:
        for col in rows[0].keys():
            print(f"  {col}")
    else:
        print("  (no rows - table exists but empty)")
        # Try without filter
        pass
except Exception as e:
    print(f"  Error: {e}")

# 6. Check triggers on mechanic_jobs
print("\n" + "="*60)
print("TRIGGERS on mechanic_jobs (via pg_trigger)")
print("="*60)
try:
    # This won't work via PostgREST directly, but let's try
    rows = rest_get('pg_trigger?select=tgname&limit=20')
    print("  Triggers:", rows)
except Exception as e:
    print(f"  Cannot query pg_trigger directly (expected): {e}")

print("\nDone!")
