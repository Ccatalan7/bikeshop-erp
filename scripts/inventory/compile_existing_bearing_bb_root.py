"""OEM adjudication of the original bearing/BB candidate; never writes data.

Enduro S7806 explicitly has an inner chamfer, independently of its rolling
contact geometry. Wheels BB86-OUT-BB has a declared shell-width range and
separately packaged spacers. Neither fact can be collapsed into a global scalar.
See existing-bearing-bb-root-decisions-2026-09-07.md for source scope.
"""
from copy import deepcopy

from compile_mobility_accessories_catalog import add_field, case, condition, new_definition, rows
from compile_wheel_small_parts_catalog import NEVER, column, retire, table

ALWAYS = {'kind': 'always'}
BEARING, BB, AXLE, BB_BEARING, CUP = (
    'bearing', 'bottom_bracket', 'bottom_bracket_axle',
    'bottom_bracket_bearing', 'bottom_bracket_cup')
CARTRIDGE, LOOSE, CAGED = 'Cartucho', 'Bolas sueltas', 'Canastillo con bolas'
MEMBERS, MOUNTS = 'bb_supplied_bearing_members', 'bb_installation_claims'
SYNTHETIC = 'https://example.invalid/root-bearing-boundary'
INNER, OUTER = 'bearing_inner_contact_angle_deg', 'bearing_outer_contact_angle_deg'
GEOMETRY = 'bearing_seat_geometry'


def all_of(*conditions):
    result = deepcopy(conditions[0])
    for extra in conditions[1:]:
        result['rows'][0].extend(deepcopy(extra['rows'][0]))
    return result


def source_columns():
    return [column('source_scope', 'Apartado y alcance de la fuente', required=True),
            column('source_url', 'Fuente', 'url', required=True)]


def add_definition(d, ts, key, label, dtype, families, **kwargs):
    d[key] = new_definition(key, label, dtype, families, **kwargs)
    for family in families:
        add_field(ts[family], key, 'measurement', 'measurement')


