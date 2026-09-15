"""Source and ownership corrections to the original-brakes candidate.

Rows describe a component, configuration or approval; a different source URL
never creates a second physical object. Park's current pad/rotor articles and
the TRP HY/RD manual are available; see existing-brakes-root-decisions.
"""
from copy import deepcopy

from compile_mobility_accessories_catalog import case, condition, rows
from compile_wheel_small_parts_catalog import column, retire

SOURCE = 'https://example.invalid/brake-root-fixture'
SOURCE_B = 'https://example.invalid/another-paragraph'


def adjust_catalog(definitions, templates):
    _assembly_member_scopes(definitions, templates)
    for template in templates.values():
        c = template['form_contract']
        drivers = {term['field'] for section in ('allowed_when', 'required_when')
                   for rule in c.get(section, {}).values()
                   for clause in rule.get('rows', []) for term in clause}
        for key in drivers:
            if c['roles'].get(key) != 'legacy':
                c['required_when'][key] = deepcopy(c.get('allowed_when', {}).get(key, {'kind': 'always'}))

    identities = {
        'brake_assembly_configurations': [['circuit_id', 'position']],
        'brake_circuit_connections': [['configuration_row_id', 'component_role', 'end_role']],
        'brake_bleed_ports': [['component_role', 'port_id']],
        'brake_model_fluid_approvals': [['system_brand', 'system_model', 'generation', 'fluid_class', 'fluid_product']],
        'compatible_caliper_models': [['brand', 'model', 'generation', 'variant']],
    }
    for key, groups in identities.items():
        if definitions[key]['origin'] != 'new':
            raise ValueError('Cannot change a published brake row definition: ' + key)
        schema = definitions[key]['validation_rules']['rows_schema']
        schema['unique_by'] = groups
        for c in schema['columns']:
            if c['key'] == 'generation' or (key == 'compatible_caliper_models' and c['key'] == 'variant'):
                c['required'] = True
    # A numeric rotor size and a source paragraph cannot identify a mounting
    # recipe: the same diameter may have multiple explicitly documented setups.
    for key in ('rotor_size_recipe', 'rim_brake_mount_fitments'):
        if definitions[key]['origin'] != 'new':
            raise ValueError('Cannot change a published mounting definition')
        schema = definitions[key]['validation_rules']['rows_schema']
        schema['columns'].insert(0, column('configuration', 'Montaje documentado', required=True))
        schema['unique_by'] = [['configuration', 'position']]

    for template in templates.values():
        c = template['form_contract']
        if 'brake_model_fluid_approvals' in c.get('row_conditions', {}).get('fields', {}):
            rule = c['row_conditions']['fields']['brake_model_fluid_approvals']
            rule.setdefault('required_when', {})['fluid_product'] = condition('fluid_class', 'Aceite Mineral')
        if 'brake_model_fluid_approvals' in c['roles']:
            c['helpers']['brake_model_fluid_approvals'] = (
                'Aprobación del modelo y edición concretos. La clase mineral '
                'por sí sola no identifica un aceite autorizado; se conserva '
                'su especificación/producto OEM. Otra URL no crea otro sistema.')
    # Literal OEM wording is evidence even if its material class is unknown.
    # Do not require the researcher to guess a class before recording a label.
    pad = templates['brake_pad']['form_contract']
    pad['allowed_when']['brake_pad_oem_compound'] = condition('braking_surface', 'Disco')
    pad['helpers']['brake_pad_oem_compound'] = (
        'Nombre literal del compuesto que publica el fabricante para esta '
        'variante. Puede registrarse aunque su clase técnica siga sin confirmar.')
    rotor = templates['rotor']['form_contract']
    rotor['allowed_when']['pad_compound_restriction'] = {'kind': 'always'}
    rotor['helpers']['pad_compound_restriction'] = (
        'Restricción explícita del modelo y edición de este rotor; no se '
        'deduce del metal de la pista ni de su marca.')
    # Park distinguishes the bolt/lockring drive, including two lockring
    # interfaces and adapters. A scalar on the rotor identifies none of those
    # physical parts. Preserve historical text, but never promote it into a
    # property or a compatibility decision about the rotor itself.
    retire(templates['rotor'], ['tool_size_mm'])
    rotor['semantic_roles']['tool_size_mm'] = 'legacy'
    rotor['helpers']['tool_size_mm'] = (
        'Lectura anterior sin fijación identificada. La herramienta corresponde '
        'al tornillo o lockring concreto y a su interfaz; no se deduce sólo '
        'del montaje del rotor. Se conserva sin convertirla en compatibilidad.')
    # A bare caliper cannot answer the purge port of an unrelated lever.
    templates['brake_caliper']['form_contract'].setdefault(
        'row_conditions', {'version': 1, 'fields': {}})['fields'].setdefault(
            'brake_bleed_ports', {}).setdefault('allowed_options', {})[
                'component_role'] = ['Cáliper']


