#!/usr/bin/env python3
"""Prepare an assignment-only rollback rehearsal using the existing RPC.

No transport, production execution, schema changes or technical-fact filling.
The exact reviewed cohort must subsequently be approved before a commit is
prepared. Snapshot files and generated SQL are private local artifacts.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
from uuid import UUID, uuid5

from compile_non_drivetrain_publication import sql_json

NAMESPACE = UUID('e95c6bbb-1fda-4c02-9e57-74f05b5a21bd')
TENANT = '5443b130-cc28-45af-a420-cd500b288890'


def canonical_uuid(value):
    if not isinstance(value, str) or str(UUID(value)) != value:
        raise ValueError('Canonical UUID required')
    return value


def commands(proposal, proposal_sha):
    actor = canonical_uuid(proposal['actor_id'])
    if proposal.get('status') != 'assignment_only_review_pending':
        raise ValueError('This preparer only emits a noncommitting rehearsal')
    if not re.fullmatch('[0-9a-f]{64}', proposal_sha):
        raise ValueError('Exact proposal hash required')
    result, seen = [], set()
    for decision in proposal['decisions']:
        product_id = canonical_uuid(decision['product_id'])
        target = canonical_uuid(decision['target_template_id'])
        if product_id in seen:
            raise ValueError('Duplicate product in assignment cohort')
        seen.add(product_id)
        if decision.get('facts_patch') != {} or decision.get('identity_patch') != {}:
            raise ValueError('Assignment cannot include fact or identity edits')
        path = Path(decision['before_file'])
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != decision['before_file_sha256']:
            raise ValueError('Authenticated snapshot file changed')
        state = json.loads(data)
        product = state['product']
        if (type(product['spec_revision']) is not int or product['spec_revision'] < 0 or
                product.get('is_service') or product.get('product_type') == 'service' or
                product.get('is_set')):
            raise ValueError('This slice requires an ordinary physical product with an exact revision')
        if (state['read_schema_version'] != 2 or state['actor_id'] != actor or
                state['tenant_id'] != TENANT or product['id'] != product_id or
                product['tenant_id'] != TENANT or state['observations'] or
                state['member_profiles']['profiles'] or
                state['member_profiles']['archived_profiles'] or
                state['member_profile_events'] or
                state['editor']['template_id'] is not None or
                product.get('spec_template_id') is not None or
                product.get('spec_reference_id') is not None):
            raise ValueError('Only unassigned products without observations are in this slice')
        for key in ('name', 'sku', 'category_id', 'spec_revision', 'updated_at'):
            if product[key] != decision[key]:
                raise ValueError('Assignment evidence changed: ' + key)
        if state['snapshot_sha256'] != decision['before_snapshot_sha256']:
            raise ValueError('Snapshot identity changed')
        version = decision['reviewed_target_contract_version']
        if type(version) is not int or version < 1:
            raise ValueError('Exact target contract revision required')
        reason = decision['review_reason']
        if not isinstance(reason, str) or not reason.strip() or len(reason) > 2000:
            raise ValueError('Bounded review reason required')
        result.append({'product_id': product_id, 'template_id': target,
            'template_key': decision['target_template_key'], 'contract_version': version,
            'snapshot_sha256': state['snapshot_sha256'],
            'expected_revision': product['spec_revision'],
            'expected_updated_at': product['updated_at'], 'reason': reason,
            'operation_key': 'spec-assignment-' + str(uuid5(NAMESPACE,
                actor + ':' + proposal_sha + ':' + product_id))})
    if not result:
        raise ValueError('An exact nonempty cohort is required')
    return actor, sorted(result, key=lambda row: row['product_id'])


def rehearsal_sql(actor, rows, proposal_sha):
    document = {'actor_id': actor, 'tenant_id': TENANT,
                'proposal_sha256': proposal_sha, 'commands': rows}
    return f"""-- Assignment-only rehearsal. No commit and no technical-fact filling.
