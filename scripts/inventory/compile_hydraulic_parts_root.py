"""Source adjudication of the unpublished hydraulic proposal; no DB writes.

The initial proposal is retained as an auditable input in its compiler. This
successor replaces its ambiguous scopes before any metadata is published.
"""
from copy import deepcopy

from compile_mobility_accessories_catalog import case, condition, rows
from compile_wheel_small_parts_catalog import column, retire, table

ALWAYS = {'kind': 'always'}
DECLARED, LITERAL, UNKNOWN = 'Declarado', 'Designación literal', 'No declarado'
STRUCTURED, NO_THREAD = 'Estructurado', 'Sin rosca'
DOT, MINERAL, OTHER = 'Fluido DOT', 'Aceite mineral', 'Otra formulación'
SILICONE, NONSILICONE, PETROLEUM = ('Base silicona', 'Base no silicona',
                                  'Base mineral / petróleo')
COMPATIBLE, INCOMPATIBLE, CONDITIONAL = ('Compatible declarado',
                                       'Incompatible declarado', 'Condicionado')
PARK = 'https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-mineral-bkm-1-2'
SRAM = 'https://support.sram.com/hc/en-us/articles/5927424375451-Can-I-use-DOT-5-in-my-SRAM-DOT-brakes'
DOT_SOURCE = 'https://www.ecfr.gov/current/title-49/subtitle-B/chapter-V/part-571/subpart-B/section-571.116'
ISO = 'https://www.iso.org/standard/16724.html'
SHIMANO = 'https://si.shimano.com/en/pdfs/dm/MBBR001/DM-MBBR001-04-ENG.pdf'
JAGWIRE = 'https://jagwire.com/files/general/2021_Jagwire_AM_Catalog_LowRes.pdf'
MOTUL = 'https://azupim01.motul.com/media/motulData/DO/base/DOT_5.1_en_FR_motul_27400_20220113.pdf'


def both(a, b):
    result = deepcopy(a)
    result['rows'][0].extend(deepcopy(b)['rows'][0])
    return result


def threads():
    # A numeric diameter cannot hide a second pitch as the old text cell did.
    return [
        column('thread_form', 'Forma de la rosca', 'token', required=True,
               options=[STRUCTURED, LITERAL, NO_THREAD, UNKNOWN]),
        column('diameter_value', 'Diámetro nominal de la rosca', 'decimal', positive=True),
        column('diameter_unit', 'Unidad del diámetro', 'token', options=['mm', 'in']),
        column('pitch_value', 'Paso o hilos por pulgada', 'decimal', positive=True),
        column('pitch_unit', 'Unidad del paso', 'token', options=['mm', 'tpi']),
        column('thread_designation', 'Designación completa publicada'),
    ]


def thread_conditions():
    return {**{k: condition('thread_form', STRUCTURED) for k in
               ('diameter_value', 'diameter_unit', 'pitch_value', 'pitch_unit')},
            'thread_designation': condition('thread_form', LITERAL)}


def replace_table(definitions, templates, key, label, family, columns,
                  *, conditions=None, required=True, ordered=(), unique=(), helper=''):
    # Keep the unpublished UUID and use; table() must not add that use twice.
    template = templates[family]
    existing = next((f for f in template['fields'] if f['key'] == key), None)
    if existing:
        template['fields'].remove(existing)
        template['form_contract'].get('row_conditions', {}).get('fields', {}).pop(key, None)
    table(definitions, templates, key, label, (family,), columns,
          conditions=conditions, required=required, ordered=ordered, helper=helper)
    if unique:
        definitions[key]['validation_rules']['rows_schema']['unique_by'] = list(unique)


def link(template, id_, source, column_, target, label):
    template['form_contract'].setdefault('row_coherence',
        {'version': 1, 'links': []})['links'].append({
            'id': id_, 'field': source, 'column': column_,
            'target_field': target, 'label_columns': [label]})


