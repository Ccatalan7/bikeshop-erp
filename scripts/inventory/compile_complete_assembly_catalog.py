#!/usr/bin/env python3
"""Compile bicycle, frame and wheel successors. No product or database writes.

A size number without its datum is not a size. A front wheel and a rear wheel
are two sets of measurements. What comes in the box and what the maker says it
fits are different declarations.
"""
from copy import deepcopy
import hashlib
import json

from compile_non_drivetrain_publication import (
    CATALOG, CATALOG_SHA, CASES, CASES_SHA, RESEARCH, write_json)
from compile_mobility_accessories_catalog import case, condition, rows
from compile_wheel_small_parts_catalog import column, retire, table
from compile_product_spec_catalog import validate_contract
from compile_complete_assembly_root import review_assemblies

FAMILIES = ('bicycle', 'frame', 'wheel')

# Sheldon: the old standard measured bottom-bracket centre to the top of the
# seat tube; many makers now measure to the top-tube centreline instead, and a
# size number is nearly meaningless unless you know how it was measured.
SHELDON_SIZING = 'https://www.sheldonbrown.com/frame-sizing.html'
# Surly's own geometry chart labels Seat Tube Length, Top Tube Length Actual and
# Effective, Head Tube Angle and Seat Tube Angle, with angles in degrees — and it
# does not say whether the seat tube is measured centre to centre or centre to
# top. A real chart omits exactly the datum Sheldon calls indispensable.
SURLY_GEOMETRY = 'https://surlybikes.com/bikes/cross_check'

DECLARED, UNPUBLISHED = 'Declarado', 'No publicado'
MM, IN, DEG, CM = 'mm', 'in', 'grados', 'cm'
FRONT, REAR = 'Delantera', 'Trasera'
COMPATIBLE, INCOMPATIBLE, CONDITIONED = ('Compatible declarado',
                                         'Incompatible declarado', 'Condicionado')
HEAD_ANGLE, SEAT_ANGLE = 'Ángulo de dirección', 'Ángulo de sillín'
ANGLES = [HEAD_ANGLE, SEAT_ANGLE]
LENGTHS = ['Alcance (reach)', 'Altura (stack)', 'Tubo de sillín', 'Tubo superior',
           'Vaina trasera', 'Distancia entre ejes', 'Caída del pedalier',
           'Altura al entrepierna', 'Otra medida declarada']


