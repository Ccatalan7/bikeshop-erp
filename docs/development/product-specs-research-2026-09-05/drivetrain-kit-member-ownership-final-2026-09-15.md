# D1 · propiedad de datos por pieza en `drivetrain_kit` — decisión final propuesta (2026-09-15, corregida en ronda 218)

Ronda 217 con corrección 218. Sólo lectura: adjudicación `6fc44761…`,
integración `0bfee2aa…`, candidato congelado
`original-successors-integrated-catalog-2026-09-08.json` `e0cccea8…` (evidencia
histórica, no se reescribe), migración del framework `20260914213000` y la
preimagen viva `.tmp/product-spec-catalog/assignment-original-parts-20260915/target-metadata.json`
`d97408d8…`. Sin SQL, datos, activación ni cambios a candidatos ni a documentos
de Root. No certifica compatibilidad ni autoriza fill.

**Corrección 218.** La versión 217 leyó el candidato congelado como si fuera
producción: afirmó «`kit_members` + quince legacy» y un delta «sólo opt-in».
Falso. Lo que sigue parte de la plantilla viva.

## 1. Punto de partida: `drivetrain_kit` v3 en producción

`6d80cd0c…`, global, activa, **12 campos**, sin `member_profiles`, sin
`row_coherence`, `prerequisites {}`:

| Campo vivo | Tipo | Rol hoy | Después |
|---|---|---|---|
| `kit_contents` | text | contents | **legacy** (conservado); su sucesor estructurado es `kit_members` |
| `front_chainring_count` | multi_select | primary | legacy (conservado) |
| `chainring_teeth` | text | primary | legacy (conservado) |
| `bottom_bracket_family` | single_select | primary | legacy (conservado) |
| `spindle_interface` | single_select | primary | legacy (conservado) |
| `crank_arm_length_mm` | number | measurement | legacy (conservado) |
| `chain_ebike_rated` | boolean | measurement | legacy (conservado) |
| `drivetrain_primary_ecosystem` | single_select | primary | legacy (conservado) |
| `drivetrain_declared_compatible_ecosystems` | multi_select | declaration | legacy (conservado) |
| `drivetrain_platform` | single_select | primary | legacy (conservado) |
| `chain_profile_family` | multi_select | primary | legacy (conservado) |
| `spec_evidence_source` | text | declaration | **permanece** activo |
| — | rows (`d0cfc800…`, definición compartida ya en producción) | — | **`kit_members` se agrega** como campo `contents` con `member_profiles` |

Las tres definiciones prototipo del candidato (`…_member_evidence`
`1b828eee…`, `…_member_interfaces` `16568903…`, `…_member_fitments`
`98492b05…`) y los tres escalares `rear_speeds`, `chainring_count` e
`included_chainring_count` **no existen en producción**: no se crean, ni
siquiera como legacy. Retirar los 11 a legacy conserva físicamente sus
observaciones (el escritor las excluye del borrado y rechaza cambios; los
lectores con `p_include_legacy` las muestran; el roundtrip tipado ya aplicado
acepta el número `crank_arm_length_mm` idéntico en texto decimal).

## 2. Dónde vive cada dato de pieza (mapa)

Regla: **identidad/perfil** = lo que el framework guarda por perfil;
**interfaz intrínseca** = lo que la plantilla de la pieza declara con tipo;
**afirmación dirigida al destino** = tablas de declaración de la plantilla de
la pieza más las `claims` de la referencia elegida.

### Del prototipo `…_member_evidence` → identidad/perfil

