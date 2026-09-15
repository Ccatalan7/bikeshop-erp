# Revisión independiente del editor de fichas de piezas (F2) — 2026-09-14

Ronda 209. Revisión de sólo lectura de `product_form_page.dart` y
`widgets/product_spec_member_editor.dart` congelados por Root, con sus modelos
y servicios. Sin SQL, sin runtime, sin producción, sin activación ni relleno.
Todos los valores de este documento son sintéticos (fixture del repo).

## Alcance y método

- Congelados (hash leído al empezar y al terminar, sin cambios):
  `lib/modules/inventory/pages/product_form_page.dart` `9bda1f9c…`,
  `lib/modules/inventory/widgets/product_spec_member_editor.dart` `1b6e306e…`.
- Leídos para el juicio: `models/product_spec_member_draft.dart` `97249b96…`,
  `models/product_spec_member_profile.dart` `2920ac12…`,
  `models/product_spec_contract.dart` `4c0db155…`,
  `services/spec_engine_service.dart` `a75d5781…`,
  `services/inventory_service.dart` `37884c46…`,
  `lib/shared/widgets/vb_searchable_select.dart` `a909b10a…`,
  `test/widget/product_spec_member_editor_test.dart` `52b41b63…`,
  `test/fixtures/product_spec_member_profiles.json` `b2b4d811…`,
  `supabase/migrations/20260914213000_product_spec_member_profiles.sql`
  `dbe9b55b…` (sólo lectura del archivo, para paridad cliente/servidor).
- Ejecutado: los 12 widget tests de Root (`flutter test --no-pub
  test/widget/product_spec_member_editor_test.dart` → **12 PASS**) y cinco
  sondas propias en `.tmp/product-spec-catalog/member_editor_review_probe_test.dart`
  (ignorado por git; 5 PASS = las cinco conductas reproducidas). Las sondas
  montan el editor solo, con el mismo `buildFields` sintético del test de Root;
  ninguna toca base, red ni UI real.
- Guías: `.github/GUI_DESIGN_PRINCIPLES.md` («Las palabras son parte del
  diseño» :49-91, §5 :483-503, §8 :901-946, §9 :947-969) y
  `docs/architecture/universal-ui-component-system.md` (S-06 :249,
  F-02/F-04 :449, I-01 :459). No se copiaron valores visuales ni se inventaron
  tokens; lo visual queda con Root.

## Resumen

- **Sin cruce ni pérdida de observaciones** entre piezas o con la raíz: el
  renderizador compartido está parametrizado por miembro en todos los tipos
  (incluida la rama de filas) y los `Key`/`scope` son únicos por ficha.
- **C1 y C2 cerrados en el cliente** tal como describe Root; los guardias
  asíncronos de creación/lectura son correctos.
- **Cuatro defectos demostrables (E1–E4)**, todos de claridad o de mensaje
  con causa en código; ninguno pierde datos ni rompe el contrato con el
  servidor. Arreglo mínimo indicado en cada uno.
- **Pendientes de runtime (R1–R5)**, no probados: la superficie de error de
  guardado para fallos de miembros, la persistencia del texto del campo tras
  adoptar el recibo, el montaje en teléfono dentro del formulario, y dos
  decisiones visuales que son de Root.

**No afirmo F2 cerrado.**

## Verificado sin hallazgo (con línea)

Claves/callbacks a raíz (`product_form_page.dart`):

- La rama `json`/filas usa `template.rowConditions.fields[def.key]` y
  `template.coherence.optionsFor(def.key, values, template.labelFor)` con el
  template y los valores del miembro (:8016-8029). Ayuda, opciones, conducta y
  validación también van por parámetro (`_specHelperTextForField` :1531,
  `_specFieldBehaviorForValues` :1549, `_specFieldOptions` :1646,
  `_validateSpecField` :1678; llamada con `template:`/`values:` del miembro en
  :7945-7946).
- `values = member?.values ?? _specValues`, `issues = member?.validate() ??
  _specIssues`, `reference = member == null ? _specReference :
  member.reference`, `scope = 'member-${member.id}-'`, `displayKey =
  '${member.id}-$memberGeneration'` (:7851-7932; `isEnabled` :7954). Las `Semantics` y los
  `ValueKey` llevan el scope: no hay colisión entre raíz y piezas ni entre
  piezas.
- `_resolveSpecInference` sigue leyendo `_specReference` (:1417-1447): es la
  inferencia de la raíz por diseño; el miembro deriva en
  `ProductSpecMemberDraft.selectReference`, sólo campos activos.
