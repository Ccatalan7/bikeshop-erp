# ND09–ND11, ND13–ND20 y ND23–ND24 contra la base con condiciones por fila (2026-09-07)

Contraste de la revisión no-transmisión del 2026-09-06 con `all-family-row-conditions-integrated-2026-09-07.json` (`c12204e42f86423f…`). Operaciones y preimágenes de `scripts/inventory/product_spec_field_patches.py`. No se editó código, base, catálogos, pruebas ni runtime.

**Trece hallazgos revisados: A/B y las condiciones por fila resolvieron once por completo y cuatro dejan un residual. Lo que queda son cuatro huecos de campo o prerrequisito y siete campos de filas sin identidad; ocho más no pueden tenerla sin inventar un dato.**

**Representación frente a aprobación.** Ningún parche aprueba un montaje ni homologa una certificación. Una fila de certificación guarda lo que dice la etiqueta y el estado de su lectura; una capacidad declarada de una herramienta no autoriza la operación sobre un modelo concreto.

## 1. Veredicto por hallazgo

| Id | Estado | Qué resolvieron A/B y las condiciones por fila | Residual |
|---|---|---|---|
| ND09 | resuelto por A/B salvo la exclusión paso/TPI | La base tiene thread_pitch_mm, thread_tpi, thread_hand, length_datum (prerrequisito de length_mm), head_drive_size_mm, torx_size, strength_class_claim y fastener_kit_members; thread ya excluye el tipo Kit y el accionamiento ya no lleva tamaño. | Paso y TPI están permitidos bajo la misma condición y con el mismo prerrequisito: nada impide escribir los dos. Es la compuerta AG01, que quedó como diseño pendiente. |
| ND16 | resuelto por A/B salvo la asimetría del diámetro | bottle tiene bottle_retention_system, base_included e included_base_model; bottle_cage tiene cage_retention_system, ancho de tubo con par ordenado, separación y cantidad de insertos y lado de extracción. | El mismo campo de diámetro está condicionado en el portabidón y permitido siempre en la botella. |
| ND17 | resuelto por A/B salvo la presión máxima | co2_cartridge_configurations separa masa de gas, roscado, cantidad incluida, peso bruto y medidas del cartucho, con condición por fila que exige la designación de rosca cuando es roscado y el modelo declarado cuando la configuración es un cartucho compatible. | max_pressure_psi sigue permitido siempre, también para un inflador de CO2 y para un cartucho de recarga. |
| ND18 | resuelto por A/B salvo el token de público en el tipo | certification_claim quedó legacy; certification_configurations guarda norma, texto exacto, edición, mercado, alcance, tipo de evidencia y fecha; label_evidence_state separa el estado de lectura; intended_audience, helmet_construction, oem_size_label con su sistema y el par de circunferencias ya existen. | helmet_kind conserva la opción «Niño» junto a las de construcción, que es la mezcla que el hallazgo describe. |
| ND10 | resuelto por A/B salvo la identidad de las capacidades | tool_capabilities registra operación, estándar objetivo, admitida, medidas de interfaz, tamaño de drive, rango de velocidades, alcance de marca y adaptador, con condición por fila que exige el modelo del adaptador cuando se requiere; chain_tool_speeds ya admite multiherramienta. | Sin unique_by, la misma operación sobre el mismo estándar puede quedar admitida y no admitida a la vez. |
| ND11 | resuelto por A/B salvo la identidad del nivel de seguridad | Las guardas de ancho, alto, largo y diámetro del cable ya incluyen «Kit U + cable»; security_rating_claim quedó legacy y security_rating_configurations guarda componente, emisor, nivel, alcance, modelo, edición y certificado. | Sin unique_by, un mismo emisor puede otorgar dos niveles al mismo componente. |
| ND13 | resuelto por A/B salvo la identidad de las configuraciones | bike_attachment_kind y device_attachment_kind separan el anclaje a la bici de la unión al aparato; bar_fit_representation decide si el ajuste se declara por rango o por filas y condiciona el rango continuo; el par de diámetros está en scalar_ordered_pairs; bar_clamp_configurations guarda medida, método, espaciador y revisión con su condición por fila. | Sin unique_by, la misma medida con el mismo método puede repetirse con resultados distintos. |
| ND14 | resuelto por A/B salvo la identidad de los miembros | bag_rack_interface y rack_top_interface separan bolso→parrilla de parrilla→bici con sistema, generación, contraparte, configuración, pieza requerida y condiciones; auxiliary_part_requirements ya tiene unique_by por configuración y pieza; rack_mount_configurations guarda punto de montaje, diámetros, vanos y exclusiones; load_reference dice a qué se refiere la carga. | bag_member_configurations no tiene identidad; las dos interfaces tampoco, y ahí no hay identidad segura (ver límites). |
| ND15 | resuelto por A/B | kickstand_mount_standard nombra los patrones KSA con su separación, y existen separación medida, cantidad de pernos, rosca, referencia de la medida y altura instalada; los dos rangos están en scalar_ordered_pairs y ambos exigen la referencia como prerrequisito. | Ninguno. La compatibilidad con un cuadro concreto sigue siendo materia de relaciones. |
| ND19 | resuelto por A/B salvo la identidad de las lentes | lens_kind ya no existe en la plantilla: eyewear_lens_configurations guarda por lente el modelo, si viene incluida, fotocromía, polarización, espejo, tinte, categoría y VLT declarados. | Sin unique_by, la misma lente puede aparecer dos veces con propiedades contrarias. |
| ND20 | resuelto por A/B | sleeve ya admite chaqueta; oem_size_label y oem_size_system conservan la etiqueta y la guía exactas; intended_audience separa el público de gender_fit; fit_cut y fabric_composition_text existen. | Ninguno en campos. Que una M de dos marcas no sea la misma talla queda como límite del consumidor. |
| ND23 | resuelto por A/B salvo la identidad de la tabla nutricional | preparation_kind condiciona porción y volumen para lo preparado y masa neta y unidades por envase para lo envasado; milk quedó legacy frente a milk_in_recipe y milk_substitution_offered; nutrition_facts guarda nutriente, cantidad y base; allergen_note exige fuente declarada y evidencia; caffeine_mg tiene su base. | Sin unique_by, el mismo nutriente sobre la misma base puede llevar dos cantidades. |
| ND24 | resuelto por A/B | conflicting_claims existe en las dos plantillas que el hallazgo nombra, bike_bag y handlebar, y guarda el campo, el valor, la unidad, el tipo y la fecha de la fuente, el localizador y el contexto de medición. | Ninguno en campos. No propongo unique_by: dos afirmaciones distintas del mismo campo son justamente lo que el campo existe para guardar. |

