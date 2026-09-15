#!/usr/bin/env python3
"""Source-to-candidate successor for the seven existing brake families.

brake_caliper, brake_lever, brake_pad, hydraulic_disc_brake,
mechanical_disc_brake, rim_brake and rotor. No migration, no production, no
fill, no assignment changes.

Three rules order the block, and each one comes from a defect measured in the
frozen proposal rather than from taste.

1. **One fact, one owner.** A fluid class in a select and again in an approvals
   table, a hose length on the product and again in its configuration row, a
   mount whose vocabulary contains «adapter required»: each is two cells that
   can disagree.
2. **The owner is the piece that has the property.** Lever reach belongs to a
   lever, not to a caliper that never touches the bar. What a caliper accepts
   belongs to the port and position that accept it.
3. **A row table without a key is not a table.** Not one of the eight row
   definitions the seven use declared `unique_by`, so two rows could answer the
   same question differently and nothing noticed.

Shared definitions come from the LIVE preimage. Five of the ones these families
use say `origin: new` in the frozen proposal and are already published, and four
more carry option lists the proposal would have extended.
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

CALIPER = 'brake_caliper'
LEVER = 'brake_lever'
PAD = 'brake_pad'
HYDRAULIC = 'hydraulic_disc_brake'
MECHANICAL = 'mechanical_disc_brake'
RIM = 'rim_brake'
ROTOR = 'rotor'
FAMILIES = (CALIPER, LEVER, PAD, HYDRAULIC, MECHANICAL, RIM, ROTOR)

PREIMAGE = ROOT / '.tmp/db/existing-37-candidate-preimage.json'
PREIMAGE_SHA = '0a21d85a1539c330e661e0c5c1aa2fde0bbf29ddad67a452a018ed767d08b2a6'

# Sheldon, Cantilever Brakes, opened and read. Two things this block uses.
#
# The pull a lever delivers and the pull a brake needs are separate facts that
# have to match: the page warns that conventional levers on direct-pull
# cantilevers «will usually not pull enough cable», and that direct-pull levers
# on anything else leave you squeezing twice as hard. Neither is derivable from
# a brand, which is why the lever keeps what it delivers and the brake keeps
# what it requires, in different cells on different pieces.
#
# And the pivot studs sit in different places per brake type — below the rim
# for direct-pull, above it for U-brakes — so the mount is a fact of the mount
# and not a scalar of the product.
SHELDON_CANTI = 'https://www.sheldonbrown.com/cantilever-adjustment.html'
# Sheldon, Disc Brakes, opened and read. Three things this block uses.
#
# A used rotor's thickness is a state, not a nominal: «The disc-brake rotor
# becomes thinner as it wears.» The discard figure is per manufacturer and not
# a universal — the page names 1.5 mm for most brands, 1.7 for Moment
# Industries and 1.52 for Hayes — so a limit without its OEM scope is a rumour.
# And measuring a worn rotor is not trivial: its thickness «cannot be measured
# directly with a conventional vernier caliper, due to the concavity», which is
# why a measured figure has to say how it was taken.
#
# On fluid the page says only that «Care must be taken to use the correct brake
# fluid», without naming which. That is a reason to demand the approval row
# with its system and source, not a licence to guess a class.
SHELDON_DISC = 'https://www.sheldonbrown.com/disc-brakes.html'
# TRP HY/RD, opened and read: «Using an open hydraulic system it's compatible
# with Shimano and SRAM 11 speed road shift levers», with «True 'plug-and-play'
# compatibility with existing cable actuated systems». So the conversion from
# cable to hydraulic happens INSIDE the caliper, and there is no external
# converter to name. The page does not publish its fluid, which stays pending.
TRP_HYRD = 'https://trpcycling.com/products/hy-rd'
# No source read in this block publishes a reach range tied to a mount, and
# none is invented. Reach moves into the fitment row because that row already
# carries the mount, the position and its own source — a structural decision,
# stated as such.
SYNTHETIC = 'https://example.invalid/synthetic'

DISC, RIM_SURFACE = 'Disco', 'Llanta'
CABLE, HYDRAULIC_ACT, HYBRID = ('Mecánico (cable)', 'Hidráulico',
                                'Híbrido (cable a hidráulico)')
WET_ACTUATION = [HYDRAULIC_ACT, HYBRID]
CABLE_ACTUATION = [CABLE, HYBRID]
FRONT, REAR = 'Delantero', 'Trasero'

RECIPE = 'rotor_size_recipe'
FITMENTS = 'rim_brake_mount_fitments'
CONFIGURATIONS = 'brake_assembly_configurations'
CONNECTIONS = 'brake_hydraulic_connections'
APPROVALS = 'brake_model_fluid_approvals'
LIVE_SHARED_INPUT = RESEARCH / 'existing-brakes-shared-live-input-2026-09-08.json'
LIVE_SHARED_SHA = '926aaf8421524e40bdc6cd02654e96bcc30f83652655d10f74c08421e484b6db'
BLEED = 'brake_bleed_ports'
PAD_CALIPERS = 'compatible_caliper_models'
KIT = 'kit_members'
CONVERTER = 'brake_external_converter_model'
CONVERSION = 'brake_conversion_location'
IN_PIECE, IN_DEVICE = 'En esta pieza', 'En un dispositivo externo'
PIECE_PORTS = 'brake_piece_hydraulic_ports'
CIRCUIT_LINKS = 'brake_circuit_connections'
NOMINAL = 'rotor_nominal_thickness_mm'
WEAR_LIMIT = 'rotor_wear_limit_mm'
MEASURED = 'rotor_measured_thickness_mm'
METHOD = 'rotor_thickness_measurement_method'


def both(*conditions):
    merged = deepcopy(conditions[0])
    for extra in conditions[1:]:
        merged['rows'][0].extend(deepcopy(extra)['rows'][0])
    return merged


def drop(template, keys):
    """Remove a field that was proposed and never published.

    Legal only for a key absent from the live preimage. A published field is
    retired instead, because an observation hangs from it.
    """
    contract = template['form_contract']
    template['fields'] = [f for f in template['fields'] if f['key'] not in keys]
    for section in ('roles', 'semantic_roles', 'labels', 'allowed_when',
                    'required_when', 'allowed_options', 'prerequisites',
                    'helpers', 'evidence_requirements'):
        for key in keys:
            contract.get(section, {}).pop(key, None)
    gone = set(keys)
    for owner, deps in list(contract.get('prerequisites', {}).items()):
        kept = [d for d in deps if d not in gone]
        if kept:
            contract['prerequisites'][owner] = kept
        else:
            contract['prerequisites'].pop(owner)
    pairs = contract.get('scalar_ordered_pairs')
    if pairs:
        contract['scalar_ordered_pairs'] = [
            p for p in pairs if not gone.intersection(p)]
        if not contract['scalar_ordered_pairs']:
            contract.pop('scalar_ordered_pairs')


def gate(template, mapping, required=None):
    contract = template['form_contract']
    for key, rule in mapping.items():
        contract['allowed_when'][key] = deepcopy(rule)
        contract['required_when'][key] = deepcopy(
            (required or {}).get(key, rule))


def key_rows(definitions, table_key, columns):
    """Give a row table a composite key made only of required columns.

    Refuses a published definition outright. A key is a change to
    `validation_rules`, and a live shared row belongs to every family that uses
    it — `brake_hydraulic_connections` is shared by seven — so keying it is its
    own adjudication and not a side effect of one block.
    """
    if definitions[table_key].get('origin') == 'existing':
        raise ValueError(
            f'{table_key} is published: a shared row schema is not ours to key')
    schema = definitions[table_key]['validation_rules']['rows_schema']
    required = {c['key'] for c in schema['columns'] if c.get('required')}
    missing = [c for c in columns if c not in required]
    if missing:
        raise ValueError(f'{table_key}: key column not required: {missing}')
    schema['unique_by'] = [list(columns)]


def add_column(definitions, table_key, spec, *, after=None):
    schema = definitions[table_key]['validation_rules']['rows_schema']
    if any(c['key'] == spec['key'] for c in schema['columns']):
        raise ValueError(f"{table_key}: column already present: {spec['key']}")
    if after is None:
        schema['columns'].append(spec)
        return
    index = next(i for i, c in enumerate(schema['columns']) if c['key'] == after)
    schema['columns'].insert(index + 1, spec)


def row_gate(template, table_key, mapping, required=None):
    entry = template['form_contract'].setdefault(
        'row_conditions', {'version': 1, 'fields': {}})['fields'].setdefault(
            table_key, {})
    entry.setdefault('allowed_when', {})
    entry.setdefault('required_when', {})
    for key, rule in mapping.items():
        entry['allowed_when'][key] = deepcopy(rule)
        entry['required_when'][key] = deepcopy(
            (required or {}).get(key, rule))


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA),
                      (PREIMAGE, PREIMAGE_SHA), (LIVE_SHARED_INPUT, LIVE_SHARED_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen input drift: ' + path.name)
    base = json.loads(CATALOG.read_text())
    live = json.loads(PREIMAGE.read_text())
    live = live[0]['metadata'] if isinstance(live, list) else live
    published = {d['key']: d for d in live['existing_definitions']}
    # The combined-control publication made four more definitions shared after
    # the original 37-template snapshot. Their actual schema remains immutable.
    shared_live = json.loads(LIVE_SHARED_INPUT.read_text())
    published.update({d['key']: d for d in shared_live['existing_definitions']})
    live_templates = {t['key']: t for t in live['templates']}
    by_id = {t['id']: t['key'] for t in live['templates']}
    definition_key = {d['id']: d['key'] for d in live['existing_definitions']}
    live_fields = {t['key']: set() for t in live['templates']}
    for field in live['fields']:
        live_fields[by_id[field['template_id']]].add(
            definition_key[field['spec_definition_id']])

    templates = {t['key']: deepcopy(t)
                 for t in base['templates'] if t['key'] in FAMILIES}
    definitions = deepcopy(base['definitions'])
    fixtures = json.loads(CASES.read_text())
    fixtures['cases'] = [c for c in fixtures['cases']
                         if c['template'] in FAMILIES]
    # Stricter model+edition+fluid-product claims need a new definition, not an
    # in-place mutation of the approvals already used by combined controls.
    if any('brake_fluid_approvals' in live_fields[f] for f in FAMILIES):
        raise ValueError('A published approval use requires explicit retirement')
    definitions[APPROVALS] = new_definition(APPROVALS,
        'Fluidos aprobados por modelo y edición', 'json', FAMILIES,
        rules=deepcopy(definitions['brake_fluid_approvals']['validation_rules']))
    def scope_approvals(value):
        if isinstance(value, dict):
            return {APPROVALS if k == 'brake_fluid_approvals' else k: scope_approvals(v)
                    for k, v in value.items()}
        if isinstance(value, list):
            return [scope_approvals(v) for v in value]
        return APPROVALS if value == 'brake_fluid_approvals' else value
    templates = scope_approvals(templates)
    fixtures['cases'] = scope_approvals(fixtures['cases'])

    # The live row is authoritative over the frozen proposal. Five keys these
    # families use say `new` there and are published; four more carry option
    # lists the proposal would have extended, and adding an option to a live
    # definition is refused by the publisher, not merged.
    changed = set()
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
            changed.add(key)

    # A rename is a product decision, not a side effect of reworking a
    # contract. All seven differ; the live word is what the shop uses.
    renamed = {}
    for key, template in templates.items():
        actual = live_templates[key]
        if template.get('name') != actual['name']:
            renamed[key] = {'frozen_proposal': template.get('name'),
                            'live_preserved': actual['name']}
            template['name'] = actual['name']

    _tables(definitions, templates)
    _caliper(definitions, templates)
    _lever(definitions, templates)
    _pad(definitions, templates)
    _assemblies(definitions, templates)
    _rim(definitions, templates)
    _rotor(definitions, templates)

    # A ficha is not complete because it skipped the question that opens the
    # others. Every field that some gate reads is required, so an unanswered
    # selector leaves the ficha pending instead of quietly finished. Computed
    # from the gates themselves rather than from a hand-written list, so a gate
    # added later cannot forget its selector.
    for template in templates.values():
        contract = template['form_contract']
        roles = contract['roles']
        selectors = {term['field']
                     for section in ('allowed_when', 'required_when')
                     for rule in contract.get(section, {}).values()
                     for clause in rule.get('rows', [])
                     for term in clause}
        for key in sorted(selectors):
            if roles.get(key) == 'legacy':
                continue
            contract['required_when'][key] = {'kind': 'always'}

    for template in templates.values():
        conditions = template['form_contract'].get(
            'row_conditions', {}).get('fields', {})
        for key in [k for k in conditions
                    if template['form_contract']['roles'].get(k) == 'legacy']:
            del conditions[key]
        present = {f['key'] for f in template['fields']}
        for key in list(template['form_contract']['roles']):
            if key not in present:
                raise ValueError(
                    f"{template['key']}: contract mentions a gone field {key}")
        for section in ('allowed_when', 'required_when'):
            for owner, rule in template['form_contract'].get(section, {}).items():
                for clause in rule.get('rows', []):
                    for term in clause:
                        if term.get('field') not in present:
                            raise ValueError(
                                f"{template['key']}.{section}.{owner} still "
                                f"reads {term['field']}")
        missing = live_fields[template['key']] - present
        if missing:
            raise ValueError(
                f"{template['key']} would lose published fields: {sorted(missing)}")

    from compile_existing_brakes_root import adjust_catalog, adjust_cases
    adjust_catalog(definitions, templates)
    fixtures['cases'] = _translate(fixtures['cases']) + _cases()
    adjust_cases(fixtures)
    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Brake families reviewed successor',
               'templates': [templates[f] for f in FAMILIES],
               'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA,
                                'preimage': PREIMAGE_SHA},
               'renames_declined': renamed,
               'live_shared_definitions': sorted(k for k in keys if k in published),
               'adopted_live_definitions': sorted(changed & keys),
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False,
               'shared_live_input_sha256': LIVE_SHARED_SHA}
    catalog['stats'] = {'templates': len(catalog['templates']),
                        'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in catalog['templates'])}
    return catalog, fixtures


def _tables(definitions, templates):
    """Every row table gets a key, and two of them gain the cell that was
    living as a loose scalar on the product.

    Not one of the eight declared `unique_by`, so a ficha could hold two rows
    answering the same question with different figures and nothing objected.
    Each key is built only from required columns: a key that contains an
    optional cell is the HY-B weakness, and it has already been reproduced
    twice in this project.
    """
    # What a caliper accepts is a property of the port and the position that
    # accept it, with the source that says so — not a bare figure on the
    # product. The nominal thickness moves in beside the mount it belongs to.
    add_column(definitions, RECIPE,
               column('accepted_rotor_thickness_mm',
                      'Espesor de rotor admitido por esta receta', 'decimal',
                      unit='mm', positive=True),
               after='rotor_diameter_mm')
    # Reach travels with the mount it is measured from, so it belongs to the
    # fitment row and not to the product. No source here publishes such a
    # range; what the move buys is that a reach cannot be stated without the
    # mount and the source it came from.
    for spec in (column('reach_min_mm', 'Reach mínimo desde este montaje',
                        'decimal', unit='mm', positive=True),
                 column('reach_max_mm', 'Reach máximo desde este montaje',
                        'decimal', unit='mm', positive=True)):
        add_column(definitions, FITMENTS, spec)
    definitions[FITMENTS]['validation_rules']['rows_schema'][
        'ordered_pairs'].append(['reach_min_mm', 'reach_max_mm'])

    key_rows(definitions, RECIPE,
             ['position', 'frame_mount', 'rotor_diameter_mm', 'source_url'])
    key_rows(definitions, FITMENTS,
             ['position', 'mount_spec', 'brake_model', 'source_url'])
    key_rows(definitions, CONFIGURATIONS, ['circuit_id', 'position', 'source_url'])
    # brake_hydraulic_connections is published and shared by seven families, so
    # it keeps the schema it has. It is the one row table in this block that
    # ends without a composite key, and that is an open gate, not an oversight:
    # two rows can still describe the same end of the same circuit with
    # different fittings and nothing objects.
    key_rows(definitions, APPROVALS,
             ['system_brand', 'system_model', 'fluid_class', 'source_url'])
    key_rows(definitions, BLEED, ['component_role', 'port_id', 'source_url'])
    key_rows(definitions, PAD_CALIPERS, ['brand', 'model', 'source_url'])

    definitions[CONVERSION] = new_definition(
        CONVERSION, 'Dónde ocurre la conversión declarada', 'single_select',
        (CALIPER, LEVER, RIM), options=[IN_PIECE, IN_DEVICE])
    definitions[CONVERTER] = new_definition(
        CONVERTER, 'Convertidor externo declarado', 'text',
        (CALIPER, LEVER, RIM))

    # The piece's own hydraulic ports. A caliper or a lever IS the owner of its
    # ports, so there is no parent row to resolve and nothing pretends there is
    # one: the circuit id that used to sit here resolved against nothing.
    table(definitions, templates, PIECE_PORTS,
          'Puertos hidráulicos de esta pieza', (CALIPER, LEVER), [
              column('port_id', 'Identificador del puerto físico', required=True),
              column('end_role', 'Papel del extremo', 'token', required=True,
                     options=['Entrada', 'Salida', 'Purgador']),
              column('fitting_model', 'Conector declarado'),
              column('connection_spec', 'Especificación de la conexión'),
              column('source_scope', 'Apartado y alcance de la fuente',
                     required=True),
              column('source_url', 'Fuente', 'url', required=True),
          ], helper=(
              'Un puerto físico por fila, de ESTA pieza. No hay circuito padre '
              'que resolver: la pieza es la dueña. Cambiar de apartado no '
              'permite repetir el mismo puerto con otro conector.'))
    definitions[PIECE_PORTS]['validation_rules']['rows_schema']['unique_by'] = [
        ['port_id']]

    # For an assembly the owner IS a configuration, so the row names it and the
    # engine resolves it. A free-text circuit id proved nothing.
    table(definitions, templates, CIRCUIT_LINKS,
          'Conexiones del circuito, por configuración', (HYDRAULIC, RIM), [
              column('configuration_row_id',
                     'Configuración a la que pertenece esta conexión',
                     required=True),
              column('component_role', 'Componente de este extremo', 'token',
                     required=True,
                     options=['Maneta', 'Cáliper', 'Convertidor', 'Manguera']),
              column('end_role', 'Papel del extremo', 'token', required=True,
                     options=['Entrada', 'Salida', 'Extremo A', 'Extremo B']),
              column('component_brand', 'Marca del componente', required=True),
              column('component_model', 'Modelo del componente', required=True),
              column('hose_brand', 'Marca del latiguillo'),
              column('hose_model', 'Modelo del latiguillo'),
              column('fitting_model', 'Conector declarado'),
              column('connection_spec', 'Especificación de la conexión'),
              column('source_scope', 'Apartado y alcance de la fuente',
                     required=True),
              column('source_url', 'Fuente', 'url', required=True),
          ], helper=(
              'Cada extremo pertenece a una configuración declarada de este '
              'conjunto, y el motor comprueba que esa configuración exista. '
              'Delantero y trasero no comparten circuito por venir en la misma '
              'caja.'))
    definitions[CIRCUIT_LINKS]['validation_rules']['rows_schema']['unique_by'] = [
        ['configuration_row_id', 'component_role', 'end_role', 'source_scope']]


def _converter(definitions, templates, family):
    """Where the conversion happens, and only then who performs it.

    My first pass assumed a hybrid piece is always driven by an external
    converter. TRP's HY/RD says otherwise in its own words: an open hydraulic
    system that is plug-and-play with existing cable-actuated levers. The cable
    arrives at the caliper and the conversion happens **inside it**; there is no
    external device to name, and a schema that demanded one would have made the
    most common hybrid on the market unrepresentable.

    So the hybrid piece first says where the conversion occurs, and only a
    conversion placed in an external device asks which device.
    """
    template = templates[family]
    for key, section in ((CONVERSION, 'primary'), (CONVERTER, 'measurement')):
        add_field(template, key, section, section)
        template['form_contract']['roles'][key] = section
        template['form_contract']['semantic_roles'][key] = section
    hybrid = condition('brake_actuation', HYBRID)
    gate(template, {
        CONVERSION: deepcopy(hybrid),
        CONVERTER: both(condition(CONVERSION, IN_DEVICE), hybrid),
    })
    template['form_contract']['helpers'].update({
        CONVERSION: (
            'Sólo si la pieza declara accionamiento híbrido: si convierte el '
            'cable a hidráulico dentro de sí misma o si la convierte un '
            'dispositivo aparte. Una maneta de cable corriente acciona un '
            'cáliper que convierte por dentro, y ahí no hay convertidor que '
            'nombrar.'),
        CONVERTER: (
            'Qué dispositivo externo hace la conversión, cuando la hace uno. '
            'No se pide cuando la pieza convierte por dentro.'),
    })


def _caliper(definitions, templates):
    """A caliper owns its own actuation, its port and what that port accepts.

    Three cells leave. `fluid_type` and `hose_system_code` each answered in a
    scalar what a table already answers with its system, its model and its
    source — the select-plus-table duplication. And `reach_adjust` is the
    distance from a lever to the bar: a caliper never touches the bar, so it
    cannot have that property. All three are published, so all three are
    retired and their observations stay.
    """
    template = templates[CALIPER]
    _converter(definitions, templates, CALIPER)
    _ports(templates, CALIPER)
    # The nominal thickness moved into the recipe row, beside its mount and its
    # source; the bare scalar was never published, so it goes.
    drop(template, ['caliper_rotor_nominal_thickness_mm'])
    retire(template, ['fluid_type', 'hose_system_code', 'reach_adjust',
                      'mount_standard'])
    drop(template, [CONNECTIONS])
    disc = condition('braking_surface', DISC)
    row_gate(templates[CALIPER], RECIPE,
             {'accepted_rotor_thickness_mm': {'kind': 'always'}},
             required={'accepted_rotor_thickness_mm': deepcopy(NEVER)})
    gate(template, {
        # A rim caliper has no rotor recipe and no pad retainer of a disc pad.
        'brake_pad_retainer_model': deepcopy(disc),
        'piston_count_value': deepcopy(disc),
    }, required={
        'brake_pad_retainer_model': deepcopy(NEVER),
        'piston_count_value': deepcopy(NEVER),
    })
    template['form_contract']['helpers'].update({
        'brake_actuation': (
            'Cómo se acciona ESTE cáliper. Si lo mueve un convertidor externo, '
            'el cáliper sigue siendo hidráulico y el convertidor se nombra '
            'aparte.'),
        'cable_pull_required': (
            'El tiro que ESTE cáliper exige de una maneta. No es el que una '
            'maneta entrega, y no se deduce de la marca.'),
        RECIPE: (
            'Qué rotor admite, por posición y por montaje, con el adaptador '
            'que haga falta y el espesor admitido de esa misma receta. Un '
            'montaje no es un adaptador y un diámetro admitido no es el que '
            'viene en la caja.'),
    })


def _ports(templates, family):
    """The piece's own ports hang on the piece declaring it has an outside end."""
    template = templates[family]
    gate(template, {PIECE_PORTS: both(
        condition('brake_external_hose_connection', True, 'boolean'),
        condition('brake_actuation', WET_ACTUATION))},
        required={PIECE_PORTS: deepcopy(NEVER)})


