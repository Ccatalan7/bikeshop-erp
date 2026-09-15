# Auditoría independiente de cobertura por familias — Claude, 2026-09-06

Autor: Claude (Fable 5.1, modo Code, Ultracode). Encargo del dueño relevado por
Codex: cadenas y conectores son una parte de transmisión; tener 37 plantillas no
resuelve familias; antes de seguir cambiando o llenando hay que tener un respaldo
legacy accesible. Este archivo es sólo lectura sobre el repositorio, los
exportados y producción; no cambia código, SQL, datos ni runtime.

## 0. Evidencia y límites

| Qué se leyó | Cómo |
|---|---|
| Matriz, contrato, base K01–K30, plan de ejecución, resultado de implementación, README de la auditoría | archivos del repositorio, rama `smartpegas1.0`, HEAD `71926a11`, árbol compartido sucio |
| Manifiesto `.tmp/db/catalog-fill-manifest.json` (1 605 productos físicos, 47 inactivos), `catalog-fill-coverage.json`, `catalog-fill-references.json` (11 referencias), `templates.json`, `leaves.json` | Python sobre los exportados |
| Producción, tenant `vinabike`: plantillas con conteos de reglas, prerrequisitos, validaciones y referencias por familia; columnas de todas las tablas `spec_*`, `product_spec_*` y `category_tech_mappings`; filas por tabla; hechos por familia y procedencia; funciones `*spec*` existentes | `scripts/db/query.sh production --file …`, sólo lectura |
| Migraciones 20260906070000 y 20260906103000 (objetos creados), migraciones históricas de pedalier, cámara, neumático y relleno por nombre; pruebas pgTAP y Dart por familia | grep y lectura |
| Fuentes públicas leídas hoy en el navegador integrado: Sheldon Brown *Tire Sizing Systems* y *Crank/Chainring BCD Crib Sheet*; Park Tool *Bottom Bracket Standards*, *Cassette Removal and Installation*, *Disc Brake Pad Removal*; KMC CL573R | texto renderizado |

Límites que hay que tener presentes al leer las tablas:

- **Las dos migraciones de la arquitectura están aplicadas en producción y sin
  commit.** `20260906070000` (verificada 2026-09-06T06:59:30Z) y
  `20260906103000` (escrita en producción 2026-09-06T21:24:28Z según el
  journal local) aparecen como `??` en `git status`, igual que los nuevos Dart,
  las pruebas y los tres documentos de arquitectura. HEAD `71926a11` es, por
  tanto, la versión de software **pre-arquitectura** en el cliente; el
  servidor productivo ya es post-arquitectura. Esto condiciona el respaldo (§7).
- **Corrección 2026-09-06 (segunda ronda), con datos de Codex:** el respaldo
  cifrado independiente existe en `/Users/Claudio/Vinabike Backups/Product Specs
  Legacy/20260906T222802Z-pre-fill` y se recuperó campo a campo: 1 664 productos
  (1 605 físicos + 59 servicios), 1 653 hechos de producto, 904 enlaces de
  opciones, 14 lecturas, 37 plantillas / 280 campos, mapeos, referencias y
  código HEAD + overlay. El plano de control confirma un backup físico
  COMPLETED 2026-09-05T10:07:25.926Z, anterior al rediseño; PITR está
  desactivado. No se restauró PostgreSQL. Lo que sigue siendo cierto: el
  runbook `docs/runbooks/DATABASE_BACKUP_AND_RESTORE.md` no tiene pasos de
  fichas, y yo no verifiqué el respaldo por mi cuenta.
- No re-leí las 30 fuentes de la base K; verifiqué seis páginas hoy y para el
  resto tomo la base K como registro de lo citado, no como regla verificada.
- Los conteos por familia salen del manifiesto exportado a las 14:43; los de
  reglas, de producción a la hora de esta auditoría. No sumo porcentajes de
  «ficha completa»; donde doy cifras son conteos.

## 1. Los cinco estados, definidos para poder medirlos

Un estado se declara sólo con la evidencia de su columna derecha. No son
escalones lineales: E3 no necesita E1; E1 sólo hace falta cuando la familia va
a emitir compatibilidad; E4 necesita E3 y el bloque transversal de §3.