- Lo único ligado a raíz que sigue alcanzable desde un miembro es
  `_buildSpecReadOnlyValue` (`ValueKey('spec-readonly-$id-$_specDisplayGeneration')`,
  :7595-7604) para campos `legacy` de la pieza. Es inerte: un borrador de
  miembro nunca cambia un valor legacy (`setValue` los rechaza,
  `product_spec_member_draft.dart:106-108`).

Estado obsoleto / C1 / C2:

- Cambio de categoría (`_loadSpecTemplate` :1321-1327, :1374-1375): los
  borradores se conservan (`??=`), una revisión distinta se rechaza sin
  bendecirla, y `_specRevision` no se refresca mientras existan borradores.
  Con la colección ausente en la nueva plantilla el editor muestra el error de
  vínculo por ficha (`_bindingError`, editor :135-147) y la compuerta de
  guardado bloquea con `_specMemberSaveError` (:4847-4856). Nada se archiva
  solo. Cubierto por los 6 tests «survive category removal».
- Adopción del recibo (`_adoptSavedSpecContext` :4787-4823): drafts nuevos,
  colecciones del recibo, `_specRevision` del recibo, `_specDisplayGeneration++` (:4805);
  el editor limpia peticiones, referencias, errores, generaciones y
  controladores MPN al cambiar la identidad de `drafts` (editor :77-93). La
  lista `_specReferences` se mantiene: la última carga fue para la plantilla
  actual, que es la guardada. Cubierto por «committed read-back».
- Ambas rutas (set :5276, simple :5307) adoptan antes de la
  sincronización WhatsApp (:5325-5334). `p_member_profiles` va siempre que
  existan borradores (:4837-4839), incluso vacío, lo que selecciona la RPC v2.

Asíncronos (editor):

- `_create` (:159-215): `++_request`, snapshot JSON de identidad y fuentes,
  tras el `await` exige `mounted`, misma petición, mismo dueño (`identical`),
  misma plantilla padre e igual `contractVersion`, fila presente e idéntica.
  `_loadReferences` (:217-241) exige el mismo dueño. Cubierto por «late family
  read» y «failed read can retry».
- Cambiar la selección durante una carga no la cancela: la ficha se crea para
  la fila pedida y queda seleccionada. Aceptable.

Elecciones imposibles con guardia:

- Crear: deshabilitado sin familia válida o con carga en curso (:484-492).
- Selección ausente de `choices` cae a la primera opción (:423-424): no hay
  `value` fuera de `options` en S-06.
- Identificar/vincular/referencia/archivar lanzan `FormatException` que
  `_change` convierte en aviso (:149-157). Ver E1 por el texto.

Desconocido vs falso:

- Booleano tri-estado (`value: currentValue is bool ? currentValue : null`,
  :7993-8007); historial `_value` distingue `Sí`/`No`/`Sin confirmar`
  (:396-405); `_title` sólo compone valores conocidos (:121-132); identificar
  un vacío exige fuente de la fila (`identify`, draft :156-160).

Identidad / MPN:

- El MPN se edita sólo mientras es nulo (:290) y cambiarlo exige archivar:
  paridad con el servidor (`…member_profiles.sql:752-762`). `identify` vuelve a
  pasar la referencia (`selectReference(draft.reference)`, :304) para derivar
  con el código confirmado.

Igualdad fuente/claim:

- La creación compara identidad **y** fuentes de la fila (:168-169, :184-189);
  identificar copia `row.sources`; los hechos de la referencia que la plantilla
  no tiene se ocultan (:370-374) y el validador compartido los bloquea con
  `reference_scope` (contract :218-232): consistente.

Montaje de superficies:

- Un solo host de pestaña para todos los anchos (:5819-5824; `isWide` sólo
  mueve la barra lateral de la pestaña 0). Servicios sustituyen la pestaña
  (:5783, :5819-5824) y no llaman `_specSaveCommand` (:5301-5304). El editor se
  monta con ficha (:7774) y sin ficha (:7735); no se monta en carga ni en
  error de carga (:7679-7697), que es lo correcto. Lecturas de familia y
  referencias pasan por `_readMemberSpecs` con usuario y tenant antes y después
  (:7798-7814).

## Defectos demostrables

### E1 — Confirmar sin cambio deja bloqueado «vincular» con una razón falsa