def _circuits(templates, family):
    """An assembly's connections name a configuration the engine resolves.

    The published table joined by a free-text `circuit_id`. On an assembly that
    id did point at a configuration through a coherence link; on a bare caliper
    it pointed at nothing at all and no one noticed. The successor keeps the
    link where a parent exists and gives the caliper its own ports where one
    does not, instead of a column that pretends.
    """
    template = templates[family]
    # Defined in the frozen proposal, never published on any of the 37, so the
    # use is dropped instead of carried forward as an empty legacy row.
    drop(template, [CONNECTIONS])
    template['form_contract']['row_coherence'] = {
        'version': 1,
        'links': [{'id': 'brake_circuit_owner', 'field': CIRCUIT_LINKS,
                   'column': 'configuration_row_id',
                   'target_field': CONFIGURATIONS,
                   'label_columns': ['position', 'circuit_id']}]}
    gate(template, {CIRCUIT_LINKS: {'kind': 'always'}},
         required={CIRCUIT_LINKS: deepcopy(NEVER)})


def _lever(definitions, templates):
    """The lever delivers a pull; it does not require one."""
    template = templates[LEVER]
    _converter(definitions, templates, LEVER)
    _ports(templates, LEVER)
    retire(template, ['fluid_type', 'hose_system_code'])
    drop(template, [CONNECTIONS])
    template['form_contract']['helpers'].update({
        'lever_cable_pull': (
            'El tiro que ESTA maneta entrega. Lo que un cáliper exige es otra '
            'celda en otra pieza, y una no implica la otra.'),
        'handlebar_clamp_mm': 'Sobre qué manillar cierra ESTA maneta.',
    })


