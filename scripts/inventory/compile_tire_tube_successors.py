#!/usr/bin/env python3
"""Prepare the five tyre/tube owners against a fresh preimage, never publish.

The reviewed 2026-09-08 catalogue and cases stay pinned. The fresh production
preimage must match them in templates, fields and shared definitions; only the
binding counts may differ. Current field observations are preserved.
"""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys

from compile_existing_spec_publication import (
    compile_packet, generate_migration, generate_verifier, load_pinned)
from compile_non_drivetrain_publication import RESEARCH, ROOT, write_json

PREFIX = 'tire-tube-2026-09-16'
FAMILIES = ('tire', 'tube', 'rim_strip', 'tubeless_consumable', 'tubeless_valve')
CATALOG_SHA = 'b9e30b145346d52489dc807400a56e7dd38788e74a0e0b269c48f2f35412e619'
CASES_SHA = '7cc47f5df2e152547b3bb0795b3fa6fcd11403bfe88e20bec72010018ea4c9b5'
FROZEN_PREIMAGE_SHA = '48b5602be1decc4ff156bae62ffd1dec409407a0815e9dbf38b67f2dc81097d5'
# New scalar definitions with operator/customer meaning. Row tables, the
# legacy cover pressure and kit membership stay outside automatic filters.
SURFACE_FIELDS = {
    'tire_tpi', 'tire_weight_g', 'tire_use', 'valve_standard',
    'valve_length_mm_value', 'valve_core_removable', 'valve_base_shape',
    'strip_width_mm', 'strip_material', 'strip_fit_internal_width_min_mm',
    'strip_fit_internal_width_max_mm', 'rim_hole_diameter_mm',
    'consumable_kind', 'sealant_base',
}
TUFO = 'https://www.tufo.com/en/tubular/'


def stripped(records):
    return {json.dumps(r, sort_keys=True) for r in records}


def gate_cases(old_cases):
    """Adjudicate the tubeless-ready gate on every bead construction."""
    base = next(c for c in old_cases['cases']
                if c['id'] == 'ttx_a_tubular_tire_declares_no_tubeless_ready')
    cases = []

    def add(name, bead, *, blocking, pending=(), forbidden=()):
        case = deepcopy(base)
        case.update(id='tire_tube_' + name, kind='synthetic_boundary',
                    facts_verified_for_product=False, automatic_fill_authorized=False)
        case['values']['tire_bead_type'] = bead
        case['expected_blocking'] = [{'code': 'field_applicability', 'field': 'tire_tubeless_ready'}] if blocking else []
        case['expected_sql_blocking'] = deepcopy(case['expected_blocking'])
        # A pending applicability is spelled `prerequisite` by the editor and
        # `field_applicability` by SQL; field and severity are the same.
        case['expected_issue_subset'] = [{'code': c, 'field': f, 'blocking': False} for c, f in pending]
        case['expected_sql_issue_subset'] = [
            {'code': 'field_applicability' if c == 'prerequisite' else c, 'field': f, 'blocking': False}
            for c, f in pending]
        case['forbidden_issue_fields'] = list(forbidden)
        case['source_urls'] = [TUFO] if blocking else []
        cases.append(case)
    add('a_solid_tire_declares_no_tubeless_ready', 'Sólido / sin aire', blocking=True)
    add('a_wire_bead_may_declare_tubeless_ready', 'Talón de alambre', blocking=False,
        forbidden=('tire_tubeless_ready',))
    # An unconfirmed bead is unknown, not a bead kind: both engines keep the
    # bead pending and leave the tubeless-ready claim pending with it.
    add('an_unconfirmed_bead_leaves_tubeless_ready_pending', 'Desconocido / sin confirmar',
        blocking=False, pending=(('prerequisite', 'tire_tubeless_ready'),
                                 ('required_missing', 'tire_bead_type')))
    return cases


