# Revisión independiente · casquillo reductor de tija y orden escalar estricto (2026-09-15, ronda 230)

Dictamen por artefacto sobre los archivos actuales de Root, con reconstrucción
previa desde fuentes. Sólo lectura y reejecuciones locales en rollback; sin
producción, código, catálogos, migraciones, git ni publicación. Llenado en cero.
No reabre manetas.

| Artefacto | SHA-256 |
|---|---|
| `.tmp/db/seatpost-shim-2026-09-15-candidate.sql` | `ff34c32c76e732b0722af3cc642eca990709f988184d46f4c45295d6258dca2f` |
| `seatpost-shim-2026-09-15-catalog.json` / `-cases.json` / `-packet.json` | `19f65ccc…` / `878d0a5b…` / `d41ad36b…` |
| `compile_seatpost_shim.py` / `test_seatpost_shim.py` / adjudicación | `b11885b2…` / `f97a1cb9…` / `e26c5174…` |
| Preimagen del casquillo (05:25:59Z, lectura de producción según el diario) | `8e11322a…` = la que declara el paquete |
| `.tmp/db/strict-scalar-2026-09-15-candidate.sql` | `e25ce520e2085537c0f31a419d2e846b1a0447067c1ff089b81b97f799a65dcc` |
| `.tmp/db/strict-scalar-2026-09-15-verification.sql` / `scripts/inventory/sql/product_spec_strict_scalar_candidate.sql` | `704a0b80…` / `93584d1b…` (mismos cuatro cuerpos) |
| `compile_product_spec_strict_scalar.py` / `compile_strict_scalar_publication.py` | `2d2856d0…` / `f1c74529…` |
| `test_product_spec_strict_scalar.py` / `test_strict_scalar_publication.py` | `4fb8bfe6…` / `6149f764…` |
| `product_spec_coherence.dart` / fixture / prueba Dart | `2a2f4922…` / `f0cf3372…` / `a7aa42b8…` |
| Preimagen de funciones (05:17:59Z, producción) / esperado | `6d9ed4c6…` / `93a5f517…` |
| Mi sonda `.tmp/product-spec-catalog/seatpost-shim-review-20260915/strict-probe.sql` | `9dd545a7…` |

## 1. Dictamen

- **Orden escalar estricto `e25ce520e208…`: aprobado** con los límites del §5.
  Modo estricto, ciclos, duplicados, herencia, unidades, seguridad, versión
  anterior y escritor real se comportan como declara la adjudicación; lo
  reproduje sobre los archivos actuales y con sondas propias.
- **Casquillo `ff34c32c76e7…`: no aprobado tal cual.** La representación
  de la pieza es sólida (§3), pero el candidato no vio que la rama heredada de
  `seatpost` ya posee las dos interfaces como definiciones globales publicadas
  (H1). Es una decisión de propiedad e identidad, no un defecto mecánico, y el
  propio paquete condiciona el rollout a esa adjudicación. Cambio mínimo en H1.

## 2. Reconstrucción desde fuentes, antes de leer la adjudicación

**Qué posee un casquillo concreto.** Dos diámetros nominales, uno por lado:
la tija que acepta y el alojamiento del cuadro que rellena. WOOdman publica dos
variantes «ID27.2/OD30.9» e «ID27.2/OD31.6», una por producto, en 6061 T6 y
38,8 g, sin longitud. Wolf Tooth Resolve declara «31.6 + shim for 34.9 frames»
con el casquillo no incluido y exige respetar la inserción mínima del cuadro.
Park Tool separa medida física y tamaño nominal («seatpost is about 0.1 mm
smaller than the tube»), fija la inserción por marca o «2.5 × diameter» y
menciona geometrías propietarias. Sheldon Brown: «measuring is better than
guessing», el tamaño va estampado y el uso con casquillo aparece sólo como
«(22.0 with shim)». De ahí: par nominal exacto por pieza, longitud total,
material y peso informativos, geometría circular o perfil OEM con código, y
condiciones del fabricante como texto con fuente. Ninguna fuente publica una
«longitud de apoyo útil»: ese campo de Root es una construcción propia,
opcional y acotada, no un dato de catálogo OEM.