def _pad(definitions, templates):
    """The typed compound and the manufacturer's literal name for it."""
    template = templates[PAD]
    live_compounds = definitions['compound_type']['allowed_values']
    gate(template, {
        'brake_pad_oem_compound': both(
            condition('compound_type', list(live_compounds)),
            condition('braking_surface', DISC)),
    }, required={'brake_pad_oem_compound': deepcopy(NEVER)})
    row_gate(template, PAD_CALIPERS, {'conditions': {'kind': 'always'}},
             required={'conditions': deepcopy(NEVER)})
    template['form_contract']['helpers'].update({
        'compound_type': (
            'La clase de compuesto. El nombre comercial con que el fabricante '
            'la rotula va en su propia celda y no puede contradecirla: sin '
            'clase declarada no hay nombre que calificar.'),
        PAD_CALIPERS: (
            'Los cáliperes para los que el fabricante declara ESTA pastilla, '
            'uno por fila con su fuente. Compartir marca no es una '
            'declaración sobre un modelo.'),
        'rim_material_intended': (
            'Para qué pista de llanta la declara el fabricante. Es su '
            'declaración sobre este patín, no una regla sobre esa pista.'),
    })


def _assemblies(definitions, templates):
    """A complete brake: what it is, and what its configuration says.

    Both assemblies arrived with no scalar gate at all, so a mechanical set
    could declare a fluid and a hydraulic one could declare a required cable
    pull. And `hose_length_mm` sat on the product while the configuration row
    carries the same length per position — the same fact twice.
    """
    for family in (HYDRAULIC, MECHANICAL):
        template = templates[family]
        retire(template, ['mount_standard'])
        key = condition('brake_position', [FRONT, REAR])
        gate(template, {
            'rotor_included_diameter_mm': {'kind': 'always'},
            'pad_shape_code': {'kind': 'always'},
            'brake_pad_retainer_model': {'kind': 'always'},
            'reach_adjust': {'kind': 'always'},
        }, required={
            'rotor_included_diameter_mm': deepcopy(NEVER),
            'pad_shape_code': deepcopy(NEVER),
            'brake_pad_retainer_model': deepcopy(NEVER),
            'reach_adjust': deepcopy(NEVER),
        })
        del key
        template['form_contract']['helpers'].update({
            'rotor_included_diameter_mm': (
                'El rotor que viene en la caja. Lo que el conjunto admite lo '
                'dice su receta, por posición y montaje: son dos preguntas.'),
            CONFIGURATIONS: (
                'Una configuración por circuito y posición. Delantero y '
                'trasero conservan sus propias medidas; ninguna se copia de la '
                'otra por venir en la misma caja.'),
        })
    _circuits(templates, HYDRAULIC)
    hydraulic = templates[HYDRAULIC]
    # The length of the hose lives with the circuit that carries it.
    retire(hydraulic, ['hose_length_mm', 'fluid_type'])
    drop(hydraulic, ['hose_system_code'])
    gate(hydraulic, {'piston_count_value': {'kind': 'always'}},
         required={'piston_count_value': deepcopy(NEVER)})
    mechanical = templates[MECHANICAL]
    gate(mechanical, {
        'cable_pull_required': {'kind': 'always'},
        'levers_included': {'kind': 'always'},
        'tool_size_mm': {'kind': 'always'},
    }, required={
        'cable_pull_required': deepcopy(NEVER),
        'levers_included': deepcopy(NEVER),
        'tool_size_mm': deepcopy(NEVER),
    })
    mechanical['form_contract']['helpers'].update({
        'levers_included': (
            'Si el conjunto trae manetas. No se supone por venderse como '
            'conjunto, y su ausencia queda pendiente.'),
    })


