#!/usr/bin/env python3
"""Prepare the cassette, freewheel, fixed cog and spacer owners against a fresh preimage, never publish.

This candidate has no family preimage of its own: the frozen reference is the
37-family candidate preimage of 2026-09-08 restricted to these four templates.

The reviewed 2026-09-08 catalogue, cases and preimage stay pinned. The fresh
production preimage must match the reviewed one in template, fields and shared
definitions; only the binding counts may differ. Observations are preserved.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

from compile_existing_spec_publication import (
    compile_packet, generate_migration, generate_verifier, load_pinned)
from test_existing_spec_candidate import prepare as prepare_rehearsal
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

PREFIX = 'rear-cogs-2026-09-16'
FAMILIES = ('cassette', 'freewheel', 'fixed_cog', 'cassette_spacer')
CATALOG_SHA = '21b3b278bbee57c32d93b0a599196582db815be4117363121bf552d2329fd15b'
CASES_SHA = '436330e8d92d796e6880732b00cb8ed11b301085585d3d1eb8c44e3968bf786b'
FROZEN_PREIMAGE_SHA = '0a21d85a1539c330e661e0c5c1aa2fde0bbf29ddad67a452a018ed767d08b2a6'
# New scalar definitions with operator/customer meaning. Free-text OEM
# designations, row tables and the retired legacy readings stay outside filters.
SURFACE_FIELDS = {
    'cassette_spline_standard', 'cog_lockring_thread', 'cog_thread_standard',
    'freewheel_thread_standard', 'lockring_included', 'remover_tool_standard',
    'shift_technology', 'sprocket_count',
}
DEAD_ON_ARRIVAL = {}


DIAGNOSIS = """
-- Reviewed activation over populated data (2026-09-16). The publication guard
-- refuses any coherence change over fields that already hold facts. The prior
-- diagnosis read every populated pair of the scope; this block repeats it in
-- the same snapshot and aborts on the first contradiction, then the guard is
-- suspended only for this transaction's template updates and restored before
-- the metadata is re-validated. No fact is read, written or relabelled.
do $diagnosis$
declare violations integer; foreign_facts integer; missing_pairs integer;
begin
 select count(*) into violations from (
   select f.subject_id,
     max(f.value_number) filter (where d.key='smallest_cog_teeth') smallest,
     max(f.value_number) filter (where d.key='largest_cog_teeth') largest
   from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
   join public.spec_template_fields tf on tf.spec_definition_id=d.id
   join public.spec_templates t on t.id=tf.template_id and t.tenant_id is null and t.key in ('cassette','freewheel')
   where f.subject_type='product' and d.tenant_id is null and d.key in ('smallest_cog_teeth','largest_cog_teeth')
   group by f.subject_id) x where x.smallest is not null and x.largest is not null and x.smallest > x.largest;
 if violations > 0 then
   raise exception 'Populated cog pairs contradict the ordered pair: % products', violations;
 end if;
 select count(*) into foreign_facts from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
   where d.tenant_id is null and d.key in ('cog_sequence','sprocket_count','freehub_bodies_accepted');
 if foreign_facts > 0 then
   raise exception 'Unexpected facts on coherence endpoints that must be new: %', foreign_facts;
 end if;
end $diagnosis$;
alter table public.spec_templates disable trigger spec_coherence_publication_guard;
"""
RESTORE = """
alter table public.spec_templates enable trigger spec_coherence_publication_guard;
do $revalidate$ declare t record; begin
 for t in select id, form_contract from public.spec_templates where tenant_id is null and key in ('cassette','freewheel','fixed_cog','cassette_spacer') loop
   perform public.spec_coherence_metadata_internal_v1(t.form_contract, public.spec_coherence_fields_internal_v1(t.id));
 end loop;
