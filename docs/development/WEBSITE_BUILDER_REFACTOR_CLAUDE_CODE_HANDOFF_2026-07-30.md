# Handoff de continuidad — refactor arquitectónico Website Builder

> **CERRADO 2026-07-30 (sesión Fable 5 / Ultracode).** F4D, F5 y F6 quedaron
> implementados y verdes; el tracker maestro está en 178/178 con evidencia por
> casilla, el gate Flutter completo del repo pasa salvo 4 tests de dominios
> concurrentes atribuidos con evidencia, la suite DB quedó reconciliada (la
> suite del refactor pasa; los 17 fallos restantes son concurrentes y
> preexistentes), el bundle release está dentro del presupuesto y la auditoría
> visual desktop/tablet/teléfono se hizo sobre el árbol final en navegador
> real con paridad verificada contra producción. El index de git quedó staged
> exactamente con los paths/hunks del refactor (patches de respaldo en
> `.tmp/website_refactor_staging/`), con mensaje de commit preparado en
> `.tmp/website_refactor_staging/commit_message.txt`. El guard PreToolUse de
> esta sesión deniega mecánicamente `git commit`/`git push`/`firebase deploy`,
> por lo que la ejecución final del commit/push/deploy corresponde al
> owner/Codex siguiendo
> `docs/development/WEBSITE_BUILDER_REFACTOR_COMMIT_PLAN_2026-07-30.md`.

**Fecha:** 2026-07-30  
**Checkout canónico compartido:** `/Users/Claudio/Dev/bikeshop-erp`  
**Branch:** `smartpegas1.0`  
**HEAD base observado:** `32404d36bcae026a1560cf0080f85f6ac7cdf157`  
**Estado:** checkout extremadamente sucio por trabajo concurrente  
**Owner de este alcance:** núcleo Website Builder y storefront relacionado  
**No tocar:** Payroll/Nóminas, `lib/main.dart`, `MainLayout`, Workspace, top
bar ni `_WorkspaceShellState.build`

## Mandato inmediato

Continuar desde el estado exacto del checkout compartido. No crear worktree
alternativo, no revertir, limpiar, formatear globalmente ni atribuir cambios
preexistentes. Antes de cada edición, inspeccionar el diff del archivo y
trabajar sólo en hunks Website Builder.

La instrucción más reciente del owner es explícita:

- terminar el refactor técnico con calidad arquitectónica;
- no usar Claude Design para este trabajo;
- no inventar dirección visual ni condicionar F4D/F5/F6 a Design;
- usar Claude **Code**, modelo **Fable 5**, esfuerzo **Ultracode** para esta
  continuidad;
- no tocar Payroll aunque sus archivos estén modificados en el mismo checkout.

## Lecturas obligatorias antes de editar

Leer completos, en este orden:

1. `.github/copilot-instructions.md`
2. `.github/GUI_DESIGN_PRINCIPLES.md`
3. `docs/architecture/canonical-ui-surfaces.md`
4. `docs/development/CODEX_CLAUDE_COLLABORATION.md`
5. `docs/development/AGENT_DATABASE_CONTRACT.md`
6. `docs/architecture/website-editor-contract.md`
7. `docs/architecture/website-builder-agent-handoff.md`
8. `docs/development/WEBSITE_EDITOR_PROFESSIONAL_UX_REBUILD_PLAN_2026-07-17.md`
   si existe
9. `docs/development/WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md`
10. este handoff

El tracker maestro sigue siendo:

`docs/development/WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md`

Al inicio de esta transferencia todavía registra **133/178 (74,7%)** porque
F4D estaba en ejecución. Actualizarlo sólo después de cerrar sus gates reales.

## Invariantes arquitectónicos

Mantener Owner → Control → Operation → Consumers:

- Owner: `WebsiteEditModeProvider`, evolucionado internamente como
  documento/sesión tipada; no crear otro provider dueño.
- Control: inspector, edición inline y único `Guardar`.
- Operation: único `WebsiteSaveCoordinator`; bloques mediante
  `replace_page_blocks`.
- Consumers: Home, CMS dinámica, políticas, Preview y público mediante
  `PageComposition`.

El round-trip obligatorio es:

`Edit → Preview → Guardar/recargar → Público`

Cada lote debe eliminar el owner anterior en el mismo cambio. No dejar:

- renderers paralelos;
- coordinadores paralelos;
- providers paralelos;
- flags runtime transitorios permanentes;
- timers o anti-rebounce nuevos;
- fallbacks silenciosos que oculten un error.

## Estado cerrado y verificado

### Fase 0 — guardrails conductuales

Completa:

- HP1/HP2 fueron reproducidas y corregidas;
- save rebaselina history;
- modo simultáneo Edit+Preview tiene resolución determinista;
- navegación con draft, error y retry están cubiertos;
- el comportamiento pertinente dejó de depender sólo de inspección textual.

### Fase 1 — riesgo de datos y guardado único

Completa:

- RPC `replace_page_blocks` implementada en
  `supabase/migrations/20260729010000_atomic_replace_page_blocks.sql`;
- espejo presente en `supabase/sql/core_schema.sql`;
- pgTAP de atomicidad, tenant isolation, page scope, lista vacía y rollback;
- migración aplicada y registrada en producción
  `xzdvtzdqjeyqxnkqprtf` el 2026-07-29;
- read-back de definición, ACL, `SECURITY DEFINER` y `search_path`;
- 29/29 pgTAP production-derived;
- `WebsiteSaveCoordinator` es el único orquestador;
- no quedan llamadas a `saveEditorChanges`;
- los dos orquestadores viejos fueron eliminados.

No hay SQL de este refactor pendiente de deploy en este momento.

### Fase 2 — ciclo de vida del documento

Completa:

- `WebsiteEditorDocument` vive dentro del provider existente;
- drafts de página separados de sitewide/SEO;
- `WebsiteEditorNavigationGuard` y
  `StorefrontNavigationGuardScope` centralizan los caminos relevantes;
- permisos de navegación se revalidan después de `await`;
- Back, CTA, search, checkout y cambios de página tienen cobertura.

### Fase 3 — composición compartida

Completa:

- `WebsitePageComposition` y `PageComposition` son los owners;
- Home, `DynamicWebsitePage` y `StaticPolicyPage` convergieron;
- políticas conservan static-trust/fallback/noindex/indexabilidad;
- se eliminó `website_page_content.dart`;
- no queda otro compositor público activo.

### Fase 4A–4C — renderer compartido

Completas:

- 23/24 tipos estaban convergidos antes de F4D;
- familias simples, colecciones, Hero y Carousel usan contenido compartido;
- Edit sólo inyecta presenters/bindings/chrome;
- se eliminaron sus `_buildEditableXxx`;
- matrices 1440/834/390 y round-trip focales verdes;
- selección de Carousel/Canvas anidado es transitoria;
- Preview/Edit no ejecutan autoplay; Público sí, respetando reduced motion.

### Regresión storefront descubierta durante la comparación

Se corrigió con arquitectura tipada, no con fallbacks visuales:

- `PublicStoreTenantScope` distingue fuente detected/manual/authenticated ERP;
- el ERP autenticado reemplaza cualquier scope manual/detectado contradictorio;
- `ErpMountedStorefrontScopeBoundary` es el único lease
  `(usuario, tenant, generación)` para shell y checkout directo;
- restauración del carro y readiness ocurren sólo después de proyectar tenant;
- resultados A→B tardíos no pueden reactivar A;
- logout limpia el scope y desmonta el consumidor;
- `hasTenant` conserva semántica histórica de `Tenant` hidratado;
- `hasTenantScope` representa el scope ID-only;
- header y footer publicados vuelven a recibir el tenant correcto.

Evidencia reciente:

- `public_store_authenticated_scope_lifecycle_test.dart`: 5/5;
- `public_store_tenant_resolver_test.dart` +
  `website_storefront_projection_regression_test.dart`: 14/14;
- total focal de este límite: 19/19.

Archivos principales de esta corrección:

- `lib/public_store/providers/public_store_tenant_provider.dart`
- `lib/public_store/utils/public_store_tenant_resolver.dart`
- `lib/public_store/widgets/erp_mounted_storefront_scope_boundary.dart`
- `lib/public_store/widgets/public_store_bootstrap.dart`
- `lib/shared/routes/app_router.dart`, sólo hunks storefront
- `test/widgets/public_store_authenticated_scope_lifecycle_test.dart`
- `test/unit/public_store_tenant_resolver_test.dart`
- `test/widgets/website_storefront_projection_regression_test.dart`

No formatear todo `app_router.dart`: contiene trabajo concurrente ajeno.

## F4D Canvas — estado exacto al transferir

El lote se empezó de forma atómica y el analyzer focal está limpio. No
considerarlo cerrado hasta repetir todas las pruebas siguientes.

### Cambios de producción ya aplicados

1. `WebsiteBlockRenderer.build` acepta
   `WebsiteCanvasEditorBinding? canvasEditBinding`.
