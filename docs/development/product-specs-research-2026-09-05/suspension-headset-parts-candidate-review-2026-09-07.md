# Suspensión/dirección — dictamen independiente del paquete final (2026-09-07)

Lectura y veredicto. No edité el candidato, el motor, la migración ni la base.
Mis sondas corrieron contra el catálogo **sin modificar**, con archivos de casos
propios en el scratchpad.

**Veredicto: publicable.** Un hallazgo sustantivo (SH‑1) que no bloquea la
migración pero debe resolverse **antes de registrar hechos** bajo esa regla, y
dos precisiones sobre afirmaciones del documento de adjudicación.

## Integridad del paquete

Los siete SHA‑256 recomputados coinciden exactamente con los declarados, uno por
uno. Aritmética del paquete verificada: 35 definiciones nuevas + 10 reutilizadas
= 45; 45 opciones; 4 plantillas; 53 usos. `scope = new_global_metadata_only`.

Las 10 reutilizadas son `color, inner_diameter_mm, kit_members, material,
max_tire_width_mm, pack_quantity, spec_evidence_source, thickness_mm,
thru_axle_thread, wheel_part_interfaces`. Que `thru_axle_thread`,
`inner_diameter_mm`, `thickness_mm` y `max_tire_width_mm` aparezcan en
`reused_definitions` y **no** en `records.spec_definitions` es la prueba
documental de que el retiro a `legacy` es de plantilla y deja intacta la
definición compartida.

Superficie de escritura de `20260908011000`: sólo `spec_templates`,
`spec_template_fields`, `spec_definitions`, `spec_definition_values`. La huella
de cuatro tablas —`spec_facts`, `products`, `product_spec_references`,
`category_tech_mappings`— se toma antes y se afirma sin cambios dentro de la
misma transacción. El pin del motor es
`ac0738d5c2039412b603dc71adc41721`, **el mismo que verifiqué en la revisión de
no‑transmisión**; guardas de colisión de clave y de deriva sobre las cuatro
tablas, con la misma forma de igualdad por `jsonb_object_agg`. Es el generador
ya auditado, parametrizado.

## Los seis ejes, medidos con doce sondas adversariales

Cada sonda esperaba deliberadamente «sin bloqueo», de modo que cualquier
bloqueo aparece como diferencia. Resultados reales, no lectura de intención:

| Sonda | Resultado |
|---|---|
| separador de geometría propietaria con diámetros circulares | bloquea `row_field_applicability` |
| forma «Intervalo» cargando además la cifra nominal | bloquea `row_field_applicability` |
| intervalo invertido (min > max) | bloquea `row_shape` |
| extremo apuntando a una configuración inexistente | bloquea `row_reference_unresolved` |
| dos extremos «Cuerpo» en la misma configuración | bloquea `row_shape` (vía `unique_by`) |
| dos medidas, cada una con sus dos extremos por id | limpio |
| tapa de kit + carbono + «Compatible declarado» | limpio — **no hereda** |
| araña + carbono + «Incompatible declarado» | limpio |
| araña + carbono + «Condicional» con condición escrita | bloquea `row_value_conflict` |

**Enlace estable de extremos (verificado y mejor de lo declarado).** No es una
convención: `form_contract.row_coherence.links` declara el vínculo
`shock_end_configurations.size_row_id → shock_size_declarations`, y el motor lo
resuelve contra el **id de fila**, con `configuration` sólo como `label_columns`.
Una referencia colgante bloquea. Confirmé además que el texto visible
(«7.875x2») **no** resuelve el vínculo: sólo el id lo hace.

**Variantes de separadores (verificado).** `inner_diameter_mm` y
`outer_diameter_mm` están permitidos sólo con `geometry_kind = 'Anillo circular'`,
e `interface_designation` es obligatoria en las dos formas no circulares. El par
ordenado interior/exterior por tanto sólo opera donde la comparación tiene
sentido geométrico, tal como se afirma.