**Diferencia con tija y espaciador axial.** La tija tiene un solo diámetro
propio, offset, anclaje de sillín e inserción mínima; el casquillo tiene dos
diámetros y ninguno de esos tres datos, y su longitud no fija la inserción de
la tija (Park Tool habla de la tija, no del casquillo). El `spacer` publicado
modela apilamiento axial (`inner_diameter_mm`, `thickness_mm`,
`outer_diameter_mm`, hoy legacy, más `spacer_components`): su medida principal
es un espesor a lo largo de un eje; el casquillo es un reductor radial cuya
pared es (exterior − interior) / 2. Ni una tija ni un espaciador expresan «acepta
X dentro de Y».

**Igualdad e inversión.** Nominales iguales significan pared cero: no es un
reductor (o no hace falta, o el dato está mal). Interior mayor que exterior es
físicamente imposible: dato cruzado. Ambos deben bloquear en las dos celdas y
nunca corregirse solos (sin intercambio, sin redondeo de 30 a 30,9, sin
tolerancia «vecina»). Una diferencia positiva mínima es representación, no
certificación: 30,9 → 31,6 existe (0,35 mm de pared) y el motor no puede
imponer una pared mínima. El motor anterior sólo ofrecía ≤: por eso la
dependencia de orden estricto es real y no cosmética.

**AE0266 y AE0274.** «28.6–27.2» y «30–27.2» son títulos; sin ficha, fuente ni
foto no producen ningún número. El caso `title_30_stays_30` de Root prueba que
un «30» no se convierte en 30,9; el resto sigue pendiente por diseño. Nada de
WOOdman ni Wolf Tooth se traslada a MUQZI.

**`seatpost_shim_length_mm` y la rama heredada.** El nuevo dueño es correcto:
la longitud es de la pieza, y reutilizar la definición `f60cf6cb…` byte a byte
con etiqueta propia conserva los hechos si un producto cambia de plantilla.
Pero la rama heredada es más ancha de lo que dice la adjudicación. La plantilla
`seatpost` publicada por `20260907235000` tiene, bajo `seatpost_kind =
Suplemento (shim)` (opción `7ea5f62a…`), tres campos: `shim_inner_diameter_mm`
(`fa6ff71e…`, obligatorio), `shim_outer_diameter_mm` (`f091e753…`, obligatorio)
y `seatpost_shim_length_mm` (opcional), todos number/mm/positive, invisibles y
no filtrables, con `material` acotado a cuatro opciones. Esa rama ya representa
las dos interfaces; lo que no tiene es orden (acepta iguales e invertidos),
geometría, perfil OEM, apoyo ni condiciones con fuente. Queda por sanear allí:
la opción «Suplemento (shim)», los tres campos (a legacy con `allowed_when
never` por el publicador de plantillas existentes, como se hizo con frenos), el
mapeo de categoría de los dos SKU hacia el nuevo dueño, y una lectura
productiva de cuántos productos, hechos y criterios guardados usan esas tres
claves (no la hice; la auditoría de adopción guardada del 09-07 no contiene
ningún «Suplemento»). Un par igual o invertido guardado en la rama vieja no
bloquea allí y sí bloquearía al copiarse: la migración es por lectura, no por
copia.

## 3. Candidato del casquillo

**H1 · Dos definiciones ya publicadas para las mismas dos interfaces
(condición antes de publicar).** `preimage_query()` sólo pide `REUSED ∪
nuevas`, así que `shim_inner_diameter_mm` y `shim_outer_diameter_mm` no
aparecen en la preimagen, el catálogo, el paquete ni la adjudicación
(`grep -c` = 0 en los cinco archivos; el paquete de puntos de contacto las
lista con `used_by: ['seatpost']`). El candidato crea
`seatpost_shim_post_diameter_mm` y `seatpost_shim_frame_bore_mm` en paralelo.
Consecuencias: dos claves por medida en el vocabulario de criterios, hechos
`shim_*` que no viajarían al nuevo dueño, y dos definiciones más que retirar
después. Cambio mínimo: (a) sumar ambas a `REUSED` con `labels` propios, como
ya se hace con la longitud, conservando ids y flags; o (b) dejar escrito en la
adjudicación que se retiran con la rama heredada, con la lectura productiva de
que nada las referencia. Recomiendo (a): mismo criterio que la longitud, una
sola clave por medida. La frase «falta cerrar su representación de las dos
interfaces» debe corregirse en la adjudicación.

