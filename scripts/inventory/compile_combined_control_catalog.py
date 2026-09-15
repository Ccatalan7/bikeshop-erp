#!/usr/bin/env python3
"""Compile the brake_shift_combined_control successor. No product or DB writes.

Each lever is a physical object, and a declared configuration is what a source
publishes about one of its two circuits. The unit row carries identity and the
handlebar it clamps to; everything that can contradict something else lives in
the configuration row that owns it, beside the actuation or the shift function
it depends on. A pair is a commercial presentation, not one control with an
averaged answer.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import (
    add_field, case, condition, new_definition, rows)
from compile_wheel_small_parts_catalog import NEVER, column, retire, table
from compile_product_spec_catalog import validate_contract

FAMILY = 'brake_shift_combined_control'

# Sheldon, Derailer Adjustment, paraphrased: the detents that give a shifter its
# indexing are in the shifter, and the adjustment is what makes the derailleur
# land correctly at each of them. So a count of mechanical positions is a
# property of the control, and whether it corresponds one-to-one with sprockets
# depends on the model. Mechanical detents, trim steps and the configuration of
# an electronic control are distinct things; none of them is a sprocket count by
# definition, and none is ruled out from matching one either.
SHELDON_ADJUST = 'https://www.sheldonbrown.com/derailer-adjustment.html'
# Park names the category and nothing more; verified that it states no counts.
PARK_SHIFTERS = 'https://www.parktool.com/en-us/blog/repair-help/shift-levers-shifters'
# Every figure in the harness is invented. Nothing points at a page that does
# not publish it.
SYNTHETIC = 'https://example.invalid/synthetic'

LEFT, RIGHT, SINGLE = 'Izquierdo', 'Derecho', 'Único'
# One canonical decision per configuration. Mode and port were two selectors
# that could contradict each other — «no indexado» plus «inalámbrico» read as a
# friction control that is also electronic, and an electronic port inherited a
# mechanical detent count. Merging them means the contradiction has nowhere to
# be written.
MECH_INDEXED, MECH_FRICTION = 'Mecánico indexado', 'Mecánico de fricción'
ELEC_WIRED, ELEC_WIRELESS = 'Electrónico por cable', 'Electrónico inalámbrico'
NO_SHIFT = 'Sin función de cambio'
SHIFT_MODES = [MECH_INDEXED, MECH_FRICTION, ELEC_WIRED, ELEC_WIRELESS, NO_SHIFT]
SHIFTING = [MECH_INDEXED, MECH_FRICTION, ELEC_WIRED, ELEC_WIRELESS]
ELECTRONIC = [ELEC_WIRED, ELEC_WIRELESS]
FIXED_ACTION, REASSIGNABLE = ('Fijo por construcción',
                              'Asignable por programación')
FRONT_D, REAR_D, TARGET_OTHER = ('Cambio delantero', 'Cambio trasero',
                                 'Otro componente declarado')
HAS_BRAKE, NO_BRAKE = 'Con freno', 'Sin freno'
CABLE, HYDRAULIC, HYBRID = ('Mecánico (cable)', 'Hidráulico',
                            'Híbrido (cable a hidráulico)')
ACT_OTHER, ACT_UNDECLARED = 'Otro', 'No declarado'
WET = [HYDRAULIC, HYBRID]
PULLS = ['Tiro largo (V-brake / disco mecánico tiro largo)',
         'Tiro corto (ruta / cantilever / caliper)', 'Ajustable',
         'Desconocido / sin confirmar']
FLUIDS = ['Aceite Mineral', 'DOT 3', 'DOT 4', 'DOT 5', 'DOT 5.1']
COMPATIBLE, INCOMPATIBLE, CONDITIONED = ('Compatible declarado',
                                         'Incompatible declarado', 'Condicionado')
UNITS = 'combined_control_units'
BRAKE = 'combined_control_brake_configurations'
SHIFT = 'combined_control_shift_configurations'
COUNT = 'combined_control_declared_units'


def both(*conditions):
    """AND single-row conditions into one clause of the same row."""
    merged = deepcopy(conditions[0])
    for extra in conditions[1:]:
        merged['rows'][0].extend(deepcopy(extra)['rows'][0])
    return merged


def per_unit(definitions, templates, key, label, columns, helper,
             conditions=None, required_when=None):
    """A configuration table: every row names its unit and is self-contained.

    `required_when` overrides requiredness for the columns that name it. A cell
    can be admissible in a whole class of rows and demanded only in some of
    them: published scope is welcome on any declaration and obligatory only on
    a conditioned one.
    """
    table(definitions, templates, key, label, (FAMILY,), [
        column('unit_row_id', 'Mando al que pertenece esta configuración',
               required=True),
        column('configuration', 'Configuración declarada', required=True),
        *columns,
        column('source_scope', 'Apartado de la fuente', required=True),
        column('source_url', 'Fuente', 'url', required=True),
    ], conditions=conditions, helper=helper)
    definitions[key]['validation_rules']['rows_schema']['unique_by'] = [
        ['unit_row_id', 'configuration', 'source_scope']]
    for family in (FAMILY,):
        entry = templates[family]['form_contract']['row_conditions']['fields'][key]
        for col, rule in (required_when or {}).items():
            entry['required_when'][col] = deepcopy(rule)


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen input drift')
    base = json.loads(CATALOG.read_text())
    templates = {t['key']: deepcopy(t)
                 for t in base['templates'] if t['key'] == FAMILY}
    definitions = deepcopy(base['definitions'])
    fixtures = json.loads(CASES.read_text())
    fixtures['cases'] = [c for c in fixtures['cases'] if c['template'] == FAMILY]
    control = templates[FAMILY]

    # CC-1. The unit row is identity, and nothing else.
    #
    # An earlier successor of mine kept brake actuation and shift function on
    # the unit, with fluids, hydraulic ends and derailleur claims hanging off it
    # by row id. That was not enough, and it is worth stating why rather than
    # calling it a limitation of the engine: a child row proves that its parent
    # exists, never that the two agree. Measured on that structure, a cable
    # lever accepted a fluid approval, a brake-less lever accepted a hydraulic
    # end, and a lever with no shift function accepted a derailleur claim —
    # three crossings, no issue raised. The engine cannot compare two rows, so
    # the datum has to change hands: whatever depends on an actuation now sits
    # in the same row as that actuation, where an ordinary row condition can see
    # both. No new operator, no new engine.
    table(definitions, templates, UNITS, 'Mandos declarados del conjunto',
          (FAMILY,), [
              column('unit', 'Lado físico del mando', 'token', required=True,
                     options=[LEFT, RIGHT, SINGLE]),
              column('control_model', 'Modelo del mando', required=True),
              column('edition', 'Edición o generación declarada', required=True),
              column('clamp_mm', 'Abrazadera de ESTE mando', 'decimal',
                     unit='mm', positive=True),
              column('source_url', 'Fuente', 'url', required=True),
          ], required=True,
          helper=('Un mando por fila: qué es, de qué lado va y sobre qué '
                  'manillar cierra. Lo que puede contradecirse —accionamiento, '
                  'fluido, tiro, puerto, posiciones— no vive aquí, sino en la '
                  'configuración que lo declara. Que un par se venda junto no '
                  'obliga a que ambos mandos respondan lo mismo, y la '
                  'abrazadera es de cada mando porque cada uno cierra sobre su '
                  'propio manillar.'))
    definitions[UNITS]['validation_rules']['rows_schema']['unique_by'] = [
        ['unit', 'control_model', 'edition']]

    # CC-2. One brake circuit configuration per row, complete.
    #
    # Function and actuation are declared in the row, and the fluid, the pull
    # and the connector are gated on them from the same row. Two approved
    # fluids are two complete configurations, each with its own source and its
    # own system model and edition — not one free configuration collecting
    # every approved combination, and not a child table multiplying against a
    # parent that never asserted it was hydraulic.
    brakes = condition('brake_function', HAS_BRAKE)
    wet = both(condition('brake_actuation', WET), brakes)
    # These two name an external end, so they hang on the declaration that
    # there is one — not merely on the circuit being wet. A configuration that
    # states «no external hose» cannot then describe its connector, and one
    # that has not said either way leaves them pending.
    external = both(condition('external_hose_connection', True, 'boolean'), wet)
    per_unit(definitions, templates, BRAKE,
             'Configuraciones de freno por mando', [
                 column('brake_function', 'Función de freno', 'token',
                        required=True, options=[HAS_BRAKE, NO_BRAKE]),
                 column('brake_actuation', 'Accionamiento de ESTA configuración',
                        'token', options=[CABLE, HYDRAULIC, HYBRID, ACT_OTHER,
                                          ACT_UNDECLARED]),
                 column('lever_cable_pull', 'Tiro de ESTA configuración',
                        'token', options=PULLS),
                 column('external_hose_connection',
                        'Conexión externa de manguera declarada', 'boolean'),
                 column('system_brand', 'Marca del sistema que lo aprueba'),
                 column('system_model', 'Modelo del sistema que lo aprueba'),
                 column('system_edition', 'Edición o generación del sistema'),
                 column('fluid_class', 'Clase de líquido declarada', 'token',
                        options=FLUIDS),
                 column('fluid_product', 'Producto declarado'),
                 column('external_connector_model',
                        'Conector del extremo externo de este mando'),
                 column('external_connection_spec',
                        'Especificación del extremo externo'),
                 column('conditions', 'Condiciones publicadas'),
             ],
             conditions={
                 'brake_actuation': deepcopy(brakes),
                 'lever_cable_pull': both(
                     condition('brake_actuation', [CABLE, HYBRID]), brakes),
                 'external_hose_connection': deepcopy(wet),
                 'system_brand': deepcopy(wet), 'system_model': deepcopy(wet),
                 'system_edition': deepcopy(wet), 'fluid_class': deepcopy(wet),
                 'fluid_product': deepcopy(wet),
                 'external_connector_model': deepcopy(external),
                 'external_connection_spec': deepcopy(external),
             },
             helper=('Una configuración completa por fila. El líquido, el tiro '
                     'y el conector se declaran junto al accionamiento al que '
                     'pertenecen, así que una maneta de cable no puede llevar '
                     'un fluido y una hidráulica no puede llevar un tiro. Dos '
                     'líquidos aprobados son dos filas completas, cada una con '
                     'su sistema y su fuente: compartir clase de fluido no es '
                     'una aprobación, y lo aprobado para un mando no vale para '
                     'el otro por venir en la misma caja. El conector y su '
                     'especificación describen el extremo externo, así que '
                     'sólo se declaran donde se declaró que ese extremo '
                     'existe.'))

    # CC-3. One shift configuration per row, and one canonical mode.
    #
    # Measured on the previous shape, four crossings passed with no issue: a
    # wireless port carried eleven mechanical detents, a wired one did too, a
    # friction control declared itself wireless and reassignable, and a
    # mechanical port declared itself reassignable. The cause was two selectors
    # answering overlapping questions — a shift function that meant indexing,
    # and a port that meant electronics — so the ficha could hold one of each
    # and mean something incoherent. They become a single decision.
    #
    # Mechanical indexing positions belong to the mechanical indexed mode and
    # nowhere else. There is deliberately no count for an electronic control:
    # the presses of a button are not an eleven-position indexation, and giving
    # them a neighbouring integer column is exactly how the two would come to be
    # read as the same thing. Nor is a detent count a sprocket count by
    # definition — how a model's positions correspond to its sprockets is the
    # manufacturer's statement, and trim steps on a front shifter are a third
    # concept again.
    shifting = condition('shift_mode', SHIFTING)
    electronic = condition('shift_mode', ELECTRONIC)
    per_unit(definitions, templates, SHIFT,
             'Configuraciones de cambio por mando', [
                 column('shift_mode', 'Modo de cambio de ESTA configuración',
                        'token', required=True, options=SHIFT_MODES),
                 column('shift_protocol', 'Protocolo electrónico declarado'),
                 column('shift_actuation_family_declared',
                        'Familia de accionamiento declarada por la fuente'),
                 column('mechanical_positions',
                        'Posiciones de indexación mecánica de ESTA configuración',
                        'integer', positive=True),
                 column('action_assignment', 'Asignación de la acción', 'token',
                        options=[FIXED_ACTION, REASSIGNABLE]),
                 column('commanded_target', 'Qué gobierna esta configuración',
                        'token', options=[FRONT_D, REAR_D, TARGET_OTHER]),
                 column('target_brand', 'Marca del destinatario'),
                 column('target_model', 'Modelo del destinatario'),
                 column('target_edition', 'Edición o generación del destinatario'),
                 column('status', 'Estado declarado', 'token',
                        options=[COMPATIBLE, INCOMPATIBLE, CONDITIONED]),
                 column('conditions', 'Alcance o condiciones publicadas'),
             ],
             conditions={
                 'shift_protocol': deepcopy(electronic),
                 'action_assignment': deepcopy(electronic),
                 'shift_actuation_family_declared': deepcopy(shifting),
                 'mechanical_positions': condition('shift_mode', MECH_INDEXED),
                 'commanded_target': deepcopy(shifting),
                 'target_brand': deepcopy(shifting),
                 'target_model': deepcopy(shifting),
                 'target_edition': deepcopy(shifting),
                 'status': deepcopy(shifting),
                 'conditions': deepcopy(shifting),
             },
             # Published scope is admissible on any declaration and demanded
             # only on a conditioned one. Forbidding it on «Compatible» or
             # «Incompatible» would have thrown away the very sentence that
             # bounds the claim.
             required_when={
                 'conditions': both(condition('status', CONDITIONED), shifting),
                 # The source's own wording for the actuation family is
                 # admissible metadata, not a demand. Leaving it coupled made
                 # every shifting row carry a pending, which then masked the
                 # pending that the conditioned verdict is supposed to raise.
                 'shift_actuation_family_declared': deepcopy(NEVER),
             },
             helper=('Una configuración de cambio por fila, con su '
                     'destinatario. El modo es una sola decisión: mecánico '
                     'indexado, mecánico de fricción, electrónico por cable, '
                     'electrónico inalámbrico o sin cambio. Las posiciones de '
                     'indexación son detentes mecánicas y sólo existen en el '
                     'modo indexado; si corresponden al número de coronas lo '
                     'dice el fabricante, no el esquema, y los pasos de trim '
                     'son otra cosa. El protocolo y la posibilidad de '
                     'reasignar la acción sólo existen donde hay control '
                     'electrónico. Un alcance publicado se puede registrar '
                     'junto a cualquier veredicto; en uno condicionado hace '
                     'falta. La ausencia queda pendiente: no se inventa.'))

    # CC-4. «Par» is a commercial presentation. If a source states how many
    # controls the package holds, that count is its own numeric field and the
    # engine compares it with the rows — never a default of two, and its
    # absence is only pending.
    definitions[COUNT] = new_definition(
        COUNT, 'Cantidad de mandos declarada en el envase', 'number', (FAMILY,),
        rules={'integer': True, 'min': 0})
    add_field(control, COUNT, 'contents', 'measurement',
              helper=('Sólo si la fuente lo publica. No se deduce de que la '
                      'presentación se llame par ni se completa con dos.'))
    control['form_contract']['row_coherence'] = {
        'version': 2,
        'links': [
            {'id': 'brake_unit', 'field': BRAKE, 'column': 'unit_row_id',
             'target_field': UNITS, 'label_columns': ['unit', 'control_model']},
            {'id': 'shift_unit', 'field': SHIFT, 'column': 'unit_row_id',
             'target_field': UNITS, 'label_columns': ['unit', 'control_model']},
        ],
        'cardinalities': [
            {'id': 'declared_units', 'field': UNITS, 'total_field': COUNT},
        ],
    }
    # Ten inherited definitions leave the form. Eight are the product-level
    # scalars whose datum now lives per unit or per configuration. The other
    # two are the ones that duplicated what the unit rows already say:
    # shifter_position answered side and quantity commercially, so «Par» plus a
    # single unit row was a contradiction the form invited; handlebar_clamp_mm
    # gave one clamp for two levers that each close on their own bar. Neither
    # definition is edited — every one of them stays byte-identical and keeps
    # its other consumers.
    retire(control, ['shifter_indexed_positions', 'shift_actuation_family',
                     'derailleur_models_compatible', 'brake_actuation',
                     'lever_cable_pull', 'brake_external_hose_connection',
                     'brake_fluid_approvals', 'brake_hydraulic_connections',
                     'shifter_position', 'handlebar_clamp_mm'])
    # A retired structured field is no longer active, so its row conditions
    # would point at nothing; the contract validator rejects that outright.
    conditions = control['form_contract']['row_conditions']['fields']
    for key in [k for k in conditions
                if control['form_contract']['roles'].get(k) == 'legacy']:
        del conditions[key]

    # The inherited negative asserted that a hydraulic control has no cable
    # pull, using two product-level scalars that this successor retires. Its
    # guarantee is unchanged and now lives where the circuit lives, so the
    # scenario moves into the brake configuration and the expectation moves
    # with it: same claim, different owner. It is the one fixture whose expected
    # code and field change, and it changes because the datum changed hands.
    for fixture in fixtures['cases']:
        if fixture['id'] != 'brake_hydraulic_combined_no_cable_pull':
            continue
        fixture['values'] = {
            UNITS: rows({'unit': RIGHT, 'control_model': 'Mando sintético',
                         'edition': 'Edición sintética',
                         'source_url': SYNTHETIC}),
            BRAKE: rows({'unit_row_id': 'r1', 'configuration': 'Sintética',
                         'brake_function': HAS_BRAKE,
                         'brake_actuation': HYDRAULIC,
                         'lever_cable_pull': PULLS[1],
                         'source_scope': 'Apartado sintético',
                         'source_url': SYNTHETIC})}
        fixture['expected_blocking'] = [
            {'code': 'row_field_applicability', 'field': BRAKE}]
        fixture['successor_translation'] = (
            'Los escalares que esta prueba usaba pasan a legacy y el circuito '
            'de freno vive por configuración de cada mando. Se conserva '
            'exactamente lo que afirma —una maneta hidráulica no declara tiro '
            'de cable— y cambia el dueño: la incidencia pasa de '
            'field_applicability sobre lever_cable_pull a '
            'row_field_applicability sobre combined_control_brake_'
            'configurations. La celda shifter_position se retira del escenario '
            'porque el lado ahora lo dice la fila del mando.')

    fixtures['cases'].extend(_cases())

    from compile_combined_control_root import integrate_root
    integrate_root(definitions, templates, fixtures)

    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Combined control reviewed successor',
               'templates': list(templates.values()), 'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(templates),
                        'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in templates.values())}
    return catalog, fixtures


def _cases():
    def unit(**kw):
        return dict({'unit': RIGHT, 'control_model': 'Mando sintético',
                     'edition': 'Edición sintética', 'source_url': SYNTHETIC},
                    **kw)

    def brake(**kw):
        return dict({'unit_row_id': 'r1', 'configuration': 'Sintética',
                     'brake_function': HAS_BRAKE, 'brake_actuation': CABLE,
                     'lever_cable_pull': PULLS[1],
                     'source_scope': 'Apartado sintético',
                     'source_url': SYNTHETIC}, **kw)

    def wet(**kw):
        return dict({'unit_row_id': 'r1', 'configuration': 'Sintética',
                     'brake_function': HAS_BRAKE, 'brake_actuation': HYDRAULIC,
                     'external_hose_connection': True,
                     'system_brand': 'Marca sintética',
                     'system_model': 'Sistema sintético',
                     'system_edition': 'Edición sintética',
                     'fluid_class': 'DOT 5.1',
                     'fluid_product': 'Producto sintético',
                     'source_scope': 'Apartado sintético',
                     'source_url': SYNTHETIC}, **kw)

    def dry(**kw):
        return dict({'unit_row_id': 'r1', 'configuration': 'Sintética',
                     'brake_function': NO_BRAKE,
                     'source_scope': 'Apartado sintético',
                     'source_url': SYNTHETIC}, **kw)

    def shift(**kw):
        # A cell set to None is not an absent cell: the row schema rejects it.
        # Overriding with None here means «this row does not carry it».
        row = dict({'unit_row_id': 'r1', 'configuration': 'Sintética',
                    'shift_mode': MECH_INDEXED, 'mechanical_positions': '11',
                    'commanded_target': REAR_D,
                    'source_scope': 'Apartado sintético',
                    'source_url': SYNTHETIC}, **kw)
        return {k: v for k, v in row.items() if v is not None}

    def electronic(**kw):
        return shift(**dict({'shift_mode': ELEC_WIRELESS,
                             'mechanical_positions': None,
                             'shift_protocol': 'Protocolo sintético'}, **kw))

    def target(**kw):
        return dict({'target_brand': 'Marca sintética',
                     'target_model': 'Modelo sintético',
                     'target_edition': 'Edición sintética'}, **kw)

    def still(**kw):
        return dict({'unit_row_id': 'r1', 'configuration': 'Sintética',
                     'shift_mode': NO_SHIFT,
                     'source_scope': 'Apartado sintético',
                     'source_url': SYNTHETIC}, **kw)

    pair = rows(unit(unit=LEFT), unit(unit=RIGHT))
    return [
        # --- the unit row is identity ----------------------------------------
        case('cbc_pair_is_two_units_with_their_own_clamp', FAMILY,
             {UNITS: rows(unit(unit=LEFT, clamp_mm='22.2'),
                          unit(unit=RIGHT, clamp_mm='31.8'))}),
        case('cbc_same_unit_and_edition_twice_blocks', FAMILY,
             {UNITS: rows(unit(), unit(clamp_mm='22.2'))},
             blocking=[('row_shape', UNITS)]),
        case('cbc_different_edition_is_kept', FAMILY,
             {UNITS: rows(unit(edition='2019'), unit(edition='2021'))}),

        # --- CC-2: the fluid cannot reach a lever that is not hydraulic ------
        # The crossing this successor exists to close. Measured on the previous
        # structure, all three of these passed with no issue at all.
        case('cbc_cable_configuration_cannot_declare_a_fluid', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(brake(fluid_class='DOT 5.1',
                                fluid_product='Producto sintético'))},
             blocking=[('row_field_applicability', BRAKE)]),
        case('cbc_cable_configuration_cannot_declare_a_hose', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(brake(external_hose_connection=True))},
             blocking=[('row_field_applicability', BRAKE)]),
        case('cbc_hydraulic_configuration_cannot_declare_a_pull', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(wet(lever_cable_pull=PULLS[1]))},
             blocking=[('row_field_applicability', BRAKE)]),
        case('cbc_brakeless_configuration_carries_nothing', FAMILY,
             {UNITS: rows(unit()), BRAKE: rows(dry())}),
        case('cbc_brakeless_configuration_cannot_declare_a_fluid', FAMILY,
             {UNITS: rows(unit()), BRAKE: rows(dry(fluid_class='DOT 4'))},
             blocking=[('row_field_applicability', BRAKE)]),
        case('cbc_brakeless_configuration_cannot_declare_a_pull', FAMILY,
             {UNITS: rows(unit()), BRAKE: rows(dry(lever_cable_pull=PULLS[1]))},
             blocking=[('row_field_applicability', BRAKE)]),
        case('cbc_brakeless_configuration_cannot_declare_actuation', FAMILY,
             {UNITS: rows(unit()), BRAKE: rows(dry(brake_actuation=CABLE))},
             blocking=[('row_field_applicability', BRAKE)]),
        # Predecessor synthetic scenario; root adjudicates the component scope
        # before this case or its contract can be emitted.
        case('cbc_hybrid_configuration_keeps_pull_and_fluid', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(wet(brake_actuation=HYBRID,
                              lever_cable_pull=PULLS[0]))}),

        # --- the connector describes an external end that must be declared ---
        # Measured before the change: a configuration that stated «no external
        # hose» still accepted a connector, and so did one that had not said.
        case('cbc_no_external_hose_cannot_carry_a_connector', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(wet(external_hose_connection=False,
                              external_connector_model='Conector sintético'))},
             blocking=[('row_field_applicability', BRAKE)]),
        case('cbc_no_external_hose_cannot_carry_its_spec', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(wet(external_hose_connection=False,
                              external_connection_spec='Especificación'))},
             blocking=[('row_field_applicability', BRAKE)]),
        case('cbc_declared_external_hose_carries_its_connector', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(wet(external_connector_model='Conector sintético',
                              external_connection_spec='Especificación'))}),
        case('cbc_cable_configuration_cannot_carry_a_connector', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(brake(external_connector_model='Conector sintético'))},
             blocking=[('row_field_applicability', BRAKE)]),

        # --- two complete alternatives, never a cross product ----------------
        case('cbc_two_fluids_are_two_complete_configurations', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(wet(configuration='Con DOT 5.1'),
                          wet(configuration='Con DOT 4', fluid_class='DOT 4',
                              system_edition='Otra edición'))}),
        case('cbc_same_configuration_twice_blocks', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(wet(), wet(fluid_class='DOT 4'))},
             blocking=[('row_shape', BRAKE)]),
        case('cbc_same_configuration_from_two_sources_is_kept', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows(wet(), wet(source_scope='Otro apartado'))}),

        # --- each lever owns its own circuit ---------------------------------
        case('cbc_two_levers_may_differ_in_brake_circuit', FAMILY,
             {UNITS: pair,
              BRAKE: rows(wet(unit_row_id='r1'), brake(unit_row_id='r2'))}),
        case('cbc_brake_configuration_cannot_point_at_an_absent_unit', FAMILY,
             {UNITS: rows(unit()), BRAKE: rows(brake(unit_row_id='r9'))},
             blocking=[('row_reference_unresolved', BRAKE)]),
        case('cbc_brake_configuration_without_its_unit_is_incomplete', FAMILY,
             {UNITS: rows(unit()),
              BRAKE: rows({'configuration': 'Sintética',
                           'brake_function': HAS_BRAKE,
                           'brake_actuation': CABLE,
                           'source_scope': 'Apartado sintético',
                           'source_url': SYNTHETIC})},
             pending=[('row_incomplete', BRAKE)]),

        # --- CC-3: the derailleur claim cannot reach a lever that never shifts
        case('cbc_shiftless_configuration_cannot_name_a_target', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(still(**target(status=COMPATIBLE)))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_shiftless_configuration_cannot_declare_a_verdict', FAMILY,
             {UNITS: rows(unit()), SHIFT: rows(still(status=INCOMPATIBLE))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_shiftless_configuration_cannot_publish_a_scope', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(still(conditions='Alcance sintético'))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_shiftless_configuration_cannot_index', FAMILY,
             {UNITS: rows(unit()), SHIFT: rows(still(mechanical_positions='11'))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_shift_configuration_cannot_point_at_an_absent_unit', FAMILY,
             {UNITS: rows(unit()), SHIFT: rows(shift(unit_row_id='r9'))},
             blocking=[('row_reference_unresolved', SHIFT)]),

        # --- the mode is one decision: mechanical detents stay mechanical ----
        # All four of these passed on the previous shape, measured before the
        # change. A wireless configuration inherited eleven mechanical
        # positions; so did a wired one; a friction control declared itself
        # wireless; and a mechanical one declared itself reassignable.
        case('cbc_wireless_mode_cannot_declare_mechanical_positions', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(electronic(mechanical_positions='11'))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_wired_mode_cannot_declare_mechanical_positions', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(electronic(shift_mode=ELEC_WIRED,
                                     mechanical_positions='11'))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_friction_mode_cannot_declare_mechanical_positions', FAMILY,
             {UNITS: rows(unit()), SHIFT: rows(shift(shift_mode=MECH_FRICTION))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_friction_mode_cannot_declare_a_protocol', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(shift_mode=MECH_FRICTION,
                                mechanical_positions=None,
                                shift_protocol='Protocolo sintético'))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_mechanical_mode_cannot_declare_a_protocol', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(shift_protocol='Protocolo sintético'))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_mechanical_mode_cannot_be_reassignable', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(action_assignment=REASSIGNABLE))},
             blocking=[('row_field_applicability', SHIFT)]),
        case('cbc_friction_mode_keeps_its_target_without_a_count', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(shift_mode=MECH_FRICTION,
                                mechanical_positions=None))}),
        # Every other required cell is present, so the only gap is the count:
        # the pending names that datum and not a neighbour's.
        case('cbc_indexed_mode_without_its_count_is_pending', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(**target(status=COMPATIBLE),
                                mechanical_positions=None))},
             pending=[('row_required_missing', SHIFT)]),

        # --- electronic control: protocol and reassignment live only here ----
        # A published example of an electronic control whose delivered action
        # can be reassigned in the manufacturer's app. The schema admits the
        # declaration; it does not extend it to any other model.
        case('cbc_electronic_mode_may_be_reassignable', FAMILY,
             {UNITS: rows(unit(unit=LEFT)),
              SHIFT: rows(electronic(action_assignment=REASSIGNABLE))}),
        case('cbc_electronic_mode_may_be_fixed', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(electronic(action_assignment=FIXED_ACTION))}),
        case('cbc_wired_electronic_mode_is_its_own_mode', FAMILY,
             {UNITS: rows(unit()), SHIFT: rows(electronic(shift_mode=ELEC_WIRED))}),

        # --- side does not imply what the control commands -------------------
        case('cbc_left_may_command_the_rear', FAMILY,
             {UNITS: rows(unit(unit=LEFT)), SHIFT: rows(shift())}),
        # The two circuits of one lever stay independent of each other: an
        # electronic shift sits with a cable brake and with a hydraulic one.
        case('cbc_electronic_shift_with_a_cable_brake', FAMILY,
             {UNITS: rows(unit()), SHIFT: rows(electronic()),
              BRAKE: rows(brake())}),
        case('cbc_electronic_shift_with_a_hydraulic_brake', FAMILY,
             {UNITS: rows(unit()), SHIFT: rows(electronic()),
              BRAKE: rows(wet())}),
        case('cbc_each_unit_keeps_its_own_shift_configuration', FAMILY,
             {UNITS: pair,
              SHIFT: rows(shift(unit_row_id='r1', commanded_target=FRONT_D,
                                mechanical_positions='2'),
                          shift(unit_row_id='r2'))}),

        # --- a verdict may publish its scope; a conditioned one must ---------
        case('cbc_documented_exclusion_is_recordable', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(**target(status=INCOMPATIBLE)))}),
        case('cbc_compatible_verdict_may_publish_its_scope', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(**target(status=COMPATIBLE,
                                         conditions='Alcance sintético')))}),
        case('cbc_incompatible_verdict_may_publish_its_scope', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(**target(status=INCOMPATIBLE,
                                         conditions='Alcance sintético')))}),
        # Same discipline: the conditioned row is complete except for its
        # published scope, so removing that rule really does remove this issue.
        case('cbc_conditioned_verdict_needs_its_conditions', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(**target(status=CONDITIONED)))},
             pending=[('row_required_missing', SHIFT)]),
        case('cbc_conditioned_verdict_with_its_conditions_is_complete', FAMILY,
             {UNITS: rows(unit()),
              SHIFT: rows(shift(**target(status=CONDITIONED,
                                         conditions='Alcance sintético')))}),

        # --- CC-4: the declared count, never a default ------------------------
        case('cbc_declared_count_matches_its_rows', FAMILY,
             {COUNT: '2', UNITS: pair}),
        case('cbc_more_rows_than_declared_blocks', FAMILY,
             {COUNT: '1', UNITS: pair},
             blocking=[('row_cardinality_conflict', UNITS)]),
        case('cbc_fewer_rows_than_declared_is_pending', FAMILY,
             {COUNT: '2', UNITS: rows(unit())},
             pending=[('row_cardinality_pending', UNITS)]),
        case('cbc_a_set_without_a_count_assumes_nothing', FAMILY,
             {UNITS: rows(unit())}),
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'combined-control-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'combined-control-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
