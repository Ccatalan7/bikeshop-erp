#!/usr/bin/env python3
"""Compile the second Chilean-Spanish vocabulary pass for product specs.

The first pass corrected the main field and template labels. This pass closes
the remaining operator-facing vocabulary in options, row schemas and helpers,
including legacy product mirrors. Stable option IDs, codes, facts and
compatibility rules keep their identity.

Usage: compile_chilean_bicycle_option_language.py [--version 20260919253000]
"""

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
AUDITED_TENANT_ID = '5443b130-cc28-45af-a420-cd500b288890'


CATEGORY_RENAMES = [
    (
        '060885f4-653e-4cdc-9b82-f1b223221439',
        'Porta Caramagiola',
        'Accesorios / Porta Caramagiola',
        'Portabotellas',
        'Accesorios / Portabotellas',
    ),
    (
        '47b4e4e2-df85-481e-b4a8-f362c4912630',
        'Adaptadores de tija',
        'Accesorios / Asientos / Adaptadores de tija',
        'Adaptadores para poste de asiento',
        'Accesorios / Asientos / Adaptadores para poste de asiento',
    ),
    (
        '9a055a2e-25cc-46a3-b30a-7311936914e6',
        'Tija',
        'Accesorios / Asientos / Tija',
        'Postes de asiento',
        'Accesorios / Asientos / Postes de asiento',
    ),
    (
        '8c5d15a3-df4b-4bc9-85ec-caa68c512252',
        'Cinta Manillar',
        'Accesorios / Cinta Manillar',
        'Cintas de manubrio',
        'Accesorios / Cintas de manubrio',
    ),
]


OPTION_RENAMES = [
    ('bag_position', 'Bajo sillín', 'Bajo el asiento'),
    ('bar_construction', 'Integrado manubrio + potencia', 'Manubrio y tee integrados'),
    ('bar_style', 'Ruta (drop)', 'Ruta (manubrio curvo)'),
    ('bar_width_reference', 'Centro a centro en manetas (hoods)', 'Centro a centro en las manillas (hoods)'),
    ('bar_width_reference', 'Centro a centro en drops', 'Centro a centro en la parte baja del manubrio'),
    ('bike_attachment_kind', 'Abrazadera de potencia / tija', 'Abrazadera al tee o poste de asiento'),
    ('bike_protection_kind', 'Funda de bicicleta (cubierta)', 'Funda para bicicleta'),
    ('bottle_retention_system', 'Convencional (portabidón de aro)', 'Portabotella convencional (de aro)'),
    ('brake_presentation', 'Cáliper con manguera, sin maneta', 'Cáliper con manguera, sin manilla'),
    ('brake_presentation', 'Cáliper sin maneta', 'Cáliper sin manilla'),
    ('brake_presentation', 'Set con manetas y cables', 'Juego con manillas y cables'),
    ('brake_presentation', 'Un freno completo (maneta, cable y funda, cáliper)', 'Un freno completo (manilla, cable, funda y cáliper)'),
    ('brake_presentation', 'Un freno completo (maneta, manguera, cáliper)', 'Un freno completo (manilla, manguera y cáliper)'),
    ('cable_head', 'Barril (MTB / manetas planas)', 'Barril (MTB / manillas planas)'),
    ('cage_mount', 'Bridas (cable ties) al tubo', 'Amarras plásticas al tubo'),
    ('cage_retention_system', 'Convencional (portabidón de aro)', 'Portabotella convencional (de aro)'),
    ('carrier_mount_kind', 'Abrazadera a tija', 'Abrazadera al poste de asiento'),
    ('covering_kind', 'Cinta de manillar', 'Cinta de manubrio'),
    ('declared_purpose', 'Perno de patilla', 'Perno de postiza'),
    ('declared_purpose', 'Perno de portacaramagiola', 'Perno de portabotella'),
    ('fender_mount_kind', 'Correas a horquilla/tija', 'Correas a la horquilla o al poste de asiento'),
    ('fender_mount_kind', 'Tornillos de guardabarros del cuadro', 'Tornillos de tapabarros del cuadro'),
    ('hanger_interface', 'Patilla estándar (M10x1)', 'Postiza estándar (M10x1)'),
    ('light_mount_kind', 'Abrazadera de tija', 'Abrazadera al poste de asiento'),
    ('rear_derailleur_hanger_interface', 'Patilla estándar (M10x1)', 'Postiza estándar (M10x1)'),
    ('rear_derailleur_hanger_interface', 'Sin patilla (single speed)', 'Sin postiza (una velocidad)'),
    ('shifter_control_style', 'Palanca en punta de manillar (bar-end)', 'Palanca en punta del manubrio (bar-end)'),
    ('shifter_control_style', 'Integrado con la maneta de freno', 'Integrado con la manilla de freno'),
]


