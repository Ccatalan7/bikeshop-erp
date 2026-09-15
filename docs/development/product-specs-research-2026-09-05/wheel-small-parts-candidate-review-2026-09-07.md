# Revisión del candidato de rueda y piezas pequeñas

2026-09-07. Revisión del código ejecutable y del candidato, sin editar nada. Sólo lecturas; sin base
de datos, runtime, git, código ni subagentes.

| artefacto | SHA-256 |
|---|---|
| `compile_wheel_small_parts_catalog.py` | `97a4413142a614b6f5859cac1303676bd11b639765e96203bca44e7d44496162` |
| `wheel-small-parts-catalog-2026-09-07.json` | `c14f02ba8f898c106c13715a98d0abf82ef2301c2d7e0b838bb8c3538cc3514a` |
| `wheel-small-parts-cases-2026-09-07.json` | `ddcc2cef7005113f5fa45bede0b547055e377cbc957de1556565f9b391f5322b` |

Los tres coinciden. 9 plantillas, 49 definiciones, 74 usos, 33 casos.

# Dictamen: **sin defectos. Aplícalo.**

Los ocho hallazgos están resueltos, y varios por una vía mejor que la que yo propuse. No encontré
ningún eje ni requisito que un producto real de estas nueve ya no pueda expresar. Dos observaciones
al final, ninguna bloquea.

## Mi tercer error de mecanismo, y el último

**C-4.** Mi alternativa `not_in` también estaba mal, y por la razón que diste:
`evaluateProductSpecTemplateCondition`, en `product_spec_template_rules.dart:37`, whitelistea
exactamente `eq`, `in`, `lt`, `lte`, `gt`, `gte` **antes** de delegar. El conjunto más amplio que leí
—`neq`, `not_in`, `is_set`, `contains_any`— es del evaluador genérico de relaciones, no del parser de
la ficha. Confundí las dos capas, que es literalmente lo que advertiste.

Dos mecanismos equivocados seguidos para el mismo hallazgo, y la resolución no necesitaba ninguno:
retiraste el escalar y la contradicción desapareció con él. Lo dejo escrito porque el patrón de mi
error es el que importa — propuse dos veces desde una lectura parcial del motor en vez de verificar la
capa que realmente evalúa el contrato.

## Correcciones tuyas que acepto

- **VP-1C incluye látex**, no sólo butilo. Mi WS-7 lo decía mal, y el candidato ya trae
  `target_material` con Butilo, Látex, TPU y Otro.
- **No usar minoristas para sostener hechos mecánicos.** Me apoyé en títulos de tiendas para las
  designaciones de Mr. Tuffy sin haber leído la fuente primaria. El candidato marca esos casos como
  sintéticos, que es lo correcto: 32 de los 33 lo están.
- La excepción UST del artículo genérico y la exclusión de la ficha del VP-1 son **fuentes y alcances
  distintos**; el diseño las conserva por separado en vez de que una familia entera «apruebe UST».
- **No universalizar la falta de rosca** en adaptadores: «Asiento sin rosca» es una opción del
  vocabulario, no una regla.

## Qué verifiqué, familia por familia

**Ejes, roscas y asientos.** `wheel_part_interfaces` tipa la interfaz con `interface_kind` —métrica,
en pulgadas, asiento sin rosca, designación OEM—, diámetro y paso en las dos unidades, designación,
sentido de rosca y longitud de engrane, con las condiciones de fila que exigen el dato que
corresponde a cada tipo. Eso cierra WS-2 sin parche —`axle_diameter_thread` quedó `legacy` y `never`,
así que ya no hay dos dueños del hueco—, cierra WS-3 porque un M14 con su paso es ahora expresable
como valores, y cierra WS-10 porque una puntera sin rosca tiene su token propio. Y `axle_length_mm`
lleva `hub_axle_length_datum` como **prerrequisito**: iba a proponerlo y ya estaba.

**Retención.** `wheel_retention_configurations` guarda una fila por componente y configuración, con
posición, tipo, diámetro y longitud de vástago, `length_kind` exacta o rango con su par ordenado,
datum, asiento de cabeza, accionamiento, espaciadores y `target_old_mm`. Un par cuyos dos miembros
difieren ya se representa, y el `row_coherence` `retention_thread` ata cada configuración a su
interfaz de rosca. Los ocho escalares viejos quedaron retirados. WS-9 cerrado, incluida la cabeza y
los espaciadores que faltaban.

**Niples.** `nipple_tool_interfaces` separa el eje que faltaba: `location` distingue exterior de
interior de llanta, `shape` la forma, `dimension_mm` la medida y `measurement_basis` es requerido
cuando hay medida, más `spline_count` y `oem_tool`. Es más completo que lo que pedí en WS-6, y
`nipple_head` quedó retirado.