| Estado | Qué significa | Evidencia exigida |
|---|---|---|
| **E0 Sólo estructura histórica** | Existe plantilla con campos y vocabulario; las reglas que haya son de opciones o visibilidad heredadas, sin fuente | fila en `spec_templates`; cero `constraint_rules`; cero prerrequisitos; cero referencias |
| **E1 Reglas mecánicas verificadas** | Cada prerrequisito y restricción cita K/OEM; casos positivo, negativo y desconocido en pgTAP y Dart; read-back del despliegue | migración con fuentes, pruebas en `supabase/tests` y `test/unit`, receipt y read-back |
| **E2 Experiencia verificada** | Editor y consumidor de taller vistos con frames reales en escritorio, tablet y compacto, claro y oscuro, en la sesión canónica | frames bajo `evidence/` y registro de la surface |
| **E3 Lista para investigar** | La familia está en la cola con campos críticos definidos, registro de fuentes por marca y esquema de propuesta | entrada en `catalog-fill-critical-fields.json`, `brand-sources` de sus marcas, lote en la cola |
| **E4 Lista para aplicar** | Procedencia de investigación y canal autenticado resueltos, simulador probado, referencias sembradas, **respaldo pre-fill verificado** | pgTAP del aplicador, receipt de la siembra, dump con SHA-256 y prueba de lectura |

Hoy ninguna familia está en E4. Dos están en E1+E2+E3. Las 34 restantes están
en E0, con matices que la tabla siguiente distingue.

## 2. Lista cerrada de familias reales presentes

### 2.1 Las 36 familias con plantilla (35 con productos)

Conteos del manifiesto: productos (activos). «Hechos» son los existentes en
producción con su procedencia. Codex evaluó con el validador del servidor las
863 fichas con plantilla: 47 con prerrequisitos faltantes no bloqueantes y
ninguna con conflicto; que pasen no prueba cobertura mecánica. Ninguna familia tiene un producto con
`spec_reference_id`, `spec_revision > 0` ni hechos `confirmed = true`.