def _rim(definitions, templates):
    """Reach and pivot belong to the mount, so they move into its row."""
    template = templates[RIM]
    _converter(definitions, templates, RIM)
    _circuits(templates, RIM)
    # Both the reach pair and the frame mount were unpublished scalars that the
    # fitment row now answers per position and per mount, with its own source.
    drop(template, ['reach_min_mm', 'reach_max_mm', 'rim_brake_frame_mount'])
    row_gate(template, FITMENTS, {
        'reach_min_mm': {'kind': 'always'},
        'reach_max_mm': {'kind': 'always'},
    }, required={'reach_min_mm': deepcopy(NEVER),
                 'reach_max_mm': deepcopy(NEVER)})
    template['form_contract']['helpers'].update({
        FITMENTS: (
            'Un montaje por fila y por posición, con la separación de sus '
            'pivotes y el reach que alcanza desde ahí. El mismo freno alcanza '
            'distinto en otro montaje, así que el reach no es del producto.'),
        'lever_pull_required': (
            'El tiro que ESTE freno exige de una maneta. No lo decide la marca '
            'ni el estilo por sí solo.'),
    })


def _rotor(definitions, templates):
    """The rotor arrived with no gate and no ordering between its thicknesses.

    A new thickness and a discard thickness are two figures of one part, and the
    discard figure is never the larger of the two. That needs no source: it is
    arithmetic about a part that only ever gets thinner. Nothing here checked
    it, so a ficha could state a minimum above the new thickness and pass.
    """
    template = templates[ROTOR]
    # Two catalogue figures. Wear of an individual used rotor belongs to a
    # physical inspection, never to every unit of this SKU (technical contract
    # section on ownership). Preserve the ambiguous published field as legacy.
    #
    # The published `rotor_thickness_mm` carries no unit and no statement of
    # which of the three it is. Stripping the unit off its new sibling to make
    # the comparator accept the pair — which is what I did first — buys an
    # ordering by throwing away the one thing that makes a number readable. The
    # live definition keeps its history and its observations as legacy, and the
    # two successors say what they are and in what unit. An actual worn
    # rotor may measure below its limit, but that is not a catalogue fact.
    #
    # The limit is per manufacturer — that page names 1.5 mm for most brands,
    # 1.7 for one and 1.52 for another — so it is never a universal and travels
    # with the evidence of who published it.
    for key, label in ((NOMINAL, 'Espesor nominal de un rotor nuevo'),
                       (WEAR_LIMIT, 'Límite de desgaste publicado por el OEM')):
        definitions[key] = new_definition(key, label, 'number', (ROTOR,),
                                          unit='mm', rules={'positive': True})
        add_field(template, key, 'measurement', 'measurement')
        template['form_contract']['roles'][key] = 'measurement'
        template['form_contract']['semantic_roles'][key] = 'measurement'
    drop(template, ['rotor_min_thickness_mm'])
    retire(template, ['rotor_thickness_mm'])
    template['form_contract']['scalar_ordered_pairs'] = [
        [WEAR_LIMIT, NOMINAL]]
    gate(template, {
        # A rotor states its own geometry; the compound it restricts is a
        # statement about this rotor, admissible only once its track material
        # is on the record.
        NOMINAL: {'kind': 'always'},
        WEAR_LIMIT: {'kind': 'always'},
        'pad_compound_restriction': condition(
            'rotor_material', definitions['rotor_material']['allowed_values']),
        'rotor_floating': {'kind': 'always'},
        'tool_size_mm': condition('rotor_mount_type',
                                  definitions['rotor_mount_type']['allowed_values']),
    }, required={
        NOMINAL: deepcopy(NEVER), WEAR_LIMIT: deepcopy(NEVER),
        'pad_compound_restriction': deepcopy(NEVER),
        'rotor_floating': deepcopy(NEVER),
        'tool_size_mm': deepcopy(NEVER),
    })
    template['form_contract']['helpers'].update({
        NOMINAL: (
            'Espesor de un rotor nuevo, según su fabricante. El límite de '
            'desgaste es otra celda y no puede ser mayor que éste.'),
        WEAR_LIMIT: (
            'Espesor al que ESTE fabricante da por terminado el rotor. Varía '
            'entre marcas y no vale para otra; sin su fuente no es un límite, '
            'es un rumor.'),
        'pad_compound_restriction': (
            'Lo que el fabricante restringe para ESTE rotor. No autoriza ni '
            'prohíbe un modelo concreto de pastilla, y no vale para otro rotor '
            'de la misma marca.'),
    })