- **Síntoma.** Con la identidad completa y con fuentes, «Confirmar
  identificación de la pieza» está siempre habilitado (editor :296-306). Al
  pulsarlo sin nada que confirmar, el borrador fija `_bindingAction =
  'identify'` (draft :167) y el `upsert` sale con `binding_action: identify`.
  Desde ese momento «Vincular a otra fila de la misma pieza» falla con «La fila
  elegida debe conservar la misma identidad.» aunque la fila sí la conserva
  (draft :177-180). En el orden inverso, tras vincular, confirmar falla con
  «Identificar exige una fuente y conservar los datos ya confirmados.» aunque
  hay fuente y nada cambió (draft :156-162).
- **Demostración.** Sonda P1: `identify` sin cambios → `binding_action:
  identify`; `rebind('r3')` (fila idéntica a `r1`) → ese mensaje; un borrador
  fresco vincula `r3` sin error y luego `identify` falla con el otro mensaje.
- **Servidor.** Inofensivo: la rama `identify` sólo corre si identidad o MPN
  difieren (`…member_profiles.sql:755-762`); la exclusividad por edición es
  correcta y refleja el servidor. El defecto es de palabras (guía :49-91:
  «Nombra la acción por lo que hace»).
- **Arreglo mínimo.** En `identify`, si `next == _identity` y `nextSku ==
  manufacturerSku`, devolver sin tocar `_bindingAction` (o deshabilitar el
  botón cuando no hay nada que confirmar). Y dos mensajes propios para la
  exclusividad: «Ya confirmaste la identificación en esta edición; guarda antes
  de vincular otra fila» / «Ya vinculaste otra fila en esta edición; guarda
  antes de confirmar la identificación».

### E2 — El historial muestra claves internas y no dice cuándo

- **Síntoma.** «Fichas archivadas» (:510) lista cada dato con `Text(entry.key)`
  (editor :522): el dueño lee `member_test_length`, no la etiqueta. El
  subtítulo «Archivada · N datos conservados» no muestra `archivedAt`, que el
  modelo sí trae (`product_spec_member_profile.dart:160-169`).
- **Demostración.** Sonda P2 con la fixture `archived`: al desplegar,
  `member_test_length` y `member_test_included` aparecen como títulos; ninguna
  etiqueta; ninguna fecha.
- **Causa.** El servidor adjunta plantilla sólo a perfiles activos
  (`_archivedKeys`, profile :43-44), así que el editor no tiene `labelFor` para
  un archivado.
- **Arreglo mínimo.** Cliente: resolver la etiqueta desde cualquier plantilla
  del mismo `templateId` ya cargada (perfiles activos o borradores) y, si no
  hay, mostrar la clave con el rótulo «dato retirado de la ficha»; mostrar
  `archivedAt` en el subtítulo. Completo: que el lector v3 incluya `labels`
  (clave → etiqueta) por perfil archivado — es SQL de Root.
- **Nota de alcance.** El servidor guarda eventos con actor y estados
  (`product_spec_member_profile_events`), pero el contexto v3 no los expone;
  «historial» en el editor es sólo la lista de archivadas. No es defecto del
  editor; es una decisión pendiente de Root.

### E3 — Un cambio de sesión durante la lectura se presenta como «reintenta»

- **Síntoma.** `_readMemberSpecs` lanza `AuthorityScopeChangedException`
  (form :7798-7813). No es `FormatException`, así que `_create` cae en
  `catch (_)` y muestra «No se pudo cargar la ficha de esta pieza. Reintenta la
  carga.» (editor :208-212; igual en `_loadReferences` :231-234). El botón de
  crear vuelve a habilitarse. Reintentar falla igual. Mientras tanto la raíz
  trata el mismo caso con «La sesión cambió. Vuelve a abrir el producto.» y
  limpia el estado (:1385-1400), y el botón Guardar hace `return` silencioso
  (:4843-4846; guía :1185 sobre botones silenciosos).
- **Demostración.** Sonda P3: `loadTemplate` que lanza la excepción → aviso de
  reintento, sin la palabra «sesión», crear habilitado.
- **Arreglo mínimo.** En los callbacks del formulario (`loadTemplate`,
  `loadReferences`, :7816-7833) capturar `AuthorityScopeChangedException` y
  relanzar `FormatException('La sesión cambió. Vuelve a abrir el producto.')`,
  o que el editor la capture explícitamente. Mejor aún, que el formulario fije
  `_specLoadError` como hace la carga raíz, para que la compuerta de guardado
  hable en vez de callar.

### E4 — La misma pieza listada dos veces son dos opciones idénticas

- **Síntoma.** El selector «Pieza incluida» rotula cada fila con `_title`
  (editor :416-422); dos filas con la misma identidad (la misma pieza dos veces
  en Contenido) dan dos opciones iguales con el mismo contexto «Sin ficha». El
  selector de vínculo sí distingue con «Fila ${row.id}» (:311-321).