**Protectores.** `tire_liner_fitments` ata tamaño y ancho **en la misma fila**: `size_basis` elige
entre designación nominal y BSD declarado, y el ancho lleva `width_kind`, valor o rango con par
ordenado, y `width_unit` en mm o pulgadas —que es lo que hacía falta para un 27x1 1/8—. Las
condiciones de fila exigen la unidad cuando hay ancho. Se acabó el producto cartesiano de WS-8, y ya
no se obliga a convertir: los tres escalares viejos quedaron retirados.

**Reparación.** `repair_target_declarations` lleva destino, material, modelo, `status` con
Compatible, Incompatible y **Condicionado**, condiciones y fuente. La excepción UST cabe como
condicionada sin que nada afirme que la familia aprueba UST — que era el punto de WS-7 — y no hay
ningún booleano universal. `tubeless_repair_plug_configurations` exige `plug_model` e
`insertion_tool`, así que un repuesto ya dice a qué herramienta pertenece: WS-11 cerrado.

**Válvulas.** `valve_part_configurations` conserva origen, salida, modelo, designación de interfaz y
—lo de WS-12— `extension_kind` con «Reubica el obús» frente a «Sobre válvula con obús», más
`requires_removable_core` atado por un `value_when` de fila. Los cuatro escalares no publicados
desaparecieron, y con ellos el token corto: **no queda en todo el candidato ni una sola opción de
desconocimiento que no sea la forma larga**, ni en escalares ni en celdas de fila. WS-1 evitado aquí,
y tomo nota de que no afirmas haberlo corregido en `rim`, `rim_strip`, `tube` y `tubeless_valve`:
sigue abierto ahí.

**Compartidas.** Las siete que encontró la preimagen —`axle_nut_thread`, `wheel_position`,
`spec_evidence_source`, `color`, `material`, `pack_quantity`, `kit_members`— no se modifican.

**Casos.** 33, con 9 bloqueos esperados repartidos en `row_field_applicability`, `row_shape`,
`row_value_conflict` y `row_reference_unresolved`. Los dos últimos importan porque demuestran que el
`value_when` del obús y el enlace de rosca se ejercitan de verdad, no sólo se declaran. Los anclados a
OEM citan Robert Axle, Park Tool y Topeak; el resto va marcado como sintético.

## Dos observaciones, ninguna bloquea

**La cinta es la única familia sin tabla de declaración.** `tubeless_tape` recibió
`tubeless_tape_application` como texto, con un helper que pide llanta, ancho, vueltas y condiciones
del fabricante y prohíbe inferirlos del ancho. Es una elección defendible y no pierde ni falsea nada
—documenta sin fingir estructura—, pero es lo único del bloque que no se puede filtrar ni comparar.
Si algún día una tabla de anchos de llanta tiene que ser consultable, esta familia pedirá el mismo
tratamiento que las otras ocho. No propongo cambiarlo ahora.

**El vocabulario de material de reparación tiene forma de cámara.** Butilo, Látex, TPU y Otro
describen cámaras; el caso UST es un **cuerpo de neumático con forro interior de butilo**. La entrada
fiel es destino «Cuerpo de neumático» con estado Condicionado y el forro en `conditions`; el token de
material entonces o sobreafirma o cae en «Otro». Es representable y honesto por las dos vías, y sólo
señalo que en esa combinación se pierde la búsqueda por token. Tampoco propongo cambiarlo: inventar
un token de forro sin una fuente que lo pida sería justo lo que no toca hacer.

Queda pendiente, menor y ya señalado antes: `nipple_thread` sigue rotulando «15G (1.8 mm)» junto a
«14G» y «13G». No lo reclamaste como corregido y no es ambiguo.

Compuertas sin cambio: `fill_allowed`, `compatibility_rules_integrated`,
`all_product_assignment_review_complete`, `all_family_domain_review_complete`.

---

# Dictamen de la publicación: **aplicar**

Los siete SHA-256 que reportaste coinciden con los que recalculé: compilador
`20734742…`, catálogo `3b026514…`, casos `77efa582…`, preimagen `8f0d8c6e…`, paquete `761324e8…`,
migración `7391c7a5…`, verificador `601088666…`.

**El mismo publicador, sin variantes.** Quitando cabecera y documento, la migración es **idéntica** a
las de los bloques de 14 y de 10 ya aplicados.

**La corrección de `wheel_position` está completa y comprobada.** La definición viva trae exactamente
`Delantera`, `Trasera` y `Universal`; el candidato declara esas tres y ninguna más; y **«Par» no
aparece ni una vez** en el catálogo candidato ni en los casos. Los pares viven donde corresponde, en
la columna `position` de `wheel_retention_configurations`. La compartida no se toca.