**Verificado sólido.** Un par nominal por pieza con `lt`: igualdad e inversión
bloquean en ambas celdas en SQL y Dart; decimales de 18 cifras se distinguen;
«30» queda 30. Perfil OEM excluye los diámetros circulares y viceversa
(`field_applicability`); geometría desconocida conserva pendientes. Apoyo ≤
longitud total con prerrequisito. `material` acotado sólo en esta plantilla
(«Algodón» rechazado; la definición global `7da3359a…` intacta). Cero, «30.9-31.6» y listas
rechazados. Escritor autenticado: 9 aserciones en rollback, cinco
rechazos 23514 y valor anterior conservado. Cuatro reutilizadas byte a byte
iguales a la preimagen de las 05:26Z; seis nuevas visibles, escalares y
selección filtrables, textos no; revisión 11 = 1 + 10; sin escrituras de
producto. Reejecutado por mí sobre los archivos actuales: arnés Dart 25/25;
`shim-tests.sql` 9 ok, 24 · 1, `exact_metadata` 1 × 3, huella 1 × 2, rollback.

**F1 · Dependencia de orden sólo implícita.** El candidato guarda el md5 del
validador (`ac0738d5…`) pero no el de las cuatro funciones de coherencia. Si se
publica antes que el orden estricto, falla cerrado en `set constraints all
immediate` con el mensaje del predecesor «Los límites requieren dos campos
numéricos distintos con la misma unidad» (sonda P1), sin nombrar la causa.
Mínimo: una guardia sobre los cuatro md5 nuevos con un mensaje propio, o dejar
el orden de publicación escrito. No bloquea.

**F2 · Decisiones, no defectos.** `seatpost_shim_length_mm` obligatoria: WOOdman
no publica longitud, así que una pieza con fuente completa quedaría pendiente
para siempre; las otras piezas no exigen longitud. `spec_evidence_source`
obligatoria siempre (en pinzas y manetas es declaración): coherente con «sin
fuente no hay números», y deja a MUQZI pendiente por diseño. Superficie
cruzada: la longitud total reutilizada sigue invisible y el apoyo nuevo es
visible y filtrable. `seatpost_shim_support_length_mm` sin fuente que lo
respalde (§2).

## 4. Candidato de orden escalar estricto

Verificado sobre `e25ce520e208…` (cuatro `CREATE OR REPLACE` idénticos a los
embebidos en `tests.sql`, `shim-tests.sql` y los tres ensayos de publicación):

| Aspecto | Evidencia |
|---|---|
| Modo estricto | par de dos claves sigue ≤ (`27.2`/`27.20` silencioso, V4); tercer elemento `lt` exige < con mensaje propio; `LT`, objeto, extremo numérico, cuarto elemento, extremo faltante y `rules_version` 1 rechazados (Root + M4/M7/M9) |
| Duplicados | mismo orden y modo mixto rechazados por `seen`; invertidos caen como ciclo (M1–M3) |
| Ciclos | CTE recursiva sobre los pares efectivos, incluidos los heredados: `[outer, inner, lt]` sobre el par de rodamiento heredado → ciclo (M1) |
| Herencia | un par declarado sobre `bearing_*` sustituye al heredado una sola vez, estricto o inclusivo (M8/M8b y prueba de Root); los otros tres pares heredados no cambian |
| Unidades | distintas → 23514; ambas nulas → aceptado, como antes (M5) |
| Valores | ausente, vacío o «Desconocido / sin confirmar» → sin incidencia (V1/V2, P5); `27,2` y ` 27.2 ` se leen como 27,2 y bloquean por igualdad (P5/V5: es `spec_rule_number_internal_v1`, previo al delta); números JSON iguales bloquean; cadena a<b≤c evalúa cada par (M6b) |
| Seguridad | `CREATE OR REPLACE` conserva dueño `postgres`, ACL `postgres/service_role`, IMMUTABLE en las tres puras, SECURITY DEFINER sólo en el trigger, `search_path` fijado; guardia previa y verificación posterior comparan los seis atributos; sin grants; huella de definiciones/plantillas/campos/hechos/referencias/productos igual dentro del mismo snapshot (prueba que la migración no escribe, no que nada concurrió) |
| Versión anterior | el predecesor rechaza el formato de tres elementos desde el trigger diferido (P1) y desde la función (Root); su `issues()` aceptaría igualdad en silencio y emitiría una incidencia sobre un pseudo-campo `lt` (P2/P2b): por eso la guardia de metadatos es la que importa. Forward + replay exacto aceptados; estado mixto y modo alterado rechazados (reejecutados) |
| Datos poblados | endurecer ≤ → < sobre una plantilla con un hecho en un extremo → 23514 «coherencia de datos poblados» (P6); una edición ajena pasa (P6b). El modo estricto no se activa en sitio sobre hechos existentes |
| Escritor real | `spec_validate_draft_internal_v1` (`ac0738d5…`, sin cambios) llama a `spec_coherence_issues_internal_v1`: igual e invertido bloquean, 27,2/30,9 pasa (P5) y el guardado del casquillo lo confirma con rol autenticado |
| Dart | `2a2f4922…` replica la gramática (`>=` estricto, `seen` por orden, ciclos, herencia una vez, unidades, v2); 91 pruebas de Root + 25 del casquillo: 116/116 en mi corrida |