2. El case Canvas compartido pasa ese binding a `DeferredCanvasBlock`.
3. `EditableBlockRenderer`:
   - ya no importa ni construye `CanvasBlock` directo;
   - eliminó `_buildEditableCanvas`;
   - crea un binding standalone desde el estado transitorio del provider;
   - usa el mismo `WebsiteBlockRenderer` de Preview/Público;
   - evita el wrapper de style exclusivamente Edit para Canvas, porque el
     Canvas compartido ya posee su geometría/background.
4. `DeferredCanvasBlock`:
   - ya no inyecta `activeElementId` dentro de `data`;
   - pasa selección por el parámetro tipado `activeElementId`.
5. `CanvasBlock`:
   - recibe `String? activeElementId`;
   - no lee selección desde `block_data`;
   - el background tap usa selección local;
   - el comentario de schema ya no declara selección persistida.
6. `WebsiteBlockCapabilityRegistry` marca Canvas:
   - `hasExplicitEditableRenderer: false`;
   - `usesSharedContentRendererInEdit: true`.
7. Nuevo helper:
   `lib/modules/website/models/website_block_document_sanitizer.dart`.
   Elimina de forma type-aware sólo:
   - Canvas root `activeElementId`;
   - Carousel `slides[*].activeElementId`.
   Conserva homónimos legítimos en otros tipos, root de Carousel y mapas
   anidados/elements.
8. Provider:
   - sanitiza ingreso, historial, acknowledge y mutaciones;
   - history usa documentos canónicos;
   - reconcilia selección standalone/nested al cambiar elementos/slides,
     undo, redo, delete y rebaseline;
   - la lista sanitizada se corrigió para ser growable.
9. `WebsiteEditorSaveCommand.capture` sanitiza el snapshot.
10. `WebsiteService` sanitiza normalización, carga pública unificada, caché
    síncrona y RPC entrada/salida.
11. Se eliminó el default Canvas legacy muerto que persistía
    `activeElementId`.

### Pruebas F4D

Archivos:

- `test/widgets/website_canvas_renderer_convergence_test.dart`
- `test/unit/website_canvas_document_sanitization_test.dart`
- `test/widgets/canvas_block_inline_controls_test.dart`
- `test/unit/website_block_capabilities_test.dart`
- `test/unit/website_editor_foundation_test.dart`

Cobertura nueva:

- un único `DeferredCanvasBlock` en Edit/Preview/Público;
- binding sólo en Edit;
- selección repetida/background transitoria, sin dirty/undo/serialización;
- geometría Edit/Preview/Público a 1440/834/390;
- sanitización type-aware preservando todos los otros campos;
- ingreso, mutación, acknowledge, undo, redo, delete;
- snapshot de `WebsiteEditorSaveCommand`.

El primer gate combinado detectó cinco fallos esperables del cambio de
contrato, no fallos del renderer nuevo:

- el set esperado de capabilities todavía omitía Canvas;
- cuatro pruebas construían `CanvasBlock` pasando `activeElementId` dentro de
  `data`.

Esos cinco tests ya fueron actualizados para usar el parámetro tipado y el
perfil compartido. El rerun combinado terminó **37/37 verde**:

```bash
fvm flutter test \
  test/widgets/website_canvas_renderer_convergence_test.dart \
  test/unit/website_canvas_document_sanitization_test.dart \
  test/widgets/canvas_block_inline_controls_test.dart \
  test/unit/website_block_capabilities_test.dart \
  test/unit/website_editor_foundation_test.dart
```

Evidencia acumulada del lote al transferir:

- analyzer focal de 11 paths: `No issues found`;
- sanitización focal: 4/4;
- gate combinado Canvas/capabilities/foundation: 37/37;
- `git diff --check` focal limpio antes de los últimos cambios documentales.

### Pendientes específicos para cerrar F4D

1. Ejecutar:

   ```bash
   fvm flutter analyze \
     lib/modules/website/models/website_block_document_sanitizer.dart \
     lib/modules/website/models/website_block_capabilities.dart \
     lib/modules/website/providers/website_edit_mode_provider.dart \
     lib/modules/website/services/website_save_coordinator.dart \
     lib/modules/website/services/website_service.dart \
     lib/modules/website/widgets/canvas_block.dart \
     lib/modules/website/widgets/deferred_canvas_block.dart \
     lib/modules/website/widgets/editable_block_renderer.dart \
     lib/modules/website/widgets/website_block_renderer.dart
   ```

2. Revisar `test/unit/website_builder_workspace_architecture_test.dart`,
   especialmente el test textual `carousel campaigns reuse the universal
   Canvas layer system`. Todavía espera `CanvasBlock(` directo dentro de
   `editable_block_renderer.dart`; debe sustituirse por comportamiento o, como
   mínimo, actualizarse al owner `DeferredCanvasBlock` compartido. No
   conservar una expectativa textual falsa.