def review_hydraulics(definitions, templates, fixtures):
    # The captured live scalar has only these three options. Its use is legacy
    # here; new DOT grades belong to this template's formulation row, never a
    # silent extension of a shared field used by installed brake fichas.
    definitions['fluid_type']['allowed_values'] = ['Aceite Mineral', 'DOT 4', 'DOT 5.1']
    hose, fitting, fluid = (templates[k] for k in
                            ('hydraulic_hose', 'hydraulic_fitting', 'brake_fluid'))
    members, ends, pieces, declarations = ('hydraulic_hose_members',
        'hydraulic_hose_end_configurations', 'hydraulic_fitting_components',
        'brake_fluid_declarations')

    replace_table(definitions, templates, members, 'Tramos suministrados',
        'hydraulic_hose', [
            column('member', 'Tramo físico incluido', required=True),
            column('quantity', 'Cantidad de tramos iguales', 'integer', positive=True),
            column('hose_brand', 'Fabricante de la manguera'),
            column('hose_model', 'Modelo o código de manguera', required=True),
            column('edition', 'Edición o versión'),
            column('length_form', 'Cómo se publica el largo', 'token', required=True,
                   options=[DECLARED, LITERAL, UNKNOWN]),
            column('length_mm', 'Largo suministrado', 'decimal', unit='mm', positive=True),
            column('length_literal', 'Largo publicado sin descomponer'),
            column('length_datum', 'Puntos entre los que se mide'),
            column('cut_to_install', 'Requiere corte para instalar', 'boolean'),
            column('outer_diameter_mm', 'Diámetro exterior', 'decimal', unit='mm', positive=True),
            column('inner_diameter_mm', 'Diámetro interior', 'decimal', unit='mm', positive=True),
            column('construction', 'Construcción publicada'),
            column('conditions', 'Condiciones del fabricante'),
            column('source_url', 'Fuente', 'url'),
        ], conditions={'length_mm': condition('length_form', DECLARED),
                       'length_literal': condition('length_form', LITERAL)},
        ordered=[['inner_diameter_mm', 'outer_diameter_mm']],
        unique=[['member']],
        helper='Identifica primero el tramo físico. Su largo suministrado y la '
        'necesidad de cortarlo son datos independientes. No se transforma un '
        'rollo en dos mangueras ya instaladas. La marca no resuelve el sistema.')
    retire(hose, ['hose_system_code', 'brake_hydraulic_connections', 'kit_members',
                  'fittings_included'])

    # Jagwire 2021 supplies two caliper couplers on a hose to be cut. Therefore
    # lever/caliper is a target role, NOT the identity of a physical end.
    end_conditions = thread_conditions()
    end_conditions.update({k: condition('termination_kind', 'Oliva + inserto')
                           for k in ('olive_model', 'insert_model')})
    replace_table(definitions, templates, ends, 'Extremos y adaptaciones del tramo',
        'hydraulic_hose', [
            column('member_row_id', 'Tramo de origen', required=True),
            column('physical_end', 'Extremo físico A, B o ramal', required=True),
            column('configuration', 'Configuración o etapa documentada', required=True),
            column('end_role', 'Componente al que se conecta', 'token', required=True,
                   options=['Maneta', 'Cáliper', 'Unión intermedia', 'Otro']),
            column('supply', 'Presentación de la terminación', 'token', required=True,
                   options=['Preinstalado en el producto', 'Incluido sin instalar',
                            'Se vende por separado', UNKNOWN]),
            column('termination_kind', 'Terminación', 'token', required=True,
                   options=['Oliva + inserto', 'Banjo', 'Conector rápido',
                            'Roscado directo', 'Extremo sin terminal', 'Otra']),
            column('termination_model', 'Modelo o código del terminal'),
            column('olive_model', 'Oliva especificada'),
            column('insert_model', 'Inserto especificado'),
            *threads(),
            column('target_brand', 'Fabricante del componente objetivo'),
            column('target_model', 'Modelo del componente objetivo'),
            column('target_edition', 'Edición del componente objetivo'),
            column('adapter_model', 'Adaptador necesario para esta configuración'),
            column('conditions', 'Condiciones, instalación y alcance'),
            column('source_url', 'Fuente', 'url'),
        ], conditions=end_conditions,
        unique=[['member_row_id', 'physical_end', 'configuration']],
        helper='A y B identifican extremos físicos; ambos pueden venir con '
        'acoples para cáliper. La etapa de suministro y cada montaje alternativo '
        'se describen por separado. Un acople preinstalado no acredita que el '
        'adaptador requerido esté incluido ni que sirva para cualquier freno.')
    hose['form_contract']['row_coherence'] = {'version': 1, 'links': []}
    link(hose, 'hose_end_member', ends, 'member_row_id', members, 'member')

    piece_conditions = thread_conditions()
    piece_conditions['insert_length_mm'] = condition('piece_kind', ['Inserto / espiga', 'Oliva + inserto'])
    replace_table(definitions, templates, pieces, 'Piezas incluidas del conector',
        'hydraulic_fitting', [
            column('component', 'Pieza física incluida', required=True),
            column('piece_kind', 'Tipo de esta pieza', 'token', required=True,
                   options=['Oliva', 'Inserto / espiga', 'Oliva + inserto',
                            'Perno banjo', 'Arandela', 'Conector rápido', 'Otra']),
            column('quantity', 'Cantidad de piezas iguales', 'integer', positive=True),
            column('oem_code', 'Código del fabricante de esta pieza', required=True),
            *threads(),
            column('insert_length_mm', 'Largo del inserto', 'decimal', unit='mm', positive=True),
            column('conditions', 'Presentación, material y condiciones'),
            column('source_url', 'Fuente', 'url'),
        ], conditions=piece_conditions, unique=[['component']],
        helper='El tipo, código y dimensiones pertenecen a esta pieza, no a '
        'todo el juego. El largo del inserto no acredita un modelo de manguera.')
    retire(fitting, ['fitting_kind', 'hose_system_code', 'hose_outer_diameter_mm',
                     'brake_fitting_oem_code', 'brake_hydraulic_connections',
                     'compatible_brake_models', 'kit_members'])
    fitments = 'hydraulic_fitting_applications'
    replace_table(definitions, templates, fitments, 'Aplicaciones documentadas de cada pieza',
        'hydraulic_fitting', [
            column('component_row_id', 'Pieza incluida', required=True),
            column('configuration', 'Configuración documentada', required=True),
            column('hose_brand', 'Fabricante de la manguera'),
            column('hose_model', 'Modelo de manguera objetivo', required=True),
            column('hose_edition', 'Edición o alcance OEM de manguera', required=True),
            column('hose_outer_diameter_mm', 'Exterior nominal de la manguera objetivo',
                   'decimal', unit='mm', positive=True),
            column('target_role', 'Destino de la conexión', 'token', required=True,
                   options=['Maneta', 'Cáliper', 'Unión intermedia', 'Manguera', 'Otro']),
            column('target_model', 'Modelo de destino', required=True),
            column('target_edition', 'Edición o alcance OEM de destino', required=True),
            column('status', 'Declaración del fabricante', 'token', required=True,
                   options=[COMPATIBLE, INCOMPATIBLE, CONDITIONAL]),
            column('conditions', 'Adaptadores, instalación y restricciones'),
            column('source_scope', 'Apartado o alcance de la fuente', required=True),
            column('source_url', 'Fuente', 'url', required=True),
        ], required=False,
        unique=[['component_row_id', 'configuration', 'hose_model',
                 'hose_edition', 'target_role', 'target_model', 'target_edition', 'source_scope']],
        helper='Una declaración por pieza y configuración de destino. Conservar '
        'el modelo y su generación; el mismo diámetro exterior no resuelve '
        'inserto, oliva, conexión ni aprobación del fabricante.')
    fitting['form_contract']['row_coherence'] = {'version': 1, 'links': []}
    link(fitting, 'fitting_application_piece', fitments, 'component_row_id', pieces, 'component')

    # The physical member owns its formulation exactly once. Further standards
    # and brake claims refer to this row; they never introduce another formula.
    replace_table(definitions, templates, declarations, 'Líquidos incluidos y su identidad',
        'brake_fluid', [
            column('container', 'Envase o miembro físico incluido', required=True),
            column('quantity', 'Cantidad de envases iguales', 'integer', positive=True),
            column('oem_brand', 'Fabricante del líquido', required=True),
            column('oem_designation', 'Nombre o código exacto del líquido', required=True),
            column('edition', 'Edición o formulación publicada'),
            column('volume_ml', 'Volumen de cada envase', 'decimal', unit='ml', positive=True),
            column('fluid_class', 'Clase del líquido', 'token', required=True,
                   options=[DOT, MINERAL, OTHER]),
            column('chemical_base', 'Base declarada', 'token', required=True,
                   options=[SILICONE, NONSILICONE, PETROLEUM, 'Otra base']),
            column('dot_grade', 'Designación DOT comercial publicada', 'token',
                   options=['DOT 3', 'DOT 4', 'DOT 3 / DOT 4', 'DOT 5', 'DOT 5.1']),
            *[column(key, label, 'boolean') for key, label in (
                ('conforms_dot3', 'Cumplimiento DOT 3 declarado'),
                ('conforms_dot4', 'Cumplimiento DOT 4 declarado'),
                ('conforms_dot5', 'Cumplimiento DOT 5 base silicona declarado'),
                ('conforms_dot51', 'Cumplimiento DOT 5.1 declarado'))],
            column('conditions', 'Alcance y advertencias del fabricante'),
            column('source_url', 'Fuente de identidad', 'url', required=True),
        ], conditions={'dot_grade': condition('fluid_class', DOT)},
        unique=[['container']],
        helper='Cada miembro físico tiene una sola formulación. Dos líquidos '
        'separados requieren envases distintos; no se mezclan en un circuito. '
        'DOT 5 y DOT 5.1 se conservan separados. La marca no determina la base '
        'ni autoriza todos los frenos de esa marca.')
    rc = fluid['form_contract']['row_conditions']['fields'][declarations]
    rc['value_when'] = {'chemical_base': [
        {'when': condition('fluid_class', MINERAL),
         'expected': {'value_type': 'token', 'value': PETROLEUM}},
        {'when': both(condition('fluid_class', DOT), condition('dot_grade', 'DOT 5')),
         'expected': {'value_type': 'token', 'value': SILICONE}},
        {'when': both(condition('fluid_class', DOT), condition('dot_grade', ['DOT 3', 'DOT 4', 'DOT 3 / DOT 4', 'DOT 5.1'])),
         'expected': {'value_type': 'token', 'value': NONSILICONE}},
    ]}
    for key in ('conforms_dot3', 'conforms_dot4', 'conforms_dot5', 'conforms_dot51'):
        rc['allowed_when'][key] = condition('fluid_class', DOT)
        # Marketing grade and conformance are different declarations. Motul
        # explicitly states DOT3/4/5.1 for one formulation. Only the conflicting
        # chemical-base class is excluded, not that legitimate multiple claim.
        incompatible_base = [NONSILICONE, PETROLEUM] if key == 'conforms_dot5' else [SILICONE, PETROLEUM]
        rc['value_when'][key] = [{'when': condition('chemical_base', incompatible_base),
                                 'expected': {'value_type': 'boolean', 'value': False}}]
    fluid['form_contract']['helpers'][declarations] += (
        ' La designación comercial y el cumplimiento de normas son diferentes: '
        'un líquido puede declarar DOT 3, 4 y 5.1 a la vez. Registrar sólo lo '
        'publicado; ningún cumplimiento se completa automáticamente desde el nombre.')
    retire(fluid, ['volume_ml', 'oem_brand_specific', 'compatible_brake_models'])
    standards = 'brake_fluid_standard_claims'
    replace_table(definitions, templates, standards, 'Otras normas publicadas del líquido',
        'brake_fluid', [
            column('container_row_id', 'Líquido al que pertenece', required=True),
            column('standard', 'Norma o especificación publicada', 'token', required=True,
                   options=['ISO 4925', 'ISO 7308', 'SAE J1703', 'SAE J1704', 'SAE J1705',
                            'Especificación OEM', 'Otra referencia documental']),
            column('designation', 'Referencia documental sin clasificar'),
            column('edition', 'Edición de la norma'),
            column('claim_scope', 'Cumplimiento, ensayo o especificación OEM', required=True),
            column('conditions', 'Alcance de la declaración'),
            column('source_url', 'Fuente', 'url', required=True),
        ], required=False, conditions={'designation': condition('standard',
                  ['Especificación OEM', 'Otra referencia documental'])},
        helper='Una norma de ensayo no equivale a homologación de un freno. '
        'No todas las normas son DOT: conservar literalmente las otras '
        'especificaciones, su edición y su alcance, también para aceite mineral. '
        'Los cumplimientos DOT tienen celdas tipadas en la formulación. Una '
        'referencia sin clasificar no se interpreta como grado ni homologación.')
    claims = 'brake_fluid_model_claims'
    replace_table(definitions, templates, claims, 'Modelos de freno declarados para el líquido',
        'brake_fluid', [
            column('container_row_id', 'Líquido incluido', required=True),
            column('target_brand', 'Fabricante del freno', required=True),
            column('target_model', 'Modelo o familia técnica declarada', required=True),
            column('target_edition', 'Generación, edición o alcance OEM', required=True),
            column('configuration', 'Circuito o configuración', required=True),
            column('source_scope', 'Apartado exacto de la fuente', required=True),
            column('status', 'Declaración publicada', 'token', required=True,
                   options=[COMPATIBLE, INCOMPATIBLE, CONDITIONAL]),
            column('conditions', 'Fluido prescrito y demás condiciones'),
            column('source_url', 'Fuente', 'url', required=True),
        ], required=False,
        unique=[['container_row_id', 'target_brand', 'target_model',
                 'target_edition', 'configuration', 'source_scope']],
        helper='El alcance pertenece a este líquido y este freno. No se '
        'interpreta una lista de adaptadores de purga como aprobación del '
        'líquido: Park no incluye líquido en BKM-1.2 ni en BKD-1.2. Una '
        'declaración del fabricante todavía requiere adjudicación de identidad.')
    fluid['form_contract']['row_coherence'] = {'version': 1, 'links': []}
    for source in (standards, claims):
        link(fluid, source + '_member', source, 'container_row_id', declarations, 'oem_designation')
    for template, field in ((fitting, fitments), (fluid, claims)):
        template['form_contract'].setdefault('row_conditions', {'version': 1, 'fields': {}})['fields'][field] = {
            'required_when': {'conditions': condition('status', CONDITIONAL)}}

    fixtures['cases'] = [c for c in fixtures['cases'] if c['id'] == 'brake_dot5_is_distinct_stock_description']
    fixtures['cases'].extend(root_cases(members, ends, pieces, fitments, declarations, standards, claims))
    for template in templates.values():
        # Physical identity before dimensions, then applications. Legacy last.
        active = [f for f in template['fields'] if template['form_contract']['roles'][f['key']] != 'legacy']
        legacy = [f for f in template['fields'] if template['form_contract']['roles'][f['key']] == 'legacy']
        sequence = {'hydraulic_hose': [members, ends],
                    'hydraulic_fitting': [pieces, fitments],
                    'brake_fluid': [declarations, standards, claims]}[template['key']]
        active.sort(key=lambda f: sequence.index(f['key']) if f['key'] in sequence else len(sequence))
        identity_key = sequence[0]
        template['form_contract']['roles'][identity_key] = 'primary'
        template['form_contract']['semantic_roles'][identity_key] = 'intrinsic'
        next(f for f in active if f['key'] == identity_key)['section_key'] = 'primary'
        for n, field in enumerate(active + legacy, 1):
            field['sort_order'] = n * 10