DEFINITION_METADATA = {
    'adapter_to': {'label': 'Conexión de salida del adaptador'},
    'axle_fit': {'label': 'Eje que acepta'},
    'bottle_bosses_count': {'label': 'Cantidad de anclajes roscados para portabotella'},
    'cage_mount': {'label': 'Fijación del portabotella'},
    'crank_axle_interface_by_member': {'label': 'Unión al eje de cada biela'},
    'crank_axle_interface_declarations': {'label': 'Uniones documentadas entre biela y eje'},
    'dropper_actuation': {'label': 'Accionamiento del poste telescópico'},
    'hub_interface': {'label': 'Conexión de la maza'},
    'hanger_interface': {'label': 'Tipo de postiza'},
    'hanger_model_code': {'label': 'Código de la postiza / fusible'},
    'lever_inline_hydraulic_ports': {'label': 'Conexiones de la manilla hidráulica en línea'},
    'rear_drive_interface': {'label': 'Sistema de montaje del piñón trasero'},
    'rear_derailleur_hanger_interface': {'label': 'Montaje del cambio trasero'},
    'rotor_mount_out': {'label': 'Fijación del disco de salida'},
    'seatpost_kind': {'label': 'Tipo de poste de asiento'},
    'seatpost_offset_mm': {'label': 'Retroceso del poste de asiento'},
    'smallest_cog_fit': {'label': 'Montaje del piñón más pequeño'},
    'tire_tubeless_ready': {
        'label': 'Apto para usar sin cámara (Tubeless Ready)',
        'description': 'Indica si el neumático declara compatibilidad Tubeless Ready.',
    },
    'tire_width_in': {
        'label': 'Ancho nominal (pulgadas)',
        'description': 'Ancho nominal del neumático declarado en pulgadas. No se deriva automáticamente del nombre comercial.',
    },
    'tire_width_mm': {
        'label': 'Ancho',
        'description': 'Ancho nominal del neumático declarado en milímetros. Se conserva separado de pulgadas para no inventar conversiones nominales.',
    },
    'wheel_size': {
        'label': 'Tamaño de rueda',
        'description': 'Rodado nominal declarado para el neumático; no reemplaza una medida ETRTO cuando esa precisión está disponible.',
    },
}


TEMPLATE_METADATA = {
    'bottle_cage': ('Portabotella', ''),
    'derailleur_hanger': (
        'Postiza / fusible de cambio',
        'Pieza reemplazable que une el cambio trasero al cuadro; se confirma por cuadro, modelo y fijación.',
    ),
    'derailleur_hanger_extender': (
        'Extensor de postiza',
        'Extensor que cambia la posición del cambio trasero.',
    ),
    'handlebar_covering': ('Cinta o funda de manubrio', ''),
    'rim_brake': ('Freno de aro / V-Brake', 'Frenos tipo V-Brake o cantilever'),
    'seat_clamp': ('Abrazadera del poste de asiento', ''),
    'seatpost': ('Poste de asiento', 'Poste que une el asiento al cuadro, fijo o telescópico.'),
    'seatpost_shim': ('Adaptador reductor para poste de asiento', ''),
    'shifter': ('Manilla de cambio / shifter', 'Manilla de cambio; compatibilidad por posición, velocidades e indexado.'),
    'stem': ('Tee / potencia', ''),
}


TEMPLATE_LABEL_PATCHES = {
    'seatpost_shim': {
        'shim_inner_diameter_mm': 'Diámetro nominal del poste admitido',
        'shim_outer_diameter_mm': 'Diámetro interior del tubo del cuadro',
        'seatpost_shim_length_mm': 'Largo total del adaptador',
    },
}


