#!/usr/bin/env python3
"""Compile an unpublished successor for shifter, rear and front derailleur.

No DB, migration, publication, assignment or product filling. Four axes stay
apart: the piece or occurrence inside the package, the interface the control
or the derailleur presents, how the mechanism is actuated, and what a document
claims about another model. Indexing lives in the control, so a derailleur
never carries friction or index as its own mechanism; a supplied claw is
contents on the axle, not a frame interface; and a brand, a speed count, a
cage or a clamp diameter is not universal compatibility.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import (
    add_field, case, condition, new_definition,
    remove_unpublished_field, rows)
from compile_wheel_small_parts_catalog import ALWAYS, NEVER, column, retire
from compile_combined_control_catalog import both
from compile_product_spec_catalog import validate_contract

FAMILIES = ('shifter', 'rear_derailleur', 'front_derailleur')
PREIMAGE = RESEARCH / 'existing-shifting-preimage-2026-09-08.json'
PREIMAGE_SHA = '9ed37fdd68e7cd21701d586751a796070ad8851d4fd19e39f5cfa729a9cf3b3e'
SHELDON_ADJ = 'https://www.sheldonbrown.com/derailer-adjustment.html'
PARK_RD = 'https://www.parktool.com/en-us/blog/repair-help/how-a-rear-derailleur-works'
PARK_FD = 'https://www.parktool.com/en-us/blog/repair-help/front-derailleur-adjustment'
SYNTHETIC = 'https://example.invalid/synthetic'
EVIDENCE = 'spec_evidence_source'
DOCUMENTED_MODEL = 'Modelo documentado'
DOCUMENTED_INTERFACE = 'Interfaz o estándar documentado'
SCOPES = [DOCUMENTED_MODEL, DOCUMENTED_INTERFACE]

INDEXED = 'Indexado'
FRICTION = 'Fricción'
SWITCHABLE = 'Conmutable entre indexado y fricción'
ELECTRONIC = 'Electrónico'
MODES = [INDEXED, FRICTION, SWITCHABLE, ELECTRONIC]
STYLES = ['Gatillo (trigger)', 'Giro (twist)', 'Palanca de pulgar',
          'Palanca en punta de manillar (bar-end)',
          'Palanca en tubo o soporte del cuadro',
          'Integrado con la maneta de freno',
          'Otro estilo documentado']
LEFT, RIGHT = 'Izquierdo (delantero)', 'Derecho (trasero)'  # renamed 2026-09-16 (20260916230000)
PAIR_TOKEN, UNIVERSAL = 'Par', 'Universal'


ADDED = set()


def _add(definitions, template, key, label, kind, *, role='measurement',
         semantic='compatibility', unit=None, options=(), rules=None,
         allowed=ALWAYS, required=NEVER, helper=None):
    if key in definitions:
        raise ValueError('Refuse to overwrite a definition: ' + key)
    ADDED.add(key)
    definitions[key] = new_definition(key, label, kind, (template['key'],),
                                      unit=unit, options=options, rules=rules)
    add_field(template, key, role, semantic, allowed=allowed,
              required=required, helper=helper)


def _retire(template, keys):
    retire(template, list(keys))
    for key in keys:
        template['form_contract']['semantic_roles'][key] = 'legacy'


def _drop(definitions, template, key):
    if definitions[key]['origin'] != 'new':
        raise ValueError('Cannot remove a published observation: ' + key)
    remove_unpublished_field(template, key)
    del definitions[key]


def _claim_columns(subject):
    """A documented claim: either a named model or a declared interface."""
    return [
        column('claim_identity', 'Identificación de esta declaración', required=True),
        column('scope_kind', 'Alcance de la declaración', 'token',
               required=True, options=SCOPES),
        column('brand', 'Marca ' + subject),
        column('model', 'Modelo ' + subject),
        column('generation', 'Generación o edición'),
        column('years', 'Años documentados'),
        column('declared_interface', 'Interfaz o estándar declarado'),
        column('conditions', 'Condiciones de la declaración'),
        column('source_document', 'Documento o envase identificado', required=True),
        column('source_url', 'URL del documento, si existe', 'url'),
    ]


def _claim_conditions():
    model = condition('scope_kind', DOCUMENTED_MODEL)
    interface = condition('scope_kind', DOCUMENTED_INTERFACE)
    return {'allowed_when': {'brand': deepcopy(model), 'model': deepcopy(model),
                             'declared_interface': deepcopy(interface)},
            'required_when': {'brand': deepcopy(model), 'model': deepcopy(model),
                              'declared_interface': deepcopy(interface)}}


CLAIM_HELPER = (
    'Declaraciones documentadas de la fuente. Cuando el documento no enumera '
    'modelos se declara la interfaz o el estándar; no se inventa un nombre '
    'para llenar la celda, y un año ausente en la fuente se deja ausente. '
    'Una declaración no convierte a esta pieza en compatible con todo lo que '
    'comparta marca o número de velocidades.')


def _claims(definitions, template, key, label, subject, helper=CLAIM_HELPER):
    _add(definitions, template, key, label, 'json', role='declaration',
         semantic='compatibility', helper=helper,
         rules={'rows_schema': {'version': 1, 'unique_by': [['claim_identity']],
                                'columns': _claim_columns(subject)}})
    c = template['form_contract']
    c.setdefault('row_conditions', {'version': 1, 'fields': {}})
    c['row_conditions']['fields'][key] = _claim_conditions()
    c['prerequisites'][key] = [EVIDENCE]


def compile_catalog():
    for path, expected in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA),
                           (PREIMAGE, PREIMAGE_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Pinned input changed: ' + path.name)
    base = json.loads(CATALOG.read_text())
    before = json.loads(PREIMAGE.read_text())
    published = {d['key']: d for d in before['existing_definitions']}
    names = {t['key']: t['name'] for t in before['templates']}

    templates, definitions = {}, {}
    for key in FAMILIES:
        template = deepcopy(next(t for t in base['templates'] if t['key'] == key))
        template['name'] = names[key]
        templates[key] = template
        for field in template['fields']:
            definitions.setdefault(field['key'],
                                   deepcopy(base['definitions'][field['key']]))
    for key, actual in published.items():
        if key not in definitions:
            continue
        definitions[key] = {k: deepcopy(actual[k]) for k in (
            'id', 'key', 'label', 'data_type', 'unit', 'allowed_values',
            'validation_rules')}
        definitions[key].update(origin='existing', used_by=[
            f for f in FAMILIES
            if any(x['key'] == key for x in templates[f]['fields'])])
    known = set(base['definitions'])

    _shifter(definitions, templates['shifter'])
    _rear(definitions, templates['rear_derailleur'])
    _front(definitions, templates['front_derailleur'])

    for key in ADDED:
        if key in known:
            raise ValueError('New key collides with the catalogue: ' + key)
    for key in FAMILIES:
        template = templates[key]
        validate_contract(key, template['form_contract'], definitions,
                          {f['key'] for f in template['fields']})
    owned = {f['key'] for t in templates.values() for f in t['fields']}
    if set(definitions) != owned:
        raise ValueError('Unowned definitions in shifting packet')

    catalog = {**base,
               'title': 'Shifter and derailleur pieces, actuation and claims',
               'templates': [templates[k] for k in FAMILIES],
               'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA,
                                'preimage': PREIMAGE_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False,
               'source_urls': [SHELDON_ADJ, PARK_RD, PARK_FD],
               'stats': {'templates': len(FAMILIES),
                         'definitions': len(definitions),
                         'field_uses': sum(len(t['fields'])
                                           for t in templates.values())}}
    return catalog, {'cases': _cases(), 'pending_cases': _pending()}


def _shifter(definitions, template):
    c = template['form_contract']
    # Two units in one package are two pieces: Park describes the index
    # shifter as the part that moves the cable a predetermined amount per
    # click, so a package holding a left and a right control holds two
    # different mechanisms and cannot answer with one scalar.
    individual = condition('shifter_position', [LEFT, RIGHT, UNIVERSAL])
    pair = condition('shifter_position', PAIR_TOKEN)
    # A published selector already separates the piece from the package.
    c['helpers']['shifter_position'] = (
        'Qué trae este envase: un mando de un lado, un mando universal, o el '
        'par completo. Con «Par» las medidas de cada mando se declaran en su '
        'tabla, porque los dos mandos del mismo envase no comparten '
        'velocidades ni mecanismo.')
    # Sheldon: the detents that provide indexing are in the shifters. The
    # control owns the mode; the derailleur it drives does not.
    _add(definitions, template, 'shifter_actuation_mode',
         'Cómo acciona este mando', 'single_select', role='primary',
         semantic='intrinsic', options=MODES, allowed=deepcopy(individual),
         helper='Los topes que producen el indexado están en el mando, no en '
         'el cambio. Un mando de fricción no tiene posiciones indexadas y un '
         'mando conmutable las tiene sólo en su posición indexada.')
    _add(definitions, template, 'shifter_control_style',
         'Estilo de la palanca', 'single_select', role='primary',
         semantic='intrinsic', options=STYLES, allowed=deepcopy(individual),
         helper='Cómo se opera la palanca. Es una forma de mando, no una '
         'compatibilidad: dos gatillos distintos no son intercambiables por '
         'ser gatillos. Un mando integrado con la maneta de freno pertenece a '
         'la familia de mando combinado, y esa reasignación se hace con '
         'evidencia del producto, no por el título.')
    indexed = both(deepcopy(individual),
                   condition('shifter_actuation_mode', [INDEXED, SWITCHABLE]))
    c['allowed_when']['shifter_indexed_positions'] = deepcopy(indexed)
    c['required_when']['shifter_indexed_positions'] = deepcopy(indexed)
    c['helpers']['shifter_indexed_positions'] = (
        'Posiciones indexadas de este mando. No es el número de velocidades '
        'del grupo ni de la piñonería que hay montada.')
    c['allowed_when']['handlebar_clamp_mm'] = deepcopy(individual)
    c['helpers']['handlebar_clamp_mm'] = (
        'Diámetro del manillar que abraza este mando. En un par, cada mando '
        'declara el suyo en la tabla de unidades.')
    _add(definitions, template, 'shifter_unit_count',
         'Cuántos mandos trae el envase', 'number', role='primary',
         semantic='contents', rules={'integer': True, 'min': 2},
         allowed=deepcopy(pair), required=deepcopy(pair),
         helper='Se cuenta lo que trae el envase, no las velocidades. Un par '
         'declara al menos dos mandos y cada uno ocupa su propia fila.')
    _add(definitions, template, 'shifter_units',
         'Mandos que trae el envase', 'json', role='primary',
         semantic='contents', allowed=deepcopy(pair), required=deepcopy(pair),
         helper='Un mando por fila, con su lado, su mecanismo y su documento. '
         'Los dos mandos de un par pueden tener distinto número de '
         'velocidades y distinto accionamiento; no se promedian ni se '
         'copian.',
         rules={'rows_schema': {
             'version': 1, 'unique_by': [['unit_side']], 'columns': [
                 column('unit_identity', 'Identificación de este mando', required=True),
                 column('unit_side', 'Lado de este mando', 'token',
                        required=True, options=[LEFT, RIGHT]),
                 column('control_style', 'Estilo de la palanca', 'token', options=STYLES),
                 column('actuation_mode', 'Cómo acciona', 'token', options=MODES),
                 column('indexed_positions', 'Posiciones indexadas', 'integer',
                        positive=True),
                 column('declared_speeds', 'Velocidades que declara el documento'),
                 column('handlebar_clamp_mm', 'Diámetro de manillar', 'decimal',
                        unit='mm', positive=True),
                 column('source_document', 'Documento o envase identificado',
                        required=True),
                 column('source_url', 'URL del documento, si existe', 'url')]}})
    c['row_conditions'] = {'version': 1, 'fields': {'shifter_units': {
        'allowed_when': {'indexed_positions':
                         condition('actuation_mode', [INDEXED, SWITCHABLE])},
        'required_when': {'indexed_positions':
                          condition('actuation_mode', [INDEXED, SWITCHABLE])}}}}
    c['row_coherence'] = {'version': 2, 'links': [], 'cardinalities': [
        {'id': 'documented_shifters_in_the_package', 'field': 'shifter_units',
         'total_field': 'shifter_unit_count'}]}
    # The published claim table requires a URL in every row and cannot hold a
    # claim whose only source is the package, nor an interface-scoped claim.
    # It is retired with its observations and replaced, never reshaped.
    _retire(template, ['drivetrain_speeds', 'front_chainring_count',
                       'drivetrain_primary_ecosystem',
                       'derailleur_models_compatible', 'kit_members'])
    _drop(definitions, template, 'shifter_mechanism')
    _claims(definitions, template, 'shifter_compatibility_claims',
            'Cambios o interfaces declarados', 'del cambio')
    for key in ('shifter_actuation_mode', 'shifter_control_style',
                'shifter_indexed_positions', 'handlebar_clamp_mm',
                'shifter_units'):
        c['prerequisites'][key] = [EVIDENCE]


def _rear(definitions, template):
    c = template['form_contract']
    _retire(template, ['drivetrain_speeds', 'drivetrain_primary_ecosystem'])
    _drop(definitions, template, 'shifter_models_compatible')
    # Sheldon documents that Rapid Rise derailers work the opposite way. The
    # rest direction is a property of this derailleur; it is not a clutch and
    # it is not the actuation family it belongs to.
    _add(definitions, template, 'rear_derailleur_spring_return',
         'Sentido de retorno del resorte', 'single_select', role='primary',
         semantic='intrinsic', options=['Retorno normal (top normal)',
             'Retorno inverso (low normal / Rapid Rise)',
             'Otro retorno documentado'],
         helper='Hacia dónde vuelve el cambio cuando se suelta el cable. Un '
         'cambio de retorno inverso se ajusta al revés y no es intercambiable '
         'con uno normal aunque comparta marca y velocidades.')
    _add(definitions, template, 'rear_derailleur_actuation_ratio_declaration',
         'Relación de accionamiento declarada', 'text', role='declaration',
         semantic='declaration',
         helper='La relación entre cable recogido y desplazamiento que declara '
         'el documento del fabricante, transcrita tal cual. El nombre '
         'comercial de un sistema no es una relación, y esta ficha no la '
         'deduce del número de velocidades.')
    # A claw held by the axle nut is a piece the package supplies; it does not
    # turn the frame into a direct-mount frame.
    supplied = 'rear_derailleur_supplied_mount_adapter'
    _add(definitions, template, supplied,
         'El envase trae una uña o adaptador de montaje', 'boolean',
         role='primary', semantic='contents',
         helper='Una uña se sostiene con la tuerca del eje o el cierre rápido: '
         'es una pieza que viene en el envase. Que venga no cambia la interfaz '
         'que el cuadro ofrece.')
    _add(definitions, template, 'rear_derailleur_supplied_adapter_reference',
         'Referencia de la uña o adaptador incluido', 'text',
         role='measurement', semantic='contents',
         allowed=condition(supplied, True, 'boolean'),
         helper='Cómo identifica el documento a esa pieza incluida. Sin pieza '
         'incluida no hay referencia que declarar.')
    c['helpers']['rear_derailleur_mount_type'] = (
        'Cómo se monta este cambio en el cuadro. «Con uña / claw» describe un '
        'cambio que se sujeta al eje porque el cuadro no ofrece patilla; que '
        'el envase incluya una uña se declara aparte, en el contenido.')
    c['helpers']['derailleur_clutch'] = (
        'Si el documento declara embrague de cadena. Un nombre de familia o de '
        'diseño del cuerpo no prueba que lo tenga.')
    c['helpers']['rear_derailleur_total_capacity_teeth'] = (
        'Capacidad total que publica el fabricante para este cambio. No se '
        'calcula sumando rangos de otras piezas.')
    c['helpers']['derailleur_cage_length'] = (
        'Largo de jaula que publica el fabricante. La jaula acota la capacidad '
        'del modelo; no declara compatibilidad con un mando ni con un grupo.')
    _claims(definitions, template, 'rear_derailleur_compatibility_claims',
            'Mandos, piñones o interfaces declarados', 'del mando o piñón')
    for key in ('rear_derailleur_spring_return',
                'rear_derailleur_actuation_ratio_declaration',
                supplied, 'rear_derailleur_supplied_adapter_reference'):
        c['prerequisites'][key] = [EVIDENCE]


def _front(definitions, template):
    c = template['form_contract']
    # The published clamp selector holds one diameter. Three of the fifteen
    # records in scope name two diameters and five name one, so the single
    # value is retired and the occurrences own the answer.
    _retire(template, ['front_chainring_count', 'drivetrain_speeds',
                       'drivetrain_primary_ecosystem',
                       'front_derailleur_pull_direction',
                       'front_derailleur_clamp_mm'])
    clamp = condition('front_derailleur_mount_type', ['Abrazadera', 'Otro'])
    _add(definitions, template, 'front_derailleur_clamp_options',
         'Diámetros de abrazadera que admite el envase', 'json',
         role='primary', semantic='contents',
         allowed=deepcopy(clamp),
         required=condition('front_derailleur_mount_type', 'Abrazadera'),
         helper='Un diámetro por fila, diciendo si necesita adaptador y si ese '
         'adaptador viene en el envase. Un envase que trae reducciones admite '
         'varios diámetros: eso es contenido documentado, no una medida única.',
         rules={'rows_schema': {
             'version': 1, 'unique_by': [['clamp_diameter_mm']], 'columns': [
                 column('option_identity', 'Identificación de esta opción', required=True),
                 column('clamp_diameter_mm', 'Diámetro de abrazadera', 'decimal',
                        required=True, unit='mm', positive=True),
                 column('adapter_state', 'Adaptador', 'token', required=True,
                        options=['Sin adaptador', 'Adaptador incluido en el envase',
                                 'Adaptador requerido y no incluido']),
                 column('source_document', 'Documento o envase identificado',
                        required=True),
                 column('source_url', 'URL del documento, si existe', 'url')]}})
    # Sheldon: new models are optimized for particular ratios. The designed
    # range is two ends, not one number.
    _add(definitions, template, 'front_derailleur_min_chainring_teeth',
         'Plato menor de diseño', 'number', unit='T',
         rules={'positive': True, 'integer': True},
         helper='Plato más chico para el que el fabricante diseñó esta jaula. '
         'Un desviador optimizado para unos platos no trabaja bien con otros, '
         'aunque el número de platos coincida.')
    c['helpers']['max_chainring_teeth'] = (
        'Plato mayor de diseño que publica el fabricante para este desviador.')
    c['scalar_ordered_pairs'] = [['front_derailleur_min_chainring_teeth',
                                  'max_chainring_teeth']]
    # Sheldon: run outside the anchor bolt and the cage moves less far for a
    # given cable movement. That is a setting the document declares, and it is
    # not the routing of the cable to the derailleur.
    _add(definitions, template, 'front_derailleur_cable_anchor',
         'Posición documentada del cable en el perno', 'single_select',
         role='declaration', semantic='declaration',
         options=['Anclaje interior del perno', 'Anclaje exterior del perno',
                  'Ambas posiciones documentadas', 'Otra posición documentada'],
         helper='De qué lado del perno pasa el cable según el documento. '
         'Cambia cuánto se mueve la jaula por cada milímetro de cable, y por '
         'eso no es lo mismo que la dirección desde la que llega el cable.')
    c['helpers']['front_derailleur_cable_pull'] = (
        'Desde dónde llega el cable al desviador. No describe la geometría de '
        'la jaula ni dónde está el pivote.')
    c['helpers']['front_derailleur_swing'] = (
        'Dónde está el pivote de la jaula. Es una geometría del cuerpo, no la '
        'ruta del cable: un título que dice «top pull» no dice si es top swing.')
    c['helpers']['front_derailleur_mount_type'] = (
        'Cómo se sujeta al cuadro. Park distingue el soporte braze-on del '
        'cuadro de una abrazadera propia del desviador.')
    _claims(definitions, template, 'front_derailleur_compatibility_claims',
            'Transmisiones o interfaces declaradas', 'de la transmisión')
    for key in ('front_derailleur_clamp_options', 'front_derailleur_cable_anchor',
                'front_derailleur_min_chainring_teeth', 'max_chainring_teeth',
                'front_derailleur_cable_pull', 'front_derailleur_swing'):
        c['prerequisites'][key] = [EVIDENCE]


def _cases():
    def build(prefix, family, i, v, forbidden=(), **k):
        result = case(prefix + i, family, v, **k)
        if forbidden:
            result['forbidden_issue_fields'] = list(forbidden)
        return result

    def sh(i, v, **k): return build('sh_', 'shifter', i, v, **k)
    def rd(i, v, **k): return build('rd_', 'rear_derailleur', i, v, **k)
    def fd(i, v, **k): return build('fd_', 'front_derailleur', i, v, **k)

    def unit(side, mode, **extra):
        return {'unit_identity': 'Mando ' + side, 'unit_side': side,
                'actuation_mode': mode, 'source_document': 'Envase identificado',
                **extra}

    def claim(identity, scope, **extra):
        return {'claim_identity': identity, 'scope_kind': scope,
                'source_document': 'Documento identificado', **extra}

    model_claim = claim('Modelo declarado', DOCUMENTED_MODEL,
                        brand='Marca declarada', model='Modelo declarado')
    interface_claim = claim('Interfaz declarada', DOCUMENTED_INTERFACE,
                            declared_interface='Interfaz declarada')
    bad_claim = claim('Interfaz con modelo', DOCUMENTED_INTERFACE,
                      declared_interface='Interfaz declarada', model='Modelo')
    left = unit(LEFT, FRICTION, declared_speeds='3')
    right = unit(RIGHT, INDEXED, indexed_positions='7', declared_speeds='7')
    single = {'shifter_position': LEFT, EVIDENCE: SYNTHETIC,
              'shifter_control_style': 'Gatillo (trigger)'}
    pair = {'shifter_position': PAIR_TOKEN, EVIDENCE: SYNTHETIC}
    both_units = {**pair, 'shifter_unit_count': '2',
                  'shifter_units': rows(left, right)}
    rear = {'compatible_rear_speeds': ['9'], EVIDENCE: SYNTHETIC,
            'rear_derailleur_mount_type': 'Pata/postiza estándar'}
    front = {'compatible_chainring_counts': ['2'], EVIDENCE: SYNTHETIC,
             'front_derailleur_mount_type': 'Abrazadera'}
    clamps = rows(
        {'option_identity': '31.8 directa', 'clamp_diameter_mm': '31.8',
         'adapter_state': 'Sin adaptador', 'source_document': 'Envase identificado'},
        {'option_identity': '34.9 con reducción', 'clamp_diameter_mm': '34.9',
         'adapter_state': 'Adaptador incluido en el envase',
         'source_document': 'Envase identificado'})
    return [
        # A control owns its own mode; the package owns how many controls.
        sh('an_individual_indexed_shifter_names_its_positions',
           {**single, 'shifter_actuation_mode': INDEXED,
            'shifter_indexed_positions': '8'}, sources=[PARK_RD]),
        sh('a_friction_shifter_has_no_indexed_positions',
           {**single, 'shifter_actuation_mode': FRICTION,
            'shifter_indexed_positions': '8'},
           blocking=[('field_applicability', 'shifter_indexed_positions')],
           sources=[SHELDON_ADJ]),
        sh('an_indexed_shifter_without_its_positions_is_pending',
           {**single, 'shifter_actuation_mode': INDEXED},
           pending=[('required_missing', 'shifter_indexed_positions')]),
        sh('a_switchable_shifter_still_declares_its_indexed_positions',
           {**single, 'shifter_actuation_mode': SWITCHABLE,
            'shifter_indexed_positions': '6'}, sources=[SHELDON_ADJ]),
        sh('a_pair_cannot_carry_one_scalar_count',
           {**pair, 'shifter_indexed_positions': '7'},
           blocking=[('field_applicability', 'shifter_indexed_positions')]),
        sh('a_pair_cannot_carry_one_scalar_clamp',
           {**pair, 'handlebar_clamp_mm': '22.2'},
           blocking=[('field_applicability', 'handlebar_clamp_mm')]),
        sh('a_pair_lists_two_units_with_different_mechanisms', both_units,
           sources=[SHELDON_ADJ]),
        sh('the_same_side_twice_blocks',
           {**pair, 'shifter_unit_count': '2',
            'shifter_units': rows(right, dict(right))},
           blocking=[('row_shape', 'shifter_units')]),
        sh('a_friction_unit_has_no_indexed_positions',
           {**pair, 'shifter_unit_count': '2',
            'shifter_units': rows(unit(LEFT, FRICTION, indexed_positions='3'), right)},
           blocking=[('row_field_applicability', 'shifter_units')]),
        sh('a_pair_without_its_count_is_pending',
           {**pair, 'shifter_units': rows(left, right)},
           pending=[('row_cardinality_pending', 'shifter_units')]),
        sh('a_unit_without_its_document_is_pending',
           {**pair, 'shifter_unit_count': '2', 'shifter_units': rows(
               {k: v for k, v in left.items() if k != 'source_document'}, right)},
           pending=[('row_incomplete', 'shifter_units')]),
        sh('an_individual_cannot_list_package_units',
           {**single, 'shifter_position': UNIVERSAL,
            'shifter_units': rows(left, right)},
           blocking=[('field_applicability', 'shifter_units')]),
        sh('a_claim_names_a_model_or_an_interface',
           {**single, 'shifter_compatibility_claims':
            rows(model_claim, interface_claim)}),
        sh('a_model_claim_without_its_model_is_pending',
           {**single, 'shifter_compatibility_claims': rows(
               claim('Sin modelo', DOCUMENTED_MODEL, brand='Marca declarada'))},
           pending=[('row_required_missing', 'shifter_compatibility_claims')]),
        sh('an_interface_claim_cannot_name_a_model',
           {**single, 'shifter_compatibility_claims': rows(bad_claim)},
           blocking=[('row_field_applicability', 'shifter_compatibility_claims')]),
        sh('the_platform_declaration_needs_its_evidence',
           {'shifter_position': LEFT, 'drivetrain_platform': 'Shimano HG / SIS'},
           pending=[('prerequisite', 'drivetrain_platform')]),
        # The derailleur answers for its own body, never for the control.
        rd('a_rear_derailleur_names_its_range_and_mount',
           {**rear, 'rear_derailleur_min_teeth': '11',
            'rear_derailleur_max_teeth': '36',
            'rear_derailleur_total_capacity_teeth': '37',
            'derailleur_cage_length': 'SGS / larga',
            'rear_derailleur_spring_return': 'Retorno normal (top normal)'}),
        rd('an_inverted_teeth_range_blocks',
           {**rear, 'rear_derailleur_min_teeth': '36',
            'rear_derailleur_max_teeth': '11'},
           blocking=[('range_order', 'rear_derailleur_min_teeth'),
                     ('range_order', 'rear_derailleur_max_teeth')]),
        rd('the_largest_cog_must_be_a_whole_tooth_count',
           {**rear, 'rear_derailleur_max_teeth': '36.5'},
           blocking=[('integer', 'rear_derailleur_max_teeth')]),
        rd('a_supplied_claw_is_contents_not_the_frame_interface',
           {**rear, 'rear_derailleur_supplied_mount_adapter': True,
            'rear_derailleur_supplied_adapter_reference': 'Uña identificada'},
           forbidden=['rear_derailleur_mount_type'], sources=[SHELDON_ADJ]),
        rd('an_adapter_reference_without_the_adapter_blocks',
           {**rear, 'rear_derailleur_supplied_mount_adapter': False,
            'rear_derailleur_supplied_adapter_reference': 'Uña identificada'},
           blocking=[('field_applicability',
                      'rear_derailleur_supplied_adapter_reference')]),
        rd('an_inverse_spring_return_is_not_a_clutch',
           {**rear, 'derailleur_clutch': False, 'rear_derailleur_spring_return':
            'Retorno inverso (low normal / Rapid Rise)'},
           forbidden=['derailleur_clutch'], sources=[SHELDON_ADJ]),
        rd('a_declared_ratio_without_evidence_is_pending',
           {'compatible_rear_speeds': ['9'],
            'rear_derailleur_mount_type': 'Pata/postiza estándar',
            'rear_derailleur_actuation_ratio_declaration': 'Relación declarada'},
           pending=[('prerequisite', 'rear_derailleur_actuation_ratio_declaration')]),
        rd('a_rear_derailleur_without_its_mount_is_pending',
           {EVIDENCE: SYNTHETIC},
           pending=[('required_missing', 'rear_derailleur_mount_type'),
                    ('required_missing', 'compatible_rear_speeds')]),
        rd('an_interface_claim_cannot_name_a_model',
           {**rear, 'rear_derailleur_compatibility_claims': rows(bad_claim)},
           blocking=[('row_field_applicability',
                      'rear_derailleur_compatibility_claims')]),
        # The front derailleur answers with occurrences, not one diameter.
        fd('a_clamp_derailleur_lists_the_diameters_it_admits',
           {**front, 'front_derailleur_clamp_options': clamps}),
        fd('a_braze_on_derailleur_has_no_clamp_options',
           {**front, 'front_derailleur_mount_type': 'Braze-on',
            'front_derailleur_clamp_options': clamps},
           blocking=[('field_applicability', 'front_derailleur_clamp_options')],
           sources=[PARK_FD]),
        fd('a_clamp_derailleur_without_its_options_is_pending', front,
           pending=[('required_missing', 'front_derailleur_clamp_options')]),
        fd('the_same_clamp_diameter_twice_blocks',
           {**front, 'front_derailleur_clamp_options': rows(
               {'option_identity': 'Primera', 'clamp_diameter_mm': '31.8',
                'adapter_state': 'Sin adaptador',
                'source_document': 'Envase identificado'},
               {'option_identity': 'Segunda', 'clamp_diameter_mm': '31.8',
                'adapter_state': 'Adaptador incluido en el envase',
                'source_document': 'Envase identificado'})},
           blocking=[('row_shape', 'front_derailleur_clamp_options')]),
        fd('a_clamp_option_without_its_adapter_state_is_pending',
           {**front, 'front_derailleur_clamp_options': rows(
               {'option_identity': 'Sin declarar', 'clamp_diameter_mm': '31.8',
                'source_document': 'Envase identificado'})},
           pending=[('row_incomplete', 'front_derailleur_clamp_options')]),
        fd('an_inverted_chainring_range_blocks',
           {**front, 'front_derailleur_clamp_options': clamps,
            'front_derailleur_min_chainring_teeth': '48',
            'max_chainring_teeth': '34'},
           blocking=[('range_order', 'front_derailleur_min_chainring_teeth'),
                     ('range_order', 'max_chainring_teeth')],
           sources=[SHELDON_ADJ]),
        fd('the_cable_route_is_not_the_cage_geometry',
           {**front, 'front_derailleur_clamp_options': clamps,
            'front_derailleur_cable_pull': 'Top pull',
            'front_derailleur_swing': 'Side swing',
            'front_derailleur_cable_anchor': 'Anclaje exterior del perno'},
           forbidden=['front_derailleur_cable_pull', 'front_derailleur_swing'],
           sources=[SHELDON_ADJ]),
        fd('the_retired_single_clamp_no_longer_answers',
           {**front, 'front_derailleur_clamp_options': clamps,
            'front_derailleur_clamp_mm': '31.8'},
           forbidden=['front_derailleur_clamp_mm']),
    ]


def _pending():
    return [
        {'id': 'combined_shift_and_brake_controls_belong_to_their_family',
         'required_result': 'assignment_pending',
         'reason': 'Several records in scope are combined shift/brake units. '
                   'The brake_shift_combined_control family already exists; '
                   'the move needs the assignment queue and product evidence, '
                   'not a reading of the title.'},
        {'id': 'shifter_and_derailleur_codes_belong_to_the_product',
         'required_result': 'identity_pending',
         'reason': 'Titles carry manufacturer codes while model and '
                   'manufacturer_sku are empty in almost every record. '
                   'Identity is resolved in the product, never in a second '
                   'store here.'},
        {'id': 'index_or_friction_in_a_title_is_a_reading_hint',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'Some titles spell out Index or Friccion. The actuation '
                   'mode is a property of the control and is filled from the '
                   'package or the manual, never from the title.'},
        {'id': 'a_body_design_name_does_not_prove_a_clutch',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'A design or family name in a title says nothing about a '
                   'chain stabiliser; derailleur_clutch stays unknown until a '
                   'document declares it.'},
        {'id': 'several_clamp_diameters_in_a_title_need_the_package',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'Titles declare two or three clamp diameters. Whether the '
                   'reduction ships in the box is a fact of the package and '
                   'is not inferred from the range written in the name.'},
        {'id': 'oem_manuals_were_not_reachable_in_this_round',
         'required_result': 'unknown_without_model_scoped_manual',
         'reason': 'The manufacturer technical sites answered 403 or 404 in '
                   'this round, so no actuation ratio, capacity or clamp '
                   'table is transcribed from a manual that was not opened.'},
        {'id': 'oem_relation_and_editor_validation_pending',
         'required_result': 'unknown_without_model_scoped_evidence',
         'reason': 'Directed OEM relations and the real editor round are not '
                   'exercised by this packet.'},
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'existing-shifting-catalog-2026-09-08.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'existing-shifting-cases-2026-09-08.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases']),
                      'pending_cases': len(fixtures['pending_cases']),
                      'production_writes': False, 'fill': False}))