def root_cases(m, e, p, a, d, s, c):
    result = []
    def add(id_, family, values, **kwargs):
        # An unknown cell is absent. JSON null is a malformed typed cell and
        # deliberately remains a blocking error in the production row parser.
        for value in values.values():
            if isinstance(value, dict) and value.get('schema_version') == 1:
                for row in value['rows']:
                    row['values'] = {k: v for k, v in row['values'].items() if v is not None}
        result.append(case('hy_root_' + id_, family, values, **kwargs))
    member = {'member': 'Tramo 1', 'hose_model': 'Manguera sintética',
              'quantity': '1', 'length_form': DECLARED, 'length_mm': '2000',
              'cut_to_install': True}
    hose = {m: rows(member)}
    end = {'member_row_id': 'r1', 'physical_end': 'A',
           'configuration': 'Suministro original', 'end_role': 'Cáliper',
           'supply': 'Preinstalado en el producto', 'termination_kind': 'Conector rápido',
           'thread_form': UNKNOWN}
    piece = {'component': 'Inserto 1', 'piece_kind': 'Inserto / espiga',
             'quantity': '1', 'oem_code': 'Sintético', 'thread_form': NO_THREAD}
    bottle = {'container': 'Envase A', 'quantity': '1', 'oem_brand': 'Fabricante sintético',
              'oem_designation': 'DOT 5.1 sintético', 'volume_ml': '100',
              'fluid_class': DOT, 'chemical_base': NONSILICONE, 'dot_grade': 'DOT 5.1',
              'source_url': DOT_SOURCE}
    add('known_supply_length_can_require_cut', 'hydraulic_hose', hose)
    add('unknown_length_is_pending', 'hydraulic_hose', {m: rows({**member, 'length_mm': None})},
        pending=[('row_required_missing', m)])
    add('undeclared_length_cannot_keep_number', 'hydraulic_hose',
        {m: rows({**member, 'length_form': UNKNOWN})}, blocking=[('row_field_applicability', m)])
    add('literal_length_cannot_keep_number', 'hydraulic_hose',
        {m: rows({**member, 'length_form': LITERAL, 'length_literal': 'Longitud OEM'})},
        blocking=[('row_field_applicability', m)])
    add('interior_cannot_exceed_exterior', 'hydraulic_hose',
        {m: rows({**member, 'inner_diameter_mm': '6', 'outer_diameter_mm': '5'})},
        blocking=[('row_shape', m)])
    add('zero_quantity_is_not_unknown', 'hydraulic_hose',
        {m: rows({**member, 'quantity': '0'})}, blocking=[('row_shape', m)])
    add('different_hose_lengths_stay_scoped', 'hydraulic_hose',
        {m: rows(member, {**member, 'member': 'Tramo 2', 'length_mm': '900'})})
    add('same_physical_member_cannot_have_two_lengths', 'hydraulic_hose',
        {m: rows(member, {**member, 'length_mm': '900'})}, blocking=[('row_shape', m)])
    add('two_factory_caliper_couplers_are_distinct_ends', 'hydraulic_hose',
        {m: rows({**member, 'hose_model': 'Pro Hydraulic Hose', 'length_mm': None,
                   'length_form': UNKNOWN, 'source_url': JAGWIRE}),
         e: rows({**end, 'source_url': JAGWIRE}, {**end, 'physical_end': 'B', 'source_url': JAGWIRE})},
        sources=[JAGWIRE])
    add('one_physical_end_one_supply_configuration', 'hydraulic_hose',
        {**hose, e: rows(end, {**end, 'supply': 'Se vende por separado'})},
        blocking=[('row_shape', e)])
    add('separate_installation_configuration_is_not_a_duplicate', 'hydraulic_hose',
        {**hose, e: rows(end, {**end, 'configuration': 'Montaje con adaptador',
                             'adapter_model': 'Adaptador sintético'})})
    add('end_requires_real_member_link', 'hydraulic_hose',
        {**hose, e: rows({**end, 'member_row_id': 'missing'})},
        blocking=[('row_reference_unresolved', e)])
    thread = {'thread_form': STRUCTURED, 'diameter_value': '9', 'diameter_unit': 'mm',
              'pitch_value': '26', 'pitch_unit': 'tpi'}
    add('diameter_and_pitch_units_are_independent', 'hydraulic_hose',
        {**hose, e: rows({**end, **thread})})
    add('diameter_is_not_a_second_free_text_thread', 'hydraulic_hose',
        {**hose, e: rows({**end, **thread, 'diameter_value': 'M8x1.25'})},
        blocking=[('row_shape', e)])
    add('literal_thread_cannot_carry_a_numeric_pitch', 'hydraulic_hose',
        {**hose, e: rows({**end, 'thread_form': LITERAL, 'thread_designation': 'M8x0.75',
                         'pitch_value': '26'})}, blocking=[('row_field_applicability', e)])
    add('olive_and_insert_keep_own_geometry', 'hydraulic_fitting',
        {p: rows(piece, {**piece, 'component': 'Oliva 1', 'piece_kind': 'Oliva'})})
    add('olive_is_not_an_insert', 'hydraulic_fitting',
        {p: rows({**piece, 'piece_kind': 'Oliva', 'insert_length_mm': '11.2'})},
        blocking=[('row_field_applicability', p)])
    application = {'component_row_id': 'r1', 'configuration': 'Montaje sintético',
                   'hose_model': 'H1', 'hose_edition': 'Edición 1',
                   'target_role': 'Manguera', 'target_model': 'H1', 'target_edition': 'Edición 1',
                   'status': COMPATIBLE, 'source_scope': 'Caso sintético'}
    add('fitting_applications_link_the_piece', 'hydraulic_fitting',
        {p: rows(piece), a: rows(application)})
    add('fitting_cannot_reference_missing_piece', 'hydraulic_fitting',
        {p: rows(piece), a: rows({**application, 'component_row_id': 'absent'})},
        blocking=[('row_reference_unresolved', a)])
    add('same_application_cannot_also_deny_fit', 'hydraulic_fitting',
        {p: rows(piece), a: rows(application, {**application, 'status': INCOMPATIBLE})},
        blocking=[('row_shape', a)])
    add('fitting_target_editions_are_not_collapsed', 'hydraulic_fitting',
        {p: rows(piece), a: rows(application, {**application, 'target_edition': 'Edición 2',
                                              'status': INCOMPATIBLE})})
    add('named_dot_fluid_is_recordable', 'brake_fluid', {d: rows(bottle)}, sources=[DOT_SOURCE])
    mineral = {**bottle, 'fluid_class': MINERAL, 'chemical_base': PETROLEUM,
               'dot_grade': None, 'oem_designation': 'Aceite mineral sintético'}
    add('mineral_has_its_own_identity', 'brake_fluid', {d: rows(mineral)})
    add('mineral_cannot_claim_dot4', 'brake_fluid',
        {d: rows({**mineral, 'dot_grade': 'DOT 4'})}, blocking=[('row_field_applicability', d)])
    add('dot5_is_silicone', 'brake_fluid', {d: rows({**bottle, 'dot_grade': 'DOT 5',
                'chemical_base': SILICONE, 'oem_designation': 'DOT 5 sintético'})}, sources=[DOT_SOURCE])
    add('dot5_cannot_be_non_silicone', 'brake_fluid',
        {d: rows({**bottle, 'dot_grade': 'DOT 5'})}, blocking=[('row_value_conflict', d)])
    add('dot51_cannot_be_silicone', 'brake_fluid',
        {d: rows({**bottle, 'chemical_base': SILICONE})}, blocking=[('row_value_conflict', d)])
    add('same_container_cannot_hold_two_formulations', 'brake_fluid',
        {d: rows(bottle, mineral)}, blocking=[('row_shape', d)])
    add('separate_containers_can_hold_different_fluids', 'brake_fluid',
        {d: rows(bottle, {**mineral, 'container': 'Envase B'})})
    add('mineral_standard_not_universally_forbidden', 'brake_fluid',
        {d: rows(mineral), s: rows({'container_row_id': 'r1', 'standard': 'ISO 7308', 'edition': '1987',
             'claim_scope': 'Ejemplo de representación; no homologación de este líquido',
             'source_url': ISO})}, sources=[ISO])
    add('fluid_identity_without_oem_name_remains_pending', 'brake_fluid',
        {d: rows({**bottle, 'oem_designation': None})}, pending=[('row_incomplete', d)])
    claim = {'container_row_id': 'r1', 'target_brand': 'Fabricante sintético',
             'target_model': 'Freno A', 'target_edition': 'Edición 1',
             'configuration': 'Circuito A', 'source_scope': 'Manual A', 'status': COMPATIBLE}
    add('fluid_claim_links_container', 'brake_fluid', {d: rows(bottle), c: rows(claim)})
    add('fluid_claim_cannot_reference_missing_container', 'brake_fluid',
        {d: rows(bottle), c: rows({**claim, 'container_row_id': 'absent'})},
        blocking=[('row_reference_unresolved', c)])
    add('one_exact_fluid_claim_cannot_contradict_itself', 'brake_fluid',
        {d: rows(bottle), c: rows(claim, {**claim, 'status': INCOMPATIBLE})},
        blocking=[('row_shape', c)])
    add('different_brake_editions_keep_separate_claims', 'brake_fluid',
        {d: rows(bottle), c: rows(claim, {**claim, 'target_edition': 'Edición 2',
                                       'status': INCOMPATIBLE})})
    add('standard_cannot_float_without_container', 'brake_fluid',
        {d: rows(bottle), s: rows({'container_row_id': 'absent', 'standard': 'Otra referencia documental',
                                 'designation': 'Norma X',
                                 'claim_scope': 'Ensayo'})},
        blocking=[('row_reference_unresolved', s)])
    motul = {**bottle, 'oem_brand': 'Motul', 'oem_designation': 'MOTUL DOT 5.1',
             'edition': 'TDS 01/22', 'conforms_dot3': True, 'conforms_dot4': True,
             'conforms_dot51': True, 'source_url': MOTUL}
    # No product package/volume was read in this edition of the TDS.
    motul.pop('volume_ml')
    add('one_motul_formula_can_declare_dot3_dot4_dot51', 'brake_fluid',
        {d: rows(motul)}, sources=[MOTUL])
    add('dot51_cannot_also_claim_dot5_silicone_conformance', 'brake_fluid',
        {d: rows({**motul, 'conforms_dot5': True})}, blocking=[('row_value_conflict', d)])
    add('other_standards_cannot_hide_another_dot_grade', 'brake_fluid',
        {d: rows(bottle), s: rows({'container_row_id': 'r1', 'standard': 'DOT 4',
                                 'claim_scope': 'Norma'})}, blocking=[('row_shape', s)])
    add('unclassified_other_standard_remains_documentary', 'brake_fluid',
        {d: rows(bottle), s: rows({'container_row_id': 'r1',
             'standard': 'Otra referencia documental', 'designation': 'Norma OEM X',
             'claim_scope': 'Referencia pendiente de adjudicación'})})
    partial_application = {k: v for k, v in application.items() if k != 'target_edition'}
    add('missing_target_edition_is_visible_as_incomplete', 'hydraulic_fitting',
        {p: rows(piece), a: rows(partial_application)}, pending=[('row_incomplete', a)])
    return result