## 2. Parches

| Id | Hallazgo | Operación | Plantilla / clave | Alcance |
|---|---|---|---|---|
| RND-ND09-thread_pitch_system | ND09 | add_field | fastener / thread_pitch_system | Sólo fastener. Declara en qué sistema publica el fabricante la designación, para que paso y TPI dejen de poder convivir. |
| RND-ND09-thread_pitch_mm-gate | ND09 | replace_field_contract | fastener / thread_pitch_mm | El motor no compara dos escalares entre sí, así que la exclusión se consigue condicionando cada uno a su sistema declarado. |
| RND-ND09-thread_tpi-gate | ND09 | replace_field_contract | fastener / thread_tpi | El motor no compara dos escalares entre sí, así que la exclusión se consigue condicionando cada uno a su sistema declarado. |
| RND-ND10-tool_capabilities-unique_by | ND10 | replace_unpublished_rows_schema | — / tool_capabilities | Dos filas con la misma operación y el mismo estándar y distinto valor de admitida son una contradicción, igual que la pareja de sensores del bloque de luces. Todas las columnas de la identidad son required, así que unique_by no las omite. |
| RND-ND11-security_rating_configurations-unique_by | ND11 | replace_unpublished_rows_schema | — / security_rating_configurations | Un mismo emisor no otorga dos niveles al mismo componente. El nivel se queda fuera de la identidad para que un cambio de nivel se vea como contradicción y no como fila nueva. Todas las columnas de la identidad son required, así que unique_by no las omite. |
| RND-ND13-bar_clamp_configurations-unique_by | ND13 | replace_unpublished_rows_schema | — / bar_clamp_configurations | Una medida discreta con su método de calce identifica la configuración; el mismo diámetro con y sin espaciador son dos filas legítimas. Todas las columnas de la identidad son required, así que unique_by no las omite. |
| RND-ND14-bag_member_configurations-unique_by | ND14 | replace_unpublished_rows_schema | — / bag_member_configurations | Cada miembro del conjunto se nombra una vez; las alforjas izquierda y derecha son miembros distintos. Todas las columnas de la identidad son required, así que unique_by no las omite. |
| RND-ND17-co2_cartridge_configurations-unique_by | ND17 | replace_unpublished_rows_schema | — / co2_cartridge_configurations | La configuración es el tipo, la masa de gas y si es roscado; la cantidad incluida es su atributo. Todas las columnas de la identidad son required, así que unique_by no las omite. |
| RND-ND19-eyewear_lens_configurations-unique_by | ND19 | replace_unpublished_rows_schema | — / eyewear_lens_configurations | Una lente se identifica por su modelo; fotocromía, polarización y espejo son propiedades suyas y pueden coexistir. Todas las columnas de la identidad son required, así que unique_by no las omite. |
| RND-ND23-nutrition_facts-unique_by | ND23 | replace_unpublished_rows_schema | — / nutrition_facts | Un nutriente sobre la misma base tiene un valor. Dos bases del mismo nutriente son dos filas legítimas. Todas las columnas de la identidad son required, así que unique_by no las omite. |
| RND-ND16-bottle_diameter-gate | ND16 | replace_field_contract | bottle / bottle_diameter_mm | Sólo la plantilla bottle. El portabidón ya condiciona el mismo campo a su sistema de retención; la botella quedó permitida siempre. |
| RND-ND17-max_pressure-gate | ND17 | replace_field_contract | pump / max_pressure_psi | Sólo la plantilla pump; en workshop_tool el mismo campo no cambia. Un inflador de CO2 no bombea y un cartucho suelto menos: la presión que alcanza depende del volumen del neumático y de la masa de gas. |
| RND-ND18-helmet_kind-options | ND18 | replace_unpublished_options | — / helmet_kind | La definición es origin new y sólo la usa helmet, así que la opción se retira sin migrar hechos. El público ya vive en intended_audience. |

