"""Adjudicate the unpublished brake accessory proposal, preserving live fields."""
from copy import deepcopy
from compile_mobility_accessories_catalog import case, condition, rows
from compile_wheel_small_parts_catalog import column, retire, table

SHIMANO = 'https://si.shimano.com/en/pdfs/dm/MDBR001/DM-MDBR001-05-ENG.pdf'
WOLF = 'https://www.wolftoothcomponents.com/products/boostinator'
COMPATIBLE, EXCLUDED = 'Compatible declarado', 'Excluido declarado'


def schema(definitions, key):
    return definitions[key]['validation_rules']['rows_schema']


def cols(definitions, key):
    return schema(definitions, key)['columns']


def review_brake_parts(definitions, templates, fixtures):
    mount, rotor, small, hub = (templates[k] for k in
        ('brake_mount_adapter', 'rotor_mount_adapter', 'brake_small_part', 'hub_brake'))
    fit, hardware, routes, parts, configs = ('brake_adapter_fitments',
        'brake_adapter_included_hardware', 'rotor_adapter_fitments',
        'brake_small_part_components', 'hub_brake_configurations')

    # Both local tables use an actual numeric inch diameter. Whole OEM thread
    # strings have their exclusive column; mm diameter + tpi remains valid.
    for key in (hardware, parts):
        for c in cols(definitions, key):
            if c['key'] == 'quantity':
                c['validation'] = {'positive': True}
            if c['key'] == 'thread_diameter_in':
                c.update(type='decimal', unit='in', label='Diámetro nominal en pulgadas',
                         validation={'positive': True})
    # A missing datum remains pending; it never erases a manufacturer's length.
    mount['form_contract']['helpers'][hardware] = (
        'Piezas incluidas, cantidad y largo suministrado. Conservar su referencia '
        'de medición; si no está publicada queda pendiente. El enlace indica '
        'la configuración de uso y no aumenta las piezas que trae la bolsa.')

    # Complete configuration IDs are scoped by the source. Different wheel
    # positions or target versions must be distinct complete configurations.
    for key in (fit, routes):
        cols(definitions, key).extend([
            column('configuration', 'Identidad de la configuración completa', required=True),
            column('source_scope', 'Apartado y alcance de fuente', required=True),
        ])
        if key == routes:
            cols(definitions, key).extend([
                column('adapter_model', 'Código completo del adaptador', required=True),
                column('adapter_function', 'Qué modifica el adaptador', 'token', required=True,
                       options=['Tipo de fijación', 'Posición del rotor', 'Otra función documentada']),
                column('rotor_offset_mm', 'Desplazamiento axial publicado', 'decimal', unit='mm'),
                column('rotor_offset_datum', 'Referencia y dirección del desplazamiento'),
                column('lockring_thread_spec', 'Rosca del anillo propio del adaptador'),
            ])
        schema(definitions, key)['unique_by'] = [['adapter_model', 'configuration', 'source_scope']]

    # Two independent interfaces must be recordable together, including a
    # threaded hub route with a separate lockring. The historic ring fixture is
    # translated by its explicit meaning, not by all future Centerlock rows.
    schema(definitions, routes)['columns'] = [c for c in cols(definitions, routes)
        if c['key'] != 'thread_owner']
    next(c for c in cols(definitions, routes) if c['key'] == 'hub_thread_spec')['label'] = (
        'Rosca de fijación del adaptador a la maza')
    rc = rotor['form_contract']['row_conditions']['fields'][routes]
    rc.setdefault('allowed_when', {})['hub_thread_spec'] = condition('hub_mount', 'Rosca especificada')
    rc.setdefault('allowed_when', {})['rotor_offset_mm'] = condition('adapter_function', 'Posición del rotor')
    rc['allowed_when']['rotor_offset_datum'] = condition('adapter_function', 'Posición del rotor')
    rc.setdefault('required_when', {})['rotor_offset_datum'] = condition('adapter_function', 'Posición del rotor')
    rotor['form_contract']['helpers'][routes] = (
        'Maza de entrada y rotor de salida tienen dirección. Ambas pueden '
        'conservar seis pernos cuando la función es desplazar el rotor. La '
        'rosca de fijación a la maza y la del anillo propio son independientes. '
        'La configuración completa incluye posición, versiones y restricciones '
        'del fabricante; no equivale a aprobación por coincidencia de anclaje.')

    for fixture in fixtures['cases']:
        for row in fixture['values'].get(routes, {}).get('rows', []):
            v = row['values']
            if fixture['id'] in ('RCF38', 'RCF39'):
                # These two synthetic regressions explicitly convert their
                # hub interface to six bolts; neither represents an offset.
                v['adapter_function'] = 'Tipo de fijación'
            owner = v.pop('thread_owner', None)
            if fixture['id'] == 'RCF39' or owner == 'Anillo propio del adaptador':
                if 'hub_thread_spec' in v:
                    v['lockring_thread_spec'] = v.pop('hub_thread_spec')
                fixture['successor_translation'] = (
                    'Se conserva el dato explícito del anillo en lockring_thread_spec; '
                    'la rosca de fijación de maza tiene su propia celda. No es '
                    'una regla para inferir propietarios de datos reales.')
        # Source of fixture geometry is synthetic; Park names mounting types,
        # not the fictitious complete adapter being described by this harness.
        for row in fixture['values'].get(fit, {}).get('rows', []):
            if row['values'].get('adapter_model') == 'Sintético':
                row['values'].pop('source_url', None)

    # The authoritative type now belongs to each piece. A whole-kit scalar
    # cannot call every clip a bolt or force one material on mixed components.
    retire(small, ['brake_part_kind', 'material', 'compatible_brake_models'])
    cols(definitions, parts).extend([
        column('oem_code', 'Código del fabricante de esta pieza'),
        column('material', 'Material de esta pieza'),
        column('target_brand', 'Fabricante del freno objetivo'),
        column('target_model', 'Modelo o referencia del freno objetivo', required=True),
        column('target_edition', 'Versión del freno objetivo'),
        column('configuration', 'Montaje de esta pieza', required=True),
    ])
    # Mixed integral/screw-on spring assemblies are not the bare spring; this
    # guard stays on the explicit individual piece_kind, never on a whole SKU.

    retire(hub, ['hub_brake_kind'])
    for c in cols(definitions, configs):
        if c['key'] == 'actuation':
            c['allowed_values'].insert(-1, 'Hidráulico')
    cols(definitions, configs).extend([
        column('brake_brand', 'Fabricante del freno'),
        column('brake_model', 'Modelo de freno o maza', required=True),
        column('edition', 'Edición o versión'),
    ])
    schema(definitions, configs)['columns'] = [c for c in cols(definitions, configs)
                                             if c['key'] != 'axle_fit']
    schema(definitions, configs)['unique_by'] = [['brake_model', 'edition', 'configuration']]
    attachment = 'hub_brake_attachment_interfaces'
    table(definitions, templates, attachment, 'Interfaces de montaje del freno de maza',
        ('hub_brake',), [
            column('configuration_row_id', 'Configuración del freno', required=True),
            column('interface', 'Zona o extremo de la interfaz', required=True),
            column('interface_kind', 'Tipo de interfaz', 'token', required=True,
                   options=['Rosca de eje', 'Eje pasante', 'Asiento liso',
                            'Separación OLD', 'Fijación de reacción', 'Designación OEM']),
            column('diameter', 'Diámetro nominal', 'decimal', positive=True),
            column('diameter_unit', 'Unidad del diámetro', 'token', options=['mm', 'in']),
            column('pitch', 'Paso o hilos por pulgada', 'decimal', positive=True),
            column('pitch_unit', 'Unidad del paso', 'token', options=['mm', 'tpi']),
            column('old_mm', 'Separación OLD', 'decimal', unit='mm', positive=True),
            column('designation', 'Designación OEM de la interfaz'),
            column('conditions', 'Método de medición y condiciones'),
            column('source_url', 'Fuente', 'url'),
        ], conditions={
            **{k: condition('interface_kind', ['Rosca de eje', 'Eje pasante', 'Asiento liso'])
               for k in ('diameter', 'diameter_unit')},
            **{k: condition('interface_kind', 'Rosca de eje') for k in ('pitch', 'pitch_unit')},
            'old_mm': condition('interface_kind', 'Separación OLD'),
            'designation': condition('interface_kind', ['Fijación de reacción', 'Designación OEM']),
        }, helper='El diámetro del eje, su rosca, la separación OLD y el anclaje '
        'de reacción son interfaces distintas de una configuración. Ninguna '
        'medida se interpreta automáticamente como modelo compatible.')
    schema(definitions, attachment)['unique_by'] = [['configuration_row_id', 'interface']]
    hub['form_contract']['row_coherence'] = {'version': 1, 'links': [{
        'id': 'hub_brake_attachment_configuration', 'field': attachment,
        'column': 'configuration_row_id', 'target_field': configs,
        'label_columns': ['brake_model', 'configuration']}]}
    fixtures['cases'].extend(root_cases(fit, hardware, routes, parts, configs, attachment))
    priorities = {'brake_mount_adapter': [fit, hardware], 'rotor_mount_adapter': [routes],
                  'brake_small_part': [parts], 'hub_brake': [configs, attachment]}
    for template in templates.values():
        sequence = priorities[template['key']]
        for n, f in enumerate(sorted(template['fields'], key=lambda f:
             1000 if template['form_contract']['roles'][f['key']] == 'legacy'
             else sequence.index(f['key']) if f['key'] in sequence else len(sequence)), 1):
            f['sort_order'] = n * 10
        key = sequence[0]
        template['form_contract']['roles'][key] = 'primary'
        template['form_contract']['semantic_roles'][key] = 'intrinsic'
        next(f for f in template['fields'] if f['key'] == key)['section_key'] = 'primary'


