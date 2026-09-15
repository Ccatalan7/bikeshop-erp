#!/usr/bin/env python3
"""Compile ten unpublished contact-point templates from the frozen catalogue."""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import (
    add_field, case, condition, new_definition, rows)
from compile_product_spec_catalog import validate_contract

FAMILIES = ('pedal', 'pedal_peg', 'grip', 'handlebar_covering', 'handlebar',
            'stem', 'seatpost', 'seat_clamp', 'saddle', 'saddle_cover')


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen input drift')
    base = json.loads(CATALOG.read_text())
    templates = {t['key']: deepcopy(t) for t in base['templates'] if t['key'] in FAMILIES}
    definitions = deepcopy(base['definitions'])
    fixtures = json.loads(CASES.read_text())
    fixtures['cases'] = [c for c in fixtures['cases'] if c['template'] in FAMILIES]
    c = templates['grip']['form_contract']
    reference = 'grip_measurement_reference'
    definitions[reference] = new_definition(
        reference, 'Zona y condición de la medición interior', 'text', ['grip'])
    add_field(templates['grip'], reference, 'measurement', 'measurement',
              helper='Identifica qué parte se midió y si estaba montada o libre, '
              'junto con el origen de esa medición. No deducirla del tamaño nominal.')
    c['prerequisites']['grip_inner_diameter_mm'] = [reference]
    c['helpers']['grip_inner_diameter_mm'] = (
        'Medición física interior, con zona y condición identificadas. No es '
        'el diámetro de manubrio admitido ni se iguala a éste por una fórmula.')
    c['helpers']['grip_bar_nominal_diameter_mm'] = (
        'Interfaz nominal de manubrio declarada para este modelo. No se obtiene '
        'midiendo el interior o el exterior del puño ni acredita todo el montaje.')

    # ODI v2.1 publishes a range in two units. One scalar cannot preserve that
    # declaration and must not silently become its maximum or a conversion.
    torque = 'grip_clamp_torque_specifications'
    scalar, interval, maximum = 'Par nominal', 'Rango de apriete', 'Máximo de apriete'
    definitions[torque] = new_definition(
        torque, 'Apriete de las abrazaderas del puño', 'json', ['grip'],
        rules={'rows_schema': {'version': 1,
            'ordered_pairs': [['minimum', 'maximum']], 'columns': [
                {'key': 'quantity_kind', 'label': 'Tipo de declaración',
                 'type': 'token', 'required': True,
                 'allowed_values': [scalar, interval, maximum]},
                {'key': 'value', 'label': 'Valor declarado', 'type': 'decimal',
                 'validation': {'positive': True}},
                {'key': 'minimum', 'label': 'Mínimo del rango', 'type': 'decimal',
                 'validation': {'positive': True}},
                {'key': 'maximum', 'label': 'Máximo del rango', 'type': 'decimal',
                 'validation': {'positive': True}},
                {'key': 'unit', 'label': 'Unidad publicada', 'type': 'token',
                 'required': True, 'allowed_values': ['Nm', 'in-lb', 'ft-lb']},
                {'key': 'configuration', 'label': 'Abrazadera, modelo y alcance',
                 'type': 'text', 'required': True},
                {'key': 'conditions', 'label': 'Condiciones del fabricante', 'type': 'text'},
                {'key': 'source_url', 'label': 'Fuente', 'type': 'url'},
            ]}})
    add_field(templates['grip'], torque, 'declaration', 'declaration',
              allowed=deepcopy(c['allowed_when']['grip_clamp_torque_nm']),
              helper='Copia el valor o rango y cada unidad publicada para esa '
              'abrazadera. No convierte unidades ni supone un apriete universal; '
              'conserva las condiciones y advertencias del modelo.')
    rules = {'value': condition('quantity_kind', [scalar, maximum]),
             'minimum': condition('quantity_kind', interval),
             'maximum': condition('quantity_kind', interval)}
    c.setdefault('row_conditions', {'version': 1, 'fields': {}})['fields'][torque] = {
        'allowed_when': deepcopy(rules), 'required_when': deepcopy(rules)}
    c['roles']['grip_clamp_torque_nm'] = 'legacy'
    c['allowed_when']['grip_clamp_torque_nm'] = {'kind': 'never'}
    c['required_when']['grip_clamp_torque_nm'] = {'kind': 'never'}
    next(f for f in templates['grip']['fields'] if f['key'] ==
         'grip_clamp_torque_nm')['section_key'] = 'legacy'
    for family, key in [('pedal', 'pedal_thread'), ('seatpost', 'dropper_actuation')]:
        c_ = templates[family]['form_contract']
        assert c_['roles'][key] == 'legacy'
        c_['allowed_when'][key] = {'kind': 'never'}
        c_['required_when'][key] = {'kind': 'never'}
    templates['handlebar_covering']['form_contract']['helpers']['kit_members'] = (
        'Describe sólo el contenido incluido. Cada pieza conserva su marca, '
        'modelo y alcance; este texto no transfiere medidas de una pieza a otra.')

    # Re-read the exact 06/2014 OEM manual before moving its fixture to the new
    # owner. Keep both printed units; do not calculate one from the other.
    ergon = next(c_ for c_ in fixtures['cases'] if c_['id'] ==
                 'grip_ergon_gp1_rohloff_nexus_asymmetric_pair')
    assert ergon['values'].pop('grip_clamp_torque_nm') == '5'
    ergon['values'][torque] = rows(*[
        {'quantity_kind': scalar, 'value': value, 'unit': unit,
         'configuration': 'GP1, abrazaderas, manual ERG_MAN_GP1_06_2014',
         'conditions': 'No sobreapretar; seguir los requisitos de manubrio y montaje.',
         'source_url': 'https://www.ergonbike.com/infocenter/downloads/manual_gp1.pdf'}
        for value, unit in [('5', 'Nm'), ('3.7', 'ft-lb')]])
    ergon['root_reconciliation'].append(
        'Torque fixture moved from retired scalar after re-reading OEM page 2; '
        '5 Nm and 3.7 ft-lb remain separate printed declarations.')

    lock = {'grip_attachment': 'Lock-on (una abrazadera)'}
    fixtures['cases'].extend([
        case('cp_grip_different_measured_and_nominal', 'grip', {
            'grip_bar_nominal_diameter_mm': '22.2', 'grip_inner_diameter_mm': '21.9',
            reference: 'Medición sintética de pieza libre; no confirma ajuste'}),
        case('cp_grip_unscoped_measurement', 'grip', {'grip_inner_diameter_mm': '31.8'},
             pending=[('prerequisite_missing', 'grip_inner_diameter_mm')]),
        case('cp_odi_printed_torque_ranges', 'grip', {**lock, torque: rows(
            {'quantity_kind': interval, 'minimum': '4.5', 'maximum': '5.0',
             'unit': 'Nm', 'configuration': 'ODI Lock Jaw v2.1'},
            {'quantity_kind': interval, 'minimum': '40', 'maximum': '45',
             'unit': 'in-lb', 'configuration': 'ODI Lock Jaw v2.1'})},
             sources=['https://www.odigrips.com/pages/install']),
        case('cp_grip_reversed_torque_range', 'grip', {**lock, torque: rows(
            {'quantity_kind': interval, 'minimum': '5', 'maximum': '4.5',
             'unit': 'Nm', 'configuration': 'Synthetic clamp'})},
             blocking=[('row_shape', torque)]),
        case('cp_grip_torque_unit_missing', 'grip', {**lock, torque: rows(
            {'quantity_kind': maximum, 'value': '5',
             'configuration': 'Synthetic clamp'})}, pending=[('row_incomplete', torque)]),
        case('cp_grip_single_is_not_range', 'grip', {**lock, torque: rows(
            {'quantity_kind': scalar, 'value': '5', 'minimum': '4.5',
             'unit': 'Nm', 'configuration': 'Synthetic clamp'})},
             blocking=[('row_field_applicability', torque)]),
        case('cp_grip_attachment_unknown', 'grip', {torque: rows(
            {'quantity_kind': maximum, 'value': '5', 'unit': 'Nm',
             'configuration': 'Synthetic clamp'})},
             pending=[('field_applicability_pending', torque)]),
    ])
    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Contact points reviewed successor',
               'templates': list(templates.values()), 'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA},
               'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(templates), 'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in templates.values())}
    return catalog, fixtures


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'contact-points-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'contact-points-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
