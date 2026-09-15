#!/usr/bin/env python3
"""Prepare one forward writer correction from its reviewed production body.

No SQL execution, template activation or observation rewrite. The candidate
must already pass the rollback test before its exact body is packaged here.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SQL = ROOT / 'scripts/inventory/sql'
SIGNATURE = 'public.spec_write_scope_payload_internal_v1(uuid,uuid,jsonb,text,text)'


def prepare(version):
    if not re.fullmatch(r'20\d{12}', version):
        raise ValueError('Expected a migration timestamp')
    source = json.loads((SQL / 'product_spec_legacy_roundtrip_predecessor.json').read_text())
    if source['md5'] != '1ec9a61aa2a4be4093be590af2f1a610' or \
            hashlib.md5(source['definition'].encode()).hexdigest() != source['md5']:
        raise ValueError('Unreviewed predecessor')
    candidate = (SQL / 'product_spec_legacy_roundtrip_candidate.sql').read_text()
    start = candidate.index('CREATE OR REPLACE FUNCTION')
    end = candidate.index('end $function$;', start) + len('end $function$')
    definition = candidate[start:end] + '\n'
    post_hash = hashlib.md5(definition.encode()).hexdigest()
    if post_hash != 'cf4c62043ce36a3f62af020fade60417':
        raise ValueError('Candidate differs from the tested typed writer')
    name = f'{version}_product_spec_legacy_typed_roundtrip.sql'
    migration = ROOT / 'supabase/migrations' / name
    verification = ROOT / 'supabase/manual_checks/verification' / name
    if migration.exists() or verification.exists():
        raise ValueError('Refusing to overwrite a prepared/applied migration')
    tables = ['products', 'spec_facts', 'spec_fact_values', 'spec_fact_readings',
              'product_spec_values', 'product_spec_member_profiles',
              'product_spec_member_profile_events', 'product_spec_save_receipts']
    fingerprint = 'jsonb_build_object(' + ','.join(
        f"'{table}',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.{table} x)"
        for table in tables) + ')'
    migration.write_text(
        '-- Preserve identical retired observations across exact numeric transports.\n'
        '-- Changes only the existing writer body; all data and ACLs stay exact.\n'
        'begin;\nset local lock_timeout=\'5s\';\nset local statement_timeout=\'120s\';\n'
        'lock table ' + ','.join('public.' + t for t in tables) + ' in share row exclusive mode;\n'
        f'create temp table legacy_roundtrip_before on commit drop as select {fingerprint} value;\n'
        + candidate + f'\ndo $data$ begin\n if (select value from legacy_roundtrip_before) is distinct from {fingerprint} then\n'
        "  raise exception 'Legacy roundtrip rollout changed observations';\n end if;\nend $data$;\n"
        "notify pgrst,'reload schema';\ncommit;\n")
    verification.write_text(
        '-- Exact read-back of the only function replaced by this forward.\n'
        'select 1 / case when exists(select 1 from pg_proc where\n'
        f" oid='{SIGNATURE}'::regprocedure and md5(pg_get_functiondef(oid))='{post_hash}'\n"
        " and pg_get_userbyid(proowner)='postgres' and prosecdef and provolatile='v'\n"
        " and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[]\n"
        " and proacl=array['postgres=X/postgres','service_role=X/postgres']::aclitem[])\n"
        ' then 1 else 0 end as typed_legacy_writer_matches;\n')
    print(json.dumps({'migration': str(migration.relative_to(ROOT)),
        'verification': str(verification.relative_to(ROOT)),
        'sha256': hashlib.sha256(migration.read_bytes()).hexdigest(),
        'function_md5': post_hash}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    prepare(parser.parse_args().version)
