# Revisión final · candidato D1 `drivetrain_kit` v3 → v16 — 2026-09-15

Ronda 220. Sólo lectura; sin código, SQL, runtime, datos ni otros documentos.
Leídos: `scripts/inventory/compile_drivetrain_kit_members.py` `2c2069d3…`,
`scripts/inventory/test_drivetrain_kit_members.py` `e7f259bf…`,
`scripts/inventory/test_existing_spec_candidate.py` `724a3173…`,
`drivetrain-kit-members-2026-09-15-{catalog,cases,packet}.json`
(`f4b15f8d…`, `6546c3a2…`, `b2255158…`), `.tmp/db/…-candidate.sql`
`6de5a28f…`, `.tmp/db/…-verification.sql` `f6ba8092…`, y la evidencia de
`.tmp/product-spec-catalog/drivetrain-kit-members-20260915/`.

**Ejecutado por mí:** `test/unit/product_spec_integrated_catalog_test.dart`
con `--dart-define=SPEC_CATALOG_INPUT=…drivetrain-kit-members-2026-09-15-catalog.json`
y `--dart-define=SPEC_CATALOG_CASES=…-cases.json` → **12 PASS** (los 12 del
kit). *Corrección 221:* mi primera corrida fue sin esos dos defines y ejecutó
los 432 casos por defecto del catálogo integrado, que no son cobertura de D1;
la cifra válida para este delta es 12. Los logs SQL de Root los leí; no corrí
SQL.

## Dictamen: **aprobado para publicar este delta**, sin bloqueantes.

No afirma compatibilidad, fill ni activación de sucesores; el paquete tampoco
(`product_writes`, `fill_allowed`, `mechanical_approval` = false).

## Evidencia (diff propio del paquete contra la preimagen viva)

- **Preimagen.** `preimage_sha256` coincide con
  `drivetrain-kit-members-20260915/preimage.json`; plantilla `6d80cd0c…` v3,
  12 campos, contrato `version 1 / coverage template / prerequisites {}`. El
  compilador rechaza cualquier otra forma (una plantilla, 12 campos exactos,
  definiciones = 11 + `spec_evidence_source` + `kit_members`, roles y contrato
  viejos exactos; :38-58).
- **Parche de plantilla.** Cambia sólo `form_contract` (más `contract_version`
  3 → 16 y `updated_at`). Roles después: 11 `legacy`, `kit_members: contents`,
  `spec_evidence_source: declaration`; `member_profiles` idéntico al de las
  nueve (`COLLECTIONS` importado); `prerequisites.kit_members =
  [spec_evidence_source]`; `allowed_when never` para legacy; `required_when
  always` sólo para `kit_members`; ayuda del kit que niega compatibilidad entre
  piezas.
- **Parches de campo.** Los 11 campos reales cambian **sólo** `section_key →
  legacy` (`is_required` ya era false); ids, `helper_text`, `default_value_json`,
  `visibility_rules`, `option_rules`, `constraint_rules` y `sort_order`
  iguales byte a byte. Un solo campo nuevo: `kit_members` (`d0cfc800…`,
  sección `contents`, global, sin ayuda ni default).
- **Sin definiciones ni prototipos.** `records.spec_definitions` y
  `spec_definition_values` vacíos (el compilador aborta si no); 13
  `reused_definitions` comparadas exactas por el guard de deriva; los tres
  prototipos se rechazan por clave **y** por id en el forward (candidato :22)
  y en el verificador (:1); los tres escalares ausentes no se agregan.
  Producción antes del cambio: `no_unpublished_kit_prototypes = 1` y luego
  `division by zero` en `exact_metadata`, es decir, falló por preimagen
  antigua y no por prototipos; `population.json`: 6 productos con la
  plantilla, `prototype_definitions: []`.
- **Revisión exacta.** 16 = 3 + 1 (contrato) + 11 (campos actualizados) + 1
  (campo insertado), coherente con `spec_contract_revision_internal_v1`; el
  registro de plantilla del paquete lleva `contract_version 16`, así que el
  verificador la afirma exacta.
- **Mismo SQL probado y publicado.** El documento embebido en candidato y
  verificador es igual al paquete; el arnés local usa los mismos
  `generate_migration`/`generate_verifier` con ids y claves enrutados a
  fixtures (`prepare(...)`), por eso su documento no es idéntico y no debe
  serlo. Forward, replay exacto, 11 casos y 13 aserciones del agregado en
  rollback: `ok` en los logs; conservación de hechos, productos, referencias y
  mapeos por huella antes/después en el propio forward.
- **Límites respetados.** Nada compara piezas entre sí (la aserción «member
  measurements never enter the root fact payload» lo afirma), nada proyecta
  miembros al consumidor raíz, ningún sucesor se activa; el resolutor de
  plantilla privada se prueba con un `chain` sintético del tenant.

## Consecuencias que conviene dejar dichas (no son defectos)

- Con `required_when.kit_members = always`, los 6 kits mostrarán
  `required_missing` **pendiente** (no bloqueante) hasta listar sus piezas,
  sin cambio de datos. Es la regla elegida: un kit declara su contenido.
- Zero hechos y zero perfiles en esos 6 productos lo tomo del read-back de
  Root; `population.json` sólo lista productos y prototipos. La huella del
  forward conserva lo que haya de todos modos.
- La utilidad real de los perfiles en este kit depende de que cada familia de
  pieza tenga plantilla activa (`get_product_spec_member_template_v1` :884
  falla si no); no es parte de este delta.

## Sobre 219

Leí que las familias sin nombre quedan visibles como «Nombre no disponible ·
clave» y que la carga de nombres degrada sin bloquear; no reabro ese alcance:
sin regresión concreta que señalar contra este delta.

## Qué no toqué

Ningún archivo de Root, código, SQL, dato ni runtime. Sólo este documento.