- **Demostración.** Sonda P5: `r3` idéntica a `r1`, sin perfiles → tres
  opciones, dos rótulos iguales.
- **Arreglo mínimo.** Añadir al `context` de las filas su posición en Contenido
  («Sin ficha · configuración N»), que es el mismo referente que ya usa
  `productSpecIssueMessage` (contract :104-118).

## Claridad de acciones e historial contra guías

- **G1 (con E5 de raíz).** La referencia con otro MPN se ofrece y luego se
  bloquea: el selector filtra por marca/modelo (editor :268-276) mientras
  `matchesIdentity` exige también el MPN (contract). Sonda P4: se ofrece
  `ref-a2`, al elegirla aparece «La referencia no corresponde…». Es
  recuperable (confirmar el MPN `A-2` con fuente y volver a pasar la
  referencia) y la raíz tiene el mismo filtro (:7496-7502), así que no lo
  cuento como error. Mínimo: mostrar el MPN en el `context` de la opción (hoy
  sólo va en `searchText`), para que el operador vea qué código tendría que
  confirmar.
- **G2.** Rótulos verbo+objeto correctos (§5). Archivar es reversible hasta
  guardar («Deshacer»), así que no pide superficie bloqueante (§9). Lo que
  falta es decir la exclusividad confirmar/vincular por edición (E1).
- **G3.** `_title` para una fila sin modelo da «Fixture · caliper · rear»,
  que se lee como identidad completa. Mínimo: sufijo «modelo sin confirmar»
  cuando `identity_model` es desconocido; el historial ya usa «Sin confirmar».
- **G4 (decisión de Root, no defecto).** El historial usa `ExpansionTile` y
  `ListTile` de Material (editor :514-528). No encontré id canónico de
  acordeón o lista en `universal-ui-component-system.md`; AGENTS.md pide
  reutilizar el dueño canónico y no crear una variante local. Lo dejo a Root
  como decisión visual; no propongo valores.

## Pendientes de runtime (no probados)

- **R1.** Errores del servidor por miembros llegan como texto: «Ficha de
  componente contradictoria: %» incrusta el JSON de issues en el mensaje
  (`…member_profiles.sql:507`), no en `details`, así que
  `productSpecServerIssues(e.details)` no los ve y el snackbar muestra el
  mensaje crudo (form :5407-5416). Y cuando sí llegan issues en `details`,
  `productSpecIssueMessage(issue, _specTemplate, _specValues)` rotula con la
  plantilla **raíz**, sin nombrar la pieza. Sólo se alcanza si la validación
  cliente y servidor divergen (p. ej. el residual C3 del writer que Root está
  cerrando). Mínimo: servidor con `using detail = issues::text` y un campo
  `scope`; cliente que rotule por scope contra la plantilla de esa ficha.
- **R2.** Tras adoptar el recibo, el editor reinicia `_generations` a `{}`
  (editor :77-93) y la clave del campo vuelve a `'${member.id}-0'`. Si la
  generación ya era 0, la clave no cambia y el `TextFormField` conserva el
  texto tecleado, no el valor del recibo. La raíz remonta a propósito con
  `_specDisplayGeneration++` (:4805). Sólo importa si el servidor normaliza
  (recorte, forma canónica del número); no lo probé. Mínimo: un contador base
  en el editor que suba en `didUpdateWidget` y se sume a la generación.
- **R3.** Montaje en teléfono/tablet dentro del `SingleChildScrollView` del
  formulario (S-06 en hoja, teclado, scroll-to-error de
  `GUI_MOBILE_DESIGN_PRINCIPLES.md`): los tests cubren 390/768/1280 sólo con el
  editor aislado.
- **R4.** Con un error de parseo de filas, el aviso repite el mismo texto por
  cada ficha (`rowsError` + `_bindingError` por borrador, editor :409-415,
  :431-436). Cosmético.
- **R5.** Cambiar el tipo a Servicio y volver deja `_specTemplate == null`
  (:3915-3925) y el editor dice «La ficha del producto cambió. Archiva…» hasta
  pulsar «Cargar ficha», que recupera los borradores (`??=`). Recuperable; el
  texto es engañoso durante ese tramo.

## Qué no toqué

Ningún archivo de implementación, test de Root, SQL ni documento global. Las
sondas viven en `.tmp/` (ignorado). Devuelvo la revisión; la propiedad de los
archivos vuelve a Root.

## Anexo · revisión del delta 209 → actual (ronda 211)

