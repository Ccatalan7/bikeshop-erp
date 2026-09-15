# Revisión independiente · familia `component_set` (2026-09-15, ronda 224)

Revisión acotada del candidato de Root. Sólo lectura de sus archivos y sondas
propias locales en transacción con rollback; sin producción, sin migraciones
aplicadas, sin escritura de datos, código ni archivos de Root. Propuesta D2 no
tocada. La base local quedó sin plantillas residuales.

| Artefacto | Hash |
|---|---|
| `.tmp/db/component-set-2026-09-15-candidate.sql` | SHA-256 `5ddb8eb789e181ba6dc9fcd350160551920282d86b8a2b1439b76afb3598ea94` |
| `…-verification.sql` | SHA-256 `c25ced76…` |
| `component-set-2026-09-15-catalog.json` / `-cases.json` / `-packet.json` | `7234d558…` / `a95a9d79…` / `dbaca28c…` |
| `scripts/inventory/compile_component_set.py` / `test_component_set.py` | `01d0c587…` / `b7145a38…` |
| Preimagen productiva `.tmp/product-spec-catalog/component-set-20260915/preimage.json` (03:10:55Z) | `f327216f…` |
| Adjudicación de Root | `d990b767…` |
| Mi sonda `.tmp/product-spec-catalog/component-set-review-20260915/{boundary_cases.py, boundary-cases.json, boundary-diagnostic.sql}` | 17 casos, rollback |

## 1. Dictamen

**No encuentro defecto de propiedad, identidad, cantidad, resolución
tenant/global ni aislamiento que bloquee el SHA `5ddb8eb7…` para los dos
productos objetivo** (PO02409001058: cierres de rueda y asiento; NNV71: tuercas
y rodamientos). El candidato es metadata pura: una plantilla global, dos campos,
definiciones compartidas reutilizadas sin cambio, guardias de deriva y de
validador vigentes, revisión 3 confirmada por replay exacto.

**Un hallazgo que Root debe adjudicar antes de publicar, porque corregirlo
cambia el SHA:** `rim_brake` figura entre las nueve familias hijas y no es una
pieza sino una presentación completa (§3 H1). Los dos objetivos no la necesitan.

Todo lo demás son límites documentados (§4) y fronteras que añadí y pasan en
los dos motores (§5).

## 2. Qué verifiqué y cómo

- **Delta exacto.** Un `spec_templates` global (`8209a066…`, `component_set`,
  `tenant_id` null, activa, `contract_version` 3) y dos `spec_template_fields`
  (`spec_evidence_source` en `declaration`, `kit_members` en `contents`).
  `records.spec_definitions` y `spec_definition_values` vacíos; las dos
  definiciones reutilizadas van en `reused_definitions` y el publicador exige
  que sigan byte a byte iguales a la preimagen (incluido `updated_at` y sus
  opciones), fallando cerrado si no. El SHA embebido del catálogo
  (`7234d558…`) y de la preimagen (`f327216f…`) coinciden con los archivos.
- **Raíz sólo con contenido y fuente.** `roles` = `{kit_members: contents,
  spec_evidence_source: declaration}`; `semantic_roles` marca la fuente como
  `evidence`; ningún campo intrínseco, ninguna medida, ninguna tabla de
  compatibilidad. `required_when always` en ambos, `prerequisites
  kit_members → [spec_evidence_source]`, `row_conditions.allowed_options.family`
  con las nueve claves, `member_profiles` idéntico a las nueve familias ya
  habilitadas (identidad `member_role, position, identity_brand,
  identity_model`, `family_column = family`).
- **Guardia del validador.** El md5 `ac0738d5…` que exige el candidato es el
  cuerpo de `spec_validate_draft_internal_v1` registrado por
  `20260907026000` y usado por todas las publicaciones del 09-07/09-08 y por las
  dos promovidas del 09-15 (`20260915004000`, `20260915023000`); ninguna
  migración posterior a `20260906170000` redefine el validador. El trigger de
  revisión no cambia desde `20260906200000`: plantilla nueva 1 + dos campos = 3,
  y el replay exacto lo comprueba porque `contract_version: 3` es parte de
  `exact_metadata`.
