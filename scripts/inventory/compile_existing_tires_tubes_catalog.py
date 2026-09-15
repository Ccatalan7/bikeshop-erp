#!/usr/bin/env python3
"""Source-to-candidate successor for the five tyre/tube families.

tire, tube, rim_strip, tubeless_consumable and tubeless_valve. No migration, no
production, no fill, no assignment change, no SQL.

These five arrived in much better shape than the rear cogs: they already carry
gates, row conditions and prerequisites. What they do **not** carry is the line
this block exists to draw, and that root named: a **physical description**, a
**declared compatibility**, a **concrete mounting** and **unknown evidence** are
four different things, and a catalogue of OEM variants is never a fact of the
SKU.

The rule that orders the block is Sheldon's: «The second ISO number is the
critical one: it is the diameter of the bead seat of the rim, in mm ("B.S.D.")»,
and «Although these size designations are mathematically equal, they refer to
different size tires, which are NOT interchangeable.» A measurement that matches
is not an approval, and a brand is not a standard.
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

TIRE, TUBE, STRIP, CONSUMABLE, VALVE = (
    'tire', 'tube', 'rim_strip', 'tubeless_consumable', 'tubeless_valve')
FAMILIES = (TIRE, TUBE, STRIP, CONSUMABLE, VALVE)

PREIMAGE = ROOT / '.tmp/db/existing-37-candidate-preimage.json'
PREIMAGE_SHA = '0a21d85a1539c330e661e0c5c1aa2fde0bbf29ddad67a452a018ed767d08b2a6'

# Sheldon Brown, Tire Sizing — abierta y leída. El eje real de la compatibilidad
# y la prohibición de universalizar una medida: «The second ISO number is the
# critical one: it is the diameter of the bead seat of the rim, in mm ("B.S.D.")»,
# «Generally, if this number matches, the tire will fit onto the rim; if it
# doesn't match, the tire won't fit», y «Although these size designations are
# mathematically equal, they refer to different size tires, which are NOT
# interchangeable.»
SHELDON_SIZING = 'https://www.sheldonbrown.com/tire-sizing.html'
# Park Tool, Tubeless Tire Compatibility — abierta y leída. Que un componente se
# llame «tubeless ready» no cierra el par: «The various 'tubeless ready'
# components may or may not match between manufacturers.»
PARK_TUBELESS = ('https://www.parktool.com/en-us/blog/repair-help/'
                 'tubeless-tire-compatibility')
STANS_DOSES = 'https://stans.com/pages/sealant-refresh-reminder'
# Park Tool, Tubeless Tire Conversion — abierta y leída; la cinta se elige por la
# llanta: «Choose a sealing tape of an appropriate width for the rim».
PARK_CONVERSION = ('https://www.parktool.com/en-us/blog/repair-help/'
                   'tubeless-tire-conversion')
# Zipp / SRAM, Hookless tire compatibility — abierta y leída dos veces. El techo
# es del **sistema**: «Zipp TSS wheel and tire systems should never be inflated
# to more than 5 bar (72 psi)». La cámara no cambia el requisito: «Inner tubes
# are ok, but the tire must be designed for TSS-compatibility for safe
# retention.»
#
# Y lo que la segunda lectura corrigió: la lista **no es exhaustiva** y no
# listar no prohíbe. «This list is not exhaustive of all TSS compatible tires
# and is provided as a convenience to help guide your tire purchases», y «If you
# are interested in a tire that is not listed here, you should check with the
# tire manufacturer or reference their website to see if the tire is compatible
# with Zipp wheels.» La prohibición expresa que sí existe es una **regla con
# parámetro**, no una lista: «Zipp TSS rims are NOT compatible with tires that
# require a minimum pressure higher than 5 bar (72 psi).»
ZIPP_HOOKLESS = 'https://www.sram.com/en/zipp/campaigns/hookless-tire-compatibility'
# ENVE, Hookless Rim Technology 101 — abierta y leída. La aprobación es por
# modelo y con umbral: «For a 28mm tire to be listed as "Approved/Recommended" on
# ENVE's Tire Compatibility Chart, the tire in question must achieve 120 psi or
# 165% of the stated ETRTO/ISO max pressure of 5 bar/72.5 psi.»
ENVE_HOOKLESS = 'https://enve.com/blogs/journal/hookless-rim-technology-101'
# Park Tool, VC-1 Valve Core Tool — abierta y leída. El núcleo desmontable **no**
# se deduce del tipo: la herramienta saca e instala «Schrader valve cores» y
# «Removable Presta valve cores», y la propia ficha aclara «(not all Presta valve
# cores are removable)». Para Dunlop u otras normas la página no dice nada:
# ABSENT, y por eso aquí no se afirma nada en ninguna dirección.
PARK_VC1 = 'https://www.parktool.com/en-us/product/valve-core-tool-vc-1'
SYNTHETIC = 'https://example.invalid/synthetic'

CONFIGS = 'tire_rim_configurations'
PRESSURES = 'tire_general_max_pressures'
FIT_ROWS = 'tube_fit_rows'
BSD = 'bead_seat_diameter_mm'
BEAD, TSS_READY, ETRTO = 'tire_bead_type', 'tire_tubeless_ready', 'tire_etrto'
VALVE_TYPE, VALVE_LEN = 'valve_type', 'valve_length_mm_value'
VALVE_SHAPE, HOLE = 'valve_base_shape', 'rim_hole_diameter_mm'
KIND, BASE = 'consumable_kind', 'sealant_base'
DOSE, VOLUME = 'recommended_dose_ml', 'sealant_volume_ml'
MEMBERS = 'kit_members'
STRIP_WIDTH, STRIP_MATERIAL = 'strip_width_mm', 'strip_material'
STRIP_MIN, STRIP_MAX = 'strip_fit_internal_width_min_mm', 'strip_fit_internal_width_max_mm'
EVIDENCE = 'spec_evidence_source'
CORE = 'valve_core_removable'

HOOKLESS = 'Sin gancho (hookless)'
SEALANT, CONVERSION_KIT = 'Sellante', 'Kit conversión (cinta+válvulas+sellante)'
UNKNOWN = 'Desconocido / sin confirmar'
OTHER_VALVE = 'Otra'

# R-3 de root: un montaje observado en el taller **no** es una declaración del
# SKU. El contrato canónico separa la inspección de una unidad de los hechos del
# producto, y cambiarle la etiqueta a la procedencia no cambia ese alcance. La
# observación se queda con su dueño de inspección y sale de este dominio.
CLAIM_BASIS = ['Especificación del fabricante del neumático',
               'Lista de compatibilidad del fabricante de la llanta',
               'Norma ETRTO citada en el documento',
               UNKNOWN]
# R-2: la identidad de una fila es el alcance realmente declarado, no su URL.
SCOPE_KIND = ['Modelo y edición de llanta',
              'Familia de llantas declarada por el fabricante',
              'Norma y edición citadas en el documento',
              UNKNOWN]
DOSE_SCOPE = ['MTB tubeless', 'Ruta o gravel tubeless',
              'Fatbike o plus tubeless', 'Cámara con sellante',
              'Otra aplicación', UNKNOWN]
MEMBER_ROLE = ['Sellante', 'Válvula tubeless', 'Cinta de llanta', 'Inserto',
               'Inyector o jeringa', 'Extractor de núcleo', 'Otro']
VALVE_STANDARD = 'valve_standard'
VALVE_STANDARDS = ['Presta (francesa)', 'Schrader (americana / auto)',
                   'Dunlop (inglesa)', 'Otra', UNKNOWN]
DOSES = 'sealant_dose_recommendations'
KIT = 'tubeless_kit_members'
TSS_APPROVAL = ['La llanta lista este neumático',
                'La llanta no lo lista', UNKNOWN]


def unknown_value(definition):
    """The domain's own «unknown» token, whatever its exact spelling."""
    found = [v for v in definition['allowed_values'] if v.startswith('Desconocido')]
    if len(found) != 1:
        raise ValueError(definition['key'] + ': no single unknown token')
    return found[0]