def _assembly_member_scopes(definitions, templates):
    from compile_existing_brakes_catalog import drop
    table = 'brake_assembly_configurations'
    definition = definitions[table]
    if definition['origin'] != 'new':
        raise ValueError('Included member schema is not unpublished')
    schema = definition['validation_rules']['rows_schema']
    additions = [column(part + '_included', label, 'boolean', required=True)
                 for part, label in [('lever', 'Incluye esta maneta'), ('caliper', 'Incluye este cáliper'),
                                     ('hose', 'Incluye esta manguera'), ('rotor', 'Incluye este rotor'),
                                     ('adapter', 'Incluye este adaptador')]]
    additions += [column('caliper_piston_count', 'Pistones de este cáliper', 'integer', positive=True),
                  column('caliper_pad_shape_code', 'Forma de pastilla para este cáliper'),
                  column('caliper_pad_retainer_model', 'Retención de pastilla de este cáliper'),
                  column('lever_reach_adjust', 'Ajuste de alcance de esta maneta', 'boolean')]
    schema['columns'].extend(additions)
    families = ('hydraulic_disc_brake', 'mechanical_disc_brake', 'rim_brake')
    for family in families:
        template = templates[family]
        present = {f['key'] for f in template['fields']}
        # Published observations retain their original IDs and legacy owner.
        retire(template, sorted(present & {'reach_adjust', 'pad_shape_code'}))
        proposed = present & {'piston_count_value', 'rotor_included_diameter_mm',
                              'brake_pad_retainer_model', 'levers_included'}
        if any(definitions[k]['origin'] != 'new' for k in proposed):
            raise ValueError('Cannot drop a published assembly scalar')
        drop(template, sorted(proposed))
        contract = template['form_contract']
        rules = contract.setdefault('row_conditions', {'version': 1, 'fields': {}})[
            'fields'].setdefault(table, {})
        for spec in schema['columns']:
            key = spec['key']
            part = key.split('_', 1)[0]
            if part not in ('lever', 'caliper', 'hose', 'rotor', 'adapter') or key.endswith('_included'):
                continue
            rules.setdefault('allowed_when', {})[key] = condition(part + '_included', True, 'boolean')
            rules.setdefault('required_when', {})[key] = (
                condition(part + '_included', True, 'boolean') if key.endswith('_model')
                and key in {'lever_model', 'caliper_model', 'hose_model', 'rotor_model', 'adapter_model'}
                else {'kind': 'never'})
        contract['helpers'][table] = (
            'Contenido por circuito y posición. Confirma qué piezas incluye '
            'esa fila antes de sus datos; no se copia el cáliper, rotor o '
            'maneta delanteros al trasero. Los pistones y la pastilla pertenecen '
            'al cáliper, el alcance a la maneta y el diámetro al rotor incluido. '
            'La receta de montaje admitido es otra declaración.')
    for key, item in definitions.items():
        if item.get('origin') == 'new':
            item['used_by'] = sorted(t['key'] for t in templates.values()
                                     if any(f['key'] == key for f in t['fields']))