end $revalidate$;
"""


def harden_over_facts(sql):
    """Insert the reviewed diagnosis and the scoped guard suspension."""
    anchor = 'create temporary table nd_publication_document(doc jsonb) on commit drop;'
    if sql.count(anchor) != 1 or sql.rstrip().endswith('commit;') is False:
        raise ValueError('Unexpected migration shape for the reviewed activation')
    sql = sql.replace(anchor, DIAGNOSIS.strip('\n') + '\n' + anchor)
    head, tail = sql.rstrip().rsplit('commit;', 1)
    return head + RESTORE.strip('\n') + '\ncommit;\n'


def reviewed_migration(packet, source_sha):
    return harden_over_facts(generate_migration(packet, source_sha=source_sha))


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_rear_cogs_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    frozen = load_pinned(ROOT / '.tmp/db/existing-37-candidate-preimage.json', FROZEN_PREIMAGE_SHA)
    if isinstance(frozen, list):
        frozen = frozen[0]['metadata']
    frozen_templates = [t for t in frozen['templates'] if t['key'] in FAMILIES]
    frozen_ids = {t['id'] for t in frozen_templates}
    live_keys = {d['key'] for d in before['existing_definitions']}
    for name, a, b in (('templates', frozen_templates, before['templates']),
                       ('fields', [f for f in frozen['fields'] if f['template_id'] in frozen_ids], before['fields']),
                       ('existing_definitions', [d for d in frozen['existing_definitions'] if d['key'] in live_keys],
                        before['existing_definitions'])):
        if stripped(a) != stripped(b):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + name)
    original = load_pinned(RESEARCH / 'existing-rear-cogs-catalog-2026-09-07.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-rear-cogs-cases-2026-09-07.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != 4:
        raise ValueError('The reviewed catalogue must carry exactly the four rear-cog families')
    legacy = {t['key']: {k for k, r in t['form_contract']['roles'].items() if r == 'legacy'} for t in templates}
    if legacy != {'cassette': {'cassette_cog_sequence', 'drivetrain_speeds', 'freehub_type'},
                  'freewheel': {'cassette_cog_sequence', 'drivetrain_speeds', 'freehub_type'},
                  'fixed_cog': {'drivetrain_speeds', 'freehub_type'},
                  'cassette_spacer': {'freehub_type'}}:
        raise ValueError('The legacy boundary changed; re-adjudicate it')
    used = {f['key'] for t in templates for f in t['fields']}
    definitions = {k: deepcopy(original['definitions'][k]) for k in sorted(used)}
    if any(d['origin'] == 'new' and d['key'] in live_keys for d in definitions.values()):
        raise ValueError('A definition labelled new already exists live; re-adjudicate it')
    catalog = {**deepcopy(original), 'templates': templates, 'definitions': definitions,
               'source_catalog_sha256': CATALOG_SHA, 'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False, 'publication_authorized': False}
    cp = RESEARCH / (PREFIX + '-catalog.json'); write_json(cp, catalog)
    sha = hashlib.sha256(cp.read_bytes()).hexdigest()
    cases = {'schema_version': 1, 'catalogue_sha256': sha,
             'cases': deepcopy(old_cases['cases']),
             'pending_cases': deepcopy(old_cases.get('pending_cases', []))}
    # The reviewed cases were run on the Dart harness only. SQL spells a pending
    # prerequisite `prerequisite_missing` and a pending applicability
    # `field_applicability`; field and severity are the same. Blocking arrays
    # are compared as ordered JSON, so they are sorted like the engine emits them.
    contracts = {t['key']: t['form_contract'] for t in templates}
    def sql_code(template, issue):
        if issue['code'] != 'prerequisite':
            return issue['code']
        contract = contracts[template]
        gate = contract.get('allowed_when', {}).get(issue['field'], {})
        if gate.get('kind') == 'when':
            return 'field_applicability'
        return 'prerequisite_missing'
    for case in cases['cases']:
        if 'expected_issue_subset' in case:
            case['expected_sql_issue_subset'] = [
                {**i, 'code': sql_code(case['template'], i)} for i in case['expected_issue_subset']]
        blocking = case.get('expected_sql_blocking', case.get('expected_blocking', []))
        case['expected_sql_blocking'] = sorted(deepcopy(blocking), key=lambda i: (i['code'], i['field']))
    case_path = RESEARCH / (PREFIX + '-cases.json'); write_json(case_path, cases)
    packet = compile_packet(catalog=catalog, cases=cases, before=before, families=list(FAMILIES),
        hashes={'catalog_sha256': sha, 'cases_sha256': hashlib.sha256(case_path.read_bytes()).hexdigest(),
                'preimage_sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
        adjudication={
            'status': 'candidate_under_sole_owner_review',
            'scope': 'Cassette, freewheel, fixed cog and spacer owners; wheels, identity and fill stay outside.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-08 37-family preimage restricted to '
                        'these templates, fields and shared definitions; effective bindings 31+28+0+3 -> 32+29+0+3.',
            'ownership': 'The unit and its resolved published variant are product facts; the model variants are OEM references.',
            'cardinality': 'sprocket_count counts the sprockets of the unit being edited; the sequence must match it.',
            'legacy': 'Published cog sequence, speed and freehub readings are retained without becoming active compatibility.',
            'reviews': 'Three Root reviews (2026-09-07/08) accepted the ownership correction; no open blocker on the metadata.',
            'released_client': 'f51f3777 decodes row_conditions, row_coherence and two-element scalar pairs; two two-element pairs here, no strict order.',
            'populated_data': 'Reviewed activation: 44 populated smallest/largest pairs read on 2026-09-16 with no contradiction; '
                              'the migration repeats that diagnosis in its snapshot and suspends the publication guard only for its own template updates.',
            'compatibility_and_fill_not_approved': True,
        })
    new_definitions = {d['key']: d for d in packet['records']['spec_definitions']}
    if not SURFACE_FIELDS <= new_definitions.keys():
        raise ValueError('Surface flags may only be assigned to reviewed new definitions')
    for key in SURFACE_FIELDS:
        new_definitions[key].update(is_customer_visible=True, is_filterable=True)
    packet['adjudication']['new_scalar_surfaces'] = sorted(SURFACE_FIELDS)
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    (ROOT / '.tmp/db' / (PREFIX + '-candidate.sql')).write_text(reviewed_migration(packet, sha))
    rehearsal = ROOT / '.tmp/db' / (PREFIX + '-forward-candidate')
    rehearsal.mkdir(parents=True, exist_ok=True)
    (rehearsal / 'forward-replay-and-cases.sql').write_text(
        prepare_rehearsal(packet, cases, migration_builder=reviewed_migration))
    (ROOT / '.tmp/db' / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': 4, 'new_definitions': len(packet['records']['spec_definitions']),
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'pending_cases': len(cases['pending_cases']),
                      'patches': len(packet['patches']),
                      'contract_versions': {t['key']: t['contract_version'] for t in packet['records']['spec_templates']},
                      'bindings': before['effective_bindings'], 'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