Sólo lectura de los tres archivos congelados: `product_form_page.dart`
`476a1565…`, `widgets/product_spec_member_editor.dart` `27bdb408…`,
`models/product_spec_member_draft.dart` `8716d9a2…` (hash leído aquí, igual al
declarado). No reaudité el resto; `member_profile.dart` sigue en `2920ac12…`.

**Ejecutado:** `test/widget/product_spec_member_editor_test.dart` +
`test/unit/product_spec_member_draft_test.dart` → **PASS** (36 en esos dos
archivos, 9 nuevos incluidos); `dart analyze` sobre los tres archivos → 0
errores/0 warnings (22 infos, preexistentes). Las cinco sondas de la ronda 209
invertidas a la conducta corregida → **5 PASS** (`.tmp/…/member_editor_review_probe_test.dart`).

**Veredicto: delta confirmado causalmente; sin bloqueo.**

| Ítem | Causa corregida (línea) | Evidencia |
|---|---|---|
| E1 | `identify` retorna sin tocar acción ni fuentes cuando identidad y MPN son los mismos (draft :156-158); exclusividad con mensajes propios y en el orden correcto: `rebind` valida identidad, luego no-op de misma fila, luego «Ya confirmaste…» (:181-193); `identify` tras `rebind` dice «Ya vinculaste otra fila…» sólo cuando hay algo que confirmar (:159-162) | Sonda P1: `binding_action` ausente tras confirmar sin cambio; vincular `r3` funciona; confirmar con MPN nuevo tras vincular da el mensaje exclusivo. Un `identify` sin cambio tras `rebind` es silencioso, que es lo correcto |
| E2 | Etiqueta por `templateId` conocido + `definition.id` presente en `factPayload` (editor :451-460); fallback explícito «Dato anterior sin etiqueta disponible»; fecha local con `MaterialLocalizations` (:462-467, :596) | Tests «archive history uses known field identity labels and date» y «…stays explicit»; sonda P2: 0 claves técnicas, 2 fechas |
| E3 | Editor captura `AuthorityScopeChangedException` en carga de familia y referencias, deshabilita todo (`_enabled`, :75) y avisa (:169-178); el padre `_invalidateSpecAuthority` limpia plantilla, borradores raíz y de miembros, referencias y fija `_specLoadError` (form :7819-7840); `_readMemberSpecs` compara `ErpAuthorityScopeKey` usuario+tenant retenida desde la lectura raíz (:1300-1304, :1367, :7797-7815); Guardar re-verifica y ahora explica por la compuerta en vez de callar (:4836-4844) | Tests «authority changes stop component reads…» y «…during reference reads disable editing»; sonda P3: «La sesión cambió…», crear deshabilitado. Un reintento de carga parte con `_specAuthority = null` y `previousMembers == null`, así que no retiene borradores de otra sesión/tenant |
| E4 | `_selectionContext`/`_rowLocation` añaden «<colección> · configuración N» y «pieza ya no incluida» (:425-448); `_title` añade «modelo sin confirmar» (:136-143) | Test «identical pieces expose separate positions…»; sonda P5: tres contextos distintos |
| G1 | Referencias filtradas por familia y `matchesIdentity` con el MPN actual; contexto «MPN: …» o «Referencia del modelo» (:275-284, :383-391) | Test «reference variants require the confirmed MPN…»; sonda P4: variante con otro MPN no ofrecida |
| R2 | `_generation` monotónico, sube en confirmar, referencia y reemplazo de `drafts` (:73, :92); clave raíz ahora incluye `_loadedSpecDraftKey` (form :7957-7959) | Test «receipt replaces the text field state even at generation zero» con `TextFormField` real |
| R4 | El aviso ya no repite el error de filas por cada ficha (:512-516) | Lectura |

Observaciones menores, sin acción exigida:

- `_knownTemplates` se llena en `build()` y no se vacía al reemplazar
  `drafts` (:79, :489-494). Como los ids de plantilla son estables y sólo se
  usan para rótulos, no produce cruce; si algún día una plantilla cambiara de
  id conservando el mismo, habría que vaciarlo en `didUpdateWidget`.
- `_generation` es global al editor: confirmar una pieza remonta los campos de
  la seleccionada; como sólo se dibuja una ficha a la vez, no pierde texto.

Siguen abiertos, como indica Root: R1 (errores SQL de miembros en el snackbar)
y R5 (cambio a Servicio y vuelta). G4 (`ExpansionTile`/`ListTile`) sigue siendo
decisión visual de Root; R3 (teléfono dentro del formulario) sigue sin probar.