def known(definitions, key):
    """The published domain minus its «unknown» answer.

    A gate that reads a selector must not open because the operator admitted
    ignorance: the engine treats that token as an absent value
    (`spec_rule_evaluator.dart:5-13`), so the dependent field stays pending.
    Writing the domain without it keeps the contract saying what the engine does.
    """
    definition = definitions[key]
    blank = unknown_value(definition)
    return condition(key, [v for v in definition['allowed_values'] if v != blank])


def gate(template, mapping, required=None):
    contract = template['form_contract']
    for key, rule in mapping.items():
        contract['allowed_when'][key] = deepcopy(rule)
        contract['required_when'][key] = deepcopy((required or {}).get(key, rule))


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
        entry['required_when'][key] = deepcopy((required or {}).get(key, rule))


def row_condition(field, value, kind='token', operator=None):
    return {'kind': 'when', 'rows': [[{
        'field': field, 'operator': operator or ('in' if isinstance(value, list) else 'eq'),
        'value_type': kind, 'value': value}]]}


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

    # The live row is authoritative over the frozen proposal. Three keys these
    # five use say `new` there and are published, and one carries the same
    # option set in a different **order** — which the publisher compares with
    # `!=` on lists, so it would have been refused as a changed shared
    # definition, not merged.
    changed, order_only = set(), set()
    for key, actual in published.items():
        if key not in definitions:
            continue
        before = definitions[key]
        if (sorted(before.get('allowed_values') or []) == sorted(actual['allowed_values'] or [])
                and (before.get('allowed_values') or []) != (actual['allowed_values'] or [])):
            order_only.add(key)
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
    # Four of the five differ; the live word is what the shop already uses, and
    # the publisher refuses the change outright.
    renamed = {}
    for key, template in templates.items():
        actual = live_templates[key]
        if template.get('name') != actual['name']:
            renamed[key] = {'frozen_proposal': template.get('name'),
                            'live_preserved': actual['name']}
            template['name'] = actual['name']

    _tire(definitions, templates)
    _tube(definitions, templates)
    _strip(definitions, templates)
    _consumable(definitions, templates)
    _valve(definitions, templates)

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
        for key in sorted(selectors):
            if contract['roles'].get(key) == 'legacy':
                continue
            contract['required_when'][key] = deepcopy(ALWAYS)

    _assert_owners(definitions, templates)
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
    fixtures['pending_cases'] = _pending_cases()
    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Tyre and tube families reviewed successor',
               'templates': [templates[f] for f in FAMILIES],
               'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA,
                                'preimage': PREIMAGE_SHA},
               'renames_declined': renamed,
               'live_shared_definitions': sorted(k for k in keys if k in published),
               'adopted_live_definitions': sorted(changed & keys),
               'option_order_collisions': sorted(order_only & keys),
               'adjudicated_limits': _adjudications(),
               'relation_integration': _relation_integration(),
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(catalog['templates']),
                        'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in catalog['templates'])}
    return catalog, fixtures


def _assert_owners(definitions, templates):
    """A strip has a hole; a valve is a valve. Asserted, not trusted.

    `used_by` is edited by hand, and a single stray family name would let a rim
    strip carry a valve type as if it were one, or a tube own a rim's hole.
    """
    valve_owned = {VALVE_SHAPE, CORE}
    for key, template in templates.items():
        present = {f['key'] for f in template['fields']}
        roles = template['form_contract']['roles']
        active = {k for k in present if roles.get(k) != 'legacy'}
        if key == STRIP and active & valve_owned:
            raise ValueError('A rim strip cannot own a valve: '
                             f'{sorted(active & valve_owned)}')
        if key in (TIRE, CONSUMABLE) and VALVE_TYPE in active:
            raise ValueError(f'{key} must not own a valve type')
    for family in (TUBE, VALVE):
        contract = templates[family]['form_contract']
        if contract['roles'].get(VALVE_TYPE) != 'legacy':
            raise ValueError(f'{family}: the published valve vocabulary must be retired')
        domain = definitions[VALVE_STANDARD]['allowed_values']
        if OTHER_VALVE not in domain or UNKNOWN not in domain:
            raise ValueError(f'{family}: «Otra» and the engine-readable unknown are both required')


def _tire(definitions, templates):
    """Cuatro cosas distintas dentro de una misma tabla, y ninguna se disfraza
    de las otras.

    `tire_rim_configurations` describe **compatibilidad declarada**: qué llanta
    admite este neumático, según alguien. La fila no decía **según quién**, ni
    exigía fuente, así que una especificación del fabricante, una cita de ETRTO
    y un montaje hecho en el taller entraban idénticas. Ahora la base de la
    afirmación es una columna obligatoria y la fuente también.

    Y sobre hookless: la aprobación es **una lista, no una medida**. Zipp dice
    «Zipp TSS rims should only be used with TSS-compatible tires» y ENVE publica
    un umbral por modelo para entrar en su tabla. Que el ancho calce no aprueba
    nada, y por eso la fila de una llanta sin gancho debe decir si el fabricante
    de la llanta lista **este** neumático.
    """
    template = templates[TIRE]
    add_column(definitions, CONFIGS,
               column('scope_kind', 'Qué identifica esta fila', 'token',
                      required=True, options=SCOPE_KIND),
               after=None)
    add_column(definitions, CONFIGS,
               column('scope_identity',
                      'Modelo y edición, familia o norma declarada',
                      required=True),
               after='scope_kind')
    add_column(definitions, CONFIGS,
               column('claim_basis', 'Base de la afirmación', 'token',
                      required=True, options=CLAIM_BASIS),
               after='scope_identity')
    schema = definitions[CONFIGS]['validation_rules']['rows_schema']
    schema['columns'] = (schema['columns'][-3:] + schema['columns'][:-3])
    add_column(definitions, CONFIGS,
               column('rim_maker_lists_this_tire',
                      'La llanta lista este neumático', 'token',
                      options=TSS_APPROVAL))
    source = next(c for c in definitions[CONFIGS]['validation_rules'][
        'rows_schema']['columns'] if c['key'] == 'source_url')
    source['required'] = True

    # R-2 de root, y tenía razón: perfil y método **no identifican** una llanta.
    # Dos modelos distintos comparten «sin gancho» y «tubeless» y traen anchos y
    # límites diferentes; con la llave anterior, la segunda configuración válida
    # se declaraba duplicada. La identidad es el alcance realmente declarado —un
    # modelo con su edición, una familia que el fabricante nombra, o una norma
    # citada— y el perfil y el método pasan a ser **parámetros** de ese alcance,
    # que viajan junto a él. La URL no entra en la llave: otra fuente del mismo
    # alcance no crea otro objeto, es la misma fila con otra referencia.
    key_rows(definitions, CONFIGS, ('scope_kind', 'scope_identity'))

    # Una revisión crítica de mi propia compuerta: **cualquier** fabricante de
    # llanta puede publicar una lista de neumáticos, no sólo los sin gancho.
    # Restringir la *pregunta* a hookless era una suposición mía sin fuente. Lo
    # que sí está en la fuente es que para TSS la aprobación importa —«Do not
    # use tires that are not TSS-approved»—, así que la pregunta queda abierta
    # siempre y sólo la **exigencia** es de hookless.
    row_gate(template, CONFIGS,
             {'rim_maker_lists_this_tire': {'kind': 'always'}},
             required={'rim_maker_lists_this_tire':
                       row_condition('rim_bead_profile', HOOKLESS)})

    # La prohibición expresa de Zipp no es una lista: es una regla con
    # parámetro sobre la presión **mínima** que el neumático exige. Esa magnitud
    # no existía en la ficha, y sin ella la regla no es evaluable. Entra como
    # columna de la tabla de presiones declaradas, junto a su unidad y su
    # alcance, que es donde el resto de las cifras ya viven.
    definitions[PRESSURES]['label'] = 'Presiones declaradas del neumático'
    add_column(definitions, PRESSURES,
               column('min_pressure_value', 'Presión mínima exigida', 'decimal',
                      positive=True),
               after='max_pressure_value')
    # Only limits of the SAME tyre/scope/unit row are ordered. A system limit
    # in another table is a different owner and is not compared here.
    definitions[PRESSURES]['validation_rules']['rows_schema'][
        'ordered_pairs'] = [['min_pressure_value', 'max_pressure_value']]

    # El número crítico de Sheldon deja de ser opcional: sin ETRTO la ficha no
    # dice a qué llanta entra, por más pulgadas que declare.
    gate(template, {ETRTO: deepcopy(ALWAYS)}, required={ETRTO: deepcopy(ALWAYS)})
    # Una lectura de neumático sin su documento no es una lectura.
    template['form_contract']['prerequisites'][CONFIGS] = [EVIDENCE]