**Las siete compartidas se leen y nunca se escriben.** 42 nuevas + 7 = 49, igual que el candidato, sin
solapamiento de claves y con **cero filas de opción apuntando a una compartida**. Las siete traen sus
opciones ordenadas por id —el orden con que el verificador compara—, idénticas a la preimagen, y con
`allowed_values` coincidiendo con el candidato; `material` con sus 29 y `axle_nut_thread` con sus 5.

**Integridad de los 174 registros:** cero campos hacia definición o plantilla desconocida, cero ids de
campo u opción repetidos, cero pares (plantilla, definición) o (definición, código) repetidos, cero
códigos fuera de forma, los 174 globales. Preimagen capturada a las 00:08:20Z con cero colisiones de
plantilla, y las compuertas del paquete en `false`.

Que el verificador de producción fallara antes de aplicar es lo esperado: afirma metadatos que aún no
existen.

---

# Dictamen del delta de rosca: **aplicar**

Tercera pasada, sobre la corrección de `wheel_part_interfaces` y el paquete nuevo. Leí
`wheel-small-parts-root-decisions-2026-09-07.md`. Los seis SHA-256 coinciden con los que recalculé:
compilador `6b950914…`, catálogo `1f38ce44…`, casos `5463a15b…`, paquete `78ace24d…`, migración
`a401264c…`, verificador `2abaf251…`. La preimagen sigue en `8f0d8c6e…`.

**El dictamen anterior queda sustituido por éste**: el candidato que aprobé llevaba el defecto, y
tienes razón en no haberlo publicado.

## La fuente sostiene la corrección, y la comprobé

No tomé tu diagnóstico como autoridad: abrí Park Tool, Basic Thread Concepts. Contiene literalmente la
designación **«10 mm x 26 TPI»** y describe estándares que mezclan diámetro métrico con paso SAE, de
origen italiano. Así que la unidad del diámetro y la del paso son independientes **como hecho de la
fuente**, no como preferencia de diseño, y la forma anterior —`Rosca métrica` frente a `Rosca en
pulgadas`— hacía inexpresable un eje real. Se me pasó al aprobar: revisé que la tabla tipara la
interfaz y no que su vocabulario admitiera el caso que la propia regresión
`rnd_root_metric_diameter_tpi_pitch` ya vigilaba.

## El delta hace exactamente lo que dice

`interface_kind` pasó a `Rosca`, `Asiento sin rosca` y `Designación OEM`, con `diameter_unit` (mm|in)
y `pitch_unit` (mm|tpi) como columnas separadas, cada una gobernando **sólo** sus propios valores:
`diameter_mm` exige `diameter_unit = mm`, `pitch_tpi` exige `pitch_unit = tpi`, y el paso entero está
condicionado a `Rosca`. Verifiqué las nueve condiciones de fila una por una.

Y los casos demuestran las dos mitades:

- `ws_metric_diameter_tpi_axle` —diámetro 10 mm con paso 26 TPI, citando el ejemplo de Park— **pasa
  sin incidencia**. Es el caso que antes no cabía.
- `ws_mixed_thread_systems` —`pitch_mm` y `pitch_tpi` en la misma declaración— **sigue bloqueando** con
  `row_field_applicability`, y `ws_imperial_thread_not_metric_pitch` lo bloquea en el sentido
  simétrico. Dos pasos en una sola declaración siguen prohibidos, que era la mitad que no había que
  perder.
- `ws_thread_pitch_unit_unknown` —un 26 sin decir en qué unidad— queda en `row_prerequisite` **no
  bloqueante**: conserva la cifra en vez de rechazarla, que es el tratamiento correcto de un
  desconocido.
- `ws_plain_seat_is_not_thread` mantiene cerrado el paso sobre un asiento sin rosca.

De paso, `ws_oem_125_pitch` registra el TRA225 como diámetro 12 con paso 1,25 mm: el hueco que
reporté en WS-9 queda cerrado **para `wheel_retention`**. Sigue abierto en `fork`, que usa el enum
publicado `thru_axle_thread`; lo dejo anotado para su bloque, no para éste.

## Paquete

42 nuevas + 7 compartidas = 49, igual que el candidato, sin solapamiento y con **cero filas de opción
apuntando a una compartida**. Las siete siguen idénticas a la preimagen, ordenadas por id y con sus
`allowed_values` coincidiendo; ninguna cambió respecto del candidato. `wheel_part_interfaces` se
inserta como definición nueva, así que la corrección **no toca nada publicado**, tal como dice tu
adjudicación.

Integridad de los 174 registros: cero colgantes, cero ids o pares repetidos, cero códigos fuera de
forma, los 174 globales. Y la migración sigue siendo **idéntica** a la del bloque de puntos de
contacto fuera de cabecera y documento: mismo publicador.

Que el verificador preaplicación falle es lo esperado.

**Aplícalo.**