| Familia | Productos | Marcas principales | Hechos existentes | Estado | Evidencia y hueco concreto |
|---|---|---|---|---|---|
| `chain` | 31 (31) | KMC 21, Shimano 5, ZTTO 5 | 29 productos: `supplier_text` 39, `import` 3 | **E1 · E2 · E3** | 5 referencias, todas KMC; 0 vinculados, 0 con modelo; Shimano y ZTTO sin referencia; HV408/HV410/K710 sin fuente exacta. **No está cerrada**: lo verificado es el contrato, no el catálogo |
| `chain_link` | 9 (9) | Risk 5, KMC 4 | 0 | **E1 · E2 · E3** | 6 referencias KMC; una propuesta revisada (CL573R) sin aplicar; Risk sin fuente |
| `cassette` | 29 (29) | Shimano 18, Sunshine 4 | 29: `supplier_text` 85 (velocidades, dientes) | E0 con datos nominales | `freehub_type` es requerido y está en 0 de 29; sin referencias; migración de relleno por nombre 20260824630000 |
| `freewheel` | 28 (28) | Falcon 6, Genérico 5, Shimano 4, SunRace 4 | 21: `supplier_text` 52 | E0 con datos nominales | `freehub_type` requerido 0 de 28; ver H2 sobre piñón fijo |
| `fixed_cog` | **0** | — | 0 | E0 sin productos | mapeada a la categoría «Fixie», que no tiene productos (corregido 2026-09-06: antes decía «sin categoría mapeada») |
| `cassette_spacer` | 3 (3) | Risk | 0 | E0 | — |
| `rear_derailleur` | 35 (34) | Shimano 19, Saiguan 4 | 0 | E0 sin datos | 2 con modelo; Shimano trae código en el nombre; validaciones de dientes sin fuente |
| `front_derailleur` | 15 (15) | Shimano 9, Saiguan 4 | 0 | E0 sin datos | — |
| `shifter` | 32 (32) | Shimano 18, SunRace 7 | 0 | E0 sin datos | 8 con descripción; ninguna regla de indexación (K10) |
| `derailleur_hanger` | 23 (23) | A-FORGE 8, Aliexpress 5 | 0 | E0 sin datos | `hanger_model_code` es el único identificador; sin dibujo ni cuadro (K13) |
| `derailleur_pulley` | 7 (7) | Aliexpress 6 | 0 | E0 | — |
| `chainring` | 16 (16) | Deckas 5 | 0 | E0 | validación `chainring_bcd_mm` 64–144 excluye BCD documentados (H5) |
| `crankset` | 27 (27) | Shimano 9, Eclipse 5, Genérico 5 | 0 | E0 sin datos | 5 con descripción; `bottom_bracket_family` y `spindle_interface` sin reglas cruzadas con pedalier |
| `crank_arm` | 7 (7) | Genérico 4 | 0 | E0 | — |
| `drivetrain_kit` | 1 (1) | Taiwan | 0 | E0 | «Groupset» (4) sigue sin mapear a esta familia |
| `chain_guide` | 3 (3) | ZTTO, RideRace | 0 | E0 | — |
| `bottom_bracket` | 34 (34) | Neco 8, Ozono 7, Shimano 5, VP 5 | 34: `import` 162 | **E0+** reglas históricas probadas, sin fuente | 12 campos con `option_rules`, 14 con visibilidad; 17 pruebas Dart de cascada, 10 de reglas de opciones y aserciones pgTAP en `drivetrain_precision_spec_layer.sql`; ninguna migración ni prueba cita K18/Park/Sheldon |
| `bottom_bracket_axle` | 3 (3) | MKR | 3: `import` | E0+ | 4 `option_rules` sin fuente |
| `bottom_bracket_cup` | 8 (8) | Genérico, Nakasawa | 8: `import` 27 | E0+ | 5 `option_rules` sin fuente |
| `bottom_bracket_bearing` | 3 (3) | — | 3: `import` 6 | E0+ | 1 `option_rule` |
| `bearing` | 9 (9) | MKR 4, Genérico 3 | 0 | E0 | 3 campos; sin ID/OD/ancho como campos (K19) |
| `tire` | 113 (113) | Maxxis 19, Arisun 16, KENDA 14, Vuelta 13 | 113: `supplier_text` 257 | E0 con datos nominales del nombre | `wheel_size` 113, `tire_width_in` 86; `tire_etrto` 0; 4 con modelo; relleno 20260824610000 |
| `tube` | 137 (132) | RBX 22, Chaoyang 16 | 132: `supplier_text` 628, `inferred` 227, `import` 11 | E0 con datos nominales del nombre | `tube_material` es `inferred`; relleno 20260824560000 |
| `rim` | 41 (41) | Weinmann 16, Fantom 6 | 6: `import` 22 | E0 | 1 regla de visibilidad; ERD y ancho interior 0 |
| `spoke` | 48 (48) | Stella 8, MKR 7 | 48: `supplier_text` 62, `import` 5 | E0 con datos nominales | largo 48 de 48, calibre 15; relleno 20260824620000 |
| `hub` | 48 (48) | Eclipse 6, Novatec 4, BLOOKE 4 | 2: `import` 7 | E0 | `hub_spacing_mm` y `spoke_holes` requeridos: 2 de 48 |
| `rim_strip` | 3 (2) | Genérico | 1: `import` | E0 | — |
| `tubeless_valve` | 8 (8) | Deemount 5 | 3: `import` 6 | E0 | — |
| `tubeless_consumable` | 3 (3) | RaceLub, Squirt | 1: `import` | E0 | — |
| `brake_pad` | 53 (49) | ZTTO 10, Risk 9, Genérico 6 | 13: `name_reading` 14 | E0 + piloto de lectura con cita | los únicos 14 `name_reading` del sistema; `pad_shape_code` requerido 0 de 53 (K25) |
| `rotor` | 18 (18) | Shimano 5, ZTTO 3 | 10: `import` 19 | E0 | diámetro 10 de 18; montaje sin datos |
| `brake_caliper` | 11 (11) | Defensor Forever 3 | 0 | E0 | 13 campos, 5 requeridos, ninguno lleno |
| `brake_lever` | 15 (15) | Genérico 3, Saiguan 2 | 0 | E0 | sin tiro (K23) |
| `rim_brake` | 24 (24) | Alhonga 5, ZTTO 4 | 0 | E0 | 5 campos; sin tipo de montaje ni tiro |
| `complete_brake` (2 plantillas) | 3 (3) | Shimano 2 | 1: `import` 5 | E0 | — |
| `headset` | 15 (15) | Neco 6, Risk 3 | 3: `import` 4 | E0 | `headset_standard` requerido; SHIS superior/inferior no separados (K19) |

Lo que la tabla demuestra: **el contrato verificado es el del piloto, y los 40
productos de cadena y conector pertenecen a ese piloto; ninguno está
mecánicamente verificado** (corregido 2026-09-06: antes decía «cubren 40
productos»). Las tres familias con más datos —cámaras, neumáticos y
pedalier, 284 productos— tienen valores que salieron de migraciones que leyeron
el nombre del producto, con procedencia `supplier_text`, `inferred` o `import`.
Ninguno está confirmado.

### 2.2 Productos sin familia: 742 (706 activos), 76 categorías más 197 sin categoría

Agrupados por la familia que la matriz §3 propone. Son las cifras que hay que
mover, no las de cadena.

