#!/usr/bin/env python3
"""Compile a successor for fourteen unpublished families; no DB writes.

The frozen all-family proposal stays immutable. Corrections here are scoped to
these templates; published shared definitions retain their existing identities.
"""
from copy import deepcopy
import hashlib
import json
import uuid

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_product_spec_catalog import validate_contract

FAMILIES = ('workshop_tool', 'light', 'cycle_computer', 'consumer_electronics',
            'accessory_mount', 'rack_basket', 'fender', 'kickstand', 'bike_bag',
            'rider_bag', 'training_wheel', 'bike_protection', 'eyewear', 'pump')
WHEEL_FAMILIES = ('rack_basket', 'fender', 'kickstand', 'training_wheel')
PREFIX = 'mobility-accessories'


def condition(field, value, value_type='token'):
    return {'kind': 'when', 'rows': [[{
        'field': field, 'operator': 'in' if isinstance(value, list) else 'eq',
        'value_type': value_type, 'value': value}]]}


def new_definition(key, label, kind, families, *, unit=None, options=(), rules=None):
    return {'key': key, 'id': str(uuid.uuid5(uuid.NAMESPACE_URL,
            'vinabike:spec-definition:' + key)), 'origin': 'new', 'label': label,
            'data_type': kind, 'unit': unit, 'allowed_values': list(options),
            'validation_rules': rules or {}, 'used_by': list(families)}


def add_field(template, key, role, semantic, *, allowed=None, required=None,
              evidence='oem_or_package', helper=None):
    fields = template['fields']
    if any(f['key'] == key for f in fields):
        raise ValueError('Field already present: ' + key)
    fields.append({'key': key, 'section_key': role,
                   'sort_order': max(f['sort_order'] for f in fields) + 10,
                   'is_required': False, 'visibility_rules': [],
                   'option_rules': [], 'constraint_rules': []})
    c = template['form_contract']
    for name, value in [('roles', role), ('semantic_roles', semantic),
                        ('allowed_when', allowed or {'kind': 'always'}),
                        ('required_when', required or {'kind': 'never'}),
                        ('evidence_requirements', evidence)]:
        c.setdefault(name, {})[key] = deepcopy(value)
    if helper:
        c.setdefault('helpers', {})[key] = helper


def remove_unpublished_field(template, key):
    template['fields'] = [f for f in template['fields'] if f['key'] != key]
    c = template['form_contract']
    for section in ('roles', 'semantic_roles', 'labels', 'allowed_when',
                    'required_when', 'allowed_options', 'prerequisites',
                    'helpers', 'evidence_requirements'):
        c.get(section, {}).pop(key, None)


def rows(*values):
    return {'schema_version': 1, 'rows': [
        {'id': 'r' + str(i + 1), 'values': value, 'sources': []}
        for i, value in enumerate(values)]}