def adjust_catalog(d, ts, base, live_fields):
    b = ts[BEARING]['form_contract']
    original = next(t for t in base['templates'] if t['key'] == BEARING)
    # These three proposed definitions were already correct. They describe the
    # physical bearing's support surfaces, not another product's empty cup.
    for key in (GEOMETRY, INNER, OUTER):
        d[key] = deepcopy(base['definitions'][key])
        ts[BEARING]['fields'].append(deepcopy(next(
            f for f in original['fields'] if f['key'] == key)))
        for section in ('roles', 'semantic_roles', 'helpers', 'evidence_requirements'):
            if key in original['form_contract'].get(section, {}):
                b.setdefault(section, {})[key] = deepcopy(original['form_contract'][section][key])
    cartridge = condition('bearing_supply_form', CARTRIDGE)
    b['allowed_when'][GEOMETRY] = deepcopy(cartridge)
    b['required_when'][GEOMETRY] = deepcopy(NEVER)
    for key, bevel in ((INNER, 'Sólo bisel interior'), (OUTER, 'Sólo bisel exterior')):
        gate = all_of(cartridge, condition(GEOMETRY, ['Biseles interior y exterior', bevel]))
        b['allowed_when'][key] = deepcopy(gate)
        b['required_when'][key] = deepcopy(gate)
    # Radial is a load classification and does not imply a missing or invalid
    # contact-angle value. NSK explicitly includes zero in this domain.
    b['allowed_when']['bearing_race_contact_angle_deg'] = deepcopy(cartridge)
    b['required_when']['bearing_race_contact_angle_deg'] = deepcopy(NEVER)
    b['helpers']['bearing_race_contact_angle_deg'] = (
        'Ángulo de rodadura declarado para este rodamiento y condición. No se '
        'deduce de los biseles de apoyo ni se exige si el OEM no lo publica.')
    # This definition is new and unpublished. "Radial" is a load class, not
    # the alternative to angular-contact construction. Do not infer deep groove
    # from that old token. Historical observations remain in their legacy field.
    d['bearing_race_type']['label'] = 'Construcción interna declarada'
    d['bearing_race_type']['allowed_values'] = [
        'Ranura profunda', 'Contacto angular', 'Otro diseño declarado',
        'Desconocido / sin confirmar']
    b['helpers']['bearing_race_type'] = (
        'Construcción que declara la fuente del modelo. «Radial» clasifica la '
        'carga y no permite deducir ranura profunda ni excluir contacto angular. '
        'Si sólo se conoce esa clasificación, la construcción sigue sin confirmar.')
    b['helpers']['ball_diameter_in'] = (
        'Diámetro de las bolas que se venden sueltas o en canastillo. No es '
        'el diámetro interno del cartucho ni se deduce del código.')

    b['required_when']['bearing_supply_form'] = deepcopy(ALWAYS)
    ts[BB_BEARING]['form_contract']['required_when']['bearing_supply_form'] = deepcopy(ALWAYS)
    ts[BB]['form_contract']['required_when']['includes_spindle'] = deepcopy(ALWAYS)
    ts[CUP]['form_contract']['required_when']['bearing_included'] = deepcopy(ALWAYS)

    # A cup still owns its seat when the bearing is included in the sale.
    cup = ts[CUP]['form_contract']
    cup['allowed_when']['bb_cup_seat_bevel'] = deepcopy(ALWAYS)
    cup['helpers']['bb_cup_seat_bevel'] = (
        'Geometría del asiento físico de esta cubeta, con o sin rodamiento '
        'incluido. Es distinta del bisel del propio rodamiento y de su rodadura.')
    for key, label, bevel in (
        ('bb_cup_inner_seat_angle_deg', 'Ángulo interior del asiento de la cubeta', 'Sólo bisel interior'),
        ('bb_cup_outer_seat_angle_deg', 'Ángulo exterior del asiento de la cubeta', 'Sólo bisel exterior')):
        add_definition(d, ts, key, label, 'number', (CUP,), unit='°', rules={'positive': True, 'max': '90'})
        gate = condition('bb_cup_seat_bevel', ['Biseles interior y exterior', bevel])
        cup['allowed_when'][key] = deepcopy(gate)
        cup['required_when'][key] = deepcopy(gate)

    # One occurrence of one physical port cannot gain an alternative diameter
    # merely by pointing at another paragraph of a source.
    port_schema = d['bb_shell_ports']['validation_rules']['rows_schema']
    port = next(c for c in port_schema['columns'] if c['key'] == 'port')
    port.update(type='text', label='Identificador del puerto físico')
    port.pop('allowed_values', None)
    port_schema['columns'].insert(1, column('side', 'Lado de la pieza', 'token',
        required=True, options=['Lado motriz', 'Lado no motriz', 'Puerto único']))
    next(c for c in port_schema['columns'] if c['key'] == 'diameter')['label'] = 'Diámetro nominal del puerto'
    port_schema['unique_by'] = [['port']]

    # An OEM may declare a standard/dimension instead of enumerating all models.
    # Both kinds preserve their scope; neither derives approval from a brand.
    accepted = d['bb_accepted_spindles']['validation_rules']['rows_schema']
    for c in accepted['columns']:
        if c['key'] in ('interface', 'oem_brand', 'oem_model', 'oem_edition'):
            c.pop('required', None)
    accepted['columns'].insert(0, column('target_kind', 'Tipo de destinatario', 'token',
        required=True, options=['Modelo y edición', 'Estándar declarado']))
    accepted['columns'].insert(1, column('standard', 'Estándar o dimensión literal declarada'))
    accepted['columns'].insert(2, column('configuration', 'Configuración a la que se aplica', required=True))
    accepted['unique_by'] = [['standard', 'configuration'],
                              ['interface', 'oem_brand', 'oem_model', 'oem_edition', 'configuration']]
    for family in (BB, CUP):
        rc = ts[family]['form_contract']['row_conditions']['fields']['bb_accepted_spindles']
        for key in ('interface', 'oem_brand', 'oem_model', 'oem_edition'):
            rc['allowed_when'][key] = condition('target_kind', 'Modelo y edición')
            rc['required_when'][key] = condition('target_kind', 'Modelo y edición')
        rc['allowed_when']['standard'] = condition('target_kind', 'Estándar declarado')
        rc['required_when']['standard'] = condition('target_kind', 'Estándar declarado')

    # A BB is an assembly; the left and right bearings need not share a code,
    # construction or dimension. Counts refer to that supplied member only.
    bb = ts[BB]['form_contract']
    retire(ts[BB], ['bearing_size_code', 'bb_ball_size_in', 'bb_ball_count_per_side',
                    'bb_bearing_arrangement', 'bb_shell_width_mm', 'bb_spacer_stack_mm'])
    # New and never-published arrangement is removed instead of carried as legacy.
    if 'bb_bearing_arrangement' not in live_fields[BB]:
        ts[BB]['fields'] = [f for f in ts[BB]['fields'] if f['key'] != 'bb_bearing_arrangement']
        for section in ('roles', 'semantic_roles', 'allowed_when', 'required_when',
                        'helpers', 'prerequisites', 'evidence_requirements', 'allowed_options'):
            bb.get(section, {}).pop('bb_bearing_arrangement', None)
    table(d, ts, MEMBERS, 'Rodamientos incluidos, por miembro', (BB,), [
        column('member', 'Miembro físico', required=True),
        column('position', 'Posición documentada', required=True),
        column('form', 'Forma de suministro', 'token', required=True, options=[CARTRIDGE, LOOSE, CAGED]),
        column('code', 'Código completo del rodamiento'),
        column('bore_mm', 'Diámetro interior', 'decimal', unit='mm', positive=True),
        column('outer_mm', 'Diámetro exterior', 'decimal', unit='mm', positive=True),
        column('width_mm', 'Ancho del rodamiento', 'decimal', unit='mm', positive=True),
        column('ball_size', 'Diámetro literal de bola, con unidad'),
        column('ball_count', 'Bolas de este miembro', 'integer', positive=True),
        *source_columns(),
    ], conditions={
        **{k: condition('form', CARTRIDGE) for k in ('code', 'bore_mm', 'outer_mm', 'width_mm')},
        **{k: condition('form', [LOOSE, CAGED]) for k in ('ball_size', 'ball_count')},
    }, ordered=[['bore_mm', 'outer_mm']],
        helper='Un miembro físico por fila; las dos posiciones pueden tener códigos y medidas distintos.')
    d[MEMBERS]['validation_rules']['rows_schema']['unique_by'] = [['member']]
    rc = bb['row_conditions']['fields'][MEMBERS]
    for key in ('bore_mm', 'outer_mm', 'width_mm', 'ball_count'):
        rc['required_when'][key] = deepcopy(NEVER)

    # Width is a claim about a frame/configuration, not a measured width of
    # this BB. An OEM-declared interval is retained as such, never synthesized.
    for family in (CUP,):
        retire(ts[family], ['bb_shell_width_mm'])
    table(d, ts, MOUNTS, 'Montajes de caja declarados, por configuración', (BB, CUP), [
        column('configuration', 'Configuración documentada', required=True),
        column('shell_designation', 'Designación de la caja de destino', required=True),
        column('width_kind', 'Cómo declara el ancho de caja', 'token',
               required=True, options=['Valor exacto', 'Intervalo publicado', 'Sin cifra publicada']),
        column('width_mm', 'Ancho de caja exacto', 'decimal', unit='mm', positive=True),
        column('width_min_mm', 'Ancho mínimo publicado', 'decimal', unit='mm', positive=True),
        column('width_max_mm', 'Ancho máximo publicado', 'decimal', unit='mm', positive=True),
        column('spacer_instructions', 'Espaciadores, lado y condiciones de instalación'),
        column('status', 'Estado declarado', 'token', required=True,
               options=['Compatible declarado', 'Incompatible declarado', 'Condicionado']),
        column('conditions', 'Alcance y condiciones'), *source_columns(),
    ], conditions={
        'width_mm': condition('width_kind', 'Valor exacto'),
        'width_min_mm': condition('width_kind', 'Intervalo publicado'),
        'width_max_mm': condition('width_kind', 'Intervalo publicado'),
        'conditions': deepcopy(ALWAYS),
    }, ordered=[['width_min_mm', 'width_max_mm']],
        helper='Cada fila pertenece a una configuración OEM de este producto. No sumar piezas sueltas para inventar un stack montado.')
    d[MOUNTS]['validation_rules']['rows_schema']['unique_by'] = [['configuration', 'shell_designation']]
    for family in (BB, CUP):
        ts[family]['form_contract']['row_conditions']['fields'][MOUNTS]['required_when']['conditions'] = condition('status', 'Condicionado')

    add_definition(d, ts, 'spindle_diameter_datum', 'Zona y método de medición del diámetro del eje',
                   'text', (BB, AXLE))
    for family in (BB, AXLE):
        c = ts[family]['form_contract']
        c.setdefault('prerequisites', {})['spindle_diameter_mm'] = ['spindle_diameter_datum']
        c['helpers']['spindle_diameter_mm'] = (
            'Diámetro de una zona identificada de este eje. No sustituye sus '
            'extremos ni demuestra el diámetro de todos sus asientos.')
    bb['allowed_when']['spindle_diameter_datum'] = condition('includes_spindle', True, 'boolean')
    ts[BB_BEARING]['form_contract']['helpers']['bearing_inner_diameter_mm'] = (
        'Diámetro interior físico del rodamiento. El eje admitido puede depender '
        'de un casquillo o adaptador: no se igualan automáticamente sus medidas.')