| Bloque propuesto por la matriz | Categorías reales (productos) | Total | Estado |
|---|---|---|---|
| Sin categoría | ∅ (197) | 197 | en la cola como `unmapped:uncategorized` (corregido 2026-09-06: antes decía «fuera de toda cola»); primero hay que categorizar |
| Contacto y dirección | Tija 13, Adaptadores de tija 2, Collerín 11, Asiento 18, Asientos 2, Cubre Asientos 4, Tee 17, Manubrios 11, Puños 23, Cinta Manillar 7, Araña 3, Espaciadores 8, Horquillas 11, Shock 1 | 131 | sin familia (K19–K21, K28–K29 citadas, sin plantilla) |
| Equipamiento del ciclista | Guantes 34, Cascos 13, Protectores 7, Lentes 3, Mochilas 3, Jerseys 1, Poleras 1 | 62 | sin familia; atributos propios, sin compatibilidad |
| Frenos, cables y fundas | Fundas y piolas 21, Terminales y topes 12, Fittings Hidráulicos 8, Frenos Hidráulicos 3, Noodles 3, Cable Freno Hidráulico 2, Frenos 2, Gomas V-Brake 2, Cambios 2, Regulador tensión frenos 1 | 56 | sin familia (K23, K26, K27) |
| Accesorios de montaje | Luces 16, Soporte Celular 8, Porta Caramagiola 7, Campanillas 6, Canastos 4, Tapabarros 4, Ciclocomputadores 1, Reflectantes 1 | 47 | sin familia |
| Piezas de maza y armado | Ejes 23, Agujas 8, Conos 6, Niples 2, Contratuerca 1, Rueda Estabilizadora 2 | 42 | sin familia (K17) |
| Seguridad y otros | Candados 31, Botella de Agua 4, Souvenirs 2, Audífonos 1, Cuerdas 1, Fundas 1, Otros 1 | 41 | sin familia |
| Químicos | Lubricantes 16, Grasa/Aceites/Soluciones/Limpiadores 7, Desengrasantes 3, Grasa 2, Silicona 1, Abrillantadores 1, Líquido Frenos 1 | 31 | sin familia; ficha del químico, no reglas |
| Pedales | Pedales 30, Pedalines 1 | 31 | sin familia (K22) |
| Herramientas | Herramientas 21, Corta Cadena 4, Botellas aplicadoras 1 | 26 | sin familia (K30) |
| Fijaciones | Pernos/Tornillos/Otros 20 | 20 | sin familia |
| Adaptadores sin extremos tipados | Adaptadores 8, Accesorios 9 | 17 | hay que identificar qué adaptan antes de asignar |
| Bombines | Bombines 14 | 14 | sin familia |
| Tubeless adicional | Tubeless 10, O'rings 1, Tripas Tubeless 1 | 12 | podrían caber en `tubeless_consumable`/`tubeless_valve`; no asignar por palabra |
| Reparación de cámara | Parches 6, Pegamento parches 2 | 8 | sin familia |
| Composición y servicio | Groupset 4, Servicio 3 | 7 | Groupset → `drivetrain_kit`; 3 productos físicos bajo «Servicio» a revisar |

Un producto de este bloque tiene 7 hechos (`supplier_text` 5, `inferred` 2):
Codex lo identificó como una cámara sin categoría. La causa no está
establecida; no hay prueba de que un mapeo haya cambiado después del relleno
(corregido 2026-09-06; H12).

## 3. Dependencias entre bloques

### 3.1 Bloque transversal T: bloquea E4 de todas las familias

En orden, porque cada uno alimenta al siguiente:

1. **Respaldo pre-fill verificado** (petición del dueño; §7).
2. **Procedencia de investigación**: la restricción `spec_facts_source_known`
   admite seis valores; el writer marca `mechanic` lo explícito y `catalog` lo
   derivado; `record_product_spec_reading_v1` sólo acepta citas del nombre o
   descripción. Sin esto, un hecho de distribuidor o envase se falsifica como
   medición del mecánico.
3. **Canal autenticado**: `save_product_with_specs_v1` exige `auth.uid()`;
   hoy hay 0 recibos en `product_spec_save_receipts`.
4. **Simulador y aplicador** con pruebas de conservación y concurrencia.
5. **Ciclo de siembra de referencias por migración**: cada lote con modelos
   nuevos necesita una migración revisada; con 11 referencias KMC y ~98
   productos Shimano con código en el nombre, es el cuello de botella real.
6. **Campos críticos por familia** en `catalog-fill-critical-fields.json`:
   hoy sólo `chain` y `chain_link`. Sin ellos no hay E3 ni métrica de cierre.
7. **Registro de fuentes por marca** (`brand-sources`): no existe todavía.
8. **Convención de evidencia**: existe en el plan; cumplida una vez
   (`research-001/evidence/kmc-cl573r-20260906.md`).

### 3.2 Dependencias mecánicas entre familias

Estas parejas comparten definiciones globales; investigar una sin fijar el
vocabulario de la otra produce dos verdades.

