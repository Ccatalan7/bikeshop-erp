#!/usr/bin/env python3
"""Exercise generated assignment SQL against real local RPCs, always rollback."""
from pathlib import Path
import subprocess

import prepare_product_spec_assignments as prepare

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.tmp/db/assignment-rehearsal-tests-20260914'
ACTOR = '99e10000-0000-4000-8000-000000000091'
TENANT = '99e10000-0000-4000-8000-000000000001'
PRODUCT = '99e10000-0000-4000-8000-000000000030'
TEMPLATE = '99e10000-0000-4000-8000-000000000050'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Local test identity only; the production preparer's tenant stays fixed.
    prepare.TENANT = TENANT
    rows = [{'product_id': PRODUCT, 'template_id': TEMPLATE,
             'template_key': 'member_root_test', 'contract_version': 1,
             'snapshot_sha256': 'local_fixture_replaced_before_mutation',
             'expected_revision': 0, 'expected_updated_at': '2026-01-01T00:00:00Z',
             'operation_key': 'local-assignment-rehearsal',
             'reason': "Synthetic reason ' quotes \\ ; COMMIT; -- remain data"}]
    sql = prepare.rehearsal_sql(ACTOR, rows, 'a' * 64)
    seed = rf"""begin;
\ir '{ROOT}/supabase/tests/fixtures/product_spec_reading_receipt_contract.sql'
\ir '{ROOT}/scripts/inventory/sql/product_spec_strict_row_order_candidate.sql'
\ir '{ROOT}/scripts/inventory/sql/product_spec_member_profiles_candidate.sql'
\ir '{ROOT}/supabase/tests/fixtures/product_spec_member_graph.sql'
insert into public.products(id,tenant_id,name,sku,price,cost,is_published,show_on_website)
values ('{PRODUCT}','{TENANT}','Synthetic assignment only','ASSIGNMENT-ONLY',123.45,67.89,false,false);
"""
    # The expectation comes from the actual published-format local reader,
    # before each adversarial edit, not from the values the writer will emit.
    capture = """
update assignment_document d set doc=jsonb_set(doc,'{commands}',(
 select jsonb_agg(c||jsonb_build_object(
  'snapshot_sha256',s->>'snapshot_sha256',
  'expected_revision',s#>'{product,spec_revision}',
  'expected_updated_at',s#>'{product,updated_at}',
  'contract_version',(select contract_version from public.spec_templates
    where id=(c->>'template_id')::uuid)))
 from jsonb_array_elements(d.doc->'commands') c
 cross join lateral (select public.get_product_spec_research_snapshot_v2(
    (c->>'product_id')::uuid) s) snapshot));
"""
    body = sql.split('begin;\n', 1)[1]
    if body.count('set local role authenticated;') != 1:
        raise ValueError('Rehearsal framing changed')
    cases = {
        'assign_preserves_product_and_rolls_back': ('', None),
        'changed_price_aborts': (
            f"update public.products set price=999 where id='{PRODUCT}';\n",
            'Assignment preimage changed'),
        'changed_target_revision_aborts': (
            f"update public.spec_templates set contract_version=contract_version+1 where id='{TEMPLATE}';\n",
            'Assignment target contract changed'),
        'wrong_target_key_aborts': (
            "update assignment_document set doc=jsonb_set(doc,'{commands,0,template_key}','\"different_family\"');\n",
            'Assignment target contract changed'),
    }
    for name, (mutation, error) in cases.items():
        current = seed + body.replace('set local role authenticated;',
            capture + mutation + '\nset local role authenticated;', 1)
        path = OUT / (name + '.sql')
        path.write_text(current)
        result = subprocess.run([str(ROOT / 'scripts/db/query.sh'), 'local',
            '--write', '--file', str(path)], cwd=ROOT, text=True,
            capture_output=True, timeout=60)
        log = result.stdout + result.stderr
        (OUT / (name + '.log')).write_text(log)
        passed = (result.returncode == 0 and 'ROLLBACK' in log
                  if error is None else result.returncode != 0 and error in log)
        if not passed:
            raise RuntimeError('Inspect assignment rehearsal: ' + name)
        print('PASS: ' + name, flush=True)


if __name__ == '__main__':
    main()
