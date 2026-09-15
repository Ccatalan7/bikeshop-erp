#!/usr/bin/env python3
"""Source-to-candidate successor for the four rear-cog families.

cassette, freewheel, fixed_cog and cassette_spacer. No migration, no
production, no fill, no assignment change.

The four arrived with **no gate at all**: not one conditional field, not one row
condition, no coherence and no ordering, and not a single case. Everything was
answerable at once, so a ficha could hold eleven sprockets with a ten-row
sequence, a smallest cog larger than its largest, and a spline standard nothing
depended on.

The rule that orders the block is the one Park states plainly: the freewheel
«threads onto the hub», while «'Cassette' sprockets slide over these splines. A
lockring threads into the freehub and holds the sprockets, or cogs, in place.»
Two different attachments, so a thread standard and a body standard are never
the same cell and never a free crossing — which is why this successor removes
the four threaded and coaster seats that the frozen proposal offered inside a
*cassette's* accepted-body table.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, ROOT, write_json)
from compile_mobility_accessories_catalog import (
    add_field, condition, new_definition, rows)
from compile_mobility_accessories_catalog import case as _case
from compile_wheel_small_parts_catalog import ALWAYS, NEVER, column, retire
from compile_product_spec_catalog import validate_contract

CASSETTE, FREEWHEEL, FIXED, SPACER = (
    'cassette', 'freewheel', 'fixed_cog', 'cassette_spacer')
FAMILIES = (CASSETTE, FREEWHEEL, FIXED, SPACER)

PREIMAGE = ROOT / '.tmp/db/existing-37-candidate-preimage.json'
PREIMAGE_SHA = '0a21d85a1539c330e661e0c5c1aa2fde0bbf29ddad67a452a018ed767d08b2a6'

# Park Tool, Determining Cassette / Freewheel Type — opened and read. The shop
# test and the two attachments: «Spin the sprockets backwards. If the fittings
# spin with the cogs, it is a cassette system with a freehub.» And the extractor
# is not a free crossing either: «Shimano-style and Falcon freewheels have
# similar but distinct tool fittings.»
PARK_TYPE = ('https://www.parktool.com/en-us/blog/repair-help/'
             'determining-cassette-freewheel-type')
# Sheldon, Freewheel or Cassette? — opened and read. «The cassette Freehub
# incorporates the ratchet mechanism into the hub body».
SHELDON_FREE_K7 = 'https://www.sheldonbrown.com/free-k7.html'
# Sheldon, Shimano Cassettes & Freehubs — opened and read. The spacer belongs to
# the PAIR and not to the cassette: «Add a 4.5 mm spacer before installing a
# 7-speed cassette on an 8-, 9-, or 10-speed hub, and the included 1-mm spacer
# before installing a 10-speed cassettes on an 8- or 9- speed hub.» And
# acceptance is not symmetric: «7-speed hubs only accept 7-speed cassettes».
SHELDON_K7 = 'https://www.sheldonbrown.com/k7.html'
# Sheldon's glossary, Lockring — opened and read. «Fixed-gear hubs use a left
# (reverse) threaded lock ring to keep the sprocket from unscrewing when the
# cyclist resists the motion of the pedals.»
SHELDON_LOCKRING = 'https://www.sheldonbrown.com/gloss_l.html'
# Sheldon, Fixed Gear Conversions — opened and read, on the track hub's second
# thread: «This thread is a left (reverse) thread, and a special lockring screws
# onto it.»
SHELDON_FIXED = 'https://www.sheldonbrown.com/fixed-conversion.html'
# Shimano, ficha de producto CS-HG50-8, leída en el navegador (si.shimano.com y
# bike.shimano.com devuelven 403 al fetch, no es que falte documentación). Un
# solo modelo con siete configuraciones publicadas, cada una de ocho piñones y
# con el código de grupo del fabricante: «11-13-15-17-19-21-24-28T (bf)»,
# «11-13-15-17-20-23-26-30T (an)», «11-13-15-18-21-24-28-32T (aw)»,
# «11-13-15-18-21-24-28-34T (Ca)», «12-13-14-15-17-19-21-23T (U)»,
# «12-13-15-17-19-21-23-25T (W)», «13-14-15-17-19-21-23-26T (V)». La misma ficha
# nombra la estría: «HG spline M (10/9/8-speed, MTB 11-speed, 7-speed
# CS-HG400/HG210)».
SHIMANO_HG50 = ('https://bike.shimano.com/en-NA/products/components/'
                'pdp.P-CS-HG50-8.html')
# SRAM, «SRAM XD and XDR Driver Body Explained» — el caso OEM de una divergencia
# legítima: «The XDR interface is 1.85mm longer than XD and is designed for road
# hub applications» y «XDR driver bodies are compatible with all XD cassettes
# when the cassette is installed with a 1.85mm spacer behind it.» El sentido
# inverso no está enunciado en esa página; no se afirma.
SRAM_XD_XDR = ('https://www.sram.com/en/service/articles/'
               'sram-xd-and-xdr-driver-body-explained')
# SRAM, «What is the new XD SLIM driver body standard?» — leída de primera mano.
# El negativo dirigido y por modelo: «the standard XD XX DH cassette (XS-797)
# requires the standard XD driver body, and the XD SLIM version (XS-797S)
# requires the XD SLIM driver body. There is no cross compatibility between
# these two standards.» La misma página deja un enunciado explícitamente
# incierto que NO se promueve a regla: «most hubs that are compatible with HG
# SLIM are likely able to be compatible with the XD SLIM diver body. Please
# consult your hub manufacturer».
SRAM_XD_SLIM = ('https://support.sram.com/hc/en-us/articles/46508211430043-'
                'What-is-the-new-XD-SLIM-driver-body-standard-How-is-it-'
                'similar-to-the-HG-SLIM-standard')
# Park Tool, Cassette Removal and Installation — por qué la posición ordena la
# secuencia: «Freehub bodies and cassette stacks are designed so that there is
# only one possible orientation in which the cogs can be installed onto the
# freehub.»
PARK_CASSETTE = ('https://www.parktool.com/en-us/blog/repair-help/'
                 'cassette-removal-and-installation')
SYNTHETIC = 'https://example.invalid/synthetic'

SEQUENCE, BODIES = 'cog_sequence', 'freehub_bodies_accepted'
CONFIGS, CONFIG_REF = 'cog_configurations', 'configuration_row_id'
CONFIG_TEETH = 'cog_configuration_teeth'
COUNT, SPLINE = 'sprocket_count', 'cassette_spline_standard'
THREAD, REMOVER = 'freewheel_thread_standard', 'remover_tool_standard'
COG_THREAD, COG_LOCKRING = 'cog_thread_standard', 'cog_lockring_thread'
TARGET, THICKNESS = 'target_rear_drive_interface', 'spacer_thickness_mm'
SMALLEST, LARGEST = 'smallest_cog_teeth', 'largest_cog_teeth'
EVIDENCE = 'spec_evidence_source'

UNKNOWN = 'Desconocido / sin confirmar'
NO_SPACER, SPACER_NEEDED, SPACER_UNPUBLISHED = (
    'Sin separador', 'Separador requerido', 'No publicado')
COMPATIBLE, INCOMPATIBLE, CONDITIONED = (
    'Compatible declarado', 'Incompatible declarado', 'Condicionado')
OEM_TABLE, OEM_MANUAL, SYNTHETIC_SCOPE = (
    'Tabla de compatibilidad OEM', 'Manual OEM', 'Apartado sintético')
SCOPES = (OEM_TABLE, OEM_MANUAL, SYNTHETIC_SCOPE)

# A cassette goes on a splined body. The frozen vocabulary of accepted bodies
# also offered two threaded freewheel seats, the threaded fixed-cog seat and a
# coaster hub — the crossing Park's two attachments forbid, offered as a value.
# Removing them is the block's central correction, not a tidy-up.
CROSSINGS = ('Rueda libre roscada 1.37" x 24 tpi',
             'Rueda libre roscada M30 x 1 (BMX)',
             'Piñón fijo roscado 1.37" x 24 tpi + contratuerca 1.29" x 24 tpi izquierda',
             'Contrapedal')

# SRAM niega el cruce XD / XD SLIM por modelo. Si XD SLIM no es un valor propio,
# una ficha sólo puede decir «SRAM XD» y el cruce imposible queda indistinguible
# del legítimo. El valor entra en el dominio de la columna, y el escalar lo hereda.
XD_SLIM = 'SRAM XD SLIM'

LOCKRING_THREADS = ['1.29" x 24 tpi izquierda (inglés)', 'Otra rosca izquierda',
                    'Sin contratuerca (maza sin segunda rosca)', UNKNOWN]
COG_THREADS = ['1.37" x 24 tpi (ISO)', 'Otro', UNKNOWN]


def known(definitions, key):
    """The published domain minus the explicit «unknown» answer.

    A gate that reads a selector must not open merely because the operator
    admitted ignorance; declaring «unknown» has to leave the dependent field
    pending, which is exactly what an unsatisfied `allowed_when` produces.
    """
    values = [v for v in definitions[key]['allowed_values'] if v != UNKNOWN]
    if len(values) != len(definitions[key]['allowed_values']) - 1:
        raise ValueError(key + ': the unknown answer is not in the domain')
    return condition(key, values)


def gate(template, mapping, required=None):
    contract = template['form_contract']
    for key, rule in mapping.items():
        contract['allowed_when'][key] = deepcopy(rule)
        contract['required_when'][key] = deepcopy(
            (required or {}).get(key, rule))


def add_column(definitions, key, spec, *, after=None):
    schema = definitions[key]['validation_rules']['rows_schema']
    if any(c['key'] == spec['key'] for c in schema['columns']):
        raise ValueError(f"{key}: column already present: {spec['key']}")
    index = (len(schema['columns']) if after is None else
             next(i for i, c in enumerate(schema['columns'])
                  if c['key'] == after) + 1)
    schema['columns'].insert(index, spec)


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


def key_rows(definitions, table_key, columns):
    """A row key is built only from required columns, and never on a live one."""
    definition = definitions[table_key]
    if definition.get('origin') == 'existing':
        raise ValueError(table_key + ' is published: a row schema is not ours to key')
    schema = definition['validation_rules']['rows_schema']
    present = {c['key']: c for c in schema['columns']}
    for key in columns:
        if present[key].get('required') is not True:
            raise ValueError(f'{table_key}: {key} is optional and cannot key a row')
    schema['unique_by'] = [list(columns)]


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA),
                      (PREIMAGE, PREIMAGE_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen input drift: ' + path.name)
    base = json.loads(CATALOG.read_text())
    live = json.loads(PREIMAGE.read_text())
    live = live[0]['metadata'] if isinstance(live, list) else live
    published = {d['key']: d for d in live['existing_definitions']}
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
    fixtures['cases'] = [c for c in fixtures['cases'] if c['template'] in FAMILIES]

    # The live row is authoritative over the frozen proposal. One key these four
    # use says `new` there and is already published; two more carry option lists
    # the proposal had emptied, and emptying a live domain is refused by the
    # publisher, not merged — it would have failed the packet outright.
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

    # A rename is a product decision, not a side effect of reworking a contract.
    # Three of the four differ; the live word is what the shop already uses, and
    # the publisher refuses the change outright.
    renamed = {}
    for key, template in templates.items():
        actual = live_templates[key]
        if template.get('name') != actual['name']:
            renamed[key] = {'frozen_proposal': template.get('name'),
                            'live_preserved': actual['name']}
            template['name'] = actual['name']

    _sequence(definitions, templates)
    _cassette(definitions, templates)
    _freewheel(definitions, templates)
    _fixed_cog(definitions, templates)
    _spacer(definitions, templates)

    # A ficha is not complete because it skipped the question that opens the
    # others. Every field some gate reads is required, computed from the gates
    # themselves so a gate added later cannot forget its selector.
    for template in templates.values():
        contract = template['form_contract']
        selectors = {term['field']
                     for section in ('allowed_when', 'required_when')
                     for rule in contract.get(section, {}).values()
                     for clause in rule.get('rows', [])
                     for term in clause}
        for item in contract.get('row_coherence', {}).get('cardinalities', []):
            selectors.add(item['total_field'])
        for key in sorted(selectors):
            if contract['roles'].get(key) == 'legacy':
                continue
            contract['required_when'][key] = deepcopy(ALWAYS)

    _assert_attachments(definitions, templates)
    for template in templates.values():
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

    fixtures['cases'] = _cases(definitions)
    # Fuera de `cases` a propósito: el arnés corre todo lo que hay ahí y estos
    # casos hoy no pasan, porque la capacidad que los cierra no existe.
    fixtures['proposed_cases'] = _proposed_cases()
    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Rear cog families reviewed successor',
               'templates': [templates[f] for f in FAMILIES],
               'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA,
                                'preimage': PREIMAGE_SHA},
               'renames_declined': renamed,
               'live_shared_definitions': sorted(k for k in keys if k in published),
               'adopted_live_definitions': sorted(changed & keys),
               'removed_attachment_crossings': {BODIES: list(CROSSINGS)},
               'proposed_capabilities': _proposals(),
               # Los datos OEM investigados se conservan íntegros y **fuera de
               # todo campo productivo**: referencia del modelo, no hecho del SKU.
               'oem_variant_reference': oem_variant_reference(),
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(catalog['templates']),
                        'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in catalog['templates'])}
    return catalog, fixtures


def _assert_attachments(definitions, templates):
    """The two attachments never meet in one ficha.

    Park describes them as different mechanisms — a freewheel «threads onto the
    hub», a cassette slides over splines under a lockring — so a template that
    owns a thread standard must not also own a body/spline standard, and the
    other way round. Asserted here rather than trusted, because `used_by` is
    edited by hand and a single stray family name would reopen the crossing.
    """
    threads = {THREAD, COG_THREAD, COG_LOCKRING}
    bodies = {SPLINE, BODIES}
    for key, template in templates.items():
        present = {f['key'] for f in template['fields']}
        if present & threads and present & bodies:
            raise ValueError(f'{key} owns both attachments: '
                             f'{sorted(present & threads)} + {sorted(present & bodies)}')
    domain = set(definitions[BODIES]['validation_rules']['rows_schema'][
        'columns'][0]['allowed_values'])
    if domain & set(CROSSINGS):
        raise ValueError('A cassette body table still offers a threaded seat')


VARIANT = 'published_variant_label'


def _sequence(definitions, templates):
    """La ficha del SKU lleva la unidad y la variante resuelta. Nada más.

    Segunda corrección de root (2026-09-08): separar `cog_configurations` y
    `cog_configuration_teeth` en tablas propias **no cambia de dueño**. Seguían
    siendo campos del producto, así que cada SKU habría publicado como hechos
    suyos las siete variantes del modelo. El contrato canónico §4.1 separa las
    referencias OEM del inventario del tenant: las alternativas del modelo
    pertenecen al catálogo de referencias, y a la ficha llega **sólo la variante
    resuelta y su procedencia**.

    Las dos definiciones quedan retiradas del candidato. Los datos OEM
    investigados no se pierden: viajan en `oem_variant_reference` del catálogo,
    fuera de todo campo productivo, y sirven como fixtures de referencia para el
    motor agrupado.

    Esto no cierra la puerta a configuraciones de montaje realmente admitidas
    por el mismo SKU ni a conjuntos de varias piezas incluidas; ninguna de las
    dos existe en estas cuatro familias hoy.
    """
    definitions[VARIANT] = new_definition(
        VARIANT, 'Combinación publicada de esta unidad', 'text',
        (CASSETTE, FREEWHEEL))
    # El escalar recupera su significado. `min` sigue porque la gramática de
    # cardinalidad exige un dominio entero no negativo, no porque cuente otra cosa.
    definitions[COUNT]['validation_rules'] = {
        'positive': True, 'integer': True, 'min': '1'}
    definitions[COUNT]['label'] = 'Cantidad de coronas'

    for family in (CASSETTE, FREEWHEEL):
        template = templates[family]
        add_field(template, VARIANT, 'declaration', 'declaration',
                  helper='Qué combinación publicada del modelo es esta unidad, '
                         'por ejemplo «11-30T (an)». Las demás variantes del '
                         'modelo no son hechos de este SKU.')
        contract = template['form_contract']
        # La variante resuelta no se afirma sin decir de dónde salió.
        contract.setdefault('prerequisites', {})[VARIANT] = [EVIDENCE]
        contract['row_coherence'] = {
            'version': 2, 'links': [],
            'cardinalities': [{'id': 'declared_sprocket_occurrences',
                               'field': SEQUENCE, 'total_field': COUNT}]}
        # Una ficha que nombra un total debe los dientes que hay detrás. Sólo la
        # exigencia es condicional: una secuencia escrita antes del total sigue
        # siendo una observación real, así que `allowed_when` queda abierto y
        # ninguna fila entregada se vuelve un valor inaplicable.
        gate(template, {SEQUENCE: deepcopy(ALWAYS)},
             required={SEQUENCE: {'kind': 'when', 'rows': [[{
                 'field': COUNT, 'operator': 'gte',
                 'value_type': 'decimal', 'value': '1'}]]}})
        # Menor y mayor eran dos números independientes: 16-14 pasaba. Ambos
        # viven, llevan la unidad `T`, y el par sólo bloquea con los dos
        # presentes e invertidos, así que ninguna cifra publicada pierde
        # aplicabilidad.
        contract['scalar_ordered_pairs'] = [[SMALLEST, LARGEST]]


def _cassette(definitions, templates):
    """What accepts this cassette is a table with a key, a spacer branch and a
    body domain that no longer contains a freewheel.

    Three defects lived in one field. The accepted-body vocabulary offered four
    seats a cassette cannot use — two threaded freewheel seats, the threaded
    fixed-cog seat and a coaster hub — which is the crossing Park's two
    attachments rule out. The spacer thickness was `required`, so a pairing that
    needs none forced inventing a figure, and `0 mm` is a measured zero, not the
    absence of a part: Sheldon's own figures are 4.5 mm and 1 mm for specific
    pairings and nothing at all for the rest. And nothing keyed the rows, so two
    sources could answer the same body twice with different numbers.
    """
    template = templates[CASSETTE]
    schema = definitions[BODIES]['validation_rules']['rows_schema']
    interface = schema['columns'][0]
    interface['allowed_values'] = [v for v in interface['allowed_values']
                                   if v not in CROSSINGS]
    if len(interface['allowed_values']) != 10:
        raise ValueError('The accepted-body domain did not lose exactly four seats')
    # SRAM niega el cruce entre XD y XD SLIM por modelo (XS-797 / XS-797S). Sin
    # un valor propio, una ficha sólo puede escribir «SRAM XD» y el cruce que la
    # fuente prohíbe queda indistinguible del legítimo.
    interface['allowed_values'].insert(
        interface['allowed_values'].index('SRAM XDR'), XD_SLIM)

    # Dos vocabularios para la misma cosa se separan solos. El escalar decía
    # «Shimano HG (M)» y la columna «Shimano HG spline M (…)»: nombres distintos
    # para la misma estría, imposibles de comparar entre sí. El escalar toma el
    # dominio de la columna, y queda atado a ella por construcción.
    definitions[SPLINE]['allowed_values'] = list(interface['allowed_values'])
    definitions[SPLINE]['label'] = 'Interfaz del cassette (estría propia)'

    spacer = next(c for c in schema['columns'] if c['key'] == 'spacer_mm')
    del spacer['required']
    add_column(definitions, BODIES,
               column('spacer_requirement', 'Separador exigido por el par',
                      'token', required=True,
                      options=(NO_SPACER, SPACER_NEEDED, SPACER_UNPUBLISHED)),
               after='rear_drive_interface')
    add_column(definitions, BODIES,
               column('status', 'Resultado declarado', 'token', required=True,
                      options=(COMPATIBLE, INCOMPATIBLE, CONDITIONED, UNKNOWN)),
               after='spacer_mm')
    add_column(definitions, BODIES,
               column('conditions', 'Condición declarada por la fuente'),
               after='status')
    add_column(definitions, BODIES,
               column('source_scope', 'Alcance de la fuente', 'token',
                      required=True, options=SCOPES),
               after='conditions')
    key_rows(definitions, BODIES, ('rear_drive_interface', 'source_scope'))

    # The figure exists only where a separator does. And a condition is never
    # forbidden on a plain verdict — a source may qualify a compatibility it
    # still calls compatible — it is only owed when the verdict is conditional.
    row_gate(template, BODIES,
             {'spacer_mm': condition('spacer_requirement', SPACER_NEEDED)})
    row_gate(template, BODIES, {'conditions': deepcopy(ALWAYS)},
             required={'conditions': condition('status', CONDITIONED)})

    # Which bodies accept it cannot be answered before the cassette's own
    # interface is on the record, and admitting ignorance of that interface
    # leaves the table pending rather than opening it.
    gate(template, {BODIES: known(definitions, SPLINE),
                    'shift_technology': known(definitions, SPLINE)},
         required={'shift_technology': deepcopy(NEVER)})
    # `lockring_included` keeps no gate on purpose: every cassette is held by
    # one, so whether the box carries it is a packaging fact that is always
    # answerable, and a boolean has no «unknown» branch to fall into.


def _freewheel(definitions, templates):
    """The extractor interface hangs off the thread, and cannot be answered
    before it.

    Park is explicit that the fittings are distinct and not interchangeable —
    «Shimano-style and Falcon freewheels have similar but distinct tool
    fittings» — so the tool is a consequence of the standard, not a free
    parallel claim. A freewheel owns a thread and never a spline or a body.
    """
    gate(templates[FREEWHEEL], {REMOVER: known(definitions, THREAD)})


def _fixed_cog(definitions, templates):
    """Two threads, two cells, and one of them turns the other way.

    The frozen domain fused both into a single string — «1.37" x 24 tpi (ISO) +
    contratuerca 1.29" x 24 izquierda» — which hard-codes one lockring standard
    onto one cog thread and cannot express a hub whose second thread is absent.
    Sheldon's glossary keeps them apart: «Fixed-gear hubs use a left (reverse)
    threaded lock ring to keep the sprocket from unscrewing», and on the track
    hub's outboard thread, «This thread is a left (reverse) thread, and a
    special lockring screws onto it.» A cog screwed onto a freewheel-threaded
    hub with no second thread is a real configuration, so «sin contratuerca» is
    a value and not a blank.
    """
    template = templates[FIXED]
    definitions[COG_THREAD]['label'] = 'Rosca del piñón (lado motriz)'
    definitions[COG_THREAD]['allowed_values'] = list(COG_THREADS)
    definitions[COG_LOCKRING] = new_definition(
        COG_LOCKRING, 'Rosca de la contratuerca (izquierda)', 'single_select',
        (FIXED,), options=LOCKRING_THREADS)
    add_field(template, COG_LOCKRING, 'measurement', 'compatibility',
              allowed=deepcopy(NEVER), required=deepcopy(NEVER),
              helper='La contratuerca de un buje de pista lleva rosca '
                     'izquierda; una maza sólo roscada para rueda libre no '
                     'tiene esa segunda rosca.')
    gate(template, {COG_LOCKRING: known(definitions, COG_THREAD)})


def _spacer(definitions, templates):
    """A thickness means nothing until it says which body it shims.

    Sheldon's figures are per pairing — 4.5 mm for a 7-speed cassette on an
    8/9/10-speed hub, 1 mm for a 10-speed on an 8/9 — so the target interface
    is the question this ficha exists to answer, and it arrived optional. The
    thickness stays *allowed* unconditionally on purpose: it is live and
    already carries published figures, and no contract change here may turn one
    of those into an inapplicable value. Only the demand for it is conditional.
    """
    gate(templates[SPACER], {THICKNESS: deepcopy(ALWAYS)},
         required={THICKNESS: known(definitions, TARGET)})


HG_M = 'Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según filas C-731; LINKGLIDE según C-649)'
SPLINE_HG = HG_M
SPLINE_XD = 'SRAM XD'
BODY_XD, BODY_XDR = 'SRAM XD', 'SRAM XDR'
ISO_THREAD = '1.37" x 24 tpi (ISO)'
ENGLISH_LOCKRING = '1.29" x 24 tpi izquierda (inglés)'
NO_LOCKRING = 'Sin contratuerca (maza sin segunda rosca)'

# Las tres combinaciones que se usan en las fixtures salen textuales de la ficha
# de Shimano del CS-HG50-8; no son secuencias plausibles inventadas.
AN = (11, 13, 15, 17, 20, 23, 26, 30)   # «11-13-15-17-20-23-26-30T (an)»
AW = (11, 13, 15, 18, 21, 24, 28, 32)   # «11-13-15-18-21-24-28-32T (aw)»
BF = (11, 13, 15, 17, 19, 21, 24, 28)   # «11-13-15-17-19-21-24-28T (bf)»


# Las siete combinaciones publicadas del CS-HG50-8, textuales de la ficha de
# Shimano. **No son hechos de ningún SKU**: viajan como referencia OEM (§4.1) y
# como fixtures de referencia del motor agrupado.
CS_HG50_8 = (('11-28T', 'bf', (11, 13, 15, 17, 19, 21, 24, 28)),
             ('11-30T', 'an', (11, 13, 15, 17, 20, 23, 26, 30)),
             ('11-32T', 'aw', (11, 13, 15, 18, 21, 24, 28, 32)),
             ('11-34T', 'Ca', (11, 13, 15, 18, 21, 24, 28, 34)),
             ('12-23T', 'U', (12, 13, 14, 15, 17, 19, 21, 23)),
             ('12-25T', 'W', (12, 13, 15, 17, 19, 21, 23, 25)),
             ('13-26T', 'V', (13, 14, 15, 17, 19, 21, 23, 26)))
AN = dict((code, cogs) for _, code, cogs in CS_HG50_8)['an']
AW = dict((code, cogs) for _, code, cogs in CS_HG50_8)['aw']


def oem_variant_reference():
    """Referencia OEM del modelo, fuera de todo campo productivo.

    Se conserva íntegra —combinación, código de grupo, piñones y secuencia— para
    que la investigación no se pierda al corregir el dueño, y para que el motor
    agrupado pueda demostrarse con datos reales sin publicarlos como hechos de
    un SKU.
    """
    return {'schema_version': 1, 'kind': 'oem_model_variant_catalogue',
            'is_product_fact': False,
            'ownership': 'referencia OEM del modelo (contrato canónico §4.1); '
                         'no es inventario del tenant ni hecho de un SKU',
            'model': 'Shimano CS-HG50-8', 'source_url': SHIMANO_HG50,
            'speeds': 8,
            'variants': [{'configuration_label': label,
                          'configuration_code': code,
                          'sprocket_count_declared': len(cogs),
                          'teeth': [{'position': i + 1, 'teeth': t}
                                    for i, t in enumerate(cogs)]}
                         for label, code, cogs in CS_HG50_8]}


def teeth(*cogs):
    """La secuencia de **esta unidad**: posición y dientes, nada más."""
    return rows(*[{'position': str(i + 1), 'teeth': str(t)}
                  for i, t in enumerate(cogs)])


def case(id_, family, values, *, blocking=(), pending=(), forbidden=(),
         sources=()):
    """El constructor compartido más la afirmación de que una compuerta no emitió nada.

    `forbidden_issue_fields` es lo que distingue una compuerta que abre de una
    que simplemente no bloquea: sin eso un caso «positivo» pasa igual cuando el
    campo quedó callado pendiente, que es como se colaron dos afirmaciones
    vacías en bloques anteriores de este proyecto.
    """
    result = _case(id_, family, values, blocking=blocking, pending=pending,
                   sources=sources)
    if forbidden:
        result['forbidden_issue_fields'] = list(forbidden)
    return result


def body(interface=HG_M, requirement=NO_SPACER, status=COMPATIBLE,
         scope=SYNTHETIC_SCOPE, **extra):
    cells = {'rear_drive_interface': interface, 'spacer_requirement': requirement,
             'status': status, 'source_scope': scope, 'source_url': SYNTHETIC}
    cells.update({k: v for k, v in extra.items() if v is not None})
    return cells


def cassette(extra=None):
    """Una unidad de ocho velocidades: ocho coronas y su secuencia.

    Recibe un diccionario y no palabras clave: las claves de este contrato son
    constantes (`SEQUENCE` vale `'cog_sequence'`), y un `SEQUENCE=` en la
    llamada nombraría la palabra «SEQUENCE», no su valor. Un `None` retira el
    campo, que es como se escribe «esta ficha no lo trae».
    """
    values = {COUNT: '8', SEQUENCE: teeth(*AN), SPLINE: SPLINE_HG,
              BODIES: rows(body())}
    values.update(extra or {})
    return {k: v for k, v in values.items() if v is not None}


def _cases(definitions):
    """Positivo, negativo y desconocido por cada compuerta que agrega este sucesor.

    `required_missing`, `prerequisite`, `row_required_missing`,
    `row_prerequisite`, `row_incomplete`, `row_reference_pending` y
    `row_cardinality_pending` no bloquean en el motor, así que una afirmación
    sobre ellos va en el subconjunto de incidencias; sólo `field_applicability`,
    `row_field_applicability`, `row_shape`, `row_reference_unresolved`,
    `row_cardinality_conflict` y `range_order` pueden aparecer como bloqueantes.
    """
    return [
        # --- las coronas de ESTA unidad contra su secuencia ------------------
        case('rcx_a_cassette_sequence_matches_its_declared_total', CASSETTE,
             cassette(), forbidden=[SEQUENCE], sources=[SHIMANO_HG50]),
        case('rcx_more_cogs_than_the_declared_total_blocks', CASSETTE,
             cassette({SEQUENCE: teeth(*(AN + (34,)))}),
             blocking=[('row_cardinality_conflict', SEQUENCE)]),
        case('rcx_fewer_cogs_than_the_total_stay_pending', CASSETTE,
             cassette({SEQUENCE: teeth(*AN[:-1])}),
             pending=[('row_cardinality_pending', SEQUENCE)]),
        case('rcx_a_total_without_its_sequence_is_pending', CASSETTE,
             cassette({SEQUENCE: None}),
             pending=[('row_cardinality_pending', SEQUENCE),
                      ('required_missing', SEQUENCE)]),
        case('rcx_a_sequence_without_its_total_is_pending', CASSETTE,
             cassette({COUNT: None}),
             pending=[('row_cardinality_pending', SEQUENCE),
                      ('required_missing', COUNT)]),
        case('rcx_a_freewheel_counts_its_own_cogs_too', FREEWHEEL,
             {COUNT: '5', THREAD: ISO_THREAD, REMOVER: 'Shimano 12 estrías',
              EVIDENCE: 'Ficha sintética',
              SEQUENCE: teeth(14, 16, 18, 21, 24, 28)},
             blocking=[('row_cardinality_conflict', SEQUENCE)],
             sources=[PARK_TYPE]),
        case('rcx_the_same_cog_position_twice_blocks', CASSETTE,
             cassette({COUNT: '2', SEQUENCE: rows(
                 {'position': '1', 'teeth': '11'},
                 {'position': '1', 'teeth': '13'})}),
             blocking=[('row_shape', SEQUENCE)], sources=[PARK_CASSETTE]),

        # --- la variante resuelta llega a la ficha; el catálogo no ----------
        # Las otras seis combinaciones del CS-HG50-8 no son hechos de esta
        # unidad. Lo que la ficha declara es cuál de ellas **es**, y de dónde lo
        # sacó.
        case('rcx_the_resolved_variant_belongs_to_the_unit', CASSETTE,
             cassette({VARIANT: '11-30T (an)',
                       EVIDENCE: 'Ficha de producto Shimano CS-HG50-8'}),
             forbidden=[VARIANT, COUNT, SEQUENCE], sources=[SHIMANO_HG50]),
        case('rcx_a_resolved_variant_without_its_source_is_pending', CASSETTE,
             cassette({VARIANT: '11-30T (an)'}),
             pending=[('prerequisite', VARIANT)], sources=[SHIMANO_HG50]),

        # --- los dos extremos del rango son una sola afirmación -------------
        case('rcx_a_smallest_cog_above_the_largest_blocks', CASSETTE,
             cassette({SMALLEST: '16', LARGEST: '14'}),
             blocking=[('range_order', SMALLEST), ('range_order', LARGEST)]),
        case('rcx_an_ordered_cog_range_passes', CASSETTE,
             cassette({SMALLEST: '11', LARGEST: '30'}),
             forbidden=[SMALLEST, LARGEST], sources=[SHIMANO_HG50]),

        # --- la interfaz propia abre lo que la acepta ------------------------
        case('rcx_a_declared_spline_opens_the_accepted_bodies', CASSETTE,
             cassette(), forbidden=[BODIES], sources=[SHELDON_FREE_K7]),
        case('rcx_an_unknown_spline_leaves_the_accepted_bodies_pending', CASSETTE,
             cassette({SPLINE: UNKNOWN}),
             pending=[('prerequisite', BODIES)]),
        case('rcx_a_missing_spline_leaves_the_bodies_pending', CASSETTE,
             cassette({SPLINE: None}),
             pending=[('prerequisite', BODIES), ('required_missing', SPLINE)]),
        # La fuente de evidencia va puesta a propósito: `shift_technology` lleva
        # además un prerrequisito documental, y sin llenarlo la afirmación de
        # abajo pasaría por la razón equivocada.
        case('rcx_an_unknown_spline_leaves_the_shift_technology_pending', CASSETTE,
             cassette({SPLINE: UNKNOWN, 'shift_technology': 'HYPERGLIDE',
                       EVIDENCE: 'Ficha sintética'}),
             pending=[('prerequisite', 'shift_technology')]),

        # --- un cassette no monta sobre una rosca ---------------------------
        case('rcx_a_cassette_cannot_accept_a_threaded_freewheel_seat', CASSETTE,
             cassette({BODIES: rows(body(
                 interface='Rueda libre roscada 1.37" x 24 tpi'))}),
             blocking=[('row_shape', BODIES)], sources=[PARK_TYPE]),
        case('rcx_a_cassette_cannot_accept_a_coaster_hub', CASSETTE,
             cassette({BODIES: rows(body(interface='Contrapedal'))}),
             blocking=[('row_shape', BODIES)], sources=[PARK_TYPE]),
        # XD SLIM es un valor propio. Sin él, la ficha sólo puede escribir «SRAM
        # XD» y el cruce que SRAM niega queda indistinguible del legítimo.
        case('rcx_xd_slim_is_its_own_body_and_not_xd', CASSETTE,
             cassette({SPLINE: XD_SLIM,
                       BODIES: rows(body(interface=XD_SLIM))}),
             forbidden=[BODIES], sources=[SRAM_XD_SLIM]),

        # --- el separador es del par, no del cassette ------------------------
        case('rcx_a_pairing_without_a_separator_has_no_thickness', CASSETTE,
             cassette({BODIES: rows(body(requirement=NO_SPACER,
                                         spacer_mm='4.5'))}),
             blocking=[('row_field_applicability', BODIES)],
             sources=[SHELDON_K7]),
        case('rcx_an_unpublished_separator_leaves_the_thickness_out', CASSETTE,
             cassette({BODIES: rows(body(requirement=SPACER_UNPUBLISHED,
                                         spacer_mm='1'))}),
             blocking=[('row_field_applicability', BODIES)]),
        case('rcx_a_required_separator_owes_its_thickness', CASSETTE,
             cassette({BODIES: rows(body(requirement=SPACER_NEEDED))}),
             pending=[('row_required_missing', BODIES)]),
        case('rcx_a_required_separator_with_its_thickness_passes', CASSETTE,
             cassette({BODIES: rows(body(requirement=SPACER_NEEDED,
                                         spacer_mm='4.5'))}),
             forbidden=[BODIES], sources=[SHELDON_K7]),

        # --- un veredicto puede matizarse sin ser condicional ---------------
        case('rcx_a_conditional_verdict_owes_its_condition', CASSETTE,
             cassette({BODIES: rows(body(status=CONDITIONED))}),
             pending=[('row_required_missing', BODIES)]),
        case('rcx_a_plain_verdict_may_still_carry_its_condition', CASSETTE,
             cassette({BODIES: rows(body(
                 status=COMPATIBLE,
                 conditions='Sólo con el separador de fábrica'))}),
             forbidden=[BODIES]),

        # --- dos fuentes son dos lecturas; una fuente dos veces es duplicado --
        case('rcx_the_same_body_from_the_same_source_twice_blocks', CASSETTE,
             cassette({BODIES: rows(body(), body(status=INCOMPATIBLE))}),
             blocking=[('row_shape', BODIES)]),
        case('rcx_the_same_body_from_two_sources_is_two_readings', CASSETTE,
             cassette({BODIES: rows(body(scope=OEM_MANUAL),
                                    body(scope=OEM_TABLE,
                                         status=INCOMPATIBLE))}),
             forbidden=[BODIES]),

        # --- el extractor cuelga de la rosca --------------------------------
        case('rcx_a_declared_thread_opens_the_extractor', FREEWHEEL,
             {COUNT: '5', THREAD: ISO_THREAD, REMOVER: 'Shimano 12 estrías',
              EVIDENCE: 'Ficha sintética', SEQUENCE: teeth(14, 16, 18, 21, 24)},
             forbidden=[REMOVER], sources=[PARK_TYPE]),
        case('rcx_an_unknown_thread_leaves_the_extractor_pending', FREEWHEEL,
             {COUNT: '5', THREAD: UNKNOWN, REMOVER: 'Shimano 12 estrías',
              EVIDENCE: 'Ficha sintética', SEQUENCE: teeth(14, 16, 18, 21, 24)},
             pending=[('prerequisite', REMOVER)], sources=[PARK_TYPE]),
        case('rcx_a_missing_thread_leaves_the_extractor_pending', FREEWHEEL,
             {COUNT: '5', REMOVER: 'Shimano 12 estrías',
              EVIDENCE: 'Ficha sintética', SEQUENCE: teeth(14, 16, 18, 21, 24)},
             pending=[('prerequisite', REMOVER), ('required_missing', THREAD)]),

        # --- dos roscas, y una gira al revés --------------------------------
        case('rcx_a_declared_cog_thread_opens_the_lockring_thread', FIXED,
             {'single_cog_teeth': '16', COG_THREAD: ISO_THREAD,
              'chain_width_family': '1/8', COG_LOCKRING: ENGLISH_LOCKRING},
             forbidden=[COG_LOCKRING], sources=[SHELDON_LOCKRING]),
        case('rcx_an_unknown_cog_thread_leaves_the_lockring_pending', FIXED,
             {'single_cog_teeth': '16', COG_THREAD: UNKNOWN,
              'chain_width_family': '1/8', COG_LOCKRING: ENGLISH_LOCKRING},
             pending=[('prerequisite', COG_LOCKRING)]),
        case('rcx_a_missing_cog_thread_leaves_the_lockring_pending', FIXED,
             {'single_cog_teeth': '16', 'chain_width_family': '1/8',
              COG_LOCKRING: ENGLISH_LOCKRING},
             pending=[('prerequisite', COG_LOCKRING),
                      ('required_missing', COG_THREAD)]),
        case('rcx_a_hub_without_a_second_thread_is_a_value', FIXED,
             {'single_cog_teeth': '16', COG_THREAD: ISO_THREAD,
              'chain_width_family': '1/8', COG_LOCKRING: NO_LOCKRING},
             forbidden=[COG_LOCKRING], sources=[SHELDON_FIXED]),

        # --- un espesor no dice nada sin su destino -------------------------
        case('rcx_a_declared_target_demands_the_thickness', SPACER,
             {TARGET: 'SRAM XD'},
             pending=[('required_missing', THICKNESS)]),
        case('rcx_an_unknown_target_does_not_demand_a_thickness', SPACER,
             {TARGET: UNKNOWN}, forbidden=[THICKNESS]),
        case('rcx_a_published_thickness_survives_a_missing_target', SPACER,
             {THICKNESS: '1.85'}, forbidden=[THICKNESS], sources=[SRAM_XD_XDR]),
    ]


def _proposals():
    """Las dos capacidades pendientes. El motor compartido no lo toco."""
    return [
        {'id': 'P-1',
         'title': 'Cardinalidad por grupo, como forma alternativa',
         'target': 'row_coherence.cardinalities[*]',
         'exclusive_forms': [
             {'shape': ['id', 'field', 'total_field'],
              'meaning': 'total escalar de la plantilla contra todas las filas'},
             {'shape': ['id', 'field', 'group_by', 'total_column'],
              'meaning': 'total por fila destino contra las filas de su grupo; '
                         '`group_by` es el ID de un link ya declarado sobre el '
                         'mismo `field`'}],
         'mutually_exclusive': True,
         'not_needed_here': 'Estas cuatro familias **ya no** necesitan la forma '
                            'agrupada. El hueco que la motivaba era de dueño, no '
                            'de contador: el catálogo de variantes del modelo no '
                            'es un grupo del SKU y sale de la ficha. La forma '
                            'agrupada sigue siendo útil para un grupo que sí sea '
                            'del mismo SKU —configuraciones de montaje admitidas '
                            'por la pieza, o conjuntos de varias piezas '
                            'incluidas—, y ninguno existe hoy en piñonería.',
         'reference_fixtures_only': True,
         'oem_case': {'model': 'Shimano CS-HG50-8', 'source': SHIMANO_HG50,
                      'published_variants': 7, 'sprockets_per_variant': 8,
                      'unit_speed_count': 8,
                      'location': 'referencia OEM (§4.1); demuestra el motor '
                                  'como fixture, no como ubicación productiva'}},
        {'id': 'P-2-prima',
         'title': 'Evaluar la relación que ya existe, en vez de duplicarla',
         'replaces': 'P-2, rechazada por root: rellenar `conditions` no puede '
                     'habilitar un cruce imposible.',
         'reuses_existing_model': {
             'class': 'ProductSpecRelation',
             'file': 'lib/modules/inventory/models/product_spec_relation.dart',
             'why': 'Ya tiene exactamente la semántica que hacía falta y no hay '
                    'que inventar otro conjunto: `interface`, filas de '
                    '`alternatives` y de `exclusions`, cada una con `id`, '
                    '`label`, `conditions` tipadas (campo, operador, tipo, '
                    'valor) y `sources` obligatorias, validadas como URL '
                    'absoluta. Las condiciones **son** los parámetros del '
                    'montaje: `spacer_mm eq 1.85` se escribe tal cual.',
             'what_is_missing': 'Hoy la clase sólo se resume en prosa '
                                '(`productSpecClaimSummary`, '
                                '`product_spec_contract.dart:41-47`). No existe '
                                'evaluador. P-2-prima es **ese** evaluador, no '
                                'otro modelo de datos.'},
         'rule': {'id': 'body_against_own_interface', 'field': BODIES,
                  'column': 'rear_drive_interface', 'scalar_field': SPLINE,
                  'relation_interface': 'rear_drive_interface'},
         'semantics': [
             'La dirección la da la regla: `scalar_field` es la interfaz propia '
             'de la pieza y `column` el cuerpo que la fila declara.',
             'Cualquiera de los dos lados sin valor conocido → '
             '`row_relation_pending`, no bloqueante.',
             'La fila coincide con una `exclusions` → '
             '`row_relation_excluded`, bloqueante. **Ningún texto lo levanta.**',
             'La fila coincide con una `alternatives`: se evalúan sus '
             '`conditions` contra las columnas de esa misma fila. Y aquí van '
             'dos estados distintos, que es la corrección de root: '
             '**parámetro ausente** → `row_relation_parameter_pending`, no '
             'bloqueante, porque no saber no es contradecir; **parámetro '
             'presente que no cumple la condición** → '
             '`row_relation_parameter_conflict`, bloqueante. Nunca el mismo '
             'error diciendo «falta» para los dos.',
             'La fila no aparece ni en alternativas ni en exclusiones → '
             '`row_relation_unlisted`, no bloqueante. Ni permitida ni negada '
             'por omisión.',
             'Dos etiquetas iguales no son un permiso: sin una fila de '
             '`alternatives` que la nombre, el par queda sin listar.',
             'Las `sources` de la fila ya son obligatorias en el modelo, así '
             'que una relación sin fuente no es representable.'],
         'new_issue_codes': ['row_relation_excluded (bloqueante)',
                             'row_relation_parameter_conflict (bloqueante)',
                             'row_relation_parameter_pending (no bloqueante)',
                             'row_relation_unlisted (no bloqueante)',
                             'row_relation_pending (no bloqueante)'],
         'relation_claim_seed': {
             'schema_version': 2, 'interface': 'rear_drive_interface',
             'label': 'Cuerpos admitidos por un cassette SRAM XD',
             'alternatives': [
                 {'id': 'xd_on_xdr', 'label': 'Cuerpo SRAM XDR con separador',
                  'conditions': [
                      {'field': 'rear_drive_interface', 'operator': 'eq',
                       'value_type': 'token', 'value': 'SRAM XDR'},
                      {'field': 'spacer_mm', 'operator': 'eq',
                       'value_type': 'decimal', 'value': '1.85'}],
                  'sources': [SRAM_XD_XDR]}],
             'exclusions': [
                 {'id': 'xd_on_xd_slim', 'label': 'Cuerpo SRAM XD SLIM',
                  'conditions': [
                      {'field': 'rear_drive_interface', 'operator': 'eq',
                       'value_type': 'token', 'value': XD_SLIM}],
                  'sources': [SRAM_XD_SLIM]}]},
         'explicitly_unknown': [
             {'about': 'cuerpos HG SLIM y XD SLIM en la misma maza',
              'why': 'la fuente lo enuncia con reserva —«most hubs … are likely '
                     'able to be compatible … Please consult your hub '
                     'manufacturer»— y una reserva no se promueve a relación',
              'source': SRAM_XD_SLIM},
             {'about': 'el sentido XDR → XD',
              'why': 'la página de XD/XDR no lo enuncia en ninguna dirección y '
                     'no se infiere del recíproco',
              'source': SRAM_XD_XDR}],
         'out_of_scope': [
             'Cambiar el cuerpo de una maza por otro es una intervención '
             'distinta del montaje del cassette sobre el cuerpo actual.',
             'Las generalizaciones históricas de Sheldon sobre 7–11 velocidades '
             'no se promueven a relaciones.']}]


def _proposed_cases():
    """Casos que hoy **fallan**: el motor no emite nada donde debería.

    Fuera de `cases` — el arnés los correría y los daría por rotos. Los de
    P-2-prima corren contra estas mismas plantillas; los de P-1 son fixtures de
    **referencia OEM** y no se ejecutan aquí, porque su superficie ya no es un
    campo de producto.
    """
    reference = oem_variant_reference()
    short = deepcopy(reference)
    short['variants'][1]['teeth'] = short['variants'][1]['teeth'][:-1]
    return [
        {'proposal': 'P-1', 'id': 'rcp_one_published_variant_is_short',
         'surface': 'oem_reference_fixture', 'runnable_against_templates': False,
         'values': short, 'today': [], 'expected_with_capability': [
             {'code': 'row_cardinality_pending', 'group': '11-30T'}],
         'reason': 'La (an) declara ocho piñones y trae siete. Es una fixture de '
                   'referencia del motor agrupado: ni el SKU ni sus ocho '
                   'velocidades cambian, y este catálogo no es un hecho suyo.',
         'source_urls': [SHIMANO_HG50]},
        {'proposal': 'P-1', 'id': 'rcp_every_published_variant_is_complete',
         'surface': 'oem_reference_fixture', 'runnable_against_templates': False,
         'values': reference, 'today': [], 'expected_with_capability': [],
         'reason': 'Siete combinaciones de ocho contra ocho: la capacidad no '
                   'debe inventar una incidencia donde cada variante está '
                   'completa.',
         'source_urls': [SHIMANO_HG50]},
        # --- P-2-prima, sobre estas mismas plantillas ----------------------
        {'proposal': 'P-2-prima',
         'id': 'rcp_a_note_cannot_authorise_an_excluded_body',
         'template': CASSETTE, 'kind': 'capability_gap',
         'values': cassette({SPLINE: SPLINE_XD, BODIES: rows(body(
             interface=XD_SLIM, status=CONDITIONED, scope=OEM_MANUAL,
             conditions='El taller afirma que entra igual.'))}),
         'today': [], 'expected_with_capability': [
             {'code': 'row_relation_excluded', 'field': BODIES,
              'row_id': 'r1', 'column': 'rear_drive_interface'}],
         'reason': 'SRAM niega el cruce XD / XD SLIM. Una frase en `conditions` '
                   'no puede levantarlo.',
         'source_urls': [SRAM_XD_SLIM]},
        {'proposal': 'P-2-prima',
         'id': 'rcp_an_absent_spacer_is_pending_not_a_contradiction',
         'template': CASSETTE, 'kind': 'capability_gap',
         'values': cassette({SPLINE: SPLINE_XD, BODIES: rows(body(
             interface=BODY_XDR, requirement=SPACER_NEEDED, status=CONDITIONED,
             scope=OEM_MANUAL,
             conditions='XDR admite cassettes XD con separador (SRAM).'))}),
         'today': [], 'expected_with_capability': [
             {'code': 'row_relation_parameter_pending', 'field': BODIES,
              'row_id': 'r1', 'column': 'spacer_mm', 'blocking': False}],
         'reason': 'El separador que la relación exige no está declarado. No '
                   'saber no es contradecir: queda pendiente, no bloquea.',
         'source_urls': [SRAM_XD_XDR]},
        {'proposal': 'P-2-prima',
         'id': 'rcp_a_contradicted_spacer_is_not_the_same_as_an_absent_one',
         'template': CASSETTE, 'kind': 'capability_gap',
         'values': cassette({SPLINE: SPLINE_XD, BODIES: rows(body(
             interface=BODY_XDR, requirement=SPACER_NEEDED, spacer_mm='1',
             status=CONDITIONED, scope=OEM_MANUAL,
             conditions='Se montó con el separador que había.'))}),
         'today': [], 'expected_with_capability': [
             {'code': 'row_relation_parameter_conflict', 'field': BODIES,
              'row_id': 'r1', 'column': 'spacer_mm'}],
         'reason': 'SRAM publica 1,85 mm y la fila declara 1 mm. Eso no es un '
                   'dato que falta: es un dato que contradice la relación.',
         'source_urls': [SRAM_XD_XDR]},
        {'proposal': 'P-2-prima',
         'id': 'rcp_the_published_spacer_satisfies_the_relation',
         'template': CASSETTE, 'kind': 'capability_gap_positive',
         'values': cassette({SPLINE: SPLINE_XD, BODIES: rows(body(
             interface=BODY_XDR, requirement=SPACER_NEEDED, spacer_mm='1.85',
             status=CONDITIONED, scope=OEM_MANUAL,
             conditions='XDR admite cassettes XD con separador de 1,85 mm '
                        'detrás (SRAM).'))}),
         'today': [], 'expected_with_capability': [],
         'reason': 'El parámetro publicado está declarado y es igual: la '
                   'relación se cumple por su medida, no por el texto.',
         'source_urls': [SRAM_XD_XDR]},
        {'proposal': 'P-2-prima', 'id': 'rcp_an_unlisted_pair_is_not_a_verdict',
         'template': CASSETTE, 'kind': 'capability_gap',
         'values': cassette({SPLINE: SPLINE_XD,
                             BODIES: rows(body(interface='Campagnolo'))}),
         'today': [], 'expected_with_capability': [
             {'code': 'row_relation_unlisted', 'field': BODIES, 'row_id': 'r1',
              'column': 'rear_drive_interface', 'blocking': False}],
         'reason': 'Ese par no está ni en alternativas ni en exclusiones. No se '
                   'permite por omisión ni se niega por omisión.',
         'source_urls': []},
        {'proposal': 'P-2-prima',
         'id': 'rcp_equal_labels_still_need_an_alternative_row',
         'template': CASSETTE, 'kind': 'capability_gap',
         'values': cassette({SPLINE: SPLINE_XD,
                             BODIES: rows(body(interface=BODY_XD))}),
         'today': [], 'expected_with_capability': [
             {'code': 'row_relation_unlisted', 'field': BODIES, 'row_id': 'r1',
              'column': 'rear_drive_interface', 'blocking': False}],
         'reason': 'Dos etiquetas iguales no demuestran el montaje: sin una fila '
                   'de `alternatives` que lo nombre, el par queda sin listar.',
         'source_urls': [SRAM_XD_XDR]},
        {'proposal': 'P-2-prima',
         'id': 'rcp_an_unknown_own_interface_is_never_a_conflict',
         'template': CASSETTE, 'kind': 'capability_gap_unknown',
         'values': cassette({SPLINE: UNKNOWN,
                             BODIES: rows(body(interface=BODY_XD))}),
         'today': [], 'expected_with_capability': [
             {'code': 'row_relation_pending', 'field': BODIES, 'row_id': 'r1',
              'column': 'rear_drive_interface', 'blocking': False}],
         'reason': 'Sin interfaz propia conocida no hay relación que evaluar.',
         'source_urls': []},
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-rear-cogs-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-rear-cogs-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'live_shared': len(catalog['live_shared_definitions']),
                      'corrected_from_frozen': len(catalog['adopted_live_definitions']),
                      'renames_declined': len(catalog['renames_declined'])}))
