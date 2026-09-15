# Transmisión, piezas pequeñas: derailleur_hanger_extender, cassette_lockring, chainring_guard, fastener

2026-09-07. Sucesor reproducible del catálogo congelado
`all-family-port-cardinality-integrated-2026-09-07.json`
(`16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`) y sus casos congelados.

4 plantillas, 32 definiciones, 37 usos, 23 casos: 14 nuevos y 9 heredados ya adjudicados.
**27/27 en el test Dart parametrizado**, con los nueve heredados en verde.

Sin base de datos, migraciones, git, runtime ni subagentes. Sin llenado ni asignaciones. El
compilador importa `column`, `retire` y `table` de `compile_wheel_small_parts_catalog.py` y los
helpers de mobility **sin editar ninguno**.

## Tres correcciones, y una que retiré yo mismo

### DS-2 · `chainring_guard`: un círculo de pernos no es una norma de montaje

`chainring_bcd_mm` y `bolt_count` eran **requeridos e incondicionales**, así que una guarda que se
fija a las pestañas ISCG05 del cuadro o a un montaje directo propietario no tenía entrada verdadera:
o declaraba un BCD que no tiene, o quedaba pendiente para siempre.

Agregué `chainring_guard_mounts` con `mount_kind` —BCD, ISCG05, ISCG antiguo, montaje directo
declarado, otro—, con `bcd_mm` y `bolt_count` **condicionados al BCD** y la designación literal
condicionada al resto, más componente destino, condiciones y fuente. Retiré los dos escalares. El
helper dice que la marca no implica un BCD.

Positivo: ISCG05 con su designación, y por separado un BCD 104 con 4 pernos. Negativo:
`ds_guard_iscg_has_no_bcd` da `row_field_applicability` bloqueante. Desconocido: sin montaje,
`required_missing` no bloqueante.

### DS-3 · `cassette_lockring`: la rosca vivía como prosa dentro de una etiqueta

El vocabulario de `target_rear_drive_interface` lleva la rosca **dentro del texto del token** — uno
de ellos llega a nombrar *dos* roscas, la del piñón y la de la contratuerca izquierda. No había
ningún campo tipado para la rosca de la propia pieza.

Agregué `lockring_thread_interfaces` con exactamente la forma que acabas de corregir en el grupo de
rueda: `interface_kind` rosca / estriado / designación OEM, y **`diameter_unit` y `pitch_unit`
independientes**, cada uno gobernando sólo sus valores, más sentido de rosca. No toqué
`target_rear_drive_interface`: ese vocabulario es tuyo y lo gobierna el trabajo C-731.

Positivo: el token de piñón fijo se descompone en **dos filas**, la contratuerca con su sentido
izquierdo; y un diámetro en mm con paso en TPI pasa sin incidencia. Negativo: dos unidades de paso en
una declaración, y un estriado con paso, bloquean. Desconocido: sin rosca, `required_missing` no
bloqueante.

### DS-4 · `derailleur_hanger_extender`: el piñón alcanzable no tenía dueño ni límite

Wolf Tooth publica el piñón alcanzable **por modelo de cambio** y declara que la pieza reposiciona el
cambio para dar holgura con un piñón mayor y **no aumenta la capacidad**, que la fija la geometría del
cambio y su jaula. `claimed_max_cog_teeth` era un número suelto: no decía para qué cambio, y no tenía
nada que lo separara de una lectura de capacidad.

Agregué `hanger_extender_claims` con cambio destino, velocidades, jaula, piñón mayor alcanzable,
condiciones y fuente; requerido; y retiré el escalar. El helper dice literalmente que no es capacidad.
Positivo: una fila con su cambio, y dos cambios con alcances distintos. Desconocido: sin filas,
pendiente.

### DS-1 · `fastener`: hueco real que **no** corregí, y por qué

`fastener_kit_members` no tiene ninguna condición de celda, así que un miembro puede llevar
`thread_pitch_mm` **y** `thread_tpi` a la vez. Es el mismo defecto que acabas de cerrar en
`wheel_part_interfaces`, y es real.

Lo intenté con una columna que declarara la forma del paso, como en la corrección de rueda, y
**rompe `RCF47`**: esa fixture es el ejemplo de Park de diámetro métrico con TPI, adjudicada con cero
incidencias de fila y con el propósito escrito de «no reintroducir gating por dialecto». Exigir la
forma antes de aceptar una cifra publicada es exactamente ese gating.

La alternativa sería excluir directamente una celda contra la otra, y **no es expresable**: el parser
de la ficha admite `eq`, `in`, `lt`, `lte`, `gt` y `gte`, sin `not_set` ni negación —lo comprobé en
`product_spec_template_rules.dart`, la misma capa que ya me corrigió una vez—.

Así que dejé sólo el helper, que documenta sin condicionar, y **reporto el hueco en vez de taparlo**.
Cerrarlo pide una decisión tuya: o un operador de exclusión en el DSL de filas, o aceptar que en un
kit la exclusión queda como convención escrita. No inventé una regla para simular que está resuelto.

El lado escalar de `fastener` ya estaba bien y no lo toqué: `thread_pitch_mm` y `thread_tpi` están
condicionados a `thread_pitch_system`, y ese campo es opcional, de modo que una cifra publicada se
acepta sin obligar a declarar el dialecto.

## Una observación, sin proponer cambio

`hanger_interface` acota sus opciones a «Patilla estándar (M10x1)», «Direct mount» y el desconocido,
mientras la definición incluye además «UDH», «Direct mount (Shimano)» y «Con uña / claw». Es la misma
forma que el hueco de M14 en `hub_axle`: la opción existe en la definición y la plantilla la excluye.
Lo detecté porque mi propio caso usaba UDH y quedó rechazado por `constraint`. **No lo corrijo**: no
tengo fuente que muestre un extensor declarado para UDH, y sin ella ampliar el vocabulario sería
inventar el hueco en vez de comprobarlo.

## Errores míos durante la corrida

Dos, los dos por asumir en vez de leer. Usé `integer=True` en columnas de fila, y la validación de una
columna sólo admite `positive`, `min` y `max` — la integralidad la expresa el tipo. Como toda
`FormatException` sale como `configuration` con campo vacío, un solo error de columna ensuciaba diez
casos de dos plantillas. Y di por buena la corrección de DS-1 hasta que la fixture adjudicada la
rechazó.

## Lo que no hice

No toqué el catálogo congelado, ninguna definición compartida, ningún compilador que importo ni
`target_rear_drive_interface`. No deduje ningún paso desde el nominal ni ningún BCD desde la marca. No
convertí unidades. Ninguna fixture verifica un SKU: son casos de representación, y los tres anclados a
fuente citan Park Tool, Wolf Tooth y Sheldon Brown.

Compuertas sin cambio: `fill_allowed`, `compatibility_rules_integrated`,
`all_product_assignment_review_complete`, `all_family_domain_review_complete`.