TEMPLATE_HELPER_PATCHES = {
    'bicycle': {
        'assembly_wheel_members': 'Cada rueda conserva medidas y montajes propios. Compartir diámetro no aprueba neumático ni cassette. La posición delantera no prohíbe por sí sola una transmisión documentada; declarar el puerto que existe.',
        'assembly_frame_fitment_claims': 'Una holgura o un OLD admitido conserva rueda, montaje, tapabarros y fuente. El ancho propio del cuadro no es el conjunto de anchos de maza permitidos. Una declaración condicionada necesita sus condiciones.',
    },
    'brake_lever': {
        'brake_actuation': 'Cómo acciona esta manilla. Una manilla de cable que mueve un convertidor sigue siendo mecánica.',
        'lever_cable_pull': 'El tiro que ESTA manilla entrega. Lo que un cáliper exige es otra celda en otra pieza, y una no implica la otra.',
        'brake_bleed_ports': 'Sólo puertos que el procedimiento OEM identifica para purgar esta manilla. No convierte un tornillo de sellado en purgador.',
        'handlebar_clamp_mm': 'Diámetro exterior de la sección donde se fija esta manilla. No se restringe a 22,2 o 23,8 ni se deduce del tiro.',
        'lever_hydraulic_role': 'La manilla auxiliar en línea conecta con un mando principal y con el resto del circuito. No es un par de manillas.',
        'lever_cable_interface': 'Una manilla en línea puede actuar sobre la funda con el cable pasante. Ambos usos requieren documentación del mismo modelo.',
        'lever_cable_head_profiles': 'Describe el alojamiento de esta manilla. Doble cabeza describe un cable sin cortar, no un alojamiento universal.',
        'brake_piece_hydraulic_ports': 'Salidas hidráulicas de la manilla principal. La auxiliar en línea tiene su propia tabla de conexiones.',
    },
    'brake_shift_combined_control': {
        'combined_control_brake_configurations': 'Una configuración completa por fila. El líquido, el tiro y el conector se declaran junto al accionamiento al que pertenecen, así que una manilla de cable no puede llevar un fluido y una hidráulica no puede llevar un tiro. Dos líquidos aprobados son dos filas completas, cada una con su sistema y su fuente: compartir clase de fluido no es una aprobación, y lo aprobado para un mando no vale para el otro por venir en la misma caja. El conector y su especificación describen el extremo externo, así que sólo se declaran donde se declaró que ese extremo existe. Si el cable termina en un conversor hidráulico externo, el mando sigue siendo de cable. El líquido y el conector hidráulico pertenecen al conversor o cáliper y se documentan en la ficha de esa pieza.',
    },
    'derailleur_hanger': {
        'bolt_pattern': 'Sujeción publicada, por ejemplo un perno M8. Dos patas de cambio distintas pueden compartir perno sin compartir código ni calce: el perno no identifica la pieza.',
        'hanger_frame_interface': 'Cómo se une esta pieza al cuadro. UDH es una postiza física sobre una unión estandarizada; un cambio Full Mount sustituye la postiza y por eso no es una opción de esta ficha.',
    },
    'frame': {
        'assembly_frame_fitment_claims': 'Una holgura o un OLD admitido conserva rueda, montaje, tapabarros y fuente. El ancho propio del cuadro no es el conjunto de anchos de maza permitidos. Una declaración condicionada necesita sus condiciones.',
    },
    'hub_brake': {
        'brake_actuation': 'Accionamiento del freno de esta rueda. No deducir el sistema de la otra rueda ni bloquear una manilla sólo porque existe contrapedal detrás.',
    },
    'hydraulic_disc_brake': {
        'kit_members': 'Una fila por pieza física incluida, con su perfil propio: cada manilla, cada cáliper, cada línea, rotor, adaptador o pastilla. Dos piezas del mismo modelo son dos filas. Las medidas y conexiones viven en el perfil de cada pieza, nunca en esta raíz.',
        'brake_circuits': 'Un circuito por freno accionado: qué manilla mueve qué cáliper o mecanismo y por qué línea, apuntando a las filas de piezas. El líquido con que se entrega es del circuito; el que cada pieza admite es de esa pieza. Declararlo no verifica que las piezas calcen.',
    },
    'mechanical_disc_brake': {
        'kit_members': 'Una fila por pieza física incluida, con su perfil propio: cada manilla, cada cáliper, cada línea, rotor, adaptador o pastilla. Dos piezas del mismo modelo son dos filas. Las medidas y conexiones viven en el perfil de cada pieza, nunca en esta raíz.',
        'brake_circuits': 'Un circuito por freno accionado: qué manilla mueve qué cáliper o mecanismo y por qué línea, apuntando a las filas de piezas. El líquido con que se entrega es del circuito; el que cada pieza admite es de esa pieza. Declararlo no verifica que las piezas calcen.',
    },
    'rim': {
        'bead_seat_diameter_mm': 'Diámetro del apoyo del talón en un aro para neumático con talón. Coincidir en este dato es necesario, pero no resuelve ancho, perfil, presión y método de montaje.',
        'rim_drilling_patterns': 'Sólo patrones de esta pieza, con el punto de referencia y la convención de la fuente. No convertir otros taladrados ofertados en hechos de este SKU.',
        'rim_internal_width_mm': 'Ancho interno del apoyo del talón según la fuente. No convertir una etiqueta ISO textual en una medición física sin identificar el estándar y el punto de referencia.',
        'rim_joint_designation': 'Designación de construcción OEM: no obliga a asignar un método metálico a un aro de otra construcción.',
        'rim_spoke_hole_diameter_mm': 'Agujero del aro para el niple, publicado por el fabricante. No es el calibre del rayo ni la medida de la llave.',
    },
    'rim_brake': {
        'kit_members': 'Una fila por pieza física incluida, con su perfil propio: cada manilla, cada mecanismo, cada línea, rotor, adaptador o pastilla. Dos piezas del mismo modelo son dos filas. Las medidas y conexiones viven en el perfil de cada pieza, nunca en esta raíz.',
        'brake_circuits': 'Un circuito por freno accionado: qué manilla mueve qué cáliper o mecanismo y por qué línea, apuntando a las filas de piezas. El líquido con que se entrega es del circuito; el que cada pieza admite es de esa pieza. Declararlo no verifica que las piezas calcen.',
    },
    'rim_strip': {
        'strip_fit_internal_width_max_mm': 'El rango de aro al que sirve esta tira, no su propio ancho.',
        'strip_fit_internal_width_min_mm': 'El rango de aro al que sirve esta tira, no su propio ancho.',
    },
    'seatpost': {
        'seatpost_kind': 'Poste de asiento completo. Un adaptador reductor tiene su propia ficha.',
    },
    'seatpost_shim': {
        'material': 'Material del adaptador indicado por la fuente. No determina qué materiales de cuadro o poste de asiento admite.',
        'seatpost_shim_shape': 'Una pieza concreta. No mezclar medidas de variantes ni juegos de adaptadores.',
        'shim_inner_diameter_mm': 'Medida nominal del poste de asiento que acepta esta pieza; no un intervalo de diámetros.',
        'shim_outer_diameter_mm': 'Medida nominal del ajuste interior del cuadro. No es el diámetro exterior del tubo ni el de su abrazadera.',
        'seatpost_shim_length_mm': 'Largo físico de esta pieza cuando la fuente lo publica; no determina la inserción mínima del poste de asiento en el cuadro.',
        'seatpost_shim_support_length_mm': 'Sólo la zona útil de apoyo declarada. No puede superar el largo total del adaptador.',
    },
    'shifter': {
        'handlebar_clamp_mm': 'Diámetro del manubrio que abraza este mando. En un par, cada mando declara el suyo en la tabla de unidades.',
        'shifter_control_style': 'Cómo se opera la palanca. Es una forma de mando, no una compatibilidad: dos gatillos distintos no son intercambiables por ser gatillos. Un mando integrado con la manilla de freno pertenece a la familia de mando combinado, y esa reasignación se hace con evidencia del producto, no por el título.',
    },
    'spoke': {
        'spoke_length_mm': 'Largo del producto según su referencia y punto de medición OEM. El cálculo para una rueda depende de maza, aro y patrón de radiado; no es una propiedad universal de un rayo de esta longitud.',
    },
    'tire': {
        'tire_general_max_pressures': 'Una fila por máximo que la fuente declara para esta variante sin condicionarlo a un perfil de aro. Conserva unidad, alcance y documento; no conviertas cifras. Los límites condicionados van en las declaraciones de montaje. Fuentes discrepantes requieren revisión antes de usar sus límites.',
    },
    'tubeless_tape': {
        'tape_width_mm': 'Ancho de esta cinta, no ancho interno del aro. La elección, vueltas y preparación siguen las instrucciones del fabricante para ese aro; no se añade automáticamente una diferencia universal de milímetros.',
        'tubeless_tape_application': 'Aro, ancho, vueltas y condiciones que el fabricante declara para esta cinta; no inferirlos del ancho.',
    },
    'wheel': {
        'assembly_wheel_members': 'Cada rueda conserva medidas y montajes propios. Compartir diámetro no aprueba neumático ni cassette. La posición delantera no prohíbe por sí sola una transmisión documentada; declarar el puerto que existe.',
        'wheel_compatible_claims': 'Lo que el fabricante declara que esta rueda acepta. No es lo que viene en la caja, que va en los miembros del conjunto, y ninguna de las dos cosas implica la otra: una rueda puede venir con un neumático que no es el único que acepta, y aceptar uno que no incluye. Un diámetro igual no es una declaración de compatibilidad.',
    },
}