def adjust_cases(fixtures, frozen):
    from compile_existing_bearing_bb_catalog import CONSTRUCTION, ANGULAR_TEXT, ANGULAR, RADIAL
    inherited = {c['id']: c for c in frozen['cases']}
    for c in fixtures['cases']:
        old = inherited.get(c['id'])
        if old and c['template'] == BEARING:
            values = deepcopy(old['values'])
            construction = values.pop('bearing_construction', None)
            if construction is not None:
                values.update(deepcopy(CONSTRUCTION[construction]))
            internal = values.pop('bearing_internal_construction', None)
            if internal is not None:
                values['bearing_race_type'] = ANGULAR if internal in ANGULAR_TEXT else RADIAL
            if 'bearing_seal_kind' in values:
                values['bearing_seal_designation'] = values.pop('bearing_seal_kind')
            values.pop('bearing_dimensional_code', None)
            c['values'] = values
            for expectation in ('expected_blocking', 'expected_sql_blocking', 'expected_issue_subset',
                                'expected_sql_issue_subset', 'forbidden_issue_fields'):
                if expectation in old:
                    c[expectation] = deepcopy(old[expectation])
                else:
                    c.pop(expectation, None)
            for expectation in ('expected_blocking', 'expected_sql_blocking', 'expected_issue_subset', 'expected_sql_issue_subset'):
                for issue in c.get(expectation, []):
                    if issue['field'] == 'bearing_seal_kind':
                        issue['field'] = 'bearing_seal_designation'
            c['successor_translation'] = (
                'Separa suministro/sellado y normaliza la descripción de pistas. '
                'Conserva los biseles del propio rodamiento, su par, pendientes '
                'y límites originales; no los transforma en ángulo de rodadura.')
        for row in c['values'].get('bb_shell_ports', {}).get('rows', []):
            row['values']['side'] = row['values']['port']
        for row in c['values'].get('bb_accepted_spindles', {}).get('rows', []):
            row['values']['target_kind'] = 'Modelo y edición'
            row['values']['configuration'] = 'Configuración sintética'
        if c['id'] == 'bbx_accepted_spindle_needs_its_variant':
            for key in ('expected_issue_subset', 'expected_sql_issue_subset'):
                c[key] = [{'code': 'row_required_missing', 'field': 'bb_accepted_spindles', 'blocking': False}]
            c['successor_translation'] = 'Las claves de modelo siguen pendientes, ahora exigidas condicionalmente por tipo de destinatario.'
        if c['id'] == 'bbx_jis_and_iso_are_two_declarations':
            c['successor_translation'] = ('Dos interfaces explícitas pueden compartir '
                'una configuración y modelo; son declaraciones independientes, '
                'sin inventar dos montajes para sortear la identidad de fila.')
        if c['id'] in ('bbx_radial_cartridge_cannot_declare_a_contact_angle',
                        'bbx_cup_with_its_bearing_declares_no_seat'):
            c['expected_blocking'] = []
            c.pop('expected_sql_blocking', None)
            c['successor_translation'] = 'Se rechaza la premisa: clasificación radial no prohíbe ángulo; incluir rodamiento no elimina el asiento de la cubeta.'
        if 'bb_bearing_arrangement' in c['values']:
            original = deepcopy(c['values'])
            arrangement = c['values'].pop('bb_bearing_arrangement')
            member = {'member': 'Miembro de la fixture', 'position': 'Posición sintética',
                      'form': LOOSE if arrangement == 'Cubetas y bolas' else CARTRIDGE,
                      'source_scope': 'Caso sintético', 'source_url': SYNTHETIC}
            for oldkey, col in [('bearing_size_code', 'code'), ('bb_ball_size_in', 'ball_size'), ('bb_ball_count_per_side', 'ball_count')]:
                if oldkey in c['values']:
                    member[col] = c['values'].pop(oldkey)
            c['values'][MEMBERS] = rows(member)
            c['successor_translation'] = 'La construcción y sus propiedades se conservan en el mismo miembro físico suministrado.'
            c['predecessor_values'] = original
            c['expected_blocking'] = [{'code': 'row_field_applicability', 'field': MEMBERS}] if c.get('expected_blocking') else []
    fixtures['cases'].extend(root_cases())
    sql_multiplicities = {
        'bbx_a_pressed_port_cannot_declare_a_pitch': 2,
        'bbx_an_oem_designation_cannot_carry_a_diameter': 2,
        'bbx_cartridge_bb_cannot_count_balls': 2,
    }
    for c in fixtures['cases']:
        if c['values'].get('bearing_race_type') == 'Radial' and c['id'] != 'bbr_radial_is_not_an_internal_construction_token':
            c.setdefault('predecessor_values', deepcopy(c['values']))
            c['values']['bearing_race_type'] = 'Desconocido / sin confirmar'
            c['successor_translation'] = c.get('successor_translation', '') + (
                ' Radial sólo informa clase de carga: conserva la preimagen y '
                'deja construcción sin confirmar, sin inferir ranura profunda.')
        expected = deepcopy(c.get('expected_sql_blocking', c.get('expected_blocking', [])))
        if c['id'] == 'bbr_radial_is_not_an_internal_construction_token':
            # The existing engines name an unavailable token differently:
            # Dart option; PostgreSQL field_constraint. Same field and failure.
            expected = [{'code': 'field_constraint', 'field': 'bearing_race_type'}]
        if c['id'] in sql_multiplicities:
            if len(expected) != 1:
                raise ValueError('SQL multiplicity adjudication changed')
            expected *= sql_multiplicities[c['id']]
        c['expected_sql_blocking'] = sorted(expected, key=lambda x: (x['code'], x['field']))
    next(c for c in fixtures['cases'] if c['id'] == 'bbr_chamfers_do_not_supply_a_rolling_angle')['forbidden_issue_fields'] = ['bearing_race_contact_angle_deg']