**Nominal/rango/literal (verificado).** Partición limpia en tres: cada forma
permite y exige exactamente sus celdas, y ninguna pieza queda obligada a publicar
un rango. `fit_kind` mantiene separados interior y exterior de espiga.

**Alcance de las fuentes (verificado, incluida la afirmación negativa).** Volví a
leer la página de Park sobre araña y expansor: dice que el sistema es
"especially popular with the carbon steering columns" y **no contiene ninguna
prohibición**. La declaración del documento de adjudicación —que Park explica la
diferencia constructiva pero no aporta la prohibición, y que la fuente es Wolf
Tooth— es exacta. El ancla FOX está guardada sin convertir: `7.875 in` × `2 in`
con `972-01-490` en la etiqueta de configuración y la ficha como `source_url`.

## SH‑1 — la regla de carbono no admite la declaración contraria de un fabricante

`value_when` sobre `status` exige el valor único `Incompatible declarado` cuando
`component_kind = 'Araña'` y `target_steerer_material = 'Carbono'`. Medido: una
fila «Condicional» que **explicita** la condición en su celda `conditions`
bloquea con `row_value_conflict`.

La consecuencia concreta: si el fabricante de una horquilla declara una espiga de
carbono que sí acepta araña —el caso habitual sería un inserto metálico unido en
la boca—, esta ficha no puede registrar esa declaración; la obliga a afirmar la
contraria. El campo se llama «estado declarado», y la regla hace que la ficha
declare por su cuenta.

Sobre la evidencia: la única fuente que pude leer esta ronda (Park) no sostiene
la prohibición, y el propio documento lo dice. La página de producto de Wolf
Tooth **no me entregó su contenido de especificación** en esta ronda, así que no
pude confirmar su redacción de forma independiente. Hasta donde puedo verificar,
una restricción universal, sin excepción y sobre todas las marcas descansa en la
declaración de un fabricante sobre su propio producto.

No lo presento como una orden. La resolución depende de una pregunta que no pude
cerrar con fuentes legibles: si la prohibición es un **hecho mecánico probado**
—y entonces la compuerta dura es correcta, y ninguna declaración OEM autoriza
guardar la contradicción— o una **política de fabricante**, en cuyo caso la ficha
debería poder registrar lo declarado y contradecirlo con su propia evidencia.

Nota de ejecutabilidad para quien decida: el arreglo intermedio evidente
—permitir `Condicional` además de `Incompatible declarado`— **no es expresable
hoy**. `ProductSpecRowValueRule` compara con un `expected` único y operador `eq`
fijado en código (`product_spec_row_conditions.dart:168-172`); no hay forma de
declarar un conjunto esperado sin tocar el motor. Las opciones reales son
conservar la compuerta tal cual, o retirarla y confiar en el helper, que ya dice
que la ausencia de declaración no equivale a aprobación.

Por qué no bloquea la publicación: corregir un `value_when` después es una
actualización de `form_contract` que las propias guardas de deriva obligan a
hacer explícita. Registrar hechos bajo una compuerta equivocada es mucho más
caro de deshacer. Publicar sí; decidir SH‑1 antes de llenar.

## Dos precisiones sobre el documento de adjudicación

1. **«Una fila sólo de recorrido ya no satisface ambas dimensiones»** es cierto
   como señal, no como rechazo. `length`, `length_unit`, `length_datum`, `stroke`
   y `stroke_unit` son celdas **estáticamente** obligatorias, y el motor entrega
   esas ausencias por `rows.missingRequired` como `row_incomplete`
   **no bloqueante** (`product_spec_contract.dart:301`). Medido: una fila sólo de
   recorrido no produce ningún bloqueo. Lo que sí bloquea es la ausencia total de
   la tabla, porque `shock_size_declarations` es obligatoria a nivel de plantilla.
   Es conducta del motor, no defecto del candidato; conviene que quede dicho con
   esa precisión antes de que alguien lea «no satisface» como «no se guarda».
2. **El vínculo se guarda por id de fila, no por la etiqueta visible.** Es lo
   correcto y lo declarado, pero es una trampa segura para el formulario y para
   cualquier importador: escribir «7.875x2» donde va `r1` produce un bloqueo cuyo
   mensaje habla de la configuración vinculada, no del formato del id.