JSON_STRING_RENAMES = [
    ('Palanca en punta de manillar (bar-end)', 'Palanca en punta del manubrio (bar-end)'),
    ('Integrado con la maneta de freno', 'Integrado con la manilla de freno'),
    ('Diámetro de manillar', 'Diámetro del manubrio'),
    ('PCD de brida izquierda', 'Diámetro del círculo de hoyos izquierdo (PCD)'),
    ('PCD de brida derecha', 'Diámetro del círculo de hoyos derecho (PCD)'),
    ('Centro de maza a brida izquierda', 'Del centro de la maza al círculo de hoyos izquierdo'),
    ('Centro de maza a brida derecha', 'Del centro de la maza al círculo de hoyos derecho'),
    ('Distancia entre bridas', 'Distancia entre los círculos de hoyos'),
    ('maneta', 'manilla'),
    ('cubierta', 'neumático'),
    ('Abrazadera de tija', 'Abrazadera al poste de asiento'),
    ('Perímetro máx. (tija aero)', 'Perímetro máx. (poste aerodinámico)'),
    ('Abrazadera a tija', 'Abrazadera al poste de asiento'),
    ('Modelo/generación de tija cubiertos por la declaración', 'Modelos o generaciones de poste de asiento incluidos en la declaración'),
    ('Ancho de cubierta mínimo', 'Ancho mínimo del neumático'),
    ('Ancho de cubierta máximo', 'Ancho máximo del neumático'),
    ('Patilla o montaje objetivo', 'Postiza o montaje objetivo'),
    ('Tija telescópica', 'Poste telescópico'),
    ('Maneta', 'Manilla'),
    ('Llanta de referencia de la cubierta', 'Aro de referencia del neumático'),
    ('Con guardabarros', 'Con tapabarros'),
    ('Asiento de tija', 'Alojamiento del poste de asiento'),
    ('Patilla de cambio', 'Postiza de cambio'),
    ('Tubo de sillín', 'Tubo de asiento'),
    ('Ángulo de sillín', 'Ángulo del tubo de asiento'),
    ('Cubierta', 'Neumático'),
    ('Fila de la maneta', 'Fila de la manilla'),
]