-- Run through scripts/db/query.sh in an isolated local fixture.
begin;
set local lock_timeout='5s';
create temp table assignment_document(doc jsonb) on commit drop;
insert into assignment_document values ({sql_json(document)});
create temp table assignment_receipts(product_id uuid, receipt jsonb) on commit drop;
grant select on assignment_document to authenticated;
grant insert,select on assignment_receipts to authenticated;
-- Exact locks before selecting the authenticated role; no new permanent grants.
select p.id from public.products p, assignment_document d
where p.tenant_id=(d.doc->>'tenant_id')::uuid and p.id in (
 select (c->>'product_id')::uuid from jsonb_array_elements(d.doc->'commands') c)
order by p.id for update of p;
select t.id from public.spec_templates t, assignment_document d
where t.id in (select (c->>'template_id')::uuid
 from jsonb_array_elements(d.doc->'commands') c) order by t.id for share of t;
select set_config('request.jwt.claims',jsonb_build_object(
 'sub',doc->>'actor_id','role','authenticated')::text,true),
 set_config('request.jwt.claim.sub',doc->>'actor_id',true)
from assignment_document;
set local role authenticated;
do $assign$
declare document jsonb; command jsonb; before_state jsonb; after_state jsonb; result jsonb;
begin
 select doc into document from assignment_document;
 if auth.uid() is distinct from (document->>'actor_id')::uuid or
    public.user_tenant_id() is distinct from (document->>'tenant_id')::uuid then
   raise exception 'Assignment actor or tenant changed';
 end if;
 for command in select value from jsonb_array_elements(document->'commands') loop
   before_state:=public.get_product_spec_research_snapshot_v2((command->>'product_id')::uuid);
   if before_state->>'snapshot_sha256' is distinct from command->>'snapshot_sha256' then
     raise exception 'Assignment preimage changed';
   end if;
   if not exists(select 1 from public.spec_templates t
     where t.id=(command->>'template_id')::uuid and t.tenant_id is null
       and t.key=command->>'template_key' and t.is_active
       and t.contract_version=(command->>'contract_version')::int) then
     raise exception 'Assignment target contract changed';
   end if;
   result:=public.assign_product_spec_template_v1(
     (command->>'product_id')::uuid,(command->>'template_id')::uuid,
     (command->>'expected_revision')::bigint,(command->>'expected_updated_at')::timestamptz,
     command->>'operation_key',command->>'reason');
   if result->'replayed' is distinct from 'false'::jsonb then
     raise exception 'Existing receipt requires explicit recovery';
   end if;
   after_state:=public.get_product_spec_research_snapshot_v2((command->>'product_id')::uuid);
   if after_state#>>'{{editor,template_id}}' is distinct from command->>'template_id' or
      after_state#>>'{{editor,binding_source}}' is distinct from 'explicit' or
      (after_state#>>'{{product,spec_revision}}')::bigint is distinct from
        (command->>'expected_revision')::bigint+1 or
      ((after_state->'product')-array['spec_template_id','spec_revision','updated_at'])
        is distinct from ((before_state->'product')-array['spec_template_id','spec_revision','updated_at']) or
      after_state->'observations' is distinct from before_state->'observations' or
      after_state->'member_profile_events' is distinct from before_state->'member_profile_events' or
      after_state#>'{{member_profiles,profiles}}' is distinct from before_state#>'{{member_profiles,profiles}}' or
      after_state#>'{{member_profiles,archived_profiles}}' is distinct from before_state#>'{{member_profiles,archived_profiles}}' then
     raise exception 'Assignment changed data outside the reviewed binding';
   end if;
   insert into assignment_receipts values ((command->>'product_id')::uuid,
      jsonb_build_object('before',before_state,'after',after_state,'rpc_result',result));
 end loop;
end $assign$;
set constraints all immediate;
select count(*) as rehearsed_assignments from assignment_receipts;
reset role;
rollback;
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proposal', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = args.proposal.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    actor, rows = commands(json.loads(data), digest)
    descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as target:
        target.write(rehearsal_sql(actor, rows, digest))
    print(json.dumps({'prepared_assignments': len(rows), 'commits': False,
                      'production_writes': 0, 'facts_to_change': 0}))


if __name__ == '__main__':
    main()