def _tube(definitions, templates):
    """La cámara calza por BSD y ancho, y cada BSD aparece una sola vez.

    `tube_fit_rows` no tenía llave: la misma medida de asiento podía entrar dos
    veces con anchos distintos y nada objetaba cuál vale. Y el contrato recortaba
    el dominio de la válvula a cuatro valores, dejando fuera «Otra»: una válvula
    rara quedaba obligada a declararse **desconocida**, que es otra cosa.
    """
    template = templates[TUBE]
    key_rows(definitions, FIT_ROWS, (BSD,))
    _valve_successor(definitions, templates)
    # Con el sucesor, el desconocido vuelve a comportarse como una ausencia, así
    # que la compuerta puede condicionar la **aplicabilidad**, que es lo que el
    # dominio pide: sin saber qué válvula es, medir su largo no dice contra qué
    # llanta sirve. La ronda anterior abrió el permiso para no convertir una
    # ignorancia en prohibición; root señaló que eso arreglaba el síntoma. La
    # semántica se arregla en el vocabulario, no en la compuerta.
    # Revisión crítica: el largo de una válvula es una **medida física**, siempre
    # contestable, y saber su norma no es un requisito para medirla. Condicionarla
    # era decorativo: se exige siempre.
    gate(template, {VALVE_LEN: deepcopy(ALWAYS)},
         required={VALVE_LEN: deepcopy(ALWAYS)})


def _valve_successor(definitions, templates):
    """Un sucesor acotado del vocabulario de válvula, con el desconocido correcto.

    R-4b de root: el desconocido literal de `valve_type` merecía una corrección
    de semántica o un sucesor, y abrir permisos para que un mutante fuera
    observable **no** es una razón de producto. Tiene razón, y la ronda anterior
    hizo exactamente eso.

    La definición publicada deletrea «Desconocido» a secas, que
    `hasKnownSpecValue` no reconoce como ausencia
    (`lib/modules/inventory/utils/spec_rule_evaluator.dart:5-13`), así que ahí
    una ignorancia declarada es una respuesta *conocida* que **prohíbe** el
    campo dependiente. Como el encargo autoriza clonar hacia una clave nueva de
    alcance explícito, el sucesor lleva el mismo dominio con «Desconocido / sin
    confirmar», y la publicada se conserva **retirada** en estas dos fichas: no
    se toca la definición global ni sus datos.
    """
    definitions[VALVE_STANDARD] = new_definition(
        VALVE_STANDARD, 'Norma de válvula', 'single_select', (TUBE, VALVE),
        options=VALVE_STANDARDS)
    for family in (TUBE, VALVE):
        template = templates[family]
        add_field(template, VALVE_STANDARD, 'measurement', 'compatibility',
                  required=deepcopy(ALWAYS),
                  helper='Sucesor acotado de «Tipo de Válvula»: mismo dominio, '
                         'con «Otra» y con el desconocido que el motor entiende.')
        retire(template, [VALVE_TYPE])
        contract = template['form_contract']
        # La propuesta congelada abría `valve_core_removable` sólo para Presta, y
        # yo la repunté al sucesor sin comprobarla: **la regla es falsa**. Park
        # publica que su VC-1 saca e instala «Schrader valve cores» y que «not
        # all Presta valve cores are removable». El núcleo desmontable es una
        # propiedad **de la válvula**, no de su norma, así que no se deduce del
        # tipo en ninguna dirección y para Dunlop la fuente no dice nada.
        # La compuerta se retira y la afirmación pasa a exigir su documento.
        for section in ('allowed_when', 'required_when'):
            for key in [k for k, rule in contract.get(section, {}).items()
                        if any(term.get('field') == VALVE_TYPE
                               for clause in rule.get('rows', [])
                               for term in clause)]:
                contract[section][key] = deepcopy(
                    ALWAYS if section == 'allowed_when' else NEVER)
        if CORE in contract['roles']:
            contract.setdefault('prerequisites', {})[CORE] = [EVIDENCE]


def _strip(definitions, templates):
    """Un fondo de llanta se elige por el interior de la llanta, no por pulgadas.

    Park lo dice para la cinta —«Choose a sealing tape of an appropriate width
    for the rim»— y para el fondo vale igual: el ancho de la tira tiene que
    cubrir el lecho de una llanta concreta. El candidato traía un ancho suelto y
    ninguna medida de la llanta a la que sirve.

    El agujero de válvula se reutiliza de `rim_hole_diameter_mm`, que es nueva y
    todavía no está publicada: es la misma magnitud física y no merece otra
    clave. Lo que **no** lleva un fondo es un tipo de válvula: tiene un agujero,
    no una válvula, y por eso ese campo se queda retirado.
    """
    template = templates[STRIP]
    for key, label in ((STRIP_MIN, 'Ancho interior mínimo de llanta que cubre'),
                       (STRIP_MAX, 'Ancho interior máximo de llanta que cubre')):
        definitions[key] = new_definition(key, label, 'number', (STRIP,),
                                          unit='mm', rules={'positive': True})
        add_field(template, key, 'measurement', 'compatibility',
                  helper='El rango de llanta al que sirve esta tira, no su '
                         'propio ancho.')
    definitions[HOLE]['used_by'] = sorted(set(definitions[HOLE]['used_by']) | {STRIP})
    add_field(template, HOLE, 'measurement', 'compatibility',
              helper='Diámetro del agujero de válvula que trae la tira.')
    template['form_contract']['rules_version'] = 2
    template['form_contract']['scalar_ordered_pairs'] = [[STRIP_MIN, STRIP_MAX]]
    # Revisión crítica: el ancho de la tira es una medida física de la tira, y el
    # material no es un requisito para medirla. Colgarla del material era
    # decorativo y hacía que un mutante pareciera cubierto. Se exige siempre.
    gate(template, {STRIP_WIDTH: deepcopy(ALWAYS)},
         required={STRIP_WIDTH: deepcopy(ALWAYS)})


