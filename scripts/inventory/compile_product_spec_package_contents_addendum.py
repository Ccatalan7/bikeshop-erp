#!/usr/bin/env python3
"""Distinguish supplied chainrings from an installed drivetrain configuration."""
from copy import deepcopy
import json

from compile_product_spec_catalog import RESEARCH, validate_contract
from compile_product_spec_row_value_addendum import compile_row_values
from product_spec_field_patches import apply_reviewed_field_addendum, artifact_sha

BASE_SHA = '58e68f0c4f0d7b8e824a84a3931cf9f7bd03767f8a65aaa55020bc6af7465f03'
CASES_SHA = '0eb5dfda6a7087cf115afd54e08a9908b00511acbae59d58217b783d371da810'


def compile_package_contents():
    base, cases, _, _ = compile_row_values()
    if artifact_sha(base) != BASE_SHA or artifact_sha(cases) != CASES_SHA:
        raise ValueError('Frozen row-value catalogue or cases changed')
    templates = {t['key']: t for t in base['templates']}
    patches = []

    def field_change(template, key, after):
        contract = templates[template]['form_contract']
        patches.append({'id': f'CONT-{len(patches)+1:02}',
            'op': 'replace_field_contract', 'template': template, 'key': key,
            'before': {bucket: deepcopy(contract[bucket].get(key)) for bucket in after},
            'after': after})

    definition = {'id': None, 'key': 'included_chainring_count', 'origin': 'new',
        'label': 'Cantidad de platos incluidos', 'data_type': 'number', 'unit': None,
        'allowed_values': [], 'validation_rules': {'min': '0', 'integer': True}, 'used_by': []}
    for template in ['crankset', 'drivetrain_kit']:
        field_change(template, 'chainring_count', {
            'roles': 'legacy', 'semantic_roles': 'legacy',
            'required_when': {'kind': 'never'}, 'evidence_requirements': 'name_reading_hint_only',
            'helpers': 'Cantidad antigua sin distinguir contenido y configuración. Se conserva; no se copia al contenido ni acredita capacidad de montaje.'})
        patches.append({'id': f'CONT-{len(patches)+1:02}', 'op': 'add_field',
            'template': template, 'key': 'included_chainring_count', 'before': None,
            'after': {'field_entry': {'key': 'included_chainring_count', 'section_key': 'contents',
                'sort_order': max(f['sort_order'] for f in templates[template]['fields'])+10,
                'is_required': False, 'visibility_rules': [], 'option_rules': [], 'constraint_rules': []},
                'definition_used_by_append': template, 'roles': 'contents', 'semantic_roles': 'contents',
                'allowed_when': {'kind': 'always'}, 'required_when': {'kind': 'always'},
                'helpers': 'Número de platos físicamente suministrados con esta variante. Cero exige evidencia de que no se incluyen; sin confirmación queda Sin dato. No indica cuántos platos admite un montaje.',
                'evidence_requirements': 'package_or_label'}})
    positive = {'kind': 'when', 'rows': [[{'field': 'included_chainring_count',
        'operator': 'gt', 'value_type': 'decimal', 'value': '0'}]]}
    field_change('crankset', 'chainring_teeth_rows', {
        'roles': 'contents', 'semantic_roles': 'contents',
        'labels': 'Dientes y posición de los platos incluidos',
        'helpers': 'Describe sólo los platos suministrados. Las configuraciones compatibles u opcionales necesitan sus propias declaraciones; no se copian aquí.',
        'allowed_when': positive, 'required_when': positive,
        'evidence_requirements': 'package_or_label'})
    # The object remains the same template/family; only the misleading label changes.
    template = templates['mechanical_disc_brake']
    patches.append({'id': f'CONT-{len(patches)+1:02}', 'op': 'replace_template_label',
        'template': 'mechanical_disc_brake', 'key': 'name', 'before': template['name'],
        'after': 'Conjunto de freno mecánico de disco'})
    field_change('mechanical_disc_brake', 'kit_members', {
        'helpers': 'Componentes realmente suministrados con esta variante. Un conjunto puede traer cálipers y discos; su nombre no presume manillas, cables, fundas ni adaptadores. No confundir ausencia de dato con exclusión.'})
    proposal = {'schema_version': 1, 'base_artifact': 'all-family-row-values-integrated-2026-09-07.json',
        'base_sha256': BASE_SHA, 'new_definitions': {'included_chainring_count': definition},
        'patches': patches, 'sources': [
            {'url': 'https://www.profileracing.com/product/no-boss-3-piece-chromoly-race-crankset/',
             'scope': 'Contraejemplo OEM: juego de bielas y eje vendido para usar plato/spider aparte. No identifica ni rellena J253.'},
            {'artifact': 'assigned-product-family-adjudication-2026-09-07.json',
             'sha256': '852577ba7176e438be9a145be4327d70d936e464ca613a6571eb46d15a9b155a',
             'scope': 'AG01/AG02, imágenes J253 y 1062 inspeccionadas también por Root; no prueba exclusiones.'}],
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    decisions = {'approval_scope': 'field_representation', 'base_sha256': BASE_SHA,
        'proposal_sha256': artifact_sha(proposal), 'source_cases_sha256': CASES_SHA,
        'patch_adjudications': [{'patch_id': p['id'], 'decision': 'aceptar',
            'reason': 'El contenido de la variante se declara por separado de la capacidad y del sistema instalado; el nombre no fabrica miembros.'}
            for p in patches],
        'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    catalogue = apply_reviewed_field_addendum(base, proposal, decisions, validate_contract)
    added = []
    for template in ['crankset', 'drivetrain_kit']:
        for suffix, value, code in [('zero', 0, None), ('positive', 2, None),
                                    ('negative', -1, 'range'), ('fraction', '1.5', 'integer')]:
            case = {'id': f'contents_{template}_{suffix}', 'template': template,
                'values': {'included_chainring_count': value}, 'expected_blocking': [],
                'facts_verified_for_product': False, 'automatic_fill_authorized': False}
            if code:
                case['expected_blocking'] = [{'code': code, 'field': 'included_chainring_count'}]
                case['expected_sql_blocking'] = [{'code': 'field_constraint', 'field': 'included_chainring_count'}]
            added.append(case)
        added.append({'id': f'contents_{template}_legacy_not_content', 'template': template,
            'values': {'chainring_count': 3}, 'expected_blocking': [],
            'expected_issue_subset': [{'code': 'required_missing', 'field': 'included_chainring_count', 'blocking': False}],
            'expected_sql_issue_subset': [{'code': 'required_missing', 'field': 'included_chainring_count', 'blocking': False}],
            'forbidden_issue_fields': ['chainring_count'],
            'facts_verified_for_product': False, 'automatic_fill_authorized': False})
    rows = {'schema_version': 1, 'rows': [{'id': 'inner', 'values': {'position': '1', 'teeth': '34'}, 'sources': []}]}
    added.extend([
        {'id': 'contents_zero_cannot_declare_included_teeth', 'template': 'crankset',
         'values': {'included_chainring_count': 0, 'chainring_teeth_rows': rows},
         'expected_blocking': [{'code': 'field_applicability', 'field': 'chainring_teeth_rows'}],
         'expected_sql_blocking': [{'code': 'field_applicability', 'field': 'chainring_teeth_rows'}]},
        {'id': 'contents_teeth_without_count_pending', 'template': 'crankset',
         'values': {'chainring_teeth_rows': rows}, 'expected_blocking': [],
         'expected_issue_subset': [{'code': 'prerequisite', 'field': 'chainring_teeth_rows', 'blocking': False}],
         'expected_sql_issue_subset': [{'code': 'field_applicability', 'field': 'chainring_teeth_rows', 'blocking': False}]},
        {'id': 'contents_mechanical_set_does_not_require_levers_true', 'template': 'mechanical_disc_brake',
         'values': {'levers_included': False}, 'expected_blocking': []},
    ])
    for case in added:
        case.update(facts_verified_for_product=False, automatic_fill_authorized=False)
    cases['cases'].extend(added)
    cases.update(title='All-family representation after package-content distinction',
                 catalogue_sha256=artifact_sha(catalogue), mechanical_coverage_complete=False,
                 automatic_fill_authorized=False)
    return catalogue, cases, proposal, decisions


if __name__ == '__main__':
    catalogue, cases, proposal, decisions = compile_package_contents()
    for name, value in [('all-family-contents-integrated-2026-09-07.json', catalogue),
                        ('all-family-contents-cases-integrated-2026-09-07.json', cases),
                        ('package-contents-proposal-2026-09-07.json', proposal),
                        ('package-contents-decisions-2026-09-07.json', decisions)]:
        (RESEARCH/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({'catalogue_sha256': artifact_sha(catalogue), 'cases_sha256': artifact_sha(cases),
                      'stats': catalogue['stats'], 'cases': len(cases['cases'])}))
