#!/usr/bin/env python3
"""Compile nine wheel/repair templates. No product or database writes.

The table row is a scoped declaration, never mechanical approval. Reusing a
dimension from another row/component is not an implicit compatibility rule.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import (
    add_field, case, condition, new_definition, remove_unpublished_field, rows)
from compile_product_spec_catalog import validate_contract

FAMILIES = ('hub_axle', 'hub_small_part', 'wheel_retention', 'spoke_nipple',
            'tubeless_tape', 'tubeless_repair', 'valve_small_part',
            'tire_liner', 'tube_repair')
ALWAYS, NEVER = {'kind': 'always'}, {'kind': 'never'}
PARK_PATCH = 'https://www.parktool.com/en-us/product/vulcanizing-patch-kit-vp-1'
PARK_NIPPLE = 'https://www.parktool.com/en-us/blog/repair-help/spoke-wrench-tool-selection'
RAP = 'https://robertaxleproject.com/what-axle-do-i-need/'


def column(key, label, kind='text', *, required=False, options=(), unit=None,
           positive=False, integer=False):
    result = {'key': key, 'label': label, 'type': kind}
    if required:
        result['required'] = True
    if options:
        result['allowed_values'] = list(options)
    if unit:
        result['unit'] = unit
    if positive:
        result['validation'] = {'positive': True}
    if integer:
        result.setdefault('validation', {})['integer'] = True
    return result


def table(definitions, templates, key, label, families, columns, *, ordered=(),
          required=False, helper=None, conditions=None):
    schema = {'version': 1, 'columns': columns}
    if ordered:
        schema['ordered_pairs'] = list(ordered)
    definitions[key] = new_definition(key, label, 'json', families,
                                      rules={'rows_schema': schema})
    for family in families:
        add_field(templates[family], key, 'declaration', 'compatibility',
                  required=ALWAYS if required else NEVER, helper=helper)
        if conditions:
            templates[family]['form_contract'].setdefault(
                'row_conditions', {'version': 1, 'fields': {}})['fields'][key] = {
                    'allowed_when': deepcopy(conditions),
                    'required_when': deepcopy(conditions)}


def retire(template, keys):
    c = template['form_contract']
    for key in keys:
        c['roles'][key] = 'legacy'
        c['allowed_when'][key] = deepcopy(NEVER)
        c['required_when'][key] = deepcopy(NEVER)
        c.get('allowed_options', {}).pop(key, None)
        c.get('prerequisites', {}).pop(key, None)
        next(f for f in template['fields'] if f['key'] == key)['section_key'] = 'legacy'


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen input drift')
    base = json.loads(CATALOG.read_text())
    templates = {t['key']: deepcopy(t) for t in base['templates'] if t['key'] in FAMILIES}
    definitions = deepcopy(base['definitions'])
    # The live preimage retains the historical three-option definition. The
    # frozen proposal's fourth option was never published. Pairs now live in
    # component rows; neither remaining scalar use admits Par. Do not extend a
    # shared vocabulary to support a field this successor has already retired.
    definitions['wheel_position']['allowed_values'] = ['Delantera', 'Trasera', 'Universal']
    fixtures = json.loads(CASES.read_text())
    fixtures['cases'] = [c for c in fixtures['cases'] if c['template'] in FAMILIES]

    # Diameter notation and pitch notation are independent: Park documents
    # 10 mm x 26 TPI axles. Never derive either unit system from the other.
    interface = 'wheel_part_interfaces'
    threaded, plain, literal = 'Rosca', 'Asiento sin rosca', 'Designación OEM'
    interface_families = ('hub_axle', 'hub_small_part', 'wheel_retention')
    interface_conditions = {
        'diameter_unit': condition('interface_kind', [threaded, plain]),
        'pitch_unit': condition('interface_kind', threaded),
        'diameter_mm': condition('diameter_unit', 'mm'),
        'diameter_in': condition('diameter_unit', 'in'),
        'pitch_mm': condition('pitch_unit', 'mm'),
        'pitch_tpi': condition('pitch_unit', 'tpi'),
        'designation': condition('interface_kind', literal),
    }
    for key in ('diameter_mm', 'diameter_in'):
        interface_conditions[key]['rows'][0].extend(
            condition('interface_kind', [threaded, plain])['rows'][0])
    for key in ('pitch_mm', 'pitch_tpi'):
        interface_conditions[key]['rows'][0].extend(
            condition('interface_kind', threaded)['rows'][0])
    table(definitions, templates, interface, 'Interfaces declaradas de la pieza de rueda',
          interface_families, [
              column('scope', 'Zona, extremo o interfaz', required=True),
              column('interface_kind', 'Forma de la interfaz', 'token', required=True,
                     options=[threaded, plain, literal]),
              column('diameter_unit', 'Unidad publicada del diámetro', 'token', options=['mm', 'in']),
              column('pitch_unit', 'Forma publicada del paso', 'token', options=['mm', 'tpi']),
              column('diameter_mm', 'Diámetro nominal de esta interfaz', 'decimal', unit='mm', positive=True),
              column('diameter_in', 'Diámetro nominal en pulgadas, literal'),
              column('pitch_mm', 'Paso', 'decimal', unit='mm', positive=True),
              column('pitch_tpi', 'Hilos por pulgada', 'decimal', unit='tpi', positive=True),
              column('designation', 'Designación publicada sin descomponer'),
              column('thread_hand', 'Sentido de rosca', 'token', options=['Derecha', 'Izquierda']),
              column('engagement_length_mm', 'Longitud roscada declarada', 'decimal', unit='mm', positive=True),
              column('conditions', 'Modelo, método y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ], conditions=interface_conditions,
          helper='Una fila por zona o interfaz documentada. El calibre del cuerpo '
          'del eje no se iguala a la rosca; una designación incompleta se conserva '
          'literal y no certifica el recambio. Diámetro y paso conservan unidades '
          'independientes; admite diámetro en mm con paso en TPI sin convertirlos.')
    # Thread-only secondary columns are optional, but prohibited on plain seats.
    for family in interface_families:
        c = templates[family]['form_contract']['row_conditions']['fields'][interface]
        for key in ('thread_hand', 'engagement_length_mm'):
            c['allowed_when'][key] = condition('interface_kind', [threaded, literal])
    retire(templates['hub_axle'], ['axle_diameter_thread'])
    retire(templates['hub_small_part'], ['axle_diameter_thread', 'adapter_to'])
    templates['hub_axle']['form_contract']['required_when'][interface] = deepcopy(ALWAYS)
    templates['hub_small_part']['form_contract']['required_when'][interface] = deepcopy(ALWAYS)
    templates['hub_axle']['form_contract']['helpers']['axle_hollow'] = (
        'Construcción de este eje. Es independiente de su diámetro y rosca; '
        'no se infiere de la posición de rueda ni del nombre comercial.')
    definitions['hub_axle_length_datum'] = new_definition(
        'hub_axle_length_datum', 'Referencia de medición del largo del eje', 'text', ['hub_axle'])
    add_field(templates['hub_axle'], 'hub_axle_length_datum', 'measurement', 'measurement')
    templates['hub_axle']['form_contract']['prerequisites']['axle_length_mm'] = ['hub_axle_length_datum']
    table(definitions, templates, 'wheel_part_model_fitments',
          'Modelos de destino y condiciones declaradas', interface_families, [
              column('component', 'Pieza a la que pertenece la declaración', required=True),
              column('target_kind', 'Destino', 'token', required=True,
                     options=['Maza', 'Cuadro', 'Horquilla', 'Eje', 'Otro']),
              column('target_brand', 'Marca del destino'),
              column('target_model', 'Modelo o referencia del destino', required=True),
              column('target_edition', 'Generación o versión'),
              column('position', 'Posición o lado'),
              column('status', 'Declaración', 'token', required=True,
                     options=['Compatible declarado', 'Incompatible declarado', 'Condicionado']),
              column('conditions', 'Condiciones, piezas o adaptadores'),
              column('source_url', 'Fuente', 'url'),
          ], helper='Conserva la declaración para el modelo, versión y lado exactos. '
          'La coincidencia de rosca o diámetro por sí sola no confirma un cono, '
          'adaptador, eje o conjunto de retención.')
    for family in interface_families:
        templates[family]['form_contract']['row_conditions']['fields']['wheel_part_model_fitments'] = {
            'required_when': {'conditions': condition('status', 'Condicionado')}}

    # Pairs and spacer alternatives cannot share one scalar length/OLD/thread.
    retention = 'wheel_retention_configurations'
    qr, thru, nut, small, other = ('Aguja cierre rápido', 'Eje pasante',
                                  'Tuerca de eje', 'Resorte / pieza de aguja', 'Otro')
    exact, interval = 'Longitud exacta', 'Rango declarado'
    length_conditions = {'effective_length_mm': condition('length_kind', exact),
                         'length_min_mm': condition('length_kind', interval),
                         'length_max_mm': condition('length_kind', interval)}
    table(definitions, templates, retention, 'Piezas y configuraciones de retención',
          ['wheel_retention'], [
              column('component', 'Pieza incluida', required=True),
              column('configuration', 'Configuración o alternativa publicada', required=True),
              column('position', 'Posición', 'token', required=True,
                     options=['Delantera', 'Trasera', 'Sin posición específica']),
              column('kind', 'Tipo de retención', 'token', required=True,
                     options=[qr, thru, nut, small, other]),
              column('shaft_diameter_mm', 'Diámetro del cuerpo del eje', 'decimal', unit='mm', positive=True),
              column('shaft_length_mm', 'Largo físico del cuerpo, datum declarado', 'decimal', unit='mm', positive=True),
              column('length_kind', 'Forma del largo útil', 'token', options=[exact, interval]),
              column('effective_length_mm', 'Largo útil declarado', 'decimal', unit='mm', positive=True),
              column('length_min_mm', 'Largo útil mínimo', 'decimal', unit='mm', positive=True),
              column('length_max_mm', 'Largo útil máximo', 'decimal', unit='mm', positive=True),
              column('length_datum', 'Desde dónde se mide el largo'),
              column('head_seat', 'Asiento o geometría de cabeza'),
              column('actuation', 'Accionamiento o herramienta'),
              column('spacers', 'Espaciadores/adaptadores y configuración'),
              column('thread_interface_id', 'Interfaz roscada de esta pieza'),
              column('target_old_mm', 'OLD de destino declarado', 'decimal', unit='mm', positive=True),
              column('conditions', 'Condiciones de uso y modelo'),
              column('source_url', 'Fuente', 'url'),
          ], required=True, ordered=[['length_min_mm', 'length_max_mm']],
          conditions=length_conditions, helper='Cada pieza y alternativa conserva '
          'su largo, asiento, espaciadores y rosca. Un rango sólo representa un rango '
          'publicado; no interpola alternativas discretas. OLD no es largo de eje.')
    c = templates['wheel_retention']['form_contract']
    retire(templates['wheel_retention'], ['retention_kind', 'wheel_position',
        'skewer_length_mm', 'thru_axle_diameter_mm', 'thru_axle_length_mm',
        'thru_axle_thread', 'axle_nut_thread', 'target_hub_old_mm'])
    rc = c['row_conditions']['fields'][retention]
    for bucket in ('allowed_when', 'required_when'):
        for key in ('effective_length_mm', 'length_min_mm', 'length_max_mm'):
            rc[bucket][key]['rows'][0].extend(condition('kind', [qr, thru, other])['rows'][0])
    for key in ('shaft_diameter_mm', 'shaft_length_mm', 'length_kind', 'length_datum',
                'head_seat', 'spacers'):
        rc['allowed_when'][key] = condition('kind', [qr, thru, other])
    rc['required_when']['length_kind'] = condition('kind', [qr, thru])
    rc['required_when']['length_datum'] = condition('kind', [qr, thru])
    rc['allowed_when']['thread_interface_id'] = condition('kind', [qr, thru, nut, other])
    rc['required_when']['thread_interface_id'] = condition('kind', [thru, nut])
    c['row_coherence'] = {'version': 1, 'links': [{
        'id': 'retention_thread', 'field': retention, 'column': 'thread_interface_id',
        'target_field': interface, 'label_columns': ['scope', 'interface_kind']} ]}

    # The tool drive is neither the spoke gauge nor its rolled-thread standard.
    drive = 'nipple_tool_interfaces'
    table(definitions, templates, drive, 'Interfaces de herramienta del niple',
          ['spoke_nipple'], [
              column('location', 'Zona de acceso', 'token', required=True,
                     options=['Exterior', 'Interior de llanta', 'Otra']),
              column('shape', 'Forma de la interfaz', 'token', required=True,
                     options=['Cuadrada', 'Hexagonal', 'Estriada', 'Otra']),
              column('dimension_mm', 'Medida declarada de herramienta', 'decimal', unit='mm', positive=True),
              column('measurement_basis', 'Plano, diámetro o referencia de la medida'),
              column('spline_count', 'Estrías', 'integer', positive=True),
              column('oem_tool', 'Herramienta o interfaz OEM'),
              column('conditions', 'Modelo y condiciones'),
              column('source_url', 'Fuente', 'url'),
          ], helper='La llave se elige por su interfaz propia. No se calcula a '
          'partir del calibre del radio ni de la designación de rosca del niple.')
    c = templates['spoke_nipple']['form_contract']
    retire(templates['spoke_nipple'], ['nipple_head'])
    c['row_conditions'] = {'version': 1, 'fields': {drive: {
        'allowed_when': {'spline_count': condition('shape', 'Estriada')},
        'required_when': {'measurement_basis': condition('dimension_mm', '0', 'decimal')}
    }}}
    # A positive measurement requires a datum; a missing measurement is unknown.
    c['row_conditions']['fields'][drive]['required_when']['measurement_basis']['rows'][0][0]['operator'] = 'gt'

    # A liner's advertised size and its width restriction belong in the same row.
    liner = 'tire_liner_fitments'
    nominal, bsd = 'Designación nominal', 'BSD declarado'
    width_exact, width_range, width_maximum = 'Ancho exacto', 'Rango de anchos', 'Ancho máximo'
    bounds = {'nominal_size': condition('size_basis', nominal),
              'bsd_mm': condition('size_basis', bsd),
              'width_min': condition('width_kind', width_range),
              'width_max': condition('width_kind', width_range),
              'width_value': condition('width_kind', [width_exact, width_maximum]),
              'width_unit': condition('width_kind', [width_exact, width_range, width_maximum])}
    table(definitions, templates, liner, 'Aplicaciones declaradas del protector',
          ['tire_liner'], [
              column('configuration', 'Variante y configuración', required=True),
              column('size_basis', 'Forma de tamaño publicada', 'token', required=True, options=[nominal, bsd]),
              column('nominal_size', 'Tamaño nominal literal'),
              column('bsd_mm', 'Diámetro BSD declarado', 'integer', unit='mm', positive=True),
              column('width_kind', 'Forma del ancho publicado', 'token',
                     options=[width_exact, width_range, width_maximum]),
              column('width_value', 'Ancho declarado', 'decimal', positive=True),
              column('width_min', 'Ancho de cubierta mínimo', 'decimal', positive=True),
              column('width_max', 'Ancho de cubierta máximo', 'decimal', positive=True),
              column('width_unit', 'Unidad del ancho', 'token', options=['mm', 'in']),
              column('conditions', 'Condiciones del montaje'),
              column('source_url', 'Fuente', 'url'),
          ], required=True, ordered=[['width_min', 'width_max']], conditions=bounds,
          helper='Cada tamaño conserva su propio intervalo y unidad. No convierte '
          '700C, 26 o 29 a BSD; no cruza el ancho de una aplicación con otra.')
    c = templates['tire_liner']['form_contract']
    retire(templates['tire_liner'], ['bead_seat_diameters_supported', 'tire_width_min_mm', 'tire_width_max_mm'])
    c.pop('scalar_ordered_pairs', None)

    # Materials describe the repair target, not the material of the patch.
    repair = 'repair_target_declarations'
    table(definitions, templates, repair, 'Superficies y materiales de reparación',
          ['tube_repair', 'tubeless_repair'], [
              column('repair_component', 'Parche, solución, mecha o conjunto', required=True),
              column('target', 'Superficie de destino', 'token', required=True,
                     options=['Cámara', 'Cuerpo de neumático', 'Otra']),
              column('target_material', 'Material de la superficie a reparar', 'token',
                     options=['Butilo', 'Látex', 'TPU', 'Otro']),
              column('target_model', 'Modelo, construcción o superficie específica'),
              column('status', 'Declaración OEM', 'token', required=True,
                     options=['Compatible declarado', 'Incompatible declarado', 'Condicionado']),
              column('conditions', 'Condiciones y exclusiones'),
              column('source_url', 'Fuente', 'url'),
          ], required=True, helper='Conserva material, superficie, producto de '
          'reparación y condiciones de la fuente exacta. Una regla para un modelo '
          'no se extiende a todos los parches o mechas del mismo formato.')
    for family in ('tube_repair', 'tubeless_repair'):
        c = templates[family]['form_contract']
        c.setdefault('row_conditions', {'version': 1, 'fields': {}})['fields'][repair] = {
            'required_when': {
                'conditions': condition('status', 'Condicionado'),
                'target_material': condition('target', 'Cámara'),
                'target_model': {'kind': 'when', 'rows': [
                    condition('target', ['Cuerpo de neumático', 'Otra'])['rows'][0],
                    condition('target_material', 'Otro')['rows'][0]]},
            }}
        c['helpers']['kit_members'] = (
            'Contenido de la caja; conserva identidad de cada pieza. La familia '
            'o las medidas de una pieza no se transfieren a las demás.')
    plugs = 'tubeless_repair_plug_configurations'
    table(definitions, templates, plugs, 'Mechas y herramientas declaradas',
          ['tubeless_repair'], [
              column('plug_brand', 'Marca de la mecha'),
              column('plug_model', 'Modelo o designación de la mecha', required=True),
              column('size_designation', 'Tamaño publicado'),
              column('diameter_mm', 'Diámetro declarado', 'decimal', unit='mm', positive=True),
              column('quantity', 'Cantidad de esta mecha incluida', 'integer', positive=True),
              column('insertion_tool', 'Herramienta y boquilla compatibles', required=True),
              column('conditions', 'Modelo y limitaciones'),
              column('source_url', 'Fuente', 'url'),
          ], helper='No supone que todas las mechas caben en todas las boquillas '
          'ni que fina/estándar sea una medida universal. No suma cantidades '
          'de observaciones alternativas para deducir el contenido del envase.')
    retire(templates['tubeless_repair'], ['plug_size'])
    templates['tube_repair']['form_contract']['prerequisites']['glue_volume_ml'] = ['spec_evidence_source']

    # Adapter direction and core relocation belong to an explicit configuration.
    valve = 'valve_part_configurations'
    core, cap, seal, adapter, extender, valve_other = ('Obús', 'Tapa', 'Junta / goma', 'Adaptador', 'Alargador', 'Otro')
    valve_options = ['Presta', 'Schrader', 'Dunlop', 'Otro']
    relocated, external, extension_other = 'Reubica el obús', 'Sobre válvula con obús', 'Otro sistema'
    table(definitions, templates, valve, 'Interfaces y configuración de la pieza de válvula',
          ['valve_small_part'], [
              column('component', 'Pieza y modelo', required=True),
              column('kind', 'Tipo de pieza', 'token', required=True,
                     options=[core, cap, seal, adapter, extender, valve_other]),
              column('input_valve', 'Válvula de origen', 'token', required=True, options=valve_options),
              column('output_connection', 'Conexión ofrecida al inflador', 'token', options=valve_options),
              column('target_model', 'Modelo/versión de la válvula de destino'),
              column('interface_designation', 'Rosca, asiento o referencia OEM'),
              column('extension_kind', 'Sistema del alargador', 'token', options=[relocated, external, extension_other]),
              column('requires_removable_core', 'Requiere obús extraíble', 'boolean'),
              column('extension_length_mm', 'Longitud nominal del alargador', 'decimal', unit='mm', positive=True),
              column('conditions', 'Requisitos y condiciones de montaje'),
              column('source_url', 'Fuente', 'url'),
          ], required=True, helper='Separa válvula de origen, conexión al inflador '
          'y sistema de alargador. El tipo comercial no confirma roscas, gomas '
          'ni obuses de otro modelo; desconocido permanece sin contestar.')
    c = templates['valve_small_part']['form_contract']
    # These unpublished fields have no product facts; do not publish the unsafe
    # Desconocido token as a new active compatibility axis just to retire it.
    for key in ('valve_part_kind', 'valve_type', 'core_thread', 'target_valve_model'):
        remove_unpublished_field(templates['valve_small_part'], key)
    c['row_conditions'] = {'version': 1, 'fields': {valve: {
        'allowed_when': {
            'output_connection': condition('kind', [adapter, extender]),
            'extension_kind': condition('kind', extender),
            'requires_removable_core': condition('kind', extender),
            'extension_length_mm': condition('kind', extender),
        },
        'required_when': {
            'output_connection': condition('kind', adapter),
            'extension_kind': condition('kind', extender),
            'target_model': condition('kind', [core, seal]),
            'interface_designation': condition('kind', [core, seal]),
        },
        'value_when': {'requires_removable_core': [{
            'when': condition('extension_kind', relocated),
            'expected': {'value_type': 'boolean', 'value': True},
        }]},
    }}}

    # Tape width is intrinsic; rim-width offsets are product-specific advice.
    templates['tubeless_tape']['form_contract']['helpers']['tape_width_mm'] = (
        'Ancho de esta cinta, no ancho interno de llanta. La elección, vueltas '
        'y preparación siguen las instrucciones del fabricante para esa llanta; '
        'no se añade automáticamente una diferencia universal de milímetros.')
    add_field(templates['tubeless_tape'], 'tubeless_tape_application', 'declaration',
              'compatibility', helper='Llanta, ancho, vueltas y condiciones que '
              'el fabricante declara para esta cinta; no inferirlos del ancho.')
    definitions['tubeless_tape_application'] = new_definition(
        'tubeless_tape_application', 'Aplicación e instrucciones de la cinta',
        'text', ['tubeless_tape'])

    # Executable representation regressions, with synthetic geometry explicitly
    # distinguished from the exact OEM claims read in the review.
    fixtures['cases'].extend([
        case('ws_metric_interface', 'hub_axle', {interface: rows({
            'scope': 'Rosca del cono', 'interface_kind': threaded, 'diameter_unit': 'mm', 'pitch_unit': 'mm',
            'diameter_mm': '10', 'pitch_mm': '1'}), 'axle_hollow': False}),
        case('ws_metric_pitch_missing', 'hub_axle', {interface: rows({
            'scope': 'Rosca del cono', 'interface_kind': threaded, 'diameter_unit': 'mm', 'pitch_unit': 'mm',
            'diameter_mm': '10'})}, pending=[('row_required_missing', interface)]),
        case('ws_mixed_thread_systems', 'hub_axle', {interface: rows({
            'scope': 'Rosca del cono', 'interface_kind': threaded, 'diameter_unit': 'mm', 'pitch_unit': 'mm',
            'diameter_mm': '10', 'pitch_mm': '1', 'pitch_tpi': '26'})},
             blocking=[('row_field_applicability', interface)]),
        case('ws_m14_pitch_not_invented', 'hub_axle', {interface: rows({
            'scope': 'Declaración parcial', 'interface_kind': literal, 'designation': 'M14'})}),
        case('ws_plain_hub_adapter', 'hub_small_part', {'hub_part_kind': 'Adaptador de eje',
            interface: rows({'scope': 'Entrada', 'interface_kind': plain, 'diameter_unit': 'mm', 'diameter_mm': '15'},
                            {'scope': 'Salida', 'interface_kind': plain, 'diameter_unit': 'mm', 'diameter_mm': '12'})}),
        case('ws_plain_seat_is_not_thread', 'hub_small_part', {interface: rows({
            'scope': 'Entrada', 'interface_kind': plain, 'diameter_unit': 'mm', 'diameter_mm': '15',
            'pitch_mm': '1'})}, blocking=[('row_field_applicability', interface)]),
        case('ws_oem_125_pitch', 'wheel_retention', {interface: rows({
            'scope': 'TRA225 rosca', 'interface_kind': threaded, 'diameter_unit': 'mm', 'pitch_unit': 'mm',
            'diameter_mm': '12', 'pitch_mm': '1.25'})}, sources=[RAP]),
        case('ws_nipple_tool_axis', 'spoke_nipple', {drive: rows({
            'location': 'Exterior', 'shape': 'Cuadrada', 'dimension_mm': '3.23',
            'measurement_basis': 'Entre caras'})}, sources=[PARK_NIPPLE]),
        case('ws_nipple_square_not_splined', 'spoke_nipple', {drive: rows({
            'location': 'Exterior', 'shape': 'Cuadrada', 'spline_count': '6'})},
             blocking=[('row_field_applicability', drive)]),
        case('ws_nipple_datum_missing', 'spoke_nipple', {drive: rows({
            'location': 'Exterior', 'shape': 'Cuadrada', 'dimension_mm': '3.23'})},
             pending=[('row_required_missing', drive)]),
        case('ws_liner_nominal_without_bsd_inference', 'tire_liner', {liner: rows({
            'configuration': 'Ejemplo sintético', 'size_basis': nominal,
            'nominal_size': '700C', 'width_kind': width_range,
            'width_min': '28', 'width_max': '32', 'width_unit': 'mm'})}),
        case('ws_liner_width_unit_missing', 'tire_liner', {liner: rows({
            'configuration': 'Ejemplo', 'size_basis': bsd, 'bsd_mm': '622',
            'width_kind': width_range, 'width_min': '28', 'width_max': '32'})}, pending=[('row_required_missing', liner)]),
        case('ws_liner_reversed_width', 'tire_liner', {liner: rows({
            'configuration': 'Ejemplo', 'size_basis': nominal, 'nominal_size': '700C',
            'width_kind': width_range, 'width_min': '32', 'width_max': '28', 'width_unit': 'mm'})}, blocking=[('row_shape', liner)]),
        case('ws_liner_different_scope_rows', 'tire_liner', {liner: rows(
            {'configuration': 'A', 'size_basis': bsd, 'bsd_mm': '559', 'width_kind': width_range, 'width_min': '1.5', 'width_max': '2.0', 'width_unit': 'in'},
            {'configuration': 'B', 'size_basis': bsd, 'bsd_mm': '622', 'width_kind': width_range, 'width_min': '28', 'width_max': '32', 'width_unit': 'mm'})}),
        case('ws_vp1_material_scopes', 'tube_repair', {repair: rows(*[
            {'repair_component': 'Park Tool VP-1C, ficha leída 2026-09-07',
             'target': target, 'target_material': material, 'status': status,
             'target_model': 'Superficie de destino publicada para VP-1C',
             'source_url': PARK_PATCH}
            for target, material, status in [
                ('Cámara', 'Butilo', 'Compatible declarado'),
                ('Cámara', 'Látex', 'Compatible declarado'),
                ('Cámara', 'TPU', 'Incompatible declarado'),
                ('Cuerpo de neumático', 'Otro', 'Incompatible declarado')]])}, sources=[PARK_PATCH]),
        case('ws_repair_condition_missing', 'tube_repair', {repair: rows({
            'repair_component': 'Ejemplo', 'target': 'Cámara', 'target_material': 'Otro',
            'status': 'Condicionado'})}, pending=[('row_required_missing', repair)]),
        case('ws_repair_material_unknown', 'tube_repair', {repair: rows({
            'repair_component': 'Ejemplo', 'target': 'Cámara', 'status': 'Compatible declarado'})},
             pending=[('row_required_missing', repair)]),
        case('ws_plug_tool_unknown', 'tubeless_repair', {plugs: rows({
            'plug_model': 'Ejemplo', 'size_designation': 'Fina'})}, pending=[('row_incomplete', plugs)]),
        case('ws_tape_dimensions', 'tubeless_tape', {'tape_width_mm': '25', 'roll_length_m': '9'}),
        case('ws_valve_unknown_is_missing', 'valve_small_part', {valve: rows({
            'component': 'Tapa ejemplo', 'kind': cap})}, pending=[('row_incomplete', valve)]),
        case('ws_valve_direction_scoped', 'valve_small_part', {valve: rows({
            'component': 'Adaptador ejemplo', 'kind': adapter,
            'input_valve': 'Presta', 'output_connection': 'Schrader'})}),
        case('ws_valve_cap_cannot_have_extension', 'valve_small_part', {valve: rows({
            'component': 'Tapa ejemplo', 'kind': cap, 'input_valve': 'Presta',
            'extension_length_mm': '40'})}, blocking=[('row_field_applicability', valve)]),
        case('ws_valve_relocated_core', 'valve_small_part', {valve: rows({
            'component': 'Topeak TFV-05', 'kind': extender, 'input_valve': 'Presta',
            'extension_kind': relocated, 'requires_removable_core': True,
            'extension_length_mm': '28'})},
             sources=['https://www.topeak.com/us/en/product/1440-VALVE-EXTENDER-28MM']),
        case('ws_valve_relocation_cannot_deny_removal', 'valve_small_part', {valve: rows({
            'component': 'Alargador sintético', 'kind': extender, 'input_valve': 'Presta',
            'extension_kind': relocated, 'requires_removable_core': False})},
             blocking=[('row_value_conflict', valve)]),
        case('ws_valve_other_extension_no_inference', 'valve_small_part', {valve: rows({
            'component': 'Alargador sintético', 'kind': extender, 'input_valve': 'Presta',
            'extension_kind': external, 'requires_removable_core': False})}),
        case('ws_imperial_thread', 'hub_axle', {interface: rows({
            'scope': 'Rosca ejemplo', 'interface_kind': threaded, 'diameter_unit': 'in', 'pitch_unit': 'tpi',
            'diameter_in': '3/8', 'pitch_tpi': '26'})}),
        case('ws_imperial_thread_not_metric_pitch', 'hub_axle', {interface: rows({
            'scope': 'Rosca ejemplo', 'interface_kind': threaded, 'diameter_unit': 'in', 'pitch_unit': 'tpi',
            'diameter_in': '3/8', 'pitch_tpi': '26', 'pitch_mm': '1'})},
             blocking=[('row_field_applicability', interface)]),
        case('ws_axle_unscoped_length', 'hub_axle', {'axle_length_mm': '140'},
             pending=[('prerequisite_missing', 'axle_length_mm')]),
        case('ws_metric_diameter_tpi_axle', 'hub_axle', {interface: rows({
            'scope': 'Eje italiano, ejemplo de Park Tool', 'interface_kind': threaded,
            'diameter_unit': 'mm', 'diameter_mm': '10', 'pitch_unit': 'tpi', 'pitch_tpi': '26'})},
             sources=['https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts']),
        case('ws_thread_pitch_unit_unknown', 'hub_axle', {interface: rows({
            'scope': 'Rosca ejemplo', 'interface_kind': threaded,
            'diameter_unit': 'mm', 'diameter_mm': '10', 'pitch_tpi': '26'})},
             pending=[('row_prerequisite', interface)]),
    ])
    ret_base = {'component': 'Eje ejemplo', 'configuration': 'A', 'position': 'Trasera',
                'kind': thru, 'length_kind': exact, 'effective_length_mm': '174',
                'length_datum': 'Bajo cabeza a extremo', 'thread_interface_id': 'r1'}
    thread_value = rows({'scope': 'Rosca A', 'interface_kind': threaded, 'diameter_unit': 'mm', 'pitch_unit': 'mm',
                         'diameter_mm': '12', 'pitch_mm': '1.75'})
    fixtures['cases'].extend([
        case('ws_retention_linked_configuration', 'wheel_retention', {
            interface: thread_value, retention: rows(ret_base)}),
        case('ws_retention_dangling_thread', 'wheel_retention', {
            interface: thread_value, retention: rows({**ret_base, 'thread_interface_id': 'missing'})},
             blocking=[('row_reference_unresolved', retention)]),
        case('ws_retention_range_reversed', 'wheel_retention', {interface: thread_value,
            retention: rows({**{k: v for k, v in ret_base.items() if k != 'effective_length_mm'},
                             'length_kind': interval, 'length_min_mm': '172', 'length_max_mm': '160'})},
             blocking=[('row_shape', retention)]),
        case('ws_qr_pair_independent_lengths', 'wheel_retention', {retention: rows(*[
            {'component': component, 'configuration': 'A', 'position': position, 'kind': qr,
             'length_kind': exact, 'effective_length_mm': length, 'length_datum': 'Declaración sintética'}
            for component, position, length in [('Aguja A', 'Delantera', '100'), ('Aguja B', 'Trasera', '135')]])}),
    ])
    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Wheel small parts reviewed successor',
               'templates': list(templates.values()), 'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA},
               'mechanical_coverage_complete': False, 'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(templates), 'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in templates.values())}
    return catalog, fixtures


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'wheel-small-parts-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'wheel-small-parts-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