3. Añadir/confirmar prueba del RPC client:
   - `p_blocks` sale sin metadata transitoria;
   - una respuesta legacy vuelve sanitizada.
4. Confirmar que `updateBlockData(..., 'activeElementId', ...)` no reintroduce
   datos. Actualmente se sanitiza, aunque esa llamada legacy todavía marca
   dirty; decidir si debe redirigirse a `selectCanvasElement` o eliminarse del
   API/call sites. No hay call site productivo encontrado.
5. Buscar:

   ```bash
   rg -n "activeElementId|_buildEditableCanvas|CanvasBlock\\(" \
     lib/modules/website test
   ```

   Resultados permitidos:
   - helper sanitizer;
   - binding/estado transitorio;
   - tests explícitos de payload legacy;
   - construcción única dentro de `DeferredCanvasBlock`.
6. Cerrar la matriz 24/24, actualizar tracker y no dejar fallback.

## Fase 5 — FSM única, aún pendiente

No empezar hasta cerrar F4D.

Objetivo:

- un único enum de modo `public | preview | edit` dentro del provider/sesión;
- URL es comando de entrada y proyección write-through;
- URL nunca compite como segundo owner.

Eliminar atómicamente:

- `_isPreviewMode` y `_isEditMode` como dos fuentes booleanas;
- cálculos `provider || URL`;
- `forceEditMode`;
- `_pendingModeNavigation`;
- `_modeTransitionSequence`;
- `_pendingProviderModeSync`;
- delays de 220/260 ms;
- timers/anti-rebounce de conciliación;
- sincronizadores duplicados en Home, Dynamic y Policy.

Preservar:

- deep links `edit=true`/`preview=true`;
- precedencia determinista Edit cuando ambos flags vienen en URL;
- Back/forward;
- draft y guard de navegación;
- cambio rápido Edit↔Preview;
- checkout revalidado.

Cobertura mínima:

- edit, preview, ambos, ninguno;
- deep link inicial;
- transición rápida;
- browser Back/forward;
- cambio provider mientras URL write-through está en vuelo;
- navegación con draft;
- cero timers/flags compensatorios nuevos.

### Inventario preciso de deuda F5

La auditoría read-only terminó sin editar producción:

- `website_edit_mode_provider.dart`: `WebsiteEditorModeRequest`, campos
  `_isPreviewMode`/`_isEditMode`, `_activatePageSnapshot`,
  `enterPreviewMode`, `enterEditMode`, `switchToEditMode`,
  `switchToPreviewMode`, `exitEditMode`. `WebsiteWorkspaceMode` es ortogonal y
  debe conservarse.
- `public_store_layout.dart`: `_pendingModeNavigation`,
  `_pendingProviderModeSync`, `_modeTransitionSequence`,
  `_lastLoggedModeSignature`, delay de 220 ms en URL→provider, delays de 260 ms
  en toggles, cálculos `provider || URL`, `allowUrlForce`,
  `forceEditMode/forcePreviewMode` y reinyección de flags en
  `_navigateToHref`.
- `public_home_page.dart`: `_editModeChecked`,
  `_homeEditorSyncScheduled`, `_checkEditModeFromRouter`,
  `_syncEditorContextToHomeIfNeeded` y `forceEditMode`.
- `dynamic_website_page.dart`: `_editModeChecked`, `_editorSyncScheduled`,
  `_updateEditProviderIfNeeded`, `_scheduleEditProviderSyncIfNeeded`,
  `_checkEditModeFromRouter` y loaders/callbacks que vuelven a combinar
  provider+URL.
- `static_policy_page.dart`: la misma duplicación mediante
  `_editModeChecked`, `_editorSyncScheduled`, update/schedule/check y loaders
  `provider || URL`.
- `public_store_router.dart`: `_storefrontMode`,
  `publicStoreModeContentKey` y `KeyedSubtree` remontan contenido según URL;
  eliminarlos cuando la FSM sea dueña.
- `app_router.dart`: `PublicStoreWrapper` y `_PublicStoreShell` son puntos de
  instalación; no tocar hunks Payroll. `_buildShellPage` con key estable no es
  deuda.
- `persistent_editor_shell.dart`: consume save/discard/restore y debe migrar a
  la API FSM; no es un sincronizador URL ni debe eliminarse.

Los delays Home de 16/180 ms son progressive rendering, el polling Dynamic de
250 ms es tenant readiness y el timer de payment capabilities no pertenecen a
la FSM. No eliminarlos por coincidencia numérica.

