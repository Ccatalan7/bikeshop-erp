#!/usr/bin/env python3
"""Compile reviewed field metadata without writing the database or product facts.

The Claude source stays immutable. Only individually accepted patches and the
explicit Codex corrections below enter this artifact. Mechanical proposals and
synthetic fixtures remain separate and cannot become compatibility decisions.
"""
from __future__ import annotations

import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import uuid

from product_spec_row_condition_metadata import validate_row_conditions
from product_spec_row_cardinality_metadata import row_coherence_links, validate_row_cardinalities

ROOT = Path(__file__).resolve().parents[2]
RESEARCH = ROOT / 'docs/development/product-specs-research-2026-09-05'
SOURCE = 'all-family-compiled-contract-2026-09-06.json'
SOURCE_SHA = '785cd11a39011b643e4bcb1422ab805c242f8a7aae0108b399c6aff0c0d78175'
TYPE_MAP = {'token': 'single_select', 'token_set': 'multi_select',
            'decimal': 'number', 'integer': 'number', 'boolean': 'boolean',
            'text': 'text', 'rows': 'json'}
ROLE_MAP = {'identity': 'primary', 'intrinsic': 'primary',
            'compatibility': 'measurement', 'measurement': 'measurement',
            'contents': 'contents', 'declaration': 'declaration',
            'evidence': 'declaration', 'legacy': 'legacy'}
TEMPLATE_NAMES = dict(line.split('=', 1) for line in '''bearing=Rodamiento
bottom_bracket=Pedalier
bottom_bracket_axle=Eje de pedalier
bottom_bracket_bearing=Rodamiento de pedalier
bottom_bracket_cup=Copa de pedalier
brake_caliper=Cáliper de freno
brake_lever=Maneta de freno
brake_pad=Pastilla o patín de freno
cassette=Cassette
cassette_spacer=Separador de cassette
chain=Cadena
chain_guide=Guía de cadena
chain_link=Conector de cadena
chainring=Plato
hydraulic_disc_brake=Freno hidráulico de disco completo
mechanical_disc_brake=Freno mecánico de disco completo
crank_arm=Biela individual
crankset=Conjunto de bielas
 derailleurs=unused
 derailleur_hanger=Patilla de cambio
 derailleur_pulley=Roldana de cambio
 drivetrain_kit=Kit de transmisión
fixed_cog=Piñón fijo
freewheel=Rueda libre
front_derailleur=Desviador delantero
headset=Dirección
hub=Maza
rear_derailleur=Cambio trasero
rim=Llanta
rim_brake=Freno de llanta
rim_strip=Fondo de llanta
rotor=Disco de freno
shifter=Mando de cambios
spoke=Rayo
 tire=Neumático
 tube=Cámara
 tubeless_consumable=Consumible tubeless
 tubeless_valve=Válvula tubeless
pedal=Pedal
pedal_peg=Peg
 grip=Puño
handlebar_covering=Cinta o cubierta de manubrio
handlebar=Manubrio
stem=Potencia
seatpost=Tija
seat_clamp=Abrazadera de tija
saddle=Sillín
saddle_cover=Cubierta de sillín
fork=Horquilla
rear_shock=Amortiguador trasero
spacer=Separador
headset_small_part=Pieza de dirección
hub_axle=Eje de maza
hub_small_part=Pieza de maza
wheel_retention=Cierre o eje de rueda
spoke_nipple=Niple de rayo
tubeless_tape=Cinta tubeless
tubeless_repair=Reparación tubeless
valve_small_part=Pieza de válvula
tire_liner=Protector interior de neumático
tube_repair=Reparación de cámara
control_cable=Cable de freno o cambio
control_housing=Funda de freno o cambio
control_small_part=Pieza de cable o funda
hydraulic_fitting=Conexión hidráulica
hydraulic_hose=Manguera hidráulica
brake_fluid=Líquido de frenos
brake_mount_adapter=Adaptador de cáliper
rotor_mount_adapter=Adaptador de disco a maza
brake_small_part=Pieza de freno
hub_brake=Freno de maza
bmx_cable_detangler=Rotor de cables BMX
 derailleur_hanger_extender=Extensor de patilla
cassette_lockring=Anillo de cierre de cassette
chainring_guard=Protector de plato
fastener=Tornillo, tuerca o arandela
workshop_tool=Herramienta de taller
workshop_chemical=Producto químico de taller
lock=Candado
light=Luz
 audible_signal=Timbre o bocina
cycle_computer=Ciclocomputador
consumer_electronics=Electrónica de consumo
accessory_mount=Soporte de accesorio
bottle_cage=Portabidón
bottle=Botella o bidón
rack_basket=Portaequipajes o canasto
fender=Tapabarros
kickstand=Pata de apoyo
bike_bag=Bolso de bicicleta
rider_bag=Mochila o bolso personal
training_wheel=Ruedas de aprendizaje
bike_protection=Protección de bicicleta
reflector=Reflectante
souvenir=Artículo de regalo
rider_glove=Guantes
helmet=Casco
eyewear=Anteojos
rider_apparel=Vestuario
rider_protection=Protección personal
food_beverage=Alimento o bebida
pump=Inflador
bicycle=Bicicleta completa
frame=Cuadro
wheel=Rueda o juego de ruedas
brake_shift_combined_control=Control integrado de freno y cambios'''.splitlines())
TEMPLATE_NAMES = {k.strip(): v for k, v in TEMPLATE_NAMES.items() if v != 'unused'}