| Vocabulario compartido | Familias que lo escriben o leen | Fuente que lo gobierna | Estado del vocabulario |
|---|---|---|---|
| `freehub_type` | `hub`, `cassette`, `freewheel`, `cassette_spacer` | K08–K09 (Park cassette/freewheel; SRAM XD/XDR) | lista histórica; cassette y freewheel lo exigen y nadie lo tiene |
| `wheel_size` / ETRTO | `tire`, `tube`, `rim`, `rim_strip`, `tubeless_valve` | K14 Sheldon *Tire Sizing* | nombres nominales; `tire_etrto` y `rim_etrto` vacíos |
| `rotor_mount_type`, `rotor_diameter_mm` | `rotor`, `hub`, `brake_caliper`, adaptadores (sin familia) | K24 | diámetro en 10 rotores; montaje en ninguno |
| `pad_shape_code` | `brake_pad`, `brake_caliper` | K25 | requerido y vacío en ambas |
| `brake_system`, `brake_type`, `brake_position` | `brake_pad`, `brake_lever`, `rim_brake`, `rotor`, `complete_brake` | K23, K26 | listas históricas |
| `bottom_bracket_family`, `spindle_interface`, `bb_shell_standard` | `crankset`, `bottom_bracket*`, `crank_arm` | K18 | reglas de cascada en pedalier; crankset no las lee |
| `shift_actuation_family`, `drivetrain_platform`, ecosistemas | `shifter`, `rear_derailleur`, `front_derailleur`, `chainring`, `crankset` | K10, K13 | listas históricas; sin tabla de indexación |
| `chain_speeds`, `drivetrain_speeds` | `chain`, `chain_link`, `cassette`, `freewheel`, `chainring`, `crankset`, `shifter`, derailleurs | K01, K04 | dos claves distintas para «velocidades»; cadena usa `chain_speeds`, el resto `drivetrain_speeds` |
| `spoke_holes`, ERD, bridas | `spoke`, `rim`, `hub` | K17 | largo de rayo sin ERD ni maza |
| `headset_standard`, `steerer_type` | `headset`, horquillas y tees (sin familia) | K19–K20 | SHIS no separa arriba/abajo |

Orden de desbloqueo que se deduce: `hub` antes que `cassette`/`freewheel`;
`rim` antes que `tire`/`tube`/`spoke`; `brake_caliper` antes que `brake_pad`;
`bottom_bracket` (ya con cascada) antes que `crankset`; `shifter` y
`rear_derailleur` juntos. Cadena y conector ya no bloquean a nadie.

## 4. Huecos concretos

- **H1 · 742 productos sin familia.** Ningún lote puede tomarlos; la matriz
  §3 propone familias pero no existe ni una plantilla ni un mapeo nuevos desde
  2026-09-05. Incluye 197 sin categoría, que ni siquiera son «hoja sin plantilla».
- **H2 · `fixed_cog` sin productos y «Piñones» con 28.** La plantilla está
  mapeada a «Fixie», vacía. No afirmo que haya piñones fijos entre las ruedas
  libres; afirmo que desde la categoría no se sabe, y la revisión nominal
  producto a producto lo resuelve (`assigned-product-ficha-claude-review-2026-09-06.json`).
- **H3 · 1 128 hechos `supplier_text` y 227 `inferred` provienen de leer el
  nombre**, por las migraciones `20260824560000/610000/620000/630000`. Las
  reglas del dueño obligan a conservarlos; la auditoría obliga a saber que son
  lecturas nominales sin cita ni recibo, a diferencia de los 14 `name_reading`
  de pastillas que sí tienen recibo. El read-back del llenado debe distinguirlos.
- **H4 · Campos requeridos vacíos en toda la familia.** `freehub_type` 0/57,
  `pad_shape_code` 0/53, `hub_spacing_mm`/`spoke_holes` 2/48,
  `headset_standard` 2/15. El «requerido» de las plantillas nunca se contrastó
  con datos; los campos críticos reales están por definir (T6).
- **H5 · Reglas y límites sin fuente.** Los 22 `option_rules` de pedalier y la
  regla de visibilidad de llanta tienen pruebas pero ninguna cita en migración
  ni test. Los 39 rangos `min/max` de `validation_rules` (43 filas, 4 de ellas
  los positivo/entero de cadena y conector) son cotas de sanidad,
  no mecánica: `chainring_bcd_mm` 64–144 excluye 58 mm (Sugino MX350 4 brazos
  interior) y 145 mm (Campagnolo Super Record/Record/Chorus 2015– exterior),
  ambos en el *BCD Crib Sheet* de Sheldon Brown leído hoy. Un rango así rechaza
  una pieza real antes de que nadie la investigue.