def root_cases(fit, hardware, routes, parts, configs, attachment):
    result = []
    def add(id_, family, values, **kwargs):
        result.append(case('ba_root_' + id_, family, values, **kwargs))
    route = {'hub_mount': 'Centerlock', 'rotor_mount': '6 pernos',
             'adapter_model': 'SM-RTAD05', 'adapter_function': 'Tipo de fijación',
             'configuration': 'Montaje rotor SM-RT86', 'source_scope': 'DM-MDBR001-05 p.8',
             'rotor_model': 'SM-RT86', 'status': EXCLUDED, 'source_url': SHIMANO,
             'conditions': 'La estructura del rotor con adaptador de aluminio está excluida.'}
    add('oem_rotor_exclusion_is_explicit', 'rotor_mount_adapter',
        {routes: rows(route)}, sources=[SHIMANO])
    add('one_exact_route_cannot_be_approved_and_excluded', 'rotor_mount_adapter',
        {routes: rows(route, {**route, 'status': COMPATIBLE})}, blocking=[('row_shape', routes)])
    add('another_configuration_is_not_collapsed', 'rotor_mount_adapter',
        {routes: rows(route, {**route, 'configuration': 'Otra configuración sintética'})})
    add('both_thread_owners_can_be_described_together', 'rotor_mount_adapter',
        {routes: rows({**route, 'adapter_model': 'Adaptador sintético',
             'configuration': 'Dos interfaces', 'hub_mount': 'Rosca especificada',
             'hub_thread_spec': 'Rosca A sintética', 'lockring_thread_spec': 'Rosca B sintética',
             'source_url': 'https://example.com/synthetic-rotor-adapter'})})
    add('ring_detail_is_not_a_threaded_hub_attachment', 'rotor_mount_adapter',
        {routes: rows({**route, 'hub_thread_spec': 'Rosca del anillo'})},
        blocking=[('row_field_applicability', routes)])
    add('same_six_bolt_interfaces_can_shift_the_rotor', 'rotor_mount_adapter',
        {routes: rows({'hub_mount': '6 pernos', 'rotor_mount': '6 pernos',
           'adapter_model': 'Boostinator HR', 'adapter_function': 'Posición del rotor',
           'configuration': 'Maza Hope Pro 2 EVO trasera 12x142',
           'hub_model': 'Hope Pro 2 EVO', 'status': COMPATIBLE,
           'source_scope': 'Rear Boostinator kits / HR', 'rotor_max_mm': '183',
           'conditions': 'Sólo trasero de seis pernos; requiere cambio de aparaguado, '
                         'tapa de eje y pernos del kit. No se infiere compatibilidad de un separador suelto.',
           'source_url': WOLF})}, sources=[WOLF])
    thread = {'piece': 'Perno sintético', 'piece_kind': 'Perno', 'quantity': '1',
              'length_form': 'No publicado', 'thread_form': 'Roscada',
              'thread_diameter_unit': 'in', 'thread_diameter_in': '0.25',
              'thread_pitch_unit': 'tpi', 'thread_pitch_tpi': '20'}
    add('numeric_inch_thread_is_recordable', 'brake_mount_adapter', {hardware: rows(thread)})
    add('diameter_cannot_embed_a_second_pitch', 'brake_mount_adapter',
        {hardware: rows({**thread, 'thread_diameter_in': '1/4x26'})}, blocking=[('row_shape', hardware)])
    add('zero_hardware_quantity_is_not_unknown', 'brake_mount_adapter',
        {hardware: rows({**thread, 'quantity': '0'})}, blocking=[('row_shape', hardware)])
    mount = {'adapter_model': 'Sintético', 'configuration': 'C1', 'source_scope': 'Manual1',
             'position': 'Delantero', 'frame_mount': 'Post Mount', 'caliper_mount': 'Post Mount',
             'frame_base_form': 'Declarado', 'frame_base_rotor_mm': '160',
             'rotor_diameter_mm': '180', 'status': COMPATIBLE}
    add('one_mount_configuration_cannot_have_two_results', 'brake_mount_adapter',
        {fit: rows(mount, {**mount, 'rotor_diameter_mm': '203'})}, blocking=[('row_shape', fit)])
    add('different_mount_configurations_keep_their_target', 'brake_mount_adapter',
        {fit: rows(mount, {**mount, 'configuration': 'C2', 'rotor_diameter_mm': '203'})})
    hub = {'configuration': 'C1', 'brake_model': 'Sintético', 'edition': 'E1',
           'mechanism': 'Tambor', 'product_scope': 'Freno integrado en la maza',
           'position': 'Delantera', 'actuation': 'Cable', 'drum_form': 'No publicado'}
    old = {'configuration_row_id': 'r1', 'interface': 'Separación',
           'interface_kind': 'Separación OLD', 'old_mm': '100'}
    add('hub_old_has_its_own_scope', 'hub_brake', {configs: rows(hub), attachment: rows(old)})
    add('old_cannot_carry_an_axle_thread', 'hub_brake',
        {configs: rows(hub), attachment: rows({**old, 'pitch': '26'})},
        blocking=[('row_field_applicability', attachment)])
    add('hub_interface_requires_existing_configuration', 'hub_brake',
        {configs: rows(hub), attachment: rows({**old, 'configuration_row_id': 'absent'})},
        blocking=[('row_reference_unresolved', attachment)])
    add('same_hub_configuration_cannot_be_front_and_rear', 'hub_brake',
        {configs: rows(hub, {**hub, 'position': 'Trasera'})}, blocking=[('row_shape', configs)])
    add('two_hub_editions_are_not_collapsed', 'hub_brake',
        {configs: rows(hub, {**hub, 'edition': 'E2', 'position': 'Trasera'})})
    return result