| Columna prototipo | Después | Contrato que lo soporta |
|---|---|---|
| `member_reference` | fila `kit_members` ↔ perfil (`member_row_id`) | `member_profiles.collections`, `spec_member_binding_internal_v1`, índice único `product_spec_member_profiles_active_row` |
| `manufacturer_sku` | `product_spec_member_profiles.manufacturer_sku`, confirmado con fuente de la fila | `identify` (cliente); servidor :752-762 |
| `source_url` | `sources` de la fila → `identity_sources` del perfil | validador de filas (URL por fila) |
| `source_document` (texto) | `spec_evidence_source` de la plantilla de la pieza, en el scope del perfil | toda plantilla de pieza lo declara |
| `edition` | **pendiente**: no hay columna; `identity_model` conserva el modelo exacto de la fila y no se le añade la edición. La edición queda documentada sólo cuando exista referencia (`reference_id`) o MPN documentado | `product_spec_references` (`label`, `manufacturer_sku`, `reviewed_on`) |

### Del prototipo `…_member_interfaces` → interfaz intrínseca de la pieza

cassette `cassette_spline_standard`, `freehub_bodies_accepted` · crankset
`chainring_mount_type`, `chainring_mounting`, `pedal_thread`, `chainline_mm`,
`crank_axle_interface_declarations` · bottom_bracket `spindle_interface`,
`bb_shell_ports`, `bb_accepted_spindles` · chainring `chainring_mount_type`,
`chainring_bcd_mm`, `chainring_direct_mount_generation` · chain
`chain_pitch_mm`, `chain_outer_width_mm`, `chain_width_family`, `chain_speeds`
· rear_derailleur `rear_derailleur_mount_type`, `derailleur_cage_length`,
`rear_derailleur_actuation_ratio_declaration` · front_derailleur
`front_derailleur_mount_type`, `front_derailleur_cable_pull` · freewheel
`freewheel_thread_standard`. Tipados y validados por su plantilla; la tabla
genérica era texto libre. `shifter` sólo lo expresa como afirmación: laguna de
esa familia, no de D1.

### Del prototipo `…_member_fitments` → afirmación dirigida al destino, de la pieza

chain `chain_application_declarations` y chain_link
`connector_target_declarations` (mismas columnas y vocabulario:
`scope_kind`, `target_*`, `verdict`, `conditions`, `source_*`) · crankset y
chainring `*_compatibility_claims` (`declared_grade`) · rear_derailleur y
shifter `*_compatibility_claims` (`target_component`, `declaration_result`) ·
cassette `freehub_bodies_accepted` (`status`) · bottom_bracket
`bb_accepted_spindles` (`status`); más las `claims` de la referencia por
`reference_id`. No unifico vocabularios: no es D1.

### Lo que queda en el kit

`kit_members` (`contents`, `member_profiles` idéntico a las nueve: versión 1,
`family_column = family`, identidad `[member_role, position, identity_brand,
identity_model]`), `spec_evidence_source` (`declaration`) con prerrequisito
`kit_members → [spec_evidence_source]` (evidencia del envase del kit), y los
11 legacy. Ningún campo nuevo de kit, ninguna medida global reintroducida.

## 3. Qué produce «pendiente» y qué RPC falla (sin atribuir de más)

- Fila de `kit_members` cuya familia **no tiene plantilla activa**: la fila se
  guarda (la familia es una opción válida) y no hay pendiente: **ningún guard
  emite una incidencia** por eso; la pieza simplemente no tiene perfil. Al
  intentar crearlo, la RPC `get_product_spec_member_template_v1` **falla**
  con 23514 «La familia aún no tiene una ficha disponible» (:884; antes :879
  si la familia no está en la colección). El editor lo presenta hoy como error
  de carga reintentable (captura genérica en `_create`); es texto, no
  contrato.
- Perfil ya persistido: la FK `(template_id, active_template_guard) →
  spec_templates(id, is_active)` impide desactivar la plantilla mientras haya
  perfiles activos; si el vínculo deja de resolver (fila, familia o plantilla
  cambiadas), `spec_member_binding_internal_v1` **falla** en la validación
  diferida del guardado (:446 fila ausente, :452 familia sin ficha) hasta
  archivar la ficha.