- **H6 · Sólo KMC tiene referencias.** Shimano es la marca principal en cambio
  trasero (19), mando (18), cassette (18), biela (9), desviador (9) y aporta 5
  cadenas y 5 rotores; ninguna referencia. El ciclo «investigar → JSON →
  migración → aplicar» está dimensionado para un lote de nueve conectores.
- **H7 · Segundo motor de reglas en el cliente.** `drivetrain_canonical_data.dart`
  conserva las funciones de ancho→velocidades (5 apariciones, sin llamadores
  fuera del archivo) y sus pruebas, más reglas de pedalier por coincidencia de
  texto (`contains('pressfit')`, `contains('bb30')`) que usa el asistente de
  servicio. No es un defecto activo; es una regla sin fuente que sigue viva
  fuera del contrato versionado.
- **H8 · Experiencia verificada sólo en cadena/conector.** El consumidor de
  taller se probó con HV408/X8/eGlide; para las otras 34 familias no hay frame
  ni contexto probado.
- **H9 · Sin campos críticos, sin fuentes por marca, sin lote listo** para 34
  familias: E3 no existe fuera de cadena/conector.
- **H10 · Respaldo.** Ningún paso del runbook se ejecutó para fichas; 0
  recibos; sin punto de restauración pre-arquitectura registrado; las
  migraciones aplicadas no están en git.
- **H11 · Identidad estructurada casi inexistente**: 12 productos con modelo,
  0 con MPN, `manufacturer` vacío en todos, `brand_id` en 1 226 pero `brand`
  texto sin normalizar («Ahlonga»/«Alhonga»; 232 sin marca sólo en el bloque
  sin familia).
- **H12 · Hechos sin familia** (una cámara sin categoría con 7 hechos): la
  causa no está establecida; el respaldo captura mapeos y hechos juntos para
  poder establecerla. Codex encontró además una cubeta cuya ficha no incluye
  `spindle_diameter_mm` ya guardado: un hecho existente que la plantilla no
  muestra, el caso inverso.

## 5. Criterios medibles para terminar cada familia

Regla general, para todas: una familia está **terminada** cuando (a) cada
producto tiene marca normalizada y modelo, o una decisión «sin modelo» con
causa; (b) cada hecho crítico tiene procedencia distinta de `inferred` y de
lectura sin cita; (c) si la familia emite compatibilidad, sus reglas citan K/OEM
y pasan casos positivo, negativo y desconocido; (d) el consumidor de taller da
el resultado correcto en un producto real de cada clase; (e) el read-back
compara valor, procedencia y lecturas del 100 % de lo escrito; (f) el residuo
queda listado con causa (`sin OEM`, `marca genérica`, `requiere medición`,
`requiere foto de envase`). «Todos los campos llenos» no cuenta.

Hechos críticos que propongo por familia, con la fuente que exigen. Las cifras
de la última columna son los conteos que hay que reportar, no metas inventadas.

| Familia | Identidad mínima | Hechos críticos y fuente exigida | Regla que necesita fuente antes de cualquier claim | Se reporta |
|---|---|---|---|---|
| `chain` | marca, modelo, presentación (eslabones) | velocidades, ancho nominal, modo, cierre incluido — OEM | ya: 1/8 vs desviador (K06–K07) | 31: vinculados, con modelo, residuo por causa |
| `chain_link` | marca, modelo | tipo, cadenas objetivo, reutilizable, sentido — OEM; cantidad — envase | ya (K06) | 9: idem |
| `cassette` / `freewheel` | marca, modelo | `freehub_type` o rosca, velocidades, dientes menor/mayor — OEM | cuerpo–cassette (K08–K09), nunca por velocidades | 57: cuerpo declarado, modelo |
| `fixed_cog` | — | rosca/interfaz, dientes, ancho | K01, K08 | 0 hasta que «Piñones» se audite |
| `rear_derailleur` / `shifter` / `front_derailleur` | marca, modelo (Shimano por código) | accionamiento/indexación, velocidades, piñón máx/mín, capacidad, montaje — OEM (Shimano si.shimano) | indexación mando–cambio (K10); patilla (K13) | 82: modelo, accionamiento declarado |
| `crankset` / `crank_arm` / `chainring` | marca, modelo | interfaz de eje, longitud, BCD o direct mount, dientes — OEM | biela–pedalier (K18), BCD (K12) con el crib sheet como tabla | 50: interfaz declarada |
| `bottom_bracket*` | marca, modelo | caja (rosca/pressfit + ancho), construcción, eje — OEM/Park | convertir los 22 `option_rules` en reglas con cita K18 y fixtures, o retirarlos | 48: los 34 con `import` revisados contra OEM |
| `hub` | marca, modelo | posición, OLD/eje, agujeros, `freehub_type`, montaje de rotor — OEM | maza–cassette (K08–K09), maza–rotor (K24) | 48: requeridos llenos con fuente |
| `rim` | marca, modelo | BSD/ETRTO, ancho interior, agujeros, ERD, tubeless — OEM | llanta–neumático (K14, K16), llanta–rayo (K17) | 41: ETRTO y ERD |
| `tire` | marca, modelo (4 hoy) | ETRTO, ancho, talón, tubeless — OEM/envase | K14–K16; la tabla ancho–llanta del fabricante | 113: ETRTO con fuente, nombre-sólo |
| `tube` | marca | rango ETRTO, válvula, largo, material — envase/OEM | K14; no cruzar rangos | 137: `inferred` resueltos |
| `spoke` | marca | largo, calibre, cabeza, rosca — envase | K17: ningún «aro compatible» | 48: largo con fuente |
| `brake_pad` | marca, modelo | `pad_shape_code`/cálipers compatibles, compuesto, aletas — OEM | forma–cáliper (K25) | 53: forma con fuente |
| `rotor` / `brake_caliper` / `brake_lever` / `rim_brake` / `complete_brake` | marca, modelo | montaje, diámetro, fluido, tiro, posición — OEM | K23–K26 | 71: montaje y tiro declarados |
| `headset` / `bearing` | marca, modelo | SHIS superior e inferior, ID/OD/ancho — OEM/Park | K19 | 24: SHIS por extremo |
| `tubeless_*`, `rim_strip`, `cassette_spacer`, `chain_guide`, `derailleur_*`, `drivetrain_kit` | marca, modelo | dimensiones propias y sistema destino — OEM/envase | K09, K13, K15 | 51 |
| Bloques sin familia (§2.2) | familia nueva declarada con interfaces y preguntas mínimas | atributos propios; compatibilidad sólo si existe fuente | matriz §4 | 742: categorizados, con familia, en cola |

