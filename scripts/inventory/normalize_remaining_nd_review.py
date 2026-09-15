#!/usr/bin/env python3
"""Adjudicate the remaining ND packet; never infer identity from required cells."""
from copy import deepcopy as copy
import hashlib
import json

from compile_product_spec_catalog import RESEARCH
from product_spec_field_patches import artifact_sha

PACKET = 'remaining-non-drivetrain-addendum-review-2026-09-07.json'
SHA = 'fd78724798b4c83773e599d33e6705d51fb5298526743470f5a223f5f586d0e1'
BASE = 'all-family-contact-integrated-2026-09-07.json'
BASE_SHA = 'd7f8510ca112da4430f485720243ddde899daa097f39fb00aec49fe35027b7ca'


def write(name, value):
    (RESEARCH / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def predicate(field, value, value_type='token', operator=None):
    return {'field': field, 'operator': operator or ('in' if isinstance(value, list) else 'eq'),
            'value_type': value_type, 'value': value}


def when(*predicates):
    return {'kind': 'when', 'rows': [list(predicates)]}


def main():
    raw = (RESEARCH / PACKET).read_bytes()
    if hashlib.sha256(raw).hexdigest() != SHA:
        raise ValueError('Frozen ND packet changed')
    base = json.loads((RESEARCH / BASE).read_text())
    if artifact_sha(base) != BASE_SHA:
        raise ValueError('Adjudicated contact base changed')
    original = json.loads(raw)
    definitions = copy(original['new_definitions'])
    patches = copy(original['patches'])
    ts = {t['key']: t for t in base['templates']}
    decisions = {p['id']: {'patch_id': p['id'], 'decision': 'aceptar',
        'reason': 'Representación de campos; no identidad OEM ni aprobación mecánica.'} for p in patches}
    def add(patch, reason):
        patches.append(patch)
        decisions[patch['id']] = {'patch_id': patch['id'], 'decision': 'aceptar', 'reason': reason}
    def correct(p, reason):
        decisions[p['id']].update(decision='corregir', reason=reason, after_override=copy(p['after']))
    def field(template, key, order, condition=None, required=None, role='measurement'):
        add({'id': 'ROOT-RND-add-' + key, 'op': 'add_field', 'template': template, 'key': key,
            'before': None, 'after': {'field_entry': {'key': key, 'section_key': 'measurement',
                'sort_order': order, 'is_required': False, 'visibility_rules': [], 'option_rules': [], 'constraint_rules': []},
                'definition_used_by_append': template, 'roles': role, 'semantic_roles': 'compatibility',
                'allowed_when': condition or {'kind': 'always'}, 'required_when': required or {'kind': 'never'},
                'prerequisites': [], 'evidence_requirements': 'oem_spec'}}, 'Magnitud o alcance explícito, conservando faltantes como pendientes.')
    def label(key, value, reason):
        add({'id': 'ROOT-RND-label-' + key, 'op': 'replace_definition_label', 'template': None,
             'key': key, 'before': base['definitions'][key]['label'], 'after': value}, reason)
    def row_definition(key, name, columns):
        definitions[key] = {'key': key, 'origin': 'new', 'id': None, 'label': name,
            'data_type': 'json', 'unit': None, 'allowed_values': [], 'used_by': [],
            'validation_rules': {'rows_schema': {'version': 1, 'columns': columns}}}
    def row_patch(key, schema, reason):
        add({'id': 'ROOT-RND-schema-' + key, 'op': 'replace_unpublished_rows_schema',
             'template': None, 'key': key, 'before': base['definitions'][key]['validation_rules']['rows_schema'],
             'after': schema}, reason)
    def conditions(template, value):
        contract = ts[template]['form_contract']
        add({'id': 'ROOT-RND-conditions-' + template, 'op': 'replace_template_coherence',
             'template': template, 'key': 'row_conditions',
             'before': {'present': 'row_conditions' in contract, 'value': contract.get('row_conditions')},
             'after': value}, 'La condición se evalúa dentro de su propia configuración; no usa otra fila como evidencia.')

    # Required is not identity. Each proposed uniqueness key loses a legitimate scope.
    reasons = {
        'tool_capabilities': 'Operación y estándar no identifican miembro, medida, adaptador ni alcance de modelo.',
        'security_rating_configurations': 'ABUS 540 tiene Sold Secure Pedal Cycle Diamond y Powered Cycle Gold; falta el programa.',
        'bar_clamp_configurations': 'Igual diámetro y método pueden usar piezas diferentes; la ficha tampoco puede incluir otra variante del soporte.',
        'bag_member_configurations': 'El mismo miembro puede medirse cerrado o expandido; el nombre libre no identifica la configuración.',
        'co2_cartridge_configurations': 'Igual masa y roscado no identifican modelo, rosca ni condiciones de la contraparte.',
        'eyewear_lens_configurations': 'El modelo libre no identifica revisión, lente izquierda/derecha, tinte o condición de medición.',
        'nutrition_facts': 'Otro incluye nutrientes distintos; una porción declarada tampoco identifica su cantidad o preparación.',
    }
    for p in patches:
        if p['key'] in reasons and p['op'] == 'replace_unpublished_rows_schema':
            decisions[p['id']].update(decision='rechazar', reason=reasons[p['key']])

    # Express the pitch independently of the nominal diameter. Park explicitly
    # documents 36 mm x 24 TPI and 10 mm x 26 TPI; metric/imperial is not a brand.
    definitions['thread_pitch_system']['label'] = 'Forma declarada de expresar el paso'
    definitions['thread_pitch_system']['allowed_values'] = ['Paso en milímetros', 'Hilos por pulgada', 'Desconocido / sin confirmar']
    for p in patches:
        if p['key'] == 'thread_pitch_system':
            correct(p, 'Selector de expresión del paso, independiente de la unidad del diámetro nominal. No certifica equivalencia ni ajuste.')
        if p['key'] in ('thread_pitch_mm', 'thread_tpi'):
            unit = 'Paso en milímetros' if p['key'] == 'thread_pitch_mm' else 'Hilos por pulgada'
            p['after']['allowed_when']['rows'][0][-1]['value'] = unit
            p['before']['required_when'] = ts['fastener']['form_contract']['required_when'][p['key']]
            p['after']['required_when'] = copy(p['after']['allowed_when'])
            correct(p, 'Una expresión canónica por ficha; la fuente original conserva equivalencias. Sin selector permanece pendiente, no mecánicamente aprobado.')

    # Cage fit diameter is a different fact from the physical bottle envelope.
    label('bottle_diameter_mm', 'Diámetro de acople con portabidón de aro',
          'El campo compartido con portabidón describe la interfaz, no cualquier dimensión exterior.')
    row_definition('bottle_body_dimensions', 'Dimensiones físicas de la botella y su configuración', [
        {'key': 'dimension', 'label': 'Dimensión', 'type': 'token', 'required': True,
         'allowed_values': ['Ancho', 'Alto', 'Largo', 'Profundidad', 'Diámetro exterior']},
        {'key': 'value_mm', 'label': 'Medida', 'type': 'decimal', 'unit': 'mm', 'required': True, 'validation': {'positive': True}},
        {'key': 'configuration', 'label': 'Configuración medida', 'type': 'token', 'required': True,
         'allowed_values': ['Botella sola', 'Botella con base incluida', 'Otra']},
        {'key': 'datum', 'label': 'Referencia exacta de la medida', 'type': 'text', 'required': True},
        {'key': 'source_url', 'label': 'Fuente', 'type': 'url'},
    ])
    field('bottle', 'bottle_body_dimensions', 310)

    # A gauge range, rated working pressure and delivered CO2 estimate are not
    # interchangeable. A pump/inflator can publish more than one of them.
    pressure_patch = next(p for p in patches if p['id'] == 'RND-ND17-max_pressure-gate')
    pressure_patch['before'] = {'roles': ts['pump']['form_contract']['roles']['max_pressure_psi']}
    pressure_patch['after'] = {'roles': 'legacy'}
    correct(pressure_patch, 'Se conserva el escalar sin alcance como legacy; las cifras nuevas declaran magnitud, unidad y configuración. No se veta CO2 por no bombear.')
    pressure_kinds = ['Máximo de bombeo declarado', 'Máximo de trabajo declarado',
                      'Fondo de escala del manómetro', 'Presión orientativa CO2 para la configuración indicada']
    row_definition('pump_pressure_specifications', 'Presiones declaradas y su alcance', [
        {'key': 'quantity_kind', 'label': 'Magnitud declarada', 'type': 'token', 'required': True, 'allowed_values': pressure_kinds},
        {'key': 'value', 'label': 'Presión', 'type': 'decimal', 'required': True, 'validation': {'positive': True}},
        {'key': 'unit', 'label': 'Unidad declarada', 'type': 'token', 'required': True, 'allowed_values': ['psi', 'bar']},
        {'key': 'configuration', 'label': 'Modo, dispositivo o configuración a que corresponde', 'type': 'text', 'required': True},
        {'key': 'target_tire', 'label': 'Neumático objetivo declarado', 'type': 'text'},
        {'key': 'cartridge_gas_g', 'label': 'Masa de gas del cartucho', 'type': 'decimal', 'unit': 'g', 'validation': {'positive': True}},
        {'key': 'tires_inflated', 'label': 'Neumáticos inflados con ese cartucho', 'type': 'integer', 'validation': {'positive': True}},
        {'key': 'conditions', 'label': 'Condiciones publicadas', 'type': 'text'},
        {'key': 'source_url', 'label': 'Fuente', 'type': 'url'},
    ])
    field('pump', 'pump_pressure_specifications', 310)
    pump_rules = copy(ts['pump']['form_contract']['row_conditions'])
    co2 = when(predicate('quantity_kind', pressure_kinds[-1]))
    pump_rules['fields']['pump_pressure_specifications'] = {
        'allowed_when': {key: co2 for key in ('target_tire', 'cartridge_gas_g', 'tires_inflated')},
        'required_when': {key: co2 for key in ('target_tire', 'cartridge_gas_g', 'tires_inflated', 'conditions')}}
    conditions('pump', pump_rules)
    schema = copy(base['definitions']['co2_cartridge_configurations']['validation_rules']['rows_schema'])
    next(c for c in schema['columns'] if c['key'] == 'counterpart_model')['label'] = 'Modelo exacto de la contraparte declarada'
    row_patch('co2_cartridge_configurations', schema, 'En una ficha de inflador la contraparte puede ser un cartucho; no se fija al nombre de otra familia.')

    # A rating has a programme; the same issuer can award different ratings.
    schema = copy(base['definitions']['security_rating_configurations']['validation_rules']['rows_schema'])
    schema['columns'].append({'key': 'rating_scheme', 'label': 'Programa o categoría de la clasificación', 'type': 'text'})
    row_patch('security_rating_configurations', schema, 'Sold Secure clasifica el mismo componente en programas distintos; no se deduplica por emisor.')
    conditions('lock', {'version': 1, 'fields': {'security_rating_configurations': {
        'required_when': {'rating_scheme': when(predicate('issuer', 'Sold Secure'))}}}})

    # An alternate SKU is not a mounting configuration of the current SKU.
    schema = copy(base['definitions']['bar_clamp_configurations']['validation_rules']['rows_schema'])
    next(c for c in schema['columns'] if c['key'] == 'fit_method')['allowed_values'].remove('Variante / versión distinta')
    next(c for c in schema['columns'] if c['key'] == 'spacer_or_variant')['label'] = 'Pieza de adaptación declarada'
    next(c for c in schema['columns'] if c['key'] == 'mount_revision')['label'] = 'Revisión de esta montura o soporte'
    row_patch('bar_clamp_configurations', schema, 'La variante física pertenece a identidad; una tabla de montajes no combina SKUs de un modelo.')
    rules = copy(ts['accessory_mount']['form_contract']['row_conditions'])
    rules['fields']['bar_clamp_configurations']['required_when']['spacer_or_variant'] = when(
        predicate('fit_method', ['Con espaciador incluido', 'Con espaciador opcional']))
    conditions('accessory_mount', rules)

    # Construction and intended audience already have independent owners.
    p = next(p for p in patches if p['id'] == 'RND-ND18-helmet_kind-options')
    p['after'] = ['Urbano', 'MTB / trail', 'Enduro', 'Ruta', 'Otro']
    correct(p, 'Se retiran público y construcción de este eje; Integral sigue en helmet_construction y Niño en intended_audience.')
    label('helmet_kind', 'Uso declarado del casco', 'No se mezcla uso, público y construcción de carcasa.')

    # Patch corrections must carry the normalized complete postimage.
    for d in decisions.values():
        if d['decision'] == 'corregir':
            d['after_override'] = copy(next(p for p in patches if p['id'] == d['patch_id'])['after'])
    proposal = {'schema_version': 1, 'new_definitions': definitions, 'patches': patches,
                'source_packet_sha256': SHA, 'approval_scope': 'field_representation'}
    decision = {'schema_version': 1, 'approval_scope': 'field_representation',
        'base_sha256': BASE_SHA, 'proposal_file': 'remaining-nd-normalized-patches-2026-09-07.json',
        'proposal_sha256': artifact_sha(proposal), 'source_hashes': {PACKET: SHA, BASE: BASE_SHA},
        'patch_adjudications': list(decisions.values()), 'mechanical_coverage_complete': False,
        'automatic_fill_authorized': False, 'product_writes': 0}
    cases = []
    for source in original['fixtures']:
        c = {'id': 'rnd_' + source['id'], 'template': source['template'], 'values': copy(source['values']),
             'kind': 'synthetic_representation', 'note': source.get('note', ''),
             'expected_blocking': [], 'automatic_fill_authorized': False, 'facts_verified_for_product': False}
        v = c['values']
        if 'thread_pitch_system' in v:
            v['thread_pitch_system'] = {'Métrico (paso en mm)': 'Paso en milímetros',
                'Imperial (hilos por pulgada)': 'Hilos por pulgada'}.get(v['thread_pitch_system'], v['thread_pitch_system'])
        if source['id'] == 'RF2':
            c['expected_blocking'] = [{'code': 'field_applicability', 'field': 'thread_tpi'}]
        if source['id'] == 'RF7':
            c['expected_blocking'] = [{'code': 'field_applicability', 'field': 'bottle_diameter_mm'}]
        if source['id'] in ('RF4', 'RF13', 'RF15'):
            c['kind'] = 'unresolved_semantic_gap'
            c['note'] = 'Persiste el conflicto documental: no se sustituye por una identidad que rechace configuraciones válidas. No habilita llenado.'
        if source['id'] == 'RF8':
            c['note'] = 'El escalar anterior se conserva como legacy; no expresa la presión canónica con alcance.'
        if source['id'] == 'RF9':
            v['co2_cartridge_configurations']['rows'][0]['values']['configuration_kind'] = 'Cartucho de esta presentación'
            c['note'] = 'Valores sintéticos para transporte y campos; no acredita rosca, peso ni contenido de un SKU OEM.'
        if source['id'] == 'RF11':
            v['helmet_construction'] = v.pop('helmet_kind')
            v['certification_configurations']['rows'][0]['values']['evidence_kind'] = 'Etiqueta observada en la unidad'
            c['note'] = 'Ejemplo sintético; no se afirma haber observado la etiqueta de un producto real.'
        for row in v.get('nutrition_facts', {}).get('rows', []):
            row['values']['nutrient'] = 'Carbohidratos (g)'
            if row['values'].get('basis') == 'Por porción declarada':
                row['values'].update(basis_amount='60', basis_unit='g')
        cases.append(c)
    def rows(*values):
        return {'schema_version': 1, 'rows': [{'id': 'r' + str(i), 'values': v, 'sources': []}
                                            for i, v in enumerate(values, 1)]}
    def case(key, template, values, blocking=None, pending=None, note='Contraejemplo de representación; no aprobación de producto.'):
        c = {'id': 'rnd_root_' + key, 'template': template, 'values': values,
             'kind': 'synthetic_representation', 'note': note, 'expected_blocking': blocking or [],
             'automatic_fill_authorized': False, 'facts_verified_for_product': False}
        if pending:
            c['expected_issue_subset'] = [dict(i, blocking=False) for i in pending]
        cases.append(c)
    case('metric_diameter_tpi_pitch', 'fastener', {'fastener_kind': 'Otro', 'thread': '36 mm',
         'thread_pitch_system': 'Hilos por pulgada', 'thread_tpi': '24'},
         note='Park documenta 36 mm × 24 TPI; prueba ejes independientes, no identidad de pieza en inventario.')
    case('pitch_selected_missing_value', 'fastener', {'fastener_kind': 'Perno', 'thread': 'M5',
         'thread_pitch_system': 'Paso en milímetros'}, pending=[{'code': 'required_missing', 'field': 'thread_pitch_mm'}])
    case('twist_physical_envelope', 'bottle', {'bottle_retention_system': 'FIDLOCK TWIST',
        'bottle_body_dimensions': rows({'dimension': 'Ancho', 'value_mm': '76', 'configuration': 'Botella con base incluida',
          'datum': 'Ancho del conjunto bottle 800 + bike base, plantilla OEM 1:1'})},
        note='Fidlock publica dimensiones del conjunto; medir el exterior no lo convierte en compatible con un aro.')
    case('co2_gauge_scale', 'pump', {'pump_kind': 'Inflador CO2', 'pump_pressure_specifications': rows({
         'quantity_kind': pressure_kinds[2], 'value': '160', 'unit': 'psi', 'configuration': 'Manómetro AirBooster G2'})},
         note='Topeak: el manómetro lee hasta 160 psi. No es promesa de presión final del neumático.')
    case('co2_estimate_incomplete', 'pump', {'pump_kind': 'Inflador CO2', 'pump_pressure_specifications': rows({
         'quantity_kind': pressure_kinds[3], 'value': '100', 'unit': 'psi', 'configuration': 'Estimación sin neumático/cartucho confirmado'})},
         pending=[{'code': 'row_required_missing', 'field': 'pump_pressure_specifications'}])
    case('co2_estimate_scoped', 'pump', {'pump_kind': 'Inflador CO2', 'pump_pressure_specifications': rows({
         'quantity_kind': pressure_kinds[3], 'value': '100', 'unit': 'psi', 'configuration': 'Tabla Topeak CO2 INFLATOR 2021-03',
         'target_tire': 'ROAD 700C x 25', 'cartridge_gas_g': '16', 'tires_inflated': '1',
         'conditions': 'Valor orientativo de la tabla; respetar límites del neumático y aro'})})
    case('gauge_is_not_co2_estimate', 'pump', {'pump_kind': 'Inflador CO2', 'pump_pressure_specifications': rows({
         'quantity_kind': pressure_kinds[2], 'value': '160', 'unit': 'psi', 'configuration': 'Escala del manómetro',
         'cartridge_gas_g': '16'})}, blocking=[{'code': 'row_field_applicability', 'field': 'pump_pressure_specifications'}])
    rating = {'component': 'U / arco', 'issuer': 'Sold Secure', 'component_model': 'GRANIT XPlus 540'}
    case('two_security_programmes', 'lock', {'lock_kind': 'U-lock', 'security_rating_configurations': rows(
         dict(rating, level='Diamond', rating_scheme='Pedal Cycle'),
         dict(rating, level='Gold', rating_scheme='Powered Cycle'))}, note='ABUS declara ambos programas para el mismo candado; no se deduplica por emisor.')
    case('security_programme_missing', 'lock', {'security_rating_configurations': rows(dict(rating, level='Diamond'))},
         pending=[{'code': 'row_required_missing', 'field': 'security_rating_configurations'}])
    capability = {'operation': 'Extraer', 'target_standard': 'Interfaz declarada', 'supported': True}
    case('tool_distinct_scope', 'workshop_tool', {'tool_capabilities': rows(
         dict(capability, brand_scope='Modelo A'), dict(capability, brand_scope='Modelo B', supported=False))})
    member = {'member': 'Compartimento superior', 'position': 'Superior'}
    case('bag_expansion_states', 'bike_bag', {'bag_member_configurations': rows(
         dict(member, configuration='Cerrado', height_mm='215'),
         dict(member, configuration='Expandido', height_mm='290'))}, note='Topeak TT9635B publica una altura variable; el nombre del miembro no identifica el estado medido.')
    cartridge = {'configuration_kind': 'Cartucho compatible declarado', 'gas_mass_g': '16', 'threaded': True, 'thread_designation': 'Declaración sintética de rosca'}
    case('two_cartridge_counterparts', 'pump', {'pump_kind': 'Inflador CO2', 'co2_cartridge_configurations': rows(
         dict(cartridge, counterpart_model='Cartucho A'), dict(cartridge, counterpart_model='Cartucho B'))})
    nutrition = {'nutrient': 'Otro', 'amount_unit': 'mg', 'basis': 'Por 100 g'}
    case('two_other_nutrients', 'food_beverage', {'nutrition_facts': rows(
         dict(nutrition, nutrient_name='Potasio', amount='100'), dict(nutrition, nutrient_name='Calcio', amount='50'))})
    nutrition = {'nutrient': 'Carbohidratos (g)', 'basis': 'Por porción declarada', 'basis_unit': 'g'}
    case('two_serving_sizes', 'food_beverage', {'nutrition_facts': rows(
         dict(nutrition, basis_amount='30', amount='20', serving_reference='Porción pequeña'),
         dict(nutrition, basis_amount='60', amount='40', serving_reference='Porción grande'))})
    case('lens_same_name_distinct_scope', 'eyewear', {'eyewear_lens_configurations': rows(
         {'model': 'Lente gris', 'conditions': 'Lente izquierda de este par', 'polarized': True},
         {'model': 'Lente gris', 'conditions': 'Lente derecha de este par', 'polarized': True})})
    case('helmet_child_full_face', 'helmet', {'helmet_kind': 'Enduro', 'helmet_construction': 'Integral', 'intended_audience': 'Niño / juvenil'})
    case('helmet_construction_in_wrong_axis', 'helmet', {'helmet_kind': 'Integral'}, blocking=[{'code': 'option', 'field': 'helmet_kind'}])
    # JSON row numbers use the existing exact-decimal string transport.
    all_definitions = dict(base['definitions'], **definitions)
    for c in cases:
        for key, value in c['values'].items():
            schema = all_definitions.get(key, {}).get('validation_rules', {}).get('rows_schema')
            if schema and isinstance(value, dict):
                numeric = {col['key'] for col in schema['columns'] if col['type'] in ('decimal', 'integer')}
                for row in value['rows']:
                    for col in numeric & row['values'].keys():
                        if type(row['values'][col]) in (int, float):
                            row['values'][col] = str(row['values'][col])
    fixture = {'schema_version': 1, 'cases': cases, 'automatic_fill_authorized': False}
    decision['cases_sha256'] = artifact_sha(fixture)
    write('remaining-nd-representation-cases-2026-09-07.json', fixture)
    write(decision['proposal_file'], proposal)
    write('remaining-nd-root-decisions-2026-09-07.json', decision)
    print(json.dumps({'patches': len(patches), 'rejected': sum(d['decision'] == 'rechazar' for d in decisions.values()),
                      'new_definitions': len(definitions), 'proposal_sha256': artifact_sha(proposal)}))


if __name__ == '__main__':
    main()