Definiciones nuevas: 1 (thread_pitch_system).

## 3. Campos de filas sin identidad segura

| Campo | Columnas requeridas | Por qué no se propone identidad |
|---|---|---|
| fastener_kit_members | member_role, quantity | Un kit puede traer dos pernos M5 de largos distintos con el mismo rol: ninguna columna requerida los distingue y la que lo haría, el largo, es opcional. Forzarla obligaría a inventar un dato. |
| tool_bits_included | bit_kind, quantity | Un juego trae varias medidas del mismo tipo de punta y la medida es opcional. |
| bag_rack_interface | interface | Un mismo sistema puede aparecer en dos generaciones y la generación es opcional; una identidad con una clave opcional no deduplica nada. |
| rack_top_interface | interface | Igual que el anterior. |
| rack_mount_configurations | mount_point | El mismo punto de montaje admite varias configuraciones declaradas y la configuración es opcional. |
| certification_configurations | standard, standard_text, evidence_kind | La misma norma puede constar por etiqueta y por documento, y edición y mercado son opcionales: son filas legítimas, no duplicados. |
| conflicting_claims | field_key, value, source_kind | Guardar dos valores contradictorios del mismo campo es su función; una identidad los prohibiría. |
| kit_members | member_role, family, quantity, position | Compartido por 23 plantillas y con el mismo problema del kit de fijaciones. |

## 4. Límites

**Motor.**
- No hay igualdad ni exclusión mutua entre dos escalares: por eso la exclusión de paso y TPI se consigue con un campo de sistema declarado y no con una regla.
- unique_by omite las filas a las que les falta una clave del grupo, así que sólo se propone identidad cuando todas sus columnas son required.
- Las condiciones por fila gobiernan una celda dentro de su fila y no comparan filas entre sí: ninguna de las identidades propuestas se puede sustituir por una condición.
- Nada compara un escalar con las filas del mismo producto: la cantidad por envase de cartuchos y la cantidad incluida por configuración conviven sin control.

**Identidad.**
- Ocho campos de filas quedan sin identidad porque ninguna combinación de columnas requeridas la da, y forzarla obligaría a inventar un dato que el fabricante no publica. Están listados con su razón.
- Las identidades propuestas son de configuración, no de nombre: ninguna usa un texto libre como clave.

**Consumidor.**
- Aprobar una representación no aprueba un montaje ni una certificación. Una fila de certificación guarda lo que la etiqueta dice y el estado de su lectura; no homologa el casco.
- Una talla M de dos marcas sigue sin ser comparable aunque las dos se escriban con la etiqueta OEM exacta.
- Una capacidad de la herramienta declarada como admitida no autoriza la operación sobre un modelo concreto: eso es una relación con fuente.

## 5. Fixtures