def _consumable(definitions, templates):
    """La dosis pertenece a una aplicación identificada; el envase es contenido."""
    template = templates[CONSUMABLE]
    definitions[KIND]['allowed_values'] = list(
        definitions[KIND]['allowed_values']) + [UNKNOWN]
    contract = template['form_contract']

    # R-1 de root, y era un error de dominio mío: **120 ml de dosis en un frasco
    # de 60 es legítimo**, se usan dos envases. La desigualdad
    # `dose <= volume` certificaba una regla falsa, y matar un mutante con ella
    # no la volvía verdadera. Se retira. La dosis pertenece a una **aplicación
    # identificada** y la cantidad vendida al SKU: son dos dueños distintos, y
    # ahora están en dos sitios distintos.
    definitions[DOSES] = new_definition(
        DOSES, 'Dosis recomendada por aplicación', 'json', (CONSUMABLE,),
        rules={'rows_schema': {'version': 1, 'columns': [
            column('application_scope', 'Aplicación documentada', 'token',
                   required=True, options=DOSE_SCOPE),
            column('application_identity', 'Medida y condiciones de esta aplicación',
                   required=True),
            column('dose_ml', 'Dosis por rueda', 'decimal', required=True,
                   unit='ml', positive=True),
            column('source_document', 'Documento y edición', required=True),
            column('source_url', 'Fuente', 'url', required=True)]}})
    # Stan's publishes different amounts for 29 x 2.3 and 29 x 2.5. Both are
    # MTB, so that category alone is not the application identity. Source URL
    # remains provenance rather than an extra way to duplicate the same recipe.
    key_rows(definitions, DOSES, ('application_scope', 'application_identity'))
    add_field(template, DOSES, 'declaration', 'declaration',
              helper='La dosis es de una aplicación, no del envase. Un frasco '
                     'de 60 ml puede servir a una dosis de 120 ml: se usan dos.')
    template['fields'] = [f for f in template['fields'] if f['key'] != DOSE]
    for section in ('roles', 'semantic_roles', 'allowed_when', 'required_when',
                    'prerequisites', 'evidence_requirements', 'helpers',
                    'labels', 'allowed_options'):
        contract.get(section, {}).pop(DOSE, None)

    # R-4a: el encargo autoriza clonar una definición compartida hacia una nueva
    # de alcance explícito. `kit_members` global se conserva **retirada** en esta
    # ficha —no se toca la definición publicada ni sus datos— y el sucesor sí
    # lleva llave: dos piezas distintas son dos filas, y el mismo miembro
    # documentado dos veces choca. La URL no entra en la llave.
    definitions[KIT] = new_definition(
        KIT, 'Componentes del kit tubeless', 'json', (CONSUMABLE,),
        rules={'rows_schema': {'version': 1, 'columns': [
            column('member_role', 'Componente', 'token', required=True,
                   options=MEMBER_ROLE),
            column('member_identity', 'Modelo y edición del componente',
                   required=True),
            column('quantity', 'Cantidad', 'integer', required=True,
                   positive=True),
            column('source_url', 'Fuente', 'url', required=True)]}})
    # The catalogue identity owns the family. A second free selector allowed
    # "sealant" + "workshop_tool" for the same member. This never-published
    # table now describes the component once; changing its role cannot bypass
    # duplicate content detection.
    key_rows(definitions, KIT, ('member_identity',))
    add_field(template, KIT, 'contents', 'contents',
              helper='Un componente por fila, con el modelo que el documento '
                     'nombra; «Sin identificar en el documento» es una respuesta.')
    retire(template, [MEMBERS])

    gate(template, {KIT: condition(KIND, CONVERSION_KIT)},
         required={KIT: deepcopy(NEVER)})
    # El volumen es un campo vivo con cifras publicadas: sólo se condiciona la
    # exigencia, nunca el permiso, para que ningún dato guardado se invalide.
    gate(template, {VOLUME: deepcopy(ALWAYS)},
         required={VOLUME: condition(KIND, [SEALANT, CONVERSION_KIT])})


def _valve(definitions, templates):
    """Qué es la válvula, y a qué agujero entra: dos preguntas, no una.

    El agujero es de la **llanta**, no de la válvula, y una válvula Presta en una
    llanta perforada para Schrader necesita un adaptador. Nada de eso se deriva
    de la medida: se declara con su fuente. Por eso el diámetro del agujero
    cuelga del tipo de válvula declarado y no al revés, y «Otra» vuelve al
    dominio para no confundir una válvula rara con una desconocida.
    """
    template = templates[VALVE]
    # Misma revisión: la forma de la base y el largo son medidas de la pieza que
    # se tiene en la mano. El diámetro del agujero, en cambio, es una
    # **declaración sobre la llanta**, así que se permite siempre, no se exige, y
    # debe su documento — pero tampoco se deduce del tipo de válvula.
    gate(template, {VALVE_SHAPE: deepcopy(ALWAYS), HOLE: deepcopy(ALWAYS),
                    VALVE_LEN: deepcopy(ALWAYS)},
         required={VALVE_SHAPE: deepcopy(ALWAYS), HOLE: deepcopy(NEVER),
                   VALVE_LEN: deepcopy(ALWAYS)})
    template['form_contract']['prerequisites'][HOLE] = [EVIDENCE]


def _adjudications():
    """Los tres «límites del motor» que reporté, adjudicados en el orden pedido.

    Ninguno sobrevive como carencia del motor. Dos eran míos, de dominio.
    """
    return [
        {'id': 'L-1', 'verdict': 'retirado: no era un límite del motor',
         'what_i_claimed': 'Que el motor no puede acotar una presión declarada '
                           'contra el techo publicado de 5 bar / 72 psi.',
         'why_it_was_wrong': [
             'Confundí tres magnitudes distintas. La **presión máxima declarada '
             'del neumático** es del neumático y vive en '
             '`tire_general_max_pressures`. El **límite del sistema o del '
             'modelo** es de una rueda concreta con su edición: Zipp lo enuncia '
             'para «Zipp TSS wheel and tire systems», no para la palabra '
             'hookless. Y la **presión real de uso** es de un montaje, que no '
             'es un hecho del SKU en ninguna de estas cinco fichas.',
             'Una cifra alta en la primera **no prueba** un montaje inflado por '
             'encima de la segunda: son dos afirmaciones sobre objetos '
             'distintos y no se contradicen.',
             'Extender Zipp y ENVE a todo hookless era una inferencia mía. Sus '
             'techos conservan su modelo, su edición y su alcance; fuera de él '
             'el resultado queda pendiente de una relación verificada, no '
             '«compatible».'],
         'what_replaced_it': 'La identidad de alcance de la fila '
                             '(`scope_kind` + `scope_identity`), que mantiene '
                             'cada límite pegado al modelo o la norma que lo '
                             'declara en vez de convertirlo en un techo global.',
         'sources': [ZIPP_HOOKLESS, ENVE_HOOKLESS]},
        {'id': 'L-3', 'verdict': 'retirado: no se pide un convertidor',
         'what_i_claimed': 'Que un par ordenado no compara bar contra psi.',
         'why_it_was_wrong': 'Es cierto que no los compara, y está bien que no '
                             'lo haga: dos autoridades en unidades distintas no '
                             'son automáticamente datos contradictorios. Pedir '
                             'una conversión en el motor era pedir que '
                             'adjudicara un conflicto que puede no existir. '
                             'Cada cifra conserva su unidad y su alcance.',
         'what_replaced_it': 'Nada que agregar al motor.',
         'sources': [ZIPP_HOOKLESS]},
        {'id': 'L-2', 'verdict': 'resuelto dentro del encargo',
         'what_i_claimed': 'Que `kit_members` no admite llave sin que root '
                           'migre una definición compartida.',
         'why_it_was_wrong': 'El encargo ya autorizaba clonar hacia una clave '
                             'nueva de alcance explícito. No hacía falta que '
                             'root tocara nada.',
         'what_replaced_it': '`tubeless_kit_members`, acotada a '
                             '`tubeless_consumable`, con llave '
                             '(componente, familia, identidad del modelo). La '
                             'publicada se conserva **retirada** en esta ficha: '
                             'ni la definición global ni sus datos se tocan. La '
                             'URL no entra en la llave.'}]