## 6. Cómo evitar seguir optimizando una sola pieza

1. **Un tablero, una métrica.** `catalog-fill-coverage.sql` más una columna de
   estado E0–E4 por familia, regenerado en cada ronda y adjunto a cada revisión.
   El progreso se mide en familias que suben de estado y en productos con
   identidad y hechos críticos con fuente; nunca en reglas añadidas a cadena.
2. **Regla de anchura antes de profundidad.** Ninguna familia entra a E4 hasta
   que todas las familias con 20 productos o más estén en E3, que es barato:
   campos críticos, fuentes por marca y un lote en la cola. Y no se abre
   trabajo E1 en una familia que ya está en E1 mientras exista una familia con
   más productos en E0 con datos (cámara, neumático, pedalier, cassette).
3. **Congelar cadena/conector** en su estado actual: sólo correcciones de
   defectos; ninguna tercera entrega hasta que el tablero muestre al menos
   cuatro familias de transmisión y cuatro de ruedas/frenos en E3.
4. **Orden obligatorio fijado por el dueño (2026-09-06, sustituye a mi
   propuesta de dos ciclos en paralelo):** primero revisar todos los productos
   con ficha; después detectar los productos sin su ficha correspondiente;
   después revisar si los campos administran correctamente la compatibilidad;
   después sanear lo que esté mal conservando lo que esté bien; **sólo después
   llenar**. Ningún lote de llenado avanza antes de cerrar la revisión y el
   saneamiento global. Las reglas mecánicas (E1) siguen yendo por familia con
   fixtures, pero dentro de la etapa de saneamiento, no como ciclo paralelo.
5. **Definir «terminada» antes de investigar**, en `critical-fields.json`,
   con la tabla de §5 como punto de partida; después no se renegocia.
6. **Rondas por bloque con propietario distinto**: transmisión restante,
   ruedas, frenos, contacto/sin familia. Cada ronda tiene que mover al menos
   dos familias un estado; una ronda que sólo toca cadena se rechaza en la
   revisión cruzada.
7. **Presupuesto para el bloque sin familia**: es el 46 % del manifiesto.
   Primero categorizar los 197 sin categoría; luego crear las familias de las
   hojas grandes (pedales, puños, tija/collarín/asiento, tee/manubrio/horquilla,
   ejes/conos/agujas, fundas/terminales, herramientas, químicos) con atributos
   propios y sin compatibilidad.
8. **Cuello de botella de referencias**: si la siembra sigue siendo una
   migración por lote, planificar los lotes Shimano por catálogo, no por
   producto; una migración por marca y familia, revisada una vez.

## 7. Qué debe contener un rollback selectivo de fichas

Son dos cosas distintas y el respaldo debe nombrarlas por separado.

### 7.1 Datos pre-fill (se pueden capturar hoy, exactos)