# Cells that changed owner, and what the successor puts in their place. A
# scalar that a row now answers is rewritten into that row; nothing is dropped
# silently and no expectation is softened to make a test pass.
def _translate(inherited):
    out = []
    for old in inherited:
        new = deepcopy(old)
        values = dict(old['values'])
        blocking = [dict(b) for b in old.get('expected_blocking', [])]
        notes = []

        for table_key in (CONNECTIONS,):
            block = values.pop(table_key, None)
            if block is None:
                continue
            notes.append(
                'la tabla compartida de conexiones se retira aquí: su '
                'identificador de circuito era texto libre que en un cáliper no '
                'resolvía ningún padre. En un conjunto la conexión nombra su '
                'configuración y el motor la resuelve; en una pieza suelta el '
                'puerto es de la pieza y no finge tener padre.')
            target = (CIRCUIT_LINKS if old['template'] in (HYDRAULIC, RIM)
                      else PIECE_PORTS)
            moved = []
            for row in block['rows']:
                cells = dict(row['values'])
                if target is CIRCUIT_LINKS:
                    cells['configuration_row_id'] = cells.pop('circuit_id', '')
                    cells.setdefault('source_scope', 'Apartado sintético')
                else:
                    cells = {'port_id': cells.get('component_model', 'p1'),
                             'end_role': cells.get('end_role', 'Entrada'),
                             'fitting_model': cells.get('fitting_model'),
                             'source_scope': 'Apartado sintético',
                             'source_url': cells.get('source_url', SYNTHETIC)}
                    cells = {k: v for k, v in cells.items() if v is not None}
                moved.append({**row, 'values': cells})
            values[target] = {**block, 'rows': moved}
            for issue in blocking:
                if issue['field'] == CONNECTIONS:
                    issue['field'] = target

        hose = values.pop('hose_system_code', None)
        if hose is not None:
            notes.append(
                'el código de sistema de latiguillo era un escalar junto a una '
                'tabla de conexiones que ya lo dice con su modelo y su fuente; '
                'la afirmación pasa a la tabla, que se admite bajo la misma '
                'declaración de conexión externa.')
            for issue in blocking:
                if issue['field'] == 'hose_system_code':
                    issue['field'] = PIECE_PORTS
            values[PIECE_PORTS] = rows({
                'port_id': hose, 'end_role': 'Entrada',
                'connection_spec': hose,
                'source_scope': 'Apartado sintético', 'source_url': SYNTHETIC})

        nominal = values.pop('caliper_rotor_nominal_thickness_mm', None)
        if nominal is not None:
            notes.append(
                'el espesor admitido deja de ser una cifra suelta del producto '
                'y pasa a la receta de rotor, junto al montaje y la posición '
                'que lo admiten y con la fuente de esa misma fila. La '
                'expectativa se conserva: en un cáliper de llanta no hay '
                'receta que llenar, así que sigue siendo un rechazo.')
            for issue in blocking:
                if issue['field'] == 'caliper_rotor_nominal_thickness_mm':
                    issue['field'] = RECIPE
            values[RECIPE] = rows({
                'position': FRONT, 'rotor_diameter_mm': '160',
                'frame_mount': 'Post Mount', 'adapter_required': False,
                'accepted_rotor_thickness_mm': nominal,
                'source_url': SYNTHETIC})

        low = values.pop('reach_min_mm', None)
        high = values.pop('reach_max_mm', None)
        if low is not None or high is not None:
            notes.append(
                'el reach deja de ser un par de escalares del producto y pasa '
                'a la fila del montaje que lo alcanza. El orden se sigue '
                'exigiendo, ahora como par ordenado de esa fila, así que un '
                'rango invertido sigue bloqueando: cambia el código, de '
                'range_order sobre dos escalares a row_shape sobre la tabla.')
            row = {'position': FRONT, 'mount_spec': 'Postes cantilever',
                   'brake_model': 'Modelo sintético', 'source_url': SYNTHETIC}
            if low is not None:
                row['reach_min_mm'] = low
            if high is not None:
                row['reach_max_mm'] = high
            values[FITMENTS] = rows(row)
            if any(b['code'] == 'range_order' for b in blocking):
                blocking = [{'code': 'row_shape', 'field': FITMENTS}]

        for key in ('reach_adjust',):
            if old['template'] == CALIPER and key in values:
                values.pop(key)
                notes.append(
                    'reach_adjust describe la distancia de una maneta al '
                    'manillar; un cáliper no la tiene, así que su uso se '
                    'retira aquí y el escenario deja de declararla.')

        new['values'] = values
        if old.get('expected_blocking'):
            new['expected_blocking'] = blocking
        if notes:
            new['successor_translation'] = ' '.join(notes)
        out.append(new)
    return out