def _relation_integration():
    """Lo que sí falta, dicho con precisión: la integración, no otro motor.

    `ProductSpecRelation.evaluate`
    (`lib/modules/inventory/models/product_spec_relation.dart:78-132`) y
    `spec_relation_assess_internal_v1`
    (`supabase/migrations/20260906180000_product_spec_scoped_relations.sql:174`)
    **ya existen**, con evaluación OR sobre alternativas, AND dentro de cada
    fila, exclusiones que estrechan, desconocido preservado y —lo importante—
    un veredicto `outsideDeclaredScope` para el no-calce, con el comentario
    explícito de que no coincidir «is only outside this declaration, never a
    physical incompatibility proof».

    Yo afirmé en el bloque de piñonería que faltaba el evaluador. **Es falso**,
    y el error fue mío: busqué «relation» en el consumidor
    (`product_spec_contract.dart`) y no en el modelo. Lo que falta es que el
    veredicto de esa evaluación llegue a la validación de la ficha.
    """
    return {'evaluator_exists': True,
            'dart': 'lib/modules/inventory/models/product_spec_relation.dart:78',
            'sql': 'public.spec_relation_assess_internal_v1',
            'claims_live_on': 'product_spec_references.claims (§4.1), no en un '
                              'fact del producto',
            'missing': 'que `validateProductSpecDraft` consuma el veredicto de '
                       'la referencia elegida y lo exponga como incidencia',
            'owner': 'root / motor; no lo escribo'}


HOOKED = 'Con gancho (hooked)'
WITH_TUBE, TUBELESS = 'Con cámara', 'Tubeless'
PRESTA = 'Presta (francesa)'
UNKNOWN_VALVE = 'Desconocido'
OEM_SPEC = 'Especificación del fabricante del neumático'
LISTED, NOT_LISTED = 'La llanta lista este neumático', 'La llanta no lo lista'


def case(id_, family, values, *, blocking=(), pending=(), forbidden=(),
         sources=()):
    """El constructor compartido más la afirmación de que una compuerta calló.

    `forbidden_issue_fields` es lo que separa una compuerta que abre de una que
    simplemente no bloquea: sin eso un «positivo» pasa igual con el campo
    callado pendiente.
    """
    result = _case(id_, family, values, blocking=blocking, pending=pending,
                   sources=sources)
    # Observed against the deployed SQL validator in local rollback. SQL uses
    # the field-constraint envelope for these row-shape failures; severity and
    # owner match Dart. Keep the original Dart expectations intact.
    sql_constraints = {
        'ttx_the_same_bead_seat_twice_blocks',
        'ttx_an_inverted_tube_width_blocks',
        'ttx_the_same_application_dosed_twice_blocks',
        'ttx_the_same_documented_member_twice_blocks',
        'ttr_another_role_does_not_create_another_physical_member',
    }
    result['expected_sql_blocking'] = sorted([
        {**item, 'code': 'field_constraint' if id_ in sql_constraints else item['code']}
        for item in result['expected_blocking']], key=lambda i: (i['code'], i['field']))
    for item in result.get('expected_sql_issue_subset', []):
        if item['code'] == 'prerequisite':
            item['code'] = 'prerequisite_missing'
    if forbidden:
        result['forbidden_issue_fields'] = list(forbidden)
    return result


def config(profile=HOOKED, method=WITH_TUBE, basis=OEM_SPEC,
           kind='Modelo y edición de llanta', identity='Rim X (ed. 2026)',
           **extra):
    cells = {'scope_kind': kind, 'scope_identity': identity,
             'claim_basis': basis, 'rim_bead_profile': profile,
             'mounting_method': method, 'source_url': SYNTHETIC,
             'pressure_unit': 'psi', 'max_pressure': '85'}
    cells.update({k: v for k, v in extra.items() if v is not None})
    return cells


def tire(extra=None):
    values = {BSD: '622', 'tire_width_mm': '28', BEAD: 'Talón plegable',
              ETRTO: '28-622', EVIDENCE: 'Ficha sintética',
              CONFIGS: rows(config())}
    values.update(extra or {})
    return {k: v for k, v in values.items() if v is not None}


def member(role='Sellante', identity='Sellante A', quantity='1'):
    return {'member_role': role,
            'member_identity': identity, 'quantity': quantity,
            'source_url': SYNTHETIC}


def dose(scope='MTB tubeless', ml='120', identity='Aplicación sintética A'):
    return {'application_scope': scope, 'application_identity': identity, 'dose_ml': ml,
            'source_document': 'Manual sintético ed. 2026',
            'source_url': SYNTHETIC}