## Lo que no verifiqué

No re‑consulté la preimagen viva de las 00:53:24Z ni la ausencia de colisiones en
producción; no re‑corrí los 37 casos SQL, las cinco regresiones del publicador ni
el ensayo en `.tmp/db/suspension-headset-parts-publication-tests.log`; no
comprobé el respaldo adicional ni el estado de aplicación de la migración. Esas
siguen siendo evidencia de root. Mi dictamen cubre hashes, superficie de
escritura, aritmética del paquete, y la conducta real del contrato y del motor
medida con doce sondas.

---

## Adenda 18:14Z — los artefactos cambiaron bajo el dictamen, y SH‑1 está resuelto

Al cerrar la ronda detecté que los cuatro artefactos de suspensión se
regeneraron a las **18:10:36** y la migración a las **18:11:18**, es decir
**después** de que los leí y hasheé. Todo lo anterior en este documento —tabla de
hashes, aritmética del paquete y las doce sondas— corresponde a las versiones
declaradas en `suspension-headset-parts-root-decisions-2026-09-07.md`, que ya no
son las del disco. Los hashes vigentes ahora son otros:

| Artefacto | SHA-256 al momento de esta adenda |
|---|---|
| `compile_suspension_headset_parts_catalog.py` | `5d32197b1e31dc4ce3e39d4b8a4c8ea2eb2f4aae452f4d94fc0bf9e88d80561e` |
| `suspension-headset-parts-catalog-2026-09-07.json` | `ae236f569f5dee24a23f5bce6adbd546de56f3ef29bcc2d25cd20271d9c1d4b0` |
| `suspension-headset-parts-cases-2026-09-07.json` | `7402081a03eaef225123e75cdd23a560ac81fceef41681b8ca086c0ccd3993d7` |
| `20260908011000_...sql` | `cf951e4af802f3adab783da64f9d4aa82c1c53f6a07f6d4bfdda0b2d98f28568` |

**SH‑1 queda resuelto en la versión nueva, y con la corrección acotada que yo no
supe formular.** El antecedente de `value_when` ya no es
`target_steerer_material = 'Carbono'` sino `anchor_contact = 'Carbono directo'`,
con una columna nueva `anchor_contact`
(`Carbono directo` / `Metal de espiga` / `Inserto de aleación OEM` / `Otro`)
obligatoria para la araña, `insert_model` abierta sólo para el inserto OEM, y
`conditions` exigida tanto para `Condicional` como para el inserto.

Yo había dicho que el arreglo intermedio no era expresable porque
`ProductSpecRowValueRule` compara con un único valor esperado. Eso sigue siendo
cierto del mecanismo, y era la conclusión equivocada: la solución no estaba en
ampliar el operador sino en **partir el antecedente**, separando el material de
la espiga del punto donde la araña apoya. Lo verifiqué con tres sondas contra el
catálogo nuevo, sin editarlo:

| Sonda | Resultado |
|---|---|
| araña + carbono + inserto de aleación OEM + «Compatible declarado» + condición | limpio — la declaración OEM **sí** se puede guardar |
| araña + carbono + contacto directo + «Condicional» | bloquea `row_value_conflict` — la contradicción probada sigue cerrada |
| araña + carbono sin declarar dónde apoya | `row_required_missing` no bloqueante |

Con eso el paquete cumple a la vez las dos exigencias que parecían opuestas: una
declaración OEM no autoriza guardar la contradicción mecánica comprobada, y la
ficha ya no obliga a afirmar una incompatibilidad donde el fabricante declara lo
contrario por una vía constructiva distinta.

Las dos precisiones del dictamen (la fila sólo de recorrido es `row_incomplete`
no bloqueante; el vínculo se guarda por id de fila y no por la etiqueta visible)
no las volví a medir contra la versión nueva. El resto del dictamen tampoco: no
re‑audité el paquete regenerado.
