#!/usr/bin/env python3
"""Assemble the 37 original successors without publishing or writing products.

Inputs are exact hashes from the shared-definition audit. Duplicate families,
case IDs, definition identities or conflicting shared meanings abort assembly.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import RESEARCH, write_json
from compile_product_spec_catalog import validate_contract

AUDIT = RESEARCH/'original-successors-shared-definition-audit-2026-09-08.json'
CORE = ('id','key','label','data_type','unit','allowed_values','validation_rules')


def sql_transport_aliases(cases):
    """Nine rear-cog aliases measured in the full SQL integration checkpoint.

    Unknown applicability is still nonblocking/pending, not compatible.
    No catalogue rule or product value is changed by these expectation names.
    """
    pending_applicability = {
        'rcx_an_unknown_spline_leaves_the_accepted_bodies_pending',
        'rcx_a_missing_spline_leaves_the_bodies_pending',
        'rcx_an_unknown_spline_leaves_the_shift_technology_pending',
        'rcx_an_unknown_thread_leaves_the_extractor_pending',
        'rcx_a_missing_thread_leaves_the_extractor_pending',
        'rcx_an_unknown_cog_thread_leaves_the_lockring_pending',
        'rcx_a_missing_cog_thread_leaves_the_lockring_pending'}
    for case in cases:
        if case['id'] in pending_applicability:
            case['expected_sql_issue_subset'] = [{**i, 'code':
                'field_applicability' if i['code'] == 'prerequisite' else i['code']}
                for i in case['expected_issue_subset']]
        if case['id'] == 'rcx_a_resolved_variant_without_its_source_is_pending':
            case['expected_sql_issue_subset'] = [{**i, 'code':'prerequisite_missing'}
                for i in case['expected_issue_subset']]
        if case['id'] == 'rcx_a_smallest_cog_above_the_largest_blocks':
            case['expected_sql_blocking'] = sorted(case['expected_blocking'],
                key=lambda i:(i['code'],i['field']))


def compile_catalog():
    audit = json.loads(AUDIT.read_text())
    if audit['shared_definition_conflicts'] or audit['templates'] != 37:
        raise ValueError('Unresolved shared meanings or incomplete original-family scope')
    definitions, templates, ids, cases, pending, sources, case_hashes = {}, {}, {}, [], [], set(), {}
    case_ids = set()
    for filename, expected in audit['input_sha256'].items():
        path = RESEARCH/filename
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Candidate changed after shared-definition audit: '+filename)
        catalog = json.loads(path.read_text())
        fixture_path = RESEARCH/filename.replace('-catalog-', '-cases-')
        fixtures = json.loads(fixture_path.read_text())
        if fixtures.get('catalogue_sha256') != expected:
            raise ValueError('Cases do not reference the exact candidate: '+fixture_path.name)
        case_hashes[fixture_path.name] = hashlib.sha256(fixture_path.read_bytes()).hexdigest()
        for t in catalog['templates']:
            if t['key'] in templates:
                raise ValueError('Duplicate family: '+t['key'])
            templates[t['key']] = deepcopy(t)
        for key, d in catalog['definitions'].items():
            if key in definitions:
                if any(definitions[key].get(k) != d.get(k) for k in CORE):
                    raise ValueError('Conflicting shared meaning: '+key)
                if d['origin'] == 'existing':
                    definitions[key]['origin'] = 'existing'
            else:
                if d['id'] in ids and ids[d['id']] != key:
                    raise ValueError('Duplicate definition identity: '+d['id'])
                ids[d['id']] = key
                definitions[key] = deepcopy(d)
        sources.update(catalog.get('source_urls', []))
        for f in fixtures['cases']:
            if f['id'] in case_ids:
                raise ValueError('Duplicate executable case: '+f['id'])
            case_ids.add(f['id'])
            cases.append(deepcopy(f))
        # Pending cases preserve their source package. They are not counted
        # as passed cases or automatically resolved by joining catalogues.
        pending += [{**deepcopy(p), 'source_package':filename} for p in fixtures.get('pending_cases', [])]
    for key, d in definitions.items():
        d['used_by'] = sorted(t['key'] for t in templates.values()
                              if any(f['key'] == key for f in t['fields']))
        if not d['used_by']:
            raise ValueError('Unowned definition: '+key)
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions, {f['key'] for f in t['fields']})
    result = {'schema_version':1, 'title':'Original 37 technical-family successors, integrated candidate',
        'templates':list(templates.values()), 'definitions':definitions,
        'input_sha256':audit['input_sha256'], 'case_input_sha256':case_hashes,
        'source_urls':sorted(sources), 'mechanical_coverage_complete':False,
        'automatic_fill_authorized':False, 'publication_authorized':False,
        'stats':{'templates':len(templates),'definitions':len(definitions),
                 'field_uses':sum(len(t['fields']) for t in templates.values())}}
    sql_transport_aliases(cases)
    return result, {'cases':cases,'pending_cases':pending}


if __name__ == '__main__':
    catalog,fixtures = compile_catalog()
    path = RESEARCH/'original-successors-integrated-catalog-2026-09-08.json'
    write_json(path,catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH/'original-successors-integrated-cases-2026-09-08.json',fixtures)
    print(json.dumps({**catalog['stats'],'cases':len(fixtures['cases']),
        'pending_cases':len(fixtures['pending_cases']),'product_writes':False,'published':False}))