def adjust_cases(fixtures):
    inspection_ids = {'bkx_a_worn_rotor_measures_below_its_limit',
                      'bkx_a_measurement_without_its_method_is_pending'}
    fixtures['out_of_catalog_inspection_cases'] = [
        {**deepcopy(c), 'root_adjudication': (
            'Estado de una pieza usada: se conserva como caso de inspección '
            'fuera del catálogo; no prueba la ficha de todas las unidades de un SKU.')}
        for c in fixtures['cases'] if c['id'] in inspection_ids]
    fixtures['cases'] = [c for c in fixtures['cases'] if c['id'] not in inspection_ids]
    for c in fixtures['cases']:
        for key in ('rotor_size_recipe', 'rim_brake_mount_fitments'):
            for index, row in enumerate(c['values'].get(key, {}).get('rows', [])):
                # Existing fixtures already declare the separate recipes. Give
                # them identities without attributing a new OEM fact to them.
                duplicate_case = any(i['code'] == 'row_shape' and i['field'] == key
                                     for i in c.get('expected_blocking', []))
                row['values']['configuration'] = 'Receta de la fixture ' + ('1' if duplicate_case else str(index + 1))
        for key in ('brake_model_fluid_approvals', 'compatible_caliper_models'):
            for row in c['values'].get(key, {}).get('rows', []):
                if c['id'].startswith('bkx_'):
                    row['values'].setdefault('generation', 'Edición de fixture sintética')
                    if key == 'compatible_caliper_models':
                        row['values'].setdefault('variant', 'Variante de fixture sintética')
        if c['id'] == 'bkx_an_undeclared_compound_leaves_its_name_pending':
            c['expected_blocking'] = []
            c.pop('expected_sql_blocking', None)
            for expected in ('expected_issue_subset', 'expected_sql_issue_subset'):
                c[expected] = [i for i in c.get(expected, []) if i['field'] != 'brake_pad_oem_compound']
            c['root_adjudication'] = 'La etiqueta literal no exige inventar la clase; ésta puede seguir pendiente.'
        if c['id'] == 'bkx_a_rotor_without_its_material_leaves_the_restriction_pending':
            for expected in ('expected_issue_subset', 'expected_sql_issue_subset'):
                c[expected] = [i for i in c.get(expected, []) if i['field'] != 'pad_compound_restriction']
            c['root_adjudication'] = 'La restricción explícita puede conocerse aunque no se haya identificado el metal.'
        if c['id'] == 'bkx_the_same_approval_twice_blocks':
            c['predecessor_values'] = deepcopy(c['values'])
            for row in c['values']['brake_model_fluid_approvals']['rows']:
                row['values']['fluid_product'] = 'Producto de fixture sintética'
            c['root_adjudication'] = (
                'La prueba de duplicación identifica ahora el mismo producto. '
                'Antes comparaba uno no identificado con otro distinto, lo que '
                'no demostraba dos respuestas a la misma aprobación. El caso '
                'bkr_distinct_oem_fluid_products_are_distinct_claims conserva '
                'la posibilidad de aprobaciones explícitas a dos productos.')
        if c['template'] == 'rotor' and 'tool_size_mm' in c['values']:
            c['predecessor_case_id'] = c['id']
            c['id'] = ('bkr_rotor_keeps_unowned_tool_as_legacy_with_' +
                       ('mount' if c['values'].get('rotor_mount_type') else 'no_mount'))
            c['predecessor_values'] = deepcopy(c['values'])
            for expected in ('expected_blocking', 'expected_sql_blocking',
                             'expected_issue_subset', 'expected_sql_issue_subset'):
                if expected in c:
                    c[expected] = [i for i in c[expected] if i['field'] != 'tool_size_mm']
            c.setdefault('forbidden_issue_fields', []).append('tool_size_mm')
            c['root_adjudication'] = (
                'Esta fixture sólo conserva una lectura legacy sin dueño. '
                'Centerlock + T25 NO es un caso de compatibilidad aceptada: '
                'el campo se retira de la ficha activa y no se publica como '
                'propiedad del rotor. Park identifica la herramienta por la '
                'interfaz de la fijación concreta.')
    fixtures['cases'].extend(root_cases())
    fixtures['cases'].extend(assembly_scope_cases())
    for c in fixtures['cases']:
        expected = deepcopy(c.get('expected_sql_blocking', c.get('expected_blocking', [])))
        if c['id'] == 'bkx_the_same_port_twice_blocks':
            # The published rows-schema constraint reports its duplicate key
            # through PostgreSQL's generic field_constraint. Both engines
            # reject this exact port; an absent blocking flag means true.
            expected = [{'code': 'field_constraint', 'field': 'brake_piece_hydraulic_ports'}]
        # The shared SQL verifier compares ordered arrays, while Dart compares
        # sets. Preserve multiplicities and normalize only their order.
        c['expected_sql_blocking'] = sorted(expected, key=lambda x: (x['code'], x['field']))