def compile_catalog():
    for path, sha in ((CATALOG, CATALOG_SHA), (CASES, CASES_SHA)):
        if hashlib.sha256(path.read_bytes()).hexdigest() != sha:
            raise ValueError('Frozen input drift')
    base = json.loads(CATALOG.read_text())
    templates = {t['key']: deepcopy(t)
                 for t in base['templates'] if t['key'] in FAMILIES}
    definitions = deepcopy(base['definitions'])
    fixtures = json.loads(CASES.read_text())
    fixtures['cases'] = [c for c in fixtures['cases'] if c['template'] in FAMILIES]

    # CA-1. Geometry had nowhere to live, and the one size cell that existed was
    # a bare label. Sheldon is explicit that a seat-tube number is nearly
    # meaningless unless you know how it was measured, so the datum travels with
    # every figure and the unit is its own answer.
    geometry = 'frame_geometry_measurements'
    table(definitions, templates, geometry, 'Medidas de geometría declaradas',
          ('frame', 'bicycle'), [
              column('size_label', 'Talla declarada', required=True),
              column('measure', 'Medida', 'token', required=True,
                     options=[*LENGTHS, *ANGLES]),
              column('value', 'Valor publicado', 'decimal', required=True,
                     positive=True),
              column('unit', 'Unidad', 'token', required=True,
                     options=[MM, IN, DEG]),
              column('datum', 'Entre qué puntos se mide', required=True),
              column('conditions', 'Edición y condiciones'),
              column('source_url', 'Fuente', 'url', required=True),
          ], helper=(
              'Cada cifra viaja con su talla, su unidad y el punto desde el que '
              'se mide. Un número de tubo de sillín no dice nada si no se sabe '
              'cómo se midió: centro a centro y centro al extremo son medidas '
              'distintas del mismo cuadro, y ambas pueden convivir aquí.'))
    definitions[geometry]['validation_rules']['rows_schema']['unique_by'] = [
        ['size_label', 'measure', 'datum']]
    for family in ('frame', 'bicycle'):
        contract = templates[family]['form_contract']
        contract.setdefault('row_conditions', {'version': 1, 'fields': {}})[
            'fields'].setdefault(geometry, {})['value_when'] = {'unit': [{
                'when': condition('measure', ANGLES),
                'expected': {'value_type': 'token', 'value': DEG}}]}

    # CA-2. A bicycle model is sold in sizes, and the ficha had one label and one
    # rider range for the whole product. Each size is its own configuration.
    bicycle = templates['bicycle']
    sizes = 'bicycle_size_configurations'
    table(definitions, templates, sizes, 'Tallas declaradas de la bicicleta',
          ('bicycle',), [
              column('size_label', 'Talla declarada', required=True),
              column('rider_form', 'Forma del rango de estatura', 'token',
                     required=True, options=[DECLARED, UNPUBLISHED]),
              column('rider_min', 'Estatura mínima declarada', 'decimal',
                     positive=True),
              column('rider_max', 'Estatura máxima declarada', 'decimal',
                     positive=True),
              column('rider_unit', 'Unidad de la estatura', 'token',
                     options=[CM, IN]),
              column('conditions', 'Edición y condiciones'),
              column('source_url', 'Fuente', 'url', required=True),
          ], required=True,
          conditions={k: condition('rider_form', DECLARED)
                      for k in ('rider_min', 'rider_max', 'rider_unit')},
          helper=('Una fila por talla. El rango de estatura es una recomendación '
                  'del fabricante con su unidad, no una medida del cuadro, y una '
                  'talla sin rango publicado queda pendiente.'))
    schema = definitions[sizes]['validation_rules']['rows_schema']
    schema['unique_by'] = [['size_label']]
    schema['ordered_pairs'] = [['rider_min', 'rider_max']]
    retire(bicycle, ['frame_size_label', 'rider_height_min_cm',
                     'rider_height_max_cm'])
    # The scalar pair guarded the retired range; the row pair replaces it, and a
    # pair over legacy fields is rejected by the contract validator.
    bicycle['form_contract']['scalar_ordered_pairs'] = [
        pair for pair in bicycle['form_contract'].get('scalar_ordered_pairs', [])
        if 'rider_height_min_cm' not in pair]

    # CA-3. The two wheels lived as ten parallel scalars, so nothing tied a
    # measurement to the wheel it belongs to and nothing stopped a front figure
    # answering a rear question. One row per position, and the ports of that
    # position with it.
    positions = 'bicycle_wheel_positions'
    table(definitions, templates, positions, 'Posiciones de rueda declaradas',
          ('bicycle',), [
              column('position', 'Rueda', 'token', required=True,
                     options=[FRONT, REAR]),
              column('bead_seat_diameter_mm', 'Diámetro de asiento de talón',
                     'decimal', unit='mm', positive=True, required=True),
              column('hub_old_mm', 'Anchura de maza', 'decimal', unit='mm',
                     positive=True),
              column('axle_type', 'Retención del eje declarada'),
              column('brake_mount', 'Montaje de freno de esta rueda', 'token',
                     options=['International Standard', 'Post Mount',
                              'Flat Mount', 'Sin freno de disco', 'Otro']),
              column('max_rotor_mm', 'Rotor máximo declarado', 'decimal',
                     unit='mm', positive=True),
              column('rotor_fitted_mm', 'Rotor montado de fábrica', 'decimal',
                     unit='mm', positive=True),
              column('conditions', 'Edición y condiciones'),
              column('source_url', 'Fuente', 'url', required=True),
          ], required=True,
          conditions={k: condition('brake_mount',
                                   ['International Standard', 'Post Mount',
                                    'Flat Mount', 'Otro'])
                      for k in ('max_rotor_mm', 'rotor_fitted_mm')},
          helper=('Una fila por rueda. El rotor montado de fábrica y el máximo '
                  'admitido son declaraciones distintas, y ninguna de las dos se '
                  'deduce del diámetro de la otra rueda. Una rueda sin freno de '
                  'disco no declara rotor.'))
    definitions[positions]['validation_rules']['rows_schema']['unique_by'] = [
        ['position']]
    definitions[positions]['validation_rules']['rows_schema']['ordered_pairs'] = [
        ['rotor_fitted_mm', 'max_rotor_mm']]
    retire(bicycle, ['front_bead_seat_diameter_mm', 'rear_bead_seat_diameter_mm',
                     'front_hub_old_mm', 'rear_hub_old_mm', 'front_axle_type',
                     'rear_axle_type', 'brake_mount_front', 'brake_mount_rear',
                     'rotor_front_mm', 'rotor_rear_mm'])

    # CA-4. `includes_tire` and `includes_tube` were yes/no summaries of what the
    # box holds, which kit_members already carries with identity. What was
    # missing is the other declaration entirely: what the maker says the wheel
    # accepts. Neither implies the other, so they are separate tables.
    wheel = templates['wheel']
    accepts = 'wheel_compatible_claims'
    table(definitions, templates, accepts, 'Compatibilidades declaradas de la rueda',
          ('wheel',), [
              column('component_kind', 'Componente declarado', 'token',
                     required=True,
                     options=['Cubierta', 'Cámara', 'Rotor', 'Cassette',
                              'Cinta de llanta', 'Válvula', 'Otro']),
              # Every column of the key is required. A key with an optional
              # column only guards rows that happen to have filled it, which is
              # precisely where a real catalogue leaves gaps: an undeclared
              # brand or edition is written as such, not left blank.
              column('target_brand', 'Marca declarada', required=True),
              column('target_model', 'Modelo declarado', required=True),
              column('target_edition', 'Edición o generación', required=True),
              column('status', 'Estado declarado', 'token', required=True,
                     options=[COMPATIBLE, INCOMPATIBLE, CONDITIONED]),
              column('conditions', 'Condiciones publicadas'),
              column('source_scope', 'Apartado de la fuente', required=True),
              column('source_url', 'Fuente', 'url', required=True),
          ], conditions={'conditions': condition('status', CONDITIONED)},
          helper=('Lo que el fabricante declara que esta rueda acepta. No es lo '
                  'que viene en la caja, que va en los miembros del conjunto, y '
                  'ninguna de las dos cosas implica la otra: una rueda puede '
                  'venir con una cubierta que no es la única que acepta, y '
                  'aceptar una que no incluye. Un diámetro igual no es una '
                  'declaración de compatibilidad.'))
    definitions[accepts]['validation_rules']['rows_schema']['unique_by'] = [
        ['component_kind', 'target_brand', 'target_model', 'target_edition',
         'source_scope']]
    retire(wheel, ['includes_tire', 'includes_tube'])

    fixtures['cases'].extend(_cases(geometry, sizes, positions, accepts))

    review_assemblies(definitions, templates, fixtures)

    keys = {f['key'] for t in templates.values() for f in t['fields']}
    definitions = {k: definitions[k] for k in sorted(keys)}
    for t in templates.values():
        validate_contract(t['key'], t['form_contract'], definitions,
                          {f['key'] for f in t['fields']})
    catalog = {**base, 'title': 'Complete assembly reviewed successor',
               'templates': list(templates.values()), 'definitions': definitions,
               'input_sha256': {'catalog': CATALOG_SHA, 'cases': CASES_SHA},
               'mechanical_coverage_complete': False,
               'automatic_fill_authorized': False}
    catalog['stats'] = {'templates': len(templates),
                        'definitions': len(definitions),
                        'field_uses': sum(len(t['fields']) for t in templates.values())}
    return catalog, fixtures