def _cases(definitions):
    """Positivo, negativo y desconocido por compuerta.

    Los cruces conocidos **sin** validación no viven aquí: root fue explícito en
    que afirmar `expected_blocking: []` sobre uno de ellos no lo convierte en un
    caso correcto. Están en `pending_cases`, con el resultado requerido.
    """
    return [
        # --- el número crítico y el alcance declarado -----------------------
        case('ttx_a_tire_ficha_with_its_iso_number_is_clean', TIRE, tire(),
             forbidden=[CONFIGS, ETRTO], sources=[SHELDON_SIZING]),
        case('ttx_a_tire_without_its_iso_number_is_incomplete', TIRE,
             tire({ETRTO: None}),
             pending=[('required_missing', ETRTO)], sources=[SHELDON_SIZING]),
        # R-2: dos modelos que comparten perfil y método son dos filas válidas.
        case('ttx_two_rim_models_sharing_profile_and_method_are_two_rows', TIRE,
             tire({CONFIGS: rows(
                 config(profile=HOOKLESS, method=TUBELESS,
                        identity='Rim A (ed. 2026)',
                        rim_internal_width_min_mm='21',
                        rim_internal_width_max_mm='25',
                        rim_maker_lists_this_tire=LISTED),
                 config(profile=HOOKLESS, method=TUBELESS,
                        identity='Rim B (ed. 2025)',
                        rim_internal_width_min_mm='23',
                        rim_internal_width_max_mm='30',
                        rim_maker_lists_this_tire=LISTED))}),
             forbidden=[CONFIGS], sources=[ZIPP_HOOKLESS]),
        case('ttx_the_same_scope_twice_blocks', TIRE,
             tire({CONFIGS: rows(config(), config(method=TUBELESS))}),
             blocking=[('row_shape', CONFIGS)]),
        # Otra URL sobre el mismo alcance no crea otro objeto.
        case('ttx_another_url_for_the_same_scope_is_still_one_scope', TIRE,
             tire({CONFIGS: rows(config(), config(source_url=SYNTHETIC + '/2'))}),
             blocking=[('row_shape', CONFIGS)]),
        case('ttx_a_configuration_without_its_source_is_incomplete', TIRE,
             tire({CONFIGS: rows({k: v for k, v in config().items()
                                  if k != 'source_url'})}),
             pending=[('row_incomplete', CONFIGS)]),
        case('ttx_a_configuration_without_its_scope_identity_is_incomplete', TIRE,
             tire({CONFIGS: rows({k: v for k, v in config().items()
                                  if k != 'scope_identity'})}),
             pending=[('row_incomplete', CONFIGS)]),
        # Antes esto bloqueaba, por una suposición mía: que sólo una llanta sin
        # gancho puede listar neumáticos. Sin fuente. Ahora es representable.
        case('ttx_a_hooked_row_may_carry_a_rim_maker_listing', TIRE,
             tire({CONFIGS: rows(config(rim_maker_lists_this_tire=LISTED))}),
             forbidden=[CONFIGS]),
        case('ttx_a_hookless_row_owes_the_rim_maker_listing', TIRE,
             tire({CONFIGS: rows(config(profile=HOOKLESS, method=TUBELESS,
                                        rim_internal_width_min_mm='21',
                                        rim_internal_width_max_mm='25'))}),
             pending=[('row_required_missing', CONFIGS)],
             sources=[ENVE_HOOKLESS]),
        case('ttx_a_hookless_row_owes_its_internal_width', TIRE,
             tire({CONFIGS: rows(config(profile=HOOKLESS, method=TUBELESS,
                                        rim_maker_lists_this_tire=LISTED))}),
             pending=[('row_required_missing', CONFIGS)],
             sources=[ENVE_HOOKLESS]),
        case('ttx_a_hooked_row_owes_no_internal_width', TIRE, tire(),
             forbidden=[CONFIGS], sources=[SHELDON_SIZING]),
        case('ttx_a_hookless_row_that_is_not_listed_is_representable', TIRE,
             tire({CONFIGS: rows(config(profile=HOOKLESS, method=TUBELESS,
                                        rim_internal_width_min_mm='21',
                                        rim_internal_width_max_mm='25',
                                        rim_maker_lists_this_tire=NOT_LISTED))}),
             forbidden=[CONFIGS], sources=[ZIPP_HOOKLESS]),
        # L-1 adjudicado: el máximo impreso del neumático y el límite de un
        # sistema con su modelo son dos objetos. Coexisten sin contradecirse.
        case('ttx_a_tire_max_and_a_system_limit_are_two_objects', TIRE,
             tire({PRESSURES: rows({'pressure_unit': 'psi',
                                    'max_pressure_value': '100',
                                    'declared_scope': 'Sin condición de llanta en el documento',
                                    'source_document': 'Flanco del neumático',
                                    'source_url': SYNTHETIC}),
                   CONFIGS: rows(config(profile=HOOKLESS, method=TUBELESS,
                                        kind='Modelo y edición de llanta',
                                        identity='Zipp 303 Firecrest (TSS)',
                                        rim_internal_width_min_mm='21',
                                        rim_internal_width_max_mm='25',
                                        rim_maker_lists_this_tire=LISTED,
                                        max_pressure='72'))}),
             forbidden=[CONFIGS, PRESSURES], sources=[ZIPP_HOOKLESS]),
        # La prohibición expresa de Zipp se apoya en la presión **mínima** que el
        # neumático exige. Sin esa cifra en la ficha, la regla no es evaluable.
        case('ttx_a_tire_may_declare_the_minimum_pressure_it_requires', TIRE,
             tire({PRESSURES: rows({'pressure_unit': 'psi',
                                    'max_pressure_value': '100',
                                    'min_pressure_value': '80',
                                    'declared_scope': 'Sin condición de llanta en el documento',
                                    'source_document': 'Flanco del neumático',
                                    'source_url': SYNTHETIC})}),
             forbidden=[PRESSURES], sources=[ZIPP_HOOKLESS]),
        case('ttx_an_inverted_internal_width_blocks', TIRE,
             tire({CONFIGS: rows(config(rim_internal_width_min_mm='25',
                                        rim_internal_width_max_mm='19'))}),
             blocking=[('row_shape', CONFIGS)]),
        case('ttx_a_tubular_tire_declares_no_tubeless_ready', TIRE,
             tire({BEAD: 'Tubular', TSS_READY: True}),
             blocking=[('field_applicability', TSS_READY)]),

        # --- la cámara calza por asiento y ancho ----------------------------
        case('ttx_the_same_bead_seat_twice_blocks', TUBE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '48',
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'},
                             {BSD: '622', 'width_min_mm': '28', 'width_max_mm': '32'})},
             blocking=[('row_shape', FIT_ROWS)], sources=[SHELDON_SIZING]),
        case('ttx_two_bead_seats_are_two_fits', TUBE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '48',
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'},
                             {BSD: '584', 'width_min_mm': '40', 'width_max_mm': '55'})},
             forbidden=[FIT_ROWS], sources=[SHELDON_SIZING]),
        case('ttx_an_inverted_tube_width_blocks', TUBE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '48',
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '32', 'width_max_mm': '25'})},
             blocking=[('row_shape', FIT_ROWS)]),
        case('ttx_an_unusual_valve_is_other_not_unknown', TUBE,
             {VALVE_STANDARD: OTHER_VALVE, VALVE_LEN: '40',
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'})},
             forbidden=[VALVE_STANDARD, VALVE_LEN]),
        # Con el sucesor, el desconocido vuelve a comportarse como una ausencia.
        # El largo es una medida de la pieza: no cuelga de la norma en ninguna
        # dirección, y se debe aunque la norma sea desconocida.
        case('ttx_an_unknown_valve_standard_still_owes_its_length', TUBE,
             {VALVE_STANDARD: UNKNOWN,
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'})},
             pending=[('required_missing', VALVE_LEN)]),
        case('ttx_an_unknown_valve_standard_does_not_forbid_its_length', TUBE,
             {VALVE_STANDARD: UNKNOWN, VALVE_LEN: '48',
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'})},
             forbidden=[VALVE_LEN]),
        # Si se sabe qué válvula es, se debe su largo: la exigencia es del
        # dominio, no un artificio para matar un mutante.
        case('ttx_a_tube_owes_its_valve_length', TUBE,
             {VALVE_STANDARD: PRESTA,
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'})},
             pending=[('required_missing', VALVE_LEN)]),
        # Park publica que su VC-1 saca e instala núcleos **Schrader** y que «not
        # all Presta valve cores are removable». El núcleo desmontable es de la
        # válvula, no de la norma: las cuatro combinaciones son representables y
        # ninguna se deduce del tipo.
        case('ttx_a_presta_tube_may_declare_a_removable_core', TUBE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '48', CORE: True,
              EVIDENCE: 'Ficha sintética',
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'})},
             forbidden=[CORE], sources=[PARK_VC1]),
        case('ttx_a_presta_tube_may_declare_a_fixed_core', TUBE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '48', CORE: False,
              EVIDENCE: 'Ficha sintética',
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'})},
             forbidden=[CORE], sources=[PARK_VC1]),
        case('ttx_a_schrader_tube_may_declare_a_removable_core', TUBE,
             {VALVE_STANDARD: 'Schrader (americana / auto)', VALVE_LEN: '35',
              CORE: True, EVIDENCE: 'Ficha sintética',
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'})},
             forbidden=[CORE], sources=[PARK_VC1]),
        # Para Dunlop la fuente calla, así que el contrato tampoco decide.
        case('ttx_a_dunlop_core_is_not_decided_by_its_standard', TUBE,
             {VALVE_STANDARD: 'Dunlop (inglesa)', VALVE_LEN: '40', CORE: True,
              EVIDENCE: 'Ficha sintética',
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'})},
             forbidden=[CORE]),
        case('ttx_a_core_claim_owes_its_document', TUBE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '48', CORE: True,
              FIT_ROWS: rows({BSD: '622', 'width_min_mm': '18', 'width_max_mm': '25'})},
             pending=[('prerequisite', CORE)], sources=[PARK_VC1]),

        # --- el fondo se elige por el interior de la llanta ------------------
        case('ttx_a_strip_fit_range_is_ordered', STRIP,
             {BSD: '622', STRIP_MATERIAL: 'Goma', STRIP_WIDTH: '20',
              STRIP_MIN: '17', STRIP_MAX: '25', HOLE: '6.5'},
             forbidden=[STRIP_MIN, STRIP_MAX, HOLE], sources=[PARK_CONVERSION]),
        case('ttx_an_inverted_strip_fit_blocks', STRIP,
             {BSD: '622', STRIP_MATERIAL: 'Goma', STRIP_WIDTH: '20',
              STRIP_MIN: '25', STRIP_MAX: '17'},
             blocking=[('range_order', STRIP_MIN), ('range_order', STRIP_MAX)]),
        case('ttx_a_strip_owes_its_width', STRIP,
             {BSD: '622', STRIP_MATERIAL: 'Goma'},
             pending=[('required_missing', STRIP_WIDTH)]),
        case('ttx_an_unknown_strip_material_still_owes_its_width', STRIP,
             {BSD: '622', STRIP_MATERIAL: UNKNOWN},
             pending=[('required_missing', STRIP_WIDTH)]),

        # --- la dosis es de una aplicación, no del envase --------------------
        # R-1: 120 ml en un frasco de 60 es legítimo. Se usan dos envases.
        case('ttx_a_dose_larger_than_the_bottle_is_legitimate', CONSUMABLE,
             {KIND: SEALANT, VOLUME: '60', DOSES: rows(dose(ml='120')),
              EVIDENCE: 'Ficha sintética'},
             forbidden=[VOLUME, DOSES]),
        case('ttx_the_same_application_dosed_twice_blocks', CONSUMABLE,
             {KIND: SEALANT, VOLUME: '500',
              DOSES: rows(dose(ml='120'), dose(ml='90'))},
             blocking=[('row_shape', DOSES)]),
        case('ttx_two_applications_are_two_doses', CONSUMABLE,
             {KIND: SEALANT, VOLUME: '500',
              DOSES: rows(dose('MTB tubeless', '120'),
                          dose('Ruta o gravel tubeless', '60'))},
             forbidden=[DOSES]),
        case('ttr_two_mtb_tire_sizes_keep_different_doses', CONSUMABLE,
             {KIND: SEALANT, VOLUME: '500', DOSES: rows(
                 {**dose(ml='118', identity='29 x 2.3'), 'source_url': STANS_DOSES},
                 {**dose(ml='148', identity='29 x 2.5'), 'source_url': STANS_DOSES})},
             forbidden=[DOSES], sources=[STANS_DOSES]),
        case('ttr_tyres_minimum_cannot_exceed_its_own_maximum', TIRE,
             tire({PRESSURES: rows({'pressure_unit': 'psi',
                 'min_pressure_value': '80', 'max_pressure_value': '72',
                 'declared_scope': 'Sin condición de llanta en el documento',
                 'source_document': 'Same synthetic tyre declaration',
                 'source_url': SYNTHETIC})}), blocking=[('row_shape', PRESSURES)]),
        case('ttx_a_plain_sealant_has_no_kit_members', CONSUMABLE,
             {KIND: SEALANT, VOLUME: '500', KIT: rows(member())},
             blocking=[('field_applicability', KIT)]),
        case('ttx_a_conversion_kit_may_list_its_members', CONSUMABLE,
             {KIND: CONVERSION_KIT, VOLUME: '500',
              KIT: rows(member(),
                        member(role='Válvula tubeless',
                               identity='Válvula 44 mm', quantity='2'))},
             forbidden=[KIT]),
        # R-4a: el mismo miembro documentado dos veces ya no pasa.
        case('ttx_the_same_documented_member_twice_blocks', CONSUMABLE,
             {KIND: CONVERSION_KIT, VOLUME: '500',
              KIT: rows(member(), member())},
             blocking=[('row_shape', KIT)]),
        case('ttr_another_role_does_not_create_another_physical_member', CONSUMABLE,
             {KIND: CONVERSION_KIT, KIT: rows(member(), member(role='Otro'))},
             blocking=[('row_shape', KIT)]),
        case('ttx_two_models_of_the_same_role_are_two_members', CONSUMABLE,
             {KIND: CONVERSION_KIT, VOLUME: '500',
              KIT: rows(member(identity='Sellante A'),
                        member(identity='Sellante B'))},
             forbidden=[KIT]),
        case('ttx_an_unknown_consumable_kind_flags_itself_not_the_volume',
             CONSUMABLE, {KIND: UNKNOWN, VOLUME: '500'},
             pending=[('required_missing', KIND)], forbidden=[VOLUME]),
        case('ttx_an_unknown_consumable_kind_does_not_demand_a_volume',
             CONSUMABLE, {KIND: UNKNOWN}, forbidden=[VOLUME]),

        # --- la válvula y el agujero de la llanta ---------------------------
        case('ttx_a_declared_valve_standard_opens_its_shape', VALVE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '60', VALVE_SHAPE: 'Cónica'},
             forbidden=[VALVE_SHAPE]),
        case('ttx_a_valve_owes_its_base_shape', VALVE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '60'},
             pending=[('required_missing', VALVE_SHAPE)]),
        case('ttx_an_unknown_valve_standard_still_owes_its_shape', VALVE,
             {VALVE_STANDARD: UNKNOWN, VALVE_LEN: '60'},
             pending=[('required_missing', VALVE_SHAPE)]),
        case('ttx_an_unknown_valve_standard_does_not_forbid_its_shape', VALVE,
             {VALVE_STANDARD: UNKNOWN, VALVE_LEN: '60', VALVE_SHAPE: 'Cónica'},
             forbidden=[VALVE_SHAPE]),
        case('ttx_a_rim_hole_without_its_source_is_pending', VALVE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '60', VALVE_SHAPE: 'Cónica',
              HOLE: '6.5'},
             pending=[('prerequisite', HOLE)], sources=[PARK_CONVERSION]),
        case('ttx_a_valve_pack_counts_its_units', VALVE,
             {VALVE_STANDARD: PRESTA, VALVE_LEN: '60', VALVE_SHAPE: 'Cónica',
              'pack_quantity': '2'},
             forbidden=['pack_quantity']),
    ]


def _pending_cases():
    """Carencias aceptadas, con el resultado **requerido**, fuera del lote verde.

    Corrección de root, y tenía razón: mi ronda anterior declaraba `excluded`
    para una llanta TSS que **no aparece** en la lista. Zipp dice lo contrario:
    «This list is not exhaustive of all TSS compatible tires and is provided as a
    convenience», y «If you are interested in a tire that is not listed here, you
    should check with the tire manufacturer». **No listado es ausencia de
    declaración**, no una prohibición — y tampoco es `supported`.

    La prohibición expresa que sí existe no es una lista, es una **regla con
    parámetro**: «Zipp TSS rims are NOT compatible with tires that require a
    minimum pressure higher than 5 bar (72 psi).» Esa es la única exclusión que
    esta reclamación declara, y se apoya en una cifra, no en una ausencia.
    """
    claim = {
        'schema_version': 2, 'interface': 'rim_bead_profile',
        'label': 'Llantas declaradas para este neumático',
        'alternatives': [
            {'id': 'tss_listed', 'label': 'Llanta TSS que lista este neumático',
             'conditions': [{'field': 'rim_bead_profile', 'operator': 'eq',
                             'value_type': 'token', 'value': HOOKLESS},
                            {'field': 'rim_maker_lists_this_tire',
                             'operator': 'eq', 'value_type': 'token',
                             'value': LISTED}],
             'sources': [ZIPP_HOOKLESS]}],
        'exclusions': [
            {'id': 'tss_min_pressure_over_ceiling',
             'label': 'Llanta TSS con un neumático que exige más de 72 psi',
             'conditions': [{'field': 'rim_bead_profile', 'operator': 'eq',
                             'value_type': 'token', 'value': HOOKLESS},
                            {'field': 'tire_min_pressure_psi',
                             'operator': 'gt', 'value_type': 'decimal',
                             'value': '72'}],
             'sources': [ZIPP_HOOKLESS]}]}
    # This is a synthetic model-scoped evaluation fixture, not a new reference
    # or an approval of all hookless rims. The Zipp statement must never apply
    # to an unidentified or different manufacturer's system.
    for row in claim['alternatives'] + claim['exclusions']:
        row['conditions'].insert(0, {'field': 'rim_documented_system',
            'operator': 'eq', 'value_type': 'token', 'value': 'Zipp TSS reference scope'})
    common = {'template': TIRE, 'kind': 'relation_integration_pending',
              'relation_claim': claim, 'runnable_against_templates': False,
              'evaluator': 'ProductSpecRelation.evaluate / '
                           'spec_relation_assess_internal_v1'}
    result = [
        {**common, 'id': 'ttp_a_listed_tss_rim_is_supported',
         'configuration': {'rim_bead_profile': HOOKLESS,
                           'rim_maker_lists_this_tire': LISTED,
                           'tire_min_pressure_psi': '40'},
         'required_verdict': 'supported', 'required_matched': ['tss_listed'],
         'reason': 'La alternativa coincide entera y ninguna exclusión aplica.',
         'source_urls': [ZIPP_HOOKLESS]},
        {**common, 'id': 'ttp_an_unlisted_tss_rim_is_outside_the_declaration',
         'configuration': {'rim_bead_profile': HOOKLESS,
                           'rim_maker_lists_this_tire': NOT_LISTED,
                           'tire_min_pressure_psi': '40'},
         'required_verdict': 'outsideDeclaredScope',
         'must_not_be': ['excluded', 'supported'],
         'reason': 'No aparecer en una lista que la propia fuente declara no '
                   'exhaustiva no prohíbe nada, y tampoco aprueba: la fuente '
                   'manda consultar al fabricante. Mi ronda anterior lo '
                   'declaraba `excluded`, y era falso.',
         'source_urls': [ZIPP_HOOKLESS]},
        {**common, 'id': 'ttp_a_tire_needing_more_than_the_ceiling_is_excluded',
         'configuration': {'rim_bead_profile': HOOKLESS,
                           'rim_maker_lists_this_tire': LISTED,
                           'tire_min_pressure_psi': '80'},
         'required_verdict': 'excluded',
         'reason': 'Prohibición **expresa** y con parámetro, no una ausencia: '
                   '«Zipp TSS rims are NOT compatible with tires that require a '
                   'minimum pressure higher than 5 bar (72 psi)». Estrecha '
                   'incluso cuando la alternativa positiva también coincide.',
         'source_urls': [ZIPP_HOOKLESS]},
        {**common, 'id': 'ttp_an_unanswered_minimum_pressure_stays_unknown',
         'configuration': {'rim_bead_profile': HOOKLESS,
                           'rim_maker_lists_this_tire': LISTED},
         'required_verdict': 'unknown',
         'required_unresolved': ['tire_min_pressure_psi'],
         'reason': 'Sin la presión mínima no se puede descartar la exclusión, y '
                   'una exclusión indeterminada no se resuelve como compatible.',
         'source_urls': [ZIPP_HOOKLESS]},
        {**common, 'id': 'ttp_a_tubular_rim_is_outside_the_declaration',
         'configuration': {'rim_bead_profile': 'Tubular / de pegar',
                           'tire_min_pressure_psi': '40'},
         'required_verdict': 'outsideDeclaredScope',
         'reason': 'No coincidir con una alternativa **no exhaustiva** no prueba '
                   'incompatibilidad física.',
         'source_urls': [PARK_TUBELESS]},
    ]
    for fixture in result:
        fixture['configuration']['rim_documented_system'] = 'Zipp TSS reference scope'
    result += [
        {**common, 'id': 'ttr_zipp_ceiling_does_not_exclude_another_system',
         'configuration': {'rim_documented_system': 'Different OEM scope',
             'rim_bead_profile': HOOKLESS, 'rim_maker_lists_this_tire': LISTED,
             'tire_min_pressure_psi': '80'},
         'required_verdict': 'outsideDeclaredScope',
         'must_not_be': ['excluded', 'supported']},
        {**common, 'id': 'ttr_unknown_system_cannot_be_approved',
         'configuration': {'rim_bead_profile': HOOKLESS,
             'rim_maker_lists_this_tire': LISTED, 'tire_min_pressure_psi': '40'},
         'required_verdict': 'unknown',
         'required_unresolved': ['rim_documented_system']},
        {**common, 'id': 'ttr_hooked_alone_is_not_a_tire_approval',
         'configuration': {'rim_documented_system': 'Different OEM scope',
             'rim_bead_profile': HOOKED, 'tire_min_pressure_psi': '40'},
         'required_verdict': 'outsideDeclaredScope',
         'must_not_be': ['supported']},
    ]
    return result


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-tires-tubes-catalog-2026-09-08.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-tires-tubes-cases-2026-09-08.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'pending_cases': len(fixtures['pending_cases']),
                      'live_shared': len(catalog['live_shared_definitions']),
                      'corrected_from_frozen': len(catalog['adopted_live_definitions']),
                      'order_collisions': catalog['option_order_collisions'],
                      'renames_declined': len(catalog['renames_declined']),
                      'adjudicated': len(catalog['adjudicated_limits'])}))
