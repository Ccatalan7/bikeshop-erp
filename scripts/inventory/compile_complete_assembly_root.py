"""Root adjudication of unpublished assemblies; never a model-wide SKU fill."""
from copy import deepcopy
from compile_mobility_accessories_catalog import case, condition, rows, remove_unpublished_field
from compile_wheel_small_parts_catalog import column, retire, table
from compile_hydraulic_parts_root import link, replace_table

FAMILIES = ('bicycle', 'frame', 'wheel')
SYNTHETIC = 'https://example.invalid/assembly-representation'
SURLY = 'https://surlybikes.com/products/cross_check_2000'
PREAMBLE = 'https://surlybikes.com/blogs/blog/a-preamble-to-the-surly-preamble'
IDENTITY, CONFIG = 'assembly_variant_identity', 'assembly_configurations'
GEOMETRY, WHEELS = 'frame_geometry_measurements', 'assembly_wheel_members'
COMPONENTS = 'assembly_component_members'
ALWAYS, NEVER = {'kind': 'always'}, {'kind': 'never'}


def schema(d, key):
    return d[key]['validation_rules']['rows_schema']


def config_column():
    return column('configuration_row_id', 'Configuración', 'text', required=True)


def source_columns():
    return [column('source_scope', 'Apartado y alcance', required=True),
            column('source_url', 'Fuente', 'url', required=True)]


def scoped_table(d, ts, key, label, families, columns, *, unique=(), **kwargs):
    table(d, ts, key, label, families, [config_column(), *columns], **kwargs)
    if unique:
        schema(d, key)['unique_by'] = [['configuration_row_id', *u] for u in unique]
    for f in families:
        link(ts[f], key + '_configuration', key, 'configuration_row_id', CONFIG, 'configuration')