Instantánea del tenant `vinabike` antes del primer lote, con SHA-256, hora
UTC, ref del proyecto y retención, según el runbook:

| Conjunto | Filas hoy | Por qué entra |
|---|---|---|
| `spec_facts` con `subject_type='product'` | 1 653 | los hechos que el llenado toca; guardar valor, `source`, `confirmed`, `updated_at`, `subject_scope` |
| `spec_fact_values` de esos hechos | 904 | opciones normalizadas (corregido 2026-09-06: 1 486 incluía sujetos de bicicleta) |
| `spec_fact_readings` | 14 | recibos de lectura; el read-back los compara |
| `product_spec_values` (espejo) | 1 653 | para verificar que el trigger de espejo reproduce el estado |
| `products`: `id, brand, brand_id, model, manufacturer, manufacturer_sku, gtin, barcode, specifications, spec_reference_id, spec_revision, updated_at, category_id` | 1 605 físicos | sólo columnas de identidad y ficha; nunca precio, stock ni documentos |
| `category_tech_mappings` | 45 | los mapeos cambian el sentido de un hecho (H12) |
| `product_spec_references` | 11 | globales, inmutables; se guardan para saber qué existía |
| `product_spec_save_receipts` | 0 | la clave del rollback selectivo; vacío hoy |
| `spec_templates`, `spec_template_fields`, `spec_definitions`, `spec_definition_values` | 37 / 280 / 136 / 542 | globales; el contrato bajo el que se escribió |
| `spec_facts` de bicicletas y visitas | 849 | no se tocan; se guardan para demostrarlo por conteo antes y después |

### 7.2 Versión de software pre-arquitectura (distinta del punto 7.1)

- **Cliente**: HEAD `71926a11` es pre-arquitectura; los archivos nuevos y
  modificados de fichas están sin commit. Hasta que se etiquete o confirme,
  «volver al software anterior» es ambiguo en este checkout compartido, y un
  `git stash`/`clean` destruiría la arquitectura sin dejar rastro.
- **Servidor**: las funciones pre-arquitectura son las de las migraciones
  confirmadas hasta `20260824700000`; las de hoy vienen de `20260906070000`
  (SHA `007450b4…`, verificada 06:59:30Z) y `20260906103000` (SHA
  `f56318fe…`, escrita 21:24:28Z). Volver atrás exige o bien PITR de
  plataforma anterior a 2026-09-06T06:59Z, cuya existencia no verifiqué, o una
  migración inversa revisada que retire triggers, funciones y columnas nuevas
  conservando datos. No es lo mismo que restaurar 7.1 y no se confunden.
- Recomendación mínima antes del primer lote: registrar en git (commit o al
  menos etiqueta) el estado post-arquitectura, y anotar en el receipt del
  respaldo ambos SHA y el HEAD.

### 7.3 Rollback selectivo que conserva operaciones y stock posteriores

- **Nunca restaurar filas completas de `products`**: precio, stock, ventas y
  compras siguen moviéndose. Se restauran sólo las columnas de 7.1, sólo en
  los productos tocados, identificados por `product_spec_save_receipts` con
  claves `catalog-fill/<lote>/<producto>/<n>`. Sin recibos no hay rollback
  selectivo: el aplicador debe escribirlos siempre.
- **Por el mismo comando, no por UPDATE directo**, para que corran los
  triggers de revisión, espejo y restricción diferida; `spec_revision` no se
  decrementa, se deja y se anota; `updated_at` no se restaura a ciegas porque
  otros procesos lo mueven.
- **Hechos**: nunca borrar por `created_at` (corregido 2026-09-06). Cada
  recibo del lote guarda el antes y el después exactos por campo; el rollback
  compara el «después» del recibo con el valor vivo y sólo si coinciden
  restaura el «antes» en valor, `source`, `confirmed`, `updated_at`,
  `spec_fact_values` y lecturas. Si el valor vivo difiere del «después», hubo
  un cambio posterior: se detiene y se lista, no se pisa. El espejo se
  verifica después.
- **Referencias sembradas** para el lote: son globales e inmutables; se
  conservan salvo decisión explícita por migración, y sólo si ningún producto
  las apunta.
- **Read-back del rollback**: diff instantánea contra vivo en los productos
  tocados sobre identidad y hechos (valor, procedencia, lecturas); cero
  diferencias salvo `spec_revision` y `updated_at`; conteo de hechos de
  bicicletas igual a 849; stock, precios y documentos intactos por
  construcción, y comprobados por conteo de movimientos posteriores al lote.
- **Ensayo**: el runbook exige probar la restauración en un entorno
  desechable; para fichas basta con un tenant sintético en local, como hacen
  las pruebas pgTAP actuales, antes de aplicar research-001.
