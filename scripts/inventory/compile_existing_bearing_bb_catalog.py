#!/usr/bin/env python3
"""Source-to-candidate successor for five existing families. No DB or migration.

bearing, bottom_bracket, bottom_bracket_axle, bottom_bracket_bearing and
bottom_bracket_cup. Two rules order everything here. The first is the one the
earlier blocks paid for: whatever can contradict something else lives in the
same row as the thing it depends on. The second is new to these families and is
what the audit kept pointing at — one fact, one owner. A construction token that
also announces the seal, a taper standard beside an interface that already names
it, a cup diameter beside a port that measures it: each of those is two cells
that can disagree, and the fix is to keep the one that carries the measurement.

Shared definitions are taken from the LIVE preimage, never from the frozen
proposal: three of them are labelled ``new`` there and are already published.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, ROOT, write_json)
from compile_mobility_accessories_catalog import (
    add_field, case, condition, new_definition, rows)
from compile_wheel_small_parts_catalog import NEVER, column, retire, table
from compile_product_spec_catalog import validate_contract

BEARING = 'bearing'
BB = 'bottom_bracket'
AXLE = 'bottom_bracket_axle'
BB_BEARING = 'bottom_bracket_bearing'
CUP = 'bottom_bracket_cup'
FAMILIES = (BEARING, BB, AXLE, BB_BEARING, CUP)

PREIMAGE = ROOT / '.tmp/db/existing-37-candidate-preimage.json'
PREIMAGE_SHA = '0a21d85a1539c330e661e0c5c1aa2fde0bbf29ddad67a452a018ed767d08b2a6'

# Sheldon, Bottom Bracket Sizes, read directly. Its threading table gives the
# hand per cup, not per product: on English/BSA the adjustable (left) cup is
# right-hand and the fixed (right) cup is left-hand, while on Italian both cups
# are right-hand. A single paired token loses which side is which, so the hand
# belongs to the port.
SHELDON_BB = 'https://www.sheldonbrown.com/bbsize.html'
# Park, Basic Thread Concepts, read directly: the diameter is the major
# diameter at the crests and the pitch is measured crest to crest along the
# thread. Two different measurements, so two cells with their own units.
PARK_THREADS = 'https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts'
SYNTHETIC = 'https://example.invalid/synthetic'

# --- vocabularies owned by this candidate -----------------------------------
CARTRIDGE, LOOSE, RETAINER, FORM_UNKNOWN = (
    'Cartucho', 'Bolas sueltas', 'Canastillo con bolas', 'Desconocido / sin confirmar')
LOOSE_FORMS = [LOOSE, RETAINER]
CONTACT_SEAL, SHIELDED, OPEN_SEAL, SEAL_UNKNOWN = (
    'Sellado de contacto', 'Blindado', 'Abierto', 'Desconocido / sin confirmar')
SEALED_FORMS = [CONTACT_SEAL, SHIELDED]
RADIAL, ANGULAR, RACE_UNKNOWN = ('Radial', 'Contacto angular',
                                 'Desconocido / sin confirmar')
DRIVE, NON_DRIVE, SINGLE_PORT = ('Lado motriz', 'Lado no motriz', 'Puerto único')
TO_SHELL, TO_CUP = 'Caja del cuadro', 'La otra copa'
THREADED, PRESSED, OEM_FORM = ('Rosca medida', 'Asiento a presión',
                               'Designación OEM sin descomponer')
MEASURED_PORTS = [THREADED, PRESSED]
RIGHT_HAND, LEFT_HAND = 'Derecha', 'Izquierda'
CARTRIDGE_BB, CUPS_AND_BALLS, INTEGRATED, ARRANGEMENT_UNKNOWN = (
    'Cartucho sellado', 'Cubetas y bolas', 'Integrado en el eje',
    'Desconocido / sin confirmar')
COMPATIBLE, INCOMPATIBLE, CONDITIONED = ('Compatible declarado',
                                         'Incompatible declarado', 'Condicionado')
SEAT_BEVELS = ['Biseles interior y exterior', 'Sólo bisel interior',
               'Sólo bisel exterior', 'Sin biseles de apoyo', 'Otro',
               'Desconocido / sin confirmar']

# The live vocabulary of spindle_interface, copied into a column of our own.
# The shared definition is not touched; a guard below checks these are the same
# fourteen values, because the frozen proposal carries a fifteenth that was
# never published and adding an option to a live definition is refused.
SPINDLE_INTERFACES = ['Cuadrado JIS', 'Cuadrado ISO', 'Hollowtech / 24mm',
                      'SRAM GXP 24/22', 'SRAM DUB 28.99mm', 'BB30 30mm', 'ISIS',
                      'Octalink', 'Con chaveta', 'BMX 19mm', 'BMX 22mm',
                      'BMX 24mm', 'One-piece / americano', 'Powerspline']

PORTS = 'bb_shell_ports'
ACCEPTED = 'bb_accepted_spindles'
SYSTEMS = 'bb_declared_systems'


def both(*conditions):
    merged = deepcopy(conditions[0])
    for extra in conditions[1:]:
        merged['rows'][0].extend(deepcopy(extra)['rows'][0])
    return merged


def drop(template, keys):
    """Remove a field that was proposed but never published.

    Only legal for a key absent from the live preimage: a published field is
    retired, never dropped, because an observation hangs from it.
    """
    contract = template['form_contract']
    template['fields'] = [f for f in template['fields'] if f['key'] not in keys]
    for section in ('roles', 'semantic_roles', 'labels', 'allowed_when',
                    'required_when', 'allowed_options', 'prerequisites',
                    'helpers', 'evidence_requirements'):
        for key in keys:
            contract.get(section, {}).pop(key, None)
    # A dropped field can still be named by someone else's prerequisite or
    # gate. Prerequisites are cleaned; a leftover gate is raised rather than
    # patched, because it means a rule lost the cell it was reasoning about.
    gone = set(keys)
    for owner, deps in list(contract.get('prerequisites', {}).items()):
        kept = [d for d in deps if d not in gone]
        if kept:
            contract['prerequisites'][owner] = kept
        else:
            contract['prerequisites'].pop(owner)
    # A gate that still reads a dropped cell is caught by the final pass in
    # compile_catalog, once every builder has had its chance to re-gate.


def gate(template, mapping, required=None):
    contract = template['form_contract']
    for key, rule in mapping.items():
        contract['allowed_when'][key] = deepcopy(rule)
        contract['required_when'][key] = deepcopy(
            (required or {}).get(key, rule))


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA),
                      (PREIMAGE, PREIMAGE_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen input drift: ' + path.name)
    base = json.loads(CATALOG.read_text())
    live = json.loads(PREIMAGE.read_text())
    live = live[0]['metadata'] if isinstance(live, list) else live
    published = {d['key']: d for d in live['existing_definitions']}
    live_fields = {t['key']: set() for t in live['templates']}
    by_id = {t['id']: t['key'] for t in live['templates']}
    definition_key = {d['id']: d['key'] for d in live['existing_definitions']}
    for field in live['fields']:
        live_fields[by_id[field['template_id']]].add(
            definition_key[field['spec_definition_id']])

    templates = {t['key']: deepcopy(t)
                 for t in base['templates'] if t['key'] in FAMILIES}
    definitions = deepcopy(base['definitions'])
    fixtures = json.loads(CASES.read_text())
    fixtures['cases'] = [c for c in fixtures['cases']
                         if c['template'] in FAMILIES]

    # A live definition is authoritative over the frozen proposal, whatever the
    # proposal's ``origin`` says. Three of the ones these families use are
    # labelled new there and are already published; ten more carry live option
    # lists or labels the proposal never had. Copying the live row is what makes
    # the candidate publishable at all — the publisher compares seven
    # properties and refuses on any difference.
    changed_from_frozen = set()
    for key, actual in published.items():
        if key not in definitions:
            continue
        before = definitions[key]
        definitions[key] = {
            'key': key, 'id': actual['id'], 'origin': 'existing',
            'label': actual['label'], 'data_type': actual['data_type'],
            'unit': actual['unit'],
            'allowed_values': deepcopy(actual['allowed_values']),
            'validation_rules': deepcopy(actual['validation_rules']),
            'used_by': list(before.get('used_by', []))}
        if any(before.get(c) != definitions[key][c] for c in
               ('id', 'label', 'data_type', 'unit', 'allowed_values',
                'validation_rules', 'origin')):
            changed_from_frozen.add(key)

    if published['spindle_interface']['allowed_values'] != SPINDLE_INTERFACES:
        raise ValueError('The live spindle interface vocabulary moved')

    # The frozen proposal renames four of the five: it says «Pedalier», «Copa»
    # and «Eje de pedalier» where the live catalogue says «Motor», «Cubeta de
    # Motor» and «Eje de Motor». That is the shop's own word for the part and
    # it is not this candidate's to change: a rename is a product decision, not
    # a side effect of reworking a contract. The live name is restored, and the
    # difference is reported instead of published.
    live_templates = {t['key']: t for t in live['templates']}
    renamed = {}
    for key, template in templates.items():
        actual = live_templates[key]
        if template.get('name') != actual['name']:
            renamed[key] = {'frozen_proposal': template.get('name'),
                            'live_preserved': actual['name']}
            template['name'] = actual['name']

    _bearing(definitions, templates, live_fields)
    _bottom_bracket(definitions, templates, live_fields)
    _axle(definitions, templates, live_fields)
    _bb_bearing(definitions, templates, live_fields)
    _cup(definitions, templates, live_fields)

    # Root's OEM adjudication preserves the manufacturer's distinction between
    # bearing chamfers and rolling contact angles, and scopes assembly data.
    from compile_existing_bearing_bb_root import adjust_catalog, adjust_cases
    adjust_catalog(definitions, templates, base, live_fields)

    for template in templates.values():
        conditions = template['form_contract'].get(
            'row_conditions', {}).get('fields', {})
        for key in [k for k in conditions
                    if template['form_contract']['roles'].get(k) == 'legacy']:
            del conditions[key]
        present = {f['key'] for f in template['fields']}
        for key in list(template['form_contract']['roles']):
            if key not in present:
                raise ValueError('Contract mentions a field that is gone: ' + key)
        for section in ('allowed_when', 'required_when'):
            for owner, rule in template['form_contract'].get(section, {}).items():
                for clause in rule.get('rows', []):
                    for term in clause:
                        if term.get('field') not in present:
                            raise ValueError(
                                f"{template['key']}.{section}.{owner} still "
                                f"reads {term['field']}")

    # Nothing published may disappear; that is the whole retirement contract.
    for family in FAMILIES:
        present = {f['key'] for f in templates[family]['fields']}
        missing = live_fields[family] - present
        if missing:
            raise ValueError(f'{family} would lose published fields: {sorted(missing)}')

    fixtures['cases'] = _translate(fixtures['cases']) + _cases()
    adjust_cases(fixtures, json.loads(CASES.read_text()))
    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    # Count what this candidate actually carries, not every live row inspected.
    adopted = sorted(changed_from_frozen & keys)
    shared = sorted(k for k in keys if k in published)
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Bearing and bottom bracket reviewed successor',
               'templates': [templates[f] for f in FAMILIES],
               'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA,
                                'preimage': PREIMAGE_SHA},
               'renames_declined': renamed,
               'live_shared_definitions': shared,
               'adopted_live_definitions': adopted,
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(catalog['templates']),
                        'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in catalog['templates'])}
    return catalog, fixtures


def _bearing(definitions, templates, live_fields):
    """One fact, one owner: supply form, seal, races and balls stop overlapping.

    The frozen proposal's ``bearing_construction`` answered three questions at
    once — how the piece is supplied, whether it is sealed, and (through
    'Cartucho abierto') what its seal state is — while ``bearing_seal_kind``
    answered the seal again in free text. Two owners for the seal is exactly
    what a construction token must not do. It splits into a supply form, a
    typed seal state and the manufacturer's literal seal designation, which are
    three different sentences.

    The pair of contact angles goes the same way. An inner and an outer angle
    read as the bevels of a seat; the rolling geometry of a bearing is one race
    contact angle. The bevel of the seat that RECEIVES a bearing is a property
    of the cup, and that is where it now lives.
    """
    control = templates[BEARING]
    drop(control, ['bearing_construction', 'bearing_seal_kind',
                   'bearing_internal_construction', 'bearing_dimensional_code',
                   'bearing_inner_contact_angle_deg',
                   'bearing_outer_contact_angle_deg', 'bearing_seat_geometry'])
    definitions['bearing_supply_form'] = new_definition(
        'bearing_supply_form', 'Forma en que se suministra', 'single_select',
        (BEARING, BB_BEARING),
        options=[CARTRIDGE, LOOSE, RETAINER, FORM_UNKNOWN])
    definitions['bearing_seal_type'] = new_definition(
        'bearing_seal_type', 'Estado de sellado del cartucho', 'single_select',
        (BEARING,), options=[CONTACT_SEAL, SHIELDED, OPEN_SEAL, SEAL_UNKNOWN])
    definitions['bearing_seal_designation'] = new_definition(
        'bearing_seal_designation', 'Designación literal del sello', 'text',
        (BEARING,))
    definitions['bearing_race_type'] = new_definition(
        'bearing_race_type', 'Geometría de las pistas', 'single_select',
        (BEARING,), options=[RADIAL, ANGULAR, RACE_UNKNOWN])
    for key, section, semantic in (
            ('bearing_supply_form', 'primary', 'primary'),
            ('bearing_seal_type', 'measurement', 'measurement'),
            ('bearing_seal_designation', 'measurement', 'measurement'),
            ('bearing_race_type', 'measurement', 'measurement')):
        add_field(control, key, section, semantic)
        control['form_contract']['roles'][key] = section
        control['form_contract']['semantic_roles'][key] = semantic
    cartridge = condition('bearing_supply_form', CARTRIDGE)
    balls = condition('bearing_supply_form', LOOSE_FORMS)
    gate(control, {
        'bearing_seal_type': deepcopy(cartridge),
        'bearing_seal_designation': both(
            condition('bearing_seal_type', SEALED_FORMS), cartridge),
        'bearing_race_type': deepcopy(cartridge),
        'bearing_race_contact_angle_deg': both(
            condition('bearing_race_type', ANGULAR), cartridge),
        'bearing_row_count': deepcopy(cartridge),
        'bearing_element_retention': deepcopy(cartridge),
        'bearing_size_code': deepcopy(cartridge),
        'bearing_inner_diameter_mm': deepcopy(cartridge),
        'bearing_outer_diameter_mm': deepcopy(cartridge),
        'bearing_width_mm': deepcopy(cartridge),
        'ball_diameter_in': deepcopy(balls),
        'ball_count_per_pack': deepcopy(balls),
        # Whether a bearing can be regreased is a claim about a cartridge; the
        # frozen gate read the construction token that no longer exists, and
        # being sealed still does not decide it.
        'bearing_regreasable': deepcopy(cartridge),
    }, required={
        # A literal designation and a regreasing claim are what a source may or
        # may not print. Demanding them would make every honest ficha pending.
        'bearing_seal_designation': deepcopy(NEVER),
        # A manufacturer that says «angular contact» very often never prints
        # the angle. Demanding it would turn an honest ficha into a permanent
        # pending, and the frozen design only demanded it because the seat
        # bevels triggered it — the very conflation this successor removes.
        'bearing_race_contact_angle_deg': deepcopy(NEVER),
        'bearing_element_retention': deepcopy(NEVER),
        'bearing_width_mm': deepcopy(NEVER),
        'ball_count_per_pack': deepcopy(NEVER),
        'bearing_regreasable': deepcopy(NEVER),
    })
    control['form_contract']['helpers'].update({
        'bearing_supply_form': (
            'Qué se compra: un cartucho, bolas sueltas o un canastillo. No dice '
            'nada del sellado — eso se declara aparte, porque un cartucho '
            'abierto y uno sellado son el mismo modo de suministro.'),
        'bearing_seal_type': (
            'Estado de sellado del cartucho. Es el dueño de este dato; la '
            'designación del fabricante va en su propia celda y no lo '
            'contradice.'),
        'bearing_race_contact_angle_deg': (
            'Ángulo de contacto de las pistas de ESTE rodamiento. No es el '
            'bisel del asiento que lo recibe: ese pertenece a la copa.'),
        'ball_diameter_in': (
            'Sólo para bolas sueltas o canastillo. Un cartucho no publica el '
            'diámetro de sus bolas y no se deduce del código.'),
    })


def _bottom_bracket(definitions, templates, live_fields):
    """Ports own the threads; the accepted spindle stops being a brand list."""
    control = templates[BB]
    drop(control, ['bb_shell_interface', 'bb_thread_hand',
                   'spindle_taper_standard'])
    _ports(definitions, templates, BB)
    _accepted(definitions, templates, BB)
    definitions['bb_bearing_arrangement'] = new_definition(
        'bb_bearing_arrangement', 'Disposición de los rodamientos',
        'single_select', (BB,),
        options=[CARTRIDGE_BB, CUPS_AND_BALLS, INTEGRATED, ARRANGEMENT_UNKNOWN])
    add_field(control, 'bb_bearing_arrangement', 'primary', 'primary')
    control['form_contract']['roles']['bb_bearing_arrangement'] = 'primary'
    control['form_contract']['semantic_roles']['bb_bearing_arrangement'] = 'primary'
    # bb_construction mixed the bearing with the mounting: 'A presión' and
    # 'Roscado entre sí' answer what the port row now measures, so keeping both
    # leaves two cells able to disagree about how the piece mounts. The
    # arrangement keeps only the bearing half.
    # bb_shell_diameter_mm and bb_cup_outer_diameter_mm are the same
    # measurement the port carries, with neither a unit choice nor a side.
    # spindle_interface_accepted is a multi-select of brands with no OEM
    # variant behind any of them.
    retire(control, ['bb_construction', 'bb_shell_diameter_mm',
                     'bb_cup_outer_diameter_mm', 'spindle_interface_accepted'])
    included = condition('includes_spindle', True, 'boolean')
    gate(control, {
        'spindle_interface': deepcopy(included),
        'spindle_length_mm': deepcopy(included),
        'spindle_diameter_mm': deepcopy(included),
        'bb_ball_size_in': condition('bb_bearing_arrangement', CUPS_AND_BALLS),
        'bb_ball_count_per_side': condition('bb_bearing_arrangement', CUPS_AND_BALLS),
        'bearing_size_code': condition('bb_bearing_arrangement', CARTRIDGE_BB),
        # Three gates used to hang from cells this successor removes. The
        # shell width and the spacer stack are single declared figures of the
        # product and stay admissible on their own; whether a spindle comes in
        # the box is a fact about the box, not a consequence of how the piece
        # mounts. None of the three is demanded, because a source that stays
        # silent leaves them pending rather than wrong.
        'bb_shell_width_mm': {'kind': 'always'},
        'bb_spacer_stack_mm': {'kind': 'always'},
        'includes_spindle': {'kind': 'always'},
    }, required={
        'bb_shell_width_mm': deepcopy(NEVER),
        'bb_spacer_stack_mm': deepcopy(NEVER),
        'includes_spindle': deepcopy(NEVER),
    })
    control['form_contract']['helpers'].update({
        'spindle_interface': (
            'La interfaz del eje que ESTE pedalier trae. Si no trae eje, lo '
            'que acepta de una biela se declara en su tabla de ejes '
            'admitidos, que es otra cosa.'),
        'bb_bearing_arrangement': (
            'Cómo van los rodamientos. Cómo se monta el pedalier en la caja lo '
            'dice cada puerto, con su medida y su lado.'),
    })


def _axle(definitions, templates, live_fields):
    """The axle is a physical piece; the system it is declared for is a claim."""
    control = templates[AXLE]
    drop(control, ['spindle_taper_standard'])
    _systems(definitions, templates, AXLE)
    retire(control, ['bb_construction'])
    control['form_contract']['helpers'].update({
        'spindle_interface': (
            'Interfaz de ESTE eje, que es una medida suya. Para qué sistema se '
            'declara es una afirmación del fabricante y va en su tabla.'),
    })


def _bb_bearing(definitions, templates, live_fields):
    """A bore and the spindle it takes are one measurement, not two."""
    control = templates[BB_BEARING]
    drop(control, ['bearing_construction'])
    _systems(definitions, templates, BB_BEARING)
    add_field(control, 'bearing_supply_form', 'primary', 'primary')
    control['form_contract']['roles']['bearing_supply_form'] = 'primary'
    control['form_contract']['semantic_roles']['bearing_supply_form'] = 'primary'
    # spindle_diameter_mm on a bearing is its bore under another name.
    retire(control, ['bb_construction', 'spindle_diameter_mm'])
    cartridge = condition('bearing_supply_form', CARTRIDGE)
    balls = condition('bearing_supply_form', LOOSE_FORMS)
    gate(control, {
        'bearing_size_code': deepcopy(cartridge),
        'bearing_inner_diameter_mm': deepcopy(cartridge),
        'bearing_outer_diameter_mm': deepcopy(cartridge),
        'bb_bearing_width_mm': deepcopy(cartridge),
        'bb_ball_size_in': deepcopy(balls),
        'bb_ball_count_per_side': deepcopy(balls),
    })
    control['form_contract']['helpers'].update({
        'bearing_inner_diameter_mm': (
            'Diámetro interior de ESTE rodamiento. Es la misma medida que el '
            'eje que admite, así que se declara una sola vez.'),
    })


def _cup(definitions, templates, live_fields):
    """The cup carries the seat that receives a bearing, and its own ports."""
    control = templates[CUP]
    drop(control, ['bb_shell_interface', 'bb_thread_hand', 'kit_members'])
    _ports(definitions, templates, CUP)
    _accepted(definitions, templates, CUP)
    definitions['bb_cup_seat_bevel'] = new_definition(
        'bb_cup_seat_bevel', 'Biseles del asiento del rodamiento',
        'single_select', (CUP,), options=SEAT_BEVELS)
    add_field(control, 'bb_cup_seat_bevel', 'measurement', 'measurement')
    control['form_contract']['roles']['bb_cup_seat_bevel'] = 'measurement'
    control['form_contract']['semantic_roles']['bb_cup_seat_bevel'] = 'measurement'
    retire(control, ['bb_construction', 'bb_cup_outer_diameter_mm',
                     'spindle_interface_accepted'])
    gate(control, {'bb_cup_seat_bevel': condition('bearing_included', False,
                                                  'boolean')},
         required={'bb_cup_seat_bevel': deepcopy(NEVER)})
    control['form_contract']['helpers'].update({
        'bb_cup_seat_bevel': (
            'Bisel del asiento que recibe el rodamiento. No es el ángulo de '
            'contacto de las pistas de ese rodamiento: son dos piezas y dos '
            'medidas. Se declara cuando la copa se vende sin su rodamiento.'),
        'bearing_included': (
            'Si la copa trae su rodamiento. No convierte a la copa en un kit '
            'ni en un catálogo de medidas de otra pieza.'),
    })


def _ports(definitions, templates, family):
    """Every thread has a side, a counterpart, a unit and a hand.

    Sheldon's threading table gives the hand per cup and not per product, so a
    single paired token cannot say which side is which. Park separates the
    major diameter from the pitch, which is why each has its own unit here.
    And a cup that threads into its opposite number says nothing about the
    frame's shell being threaded: that is what the counterpart column is for.
    """
    if PORTS not in definitions:
        table(definitions, templates, PORTS, 'Puertos declarados de esta pieza',
              (family,), [
                  column('port', 'Lado o puerto', 'token', required=True,
                         options=[DRIVE, NON_DRIVE, SINGLE_PORT]),
                  column('mates_with', 'Contra qué cierra este puerto', 'token',
                         required=True, options=[TO_SHELL, TO_CUP]),
                  column('form', 'Forma del puerto', 'token', required=True,
                         options=[THREADED, PRESSED, OEM_FORM]),
                  column('diameter', 'Diámetro mayor declarado', 'decimal',
                         positive=True),
                  column('diameter_unit', 'Unidad del diámetro', 'token',
                         options=['mm', 'in']),
                  column('pitch', 'Paso declarado', 'decimal', positive=True),
                  column('pitch_unit', 'Unidad del paso', 'token',
                         options=['mm', 'tpi']),
                  column('thread_hand', 'Sentido de la rosca', 'token',
                         options=[RIGHT_HAND, LEFT_HAND]),
                  column('designation', 'Designación OEM literal'),
                  column('source_scope', 'Apartado de la fuente', required=True),
                  column('source_url', 'Fuente', 'url', required=True),
              ], conditions={
                  'diameter': condition('form', MEASURED_PORTS),
                  'diameter_unit': condition('form', MEASURED_PORTS),
                  'pitch': condition('form', THREADED),
                  'pitch_unit': condition('form', THREADED),
                  'thread_hand': condition('form', THREADED),
                  'designation': condition('form', OEM_FORM),
              }, helper=(
                  'Un puerto por fila, con su lado y contra qué cierra. El '
                  'sentido de la rosca es de cada puerto: en una caja inglesa '
                  'las dos copas no giran igual. Que dos copas se rosquen '
                  'entre sí no dice que la caja del cuadro tenga rosca; eso lo '
                  'dice el puerto que cierra contra la caja.'))
        definitions[PORTS]['validation_rules']['rows_schema']['unique_by'] = [
            ['port', 'mates_with', 'source_scope']]
    else:
        definitions[PORTS]['used_by'].append(family)
        _reuse(definitions, templates, PORTS, family)


def _accepted(definitions, templates, family):
    """An accepted interface without its OEM variant is a brand rumour."""
    if ACCEPTED not in definitions:
        table(definitions, templates, ACCEPTED,
              'Ejes admitidos, declarados por variante', (family,), [
                  column('interface', 'Interfaz admitida', 'token', required=True,
                         options=SPINDLE_INTERFACES),
                  column('oem_brand', 'Marca de la variante', required=True),
                  column('oem_model', 'Modelo de la variante', required=True),
                  column('oem_edition', 'Edición o versión', required=True),
                  column('status', 'Estado declarado', 'token', required=True,
                         options=[COMPATIBLE, INCOMPATIBLE, CONDITIONED]),
                  column('conditions', 'Alcance o condiciones publicadas'),
                  column('source_scope', 'Apartado de la fuente', required=True),
                  column('source_url', 'Fuente', 'url', required=True),
              ], conditions={'conditions': {'kind': 'always'}},
              helper=(
                  'Una fila por variante admitida. Cuadrado JIS y Cuadrado ISO '
                  'son interfaces distintas y ninguna se hereda de la marca: '
                  'cada fila nombra el modelo y la versión con que se declaró. '
                  'Una exclusión publicada se registra; la ausencia de fila no '
                  'es un permiso.'))
        definitions[ACCEPTED]['validation_rules']['rows_schema']['unique_by'] = [
            ['interface', 'oem_brand', 'oem_model', 'oem_edition', 'source_scope']]
        entry = templates[family]['form_contract']['row_conditions']['fields'][ACCEPTED]
        entry['required_when']['conditions'] = condition('status', CONDITIONED)
    else:
        definitions[ACCEPTED]['used_by'].append(family)
        _reuse(definitions, templates, ACCEPTED, family)


def _systems(definitions, templates, family):
    """What a physical piece is declared FOR is a claim, not a property."""
    if SYSTEMS not in definitions:
        table(definitions, templates, SYSTEMS,
              'Sistemas de pedalier para los que se declara', (family,), [
                  column('system_brand', 'Marca del sistema', required=True),
                  column('system_model', 'Modelo del sistema', required=True),
                  column('system_edition', 'Edición o versión', required=True),
                  column('status', 'Estado declarado', 'token', required=True,
                         options=[COMPATIBLE, INCOMPATIBLE, CONDITIONED]),
                  column('conditions', 'Alcance o condiciones publicadas'),
                  column('source_scope', 'Apartado de la fuente', required=True),
                  column('source_url', 'Fuente', 'url', required=True),
              ], conditions={'conditions': {'kind': 'always'}},
              helper=(
                  'Esta pieza es un objeto físico con sus propias medidas; el '
                  'sistema para el que se declara es una afirmación del '
                  'fabricante, con su modelo y su versión. Una no se deduce de '
                  'la otra.'))
        definitions[SYSTEMS]['validation_rules']['rows_schema']['unique_by'] = [
            ['system_brand', 'system_model', 'system_edition', 'source_scope']]
        entry = templates[family]['form_contract']['row_conditions']['fields'][SYSTEMS]
        entry['required_when']['conditions'] = condition('status', CONDITIONED)
    else:
        definitions[SYSTEMS]['used_by'].append(family)
        _reuse(definitions, templates, SYSTEMS, family)


def _reuse(definitions, templates, key, family):
    """Add an already-defined local table to a second family, same conditions."""
    template = templates[family]
    source = next(t for t in templates.values()
                  if key in t['form_contract'].get('row_conditions', {})
                  .get('fields', {}))
    add_field(template, key, 'declaration', 'compatibility')
    template['form_contract']['roles'][key] = 'declaration'
    template['form_contract']['semantic_roles'][key] = 'declaration'
    template['form_contract']['allowed_when'][key] = {'kind': 'always'}
    template['form_contract']['required_when'][key] = deepcopy(NEVER)
    template['form_contract']['helpers'][key] = source['form_contract'][
        'helpers'].get(key, '')
    template['form_contract'].setdefault(
        'row_conditions', {'version': 1, 'fields': {}})['fields'][key] = deepcopy(
            source['form_contract']['row_conditions']['fields'][key])


# Every inherited regression is kept. The construction token that answered three
# questions is replaced by the three cells that answer them, so each scenario is
# rewritten cell by cell and the assertion is stated again in the new owner's
# terms. Nothing is softened: where a case blocked, it still blocks.
CONSTRUCTION = {
    'Cartucho sellado': {'bearing_supply_form': CARTRIDGE,
                         'bearing_seal_type': CONTACT_SEAL},
    'Cartucho abierto': {'bearing_supply_form': CARTRIDGE,
                         'bearing_seal_type': OPEN_SEAL},
    'Cartucho blindado': {'bearing_supply_form': CARTRIDGE,
                          'bearing_seal_type': SHIELDED},
    'Bolas sueltas (bolsa)': {'bearing_supply_form': LOOSE},
    'Canastillo con bolas': {'bearing_supply_form': RETAINER},
}
ANGULAR_TEXT = ('Contacto angular', 'Angular Contact MAX',
                'Contacto angular, doble hilera, MAX')


def _translate(inherited):
    out = []
    for old in inherited:
        new = deepcopy(old)
        values = dict(old['values'])
        notes = []
        construction = values.pop('bearing_construction', None)
        if construction is not None:
            values.update(deepcopy(CONSTRUCTION[construction]))
            notes.append(
                f'«{construction}» decía a la vez cómo se suministra y cómo se '
                'sella; pasa a forma de suministro más estado de sellado.')
        internal = values.pop('bearing_internal_construction', None)
        if internal is not None:
            values['bearing_race_type'] = (ANGULAR if internal in ANGULAR_TEXT
                                           else RADIAL)
            notes.append(
                f'«{internal}» era texto libre que competía con el ángulo '
                'tipado; pasa a la geometría de pistas.')
        seal = values.pop('bearing_seal_kind', None)
        if seal is not None:
            values['bearing_seal_designation'] = seal
            notes.append('la designación literal del sello conserva su celda, '
                         'ahora con el alcance en el nombre.')
        code = values.pop('bearing_dimensional_code', None)
        if code is not None:
            notes.append(f'el código dimensional «{code}» ya venía dentro de '
                         'bearing_size_code, que lo lleva con sus sufijos.')
        for key in ('bearing_inner_contact_angle_deg',
                    'bearing_outer_contact_angle_deg'):
            angle = values.pop(key, None)
            if angle is None:
                continue
            values.setdefault('bearing_race_contact_angle_deg', angle)
            if values.get('bearing_supply_form') == CARTRIDGE:
                values.setdefault('bearing_race_type', ANGULAR)
            notes.append(
                'el par de ángulos interior/exterior se leía como los biseles '
                'de un asiento; la geometría de rodadura es un solo ángulo de '
                'contacto de pistas.')
        bevel = values.pop('bearing_seat_geometry', None)
        if bevel is not None:
            notes.append(
                f'«{bevel}» describe el asiento que RECIBE al rodamiento, que '
                'es de la copa y no del rodamiento; el caso conserva lo que '
                'afirmaba sobre la pieza y el asiento se prueba en '
                'bottom_bracket_cup.')
        if values.get('bearing_race_type') == ANGULAR and \
                'bearing_race_contact_angle_deg' not in values and \
                old.get('expected_issue_subset'):
            notes.append('la pendiente del ángulo se conserva sobre la celda '
                         'que ahora lo posee.')
        new['values'] = values
        if old.get('expected_blocking'):
            new['expected_blocking'] = [
                {'code': b['code'],
                 'field': {'bearing_inner_contact_angle_deg':
                           'bearing_race_contact_angle_deg',
                           'bearing_outer_contact_angle_deg':
                           'bearing_race_contact_angle_deg',
                           'bearing_seal_kind': 'bearing_seal_designation',
                           }.get(b['field'], b['field'])}
                for b in old['expected_blocking']]
        if old.get('expected_issue_subset'):
            seen, subset = set(), []
            for issue in old['expected_issue_subset']:
                # The frozen ficha was pending on its angles because the
                # seat bevels demanded them — the conflation this successor
                # removes. Where the rolling geometry is still undeclared the
                # pending moves to the cell that now carries that unknown;
                # where the source did declare it, the pending disappears,
                # because nothing is missing any more. That second outcome is
                # a regression that weakens, and it is written down as such
                # rather than propped up by demanding a figure no manufacturer
                # prints.
                if issue['field'] in ('bearing_inner_contact_angle_deg',
                                      'bearing_outer_contact_angle_deg'):
                    if values.get('bearing_race_type'):
                        notes.append(
                            'la pendiente del ángulo desaparece: la exigía el '
                            'bisel del asiento, que no es propiedad de esta '
                            'pieza, y la geometría de pistas sí está '
                            'declarada. La regresión queda más débil y se '
                            'anota; el ángulo se admite y no se exige, porque '
                            'la fuente rara vez lo publica.')
                        continue
                    field = 'bearing_race_type'
                else:
                    field = issue['field']
                if (issue['code'], field) in seen:
                    continue
                seen.add((issue['code'], field))
                subset.append({**issue, 'field': field})
            new['expected_issue_subset'] = subset
            new['expected_sql_issue_subset'] = deepcopy(subset)
        if notes:
            new['successor_translation'] = ' '.join(notes)
        out.append(new)
    return out


def _cases():
    def port(**kw):
        # None means «this row does not carry it»; the row schema rejects a
        # literal null, so the cell is removed rather than emptied.
        row = dict({'port': DRIVE, 'mates_with': TO_SHELL, 'form': THREADED,
                    'diameter': '1.37', 'diameter_unit': 'in', 'pitch': '24',
                    'pitch_unit': 'tpi', 'thread_hand': LEFT_HAND,
                    'source_scope': 'Apartado sintético',
                    'source_url': SYNTHETIC}, **kw)
        return {k: v for k, v in row.items() if v is not None}
    accepted = lambda **kw: dict({'interface': 'Cuadrado JIS',
                                  'oem_brand': 'Marca sintética',
                                  'oem_model': 'Modelo sintético',
                                  'oem_edition': 'Edición sintética',
                                  'status': COMPATIBLE,
                                  'source_scope': 'Apartado sintético',
                                  'source_url': SYNTHETIC}, **kw)
    system = lambda **kw: dict({'system_brand': 'Marca sintética',
                                'system_model': 'Modelo sintético',
                                'system_edition': 'Edición sintética',
                                'status': COMPATIBLE,
                                'source_scope': 'Apartado sintético',
                                'source_url': SYNTHETIC}, **kw)
    cart = {'bearing_supply_form': CARTRIDGE, 'bearing_seal_type': CONTACT_SEAL}
    return [
        # --- construction cannot answer for the seal ------------------------
        case('bbx_loose_balls_cannot_declare_a_seal', BEARING,
             {'bearing_supply_form': LOOSE, 'bearing_seal_type': CONTACT_SEAL},
             blocking=[('field_applicability', 'bearing_seal_type')]),
        case('bbx_open_cartridge_cannot_declare_a_seal_designation', BEARING,
             {'bearing_supply_form': CARTRIDGE, 'bearing_seal_type': OPEN_SEAL,
              'bearing_seal_designation': '2RS'},
             blocking=[('field_applicability', 'bearing_seal_designation')]),
        case('bbx_sealed_cartridge_keeps_its_designation', BEARING,
             {**cart, 'bearing_seal_designation': 'LLU',
              'bearing_size_code': '3802 LLU MAX'}),
        case('bbx_supply_form_does_not_decide_the_seal', BEARING,
             {'bearing_supply_form': CARTRIDGE, 'bearing_seal_type': OPEN_SEAL,
              'bearing_size_code': '6902'}),

        # --- balls, retainer and cartridge stay apart ------------------------
        case('bbx_loose_balls_cannot_declare_a_cartridge_code', BEARING,
             {'bearing_supply_form': LOOSE, 'bearing_size_code': '6902'},
             blocking=[('field_applicability', 'bearing_size_code')]),
        case('bbx_cartridge_cannot_declare_a_ball_count', BEARING,
             {**cart, 'ball_diameter_in': '5/32', 'ball_count_per_pack': '100'},
             blocking=[('field_applicability', 'ball_diameter_in'),
                       ('field_applicability', 'ball_count_per_pack')]),
        case('bbx_retainer_keeps_its_ball_size', BEARING,
             {'bearing_supply_form': RETAINER, 'ball_diameter_in': '5/32'}),
        case('bbx_cartridge_keeps_its_retention', BEARING,
             {**cart, 'bearing_element_retention': 'Complemento completo / sin jaula',
              'bearing_row_count': '2'}),

        # --- race angle is not a seat bevel ---------------------------------
        case('bbx_radial_cartridge_cannot_declare_a_contact_angle', BEARING,
             {**cart, 'bearing_race_type': RADIAL,
              'bearing_race_contact_angle_deg': '15'},
             blocking=[('field_applicability', 'bearing_race_contact_angle_deg')]),
        case('bbx_angular_cartridge_declares_one_angle', BEARING,
             {**cart, 'bearing_race_type': ANGULAR,
              'bearing_race_contact_angle_deg': '36'}),
        case('bbx_angular_cartridge_without_its_angle_is_complete', BEARING,
             {**cart, 'bearing_race_type': ANGULAR}),
        case('bbx_cartridge_without_its_race_geometry_is_pending', BEARING,
             {**cart, 'bearing_size_code': '6902'},
             pending=[('required_missing', 'bearing_race_type')]),
        # The bevel of the seat that receives a bearing is on the cup, and it
        # is a different measurement from the bearing's own rolling geometry.
        case('bbx_cup_owns_the_seat_bevel', CUP,
             {'bearing_included': False,
              'bb_cup_seat_bevel': 'Biseles interior y exterior'}),
        case('bbx_cup_with_its_bearing_declares_no_seat', CUP,
             {'bearing_included': True,
              'bb_cup_seat_bevel': 'Biseles interior y exterior'},
             blocking=[('field_applicability', 'bb_cup_seat_bevel')]),

        # --- ports: side, unit, hand, and what the port closes against -------
        case('bbx_english_shell_has_two_hands', BB,
             {PORTS: rows(port(port=DRIVE, thread_hand=LEFT_HAND),
                          port(port=NON_DRIVE, thread_hand=RIGHT_HAND))}),
        case('bbx_same_port_twice_blocks', BB,
             {PORTS: rows(port(), port(thread_hand=RIGHT_HAND))},
             blocking=[('row_shape', PORTS)]),
        # Cups that thread to each other, in a shell that is pressed.
        case('bbx_cups_thread_to_each_other_in_a_pressed_shell', BB,
             {PORTS: rows(port(port=DRIVE, mates_with=TO_SHELL, form=PRESSED,
                               diameter='41', diameter_unit='mm', pitch=None,
                               pitch_unit=None, thread_hand=None),
                          port(port=NON_DRIVE, mates_with=TO_SHELL, form=PRESSED,
                               diameter='41', diameter_unit='mm', pitch=None,
                               pitch_unit=None, thread_hand=None),
                          port(port=SINGLE_PORT, mates_with=TO_CUP,
                               diameter='30', diameter_unit='mm', pitch='1',
                               pitch_unit='mm', thread_hand=RIGHT_HAND))}),
        # Only the pitch is out of place here. Leaving the hand in the row
        # would let its own gate do the blocking and the assertion would say
        # nothing about the pitch.
        case('bbx_a_pressed_port_cannot_declare_a_pitch', BB,
             {PORTS: rows(port(form=PRESSED, diameter='41', diameter_unit='mm',
                               thread_hand=None))},
             blocking=[('row_field_applicability', PORTS)]),
        case('bbx_a_pressed_port_cannot_declare_a_hand', BB,
             {PORTS: rows(port(form=PRESSED, diameter='41', diameter_unit='mm',
                               pitch=None, pitch_unit=None))},
             blocking=[('row_field_applicability', PORTS)]),
        case('bbx_an_oem_designation_cannot_carry_a_diameter', BB,
             {PORTS: rows(port(form=OEM_FORM, designation='BB86',
                               pitch=None, pitch_unit=None, thread_hand=None))},
             blocking=[('row_field_applicability', PORTS)]),
        case('bbx_a_threaded_port_keeps_both_units', BB,
             {PORTS: rows(port(diameter='36', diameter_unit='mm',
                               pitch='24', pitch_unit='tpi'))}),
        case('bbx_a_cup_carries_its_own_ports', CUP,
             {PORTS: rows(port(port=SINGLE_PORT))}),

        # --- accepted spindles need a variant, not a brand -------------------
        case('bbx_accepted_spindle_needs_its_variant', BB,
             {ACCEPTED: rows({'interface': 'Cuadrado JIS', 'status': COMPATIBLE,
                              'source_scope': 'Apartado sintético',
                              'source_url': SYNTHETIC})},
             pending=[('row_incomplete', ACCEPTED)]),
        case('bbx_jis_and_iso_are_two_declarations', BB,
             {ACCEPTED: rows(accepted(interface='Cuadrado JIS'),
                             accepted(interface='Cuadrado ISO',
                                      status=INCOMPATIBLE))}),
        case('bbx_same_variant_twice_blocks', BB,
             {ACCEPTED: rows(accepted(), accepted(status=INCOMPATIBLE))},
             blocking=[('row_shape', ACCEPTED)]),
        case('bbx_a_compatible_verdict_may_publish_its_scope', BB,
             {ACCEPTED: rows(accepted(conditions='Alcance sintético'))}),
        case('bbx_a_conditioned_verdict_needs_its_scope', BB,
             {ACCEPTED: rows(accepted(status=CONDITIONED))},
             pending=[('row_required_missing', ACCEPTED)]),

        # --- an included spindle is not the crank's spindle -------------------
        case('bbx_a_bb_without_a_spindle_cannot_measure_one', BB,
             {'includes_spindle': False, 'spindle_length_mm': '113'},
             blocking=[('field_applicability', 'spindle_length_mm')]),
        case('bbx_a_bb_without_a_spindle_still_accepts_them', BB,
             {'includes_spindle': False, ACCEPTED: rows(accepted())}),
        case('bbx_a_bb_with_a_spindle_measures_it', BB,
             {'includes_spindle': True, 'spindle_interface': 'Cuadrado JIS',
              'spindle_length_mm': '113', 'spindle_diameter_mm': '17'}),

        # --- arrangement is the bearing, ports are the mounting --------------
        case('bbx_cartridge_bb_cannot_count_balls', BB,
             {'bb_bearing_arrangement': CARTRIDGE_BB,
              'bb_ball_size_in': '1/4', 'bb_ball_count_per_side': '11'},
             blocking=[('field_applicability', 'bb_ball_size_in'),
                       ('field_applicability', 'bb_ball_count_per_side')]),
        case('bbx_cup_and_ball_bb_cannot_declare_a_cartridge_code', BB,
             {'bb_bearing_arrangement': CUPS_AND_BALLS,
              'bearing_size_code': '6902'},
             blocking=[('field_applicability', 'bearing_size_code')]),
        case('bbx_cup_and_ball_bb_counts_its_balls', BB,
             {'bb_bearing_arrangement': CUPS_AND_BALLS,
              'bb_ball_size_in': '1/4', 'bb_ball_count_per_side': '11'}),

        # --- a physical piece versus the system it is declared for -----------
        case('bbx_an_axle_declares_its_systems', AXLE,
             {'spindle_interface': 'Cuadrado JIS', 'spindle_length_mm': '113',
              'spindle_diameter_mm': '17', SYSTEMS: rows(system())}),
        case('bbx_same_system_twice_blocks', AXLE,
             {SYSTEMS: rows(system(), system(status=INCOMPATIBLE))},
             blocking=[('row_shape', SYSTEMS)]),
        case('bbx_a_declared_system_needs_its_edition', AXLE,
             {SYSTEMS: rows({'system_brand': 'Marca sintética',
                             'system_model': 'Modelo sintético',
                             'status': COMPATIBLE,
                             'source_scope': 'Apartado sintético',
                             'source_url': SYNTHETIC})},
             pending=[('row_incomplete', SYSTEMS)]),

        # --- a bore is declared once ------------------------------------------
        case('bbx_bb_bearing_declares_its_bore_once', BB_BEARING,
             {'bearing_supply_form': CARTRIDGE, 'bearing_size_code': '6902',
              'bearing_inner_diameter_mm': '15',
              'bearing_outer_diameter_mm': '28', 'bb_bearing_width_mm': '7'}),
        case('bbx_bb_bearing_with_loose_balls_has_no_cartridge_code', BB_BEARING,
             {'bearing_supply_form': LOOSE, 'bearing_size_code': '6902'},
             blocking=[('field_applicability', 'bearing_size_code')]),
        case('bbx_bb_bearing_with_loose_balls_counts_them', BB_BEARING,
             {'bearing_supply_form': LOOSE, 'bb_ball_size_in': '1/4',
              'bb_ball_count_per_side': '11'}),
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-bearing-bb-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-bearing-bb-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'live_shared': len(catalog['live_shared_definitions']),
                      'renames_declined': len(catalog['renames_declined']),
                      'corrected_from_frozen': len(catalog['adopted_live_definitions'])}))