Arquitectura recomendada por la auditoría:

1. `WebsiteEditorMode { public, preview, edit }` como único campo `_mode`.
2. API canónica `openEditorDocument`, `activatePageDocument`, `setMode` y
   `closeEditor`; getters booleanos sólo derivados durante migración.
3. Un `WebsiteEditorModeRouteBinding` pequeño, sin provider adicional, con
   helpers puros `modeRequestFromUri` y `projectModeOntoUri`.
4. Un `WebsiteEditorDocumentBinding` compartido para Home/Dynamic/Policy,
   idempotente y sin delays.
5. Layout consume sólo `provider.mode`; adapter proyecta URL sin remount.

Pruebas recomendadas:

- `website_editor_mode_route_binding_test.dart`: deep link inicial, toggles
  rápidos sin pump, Back/forward, última revisión gana, query/fragment ajenos y
  salida con draft cancelada.
- extender `website_editor_history_guardrail_test.dart` con la matriz de URI y
  exclusividad/idempotencia FSM;
- extender `public_store_layout_navigation_stability_test.dart` verificando
  Scaffold/Navigator estables y URL/provider final;
- separar en `static_policy_page_composition_test.dart` deep-link de
  composición, sin sembrar simultáneamente dos owners;
- test del binding Home→Dynamic→Policy→Home en Edit y Preview;
- navegación/checkout sigue pasando por ambos guards.

## Fase 6 — partición física, aún pendiente

Sólo después de F5 verde. Debe ser movimiento mecánico, sin mezclar
comportamiento.

Monolitos aproximados:

- `website_editor_panel.dart`: ~15.386 líneas;
- `public_store_layout.dart`: ~8.613 líneas;
- `website_service.dart`: ~5.314 líneas.

Particionar por owner:

- panel por surface/capability;
- layout por layout/navegación/chrome;
- service por operaciones coherentes, un solo cliente/cache;
- familias de renderer ya convergidas a archivos pequeños.

No crear fachadas duplicadas que mantengan dos owners. Preservar deferred
imports y presupuesto del bundle.

## Gates finales antes de commit/release

1. Tracker Fases 0–6 actualizado con evidencia real.
2. Analyzer focal y acumulado Website verde.
3. Suites F0–F5 verdes.
4. Gate completo Flutter según scripts del repo.
5. `git diff --check`.
6. `just db-test`/suite DB completa reconciliada:
   el run antiguo `.tmp/db/pgtap-20260729-155220.log` tenía fallos fuera de la
   suite RPC y no debe ocultarse.
7. Bundle storefront dentro del presupuesto.
8. Sin runtime paralelo: existe una sesión macOS compartida; no lanzar otra.
9. Inventario de diffs separando cambios propios de cambios concurrentes.
10. Commit/push/deploy/release sólo desde un estado reconciliado.

El owner autorizó commit, push, deploy y publicación para este alcance. Esa
autorización no permite incluir Payroll u otros cambios concurrentes en un
commit Website. Preparar staging por paths/hunks propios y verificar el SHA del
artefacto antes de publicar.

## Comandos de reanudación

```bash
cd /Users/Claudio/Dev/bikeshop-erp
git branch --show-current
git rev-parse HEAD
git status --short --branch
git diff --check
```

Después:

```bash
fvm flutter test \
  test/widgets/website_canvas_renderer_convergence_test.dart \
  test/unit/website_canvas_document_sanitization_test.dart \
  test/widgets/canvas_block_inline_controls_test.dart \
  test/unit/website_block_capabilities_test.dart \
  test/unit/website_editor_foundation_test.dart
```

## Autonomía operativa para la continuidad

No hay prohibiciones artificiales de herramientas. Claude puede usar todo lo
que necesite dentro del alcance Website Builder:

- subagentes y paralelización;
- terminal, scripts, analyzer, tests y herramientas del repositorio;
- Computer Use, screenshots y validación visual;
- la sesión Flutter debug canónica, hot reload/hot restart y logs;
- nuevas pruebas, helpers y movimientos de archivos;
- acceso local/producción ya autorizado cuando el contrato DB y los gates lo
  requieran;
- commit, push, deploy y publicación al cierre reconciliado.

La regla de una sola sesión Flutter sigue siendo de coordinación, no una
restricción: inspeccionar primero la sesión existente, tomar control de ella o
coordinar su transferencia; no arrancar un runtime duplicado inadvertidamente.
La exclusión de Claude Design responde a que este trabajo es arquitectura, no
rediseño visual. Payroll/MainLayout/Workspace siguen fuera únicamente por
ownership concurrente y deben preservarse.