Base local: 21 plantillas, los cuatro predecesores con los md5 de la preimagen
de producción, validador `ac0738d5…`, trigger `spec_coherence_publication_guard`
diferido. Tras todas las corridas los cuatro cuerpos siguen siendo los
predecesores y no queda ninguna fila de sonda.

## 5. Evidencia de Root y límites

Cronología (hora local, UTC−7): preimagen 22:17:59 leída de producción según
el diario; `dart.log` 22:21:19 con 91 en verde sobre el modelo, fixture y prueba
que no cambiaron después; `tests.log` 22:23:19 sobre cuerpos idénticos al
candidato; `shim-dart.log` 22:27:39 con 6 fallos por códigos de una versión
anterior de los casos, superado por `shim-dart-final.log` 22:34:35 tras la
regeneración de las 22:33:18; `shim-tests.log` 22:34:32 con el catálogo
`19f65ccc…` embebido; ensayos de publicación 22:36:44–22:37:00 tras el
compilador de las 22:36:00. Nada desfasado; lo reejecuté todo igual.

Límites: (i) el predecesor Dart no se puede diferenciar: toda la extensión
cliente (`product_spec_*.dart`, cambios de `spec_engine_service`, arnés) está
sin seguimiento en git; «los clientes anteriores rechazan» está demostrado en
SQL y, en Dart, sólo para la copia de trabajo no distribuida. La app
distribuida sigue sin la extensión cliente; su distribución no está cerrada.
(ii) `existing_template_contracts_validated` cubre 21 plantillas aquí; la
verificación lo repite sobre el conjunto real al publicar y falla por
excepción si alguna no valida. (iii) `lock table spec_definitions in share
mode` serializa con publicadores, no con escritores de hechos; suficiente.
(iv) Dos gramáticas para un concepto: el DSL de filas publicado en
`20260908185800` usa una clave aparte `strict_ordered_pairs` con versión 2; el
escalar usa un tercer elemento `lt`. No es defecto; documentarlo. (v) Aún no
es archivo de migración: falta `supabase/migrations/<ts>_…sql` con su
`--verify` (`704a0b80…`) y publicarlo antes que el casquillo. (vi) Todo es
representación y conservación; no certifica montaje, tolerancias ni
compatibilidad OEM; llenado en cero.

## 6. Síntesis accionable

1. Publicar el orden escalar estricto `e25ce520e208…` tal cual, como
   migración con verify, antes del casquillo.
2. Corregir el casquillo por H1: reutilizar `shim_inner_diameter_mm` y
   `shim_outer_diameter_mm` con etiquetas propias (o adjudicar por escrito su
   retiro con lectura productiva), regenerar y dejar los logs sobre el SHA
   final; añadir la guardia de F1 o el orden escrito.
3. Decidir F2 (longitud obligatoria, fuente obligatoria, flags de la longitud
   reutilizada) y anotar en la adjudicación que el apoyo útil no tiene fuente.
4. Sanear la rama heredada de `seatpost` en un delta aparte del publicador de
   plantillas existentes: opción «Suplemento (shim)» y tres campos a legacy,
   mapeo de categoría de AE0266/AE0274, cero llenado desde títulos.

Propiedad de vuelta a Root.