- **Resolución tenant/global.** Plantilla y definiciones globales; el
  publicador rechaza homónimos con otro id en global o en el tenant auditado;
  la preimagen muestra `template_collisions: []` por clave e id. Los perfiles
  resuelven la familia tenant-primero y luego global entre plantillas activas
  (`get_product_spec_member_template_v1` y `spec_member_binding_internal_v1`).
  No hay mapeo de categoría: la ficha sólo llega por asignación explícita, como
  dice la adjudicación. Las dos migraciones promovidas del 09-15 no tocan a
  ninguna de las nueve hijas (intersección vacía), así que la premisa «sin
  `member_profiles` propios» sigue válida después de ellas.
- **Identidad y aislamiento.** Cada fila conserva `id` propio y un perfil
  activo por fila; la identidad que el servidor fija al vincular incluye la
  columna de familia además de las cuatro columnas de identidad
  (`spec_member_binding_internal_v1`), de modo que «tuerca» y «rodamiento» con
  los mismos tokens no se confunden en el enlace. En el editor, el selector
  muestra `_title` (marca/modelo · rol · posición) más el contexto «Sin ficha ·
  Componentes incluidos · configuración N» (`_rowLocation`), y la tabla raíz
  rotula la familia por token.
- **Reproducción.** Dart 14/14 con ambos `--dart-define` (plantilla + 13
  casos). Los ensayos SQL de Root (forward + replay exacto, rechazo de deriva de
  plantilla y de definición compartida) los leí en sus logs y no los reejecuté
  para no pisar su evidencia; mi sonda usa los mismos constructores
  (`prepare`, `generate_migration`) y obtiene `exact_metadata` 1/1 y
  `product_observations_and_identity_unchanged` 1/1 en forward y replay.

## 3. Hallazgos

**H1 · `rim_brake` no es una pieza (adjudicar antes de publicar).** La plantilla
viva `rim_brake` `3a76d564…` v2 se llama «Freno de Llanta / V-Brake» y sus roles
son `brake_system`, `brake_position`, `tool_size_mm` y `reach_adjust`
(alcance de maneta): es la presentación completa con maneta, no un cáliper ni
una pastilla, y tiene 28 productos. El propio paquete excluye
`drivetrain_kit` como «assembly_cannot_be_member»; `rim_brake` es el mismo caso
en frenos. Además la propuesta D2 (aún propuesta) le daría `kit_members` a
`rim_brake`; con el vacío E1 (el scope de miembro no excluye campos de
contenido), un `component_set` con una fila `rim_brake` anidaría contenidos
dentro de contenidos, que es la recursión que la adjudicación prohíbe. Ninguno
de los dos objetivos la necesita. Opciones: retirarla ahora (ocho familias,
nuevo SHA y nueva preimagen) o dejar constancia explícita de que se acepta una
presentación completa como miembro y de que D2 tendría que vetar `rim_brake`
dentro de un conjunto. `brake_caliper`, `brake_lever` y `brake_pad` sí son
piezas.

**H2 · Vocabulario de rol y títulos iguales (menor, no bloquea).** `member_role`
no tiene «cierre», «tuerca» ni «abrazadera»: los cierres, la abrazadera y las
tuercas van como «otro»; los rodamientos sí tienen «rodamientos». Dos tuercas
de distinta rosca con `otro · Sin posición` producen títulos idénticos
(«otro · Sin posición · modelo sin confirmar») y se distinguen sólo por
«configuración N» y por lo que el operador escriba en `identity_model`
(p. ej. «M10x1»). La semántica de cantidad lo exige: piezas que difieren en
medida van en filas distintas y el texto de identidad es lo único que las
separa. Ampliar `member_role` es un cambio de la definición compartida
`d0cfc800…`, fuera de este delta.

**H3 · Cantidad: el motor sólo exige entero positivo.** Fracción, negativo,
texto, espacio y número JSON bloquean (`row_shape`); falta de cantidad queda
pendiente (`row_incomplete`); no hay máximo (`99999999999` se acepta). «Una
cantidad agrupa sólo piezas idénticas» vive en el helper: dos filas idénticas
se aceptan (sin `unique_by`, igual que D1 pendiente (e)) y una fila con
cantidad 2 es indistinguible para el motor de dos filas. Correcto para lo que
se pide; no es una garantía.