def root_cases():
    cart = {'bearing_supply_form': CARTRIDGE, 'bearing_seal_type': 'Sellado de contacto'}
    source = {'source_scope': 'Caso sintético', 'source_url': SYNTHETIC}
    mount = {'configuration': 'Configuración sintética', 'shell_designation': 'Caja sintética',
             'status': 'Compatible declarado', **source}
    return [
        case('bbr_empty_bearing_supply_stays_pending', BEARING, {},
             pending=[('required_missing', 'bearing_supply_form')]),
        case('bbr_empty_bb_spindle_contents_stays_pending', BB, {},
             pending=[('required_missing', 'includes_spindle')]),
        case('bbr_empty_cup_bearing_contents_stays_pending', CUP, {},
             pending=[('required_missing', 'bearing_included')]),
        case('bbr_chamfers_do_not_supply_a_rolling_angle', BEARING,
             {**cart, GEOMETRY: 'Biseles interior y exterior', INNER: '36', OUTER: '45'}),
        case('bbr_radial_zero_contact_angle_remains_valid', BEARING,
             {**cart, 'bearing_race_type': 'Radial', 'bearing_race_contact_angle_deg': '0'}),
        case('bbr_shell_width_interval_is_one_claim', BB,
             {MOUNTS: rows({**mount, 'width_kind': 'Intervalo publicado', 'width_min_mm': '86', 'width_max_mm': '92'})}),
        case('bbr_exact_width_cannot_also_have_range', BB,
             {MOUNTS: rows({**mount, 'width_kind': 'Valor exacto', 'width_mm': '68', 'width_min_mm': '68'})},
             blocking=[('row_field_applicability', MOUNTS)]),
        case('bbr_reversed_width_interval_blocks', BB,
             {MOUNTS: rows({**mount, 'width_kind': 'Intervalo publicado', 'width_min_mm': '92', 'width_max_mm': '86'})},
             blocking=[('row_shape', MOUNTS)]),
        case('bbr_two_bearings_have_distinct_bores', BB,
             {MEMBERS: rows({'member': 'Motriz', 'position': 'Motriz', 'form': CARTRIDGE, 'code': 'A', 'bore_mm': '24', **source},
                            {'member': 'No motriz', 'position': 'No motriz', 'form': CARTRIDGE, 'code': 'B', 'bore_mm': '22', **source})}),
        case('bbr_cartridge_member_cannot_receive_loose_ball_fields', BB,
             {MEMBERS: rows({'member': 'Uno', 'position': 'Una', 'form': CARTRIDGE, 'code': 'A', 'ball_count': '11', **source})},
             blocking=[('row_field_applicability', MEMBERS)]),
        case('bbr_same_physical_port_cannot_change_with_source', BB,
             {'bb_shell_ports': rows({'port': 'Uno', 'side': 'Lado motriz', 'mates_with': 'Caja del cuadro',
                 'form': 'Designación OEM sin descomponer', 'designation': 'A', **source},
                {'port': 'Uno', 'side': 'Lado motriz', 'mates_with': 'Caja del cuadro',
                 'form': 'Designación OEM sin descomponer', 'designation': 'B',
                 **source, 'source_scope': 'Otro apartado'})},
             blocking=[('row_shape', 'bb_shell_ports')]),
        case('bbr_interval_without_upper_bound_stays_pending', BB,
             {MOUNTS: rows({**mount, 'width_kind': 'Intervalo publicado', 'width_min_mm': '86'})},
             pending=[('row_required_missing', MOUNTS)]),
        case('bbr_cup_with_bearing_preserves_its_own_angles', CUP,
             {'bearing_included': True, 'bb_cup_seat_bevel': 'Biseles interior y exterior',
              'bb_cup_inner_seat_angle_deg': '36', 'bb_cup_outer_seat_angle_deg': '45'}),
        case('bbr_absent_spindle_cannot_have_a_measurement_datum', BB,
             {'includes_spindle': False, 'spindle_diameter_datum': 'Extremo'},
             blocking=[('field_applicability', 'spindle_diameter_datum')]),
        case('bbr_standard_claim_does_not_invent_an_oem_model', BB,
             {'bb_accepted_spindles': rows({'target_kind': 'Estándar declarado', 'standard': 'Diámetro sintético 24 mm',
                 'configuration': 'Configuración sintética', 'status': 'Compatible declarado', **source})}),
        case('bbr_model_claim_without_interface_stays_pending', BB,
             {'bb_accepted_spindles': rows({'target_kind': 'Modelo y edición',
                 'oem_brand': 'Sintético', 'oem_model': 'Uno', 'oem_edition': 'Edición sintética',
                 'configuration': 'Única', 'status': 'Compatible declarado', **source})},
             pending=[('row_required_missing', 'bb_accepted_spindles')]),
        case('bbr_radial_is_not_an_internal_construction_token', BEARING,
             {**cart, 'bearing_race_type': 'Radial'},
             blocking=[('option', 'bearing_race_type')]),
    ]