def _cases():
    recipe = lambda **kw: dict({'position': FRONT, 'rotor_diameter_mm': '160',
                                'frame_mount': 'Post Mount',
                                'adapter_required': False,
                                'source_url': SYNTHETIC}, **kw)
    fitment = lambda **kw: dict({'position': FRONT,
                                 'mount_spec': 'Postes cantilever',
                                 'brake_model': 'Modelo sintético',
                                 'source_url': SYNTHETIC}, **kw)
    approval = lambda **kw: dict({'system_brand': 'Marca sintética',
                                  'system_model': 'Modelo sintético',
                                  'fluid_class': 'Aceite Mineral',
                                  'source_url': SYNTHETIC}, **kw)
    caliper_model = lambda **kw: dict({'brand': 'Marca sintética',
                                       'model': 'Modelo sintético',
                                       'source_url': SYNTHETIC}, **kw)
    disc = {'braking_surface': DISC, 'brake_actuation': HYDRAULIC_ACT}
    return [
        # --- the piece's actuation, and the conversion outside it ------------
        case('bkx_hybrid_caliper_names_its_converter', CALIPER,
             {'braking_surface': DISC, 'brake_actuation': HYBRID,
              CONVERTER: 'Convertidor sintético'}),
        case('bkx_a_hydraulic_caliper_has_no_external_converter', CALIPER,
             {**disc, CONVERTER: 'Convertidor sintético'},
             blocking=[('field_applicability', CONVERTER)]),
        case('bkx_a_cable_caliper_has_no_external_converter', CALIPER,
             {'braking_surface': DISC, 'brake_actuation': CABLE,
              CONVERTER: 'Convertidor sintético'},
             blocking=[('field_applicability', CONVERTER)]),

        # --- one fact, one owner: the fluid lives in its approval row --------
        case('bkx_fluid_is_declared_with_its_system_and_source', CALIPER,
             {**disc, APPROVALS: rows(approval())}),
        case('bkx_two_fluids_are_two_approvals', CALIPER,
             {**disc, APPROVALS: rows(approval(),
                                      approval(fluid_class='DOT 4'))}),
        case('bkx_the_same_approval_twice_blocks', CALIPER,
             {**disc, APPROVALS: rows(approval(),
                                      approval(fluid_product='Otro'))},
             blocking=[('row_shape', APPROVALS)]),

        # --- what a caliper accepts belongs to its port and position --------
        case('bkx_accepted_thickness_lives_in_its_recipe', CALIPER,
             {**disc, RECIPE: rows(recipe(accepted_rotor_thickness_mm='1.8'))}),
        case('bkx_front_and_rear_keep_their_own_recipe', CALIPER,
             {**disc, RECIPE: rows(recipe(position=FRONT),
                                   recipe(position=REAR,
                                          rotor_diameter_mm='180'))}),
        case('bkx_the_same_recipe_twice_blocks', CALIPER,
             {**disc, RECIPE: rows(recipe(), recipe(adapter_required=True))},
             blocking=[('row_shape', RECIPE)]),
        case('bkx_a_rim_caliper_has_no_rotor_recipe', CALIPER,
             {'braking_surface': RIM_SURFACE, 'brake_actuation': CABLE,
              RECIPE: rows(recipe())},
             blocking=[('field_applicability', RECIPE)]),
        case('bkx_a_rim_caliper_has_no_piston_count', CALIPER,
             {'braking_surface': RIM_SURFACE, 'brake_actuation': CABLE,
              'piston_count_value': '2'},
             blocking=[('field_applicability', 'piston_count_value')]),

        # --- a lever delivers a pull; a caliper requires one -----------------
        case('bkx_lever_pull_and_caliper_pull_are_two_cells', LEVER,
             {'brake_actuation': CABLE,
              'lever_cable_pull': 'Tiro largo (V-brake / disco mecánico tiro largo)'}),
        case('bkx_a_hydraulic_lever_delivers_no_cable_pull', LEVER,
             {'brake_actuation': HYDRAULIC_ACT,
              'lever_cable_pull': 'Tiro corto (ruta / cantilever / caliper)'},
             blocking=[('field_applicability', 'lever_cable_pull')]),
        case('bkx_a_hydraulic_caliper_requires_no_cable_pull', CALIPER,
             {**disc, 'cable_pull_required':
              'Tiro corto (ruta / cantilever / caliper)'},
             blocking=[('field_applicability', 'cable_pull_required')]),

        # --- pad: the class, and the manufacturer's word for it -------------
        # An undeclared class leaves the commercial name PENDING, not refused:
        # the source may still publish it. What is refused is a disc compound on
        # a rim pad, which the surface decides outright.
        case('bkx_an_undeclared_compound_leaves_its_name_pending', PAD,
             {'braking_surface': DISC, 'brake_pad_oem_compound': 'Resina'},
             pending=[('prerequisite', 'brake_pad_oem_compound')]),
        case('bkx_a_declared_compound_keeps_its_commercial_name', PAD,
             {'braking_surface': DISC, 'compound_type': 'Orgánico',
              'brake_pad_oem_compound': 'Resina J04C'}),
        case('bkx_a_rim_pad_has_no_disc_compound', PAD,
             {'braking_surface': RIM_SURFACE, 'compound_type': 'Orgánico'},
             blocking=[('field_applicability', 'compound_type')]),
        case('bkx_the_same_caliper_claimed_twice_blocks', PAD,
             {'braking_surface': DISC,
              PAD_CALIPERS: rows(caliper_model(),
                                 caliper_model(conditions='Otra cosa'))},
             blocking=[('row_shape', PAD_CALIPERS)]),
        case('bkx_two_calipers_are_two_claims', PAD,
             {'braking_surface': DISC,
              PAD_CALIPERS: rows(caliper_model(),
                                 caliper_model(model='Otro modelo'))}),

        # --- rim brake: reach belongs to the mount --------------------------
        case('bkx_reach_belongs_to_its_mount', RIM,
             {'brake_actuation': CABLE, 'rim_brake_style': 'Cantilever',
              FITMENTS: rows(fitment(reach_min_mm='39', reach_max_mm='49'))}),
        case('bkx_an_inverted_reach_blocks', RIM,
             {'brake_actuation': CABLE, 'rim_brake_style': 'Cantilever',
              FITMENTS: rows(fitment(reach_min_mm='49', reach_max_mm='39'))},
             blocking=[('row_shape', FITMENTS)]),
        case('bkx_two_mounts_keep_their_own_reach', RIM,
             {'brake_actuation': CABLE, 'rim_brake_style': 'Cantilever',
              FITMENTS: rows(fitment(reach_min_mm='39', reach_max_mm='49'),
                             fitment(mount_spec='Perno central',
                                     reach_min_mm='47', reach_max_mm='57'))}),
        case('bkx_the_same_mount_twice_blocks', RIM,
             {'brake_actuation': CABLE, 'rim_brake_style': 'Cantilever',
              FITMENTS: rows(fitment(reach_min_mm='39'),
                             fitment(reach_min_mm='41'))},
             blocking=[('row_shape', FITMENTS)]),

        # --- rotor: three figures, and only two of them are ordered ---------
        case('bkx_a_rotor_states_nominal_and_wear_limit', ROTOR,
             {NOMINAL: '1.8', WEAR_LIMIT: '1.5'}),
        case('bkx_a_wear_limit_above_the_nominal_blocks', ROTOR,
             {NOMINAL: '1.5', WEAR_LIMIT: '1.8'},
             blocking=[('range_order', WEAR_LIMIT),
                       ('range_order', NOMINAL)]),
        case('bkx_equal_nominal_and_limit_are_admissible', ROTOR,
             {NOMINAL: '1.8', WEAR_LIMIT: '1.8'}),
        # A worn rotor measures below its limit. That is the state Sheldon
        # describes, not an impossible nominal, so nothing may reject it.
        case('bkx_a_worn_rotor_measures_below_its_limit', ROTOR,
             {NOMINAL: '1.8', WEAR_LIMIT: '1.5', MEASURED: '1.4',
              METHOD: 'Micrómetro sobre la pista, fuera del hueco'}),
        case('bkx_a_measurement_without_its_method_is_pending', ROTOR,
             {NOMINAL: '1.8', MEASURED: '1.4', 'spec_evidence_source': 'Ficha'},
             pending=[('prerequisite', MEASURED)]),
        case('bkx_two_makers_two_limits_for_the_same_nominal', ROTOR,
             {NOMINAL: '1.8', WEAR_LIMIT: '1.52',
              'spec_evidence_source': 'Ficha del fabricante'}),
        # The evidence source is filled on purpose: these fields already carry a
        # prerequisite on it, and leaving it out would let that prerequisite
        # satisfy the assertion while the gate under test did nothing.
        case('bkx_a_rotor_without_its_material_leaves_the_restriction_pending',
             ROTOR,
             {'rotor_thickness_mm': '1.8', 'spec_evidence_source': 'Ficha',
              'pad_compound_restriction': 'Sólo resina'},
             pending=[('prerequisite', 'pad_compound_restriction')]),
        case('bkx_a_rotor_with_its_material_may_restrict', ROTOR,
             {'rotor_material': 'Acero Inoxidable',
              'pad_compound_restriction': 'Sólo resina'}),
        case('bkx_a_rotor_without_its_mount_leaves_the_tool_pending', ROTOR,
             {'rotor_thickness_mm': '1.8', 'spec_evidence_source': 'Ficha',
              'tool_size_mm': 'T25'},
             pending=[('prerequisite', 'tool_size_mm')]),
        case('bkx_a_rotor_with_its_mount_declares_its_tool', ROTOR,
             {'rotor_mount_type': 'Centerlock', 'spec_evidence_source': 'Ficha',
              'tool_size_mm': 'T25'}),

        # --- where the conversion happens, read from TRP's own words --------
        # An open hydraulic caliper that is plug-and-play with cable levers
        # converts inside itself. There is no external device to name, and the
        # page does not publish its fluid, so the fluid stays absent.
        case('bkx_a_hybrid_caliper_may_convert_inside_itself', CALIPER,
             {'braking_surface': DISC, 'brake_actuation': HYBRID,
              CONVERSION: IN_PIECE}),
        case('bkx_a_conversion_inside_names_no_external_device', CALIPER,
             {'braking_surface': DISC, 'brake_actuation': HYBRID,
              CONVERSION: IN_PIECE, CONVERTER: 'Convertidor sintético'},
             blocking=[('field_applicability', CONVERTER)]),
        case('bkx_a_conversion_in_a_device_names_it', CALIPER,
             {'braking_surface': DISC, 'brake_actuation': HYBRID,
              CONVERSION: IN_DEVICE, CONVERTER: 'Convertidor sintético'}),
        case('bkx_a_hydraulic_caliper_declares_no_conversion', CALIPER,
             {**disc, CONVERSION: IN_PIECE},
             blocking=[('field_applicability', CONVERSION)]),

        # --- the piece owns its ports; the assembly owns its circuits --------
        case('bkx_a_caliper_owns_its_ports', CALIPER,
             {**disc, 'brake_external_hose_connection': True,
              PIECE_PORTS: rows(
                  {'port_id': 'entrada', 'end_role': 'Entrada',
                   'fitting_model': 'Oliva sintética',
                   'source_scope': 'A', 'source_url': SYNTHETIC},
                  {'port_id': 'purga', 'end_role': 'Purgador',
                   'source_scope': 'A', 'source_url': SYNTHETIC})}),
        case('bkx_the_same_port_twice_blocks', CALIPER,
             {**disc, 'brake_external_hose_connection': True,
              PIECE_PORTS: rows(
                  {'port_id': 'entrada', 'end_role': 'Entrada',
                   'source_scope': 'A', 'source_url': SYNTHETIC},
                  {'port_id': 'entrada', 'end_role': 'Salida',
                   'source_scope': 'Otro', 'source_url': SYNTHETIC})},
             blocking=[('row_shape', PIECE_PORTS)]),
        case('bkx_a_caliper_without_an_outside_end_has_no_ports', CALIPER,
             {**disc, 'brake_external_hose_connection': False,
              PIECE_PORTS: rows({'port_id': 'entrada', 'end_role': 'Entrada',
                                 'source_scope': 'A', 'source_url': SYNTHETIC})},
             blocking=[('field_applicability', PIECE_PORTS)]),
        case('bkx_a_connection_names_a_configuration_that_exists', HYDRAULIC,
             {CONFIGURATIONS: rows(
                 {'circuit_id': 'c1', 'position': FRONT, 'source_url': SYNTHETIC}),
              CIRCUIT_LINKS: rows(
                 {'configuration_row_id': 'r1', 'component_role': 'Cáliper',
                  'end_role': 'Entrada', 'component_brand': 'B',
                  'component_model': 'M', 'source_scope': 'A',
                  'source_url': SYNTHETIC})}),
        case('bkx_a_connection_cannot_name_an_absent_configuration', HYDRAULIC,
             {CONFIGURATIONS: rows(
                 {'circuit_id': 'c1', 'position': FRONT, 'source_url': SYNTHETIC}),
              CIRCUIT_LINKS: rows(
                 {'configuration_row_id': 'r9', 'component_role': 'Cáliper',
                  'end_role': 'Entrada', 'component_brand': 'B',
                  'component_model': 'M', 'source_scope': 'A',
                  'source_url': SYNTHETIC})},
             blocking=[('row_reference_unresolved', CIRCUIT_LINKS)]),
        case('bkx_the_same_end_of_one_circuit_twice_blocks', HYDRAULIC,
             {CONFIGURATIONS: rows(
                 {'circuit_id': 'c1', 'position': FRONT, 'source_url': SYNTHETIC}),
              CIRCUIT_LINKS: rows(
                 {'configuration_row_id': 'r1', 'component_role': 'Cáliper',
                  'end_role': 'Entrada', 'component_brand': 'B',
                  'component_model': 'M', 'source_scope': 'A',
                  'source_url': SYNTHETIC},
                 {'configuration_row_id': 'r1', 'component_role': 'Cáliper',
                  'end_role': 'Entrada', 'component_brand': 'B',
                  'component_model': 'Otro', 'source_scope': 'A',
                  'source_url': SYNTHETIC})},
             blocking=[('row_shape', CIRCUIT_LINKS)]),

        # --- an unanswered selector leaves the ficha pending ------------------
        case('bkx_a_caliper_without_its_surface_is_pending', CALIPER,
             {'spec_evidence_source': 'Ficha'},
             pending=[('required_missing', 'braking_surface')]),
        case('bkx_a_pad_without_its_surface_is_pending', PAD,
             {'spec_evidence_source': 'Ficha'},
             pending=[('required_missing', 'braking_surface')]),
        case('bkx_a_rim_brake_without_its_style_is_pending', RIM,
             {'spec_evidence_source': 'Ficha'},
             pending=[('required_missing', 'rim_brake_style')]),

        # --- a complete brake: box contents versus what it admits -----------
        case('bkx_included_rotor_is_not_the_admitted_one', HYDRAULIC,
             {'rotor_included_diameter_mm': '160',
              RECIPE: rows(recipe(rotor_diameter_mm='180'),
                           recipe(rotor_diameter_mm='160'))}),
        case('bkx_the_same_configuration_twice_blocks', HYDRAULIC,
             {CONFIGURATIONS: rows(
                 {'circuit_id': 'c1', 'position': FRONT,
                  'hose_length_mm': '900', 'source_url': SYNTHETIC},
                 {'circuit_id': 'c1', 'position': FRONT,
                  'hose_length_mm': '1400', 'source_url': SYNTHETIC})},
             blocking=[('row_shape', CONFIGURATIONS)]),
        case('bkx_front_and_rear_are_two_configurations', HYDRAULIC,
             {CONFIGURATIONS: rows(
                 {'circuit_id': 'c1', 'position': FRONT,
                  'hose_length_mm': '900', 'source_url': SYNTHETIC},
                 {'circuit_id': 'c2', 'position': REAR,
                  'hose_length_mm': '1400', 'source_url': SYNTHETIC})}),
        case('bkx_a_mechanical_set_may_omit_its_levers', MECHANICAL,
             {'cable_pull_required':
              'Tiro largo (V-brake / disco mecánico tiro largo)'}),
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-brakes-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-brakes-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'live_shared': len(catalog['live_shared_definitions']),
                      'corrected_from_frozen': len(catalog['adopted_live_definitions']),
                      'renames_declined': len(catalog['renames_declined'])}))
