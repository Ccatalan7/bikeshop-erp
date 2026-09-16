#!/usr/bin/env python3
"""Prepare the readiness receipt and its guarded SQL from two named artifacts.

The readiness row is what lets apply_product_spec_research_v1 write. It names,
by sha256, the global audit and the closure decision it rests on. This script
recomputes both hashes from the files, writes the receipt JSON the registrar
consumes (schema_version 1, project, tenant, id, both hashes, closed_at,
enabled) and a standalone SQL file for scripts/db/query.sh --write that
inserts the row only if the tenant has no readiness yet and reads it back.
It runs nothing itself.
"""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'
NAMESPACE = uuid.UUID('e95c6bbb-1fda-4c02-9e57-74f05b5a21bd')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True)
    parser.add_argument('--tenant-id', required=True)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--review', type=Path, required=True)
    parser.add_argument('--label', required=True, help='stable label, e.g. sanitation-closure-2026-09-16')
    parser.add_argument('--receipt', type=Path, required=True)
    parser.add_argument('--sql', type=Path, required=True)
    args = parser.parse_args()
    tenant = str(uuid.UUID(args.tenant_id))
    readiness_id = str(uuid.uuid5(NAMESPACE, 'readiness:' + args.project + ':' + tenant + ':' + args.label))
    closed_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    receipt = {'schema_version': 1, 'project': args.project, 'tenant_id': tenant, 'id': readiness_id,
               'audit_sha256': digest(args.audit), 'review_sha256': digest(args.review),
               'closed_at': closed_at, 'enabled': True}
    args.receipt.write_text(json.dumps(receipt, ensure_ascii=False, indent=1) + '\n')
    sql = f"""-- Readiness of the research applier for tenant {tenant}; label {args.label}.
-- audit {args.audit.name} sha256 {receipt['audit_sha256']}
-- review {args.review.name} sha256 {receipt['review_sha256']}
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $readiness$ begin
 if not exists(select 1 from public.tenants where id='{tenant}') then
  raise exception 'Tenant missing';
 end if;
 if exists(select 1 from public.product_spec_research_readiness where tenant_id='{tenant}' and id<>'{readiness_id}') then
  raise exception 'Another readiness row exists for this tenant; decide explicitly before adding one';
 end if;
 insert into public.product_spec_research_readiness(id,tenant_id,audit_sha256,review_sha256,closed_at,enabled)
 values('{readiness_id}','{tenant}','{receipt['audit_sha256']}','{receipt['review_sha256']}','{closed_at}',true)
 on conflict(id) do nothing;
end $readiness$;
select id,tenant_id,audit_sha256,review_sha256,closed_at,enabled from public.product_spec_research_readiness
 where id='{readiness_id}';
commit;
"""
    args.sql.write_text(sql)
    print(json.dumps({'readiness_id': readiness_id, 'closed_at': closed_at,
                      'audit_sha256': receipt['audit_sha256'], 'review_sha256': receipt['review_sha256'],
                      'receipt': str(args.receipt), 'sql': str(args.sql)}))


if __name__ == '__main__':
    main()