def _cases(geometry, sizes, positions, accepts):
    geo = lambda **kw: dict({'size_label': 'M', 'measure': 'Tubo de sillín',
                             'value': '540', 'unit': MM,
                             'datum': 'Centro del pedalier al centro del tubo superior',
                             'source_url': SHELDON_SIZING}, **kw)
    size = lambda **kw: dict({'size_label': 'M', 'rider_form': UNPUBLISHED,
                              'source_url': SHELDON_SIZING}, **kw)
    pos = lambda **kw: dict({'position': FRONT, 'bead_seat_diameter_mm': '622',
                             'source_url': SHELDON_SIZING}, **kw)
    acc = lambda **kw: dict({'component_kind': 'Cubierta',
                             'target_brand': 'Marca sintética',
                             'target_model': 'Sintético',
                             'target_edition': 'No declarada',
                             'status': COMPATIBLE,
                             'source_scope': 'Apartado sintético',
                             'source_url': SHELDON_SIZING}, **kw)
    return [
        # --- CA-1: geometry --------------------------------------------------
        # The same tube, measured two ways, is two rows and not a contradiction.
        case('ca_same_tube_two_datums_coexist', 'frame',
             {geometry: rows(
                 geo(datum='Centro del pedalier al extremo del tubo de sillín',
                     value='560'),
                 geo(datum='Centro del pedalier al centro del tubo superior',
                     value='540'))},
             sources=[SHELDON_SIZING]),
        # The same measurement declared twice, with the same datum, is one.
        case('ca_same_measure_same_datum_twice_blocks', 'frame',
             {geometry: rows(geo(value='540'), geo(value='560'))},
             blocking=[('row_shape', geometry)]),
        case('ca_angle_must_be_in_degrees', 'frame',
             {geometry: rows(geo(measure=HEAD_ANGLE, value='69', unit=MM,
                                 datum='Respecto a la horizontal'))},
             blocking=[('row_value_conflict', geometry)]),
        case('ca_angle_in_degrees_is_fine', 'frame',
             {geometry: rows(geo(measure=SEAT_ANGLE, value='73.5', unit=DEG,
                                 datum='Respecto a la horizontal'))}),
        # An imperial length keeps its own unit; nothing is converted.
        case('ca_length_may_be_imperial', 'frame',
             {geometry: rows(geo(measure='Tubo superior', value='22.5', unit=IN,
                                 datum='Horizontal efectivo'))}),
        case('ca_geometry_row_without_datum_is_pending', 'frame',
             {geometry: rows({'size_label': 'M', 'measure': 'Alcance (reach)',
                              'value': '400', 'unit': MM,
                              'source_url': SHELDON_SIZING})},
             pending=[('row_incomplete', geometry)]),
        # A real chart may simply not say how it measured. That is an answer
        # the row records, not a blank it hides.
        case('ca_source_does_not_state_its_datum', 'frame',
             {geometry: rows(geo(measure='Tubo de sillín', value='560', unit=MM,
                                 datum='No especificado por la fuente',
                                 source_url=SURLY_GEOMETRY))},
             sources=[SURLY_GEOMETRY]),
        # Actual and effective top tube are two published datums, not a conflict.
        case('ca_actual_and_effective_top_tube_coexist', 'frame',
             {geometry: rows(
                 geo(measure='Tubo superior', value='560', unit=MM,
                     datum='Longitud real', source_url=SURLY_GEOMETRY),
                 geo(measure='Tubo superior', value='565', unit=MM,
                     datum='Longitud efectiva (horizontal)',
                     source_url=SURLY_GEOMETRY))},
             sources=[SURLY_GEOMETRY]),
        # Two sizes of one frame are two sets of figures.
        case('ca_two_sizes_keep_their_own_geometry', 'frame',
             {geometry: rows(geo(size_label='M', value='540'),
                             geo(size_label='L', value='580'))}),
        # --- CA-2: sizes -----------------------------------------------------
        case('ca_size_without_published_range', 'bicycle',
             {sizes: rows(size()), positions: rows(pos(), pos(position=REAR))}),
        case('ca_unpublished_range_cannot_carry_a_figure', 'bicycle',
             {sizes: rows(size(rider_min='165')),
              positions: rows(pos(), pos(position=REAR))},
             blocking=[('row_field_applicability', sizes)]),
        case('ca_declared_range_keeps_its_unit', 'bicycle',
             {sizes: rows(size(rider_form=DECLARED, rider_min='165',
                               rider_max='178', rider_unit=CM)),
              positions: rows(pos(), pos(position=REAR))}),
        case('ca_inverted_rider_range_blocks', 'bicycle',
             {sizes: rows(size(rider_form=DECLARED, rider_min='178',
                               rider_max='165', rider_unit=CM)),
              positions: rows(pos(), pos(position=REAR))},
             blocking=[('row_shape', sizes)]),
        case('ca_same_size_twice_blocks', 'bicycle',
             {sizes: rows(size(), size(rider_form=DECLARED, rider_min='165',
                                       rider_max='178', rider_unit=CM)),
              positions: rows(pos(), pos(position=REAR))},
             blocking=[('row_shape', sizes)]),
        # --- CA-3: wheel positions -------------------------------------------
        # Two wheels, two sets of figures, and neither answers for the other.
        case('ca_front_and_rear_keep_their_own_figures', 'bicycle',
             {sizes: rows(size()), positions: rows(
                 pos(position=FRONT, bead_seat_diameter_mm='622',
                     hub_old_mm='100', axle_type='Eje pasante 12 mm',
                     brake_mount='Flat Mount', max_rotor_mm='160'),
                 pos(position=REAR, bead_seat_diameter_mm='584',
                     hub_old_mm='142', axle_type='Eje pasante 12 mm',
                     brake_mount='Flat Mount', max_rotor_mm='160'))}),
        case('ca_same_wheel_position_twice_blocks', 'bicycle',
             {sizes: rows(size()), positions: rows(pos(), pos(hub_old_mm='110'))},
             blocking=[('row_shape', positions)]),
        # A wheel with no disc mount declares no rotor.
        case('ca_rim_braked_wheel_has_no_rotor', 'bicycle',
             {sizes: rows(size()), positions: rows(
                 pos(brake_mount='Sin freno de disco', max_rotor_mm='160'),
                 pos(position=REAR))},
             blocking=[('row_field_applicability', positions)]),
        # The fitted rotor cannot exceed the declared maximum.
        case('ca_fitted_rotor_cannot_exceed_the_maximum', 'bicycle',
             {sizes: rows(size()), positions: rows(
                 pos(brake_mount='Post Mount', rotor_fitted_mm='180',
                     max_rotor_mm='160'),
                 pos(position=REAR))},
             blocking=[('row_shape', positions)]),
        # --- CA-4: included versus compatible --------------------------------
        case('ca_compatible_is_not_included', 'wheel',
             {'wheel_position': FRONT, 'bead_seat_diameter_mm': '622',
              'hub_old_mm': '100', 'axle_type': 'Eje pasante 12 mm',
              accepts: rows(acc(target_brand='Marca sintética',
                                target_model='Cubierta sintética'))}),
        case('ca_conditioned_claim_needs_its_condition', 'wheel',
             {'wheel_position': FRONT, 'bead_seat_diameter_mm': '622',
              'hub_old_mm': '100', 'axle_type': 'Eje pasante 12 mm',
              accepts: rows(acc(status=CONDITIONED))},
             pending=[('row_required_missing', accepts)]),
        case('ca_same_claim_twice_blocks', 'wheel',
             {'wheel_position': FRONT, 'bead_seat_diameter_mm': '622',
              'hub_old_mm': '100', 'axle_type': 'Eje pasante 12 mm',
              accepts: rows(acc(target_edition='2021'),
                            acc(target_edition='2021', status=INCOMPATIBLE))},
             blocking=[('row_shape', accepts)]),
        # The guard holds even when the edition itself is «no declarada»,
        # because that is an answer and not a blank.
        case('ca_undeclared_edition_still_guards', 'wheel',
             {'wheel_position': FRONT, 'bead_seat_diameter_mm': '622',
              'hub_old_mm': '100', 'axle_type': 'Eje pasante 12 mm',
              accepts: rows(acc(), acc(status=INCOMPATIBLE))},
             blocking=[('row_shape', accepts)]),
        case('ca_different_edition_keeps_its_claim', 'wheel',
             {'wheel_position': FRONT, 'bead_seat_diameter_mm': '622',
              'hub_old_mm': '100', 'axle_type': 'Eje pasante 12 mm',
              accepts: rows(acc(target_edition='2019'),
                            acc(target_edition='2021', status=INCOMPATIBLE))}),
        # A wheelset still keeps each wheel's measurements apart.
        case('ca_wheelset_does_not_mix_its_wheels', 'wheel',
             {'wheel_position': 'Par', 'wheel_configurations': rows(
                 {'position': FRONT, 'bead_seat_diameter_mm': '622',
                  'hub_old_mm': '100', 'axle_type': 'Eje pasante 12 mm'},
                 {'position': REAR, 'bead_seat_diameter_mm': '622',
                  'hub_old_mm': '142', 'axle_type': 'Eje pasante 12 mm'})}),
    ]


if __name__ == '__main__':
    catalog, fixtures = compile_catalog()
    path = RESEARCH / 'complete-assembly-catalog-2026-09-07.json'
    write_json(path, catalog)
    fixtures['catalogue_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    write_json(RESEARCH / 'complete-assembly-cases-2026-09-07.json', fixtures)
    print(json.dumps({**catalog['stats'], 'cases': len(fixtures['cases'])}))