def q(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def json_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def json_replace_sql(column: str, old: str, new: str) -> str:
    old_json = json_string(old)
    new_json = json_string(new)
    return (
        f"replace({column}::text,{q(old_json)},{q(new_json)})::jsonb"
    )


def compile_sql(version: str) -> tuple[str, str]:
    definition_keys = list(DEFINITION_METADATA)
    template_keys = sorted(
        set(TEMPLATE_METADATA) | set(TEMPLATE_LABEL_PATCHES) | set(TEMPLATE_HELPER_PATCHES)
    )
    nested_rename_map: dict[str, str] = {}
    for _, old, new in OPTION_RENAMES:
        if old in nested_rename_map and nested_rename_map[old] != new:
            raise ValueError(f'Conflicting nested rename for {old!r}')
        nested_rename_map[old] = new
    for old, new in JSON_STRING_RENAMES:
        if old in nested_rename_map and nested_rename_map[old] != new:
            raise ValueError(f'Conflicting nested rename for {old!r}')
        nested_rename_map[old] = new
    nested_json_renames = list(nested_rename_map.items())
    all_old_json_strings = list(nested_rename_map)

    lines = [
        '-- Chilean-Spanish option, row-schema and helper vocabulary (2026-09-19).',
        '-- Stable definition/option ids and codes are preserved. Compatibility rules',
        '-- keep their structure; only operator-facing strings and matching legacy',
        '-- JSON values move atomically to the local wording.',
        f'-- Generated by scripts/inventory/compile_chilean_bicycle_option_language.py --version {version}.',
        'begin;',
        "set local lock_timeout='5s';",
        "set local statement_timeout='180s';",
        'do $guard$ begin',
        ' if (select count(*) from public.spec_definitions where tenant_id is null and key in ('
        + ','.join(q(k) for k in definition_keys)
        + f')) <> {len(definition_keys)} then',
        "  raise exception 'A Chilean-language definition is missing';",
        ' end if;',
        ' if (select count(*) from public.spec_templates where tenant_id is null and is_active and key in ('
        + ','.join(q(k) for k in template_keys)
        + f')) <> {len(template_keys)} then',
        "  raise exception 'A Chilean-language template is missing';",
        ' end if;',
    ]
    for key, old, new in OPTION_RENAMES:
        lines.extend([
            ' if (select count(*) from public.spec_definition_values v join public.spec_definitions d '
            'on d.id=v.spec_definition_id where d.tenant_id is null '
            f'and d.key={q(key)} and v.label in ({q(old)},{q(new)})) <> 1 then',
            f"  raise exception 'Option preimage is ambiguous for {key}: {old}';",
            ' end if;',
        ])
    for category_id, old_name, old_path, new_name, new_path in CATEGORY_RENAMES:
        lines.extend([
            ' if (select count(*) from public.product_categories where '
            f'id={q(category_id)}::uuid and tenant_id={q(AUDITED_TENANT_ID)}::uuid '
            f'and (name,full_path) in (({q(old_name)},{q(old_path)}),({q(new_name)},{q(new_path)}))) <> 1 then',
            f"  raise exception 'Category preimage is ambiguous for {category_id}';",
            ' end if;',
            ' if exists(select 1 from public.product_categories where '
            f'tenant_id={q(AUDITED_TENANT_ID)}::uuid and id<>{q(category_id)}::uuid '
            f'and (name={q(new_name)} or full_path={q(new_path)})) then',
            f"  raise exception 'Category target already exists for {category_id}';",
            ' end if;',
        ])
    reference_predicate = ' or '.join(
        f"position({q(json_string(old))} in r.fact_values::text)>0"
        for old in all_old_json_strings
    )
    affected_predicate = ' or '.join(
        f"position({q(json_string(old))} in d.validation_rules::text)>0"
        for old, _ in nested_json_renames
    )
    lines.extend([
        " if (select count(*) from pg_catalog.pg_trigger g where g.tgrelid='public.spec_definitions'::regclass "
        "and g.tgname='spec_rows_definition_guard' and not g.tgisinternal and g.tgenabled='O') <> 1 then",
        "  raise exception 'The structured-row definition guard is missing or disabled';",
        ' end if;',
        " if (select count(*) from pg_catalog.pg_trigger g where g.tgrelid='public.spec_facts'::regclass "
        "and g.tgname='spec_rows_fact_guard' and not g.tgisinternal and g.tgenabled='O') <> 1 then",
        "  raise exception 'The structured-row fact guard is missing or disabled';",
        ' end if;',
        " if (select count(*) from pg_catalog.pg_trigger g where g.tgrelid='public.spec_templates'::regclass "
        "and g.tgname='spec_coherence_publication_guard' and not g.tgisinternal and g.tgenabled='O') <> 1 then",
        "  raise exception 'The template coherence guard is missing or disabled';",
        ' end if;',
        ' if exists(select 1 from public.product_spec_references r where '
        + reference_predicate + ') then',
        "  raise exception 'An immutable product reference contains old operator vocabulary';",
        ' end if;',
        'end $guard$;',
        # The trigger must be suspended before any update to spec_definitions;
        # PostgreSQL refuses ALTER TABLE after that table has pending trigger
        # events, even when the earlier update did not touch rows_schema.
        'create temporary table chilean_language_affected_row_definitions('
        'definition_id uuid primary key) on commit drop;',
        'insert into chilean_language_affected_row_definitions(definition_id) '
        'select d.id from public.spec_definitions d where d.tenant_id is null '
        "and d.validation_rules ? 'rows_schema' and (" + affected_predicate + ');',
        'alter table public.spec_definitions disable trigger spec_rows_definition_guard;',
        'alter table public.spec_templates disable trigger spec_coherence_publication_guard;',
    ])

    for key, metadata in DEFINITION_METADATA.items():
        assignments = []
        comparisons = []
        for column, value in metadata.items():
            assignments.append(f'{column}={q(value)}')
            comparisons.append(f'{column} is distinct from {q(value)}')
        assignments.append('updated_at=now()')
        lines.append(
            'update public.spec_definitions set ' + ','.join(assignments)
            + f' where tenant_id is null and key={q(key)} and ('
            + ' or '.join(comparisons) + ');'
        )

    for key, old, new in OPTION_RENAMES:
        lines.append(
            'update public.spec_definition_values v set '
            f'label={q(new)}, reading_terms=case when {q(old)}=any(coalesce(v.reading_terms,ARRAY[]::text[])) '
            f'then v.reading_terms else coalesce(v.reading_terms,ARRAY[]::text[])||{q(old)}::text end, updated_at=now() '
            'from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null '
            f'and d.key={q(key)} and v.label={q(old)};'
        )
        lines.append(
            'update public.spec_definitions d set allowed_values=(select jsonb_agg('
            f'case when e=to_jsonb({q(old)}::text) then to_jsonb({q(new)}::text) else e end order by ord) '
            'from jsonb_array_elements(d.allowed_values) with ordinality as t(e,ord)), updated_at=now() '
            f'where d.tenant_id is null and d.key={q(key)} and jsonb_typeof(d.allowed_values)=\'array\' '
            f'and d.allowed_values @> to_jsonb(array[{q(old)}::text]);'
        )
        lines.append(
            'update public.spec_templates t set '
            f'form_contract={json_replace_sql("t.form_contract", old, new)}, updated_at=now() '
            'where t.tenant_id is null and t.is_active '
            f'and position({q(json_string(old))} in t.form_contract::text)>0;'
        )
        lines.append(
            'update public.product_spec_values p set '
            f'value_text=case when p.value_text={q(old)} then {q(new)} else p.value_text end, '
            f'value_option=case when p.value_option={q(old)} then {q(new)} else p.value_option end, '
            f'display_value=case when p.display_value={q(old)} then {q(new)} else p.display_value end, '
            'updated_at=now() from public.spec_definitions d '
            'where d.id=p.spec_definition_id and d.tenant_id is null '
            f'and d.key={q(key)} and (p.value_text={q(old)} or p.value_option={q(old)} or p.display_value={q(old)});'
        )

    for category_id, old_name, old_path, new_name, new_path in CATEGORY_RENAMES:
        lines.append(
            'update public.product_categories set '
            f'name={q(new_name)},full_path={q(new_path)},updated_at=now() '
            f'where id={q(category_id)}::uuid and tenant_id={q(AUDITED_TENANT_ID)}::uuid '
            f'and (name,full_path)=({q(old_name)},{q(old_path)});'
        )

    # A row-schema label or enum is part of the saved document contract. The
    # production guard correctly rejects changing it while facts exist. Record
    # the exact affected definitions, suspend only that definition guard, move
    # schemas and saved documents together, restore it, and validate every
    # affected schema plus both canonical and legacy saved copies.
    for old, new in nested_json_renames:
        old_json = json_string(old)
        lines.extend([
            'update public.spec_definitions d set '
            f'validation_rules={json_replace_sql("d.validation_rules", old, new)}, updated_at=now() '
            f'where d.tenant_id is null and position({q(old_json)} in d.validation_rules::text)>0;',
            'update public.spec_templates t set '
            f'form_contract={json_replace_sql("t.form_contract", old, new)}, updated_at=now() '
            'where t.tenant_id is null and t.is_active '
            f'and position({q(old_json)} in t.form_contract::text)>0;',
            'update public.spec_facts f set '
            f'value_json={json_replace_sql("f.value_json", old, new)}, updated_at=now() '
            'from public.spec_definitions d where d.id=f.spec_definition_id and d.tenant_id is null '
            f'and f.value_json is not null and position({q(old_json)} in f.value_json::text)>0;',
            'update public.product_spec_values p set '
            f'value_json={json_replace_sql("p.value_json", old, new)}, updated_at=now() '
            'from public.spec_definitions d where d.id=p.spec_definition_id and d.tenant_id is null '
            f'and p.value_json is not null and position({q(old_json)} in p.value_json::text)>0;',
        ])

    lines.extend([
        # Flush the repository's deferred metadata guards before ALTER TABLE;
        # PostgreSQL otherwise reports pending trigger events. At this point
        # definitions, templates and saved values already contain one coherent
        # vocabulary, so those guards evaluate the final state.
        'set constraints all immediate;',
        'alter table public.spec_definitions enable trigger spec_rows_definition_guard;',
        'alter table public.spec_templates enable trigger spec_coherence_publication_guard;',
        'do $revalidate$ declare r record; begin',
        ' for r in select d.validation_rules->\'rows_schema\' as schema '
        'from public.spec_definitions d join chilean_language_affected_row_definitions a '
        'on a.definition_id=d.id loop',
        '  perform public.spec_rows_schema_validate_internal_v1(r.schema);',
        ' end loop;',
        ' for r in select d.validation_rules->\'rows_schema\' as schema,f.value_json as value '
        'from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id '
        'join chilean_language_affected_row_definitions a on a.definition_id=d.id '
        'where f.value_json is not null loop',
        '  perform public.spec_rows_validate_internal_v1(r.schema,r.value);',
        ' end loop;',
        ' for r in select d.validation_rules->\'rows_schema\' as schema,p.value_json as value '
        'from public.product_spec_values p join public.spec_definitions d on d.id=p.spec_definition_id '
        'join chilean_language_affected_row_definitions a on a.definition_id=d.id '
        'where p.value_json is not null loop',
        '  perform public.spec_rows_validate_internal_v1(r.schema,r.value);',
        ' end loop;',
        ' for r in select t.id,t.form_contract from public.spec_templates t '
        'where t.tenant_id is null and t.is_active loop',
        '  perform public.spec_coherence_metadata_internal_v1('
        'r.form_contract,public.spec_coherence_fields_internal_v1(r.id));',
        ' end loop;',
        'end $revalidate$;',
    ])

    for key, (name, description) in TEMPLATE_METADATA.items():
        lines.append(
            f'update public.spec_templates set name={q(name)},description={q(description)},updated_at=now() '
            f'where tenant_id is null and is_active and key={q(key)} '
            f'and (name,coalesce(description,\'\')) is distinct from ({q(name)},{q(description)});'
        )

    for key, labels in TEMPLATE_LABEL_PATCHES.items():
        payload = json.dumps(labels, ensure_ascii=False, sort_keys=True)
        lines.append(
            "update public.spec_templates set form_contract=jsonb_set(form_contract,'{labels}',"
            f"coalesce(form_contract->'labels','{{}}'::jsonb)||{q(payload)}::jsonb),updated_at=now() "
            f"where tenant_id is null and is_active and key={q(key)} and form_contract->'labels' is distinct from "
            f"(coalesce(form_contract->'labels','{{}}'::jsonb)||{q(payload)}::jsonb);"
        )

    for key, helpers in TEMPLATE_HELPER_PATCHES.items():
        payload = json.dumps(helpers, ensure_ascii=False, sort_keys=True)
        lines.append(
            "update public.spec_templates set form_contract=jsonb_set(form_contract,'{helpers}',"
            f"coalesce(form_contract->'helpers','{{}}'::jsonb)||{q(payload)}::jsonb),updated_at=now() "
            f"where tenant_id is null and is_active and key={q(key)} and form_contract->'helpers' is distinct from "
            f"(coalesce(form_contract->'helpers','{{}}'::jsonb)||{q(payload)}::jsonb);"
        )

    lines.append('commit;')
    migration = '\n'.join(lines) + '\n'

    checks = []
    for key, metadata in DEFINITION_METADATA.items():
        predicates = ' and '.join(f'{column}={q(value)}' for column, value in metadata.items())
        checks.append(
            f'(select count(*) from public.spec_definitions where tenant_id is null and key={q(key)} and {predicates})=1'
        )
    for key, old, new in OPTION_RENAMES:
        checks.extend([
            '(select count(*) from public.spec_definition_values v join public.spec_definitions d '
            'on d.id=v.spec_definition_id where d.tenant_id is null '
            f'and d.key={q(key)} and v.label={q(new)})=1',
            '(select count(*) from public.spec_definition_values v join public.spec_definitions d '
            'on d.id=v.spec_definition_id where d.tenant_id is null '
            f'and d.key={q(key)} and v.label={q(old)})=0',
            '(select count(*) from public.spec_definitions d where d.tenant_id is null '
            f'and d.key={q(key)} and d.allowed_values @> to_jsonb(array[{q(new)}::text]) '
            f'and not d.allowed_values @> to_jsonb(array[{q(old)}::text]))=1',
            '(select count(*) from public.product_spec_values p join public.spec_definitions d '
            'on d.id=p.spec_definition_id where d.tenant_id is null '
            f'and d.key={q(key)} and (p.value_text={q(old)} or p.value_option={q(old)} or p.display_value={q(old)}))=0',
        ])
    for category_id, _, _, new_name, new_path in CATEGORY_RENAMES:
        checks.append(
            '(select count(*) from public.product_categories where '
            f'id={q(category_id)}::uuid and tenant_id={q(AUDITED_TENANT_ID)}::uuid '
            f'and name={q(new_name)} and full_path={q(new_path)})=1'
        )
    for old, _ in nested_json_renames:
        old_json = json_string(old)
        checks.extend([
            '(select count(*) from public.spec_definitions where tenant_id is null '
            f'and position({q(old_json)} in validation_rules::text)>0)=0',
            '(select count(*) from public.spec_templates where tenant_id is null and is_active '
            f'and position({q(old_json)} in form_contract::text)>0)=0',
            '(select count(*) from public.spec_facts f join public.spec_definitions d '
            'on d.id=f.spec_definition_id where d.tenant_id is null and f.value_json is not null '
            f'and position({q(old_json)} in f.value_json::text)>0)=0',
            '(select count(*) from public.product_spec_values p join public.spec_definitions d '
            'on d.id=p.spec_definition_id where d.tenant_id is null and p.value_json is not null '
            f'and position({q(old_json)} in p.value_json::text)>0)=0',
        ])
    for key, (name, description) in TEMPLATE_METADATA.items():
        checks.append(
            f'(select count(*) from public.spec_templates where tenant_id is null and is_active and key={q(key)} '
            f'and name={q(name)} and coalesce(description,\'\')={q(description)})=1'
        )
    for key, labels in TEMPLATE_LABEL_PATCHES.items():
        for field, label in labels.items():
            checks.append(
                f'(select count(*) from public.spec_templates where tenant_id is null and is_active and key={q(key)} '
                f'and form_contract->\'labels\'->>{q(field)}={q(label)})=1'
            )
    for key, helpers in TEMPLATE_HELPER_PATCHES.items():
        for field, helper in helpers.items():
            checks.append(
                f'(select count(*) from public.spec_templates where tenant_id is null and is_active and key={q(key)} '
                f'and form_contract->\'helpers\'->>{q(field)}={q(helper)})=1'
            )
    old_word_regex = r'\m(brida|bridas|tija|tijas|sillín|sillines|patilla|patillas|portabidón|portacaramagiola|manillar|manillares|maneta|manetas|guardabarros)\M'
    checks.extend([
        "(select count(*) from pg_catalog.pg_trigger g where g.tgrelid='public.spec_definitions'::regclass "
        "and g.tgname='spec_rows_definition_guard' and not g.tgisinternal and g.tgenabled='O')=1",
        "(select count(*) from pg_catalog.pg_trigger g where g.tgrelid='public.spec_facts'::regclass "
        "and g.tgname='spec_rows_fact_guard' and not g.tgisinternal and g.tgenabled='O')=1",
        "(select count(*) from pg_catalog.pg_trigger g where g.tgrelid='public.spec_templates'::regclass "
        "and g.tgname='spec_coherence_publication_guard' and not g.tgisinternal and g.tgenabled='O')=1",
        '(select count(*) from public.spec_definitions where tenant_id is null and '
        f'(label~*{q(old_word_regex)} or coalesce(description,\'\')~*{q(old_word_regex)} or allowed_values::text~*{q(old_word_regex)} or validation_rules::text~*{q(old_word_regex)}))=0',
        '(select count(*) from public.spec_templates where tenant_id is null and is_active and '
        f'(name~*{q(old_word_regex)} or coalesce(description,\'\')~*{q(old_word_regex)} or form_contract::text~*{q(old_word_regex)}))=0',
    ])
    verifier = (
        '-- Verifier: fails until the local vocabulary is consistent in labels, options, rows and saved JSON.\n'
        'select 1/(case when ' + '\n and '.join(checks)
        + ' then 1 else 0 end) as chilean_bicycle_option_language_ok;\n'
    )
    return migration, verifier


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', default='20260919253000')
    args = parser.parse_args()
    migration, verifier = compile_sql(args.version)
    slug = f'{args.version}_chilean_bicycle_option_language.sql'
    migration_path = ROOT / 'supabase' / 'migrations' / slug
    verifier_path = ROOT / 'supabase' / 'manual_checks' / 'verification' / slug
    migration_path.write_text(migration, encoding='utf-8')
    verifier_path.write_text(verifier, encoding='utf-8')
    print(
        f'wrote {migration_path.relative_to(ROOT)} and verifier: '
        f'{len(OPTION_RENAMES)} options, {len(DEFINITION_METADATA)} definitions, '
        f'{len(TEMPLATE_METADATA)} templates, '
        f'{len({old for _, old, _ in OPTION_RENAMES} | {old for old, _ in JSON_STRING_RENAMES})} nested strings, '
        f'{len(CATEGORY_RENAMES)} categories'
    )


if __name__ == '__main__':
    main()