**H4 · Fila sin fuente.** `sources: []` se acepta en la validación de filas;
la evidencia `package_or_label` es documental. La ficha del miembro puede
crearse, pero identificar (MPN/marca) exige al menos una fuente en el
servidor (`jsonb_array_length(identity_sources)=0` → 23514) y en el cliente
(`ProductSpecMemberDraft.identify`). Coherente; documentado.

**H5 · Familia permitida sin ficha activa no es pendiente.** La validación de
filas es estática: en mi sonda, con ninguna de las nueve plantillas presente
en la base local, una fila `seat_clamp` valida sin incidencia. La creación del
perfil es la que falla (`get_product_spec_member_template_v1` :884, 23514).
Mismo hallazgo que D1 (218 §3); la preimagen productiva muestra las nueve
activas y globales, así que hoy no aplica, pero conviene una lectura real de
la RPC para una familia después de publicar.

**H6 · Entorno del ensayo.** La base local tiene 21 plantillas globales y
**ninguna** de las nueve hijas, ni el framework de perfiles. El ensayo local
prueba el publicador, la deriva, la revisión y el validador sobre la copia
namespaced de `kit_members` del paquete; **no** prueba la resolución de
familias ni el guardado de perfiles (Root lo está ensayando cargando el
candidato del framework dentro de la transacción; fuera de mi alcance).

**H7 · Mantenimiento de los casos.** `cannot_contain_itself` da `row_shape`
porque `component_set` no está en las 105 familias de la definición
compartida; si una publicación futura la agrega, el caso pasa a `row_option`
(sigue bloqueando) y hay que actualizar la expectativa. La diferencia con D1
(`field_constraint` en SQL) es real y no un ajuste: las plantillas con
`row_conditions` emiten `row_shape` y el validador descarta el
`field_constraint` duplicado (`20260907020000:513`, `20260907022000:161`); la
corrección de Root fue correcta.

## 4. Límites de este dictamen

- No leí producción; la única evidencia productiva es la preimagen de Root.
- No juzgo los 28 productos `rim_brake` ni ninguna combinación mecánica; no
  hay compatibilidad deducida del envase y el motor no la produce.
- La existencia del conjunto no cierra sucesores de las nueve familias, no
  autoriza llenado ni asignación, y no cuenta como original cerrado del plan
  de 105.
- La prueba de perfiles (crear, aislar, editar dentro de esta plantilla) sigue
  pendiente y es de Root.

## 5. Fronteras añadidas (17 casos, mismos dos motores)

Archivo `boundary-cases.json`; SQL por `prepare` + diagnóstico (`passed` en los
17), Dart por el arnés integrado con `SPEC_CATALOG_CASES` (18/18: plantilla + 17).

| Caso | Resultado esperado y obtenido |
|---|---|
| cantidad `1.5`, `-1`, `dos`, `" 2"`, número JSON `2` | `row_shape` bloqueante |
| sin cantidad | `row_incomplete` pendiente |
| cantidad `99999999999` | aceptada (sin máximo) |
| posición `Arriba`; rol `tuerca`; columna ajena `size` | `row_shape` |
| `sources: []` | aceptada (ver H4) |
| URL inválida; URL duplicada | `row_shape` |
| dos filas `fastener` idénticas | aceptadas, 2 filas (ver H3) |
| `fastener` M5 y M6 por `identity_model` | aceptadas, 2 filas |
| `wheel_retention` Delantero + Trasero + `seat_clamp` | aceptadas, 3 filas (forma de PO02409001058) |
| `seat_clamp` con rol `rodamientos` | aceptada: rol y familia son tokens independientes |
| `seat_clamp` sin plantilla disponible | sin incidencia (ver H5) |

## 6. Cierre

Propiedad de los archivos de vuelta a Root. Decisión pendiente de Root: H1
(`rim_brake`), antes de fijar el SHA a publicar. Sin cambios en D2.