def case(id_, family, values, *, blocking=(), pending=(), sources=()):
    result = {'id': id_, 'template': family, 'values': values,
              'expected_blocking': [{'code': code, 'field': field}
                                    for code, field in blocking],
              'facts_verified_for_product': False,
              'automatic_fill_authorized': False,
              'kind': 'synthetic_representation', 'source_urls': list(sources)}
    if pending:
        result['expected_issue_subset'] = [
            {'code': {'field_applicability_pending': 'prerequisite',
                      'prerequisite_missing': 'prerequisite'}.get(code, code),
             'field': field, 'blocking': False}
            for code, field in pending]
        result['expected_sql_issue_subset'] = [
            {'code': {'field_applicability_pending': 'field_applicability'}.get(code, code),
             'field': field, 'blocking': False} for code, field in pending]
    return result


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen input drift: ' + str(path))
    base = json.loads(CATALOG.read_text())
    templates = {t['key']: deepcopy(t) for t in base['templates']
                 if t['key'] in FAMILIES}
    definitions = deepcopy(base['definitions'])
    fixtures = json.loads(CASES.read_text())
    fixtures['cases'] = [c for c in fixtures['cases'] if c['template'] in FAMILIES]

    # Numeric order has meaning only within the stated nominal unit. Neither
    # a marketing label nor this declaration certifies clearance or fitment.
    wheel = 'wheel_size_declarations'
    literal, interval, bsd = ('Designación nominal',
                              'Rango nominal en pulgadas', 'Diámetro BSD')
    definitions[wheel] = new_definition(
        wheel, 'Medidas de rueda declaradas', 'json', WHEEL_FAMILIES,
        rules={'rows_schema': {'version': 1,
            'ordered_pairs': [['min_in', 'max_in']], 'columns': [
                {'key': 'kind', 'label': 'Forma de la declaración',
                 'type': 'token', 'required': True,
                 'allowed_values': [literal, interval, bsd]},
                {'key': 'designation', 'label': 'Designación publicada', 'type': 'text'},
                {'key': 'min_in', 'label': 'Mínimo nominal', 'type': 'decimal',
                 'unit': 'in', 'validation': {'positive': True}},
                {'key': 'max_in', 'label': 'Máximo nominal', 'type': 'decimal',
                 'unit': 'in', 'validation': {'positive': True}},
                {'key': 'bsd_mm', 'label': 'Diámetro de asiento BSD',
                 'type': 'integer', 'unit': 'mm', 'validation': {'positive': True}},
                {'key': 'conditions', 'label': 'Condiciones declaradas', 'type': 'text'},
                {'key': 'source_url', 'label': 'Fuente', 'type': 'url'},
            ]}})
    column_conditions = {'designation': condition('kind', literal),
                         'min_in': condition('kind', interval),
                         'max_in': condition('kind', interval),
                         'bsd_mm': condition('kind', bsd)}
    for family in WHEEL_FAMILIES:
        t = templates[family]
        for key in ('nominal_wheel_size_min', 'nominal_wheel_size_max'):
            remove_unpublished_field(t, key)
        add_field(t, wheel, 'measurement', 'compatibility',
                  required={'kind': 'always' if family == 'training_wheel' else 'never'},
                  helper='Copia las medidas declaradas por el fabricante. Una lista '
                  'usa una fila por designación; un rango sólo se registra si fue '
                  'publicado como tal. No convierte tamaños nominales a BSD ni '
                  'certifica por sí solo el montaje, la carga o la holgura.')
        t['form_contract'].setdefault('row_conditions', {'version': 1, 'fields': {}})[
            'fields'][wheel] = {'allowed_when': deepcopy(column_conditions),
                               'required_when': deepcopy(column_conditions)}
        fixtures['cases'].extend([
            case('ma_wheel_range_' + family, family, {wheel: rows(
                {'kind': interval, 'min_in': '20', 'max_in': '29'})}),
            case('ma_wheel_reversed_' + family, family, {wheel: rows(
                {'kind': interval, 'min_in': '29', 'max_in': '20'})},
                blocking=[('row_shape', wheel)]),
            case('ma_wheel_incomplete_' + family, family, {wheel: rows(
                {'kind': interval, 'min_in': '20'})},
                pending=[('row_required_missing', wheel)]),
            case('ma_wheel_discrete_' + family, family, {wheel: rows(
                {'kind': literal, 'designation': '700C'},
                {'kind': literal, 'designation': '29"'})}),
            case('ma_wheel_mixed_axis_' + family, family, {wheel: rows(
                {'kind': literal, 'designation': '700C', 'min_in': '29'})},
                blocking=[('row_field_applicability', wheel)]),
        ])

    for family in ('light', 'fender', 'training_wheel'):
        templates[family]['form_contract']['helpers']['kit_members'] = (
            'Describe el contenido incluido. La marca y el modelo son los '
            'declarados para cada pieza; sus medidas y certificaciones '
            'deben conservar su propio alcance.')

    # A hybrid is still a mini pump. The extra capability is independent of
    # its format and of which cartridge happens to be included in the box.
    pump = templates['pump']
    cap = 'co2_inflation_capable'
    non_dedicated = [v for v in definitions['pump_kind']['allowed_values']
                     if v not in ('Inflador CO2', 'Cartucho CO2 (recarga)')]
    definitions[cap] = new_definition(cap, 'También permite inflar con CO₂',
                                      'boolean', ['pump'])
    add_field(pump, cap, 'primary', 'intrinsic',
              allowed=condition('pump_kind', non_dedicated),
              helper='Capacidad adicional declarada para este modelo. No se '
              'deduce de un cartucho incluido ni se confirma al dejarlo vacío.')
    co2 = pump['form_contract']['allowed_when']['co2_cartridge_configurations']
    co2['rows'].append(condition(cap, True, 'boolean')['rows'][0])
    fixtures['cases'].extend([
        case('ma_hybrid_pump', 'pump', {'pump_kind': 'De mano / mini', cap: True,
             'co2_cartridge_configurations': rows({'configuration_kind':
             'Cartucho de esta presentación', 'gas_mass_g': '16',
             'threaded': True, 'included_quantity': '1'})},
             sources=['https://www.topeak.com/global/en/product/407-HYBRIDROCKET-HP']),
        case('ma_manual_without_co2', 'pump', {'pump_kind': 'De mano / mini', cap: False,
             'co2_cartridge_configurations': rows({'configuration_kind':
             'Cartucho compatible declarado', 'gas_mass_g': '16',
             'threaded': True, 'counterpart_model': 'Synthetic cartridge'})},
             blocking=[('field_applicability', 'co2_cartridge_configurations')]),
        case('ma_pump_capability_unknown', 'pump', {'pump_kind': 'De mano / mini',
             'co2_cartridge_configurations': rows({'configuration_kind':
             'Cartucho compatible declarado', 'gas_mass_g': '16',
             'threaded': True, 'counterpart_model': 'Synthetic cartridge'})},
             pending=[('field_applicability_pending', 'co2_cartridge_configurations')]),
        case('ma_dedicated_has_one_capability_owner', 'pump',
             {'pump_kind': 'Inflador CO2', cap: False},
             blocking=[('field_applicability', cap)]),
    ])

    bag = templates['rider_bag']
    waist = 'Riñonera / bolso de cintura'
    definitions['bag_kind']['allowed_values'].append(waist)
    bag['form_contract']['allowed_when']['volume_l']['rows'][0][0]['value'].append(waist)
    bag_forms = [v for v in definitions['bag_kind']['allowed_values'] if v != 'Cubre-mochila']
    included = 'reservoir_included'
    definitions[included] = new_definition(included, 'Incluye depósito de hidratación',
                                          'boolean', ['rider_bag'])
    add_field(bag, included, 'contents', 'contents',
              allowed=condition('bag_kind', bag_forms),
              helper='Contenido de esta presentación. La compatibilidad con un '
              'depósito opcional no significa que venga incluido.')
    reservoir_allowed = condition(included, True, 'boolean')
    reservoir_allowed['rows'][0].extend(condition('bag_kind', bag_forms)['rows'][0])
    bag['form_contract']['allowed_when']['reservoir_l'] = reservoir_allowed
    bag['form_contract']['labels']['reservoir_l'] = 'Capacidad del depósito incluido'
    bag['form_contract']['helpers']['reservoir_l'] = (
        'Capacidad del depósito entregado, según esta presentación. No es la '
        'capacidad del compartimento ni la de un depósito que se compra aparte.')
    definitions['reservoir_l']['validation_rules'] = {'positive': True}
    fixtures['cases'].extend([
        case('ma_waist_hydration', 'rider_bag', {'bag_kind': waist,
             included: True, 'reservoir_l': '1.5'}, sources=[
             'https://www.camelbak.com/product/m.u.l.e.%C2%AE-5-waist-pack-with-crux%C2%AE-1.5l-lumbar-reservoir/CB-2815.html']),
        case('ma_reservoir_not_included', 'rider_bag', {'bag_kind': waist,
             included: False, 'reservoir_l': '1.5'},
             blocking=[('field_applicability', 'reservoir_l')]),
        case('ma_reservoir_inclusion_unknown', 'rider_bag', {'bag_kind': waist,
             'reservoir_l': '1.5'},
             pending=[('field_applicability_pending', 'reservoir_l')]),
        case('ma_cover_is_not_reservoir', 'rider_bag',
             {'bag_kind': 'Cubre-mochila', included: True, 'reservoir_l': '1.5'},
             blocking=[('field_applicability', 'reservoir_included'),
                       ('field_applicability', 'reservoir_l')]),
    ])

    # Quantity basis and package scope are orthogonal; a single token mixing
    # cargo/total with per-unit/per-set would allow only half the declaration.
    for key, label, options in [
        ('volume_basis', 'Qué incluye la capacidad declarada',
         ['Sólo carga', 'Carga e hidratación', 'Desconocido / sin confirmar']),
        ('volume_scope', 'A qué corresponde la capacidad declarada',
         ['Producto completo tal como se vende', 'Una unidad del conjunto',
          'Desconocido / sin confirmar']),
    ]:
        definitions[key] = new_definition(key, label, 'single_select',
                                          ['bike_bag', 'rider_bag'], options=options)
        for family in ('bike_bag', 'rider_bag'):
            t = templates[family]
            add_field(t, key, 'declaration', 'declaration',
                      allowed=deepcopy(t['form_contract']['allowed_when']['volume_l']),
                      helper='Conserva el alcance publicado; no lo deduce del nombre '
                      'del modelo ni suma o resta capacidades.')
            t['form_contract'].setdefault('prerequisites', {}).setdefault(
                'volume_l', []).append(key)
    for family in ('bike_bag', 'rider_bag'):
        templates[family]['form_contract']['helpers']['volume_l'] = (
            'Capacidad principal declarada por el fabricante con base y alcance. '
            'No suma piezas ni resta el depósito. Los miembros de un conjunto '
            'conservan sus propias declaraciones en sus filas.')
        fixtures['cases'].extend([
            case('ma_volume_scope_' + family, family, {
                **({'bag_kind': waist} if family == 'rider_bag' else {}),
                'volume_l': '5', 'volume_basis': 'Sólo carga',
                'volume_scope': 'Producto completo tal como se vende'}),
            case('ma_volume_unknown_' + family, family, {'volume_l': '5'},
                 pending=[('prerequisite_missing', 'volume_l')]),
        ])

    # No already-published template uses this legacy scalar. Preserve any old
    # draft data as legacy, but mark it unreachable for new scalar consumers.
    for family in ('pump', 'workshop_tool'):
        t = templates[family]
        c = t['form_contract']
        c['roles']['max_pressure_psi'] = 'legacy'
        c['allowed_when']['max_pressure_psi'] = {'kind': 'never'}
        c['required_when']['max_pressure_psi'] = {'kind': 'never'}
        next(f for f in t['fields'] if f['key'] == 'max_pressure_psi')['section_key'] = 'legacy'
    tool_pressure = 'tool_pressure_specifications'
    definitions[tool_pressure] = new_definition(
        tool_pressure, 'Presiones declaradas de la herramienta', 'json', ['workshop_tool'],
        rules={'rows_schema': {'version': 1, 'columns': [
            {'key': 'quantity_kind', 'label': 'Magnitud declarada', 'type': 'token',
             'required': True, 'allowed_values': [
                 'Máximo de trabajo declarado', 'Máximo de entrada declarado',
                 'Fondo de escala del manómetro', 'Otra presión declarada']},
            {'key': 'value', 'label': 'Presión', 'type': 'decimal', 'required': True,
             'validation': {'positive': True}},
            {'key': 'unit', 'label': 'Unidad publicada', 'type': 'token',
             'required': True, 'allowed_values': ['psi', 'bar']},
            {'key': 'configuration', 'label': 'Dispositivo o configuración',
             'type': 'text', 'required': True},
            {'key': 'conditions', 'label': 'Condiciones publicadas', 'type': 'text'},
            {'key': 'source_url', 'label': 'Fuente', 'type': 'url'},
        ]}})
    add_field(templates['workshop_tool'], tool_pressure, 'measurement', 'declaration',
              helper='Guarda cada unidad como fue publicada para esa magnitud '
              'y configuración. El fondo de escala no demuestra la presión '
              'máxima de trabajo; no convierte ni sustituye valores OEM.')
    fixtures['cases'].extend([
        case('ma_tool_printed_units', 'workshop_tool', {tool_pressure: rows(
            {'quantity_kind': 'Fondo de escala del manómetro', 'value': '160',
             'unit': 'psi', 'configuration': 'Manómetro INF-2'},
            {'quantity_kind': 'Fondo de escala del manómetro', 'value': '11',
             'unit': 'bar', 'configuration': 'Manómetro INF-2'})},
            sources=['https://www.parktool.com/en-us/product/shop-inflator-inf-2']),
        case('ma_tool_missing_unit', 'workshop_tool', {tool_pressure: rows(
            {'quantity_kind': 'Máximo de trabajo declarado', 'value': '11',
             'configuration': 'Synthetic tool'})},
            pending=[('row_incomplete', tool_pressure)]),
    ])

    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {key: definitions[key] for key in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Mobility and accessories reviewed successor',
               'templates': list(templates.values()), 'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA},
               'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(templates), 'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in templates.values())}
    return catalog, fixtures


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / (PREFIX + '-catalog-2026-09-07.json')
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / (PREFIX + '-cases-2026-09-07.json'), fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