def review_assemblies(d, ts, fixtures):
    # The proposal added Par, but the published shared definition has 3 values.
    # A wheelset is represented by its members, not a new shared scalar token.
    d['wheel_position']['allowed_values'] = ['Delantera', 'Trasera', 'Universal']
    d['bb_shell_width_mm']['allowed_values'] = [68, 70, 73, 83, 86.5, 89.5, 92, 100, 107, 121]
    d['rotor_mount_type']['allowed_values'] = ['6 pernos', 'Centerlock']
    table(d, ts, IDENTITY, 'Variante documentada', FAMILIES, [
        column('scope', 'Ámbito', 'token', required=True,
               options=['Esta variante de catálogo']),
        column('brand', 'Fabricante', required=True),
        column('model', 'Modelo', required=True),
        column('variant', 'Variante o código exacto', required=True),
        column('edition', 'Edición y alcance del modelo', required=True),
        column('size_label', 'Talla comercial de esta variante'),
        *source_columns(),
    ], required=True, helper='Identificación de la fuente para contrastar con la '
       'identidad del producto. Las otras tallas o '
       'variantes del catálogo del fabricante pertenecen a otros productos; '
       'no se reúnen aquí. Lo desconocido queda pendiente.')
    schema(d, IDENTITY)['unique_by'] = [['scope']]
    table(d, ts, CONFIG, 'Configuraciones de esta variante', FAMILIES, [
        column('variant_row_id', 'Variante de producto', 'text', required=True),
        column('configuration', 'Configuración completa', required=True),
        column('state', 'Qué declara', 'token', required=True,
               options=['Suministrada', 'Alternativa OEM documentada']),
        column('conditions', 'Condiciones y piezas necesarias'),
        *source_columns(),
    ], required=True, conditions={'conditions': condition('state', 'Alternativa OEM documentada')},
       helper='Un montaje suministrado y una alternativa documentada no se suman. '
       'Cada configuración pertenece a esta variante y conserva su fuente.')
    schema(d, CONFIG)['unique_by'] = [['variant_row_id', 'configuration']]
    for f in FAMILIES:
        link(ts[f], 'assembly_configuration_variant', CONFIG, 'variant_row_id', IDENTITY, 'variant')

    # A size label is not a row identifier. Geometry and rider guidance refer to
    # the exact configuration; the label belongs once to the product variant.
    for f in ('bicycle', 'frame'):
        retire(ts[f], ['frame_size_label'])
    g = schema(d, GEOMETRY)
    g['columns'] = [config_column(), *[c for c in g['columns'] if c['key'] != 'size_label']]
    g['columns'].extend([
        column('offset_value', 'Desnivel con signo publicado', 'decimal'),
        column('source_scope', 'Apartado y configuración de medición', required=True)])
    measure = next(c for c in g['columns'] if c['key'] == 'measure')
    measure['allowed_values'].extend(['Longitud del tubo de dirección', 'Longitud de horquilla',
                                      'Avance de horquilla', 'Desnivel firmado del pedalier'])
    next(c for c in g['columns'] if c['key'] == 'value').pop('required', None)
    next(c for c in g['columns'] if c['key'] == 'unit')['allowed_values'] = ['mm', 'cm', 'in', 'grados']
    g['unique_by'] = [['configuration_row_id', 'measure', 'datum', 'source_scope']]
    angles = ['Ángulo de dirección', 'Ángulo de sillín']
    lengths = [v for v in measure['allowed_values'] if v not in angles]
    unsigned = [v for v in measure['allowed_values'] if v != 'Desnivel firmado del pedalier']
    for f in ('bicycle', 'frame'):
        rc = ts[f]['form_contract']['row_conditions']['fields'][GEOMETRY]
        rc.update(allowed_when={
            'value': condition('measure', unsigned),
            'offset_value': condition('measure', 'Desnivel firmado del pedalier')},
            required_when={'value': condition('measure', unsigned),
                           'offset_value': condition('measure', 'Desnivel firmado del pedalier')})
        # Degrees cannot describe a length. Independent units remain explicit.
        linear = condition('measure', [v for v in lengths if v in unsigned])
        linear['rows'][0].extend(condition('unit', ['mm', 'cm', 'in'])['rows'][0])
        linear['rows'].extend(condition('measure', angles)['rows'])
        rc['allowed_when']['value'] = linear
        signed = condition('measure', 'Desnivel firmado del pedalier')
        signed['rows'][0].extend(condition('unit', ['mm', 'cm', 'in'])['rows'][0])
        rc['allowed_when']['offset_value'] = signed
        link(ts[f], 'geometry_configuration', GEOMETRY, 'configuration_row_id', CONFIG, 'configuration')
        ts[f]['form_contract']['helpers'][GEOMETRY] = (
            'Medidas de esta variante y configuración. Conservar unidad, datum '
            'y condiciones; no tomar otra columna de talla de la tabla OEM. '
            'Un datum sin publicar queda vacío y pendiente, no se inventa.')

    sizekey = 'bicycle_size_configurations'
    s = schema(d, sizekey)
    s['columns'] = [config_column(), *[c for c in s['columns'] if c['key'] != 'size_label']]
    s['unique_by'] = [['configuration_row_id']]
    link(ts['bicycle'], 'rider_recommendation_configuration', sizekey, 'configuration_row_id', CONFIG, 'configuration')
    ts['bicycle']['form_contract']['helpers'][sizekey] = (
        'Recomendación OEM para esta variante. No equivale a garantizar ajuste '
        'corporal ni representa las tallas de otros productos.')

    build_wheel_members(d, ts)
    build_components_and_interfaces(d, ts)
    translate_cases(fixtures)
    fixtures['cases'].extend(root_cases())
    for t in ts.values():
        c = t['form_contract']
        for key in list(c.get('row_conditions', {}).get('fields', {})):
            if c['roles'].get(key) == 'legacy':
                c['row_conditions']['fields'].pop(key)
        for key in (IDENTITY, CONFIG):
            c['roles'][key] = 'primary'
            c['semantic_roles'][key] = 'intrinsic'
            next(f for f in t['fields'] if f['key'] == key)['section_key'] = 'primary'
        t['fields'].sort(key=lambda f: (0 if f['key'] == IDENTITY else
            1 if f['key'] == CONFIG else 3 if c['roles'][f['key']] == 'legacy' else 2,
            f['sort_order']))
        for i, f in enumerate(t['fields']):
            f['sort_order'] = i * 10