- El guard valida **por perfil**: identidad por proyección, un perfil activo
  por fila, hechos sólo de la plantilla del perfil y en su scope (:499-503),
  referencia exigible (:466-473), identificar con fuente y vincular con la
  misma identidad (:542-558). **No** compara entre perfiles ni tablas, no
  detecta dos filas de la misma pieza (`kit_members` sin `unique_by`), no
  deriva conexiones internas del kit y no proyecta hechos ni reclamaciones de
  miembros al consumidor de compatibilidad (`get_product_spec_contexts_v1`
  lee sólo el scope raíz).

## 4. Casos imprescindibles (intención; los escribe Root)

1. **Preimagen viva por id y clave:** los 12 campos y roles exactos de la
   tabla del §1; las tres definiciones prototipo y los tres escalares ausentes
   no existen y **no se crean**; `kit_members` `d0cfc800…` existe y es la misma
   definición de las nueve.
2. **Delta exacto:** un `spec_template_fields` nuevo (`kit_members`,
   sección `contents`), `roles` con 11 `legacy` + `kit_members: contents` +
   `spec_evidence_source: declaration`, `member_profiles` añadido,
   `prerequisites.kit_members = [spec_evidence_source]`; ningún otro campo,
   definición ni opción cambia.
3. **Revisión, no «+1»:** el trigger sube `contract_version` una vez por el
   cambio de `form_contract` y una vez por cada fila de `spec_template_fields`
   insertada, actualizada o borrada; el verificador afirma el número que
   resulte del delta (calculado a partir de la preimagen), no un incremento
   supuesto.
4. **Conservación legacy:** huella de `spec_facts` igual antes y después; las
   observaciones de los 11 campos siguen legibles con `p_include_legacy`; un
   roundtrip idéntico de `crank_arm_length_mm` en texto decimal se acepta y un
   cambio se rechaza.
5. **Sin mezcla entre familias:** un perfil de cassette rechaza un hecho de
   biela (23514 «El hecho no pertenece a la ficha del componente»).
6. **Sin duplicar piezas:** dos perfiles no toman la misma fila; una segunda
   fila idéntica obtiene su propio perfil y scope y sus declaraciones no se
   funden.
7. **Un solo MPN:** el MPN de la pieza vive sólo en su perfil; el payload raíz
   con una clave prototipo rechaza («La respuesta no pertenece a esta
   plantilla»).
8. **Evidencia del kit exigida:** `kit_members` sin `spec_evidence_source`
   queda pendiente por el prerrequisito nuevo.
9. **Nada conecta piezas:** con dos perfiles con reclamaciones, el contexto
   raíz no expone reclamaciones de miembros ni veredicto nuevo; se afirma la
   ausencia.
10. **Familia sin ficha:** una fila con familia sin plantilla activa se guarda
    sin incidencia; `get_product_spec_member_template_v1` para esa fila
    devuelve 23514 :884, no un perfil ni un pendiente.

## 5. Conclusión y recomendación

**Integrar ahora** el delta de metadata que Root prepara sobre la preimagen
viva: agregar `kit_members` compartido con `member_profiles`, retirar a
legacy los 11 campos antiguos conservándolos, mantener `spec_evidence_source`
con prerrequisito, no crear ninguna definición prototipo ni escalar ausente,
verificar por id/clave y por revisión calculada, con los casos 1-10. Es un
cambio de campos y contrato, no un opt-in puro: exige sus propias revisiones y
su propio verificador.

**Pendiente, con nombre:** (a) edición por pieza, hasta referencia o MPN
documentados; (b) proyección de hechos/reclamaciones de miembros al
consumidor de compatibilidad, capacidad inexistente; (c) semántica de
conexión interna del kit: ninguna; (d) unificación de vocabularios de
veredicto entre familias; (e) `unique_by` en `kit_members`; (f) el texto del
editor ante el 23514 de familia sin ficha; (g) la activación de las
plantillas de las piezas es una decisión aparte: sin ella la RPC falla y la
pieza queda sin perfil, no pendiente.
