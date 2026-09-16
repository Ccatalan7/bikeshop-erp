#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema[format-nongpl]==4.26.0"]
# ///
"""Prepare one exact privileged registration after fresh authenticated review.

This emits SQL for scripts/db/query.sh's guarded write path; it does not run
SQL, enable readiness, apply facts or create a new approval. The input readiness
receipt must come from the separately reviewed global sanitation closure, and
the audit and independent-review artifacts it hashes must be present: their
sha256 are recomputed here, so an opaque receipt cannot register anything.
"""
import argparse
from datetime import datetime
import hashlib
import os
from pathlib import Path
import re
import sys
from uuid import UUID

from prepare_product_spec_application import prepare, verify_bundle
from product_spec_session import ProductSpecSession, SessionUnavailable
from simulate_product_spec_research import ROOT, RESEARCH, canonical, load_json, simulate


def sql_text(value):
    if not isinstance(value, str) or '\x00' in value:
        raise ValueError('SQL text must be a NUL-free string')
    return "'" + value.replace("'", "''") + "'"


def registration_sql(bundle, readiness, simulation, evidence_root=RESEARCH):
    command = verify_bundle(bundle)
    required = {'schema_version', 'project', 'id', 'tenant_id', 'audit_sha256',
                'review_sha256', 'closed_at', 'enabled'}
    if (set(readiness) != required or type(readiness['schema_version']) is not int
            or readiness['schema_version'] != 1 or readiness['enabled'] is not True
            or readiness['project'] != bundle['project']
            or readiness['tenant_id'] != command['tenant_id']):
        raise ValueError('A closed readiness receipt for this exact project and tenant is required')
    for key in ('id', 'tenant_id'):
        if not isinstance(readiness[key], str) or str(UUID(readiness[key])) != readiness[key]:
            raise ValueError('Readiness identities must be canonical UUIDs')
    for key in ('audit_sha256', 'review_sha256'):
        if not isinstance(readiness[key], str) or not re.fullmatch('[a-f0-9]{64}', readiness[key]):
            raise ValueError('Readiness needs the exact audit and independent review hashes')
    if (not isinstance(readiness['closed_at'], str)
            or datetime.fromisoformat(readiness['closed_at'].replace('Z', '+00:00')).utcoffset() is None):
        raise ValueError('Readiness closure must have an explicit timezone')
    # Hash verification alone can be recreated by anyone. Re-run the proposal
    # schema, evidence files, independent review, full preimage and all effects.
    fresh = prepare(bundle['proposal'], simulation, evidence_root)
    if fresh['bundle_sha256'] != bundle['bundle_sha256']:
        raise ValueError('Fresh review differs; this registration cannot refresh or replace approval')
    command_text = canonical(command).decode()
    if len(command_text.encode()) > 4194304:
        raise ValueError('Reviewed command exceeds the server registration limit')
    literal = {k: sql_text(v) for k, v in {
        'id': bundle['operation_id'], 'tenant': command['tenant_id'], 'actor': command['actor_id'],
        'readiness': readiness['id'], 'audit': readiness['audit_sha256'],
        'review': readiness['review_sha256'], 'closed': readiness['closed_at'],
        'command': command_text, 'command_sha': bundle['command_sha256'],
        'proposal': canonical(bundle['proposal']).decode(), 'bundle_sha': bundle['bundle_sha256'],
    }.items()}
    tag = '$registration_' + bundle['command_sha256'][:16] + '$'
    while any(tag in value for value in literal.values()):
        tag = tag[:-1] + '_x$'
    return f"""-- Exact research registration; project {bundle['project']}.
-- Execute only through scripts/db/query.sh on that verified linked target.
begin;
set local standard_conforming_strings=on;
set local lock_timeout='5s';
set local statement_timeout='30s';
do {tag}
declare v_gate public.product_spec_research_readiness%rowtype;
        v_app public.product_spec_research_applications%rowtype;
begin
 perform pg_advisory_xact_lock(hashtextextended({literal['tenant']}::uuid::text||':spec_research:'||{literal['id']}::uuid::text,0));
 select * into v_gate from public.product_spec_research_readiness
 where id={literal['readiness']}::uuid and tenant_id={literal['tenant']}::uuid for share;
 if not found or not v_gate.enabled
  or v_gate.audit_sha256 is distinct from {literal['audit']}
  or v_gate.review_sha256 is distinct from {literal['review']}
  or v_gate.closed_at is distinct from {literal['closed']}::timestamptz then
  raise exception 'Global readiness no longer matches the reviewed closure' using errcode='40001';
 end if;
 insert into public.product_spec_research_applications
 (id,tenant_id,actor_id,readiness_id,command_text,command_sha256,proposal,bundle_sha256)
 values({literal['id']}::uuid,{literal['tenant']}::uuid,{literal['actor']}::uuid,
  {literal['readiness']}::uuid,{literal['command']},{literal['command_sha']},
  {literal['proposal']}::jsonb,{literal['bundle_sha']}) on conflict(id) do nothing;
 select * into v_app from public.product_spec_research_applications where id={literal['id']}::uuid for update;
 if v_app.tenant_id is distinct from {literal['tenant']}::uuid
  or v_app.actor_id is distinct from {literal['actor']}::uuid
  or v_app.readiness_id is distinct from {literal['readiness']}::uuid
  or v_app.command_text is distinct from {literal['command']}
  or v_app.command_sha256 is distinct from {literal['command_sha']}
  or v_app.proposal is distinct from {literal['proposal']}::jsonb
  or v_app.bundle_sha256 is distinct from {literal['bundle_sha']}
  or v_app.revoked_at is not null then
  raise exception 'Existing application differs or was revoked; no approval was replaced' using errcode='23514';
 end if;
end {tag};
select id as application_id,tenant_id,actor_id,readiness_id,command_sha256,bundle_sha256,
 revoked_at is not null as revoked from public.product_spec_research_applications
 where id={literal['id']}::uuid;
commit;
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', required=True, type=Path)
    parser.add_argument('--readiness', required=True, type=Path)
    parser.add_argument('--audit', required=True, type=Path,
                        help='global audit artifact whose sha256 the readiness receipt names')
    parser.add_argument('--review', required=True, type=Path,
                        help='independent review artifact whose sha256 the readiness receipt names')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    bundle, readiness = load_json(args.bundle), load_json(args.readiness)
    for path, key in ((args.audit, 'audit_sha256'), (args.review, 'review_sha256')):
        if not path.is_file():
            raise ValueError('Readiness artifact is missing: ' + str(path))
        if hashlib.sha256(path.read_bytes()).hexdigest() != readiness.get(key):
            raise ValueError('Readiness ' + key + ' does not match ' + path.name)
    command = verify_bundle(bundle)
    client = ProductSpecSession(ROOT)
    if client.project != bundle['project'] or client.actor_id != command['actor_id']:
        raise ValueError('Verified session does not belong to this reviewed project and actor')
    prepared_sql = registration_sql(bundle, readiness, simulate(bundle['proposal'], client))
    fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        output.write(prepared_sql)
    print(canonical({'application_id': bundle['operation_id'], 'project': client.project,
                     'readiness_id': readiness['id'], 'audit': args.audit.name, 'review': args.review.name,
                     'product_writes': 0, 'registrations': 0, 'output': str(args.output)}).decode())


if __name__ == '__main__':
    try:
        main()
    except (ValueError, SessionUnavailable, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