def build_wheel_members(d, ts):
    # Physical wheels carry all their ports, including the fields previously
    # global for a pair: bead profile, valve, spoke count and tubeless declaration.
    retired = [f['key'] for f in ts['wheel']['fields'] if f['key'] not in
               (IDENTITY, CONFIG, 'spec_evidence_source', 'wheel_compatible_claims', 'kit_members')]
    retire(ts['wheel'], retired)
    retire(ts['bicycle'], ['bicycle_wheel_positions', 'max_tire_width_mm', 'rear_drive_interface',
                          'brake_system_kind'])
    scoped_table(d, ts, WHEELS, 'Ruedas de cada montaje', ('wheel', 'bicycle'), [
        column('member', 'Rueda física', required=True),
        column('position', 'Posición', 'token', required=True,
               options=['Delantera', 'Trasera', 'Lateral u otra posición OEM']),
        column('model', 'Modelo y edición de rueda o maza'),
        column('bead_seat_diameter_mm', 'Diámetro de asiento de talón', 'decimal', unit='mm', positive=True),
        column('rim_internal_width_mm', 'Ancho interior', 'decimal', unit='mm', positive=True),
        column('rim_bead_profile', 'Perfil de asiento', 'token', options=d['rim_bead_profile']['allowed_values']),
        column('rim_tubeless_ready', 'Declarada tubeless ready', 'boolean'),
        column('brake_track', 'Pista de frenado', 'boolean'),
        column('hub_old_mm', 'OLD entre apoyos', 'decimal', unit='mm', positive=True),
        column('axle_type', 'Retención publicada'),
        column('valve_hole_mm', 'Orificio de válvula publicado', 'decimal', unit='mm', positive=True),
        {**column('spoke_count', 'Rayos', 'integer'), 'validation': {'min': '0'}},
        column('drive_present', 'Tiene interfaz de transmisión', 'boolean'),
        column('drive_interface', 'Interfaz de transmisión publicada'),
        column('disc_present', 'Tiene montaje para disco', 'boolean'),
        column('rotor_mount', 'Montaje de rotor', 'token',
               options=['6 pernos', 'Centerlock', 'Otra interfaz OEM']),
        column('frame_brake_mount', 'Montaje del cáliper en cuadro u horquilla'),
        column('max_rotor_mm', 'Rotor máximo de esta configuración', 'decimal', unit='mm', positive=True),
        column('rotor_fitted_mm', 'Rotor suministrado', 'decimal', unit='mm', positive=True),
        column('conditions', 'Condiciones y piezas del montaje'), *source_columns(),
    ], required=True, unique=[['member']], ordered=[['rotor_fitted_mm', 'max_rotor_mm']],
       conditions={'drive_interface': condition('drive_present', True, 'boolean'),
                   **{k: condition('disc_present', True, 'boolean') for k in
                      ['rotor_mount', 'frame_brake_mount', 'max_rotor_mm', 'rotor_fitted_mm']}},
       helper='Cada rueda conserva medidas y montajes propios. Compartir diámetro '
       'no aprueba cubierta ni cassette. La posición delantera no prohíbe por sí '
       'sola una transmisión documentada; declarar el puerto que existe.')
    # Optional OEM maximum and supplied rotor are independent; do not require
    # every unknown maximum just because a disc interface is present.
    for f in ('bicycle', 'wheel'):
        rc = ts[f]['form_contract']['row_conditions']['fields'][WHEELS]
        for k in ['frame_brake_mount', 'max_rotor_mm', 'rotor_fitted_mm']:
            rc['required_when'].pop(k, None)
    claims = 'wheel_compatible_claims'
    schema(d, claims)['columns'].insert(0, column('wheel_row_id', 'Rueda de este montaje', 'text', required=True))
    schema(d, claims)['unique_by'][0].insert(0, 'wheel_row_id')
    link(ts['wheel'], 'wheel_claim_member', claims, 'wheel_row_id', WHEELS, 'member')