def assembly_scope_cases():
    table = 'brake_assembly_configurations'
    family = 'hydraulic_disc_brake'
    magura = 'https://magura.com/product/mt-trail-sport/'
    included = {'circuit_id': 'c1', 'position': 'Delantero', 'source_url': SOURCE,
                'caliper_included': True, 'caliper_model': 'Modelo sintético',
                'lever_included': False, 'rotor_included': False,
                'hose_included': False, 'adapter_included': False}
    return [
        case('bkr_magura_trail_sport_preserves_four_front_two_rear', family,
             {table: rows(
                 {'circuit_id': 'front', 'position': 'Delantero', 'source_url': magura,
                  'caliper_included': True, 'caliper_brand': 'MAGURA',
                  'caliper_model': 'MT Trail Sport', 'caliper_piston_count': '4'},
                 {'circuit_id': 'rear', 'position': 'Trasero', 'source_url': magura,
                  'caliper_included': True, 'caliper_brand': 'MAGURA',
                  'caliper_model': 'MT Trail Sport', 'caliper_piston_count': '2'})}, sources=[magura]),
        case('bkr_no_lever_cannot_claim_lever_reach', family,
             {table: rows({**included, 'lever_reach_adjust': False})},
             blocking=[('row_field_applicability', table)]),
        case('bkr_no_rotor_cannot_claim_an_included_diameter', family,
             {table: rows({**included, 'rotor_diameter_mm': '180'})},
             blocking=[('row_field_applicability', table)]),
        case('bkr_inclusion_of_front_rotor_does_not_enable_rear', family,
             {table: rows({**included, 'rotor_included': True, 'rotor_model': 'Rotor sintético', 'rotor_diameter_mm': '180'},
                          {**included, 'circuit_id': 'c2', 'position': 'Trasero', 'rotor_diameter_mm': '160'})},
             blocking=[('row_field_applicability', table)]),
        case('bkr_included_rotor_without_model_remains_pending', family,
             {table: rows({**included, 'rotor_included': True})},
             pending=[('row_required_missing', table)]),
        case('bkr_legacy_pad_shape_is_not_assigned_to_both_calipers', family,
             {'pad_shape_code': 'Código heredado', table: rows(included)}),
        case('bkr_caliper_cannot_claim_a_lever_bleed_port', 'brake_caliper',
             {'braking_surface': 'Disco', 'brake_actuation': 'Hidráulico',
              'brake_bleed_ports': rows({'component_role': 'Maneta', 'port_id': 'p', 'source_url': SOURCE})},
             blocking=[('row_option', 'brake_bleed_ports')]),
    ]


def root_cases():
    circuit = {'circuit_id': 'c1', 'position': 'Delantero', 'source_url': SOURCE}
    approval = {'system_brand': 'Marca sintética', 'system_model': 'Modelo sintético',
                'generation': 'Edición sintética', 'fluid_class': 'Aceite Mineral',
                'fluid_product': 'Producto sintético A', 'source_url': SOURCE}
    return [
        case('bkr_another_source_cannot_duplicate_a_physical_circuit', 'hydraulic_disc_brake',
             {'brake_assembly_configurations': rows(circuit, {**circuit, 'source_url': SOURCE_B})},
             blocking=[('row_shape', 'brake_assembly_configurations')]),
        case('bkr_another_source_cannot_duplicate_an_approved_fluid', 'brake_caliper',
             {'braking_surface': 'Disco', 'brake_actuation': 'Hidráulico',
              'brake_model_fluid_approvals': rows(approval, {**approval, 'source_url': SOURCE_B})},
             blocking=[('row_shape', 'brake_model_fluid_approvals')]),
        case('bkr_distinct_oem_fluid_products_are_distinct_claims', 'brake_caliper',
             {'braking_surface': 'Disco', 'brake_actuation': 'Hidráulico',
              'brake_model_fluid_approvals': rows(approval, {**approval, 'fluid_product': 'Producto sintético B'})}),
        case('bkr_mineral_class_does_not_identify_the_approved_product', 'brake_caliper',
             {'braking_surface': 'Disco', 'brake_actuation': 'Hidráulico',
              'brake_model_fluid_approvals': rows({k: v for k, v in approval.items() if k != 'fluid_product'})},
             pending=[('row_required_missing', 'brake_model_fluid_approvals')]),
        case('bkr_literal_compound_can_precede_technical_classification', 'brake_pad',
             {'braking_surface': 'Disco', 'brake_pad_oem_compound': 'Nombre comercial sintético',
              'spec_evidence_source': SOURCE}),
        case('bkr_rotor_restriction_does_not_require_guessing_the_track_metal', 'rotor',
             {'pad_compound_restriction': 'Sólo resina', 'spec_evidence_source': SOURCE}),
    ]