def read(name):
    return json.loads((RESEARCH / name).read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pointer_parent(document, path):
    parts = [p.replace('~1', '/').replace('~0', '~') for p in path.split('/')[1:]]
    parent = document
    for key in parts[:-1]:
        parent = parent[int(key)] if isinstance(parent, list) else parent[key]
    return parent, int(parts[-1]) if isinstance(parent, list) else parts[-1]


def when(key, choices, value_type='token'):
    return {'kind': 'when', 'rows': [[{'field': key,
        'operator': 'in' if isinstance(choices, list) else 'eq',
        'value_type': value_type, 'value': choices}]]}


def expression(value):
    # Editorial notes never belong to the executable AST.
    return {k: deepcopy(value[k]) for k in ('kind', 'rows') if k in value}


def build():
    if sha(RESEARCH / SOURCE) != SOURCE_SHA:
        raise ValueError('The independently reviewed Claude source has drifted')
    source = read(SOURCE)
    doc = deepcopy(source)
    adjudication = read('mechanical-patch-adjudication-2026-09-06.json')
    decisions = {x['patch_id']: x for x in adjudication['patch_adjudications']}
    accepted = []
    for patch in read('all-family-mechanical-corrections-2026-09-06.json')['patches']:
        if decisions[patch['id']]['decision'] != 'aceptar':
            continue
        parent, key = pointer_parent(doc, patch['path'])
        if patch['op'] != 'replace' or parent[key] != patch['before']:
            raise ValueError(f'Accepted patch preimage drift: {patch["id"]}')
        parent[key] = deepcopy(patch['after'])
        accepted.append(patch['id'])
    definitions = doc['definitions']
    templates = {t['template_key']: t for t in doc['templates']}
    labels = read('all-family-field-labels-2026-09-06.json')['labels']
    existing = read('all-family-existing-metadata-2026-09-06.json')
    if set(labels) != {k for k, d in source['definitions'].items() if d['origin'] == 'new'}:
        raise ValueError('Spanish label review does not cover the original new definitions')
    for key, label in labels.items():
        definitions[key]['label_es'] = label
        definitions[key]['label_origin'] = 'codex_reviewed'
    corrections = []

    def record(code, message, sources=()):
        corrections.append({'id': code, 'change': message, 'source_refs': list(sources)})

    def definition(key, label, kind, unit=None, vocabulary=None, validation=None, row_schema=None):
        if key in definitions:
            raise ValueError(f'Duplicate new definition {key}')
        d = {'key': key, 'origin': 'new', 'type': kind, 'unit': unit,
             'label_es': label, 'label_origin': 'codex_reviewed',
             'validation': validation or {}, 'vocabulary': None, 'used_by': []}
        if vocabulary is not None:
            d['vocabulary'] = [{'value': v, 'source_ids': []} for v in vocabulary]
        if row_schema is not None:
            d['row_schema'] = row_schema
            doc['row_schemas'][key] = row_schema
        definitions[key] = d

    def field(key, role='intrinsic', required=False, allowed=None, note=None):
        return {'key': key, 'role': role, 'required_when': {'kind': 'always' if required else 'never'},
                'allowed_when': allowed or {'kind': 'always'}, 'legacy_action': 'new',
                'evidence_required': 'oem_or_package', 'note': note}

    def replace_field(template, old, new_fields):
        items = templates[template]['fields']
        index = next(i for i, x in enumerate(items) if x['key'] == old)
        items[index:index + 1] = new_fields

    def add_field(template, new_field):
        items = templates[template]['fields']
        if any(f['key'] == new_field['key'] for f in items):
            raise ValueError('Duplicate template field')
        items.insert(len(items) - 1, new_field)

    def clone_split(old, replacements):
        original = definitions.pop(old)
        for key, label in replacements:
            clone = deepcopy(original)
            clone.update(key=key, label_es=label, label_origin='codex_reviewed')
            definitions[key] = clone
        for t in templates.values():
            for f in list(t['fields']):
                if f['key'] == old:
                    replace_field(t['template_key'], old,
                                  [dict(deepcopy(f), key=key) for key, _ in replacements])

    clone_split('bearing_contact_angle_deg', [
        ('bearing_inner_contact_angle_deg', 'Ángulo de contacto interior del rodamiento'),
        ('bearing_outer_contact_angle_deg', 'Ángulo de contacto exterior del rodamiento')])
    record('C01', 'Un par de ángulos conserva 36×45 y 45×45 como configuraciones distintas; ninguno aprueba el rodamiento completo.', ['W04'])
    clone_split('includes_tire_tube', [('includes_tire', 'Incluye neumático'), ('includes_tube', 'Incluye cámara')])
    record('C02', 'Neumático y cámara incluidos son dos observaciones independientes del contenido.')
    definitions.pop('mips_or_equivalent')
    definition('rotational_protection_claimed', 'Declara sistema de protección rotacional', 'boolean')
    definition('rotational_protection_system', 'Nombre del sistema de protección rotacional', 'text')
    child = field('rotational_protection_system', 'declaration', allowed=when('rotational_protection_claimed', True, 'boolean'))
    child['required_when'] = deepcopy(child['allowed_when'])
    replace_field('helmet', 'mips_or_equivalent', [field('rotational_protection_claimed', 'declaration'), child])
    evidence_dependencies = templates['helmet']['prerequisites'].pop('mips_or_equivalent', [])
    templates['helmet']['prerequisites']['rotational_protection_claimed'] = evidence_dependencies
    templates['helmet']['prerequisites']['rotational_protection_system'] = evidence_dependencies
    record('C03', 'Registrar presencia declarada y nombre exacto del sistema; no crear una clase de equivalencia entre marcas.')
    replace_field('tube', 'bead_seat_diameter_mm', [])
    record('C04', 'Una cámara describe cada BSD y rango de ancho en la misma fila; se elimina el escalar que impedía varios BSD.', ['W01', 'S01'])

    # Numerical domains describe magnitudes, not a popular catalogue's menu.
    signed = {'stem_angle_deg', 'bar_backsweep_deg', 'bar_upsweep_deg', 'bar_rise_mm'}
    nonnegative = {'stack_height_mm', 'spacer_thickness_mm', 'keys_included',
                   'interchangeable_lenses', 'bottle_bosses_count', 'bolt_count',
                   'spoke_count', 'spoke_hole_count', 'bar_rise_mm', 'travel_mm',
                   'fork_travel_mm', 'dropper_travel_mm',
                   'reservoir_l', 'glue_volume_ml', 'plug_count', 'patch_count'}
    for key in signed:
        definitions[key]['validation'] = {}
    for key in nonnegative - signed:
        if definitions[key]['origin'] == 'new':
            definitions[key]['validation'] = {'min': 0}
    definitions['bottle_bosses_count']['label_es'] = 'Cantidad de puntos roscados para portabidón'
    definitions['interchangeable_lenses']['label_es'] = 'Cantidad de lentes intercambiables adicionales'
    record('C05', 'Ángulos y elevaciones admiten signo; cantidades de elementos opcionales admiten cero. Los límites no se inventan a partir de tamaños frecuentes.')
    record('C06', 'Puntos de portabidón se cuentan individualmente; lentes adicionales no confunden cero accesorios con ausencia de lente principal.')

    for key in ['thru_axle_thread']:
        for value in ['M12 x 1.75', 'M20 x 1.0', 'M20 x 1.5', 'M20 x 1.75']:
            definitions[key]['vocabulary'].append({'value': value, 'source_ids': ['W09']})
            doc['shared_vocabularies'][key]['values'].append(value)
    record('C07', 'Se incluyen pasos de rosca reales que faltaban; diámetro, longitud del eje y OLD siguen separados.', ['W09'])

    definition('headset_part_scope', 'Partes de dirección incluidas', 'token', vocabulary=['Superior', 'Inferior', 'Completa'])
    templates['headset']['fields'].insert(0, field('headset_part_scope', required=True))
    for f in templates['headset']['fields']:
        if f['key'] in ['headset_upper_shis', 'headset_lower_shis']:
            side = 'Superior' if 'upper' in f['key'] else 'Inferior'
            f['allowed_when'] = f['required_when'] = when('headset_part_scope', [side, 'Completa'])
        if f['key'] == 'stack_height_mm':
            f['note'] = 'Altura de las partes incluidas, según el alcance de esta ficha; no sustituye la geometría de cuadro y horquilla.'
    record('C08', 'Una dirección superior, inferior o completa solicita únicamente sus códigos SHIS correspondientes. El código no impone un diámetro medido literal.', ['W05', 'W06'])

    # A wheelset can contain unlike front/rear wheels. Never broadcast one OLD
    # or rim size to both members of a commercial product.
    wheel_cols = [{'key': 'position', 'type': 'token', 'vocabulary': ['Delantera', 'Trasera']},
                  {'key': 'bead_seat_diameter_mm', 'type': 'integer'},
                  {'key': 'hub_old_mm', 'type': 'decimal'},
                  {'key': 'axle_type', 'type': 'token', 'vocabulary': 'axle_type'},
                  {'key': 'rim_internal_width_mm', 'type': 'decimal', 'optional': True},
                  {'key': 'rear_drive_interface', 'type': 'token', 'vocabulary': 'rear_drive_interface', 'optional': True},
                  {'key': 'rotor_mount_type', 'type': 'token', 'vocabulary': [x['value'] for x in definitions['rotor_mount_type']['vocabulary']], 'optional': True},
                  {'key': 'brake_track', 'type': 'boolean', 'optional': True},
                  {'key': 'rim_tubeless_ready', 'type': 'boolean', 'optional': True},
                  {'key': 'spoke_count', 'type': 'integer', 'optional': True}]
    definition('wheel_configurations', 'Configuración de cada rueda incluida', 'rows', row_schema={'columns': wheel_cols})
    wheel_pair = field('wheel_configurations', 'compatibility', allowed=when('wheel_position', 'Par'))
    wheel_pair['required_when'] = deepcopy(wheel_pair['allowed_when'])
    add_field('wheel', wheel_pair)
    for f in templates['wheel']['fields']:
        if f['key'] in {'bead_seat_diameter_mm', 'hub_old_mm', 'axle_type', 'rim_internal_width_mm',
                        'brake_track', 'rim_tubeless_ready', 'rotor_mount_type', 'spoke_count', 'valve_hole'}:
            f['allowed_when'] = when('wheel_position', ['Delantera', 'Trasera'])
            if f['required_when']['kind'] == 'always':
                f['required_when'] = deepcopy(f['allowed_when'])
        if f['key'] == 'rear_drive_interface':
            f['allowed_when'] = f['required_when'] = when('wheel_position', 'Trasera')
    record('C09', 'Un juego de ruedas almacena filas por posición y no comparte ficticiamente OLD, diámetro o interfaz de transmisión entre ambas ruedas.')

    # Preserve source scopes in rows naming a counterpart. "Absent" is unknown;
    # no exhaustive flag and no free-text list can authorize a global negative.
    for key in ['compatible_caliper_models', 'compatible_derailleur_models', 'shifter_models_compatible',
                'derailleur_models_compatible', 'compatible_brake_models', 'compatible_frames']:
        cols = definitions[key]['row_schema']['columns']
        cols.append({'key': 'generation', 'type': 'text', 'optional': True})
        cols.append({'key': 'conditions', 'type': 'text', 'optional': True})
    record('C10', 'Las relaciones por modelo conservan generación y condiciones de la fuente; ausencia de fila permanece desconocida.', ['A05', 'A21', 'A22'])

    for prefix, label in [('front', 'delantera'), ('rear', 'trasera')]:
        definition(prefix + '_bead_seat_diameter_mm', 'BSD de rueda ' + label, 'integer', 'mm', validation={'positive': True})
    replace_field('bicycle', 'bead_seat_diameter_mm', [field('front_bead_seat_diameter_mm', 'compatibility', True), field('rear_bead_seat_diameter_mm', 'compatibility', True)])
    replace_field('frame', 'bead_seat_diameter_mm', [field('rear_bead_seat_diameter_mm', 'compatibility', True)])
    record('C11', 'Una bicicleta puede llevar tamaños distintos por posición; el cuadro describe la rueda trasera y no impone un tamaño al tren delantero.', ['https://www.trekbikes.com/us/en_US/FAQ/Slash-Gen6/'])

    def edit_field(template, key, **changes):
        item = next(f for f in templates[template]['fields'] if f['key'] == key)
        item.update(deepcopy(changes))

    # These are representation fixes, not permissions to install components.
    # In particular a row naming optional parts cannot describe the contents
    # of the box or the configuration already installed on a bicycle.
    edit_field('pedal', 'replaceable_pins', allowed_when={'kind': 'always'})
    definitions['pedal_type']['vocabulary'] = [v for v in definitions['pedal_type']['vocabulary'] if v['value'] != 'Niño']
    definition('pedal_intended_rider', 'Público previsto declarado para el pedal', 'text')
    add_field('pedal', field('pedal_intended_rider', 'declaration'))
    definition('pedal_bearing_configurations', 'Apoyos y rodamientos del pedal', 'rows', row_schema={'columns': [
        {'key': 'position', 'type': 'text'},
        {'key': 'construction', 'type': 'token', 'vocabulary': ['Cartucho', 'Bolas sueltas', 'Casquillo', 'Otro']},
        {'key': 'model', 'type': 'text', 'optional': True},
        {'key': 'conditions', 'type': 'text', 'optional': True}]})
    replace_field('pedal', 'pedal_bearing_kind', [field('pedal_bearing_configurations')])
    definitions.pop('pedal_bearing_kind')
    definition('cleats_included', 'Incluye calas', 'boolean')
    definition('included_cleat_model', 'Modelo de las calas incluidas', 'text')
    add_field('pedal', field('cleats_included', 'contents'))
    cleat_model = field('included_cleat_model', 'contents', allowed=when('cleats_included', True, 'boolean'))
    cleat_model['required_when'] = deepcopy(cleat_model['allowed_when'])
    add_field('pedal', cleat_model)
    record('C13', 'Los pines no dependen de ser plataforma; apoyos de distinta construcción permanecen en filas independientes y las calas incluidas requieren una observación del contenido.', ['ND01', 'ND02', 'https://www.crankbrothers.com/products/mallet-e'])

    definition('stem_steerer_clamp_diameter_mm', 'Diámetro nominal de espiga admitido por la potencia ahead', 'decimal', 'mm', validation={'positive': True})
    definition('quill_adapter_output_diameter_mm', 'Diámetro nominal de salida del adaptador quill a ahead', 'decimal', 'mm', validation={'positive': True})
    stem_input = field('stem_steerer_clamp_diameter_mm', 'compatibility', allowed=when('stem_kind', 'Tee sin rosca (ahead)'))
    stem_output = field('quill_adapter_output_diameter_mm', 'compatibility', allowed=when('stem_kind', 'Adaptador quill → ahead'))
    for item in [stem_input, stem_output]:
        item['required_when'] = deepcopy(item['allowed_when'])
    replace_field('stem', 'steerer_fit', [stem_input, stem_output])
    for key in ['bar_clamp_diameter_mm', 'stem_length_mm', 'stem_angle_deg']:
        edit_field('stem', key, allowed_when=when('stem_kind', ['Tee sin rosca (ahead)', 'Tee de espiga (quill)', 'Otro']))
    edit_field('stem', 'stack_height_mm', allowed_when=when('stem_kind', 'Tee sin rosca (ahead)'))
    record('C14', 'La potencia ahead describe el diámetro exterior en su zona de abrazadera. La espiga quill conserva su diámetro de inserción y el adaptador tiene una salida independiente, sin abrazadera de manubrio ficticia.', ['ND05', 'https://www.parktool.com/en-us/blog/repair-help/stem-removal-installation-threadless', 'https://www.parktool.com/en-us/blog/repair-help/stem-removal-installation-quill-stems'])

    rails = ['Redondo 7 mm', 'Oval 7x9 mm', 'Oval 7x9.6 mm', 'Oval 7x10 mm', 'Oval 8x8.5 mm', 'Sistema propietario', 'Otro']
    definition('saddle_rail_geometry', 'Geometría de los rieles o del anclaje del sillín', 'token', vocabulary=rails)
    definition('saddle_mount_model', 'Modelo exacto de anclaje de sillín', 'text')
    definition('saddle_rail_material', 'Material declarado de los rieles', 'text')
    replace_field('saddle', 'rail_type', [field('saddle_rail_geometry', 'compatibility', True),
        field('saddle_mount_model', 'compatibility'), field('saddle_rail_material')])
    definitions.pop('rail_type')
    definition('seatpost_saddle_configurations', 'Configuraciones documentadas de anclaje de sillín', 'rows', row_schema={'columns': [
        {'key': 'rail_geometry', 'type': 'token', 'vocabulary': rails},
        {'key': 'configuration_state', 'type': 'token', 'vocabulary': ['De fábrica', 'Con kit incluido', 'Con kit opcional']},
        {'key': 'model', 'type': 'text', 'optional': True},
        {'key': 'generation', 'type': 'text', 'optional': True},
        {'key': 'conditions', 'type': 'text', 'optional': True}]})
    actual_post = when('seatpost_kind', ['Rígida', 'Con suspensión', 'Telescópica (dropper)', 'Otro'])
    post_rails = field('seatpost_saddle_configurations', 'compatibility', allowed=actual_post)
    post_rails['required_when'] = deepcopy(actual_post)
    replace_field('seatpost', 'rail_clamp_fit', [post_rails])
    definitions.pop('rail_clamp_fit')
    for key in ['seatpost_diameter_mm', 'seatpost_offset_mm', 'seatpost_length_mm']:
        edit_field('seatpost', key, allowed_when=actual_post)
    definition('seatpost_shim_length_mm', 'Longitud del suplemento de tija', 'decimal', 'mm', validation={'positive': True})
    add_field('seatpost', field('seatpost_shim_length_mm', 'measurement', allowed=when('seatpost_kind', 'Suplemento (shim)')))
    record('C15', 'La geometría del riel no implica material ni piezas incluidas. La cobertura 7x9/7x9.6/7x10 se registra por configuración y kit documentado; un suplemento no tiene anclaje de sillín ni offset de tija.', ['ND06', 'ND07', 'https://ritcheylogic.com/bike/seatposts/wcs-carbon-1-bolt-seatpost-complete-clampset'])

    for key in ['inner_width_mm', 'inner_height_mm']:
        edit_field('lock', key, allowed_when=when('lock_kind', ['U-lock', 'Kit U + cable']))
    edit_field('lock', 'cable_length_mm', allowed_when=when('lock_kind', ['Cable / espiral', 'Kit U + cable']))
    definition('lock_chain_length_mm', 'Longitud de cadena del candado', 'decimal', 'mm', validation={'positive': True})
    add_field('lock', field('lock_chain_length_mm', 'measurement', allowed=when('lock_kind', 'Cadena')))
    record('C16', 'El kit U más cable permite las dimensiones de ambos componentes. La longitud de cadena ya no se registra como cable; la clasificación de seguridad sigue siendo una declaración pendiente de alcance.', ['ND11', 'https://www.kryptonitelock.com/en/products/product-information/current-key/002079.html?type=bicycle'])

    definition('eyewear_lens_configurations', 'Lentes de esta presentación y sus propiedades', 'rows', row_schema={'columns': [
        {'key': 'model', 'type': 'text'},
        {'key': 'included', 'type': 'boolean', 'optional': True},
        {'key': 'photochromic', 'type': 'boolean', 'optional': True},
        {'key': 'polarized', 'type': 'boolean', 'optional': True},
        {'key': 'mirrored', 'type': 'boolean', 'optional': True},
        {'key': 'tint', 'type': 'text', 'optional': True},
        {'key': 'conditions', 'type': 'text', 'optional': True}]})
    replace_field('eyewear', 'lens_kind', [field('eyewear_lens_configurations', 'declaration', True)])
    definitions.pop('lens_kind')
    record('C17', 'Fotocromía, polarización y recubrimiento pueden coexistir; cada lente conserva sus propiedades y estado de contenido en la misma fila, sin mezclarlas entre variantes.', ['ND19', 'https://www.julbo.com/en_gb/sunglasses/photochromic-2-4-polarized-sunglasses'])

    edit_field('rider_apparel', 'sleeve', allowed_when=when('garment_kind', ['Jersey', 'Polera', 'Chaqueta', 'Otro']))
    definition('oem_size_label', 'Talla exacta declarada por el fabricante', 'text')
    definition('oem_size_system', 'Sistema o guía de tallas del fabricante', 'text')
    for key in ['helmet', 'rider_apparel', 'rider_glove', 'rider_protection']:
        replace_field(key, 'size_label', [field('oem_size_label', required=True), field('oem_size_system', 'declaration')])
    record('C18', 'Las chaquetas pueden declarar manga. Vestuario y protección conservan la talla OEM exacta y su guía sin equiparar rótulos de distintas marcas.', ['ND18', 'ND20'])

    # Every former field remains reachable as legacy. In particular the Claude
    # proposal omitted the old piston count from two brake templates.
    existing_definitions = {d['id']: d for d in existing['definitions']}
    existing_templates = {t['id']: t for t in existing['templates']}
    previous_constraints = {}
    retired_fields = []
    for old in existing['fields']:
        template_key = existing_templates[old['template_id']]['key']
        old_def = existing_definitions[old['spec_definition_id']]
        key = old_def['key']
        if not any(f['key'] == key for f in templates[template_key]['fields']):
            if key not in definitions:
                inverse = {'number': 'integer' if old_def['validation_rules'].get('integer') else 'decimal',
                           'single_select': 'token', 'multi_select': 'token_set', 'boolean': 'boolean', 'text': 'text'}
                definitions[key] = {'key': key, 'origin': 'existing', 'existing_definition_id': old_def['id'],
                    'type': inverse[old_def['data_type']], 'unit': old_def['unit'], 'label_es': old_def['label'],
                    'validation': old_def['validation_rules'], 'vocabulary': [{'value': v} for v in old_def['allowed_values']]}
            add_field(template_key, field(key, 'legacy'))
            retired_fields.append([template_key, key])
        if old['constraint_rules']:
            previous_constraints[template_key + '/' + key] = old['constraint_rules']
    record('C12', 'Se conservan también los campos anteriores omitidos del borrador: ' + ', '.join('/'.join(x) for x in retired_fields))

    return compile_fields(doc, source, accepted, corrections, adjudication, existing, previous_constraints)


COLUMN_LABELS = {
    'member_role': 'Componente', 'family': 'Familia técnica', 'quantity': 'Cantidad',
    'position': 'Posición', 'identity_brand': 'Marca', 'identity_model': 'Modelo',
    'bead_seat_diameter_mm': 'Diámetro de asiento (BSD)', 'width_min_mm': 'Ancho mínimo',
    'width_max_mm': 'Ancho máximo', 'rear_drive_interface': 'Interfaz de transmisión',
    'spacer_mm': 'Espesor de separador requerido', 'source_url': 'Fuente',
    'rotor_diameter_mm': 'Diámetro de disco', 'frame_mount': 'Anclaje de cuadro u horquilla',
    'adapter_required': 'Requiere adaptador', 'adapter_model': 'Modelo de adaptador',
    'brand': 'Marca', 'model': 'Modelo', 'frame_brand': 'Marca del cuadro',
    'frame_model': 'Modelo del cuadro', 'years': 'Años documentados', 'teeth': 'Dientes',
    'bb_shell_interface': 'Interfaz de caja de pedalier', 'bb_shell_width_mm': 'Ancho de caja',
    'model_or_family': 'Modelo o familia documentada', 'generation': 'Generación o edición',
    'conditions': 'Condiciones de la declaración', 'hub_old_mm': 'Distancia entre apoyos (OLD)',
    'axle_type': 'Tipo de eje', 'rim_internal_width_mm': 'Ancho interior de llanta',
    'rotor_mount_type': 'Anclaje del disco', 'brake_track': 'Tiene pista de frenado',
    'rim_tubeless_ready': 'Llanta declarada tubeless ready', 'spoke_count': 'Cantidad de rayos',
    'construction': 'Construcción del apoyo', 'rail_geometry': 'Geometría del riel o anclaje',
    'configuration_state': 'Piezas de la configuración', 'included': 'Incluida en esta presentación',
    'photochromic': 'Fotocromática', 'polarized': 'Polarizada', 'mirrored': 'Espejada', 'tint': 'Tinte o color de la lente',
}


def compile_fields(doc, original, accepted, corrections, adjudication, existing, previous_constraints):
    definitions = doc['definitions']
    templates = doc['templates']
    template_keys = {t['template_key'] for t in templates}
    if template_keys != set(TEMPLATE_NAMES):
        raise ValueError(f'Template names mismatch {template_keys ^ set(TEMPLATE_NAMES)}')
    output_definitions = {}
    for key, d in definitions.items():
        kind = TYPE_MAP[d['type']]
        validation = deepcopy(d['validation'])
        if d['type'] == 'integer':
            validation['integer'] = True
        options = [x['value'] for x in d.get('vocabulary', []) or []] if kind in ('single_select', 'multi_select') else []
        if len(options) != len(set(options)):
            raise ValueError(f'Duplicate options {key}')
        if kind == 'json':
            columns = []
            for c in d['row_schema']['columns']:
                col = {'key': c['key'], 'label': COLUMN_LABELS[c['key']], 'type': c['type'],
                       'required': not c.get('optional', False)}
                if c['type'] in ('decimal', 'integer'):
                    col['validation'] = {'min': '0'} if c['key'] in ('spacer_mm', 'spoke_count') else {'positive': True}
                    if c['key'].endswith('_mm'):
                        col['unit'] = 'mm'
                if c['type'] == 'token':
                    vocab = c['vocabulary']
                    if vocab == 'template_keys':
                        vocab = sorted(template_keys)
                    elif isinstance(vocab, str):
                        vocab = doc['shared_vocabularies'][vocab]['values']
                    col['allowed_values'] = vocab
                columns.append(col)
            schema = {'version': 1, 'columns': columns}
            column_keys = {c['key'] for c in columns}
            if {'width_min_mm', 'width_max_mm'} <= column_keys:
                schema['ordered_pairs'] = [['width_min_mm', 'width_max_mm']]
            if key in ('cog_sequence', 'chainring_teeth_rows', 'wheel_configurations'):
                schema['unique_by'] = [['position']]
            validation = {'rows_schema': schema}
        output_definitions[key] = {
            'id': d.get('existing_definition_id') or str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:spec-definition:' + key)),
            'key': key, 'origin': d['origin'], 'label': d['label_es'], 'data_type': kind,
            'unit': d['unit'], 'allowed_values': options, 'validation_rules': validation,
            'used_by': [],
        }
    output_templates = []
    target_definitions = {d['key']: d for d in existing['definitions']}
    for key, d in output_definitions.items():
        target = target_definitions.get(key)
        if d['origin'] == 'new' and target is not None:
            raise ValueError(f'New definition collides with the production snapshot: {key}')
        if d['origin'] == 'existing' and (target is None or
                any(d[attr] != target[attr] for attr in ['id', 'key', 'data_type', 'unit'])):
            raise ValueError(f'Existing production definition identity/type drift: {key}')
    for t in templates:
        fields = t['fields']
        keys = {f['key'] for f in fields}
        if len(keys) != len(fields):
            raise ValueError('Duplicate field in ' + t['template_key'])
        contract = {'rules_version': 2, 'roles': {}, 'semantic_roles': {}, 'labels': {},
                    'allowed_when': {}, 'required_when': {}, 'allowed_options': {},
                    'prerequisites': t['prerequisites'], 'helpers': {}, 'evidence_requirements': {}}
        for f in fields:
            k = f['key']
            output_definitions[k]['used_by'].append(t['template_key'])
            contract['roles'][k] = ROLE_MAP[f['role']]
            contract['semantic_roles'][k] = f['role']
            contract['allowed_when'][k] = expression(f['allowed_when'])
            contract['required_when'][k] = expression(f['required_when'])
            if 'allowed_options' in f:
                contract['allowed_options'][k] = f['allowed_options']
            contract['evidence_requirements'][k] = f['evidence_required']
        # Keep editorial proposals and machine rules outside runtime helpers.
        # Source notes may contain a disproved claim and cannot instruct users.
        validate_contract(t['template_key'], contract, output_definitions, keys)
        output_templates.append({'key': t['template_key'], 'name': TEMPLATE_NAMES[t['template_key']],
                                 'id': next((x['id'] for x in existing['templates'] if x['key'] == t['template_key']),
                                            str(uuid.uuid5(uuid.NAMESPACE_URL, 'vinabike:spec-template:' + t['template_key']))),
                                 'technical_family': t['technical_family'], 'origin': t['status'],
                                 'form_contract': contract,
                                 'fields': [{'key': f['key'], 'section_key': ROLE_MAP[f['role']],
                                             'sort_order': i * 10, 'is_required': False,
                                             'visibility_rules': [], 'option_rules': [],
                                             'constraint_rules': deepcopy(previous_constraints.get(t['template_key'] + '/' + f['key'], []))}
                                            for i, f in enumerate(fields)]})
    return {
        'schema_version': 1, 'title': 'Campos de todas las familias: compilación revisable',
        'source_sha256': SOURCE_SHA, 'accepted_claude_patch_ids': accepted,
        'input_sha256': {name: sha(RESEARCH / name) for name in [SOURCE,
             'all-family-existing-metadata-2026-09-06.json', 'all-family-field-labels-2026-09-06.json',
             'all-family-mechanical-corrections-2026-09-06.json', 'mechanical-patch-adjudication-2026-09-06.json',
             'non-drivetrain-field-review-2026-09-06.json']},
        'codex_corrections': corrections, 'definitions': output_definitions, 'templates': output_templates,
        'publication_gates': {'all_family_domain_review_complete': False,
                              'all_product_assignment_review_complete': False,
                              'compatibility_rules_integrated': False,
                              'fill_allowed': False},
        'mechanical_rule_policy': 'No importar reglas ni verified del borrador. Los dictámenes A01-A29 y W01-W11 requieren cierre por interfaz, evidencia OEM y pruebas del consumidor real.',
        'unresolved_adjudications': [x for x in adjudication['patch_adjudications'] if x['decision'] != 'aceptar'],
        'stats': {'templates': len(output_templates), 'definitions': len(output_definitions),
                  'new_definitions': sum(d['origin'] == 'new' for d in output_definitions.values()),
                  'structured_fields': sum(d['data_type'] == 'json' for d in output_definitions.values()),
                  'fields': sum(len(t['fields']) for t in output_templates),
                  'product_facts_changed': 0},
    }


def validate_contract(name, contract, definitions, keys):
    validate_row_conditions(contract, definitions, keys)
    edges = {k: set() for k in keys}
    for kind in ['allowed_when', 'required_when']:
        for target, expr in contract[kind].items():
            assert expr['kind'] in ('always', 'never', 'when')
            for row in expr.get('rows', []):
                assert row
                for pred in row:
                    dep = pred['field']
                    if dep not in keys or contract['roles'][dep] == 'legacy':
                        raise ValueError(f'{name}/{target}: unavailable prerequisite {dep}')
                    dtype = definitions[dep]['data_type']
                    allowed_types = {'token': ['single_select', 'text'], 'boolean': ['boolean'], 'decimal': ['number']}
                    if dtype not in allowed_types[pred['value_type']]:
                        raise ValueError(f'{name}/{target}: wrong prerequisite type')
                    values = pred['value'] if pred['operator'] == 'in' else [pred['value']]
                    if dtype == 'single_select' and not set(values) <= set(definitions[dep]['allowed_values']):
                        raise ValueError(f'{name}/{target}: unknown condition options {values}')
                    if kind == 'allowed_when':
                        edges[target].add(dep)
    for target, deps in contract['prerequisites'].items():
        if target not in keys or any(dep not in keys or contract['roles'][dep] == 'legacy' for dep in deps):
            raise ValueError(f'{name}: foreign or legacy prerequisite')
        edges[target].update(deps)
    for k, options in contract['allowed_options'].items():
        allowed = ['true', 'false'] if definitions[k]['data_type'] == 'boolean' else definitions[k]['allowed_values']
        if not set(options) <= set(allowed):
            raise ValueError(f'{name}/{k}: template options exceed definition')
    if 'row_coherence' in contract or 'scalar_ordered_pairs' in contract:
        if contract.get('rules_version') != 2:
            raise ValueError(f'{name}: coherence requires v2')
        links = row_coherence_links(contract)
        ids, cells = set(), set()
        for link in links:
            if set(link) != {'id', 'field', 'column', 'target_field', 'label_columns'}:
                raise ValueError(f'{name}: invalid link metadata')
            source, target = link['field'], link['target_field']
            if source not in keys or target not in keys or source == target:
                raise ValueError(f'{name}: unavailable link endpoints')
            if any(contract['roles'][k] == 'legacy' or definitions[k]['data_type'] != 'json' for k in [source, target]):
                raise ValueError(f'{name}: retired or non-row link endpoint')
            source_columns = {c['key']: c for c in definitions[source]['validation_rules']['rows_schema']['columns']}
            target_columns = {c['key']: c for c in definitions[target]['validation_rules']['rows_schema']['columns']}
            col = source_columns.get(link['column'], {})
            if col.get('type') not in ('text', 'token') or col.get('allowed_values'):
                raise ValueError(f'{name}: link column cannot represent arbitrary row IDs')
            labels = link['label_columns']
            if not labels or len(labels) != len(set(labels)) or not set(labels) <= set(target_columns):
                raise ValueError(f'{name}: unavailable link labels')
            cell = (source, link['column'])
            if link['id'] in ids or cell in cells:
                raise ValueError(f'{name}: duplicate link')
            ids.add(link['id']); cells.add(cell); edges[source].add(target)
        if any((link['target_field'], col) in cells for link in links for col in link['label_columns']):
            raise ValueError(f'{name}: a label cannot display another link')
        validate_row_cardinalities(contract, definitions, keys, edges, ids)
        pairs = set()
        for pair in contract.get('scalar_ordered_pairs', []):
            if (not isinstance(pair, list) or not (len(pair) == 2 or len(pair) == 3 and pair[2] == 'lt')
                    or pair[0] == pair[1]
                    or tuple(sorted(pair[:2])) in pairs or any(k not in keys or contract['roles'][k] == 'legacy'
                        or definitions[k]['data_type'] != 'number' for k in pair[:2])
                    or definitions[pair[0]]['unit'] != definitions[pair[1]]['unit']):
                raise ValueError(f'{name}: invalid scalar bounds')
            pairs.add(tuple(sorted(pair[:2])))
    def visit(key, trail):
        if key in trail:
            raise ValueError(f'{name}: cyclic applicability {trail} -> {key}')
        for dep in edges[key]:
            visit(dep, trail + [key])
    for key in keys:
        visit(key, [])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=RESEARCH / 'all-family-reviewed-fields-2026-09-06.json')
    args = parser.parse_args()
    result = build()
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'output': str(args.output), 'sha256': sha(args.output), **result['stats']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