def build_components_and_interfaces(d, ts):
    # Complete-bicycle properties belong to an assembled circuit, not to a
    # catalogue-wide combination of every drivetrain and electric option.
    retire(ts['bicycle'], ['rear_speeds', 'chainring_count', 'fork_travel_mm',
        'rear_shock_size', 'ebike_motor_kind', 'ebike_battery_wh',
        'ebike_battery_voltage_v', 'ebike_charger_connector'])
    drive = 'bicycle_drive_configurations'
    scoped_table(d, ts, drive, 'Transmisión de cada montaje', ('bicycle',), [
        column('drive_kind', 'Transmisión', 'token', required=True,
            options=['Cadena', 'Correa', 'Directa', 'Sin transmisión a pedales', 'Otra OEM']),
        column('rear_external_gears', 'Coronas externas', 'integer', positive=True),
        column('hub_internal_gears', 'Relaciones internas de maza', 'integer', positive=True),
        column('front_chainrings', 'Platos para cadena', 'integer', positive=True),
        column('electric_assistance', 'Asistencia eléctrica', 'boolean'),
        column('system_model', 'Sistema completo y edición'),
        column('conditions', 'Configuración publicada'), *source_columns(),
    ], unique=[[]], conditions={
        'front_chainrings': condition('drive_kind', 'Cadena'),
        'rear_external_gears': condition('drive_kind', ['Cadena', 'Otra OEM']),
        'hub_internal_gears': condition('drive_kind', ['Cadena', 'Correa', 'Otra OEM'])},
       helper='Coronas externas y relaciones internas son conteos distintos. '
       'No multiplicarlos para inventar una compatibilidad de mando o cadena.')
    rc = ts['bicycle']['form_contract']['row_conditions']['fields'][drive]
    rc['required_when'].pop('rear_external_gears', None)
    rc['required_when'].pop('hub_internal_gears', None)

    scoped_table(d, ts, COMPONENTS, 'Componentes de este montaje', FAMILIES, [
        column('member', 'Pieza física y posición', required=True),
        column('kind', 'Tipo de pieza', 'token', required=True, options=[
            'Cuadro', 'Horquilla', 'Amortiguador', 'Motor', 'Batería', 'Cargador',
            'Mando', 'Freno', 'Transmisión', 'Accesorio', 'Otro componente OEM']),
        column('brand', 'Fabricante'), column('model', 'Modelo y variante exactos'),
        column('edition', 'Edición o sistema'),
        column('quantity', 'Cantidad suministrada', 'integer', required=True, positive=True),
        column('conditions', 'Piezas incluidas y configuración'), *source_columns(),
    ], unique=[['member']], helper='Componentes suministrados en este montaje. '
       'Una alternativa autorizada usa otra configuración; no aumenta lo '
       'incluido en la caja. El modelo identifica, no aprueba otros modelos.')
    suspension = 'assembly_suspension_declarations'
    scoped_table(d, ts, suspension, 'Suspensión de este montaje', ('bicycle', 'frame'), [
        column('component_row_id', 'Componente', 'text', required=True),
        column('kind', 'Qué se mide', 'token', required=True, options=['Horquilla', 'Amortiguador']),
        column('travel_mm', 'Recorrido de horquilla publicado', 'decimal', unit='mm', positive=True),
        column('axle_to_crown_mm', 'Eje a corona publicado', 'decimal', unit='mm', positive=True),
        column('eye_to_eye_mm', 'Largo entre puntos publicados', 'decimal', unit='mm', positive=True),
        column('stroke_mm', 'Carrera del amortiguador', 'decimal', unit='mm', positive=True),
        column('datum', 'Puntos de medición y posición de suspensión', required=True),
        column('mounting', 'Montajes y herrajes declarados'), *source_columns(),
    ], unique=[['component_row_id']], conditions={
        **{k: condition('kind', 'Horquilla') for k in ['travel_mm', 'axle_to_crown_mm']},
        **{k: condition('kind', 'Amortiguador') for k in ['eye_to_eye_mm', 'stroke_mm']}},
       helper='Recorrido de horquilla, distancia entre ojos y carrera de '
       'amortiguador no son la misma medida. Conservar datum y piezas del montaje.')
    for f in ('frame', 'bicycle'):
        link(ts[f], 'suspension_component', suspension, 'component_row_id', COMPONENTS, 'member')
        ts[f]['form_contract']['row_conditions']['fields'][suspension]['required_when'] = {}

    electric = 'assembly_electrical_declarations'
    scoped_table(d, ts, electric, 'Sistema eléctrico documentado', ('bicycle',), [
        column('component_row_id', 'Componente eléctrico', 'text', required=True),
        column('role', 'Función eléctrica', 'token', required=True,
            options=['Batería', 'Motor', 'Cargador', 'Mando o pantalla', 'Otro componente']),
        column('system_model', 'Sistema y generación', required=True),
        column('nominal_voltage_v', 'Tensión nominal', 'decimal', unit='V', positive=True),
        column('battery_energy_wh', 'Energía de esta batería', 'decimal', unit='Wh', positive=True),
        column('charger_output_voltage_v', 'Tensión de salida del cargador', 'decimal', unit='V', positive=True),
        column('connector', 'Conector y puerto declarados'),
        column('protocol', 'Protocolo o condición de software publicada'),
        column('conditions', 'Requisitos OEM de esta instalación'), *source_columns(),
    ], unique=[['component_row_id']], conditions={
        'battery_energy_wh': condition('role', 'Batería'),
        'charger_output_voltage_v': condition('role', 'Cargador')},
       helper='La energía pertenece a cada batería; no se duplica como total. '
       'Tensión nominal y salida de cargador son datos diferentes. Voltaje o '
       'conector coincidentes no aprueban un circuito ni otra generación.')
    ts['bicycle']['form_contract']['row_conditions']['fields'][electric]['required_when'] = {}
    link(ts['bicycle'], 'electric_component', electric, 'component_row_id', COMPONENTS, 'member')

    # These intrinsic measurements must use the same row that owns the physical
    # component's kind. A mere row_id link cannot prove that a separate row
    # calling itself a battery points to a battery, or to the same configuration.
    # Fold the typed declarations into that owner instead of adding a join rule
    # the shared engine does not implement.
    component_columns = schema(d, COMPONENTS)['columns']
    existing_columns = {c['key'] for c in component_columns}
    member_conditions = {}
    for child in (suspension, electric):
        for c in schema(d, child)['columns']:
            if c['key'] in existing_columns or c['key'] in ('component_row_id', 'role'):
                continue
            c = deepcopy(c)
            c.pop('required', None)
            component_columns.append(c)
            existing_columns.add(c['key'])
    member_conditions.update({k: condition('kind', 'Horquilla') for k in
                              ['travel_mm', 'axle_to_crown_mm']})
    member_conditions.update({k: condition('kind', 'Amortiguador') for k in
                              ['eye_to_eye_mm', 'stroke_mm']})
    member_conditions.update({
        'battery_energy_wh': condition('kind', 'Batería'),
        'charger_output_voltage_v': condition('kind', 'Cargador'),
        **{k: condition('kind', ['Motor', 'Batería', 'Cargador', 'Mando', 'Otro componente OEM'])
           for k in ['system_model', 'nominal_voltage_v', 'connector', 'protocol']}})
    for f in FAMILIES:
        c = ts[f]['form_contract']
        c.setdefault('row_conditions', {'version': 1, 'fields': {}})['fields'][COMPONENTS] = {
            'allowed_when': deepcopy(member_conditions)}
        for child in (suspension, electric):
            if any(v['key'] == child for v in ts[f]['fields']):
                remove_unpublished_field(ts[f], child)
                c['row_conditions']['fields'].pop(child, None)
                c['row_coherence']['links'] = [v for v in c['row_coherence']['links']
                                              if v['field'] != child]

    # Intrinsic frame ports and OEM accepted targets must not share ownership.
    frame_fields = ['bb_shell_interface', 'bb_shell_width_mm', 'headset_upper_shis',
        'headset_lower_shis', 'seatpost_diameter_mm', 'seat_tube_outer_diameter_mm',
        'rear_derailleur_hanger_interface']
    for f in ('bicycle', 'frame'):
        retire(ts[f], frame_fields)
    retire(ts['frame'], ['rear_bead_seat_diameter_mm', 'max_tire_width_mm',
        'rear_hub_old_mm', 'rear_axle_type', 'thru_axle_thread', 'brake_mount_rear',
        'max_rotor_rear_mm', 'front_derailleur_mount', 'seat_tube_outer_for_fd_mm',
        'rear_shock_size', 'iscg_tabs', 'bottle_bosses_count', 'rack_mounts',
        'headset_port_configurations', 'dropout_hub_acceptance_configurations'])
    ports = 'assembly_frame_interfaces'
    structured, plain, literal = 'Rosca medida', 'Asiento sin rosca', 'Designación OEM sin descomponer'
    scoped_table(d, ts, ports, 'Interfaces del cuadro y horquilla', ('bicycle', 'frame'), [
        column('interface', 'Puerto físico y posición', required=True),
        column('port_kind', 'Función del puerto', 'token', required=True, options=[
            'Caja de pedalier', 'Dirección superior', 'Dirección inferior',
            'Asiento de tija', 'Asiento de abrazadera', 'Puntera trasera',
            'Puntera delantera', 'Anclaje de freno', 'Patilla de cambio',
            'Desviador delantero', 'Guía ISCG', 'Suspensión', 'Accesorio', 'Otro OEM']),
        column('form', 'Descripción de la interfaz', 'token', required=True,
               options=[structured, plain, literal]),
        column('diameter', 'Diámetro nominal del puerto', 'decimal', positive=True),
        column('diameter_unit', 'Unidad de diámetro', 'token', options=['mm', 'in']),
        column('pitch', 'Paso o hilos por pulgada', 'decimal', positive=True),
        column('pitch_unit', 'Unidad del paso', 'token', options=['mm', 'tpi']),
        column('thread_hand', 'Sentido', 'token', options=['Derecha', 'Izquierda']),
        column('width_mm', 'Ancho del puerto', 'decimal', unit='mm', positive=True),
        column('depth_mm', 'Profundidad útil', 'decimal', unit='mm', positive=True),
        column('designation', 'Designación OEM completa'),
        column('datum', 'Puntos medidos y condiciones', required=True), *source_columns(),
    ], unique=[['interface']], conditions={
        **{k: condition('form', [structured, plain]) for k in ['diameter', 'diameter_unit']},
        **{k: condition('form', structured) for k in ['pitch', 'pitch_unit', 'thread_hand']},
        'designation': condition('form', literal)},
       helper='Lo que tiene el cuadro o la horquilla. El alojamiento, la cazoleta '
       'y la pieza admitida son objetos distintos. Un pedalier con copas roscadas '
       'entre sí puede montar en una caja lisa: no trasladar esa rosca al cuadro.')

    limits = 'assembly_frame_fitment_claims'
    scoped_table(d, ts, limits, 'Montajes admitidos por el fabricante', ('bicycle', 'frame'), [
        column('location', 'Zona o posición de montaje', required=True),
        column('target_kind', 'Pieza admitida', 'token', required=True, options=[
            'Neumático', 'Maza', 'Horquilla', 'Amortiguador', 'Freno',
            'Pedalier', 'Dirección', 'Transmisión', 'Accesorio', 'Otro OEM']),
        column('target_model', 'Modelo o estándar completo declarado', required=True),
        column('target_edition', 'Edición y alcance', required=True),
        column('status', 'Declaración', 'token', required=True, options=[
            'Compatible declarado', 'Incompatible declarado', 'Condicionado']),
        column('bsd_mm', 'BSD de esta aplicación', 'decimal', unit='mm', positive=True),
        column('max_tire_width_mm', 'Ancho máximo publicado', 'decimal', unit='mm', positive=True),
        column('rim_context', 'Llanta de referencia de la cubierta'),
        column('fender_present', 'Con guardabarros', 'boolean'),
        column('accepted_hub_old_mm', 'OLD de la maza admitida', 'decimal', unit='mm', positive=True),
        column('conditions', 'Condiciones y piezas necesarias'), *source_columns(),
    ], unique=[['location', 'target_kind', 'target_model', 'target_edition', 'source_scope']],
       conditions={**{k: condition('target_kind', 'Neumático') for k in
                       ['bsd_mm', 'max_tire_width_mm', 'rim_context', 'fender_present']},
                   'accepted_hub_old_mm': condition('target_kind', 'Maza'),
                   'conditions': condition('status', 'Condicionado')},
       helper='Una holgura o un OLD admitido conserva rueda, montaje, guardabarros '
       'y fuente. La anchura intrínseca del cuadro no es el conjunto de anchos '
       'de maza permitidos. Una declaración condicionada necesita sus condiciones.')
    for f in ('frame', 'bicycle'):
        r = ts[f]['form_contract']['row_conditions']['fields'][limits]
        r['required_when'] = {'conditions': condition('status', 'Condicionado')}
        # Conditions may qualify even a positive or negative OEM declaration.
        r['allowed_when'].pop('conditions', None)