def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: compile_tire_tube_successors.py <fresh-preimage.json>')
    path = Path(sys.argv[1])
    before = json.loads(path.read_text())
    if isinstance(before, list):
        before = before[0]['metadata']
    frozen = load_pinned(RESEARCH / 'existing-tires-tubes-publication-preimage-2026-09-08.json',
                         FROZEN_PREIMAGE_SHA)
    for section in ('templates', 'fields', 'existing_definitions'):
        if stripped(before[section]) != stripped(frozen[section]):
            raise ValueError('Live metadata drifted from the reviewed preimage: ' + section)
    original = load_pinned(RESEARCH / 'existing-tires-tubes-catalog-2026-09-08.json', CATALOG_SHA)
    old_cases = load_pinned(RESEARCH / 'existing-tires-tubes-cases-2026-09-08.json', CASES_SHA)
    templates = deepcopy([t for t in original['templates'] if t['key'] in FAMILIES])
    if len(templates) != len(FAMILIES):
        raise ValueError('The reviewed catalogue must carry exactly the five families')
    used = {f['key'] for t in templates for f in t['fields']}
    definitions = {k: deepcopy(original['definitions'][k]) for k in sorted(used)}
    tire = next(t for t in templates if t['key'] == 'tire')['form_contract']
    gate = tire['allowed_when']['tire_tubeless_ready']
    allowed = gate['rows'][0][0]['value']
    if (gate['kind'] != 'when' or set(allowed) !=
            {'Talón plegable', 'Talón de alambre', 'Desconocido / sin confirmar'}):
        raise ValueError('The tubeless-ready gate changed; re-adjudicate it')
    tire['helpers']['tire_tubeless_ready'] = (
        'Apto para montaje tubeless con talón y llanta compatibles. Un tubular '
        'o un neumático sólido no lo declaran aunque usen sellante o no lleven '
        'cámara separada; con el talón sin confirmar queda pendiente, no bloqueado.')
    catalog = {**deepcopy(original), 'templates': templates, 'definitions': definitions,
               'source_catalog_sha256': CATALOG_SHA, 'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False, 'publication_authorized': False}
    cp = RESEARCH / (PREFIX + '-catalog.json'); write_json(cp, catalog)
    sha = hashlib.sha256(cp.read_bytes()).hexdigest()
    cases = {'schema_version': 1, 'catalogue_sha256': sha,
             'cases': deepcopy(old_cases['cases']) + gate_cases(old_cases),
             'pending_cases': deepcopy(old_cases['pending_cases'])}
    case_path = RESEARCH / (PREFIX + '-cases.json'); write_json(case_path, cases)
    packet = compile_packet(catalog=catalog, cases=cases, before=before, families=list(FAMILIES),
        hashes={'catalog_sha256': sha, 'cases_sha256': hashlib.sha256(case_path.read_bytes()).hexdigest(),
                'preimage_sha256': hashlib.sha256(path.read_bytes()).hexdigest()},
        adjudication={
            'status': 'candidate_under_sole_owner_review',
            'scope': 'Five original tyre/tube owners; no wheel assembly, no fill, no assignment.',
            'preimage': 'Fresh 2026-09-16 production capture equals the 2026-09-08 preimage in '
                        'templates, fields and shared definitions; effective bindings 264 -> 271.',
            'tubeless_ready_gate': 'Kept as compiled: Tubeless Ready is the clincher bead/rim '
                                   'property. A tubular (glued, sealed casing) or a solid tyre '
                                   'cannot declare it; an unconfirmed bead leaves it pending, never approved.',
            'tubeless_ready_source': TUFO,
            'dose': 'Application identity includes tyre size and conditions, never just MTB or bottle capacity.',
            'valve': 'Core removal is separately evidenced, not inferred from Presta/Schrader/Dunlop.',
            'pressures': 'Order only the minimum/maximum within one scope and unit; preserve other system owners.',
            'contents': 'A component has one identity; its family is not an independent free choice.',
            'relations': 'Existing evaluator tested; source scope and editor/reference integration remain separate gates.',
            'released_client': 'f51f3777 decodes row_conditions and two-element scalar_ordered_pairs; '
                               'this catalogue declares one two-element pair and no strict order.',
            'compatibility_and_fill_not_approved': True,
        })
    new_definitions = {d['key']: d for d in packet['records']['spec_definitions']}
    if not SURFACE_FIELDS <= new_definitions.keys():
        raise ValueError('Surface flags may only be assigned to reviewed new definitions')
    for key in SURFACE_FIELDS:
        new_definitions[key].update(is_customer_visible=True, is_filterable=True)
    packet['adjudication']['new_scalar_surfaces'] = sorted(SURFACE_FIELDS)
    write_json(RESEARCH / (PREFIX + '-packet.json'), packet)
    (ROOT / '.tmp/db' / (PREFIX + '-candidate.sql')).write_text(generate_migration(packet, source_sha=sha))
    (ROOT / '.tmp/db' / (PREFIX + '-verification.sql')).write_text(generate_verifier(packet, cases))
    print(json.dumps({'templates': len(templates), 'new_definitions': len(packet['records']['spec_definitions']),
                      'reused_definitions': len(packet['reused_definitions']),
                      'cases': len(cases['cases']), 'pending_cases': len(cases['pending_cases']),
                      'patches': len(packet['patches']),
                      'contract_versions': {t['key']: t['contract_version'] for t in packet['records']['spec_templates']},
                      'bindings': before['effective_bindings'], 'published': False, 'facts_changed': 0}))


if __name__ == '__main__':
    main()