| Id | Hallazgo | Plantilla | Tipo | Issues esperados | Nota |
|---|---|---|---|---|---|
| RF1 | ND09 | fastener | válido | — | Designación métrica completa. Con el sistema en métrico, el campo de TPI no está disponible. |
| RF2 | ND09 | fastener | contradictorio | field_constraint@thread_tpi | El caso negativo de la compuerta AG01: hoy se escribe sin ruido; con el sistema declarado, el TPI queda fuera de su condición. |
| RF3 | ND09 | fastener | desconocido | — | Sin sistema declarado no se escribe ni paso ni TPI: la designación queda incompleta y visible, no rellenada. |
| RF4 | ND10 | workshop_tool | contradictorio | row_shape@tool_capabilities | Admitida y no admitida a la vez para la misma operación y estándar. Es el mismo error que los sensores del bloque de luces. |
| RF5 | ND10 | workshop_tool | válido | — | Dos operaciones sobre el mismo estándar con resultados distintos: legítimo y es justo la corrección que pedía el hallazgo sobre HG y XD. |
| RF6 | ND16 | bottle | válido | — | Una botella TWIST sin diámetro de portabidón. Hoy el campo está permitido y su ausencia parece un dato que falta. |
| RF7 | ND16 | bottle | contradictorio | field_constraint@bottle_diameter_mm | Reducir la TWIST a una botella de un diámetro es lo que el hallazgo prohíbe. |
| RF8 | ND17 | pump | contradictorio | field_constraint@max_pressure_psi | Un inflador de CO2 no tiene presión máxima propia; la que alcance depende del neumático y de la masa de gas. |
| RF9 | ND17 | pump | válido | — | Gas neto, peso bruto y cantidad separados, con la designación de rosca que la condición por fila exige por ser roscado. |
| RF10 | ND17 | pump | desconocido | — | Sin cartuchos declarados no se infiere ninguno: la interfaz queda desconocida y no se copia de otro inflador. |
| RF11 | ND18 | helmet | válido | — | Construcción y público a la vez, que hoy obliga a elegir. La norma conserva su texto, edición y mercado. |
| RF12 | ND18 | helmet | desconocido | — | Sin etiqueta observada no hay declaración de norma; la ausencia no se escribe como una norma más. |
| RF13 | ND23 | food_beverage | contradictorio | row_shape@nutrition_facts | Dos cantidades del mismo nutriente sobre la misma base. |
| RF14 | ND23 | food_beverage | válido | — | El mismo nutriente sobre dos bases distintas es legítimo y la identidad lo permite. |
| RF15 | ND19 | eyewear | contradictorio | row_shape@eyewear_lens_configurations | La misma lente polarizada y no polarizada. Que fotocromía y polarización coexistan en una fila sí es válido, y es la corrección del hallazgo. |
| RF16 | ND11 | lock | desconocido | — | Las medidas del arco y del cable en la misma presentación, sin nivel de seguridad declarado: pendiente, no transferido desde el arco. |

## 6. Fuentes

**S-PARK-THREAD — Park Tool — Basic Thread Concepts** · https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts · reference_general

  - Una rosca métrica se designa por diámetro nominal y paso en milímetros; una rosca en pulgadas se designa por diámetro y hilos por pulgada. Son dos sistemas de designación, no dos medidas del mismo tornillo.

**S-SHELDON-THREAD — Sheldon Brown — Thread sizes / glosario de roscas** · https://www.sheldonbrown.com/gloss_th-z.html · reference_general

  - El glosario distingue la designación métrica (paso) de la inglesa (TPI) y advierte que roscas de designación distinta pueden parecerse dimensionalmente sin ser intercambiables.

**S-FIDLOCK — Fidlock — sistema TWIST de botella y base** · https://fidlock.com/en/bike/twist-bottle · oem_page (citada en la revisión ND del 2026-09-06 como N22/N23; no releída aquí)

  - La botella se retiene por una base magnética con giro, no por el aro de un portabidón: no tiene un diámetro de portabidón que declarar.

**S-CO2 — Revisión ND 2026-09-06, fuente N24 (inflador y cartuchos CO2)** · review_cited_not_read

  - Un inflador de CO2 no bombea: entrega el gas del cartucho. La presión final depende del volumen del neumático y de la masa de gas, no de un máximo del aparato.

**S-HELMET — Revisión ND 2026-09-06, fuentes N25/N26 (cascos y certificación)** · review_cited_not_read

  - La construcción del casco y el público al que se destina son ejes distintos: «Integral» describe la carcasa y «Niño» describe al usuario.

**S-ENGINE — Motor desplegado: 0200 (condiciones y pares escalares) y 2200/2300 (condiciones por fila)** · structural

  - Una condición sólo mira escalares de la misma plantilla; no existe igualdad ni exclusión mutua entre dos escalares.
  - unique_by omite las filas a las que les falta una clave del grupo: una identidad opcional no deduplica.
  - Las condiciones por fila gobiernan una celda dentro de su fila; no comparan filas entre sí.

**S-BASE — Base con condiciones por fila (c12204e42f86423f…)** · structural

  - 105 plantillas, 681 definiciones, 48 campos estructurados, 14 plantillas con condiciones por fila; compuertas cerradas y llenado 0.

## 7. Compuertas

- Ningún parche autoriza llenado, asignación ni publicación.
- ND01–ND08 no se tocan: son de otro revisor. ND12, ND21 y ND22 ya se integraron con el bloque de luces.
- Los tres parches de ND09 se aplican juntos: el campo de sistema debe existir antes de que las condiciones lo citen, o el guard de metadatos rechaza la plantilla.

Verificación de preimágenes: sin discrepancias.


| remaining-non-drivetrain-addendum-review-2026-09-07.json | `fd78724798b4c83773e599d33e6705d51fb5298526743470f5a223f5f586d0e1` |