def identity(size='M'):
    return {'scope': 'Esta variante de catálogo', 'brand': 'Marca sintética',
            'model': 'Modelo sintético', 'variant': 'Variante ' + size,
            'size_label': size, 'edition': 'Edición sintética',
            'source_scope': 'Ficha de esta variante', 'source_url': SYNTHETIC}


def configuration(**kw):
    return dict({'variant_row_id': 'r1', 'configuration': 'Montaje suministrado',
                 'state': 'Suministrada', 'source_scope': 'Montaje',
                 'source_url': SYNTHETIC}, **kw)


def baseline(**values):
    return {IDENTITY: rows(identity()), CONFIG: rows(configuration()), **values}


def wheel(**kw):
    return dict({'configuration_row_id': 'r1', 'member': 'Delantera',
                 'position': 'Delantera', 'source_scope': 'Montaje sintético',
                 'source_url': SYNTHETIC}, **kw)


def translate_cases(fixtures):
    # The five frozen regressions remain byte-for-byte. Only the unpublished
    # Claude candidate cases are translated with explicit adjudication.
    for c in fixtures['cases']:
        if not c['id'].startswith('ca_'):
            continue
        v = c['values']
        labels = []
        for key in (GEOMETRY, 'bicycle_size_configurations'):
            for row in v.get(key, {}).get('rows', []):
                label = row['values'].get('size_label', 'M')
                if label not in labels:
                    labels.append(label)
        labels = labels or ['M']
        v[IDENTITY] = rows(*(identity(label) for label in labels))
        v[CONFIG] = rows(*(configuration(variant_row_id='r' + str(i + 1))
                           for i in range(len(labels))))
        for key in (GEOMETRY, 'bicycle_size_configurations'):
            for row in v.get(key, {}).get('rows', []):
                rv = row['values']
                label = rv.pop('size_label', 'M')
                rv['configuration_row_id'] = 'r' + str(labels.index(label) + 1)
                if key == GEOMETRY:
                    rv['source_scope'] = 'Medición sintética'
                rv['source_url'] = SYNTHETIC
                if rv.get('datum') == 'No especificado por la fuente':
                    rv.pop('datum')
        if c['id'] == 'ca_two_sizes_keep_their_own_geometry':
            c['expected_blocking'] = [{'code': 'row_shape', 'field': IDENTITY}]
            c['successor_translation'] = ('Una ficha de SKU no es el catálogo de tallas. '
                'Los datos conservan dos identidades y ahora se rechaza unirlas.')
        if c['id'] == 'ca_source_does_not_state_its_datum':
            c['expected_issue_subset'] = [{'code': 'row_incomplete', 'field': GEOMETRY, 'blocking': False}]
            c['expected_sql_issue_subset'] = deepcopy(c['expected_issue_subset'])
        ws = []
        for old in ('bicycle_wheel_positions', 'wheel_configurations'):
            for row in v.pop(old, {}).get('rows', []):
                rv = row['values']
                rv.update(configuration_row_id='r1', member=rv['position'],
                          source_scope='Montaje sintético', source_url=SYNTHETIC)
                mount = rv.pop('brake_mount', None)
                if mount:
                    rv['disc_present'] = mount != 'Sin freno de disco'
                    if rv['disc_present']:
                        rv['frame_brake_mount'] = mount
                ws.append(rv)
        position = v.pop('wheel_position', None)
        if position in ('Delantera', 'Trasera'):
            rv = wheel(position=position, member=position)
            for key in ('bead_seat_diameter_mm', 'hub_old_mm', 'axle_type'):
                if key in v:
                    rv[key] = v.pop(key)
            ws.append(rv)
        if ws:
            v[WHEELS] = rows(*ws)
        for row in v.get('wheel_compatible_claims', {}).get('rows', []):
            row['values'].update(wheel_row_id='r1', source_url=SYNTHETIC)
        for bucket in ('expected_blocking', 'expected_sql_blocking',
                       'expected_issue_subset', 'expected_sql_issue_subset'):
            for issue in c.get(bucket, []):
                if issue['field'] in ('bicycle_wheel_positions', 'wheel_configurations'):
                    issue['field'] = WHEELS
        c['source_urls'] = []
        c.setdefault('successor_translation', 'Campos del candidato no publicado movidos '
                     'a su variante/configuración/rueda explícitas. Cifras sintéticas; '
                     'no son lectura de un modelo OEM ni receta de llenado.')


def root_cases():
    result = []
    def add(id_, family, values, **kw):
        result.append(case('ca_root_' + id_, family, baseline(**values), **kw))
    add('second_product_variant_is_not_an_assembly_option', 'bicycle',
        {IDENTITY: rows(identity('M'), identity('L'))}, blocking=[('row_shape', IDENTITY)])
    add('dangling_variant_cannot_own_a_configuration', 'frame',
        {CONFIG: rows(configuration(variant_row_id='missing'))},
        blocking=[('row_reference_unresolved', CONFIG)])
    add('two_oem_mountings_belong_to_one_variant', 'frame',
        {CONFIG: rows(configuration(), configuration(configuration='Montaje B',
          state='Alternativa OEM documentada', conditions='Piezas OEM y ajuste'))})
    add('undeclared_alternative_conditions_stay_pending', 'frame',
        {CONFIG: rows(configuration(state='Alternativa OEM documentada'))},
        pending=[('row_required_missing', CONFIG)])
    add('front_and_rear_bead_profiles_stay_separate', 'wheel',
        {WHEELS: rows(wheel(rim_bead_profile='Con gancho (hooked)'),
          wheel(member='Trasera', position='Trasera', rim_bead_profile='Sin gancho (hookless)'))})
    add('member_identity_blocks_two_widths_for_one_wheel', 'wheel',
        {WHEELS: rows(wheel(hub_old_mm='100'), wheel(hub_old_mm='110'))},
        blocking=[('row_shape', WHEELS)])
    add('wheel_cannot_float_between_mountings', 'wheel',
        {WHEELS: rows(wheel(configuration_row_id='missing'))},
        blocking=[('row_reference_unresolved', WHEELS)])
    add('disc_wheel_can_have_zero_wire_spokes', 'wheel',
        {WHEELS: rows(wheel(spoke_count='0'))})
    add('non_disc_wheel_cannot_hold_a_rotor_mount', 'wheel',
        {WHEELS: rows(wheel(disc_present=False, rotor_mount='6 pernos'))},
        blocking=[('row_field_applicability', WHEELS)])
    add('no_drive_port_cannot_hold_a_freehub', 'wheel',
        {WHEELS: rows(wheel(drive_present=False, drive_interface='HG'))},
        blocking=[('row_field_applicability', WHEELS)])
    geometry = dict(configuration_row_id='r1', measure='Tubo superior',
        value='560', unit='mm', datum='Longitud efectiva', source_scope='Sintético', source_url=SYNTHETIC)
    add('linear_measure_cannot_use_degrees', 'frame',
        {GEOMETRY: rows(dict(geometry, unit='grados'))},
        blocking=[('row_field_applicability', GEOMETRY)])
    signed = {k:v for k,v in geometry.items() if k != 'value'}
    signed.update(measure='Desnivel firmado del pedalier', offset_value='-5',
                  datum='Convención con signo explícita de la fuente')
    add('signed_bottom_bracket_offset_is_not_a_negative_length', 'frame', {GEOMETRY: rows(signed)})
    add('geometry_cannot_link_another_absent_configuration', 'frame',
        {GEOMETRY: rows(dict(geometry, configuration_row_id='missing'))},
        blocking=[('row_reference_unresolved', GEOMETRY)])
    member = dict(configuration_row_id='r1', member='Batería principal', kind='Batería',
        quantity='1', battery_energy_wh='500', nominal_voltage_v='36',
        source_scope='Sintético', source_url=SYNTHETIC)
    add('two_batteries_retain_per_pack_energy', 'bicycle',
        {COMPONENTS: rows(member, dict(member, member='Batería auxiliar', battery_energy_wh='250'))})
    add('battery_energy_cannot_belong_to_a_fork', 'bicycle',
        {COMPONENTS: rows(dict(member, kind='Horquilla'))},
        blocking=[('row_field_applicability', COMPONENTS)])
    result[-1]['expected_sql_blocking'] = [
        {'code': 'row_field_applicability', 'field': COMPONENTS},
        {'code': 'row_field_applicability', 'field': COMPONENTS}]
    add('charger_output_is_not_a_battery_nominal_voltage', 'bicycle',
        {COMPONENTS: rows(dict(member, charger_output_voltage_v='42'))},
        blocking=[('row_field_applicability', COMPONENTS)])
    ports = 'assembly_frame_interfaces'
    port = dict(configuration_row_id='r1', interface='Caja BB', port_kind='Caja de pedalier',
        form='Asiento sin rosca', diameter='46', diameter_unit='mm', width_mm='86.5',
        datum='Alojamiento del cuadro sintético', source_scope='Sintético', source_url=SYNTHETIC)
    add('cup_thread_does_not_make_a_smooth_frame_threaded', 'frame',
        {ports: rows(dict(port, pitch='24', pitch_unit='tpi'))},
        blocking=[('row_field_applicability', ports)])
    result[-1]['expected_sql_blocking'] = [
        {'code': 'row_field_applicability', 'field': ports},
        {'code': 'row_field_applicability', 'field': ports}]
    add('metric_diameter_and_imperial_pitch_independent', 'frame',
        {ports: rows(dict(port, form='Rosca medida', diameter='10', pitch='26',
                         pitch_unit='tpi', thread_hand='Derecha'))})
    drive = 'bicycle_drive_configurations'
    add('belt_has_no_chainring_count', 'bicycle',
        {drive: rows(dict(configuration_row_id='r1', drive_kind='Correa',
                          front_chainrings='2', source_scope='Sintético', source_url=SYNTHETIC))},
        blocking=[('row_field_applicability', drive)])
    add('internal_and_external_gear_counts_remain_distinct', 'bicycle',
        {drive: rows(dict(configuration_row_id='r1', drive_kind='Cadena',
                          front_chainrings='1', rear_external_gears='9', hub_internal_gears='3',
                          source_scope='Sintético', source_url=SYNTHETIC))})
    claims = 'assembly_frame_fitment_claims'
    clearance = dict(configuration_row_id='r1', location='Paso de rueda', target_kind='Neumático',
        target_model='700c nominal publicado', target_edition='Página legacy Cross-Check',
        status='Condicionado', conditions='Depende de cubierta, llanta, posición del eje y otros factores',
        source_scope='Tire Clearance', source_url=SURLY)
    add('surly_clearance_keeps_fender_conditions', 'frame', {
        CONFIG: rows(configuration(), configuration(configuration='Con guardabarros',
            state='Alternativa OEM documentada', conditions='Guardabarros y límites OEM')),
        claims: rows(dict(clearance, max_tire_width_mm='42', fender_present=False),
                     dict(clearance, configuration_row_id='r2', max_tire_width_mm='40', fender_present=True))
    }, sources=[SURLY])
    return result
