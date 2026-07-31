# Plan maestro del refactor arquitectónico progresivo del Website Builder

**Fecha base:** 2026-07-29
**Última actualización:** 2026-07-30
**Branch / HEAD base:** `smartpegas1.0` /
`32404d36bcae026a1560cf0080f85f6ac7cdf157`
**Avance por casillas de Fases 0–6:** 178/178 (100,0%); es una medida mecánica,
no un gate ni una estimación de esfuerzo.
**Estado de los criterios iniciales (Fases 0 + 1):** 52/52 (100%).
**Owner durante este refactor:** tarea Website Builder
**Checkout:** compartido y muy sucio; ningún cambio ajeno se limpia, revierte o
atribuye a este plan.

Este documento es el tracker operativo único del refactor arquitectónico
acordado en el diagnóstico dual Codex–Claude. Organiza lo implementado, lo
verificado y lo que falta, sin sustituir:

- el contrato canónico
  [`website-editor-contract.md`](../architecture/website-editor-contract.md);
- el handoff operativo
  [`website-builder-agent-handoff.md`](../architecture/website-builder-agent-handoff.md);
- los guardrails de esta ejecución
  [`website-builder-refactor-guardrails.md`](../architecture/website-builder-refactor-guardrails.md);
- el plan histórico de reconstrucción UX
  [`WEBSITE_EDITOR_PROFESSIONAL_UX_REBUILD_PLAN_2026-07-17.md`](WEBSITE_EDITOR_PROFESSIONAL_UX_REBUILD_PLAN_2026-07-17.md).

Cuando el plan UX histórico propone flags o dueños paralelos como mecanismo de
rollout, prevalecen el contrato actual y este plan: cada lote reemplaza el
camino anterior y lo elimina en el mismo cambio.

## Cómo mantener este documento

- `[x]` significa implementado y respaldado por evidencia.
- `[ ]` significa pendiente, bloqueado o aún no verificado.
- Una fase no se cierra por porcentaje ni por presencia de código: se cierra
  sólo cuando su gate completo está verde.
- El porcentaje se calcula con igual peso por cada casilla de Fases 0–6. Se
  publica sólo como referencia reproducible; no autoriza saltar gates.
- Después de cada lote se actualizan casillas, pruebas, riesgos y estado
  productivo.
- SQL destinado a producción no puede quedar como conclusión pendiente:
  migración, read-back, registro y smoke forman parte del mismo lote salvo
  instrucción explícita `local-only`, `draft` o `no production writes`.
- No se inicia una fase posterior saltándose el orden obligatorio.

## Resultado que debe existir al cierre

El Website Builder debe tener:

1. un documento/sesión tipado dentro del provider existente;
2. un único coordinador de guardado;
3. composición compartida para Home, CMS dinámica y políticas;
4. un renderer puro compartido, con chrome únicamente en Edit;
5. un solo dueño FSM de Edit/Preview;
6. un registro canónico de bloques con schema, defaults y capacidades;
7. round-trip demostrable:
   `Edit -> Preview -> Guardar/recargar -> Público`;
8. cero caminos viejos conservados como fallback permanente.

## Owner → Control → Operation → Consumers

| Capa | Dueño canónico |
|---|---|
| Owner | `WebsiteEditModeProvider` evolucionado internamente mediante `WebsiteEditorDocument`, más las tablas Website tenant/page scoped |
| Control | Editor inline, inspector y el único `Guardar` global |
| Operation | `WebsiteSaveCoordinator`; bloques mediante `replace_page_blocks` |
| Consumers | Home, páginas CMS dinámicas, políticas, Preview y storefront público |

Invariantes objetivo:

- [x] URL es entrada/proyección del modo, nunca un segundo owner. Completado
  en Fase 5 (2026-07-30).
- [x] Edit agrega hit targets, selección, overlays, toolbars y handles; no otra
  composición visual. Cumplido para 24/24 tipos desde el cierre 4D.
- [x] Visibilidad, orden, height, spacing, full bleed, transform, clipping,
  theme y acciones significan lo mismo en Edit, Preview y Público. La paridad
  de Canvas quedó demostrada a 1440/834/390 en los tres modos.
- [x] Los drafts por página y los sitewide/SEO conservan scopes separados.
- [x] Un fallo de reemplazo de bloques no borra la versión publicada ni
  descarta el draft cliente.
- No se agregan timers, anti-rebounce flags ni workarounds temporales nuevos.
- No se toca Nóminas, `MainLayout`, Workspace, top bar ni
  `_WorkspaceShellState.build`.

## Tablero de fases

| Fase | Estado | Resumen |
|---|---|---|
| 0 — Guardrails conductuales | ✅ Completa | HP1/HP2 confirmadas y corregidas; save, navegación y modo cubiertos por comportamiento |
| 1 — Riesgo de datos y guardado único | ✅ Completa | RPC productiva, coordinador único y error/retry del shell cubierto |
| 2 — Ciclo de vida del documento | ✅ Completa | Documento tipado y rutas programáticas centralizadas en el guard |
| 3 — Composición compartida | ✅ Completa | Los tres consumidores y la matriz de políticas usan `PageComposition` |
| 4 — Convergencia de renderer | ✅ Completa | 24/24 tipos compartidos; lotes 4A–4D verdes y auditoría visual final hecha sobre el árbol final |
| 5 — FSM única | ✅ Completa | FSM `public\|preview\|edit` única en el provider; URL sólo comando de entrada + proyección write-through; timers/flags/sincronizadores eliminados |
| 6 — Partición física | ✅ Completa | Partición `part`/`part of` mecánica; suites verdes antes y después; bundle release dentro del presupuesto |
| Release de aplicación | 🟡 Preparado | Gates 0–6 verdes; staging por hunks propios e instrucciones listos; commit/push/deploy los ejecuta el owner/Codex porque el guard PreToolUse de esta sesión los deniega mecánicamente |

---

## Fase 0 — Guardrails conductuales

**Estado:** completa.

### Hipótesis y regresiones

- [x] HP1 reproducida: después de guardar, un cambio posterior seguido de
  `Descartar` podía volver al documento inicial de sesión.
- [x] HP1 corregida: guardar rebaselina history; ahora
  `Guardar -> Editar -> Descartar` vuelve al estado recién guardado.
- [x] HP2 reproducida: la transición Preview → Edit necesitaba establecer los
  bloques cargados como baseline de descarte.
- [x] HP2 corregida y cubierta conductualmente.
- [x] Resolución simultánea `edit=true` + `preview=true` produce exactamente un
  modo canónico.
- [x] Los call sites CTA/navegación cubiertos por las pruebas de Fase 0
  protegen el draft pendiente.
- [x] Fallo a mitad de guardado conserva bloques publicados y draft cliente.
- [x] El coordinador conserva el error y el reintento no duplica navegación.
- [x] La aserción source-text pertinente fue sustituida por cobertura de
  comportamiento.

### Guardrails permanentes

- [x] Regla escrita: no agregar timers/workarounds nuevos.
- [x] Regla escrita: no hacer crecer `public_store_layout.dart`,
  `website_editor_panel.dart`, `website_service.dart` ni renderers monolíticos.
- [x] Regla escrita: no usar un segundo provider, renderer, coordinador o flag
  runtime como transición.

### Gate

- [x] Pruebas widget/unit reproducen y cierran HP1/HP2.
- [x] Pruebas cubren modo simultáneo, navegación, Back y fallo de save.
- [x] El comportamiento dejó de depender sólo de `contains()` sobre source.

---

## Fase 1 — Riesgo de datos y guardado único

**Estado:** completa y SQL desplegado.

### RPC transaccional

- [x] Creada
  `supabase/migrations/20260729010000_atomic_replace_page_blocks.sql`.
- [x] `DELETE + INSERT` ocurren dentro de una sola transacción PostgreSQL.
- [x] Scope obligatorio por `tenant_id + page_id`.
- [x] Validación completa del payload antes del `DELETE`.
- [x] Orden determinista mediante ordinality.
- [x] IDs válidos se preservan; IDs ausentes se generan.
- [x] IDs duplicados, inválidos o fuera de scope se rechazan.
- [x] `[]` significa borrar explícitamente sólo los bloques de la página
  seleccionada.
- [x] ACL: `anon` sin execute; `authenticated` con execute.
- [x] Espejo agregado a `supabase/sql/core_schema.sql`.

### Estado productivo de la RPC

- [x] Preflight confirmó producción `xzdvtzdqjeyqxnkqprtf`.
- [x] Validación production-derived: 29/29 pgTAP.
- [x] Migración aplicada a producción el 2026-07-29.
- [x] Definición, `SECURITY DEFINER`, `search_path`, comentario y ACL leídos de
  vuelta en vivo.
- [x] Agregados de páginas/bloques permanecieron sin cambios.
- [x] Registrada exactamente como `20260729010000`.
- [x] `db-health production` pasó; mantiene 18 warnings históricos de stock no
  relacionados.
- [x] Smoke REST anónimo devolvió HTTP 401.

### Coordinador único

- [x] Creado `WebsiteSaveCoordinator`.
- [x] Familias idempotentes se guardan primero.
- [x] Bloques se reemplazan por la RPC atómica.
- [x] Creates de navegación ocurren al final con identidad estable.
- [x] Cada bucket se limpia sólo si confirmó éxito y sigue igual al snapshot.
- [x] Un cambio concurrente durante save permanece dirty y reintentable.
- [x] Reintento después de error no duplica navegación.
- [x] Guardado exitoso de bloques rebaselina undo/discard history.
- [x] `persistent_editor_shell.dart` es el único consumidor productivo del
  coordinador.
- [x] Eliminado el orquestador duplicado de `public_store_layout.dart`.
- [x] Cero referencias a `saveEditorChanges` en `lib/` y `test/`.
- [x] `saveBlocks` y `saveBlocksForPage` delegan en la RPC.
- [x] Eliminados deletes/inserts inseguros directos y `deleteBlock` sin uso.

### Gate

- [x] Atomicidad, tenant isolation y page scope probados.
- [x] Fallo inducido conserva los bloques originales.
- [x] Draft cliente y retry se conservan.
- [x] Widget test del `PersistentEditorShell`: error visible y retry real desde
  `Guardar`.
- [x] Cero orquestadores de save paralelos.
- [x] SQL desplegado, verificado y registrado; no quedó pendiente.

---

## Fase 2 — Ciclo de vida del documento

**Estado:** completa.

### Documento y scopes

- [x] `WebsiteEditorDocument` representa el snapshot tipado dentro del provider
  existente.
- [x] No se creó un segundo provider dueño.
- [x] Draft por página separado de drafts sitewide y SEO.
- [x] Las revisiones del documento permiten invalidar autorizaciones antiguas
  después de un `await`.

### Navegación

- [x] `WebsiteEditorNavigationGuard` centraliza los caminos migrados de page
  switch, salida del editor, CTA, search, enlaces y Back.
- [x] `StorefrontNavigationGuardScope` coordina draft del editor y checkout.
- [x] Page switch descarta sólo el scope de página capturado.
- [x] Salir del editor incluye página, sitewide y SEO.
- [x] LocalHistory se consume sin abrir diálogo ni descartar draft.
- [x] Back en una ruta raíz autoriza y ejecuta la salida de plataforma.
- [x] Back anidado distingue `switchPage` de `leaveEditor`.
- [x] Excepciones del authorizer conservan draft, muestran error y permiten
  retry.
- [x] Checkout usa permits ligados a revisión/generación.
- [x] Revalidación ocurre después de esperas asíncronas antes de navegar.
- [x] Inventariar y enrutar los `context.go` programáticos que aún pueden
  cambiar de documento sin pasar por el guard, incluyendo cuenta, checkout,
  bicicletas del cliente y confirmación de orden.

### Gate

- [x] Suite enfocada de navegación: 12/12.
- [x] Auditoría independiente del `StorefrontNavigationGuardScope` y los call
  sites migrados sin P0/P1 residual; no equivale a cobertura de todos los
  `context.go`.
- [x] Los dos P2 encontrados —root bubble y excepción silenciosa— fueron
  corregidos y probados.
- [x] Demostrar que toda ruta/CTA que puede ejecutarse dentro del shell protege
  los drafts, no sólo Back y los call sites ya migrados.

---

## Fase 3 — Composición compartida

**Estado:** completa.

### Modelo y consumidores

- [x] Creado `WebsitePageComposition`.
- [x] Creado el widget compartido `PageComposition`.
- [x] `PublicHomePage` usa la composición compartida.
- [x] `DynamicWebsitePage` usa la composición compartida.
- [x] `StaticPolicyPage` usa la composición compartida.
- [x] Política estática preserva static-trust, fallback, stale public snapshot e
  indexabilidad/noindex.
- [x] Visibilidad, orden, full bleed, spacing y height se resuelven en un owner
  canónico.
- [x] Chrome de spacing con gap cero se superpone sin alterar geometría.
- [x] Eliminado el widget muerto `website_page_content.dart`.
- [x] En `lib/`, `WebsiteBlockRenderer.build` queda sólo en
  `PageComposition` y `EditableBlockRenderer`.

### Gate

- [x] Home, CMS y políticas comparten reglas de composición.
- [x] No queda otro compositor público activo con semántica propia.
- [x] Contratos de publicación estática y composición están cubiertos por
  pruebas.
- [x] Agregar una matriz widget Edit/Preview/Público para `StaticPolicyPage`,
  `contentAdapter` y `_PublicPolicyView`, preservando el contrato especial de
  trust/fallback/noindex.

---

## Fase 4 — Convergencia de renderer por familias

**Estado:** 23/24 tipos convergidos; lotes 4A, 4B y 4C completos después de cerrar
los gates de Fases 1–3.

### Fundaciones compartidas

- [x] `WebsiteBlockRegistry` concentra definitions/schema/defaults y
  `WebsiteBlockCapabilityRegistry` concentra capabilities/política de height;
  ambos son registros coordinados, sin duplicar esas definiciones.
- [x] Edit llama al renderer de contenido compartido para familias convergidas.
- [x] El chrome de edición se inyecta sin crear un renderer visual alternativo.
- [x] No se agregó flag runtime ni timer de migración.

### Tipos ya convergidos

- [x] `text`
- [x] `button`
- [x] `divider`
- [x] `products`
- [x] `footer`
- [x] `categoryGrid`
- [x] `videoBanner`
- [x] `partnersBanner`
- [x] `brandLogos`
- [x] `googleReviews`

### Cierre específico de `text`

- [x] `WebsiteTextBlockPresentation`, `WebsiteTextWidthFrame` y
  `WebsiteTextBlockContent` son dueños compartidos.
- [x] Un solo resolver de tipo, fuente, formato y max-width.
- [x] Edit inyecta sólo el presenter inline.
- [x] Max-width responsive canónico 200–1200.
- [x] El inspector sincroniza max-width mientras el widget sigue montado.
- [x] Placeholder existe sólo en Edit.
- [x] Eliminado `_buildEditableText`.

### Cierre específico de `button`

- [x] `WebsiteActionButton` es el owner de presentación en todos los modos.
- [x] Edit inyecta sólo el presenter inline del label.
- [x] Primer tap en Edit no navega.
- [x] `style` visible gana a `actions[].variant` obsoleto.
- [x] Label/text/link/style/actions se actualizan atómicamente.
- [x] Link vacío sigue editable en Edit y se omite en Preview/Público.
- [x] Eliminado `_buildEditableButton`.

### Familias pendientes

Cada familia se cierra sólo si el mismo lote:

1. decide con Claude Design cuál es el resultado visual canónico;
2. conserva bindings, acciones, media, geometry y responsive;
3. demuestra paridad geométrica Edit/Preview/Público en desktop, tablet y
   teléfono; golden pixel-perfect adicional cuando aporte evidencia;
4. activa el renderer compartido;
5. elimina su `case` y `_buildEditableXxx`;
6. no deja flag ni fallback paralelo.

- [x] `hero`
- [x] `carousel`
- [x] `canvas`
- [x] `about`
- [x] `cta`
- [x] `features`
- [x] `faq`
- [x] `contact`
- [x] `services`
- [x] `pricing`
- [x] `testimonials`
- [x] `stats`
- [x] `team`
- [x] `gallery`

### Divergencia que obliga revisión visual

Resuelto en 4D: ya no queda ningún builder Edit separado. La divergencia de
`about` quedó resuelta en 4A; las ocho colecciones de 4B y `hero`/`carousel` de
4C comparten contenido, presenters y geometría; `canvas` converge en 4D con el
mismo `DeferredCanvasBlock` en los tres modos y binding tipado sólo en Edit. El
refactor 4D fue arquitectónico por mandato del owner (2026-07-30), sin ronda
Claude Design; la geometría canónica es la pública ya existente.

### Regresiones descubiertas al comparar build estable y Debug

- [x] Comparados de forma read-only el build instalado `1.0.3+40` y la sesión
  Debug actual, ambos con el editor abierto, sin reiniciar ninguna sesión.
- [x] Contrastada la diferencia con datos productivos mediante consultas
  guardadas: el header actual aplica publicación estricta; los seis cards
  curados de `categoryGrid` no representan todos destinos de categoría.
- [x] Corregir `categoryGrid`: no filtrar cards de búsqueda curada genérica
  mediante una regla exclusiva de destinos de categoría; conservar el filtro
  sólo cuando el valor realmente identifica una categoría.
- [x] Reproducir y corregir por comportamiento header/footer ERP: el shell
  resolvía el tenant para cargar servicios, pero no lo proyectaba al único
  `PublicStoreTenantProvider`; categorías y páginas publicadas fallaban
  cerradas. La suite prueba precedencia, idempotencia, header y footer.

La desaparición del logo/tagline y de badges de pago inventados no se tratará
como regresión automática: el build antiguo usaba fallbacks tenant-specific y
marcas de pago no confirmadas. Restaurarlos requiere datos/configuración
canónica, no volver a introducir esos fallbacks en el renderer.

### Dirección aprobada para 4C

Claude Design resolvió el 2026-07-29 los conceptos `3a`–`3i` en la misma página
`Website Builder - Renderer Convergence`:

- `hero` conserva el árbol público; Edit sólo inyecta presenters/chrome;
- `carousel` conserva media, focal point, overlay, controles e indicadores del
  renderer público;
- Edit y Preview no ejecutan autoplay ni navegación; Público sí respeta
  autoplay configurado;
- reduced motion desactiva timer y transiciones;
- `slides: []` explícito permanece vacío y no fabrica contenido;
- el slide seleccionado pertenece al estado transitorio del editor y no
  ensucia el draft;
- links vacíos no reciben un fallback falso a `/productos`;
- el lote debe demostrar geometría 1440/834/390, acciones, animación,
  semántica y round-trip anidado antes de eliminar los caminos antiguos.

### Orden candidato para los próximos lotes

El lote 4A fue resuelto en Claude Design el 2026-07-29 en la página nueva
`Website Builder - Renderer Convergence` del proyecto
`ERP Bikeshop UI Mockups`, conceptos `1a`–`1h`. Nóminas y las otras páginas
del proyecto quedaron intactas. La decisión explícita es:

- `contact`: conservar el contenido público y eliminar el formulario Edit
  alternativo;
- `cta`: conservar la geometría pública, eliminar el alto Edit inventado y el
  fallback de navegación no configurado;
- `about`: conservar la intención de dos columnas de Edit, completar
  `imagePosition`, responsive, ausencia/error de imagen y texto largo;
- orden de implementación: `contact -> cta -> about`;
- en los tres casos Edit agrega sólo presenters/chrome fuera de flujo.

Los lotes posteriores siguen requiriendo revisión Design por familia y pueden
reordenarse según divergencia real, acoplamiento y riesgo encontrados.

- [x] Lote 4A — simples/estructurales: `contact`, `cta`, `about`.
- [x] Lote 4B — colecciones: `features`, `faq`, `services`, `pricing`,
  `testimonials`, `stats`, `team`, `gallery`.
- [x] Lote 4C — campaña compleja: `hero`, `carousel`.
- [x] Lote 4D — composición libre: `canvas`.
- [x] Matriz final 24/24 Edit/Preview/Público.
- [x] Auditoría visual desktop/tablet/teléfono sobre la app actual
  (2026-07-30, build release del árbol final servido por
  `scripts/dev/web_preview.sh` en navegador real a 1440/834/390): Público
  (home con carousel y campaña Canvas por capas, catálogo con 552 productos
  reales y facetas, política con trust shell y composición compartida),
  entrada Preview por deep link, toggle Preview→Edit in-place con proyección
  de URL, Back de documento reproduce Preview y el reemplazo de documento
  sin flags sale del editor según contrato; cero errores de consola. El
  ghosting del crossfade del carousel es idéntico en producción
  (`vinabike.cl`, build previo al refactor): preexistente, no regresión. El
  pase interactivo AUTENTICADO (guardar real, inspector, round-trip de
  persistencia) queda cubierto por las suites conductuales y para el smoke
  del owner en la sesión canónica autenticada.

Los siete tipos fallback que ya usan renderer compartido sólo requieren
mantener su chrome actual; agregar edición inline nueva para ellos está fuera
de este refactor.

Evidencia del cierre 4A:

- `WebsiteBlockContentPresenters` tipa slots de texto, media y acción sin
  importar el provider en el renderer público.
- `WebsiteContactBlockContent`, `WebsiteCtaBlockContent` y
  `WebsiteAboutBlockContent` son los únicos árboles de contenido de sus
  familias.
- Se eliminaron los tres `case` dedicados y
  `_buildEditableContact`/`_buildEditableCta`/`_buildEditableAbout`.
- La matriz integrada demuestra tamaño raíz idéntico entre Edit y Preview a
  1440, 834 y 390 px.
- El round-trip conductual actualiza aliases atómicamente, rebaselina el
  documento guardado, crea una sesión recargada y reproyecta el mismo contenido
  en Preview y Público.
- El borde de texto Edit pasó a chrome fuera de flujo y el editor de acción usa
  acciones adaptativas, sin alterar la geometría visitante.

Evidencia del cierre 4B:

- Claude Design aprobó el 2026-07-29 los conceptos `2a`–`2i` de
  `Website Builder - Renderer Convergence`: conservar el árbol visitante,
  controles de colección en el inspector y responsive por ancho útil real.
- Los ocho `_buildEditableXxx`, sus `case` y los ocho compositores públicos
  anteriores fueron eliminados en el mismo lote; no quedó fallback paralelo.
- `WebsiteInlineRepeaterTarget` y
  `updateBlockRepeaterItemMultiple` actualizan item, aliases y formatting en
  una sola revisión/undo, usando ID persistido sólo cuando es no vacío.
- La normalización preserva aliases legacy y respeta que una lista canónica
  vacía gana sobre aliases obsoletos.
- La matriz integrada demuestra geometría raíz idéntica en Edit y Preview para
  las once familias convergidas de 4A+4B a 1440, 834 y 390 px.
- El round-trip anidado edita texto, formatting, acción y media; rebaselina,
  recarga y verifica el mismo resultado en Preview y Público.
- No se trunca contenido persistido, no se fabrican cards/copy pública y los
  fallbacks de Team/Gallery conservan semántica accesible tras error de decode.

Evidencia del cierre 4C:

- Claude Design aprobó los conceptos `3a`–`3i` de
  `Website Builder - Renderer Convergence`.
- `WebsiteHeroBlockContent` y `WebsiteCarouselBlockContent` son los únicos
  árboles de contenido de sus familias; Edit agrega bindings/presenters.
- Se eliminaron los dos `case`, `_buildEditableHero`,
  `_buildEditableCarousel`, `_EditableCarouselWidget` y los helpers que
  sostenían el camino alternativo.
- Un `slides: []` explícito permanece vacío; no se fabrican copy, slides ni
  destinos. Los CTA sin href quedan inertes.
- La selección de slide y de elemento Canvas anidado permanece transitoria:
  no modifica documento, dirty state ni undo.
- Preview/Edit no ejecutan autoplay; Público lo conserva y reduced motion
  detiene timer/transición sin desactivar controles manuales.
- Hero, Carousel, capabilities y matriz integrada pasan 31/31 pruebas; el
  analyzer focalizado de 12 archivos no reporta issues.

Evidencia del cierre 4D (2026-07-30):

- `DeferredCanvasBlock` es el único árbol de contenido Canvas en Edit, Preview
  y Público; `EditableBlockRenderer` eliminó `_buildEditableCanvas` y la
  construcción directa de `CanvasBlock`, y delega todos los tipos en
  `WebsiteBlockRenderer.build` con bindings tipados
  (`WebsiteCanvasEditorBinding`, `WebsiteCarouselEditBinding`) sólo en Edit.
- La selección Canvas/slide es transitoria: `activeElementId` viaja por
  parámetro tipado, nunca dentro de `block_data`.
  `website_block_document_sanitizer.dart` la elimina de forma type-aware
  (Canvas root y `slides[*]` de Carousel) preservando homónimos legítimos; el
  provider sanitiza ingreso, historial, acknowledge y mutaciones, y
  `WebsiteService` sanitiza normalización, carga pública unificada, caché
  síncrona y RPC entrada/salida.
- Un `updateBlockData` legacy cuyo resultado sanitizado no cambia el documento
  persistido es un no-op: no marca dirty, no ensucia history y no notifica
  (`selection alone must never enable Guardar`); cubierto por
  `website_canvas_document_sanitization_test.dart`.
- El cliente RPC demuestra que `p_blocks` sale sin metadata transitoria y que
  una respuesta legacy con selección persistida vuelve sanitizada, preservando
  homónimos legítimos (`website_page_blocks_rpc_client_test.dart`, 2/2).
- Paridad geométrica Canvas Edit/Preview/Público a 1440/834/390, incluyendo
  offset y tamaño del elemento, más selección repetida/background transitoria
  (`website_canvas_renderer_convergence_test.dart`).
- La aserción source-text del test de arquitectura del workspace se sustituyó
  por el contrato vigente de owner compartido; el gate combinado
  Canvas/capabilities/foundation + arquitectura + RPC pasó 73/73 y el analyzer
  focal de 12 paths no reporta issues.
- Matriz 24/24 cerrada: `WebsiteBlockCapabilityRegistry` declara los 24 tipos
  con `usesSharedContentRendererInEdit: true` y cero
  `hasExplicitEditableRenderer: true`; `website_block_capabilities_test.dart`
  fija por enumeración exhaustiva que el conjunto legacy es vacío, y las
  matrices por familia (4A/4B integrada, hero/carousel 4C, canvas 4D) aportan
  la evidencia geométrica.

### Gate

- [x] 24/24 tipos usan contenido compartido.
- [x] Cero `_buildEditableXxx` de contenido.
- [x] Cero switches de renderer fuera del owner compartido.
- [x] Paridad geométrica desktop/tablet/teléfono y round-trip demostrados por
  cada familia.
- [x] `previewMode` sólo inyecta placeholders/presenters de Edit; nunca cambia
  geometría derivada de valores guardados.
- [x] Revisión visual final de Claude (2026-07-30; ver la auditoría visual de
  la casilla anterior, con paridad verificada contra producción).

---

## Fase 5 — FSM única de Edit/Preview

**Estado:** completa (2026-07-30).

### Trabajo

- [x] Declarar un único estado tipado del modo dentro del owner de sesión.
- [x] Reemplazar los dos booleanos de modo por una FSM
  `public | preview | edit`.
- [x] Tratar query/URL como comando de entrada y proyección write-through.
- [x] Eliminar competencia URL ↔ provider.
- [x] Eliminar cálculos `provider || URL` y `forceEditMode`.
- [x] Eliminar `_pendingModeNavigation` y `_modeTransitionSequence`.
- [x] Eliminar `_pendingProviderModeSync`.
- [x] Eliminar delays de sincronización de 220/260 ms.
- [x] Eliminar anti-rebounce/pending flags que sólo existen para reconciliar
  dos owners.
- [x] Eliminar sincronizadores duplicados en Home, página dinámica y políticas.
- [x] Mantener deep links Edit/Preview y Back/forward.
- [x] Revalidar navegación y checkout al cambiar de modo.

### Cobertura requerida

- [x] `edit=true`, `preview=true`, ambos y ninguno.
- [x] Deep link inicial.
- [x] Cambio rápido Edit ↔ Preview.
- [x] Back/forward del navegador.
- [x] Provider cambia mientras URL update está en vuelo.
- [x] Navegación con draft durante transición.
- [x] Cero timers o flags compensatorios nuevos.

### Gate

- [x] Un solo owner FSM demostrado.
- [x] URL refleja estado sin poder competir con él.
- [x] Timers/anti-rebounce eliminados.
- [x] Suite acumulada de Fases 0–4 continúa verde.

### Evidencia del cierre F5 (2026-07-30)

Arquitectura implementada como lote atómico:

- `WebsiteEditorMode { public, preview, edit }` con un único campo `_mode` en
  `WebsiteEditModeProvider`; `isEditMode`/`isPreviewMode`/`isInEditorContext`
  quedaron como getters derivados de migración. `WebsiteWorkspaceMode` se
  conservó ortogonal.
- API canónica: `openEditorDocument` (entrada con documento y modo explícito),
  `activatePageDocument` (documento sin cambiar modo, seguro en `build` con
  notify diferido), `setMode` (transición edit↔preview; `public` delega en
  `closeEditor`), `applyRouteModeCommand` (comando URL: entra o cambia de modo,
  nunca sale) y `closeEditor`. `enterEditMode`/`enterPreviewMode` son alias
  finos de compatibilidad de tests que delegan en la FSM; `switchToEditMode`,
  `switchToPreviewMode`, `exitEditMode` y `WebsiteEditorModeRequest` fueron
  eliminados.
- Helpers puros en
  `lib/modules/website/models/website_editor_mode_route_binding.dart`
  (`websiteEditorModeRequestFromUri`, `projectWebsiteEditorModeOntoUri`,
  `uriProjectsWebsiteEditorMode`), preservando query ajena multivalor y
  fragmento.
- Adapter determinista en `PublicStoreLayout.build`: una URI cambiada es
  comando de entrada (Edit gana; una URI sin flags nunca es salida); una URI
  sin cambios con cambio de provider recibe proyección write-through post-frame
  (sólo web) releyendo el provider para que la última revisión gane. Sin
  timers, sin pending flags, sin `provider || URL`.
- `_navigateToHref` proyecta el modo canónico sobre cada destino interno
  mediante el helper compartido (una sola navegación por transición, historial
  reproducible con Back/forward); se eliminó la reinyección manual de flags.
- Toggle Edit/Preview: en web navega con la proyección canónica (la URI
  cambiada es el comando); en ERP nativo llama `setMode` directo con ruta
  estable. Cero delays de 220/260 ms; los delays de progressive rendering
  (16/180 ms), el polling de tenant readiness (250 ms) y el timer de payment
  capabilities se preservaron por no pertenecer a la FSM.
- `WebsiteEditorDocumentBinding` compartido e idempotente reemplazó los
  sincronizadores duplicados (`_checkEditModeFromRouter`,
  `_syncEditorContextToHomeIfNeeded`, `_updateEditProviderIfNeeded`,
  `_scheduleEditProviderSyncIfNeeded`, `_editModeChecked`,
  `_editorSyncScheduled`) en Home, Dynamic y Policy.
- `public_store_router.dart` eliminó `_storefrontMode` y el componente de modo
  de `publicStoreModeContentKey`: un cambio de flags de modo ya no remonta el
  subtree ruteado (Scaffold/Navigator/drafts estables).
- `persistent_editor_shell.dart` migró a `setMode`/`openEditorDocument`.
- El registro `canonical-ui-surfaces.md` ganó la fila
  `Storefront mode FSM route binding` y la fila de identidad de ruta se
  actualizó al key sin modo; la deuda correspondiente del contrato quedó
  marcada resuelta.

Pruebas:

- `test/widgets/website_editor_mode_route_binding_test.dart` (4/4): deep link
  inicial, ambos flags → Edit, Back/forward como comandos con salida
  prohibida por URI sin flags, provider gana sobre URI obsoleta y draft
  sobrevive a toggles rápidos.
- `test/widgets/website_editor_history_guardrail_test.dart` extendido: matriz
  URI total con precedencia Edit, proyección write-through preservando query
  ajena/fragmento con round-trip, y exclusividad/idempotencia FSM (comando
  público nunca sale; toggles rápidos sin timers; `setMode(public)` cierra).
- `test/widgets/public_store_layout_navigation_stability_test.dart` extendido:
  el Scaffold del shell mantiene identidad a través de Edit↔Preview, toggles
  rápidos se asientan en la última revisión, y un cambio de flags de modo en
  la URL no remonta el subtree ruteado.
- `test/widgets/website_editor_document_binding_test.dart` (3/3): binding
  inerte fuera de sesión/sin datos, recorrido Home → Dynamic → Policy → Home
  en Edit y Preview con reemplazo idempotente sin tormenta de notificaciones,
  y páginas offstage sin capacidad de robar el documento.
- Suite acumulada F0–F5: 190/190 (187 de la matriz acumulada + 3 del binding
  de documento); analyzer de `lib/modules/website` + `lib/public_store` sin
  errores ni warnings nuevos (15 infos preexistentes en archivos no tocados).
- La proyección write-through está detrás de `kIsWeb`; su rama de navegador
  real se valida en la auditoría visual final (la lógica pura está cubierta
  por unit tests).

---

## Fase 6 — Partición física

**Estado:** movimientos mecánicos ejecutados (2026-07-30); el gate de bundle
se cierra con el build del gate final.

Esta fase sólo mueve responsabilidades ya estabilizadas. No mezcla movimientos
masivos con cambios de comportamiento.

### Trabajo

- [x] Confirmar primero Fases 4 y 5 cerradas.
- [x] Dividir `website_editor_panel.dart` por surface/capability.
- [x] Dividir `public_store_layout.dart` por layout, navegación y chrome.
- [x] Dividir `website_service.dart` por operaciones coherentes sin duplicar
  cliente ni cache.
- [x] Extraer familias de renderer ya convergidas a archivos pequeños.
- [x] Mantener imports públicos/deferred y presupuesto del bundle storefront.
- [x] Eliminar código muerto sólo después de probar cero consumidores.
- [x] Ejecutar format mecánico únicamente en archivos movidos/propios.

Línea base física anterior:

- `website_editor_panel.dart`: aproximadamente 15.386 líneas.
- `public_store_layout.dart`: aproximadamente 8.613 líneas.
- `website_service.dart`: aproximadamente 5.314 líneas.
- No existía una partición `part`/`part of`.

Resultado de la partición (2026-07-30), mediante `part`/`part of` puros —
misma librería, cero cambio de import para consumidores, acceso privado
preservado, cero owners nuevos:

- `website_editor_panel.dart`: 342 líneas (núcleo del panel) + 14 part files
  en `widgets/editor_panel/` por surface/capability: inserter
  (`add_blocks_tab`), sync, inspector (`edit_block_tab`), controles por
  familia (`carousel_controls`, `products_controls`, `schema_controls`,
  `canvas_controls`, `collection_block_controls`,
  `header_footer_controls`, `style_controls`), `page_settings_tab`,
  `theme_tab`, `shared_field_widgets` y `backups_dialog`.
- `public_store_layout.dart`: 7.042 líneas + 6 part files en
  `widgets/store_layout/`: navegación (`runtime_href`, `header_geometry`,
  `page_navigator`), chrome (`scroll_and_chrome`) y soporte del workspace
  (`editor_workspace_tabs`, `layout_helpers`). `_PublicStoreLayoutState`
  permanece como clase única: Dart no permite partir un cuerpo de clase entre
  part files, y extraer sus métodos a extensiones dispararía
  `invalid_use_of_protected_member` por `setState`; la clase es un owner
  único legítimo (shell/route controller) y no un candidato mecánico.
- `website_service.dart`: 5.192 líneas + 2 part files:
  `website_service_support.dart` (scoped loads, cache-safety, address
  helper) y `website_page_snapshot_cache.dart` (familia completa del snapshot
  cache). `WebsiteService` permanece como clase única por la misma
  restricción (`notifyListeners` es protected); sigue siendo un solo
  cliente/cache.
- Los tests de contrato source-text leen ahora la librería completa mediante
  `test/support/library_source.dart` (`readLibrarySource`: archivo principal
  + todos sus `part`), de modo que una partición física nunca debilita un
  contrato de código. Migrados 18 archivos de test de forma mecánica.
- Reparaciones mecánicas de expectativas obsoletas descubiertas al reejecutar
  los contratos (documentadas para el paquete de cross-review):
  `public_order_access_architecture_test.dart` (la navegación a confirmación
  usa el boundary canónico `PublicStoreLayout.navigateToHref`; índices sobre
  fuente whitespace-normalizada), `checkout_error_copy_contract_test.dart`
  (el lock de pop vive en `StorefrontNavigationGuardScope.canPop:
  _allowPopOnce` desde la migración del guard) y
  `public_tenant_directory_client_contract_test.dart` (el audit de destinos
  lee `tenants` con `.eq('id', tenantId)` — superficie own-tenant
  autenticada añadida por trabajo concurrente, verificada scoped antes de
  permitirla).

### Gate

- [x] Diff de movimientos revisable y sin cambio semántico.
- [x] Analyzer y suite acumulada verdes antes y después.
- [x] Bundle storefront dentro del presupuesto (2026-07-30, build release
  post-partición: `main.dart.js` 5.606.752/6.000.000 raw y
  1.584.835/1.700.000 gzip; 23 chunks deferred, total diferido
  3.155.762/3.600.000, mayor chunk 1.366.418/1.600.000 —
  `scripts/check_storefront_bundle_budget.sh` verde).
- [x] Sin cambios en Nóminas, `MainLayout`, Workspace o top bar.

---

## Seguimiento futuro que no bloquea la corrección inicial

- [ ] Evaluar una RPC transaccional global para todas las familias de save.
- [ ] Completar la reconstrucción UX histórica: Layers, inserter, media,
  commands, multi-select y overrides responsive, sin crear owners paralelos.
- [ ] Convertir las aserciones de arquitectura source-text restantes cuando se
  toque su comportamiento.
- [ ] Resolver `activeElementId` Canvas completamente como estado transitorio.
- [ ] Eliminar inset residual de chrome Canvas.
- [ ] Convertir campos URL-only legacy al picker canónico cuando se toquen.

Estos puntos no permiten reabrir el DELETE + INSERT inseguro ni duplicar el
coordinador actual.

## Matriz de validación acumulada

### Flutter

- [x] 128/128 pruebas enfocadas acumuladas, reejecutadas sobre el checkout
  actual el
  2026-07-29:
  - `website_page_blocks_rpc_client_test`
  - `website_save_coordinator_test`
  - `website_save_tenant_projection_test`
  - `website_editor_navigation_guard_test`
  - `website_editor_history_guardrail_test`
  - `website_block_capabilities_test`
  - `website_action_value_test`
  - `website_page_composition_projection_test`
  - `page_composition_test`
  - `static_policy_publication_contract_test`
  - `public_store_navigation_fluency_test`
  - `persistent_editor_save_error_retry_test`
  - `storefront_programmatic_navigation_inventory_test`
  - `static_policy_page_composition_test`
  - `website_about_block_content_test`
  - `website_contact_block_content_test`
  - `website_cta_block_content_test`
  - `website_renderer_convergence_test`
- [x] Gate F4B: 114/114 pruebas enfocadas en capabilities, normalización,
  comandos nested, contenido 4A/4B, composición y round-trip.
- [x] Gate F4D (2026-07-30): 73/73 sobre convergencia Canvas, sanitización de
  documento, controles inline, capabilities, foundation, arquitectura del
  workspace y cliente RPC; analyzer focal de 12 paths sin issues.
- [x] Rerun del cliente RPC después del deploy: 1/1.
- [x] Analyzer focalizado de 36 archivos Website/tests: sin issues.
- [x] Analyzer focalizado de los 17 archivos del lote 4A: sin issues.
- [x] Analyzer focalizado de los 28 archivos del lote 4B: sin issues.
- [x] `app_router.dart` analizado con `--no-fatal-infos`: exit 0.
- [x] `git diff --check`: limpio.
- [x] Gate F5+F6 (2026-07-30): suite acumulada F0–F5 completa 190/190 tras el
  lote FSM; reejecutada íntegra tras la partición física con 0 fallos; los
  contratos source-text afectados por la partición leen la librería completa
  vía `test/support/library_source.dart` y pasan (254/257 en el barrido de
  contratos, con las 3 reparaciones mecánicas documentadas en Fase 6).
- [x] Gate Flutter COMPLETO del repo (`scripts/run_flutter_test_gate.sh`,
  2026-07-30): toda la suite pasa salvo 4 tests en 3 archivos de dominios
  concurrentes, ninguno atribuible al refactor:
  `checkout_exit_navigation_test.dart` (declarado concurrente en este plan),
  `checkout_durable_recovery_widget_test.dart` (dominio checkout/pagos
  concurrente) y `website_link_value_editor_category_scope_test.dart`, roto
  por el gate de readiness concurrente añadido a
  `website_link_value_editor.dart` (+69 líneas, fuera del inventario de este
  refactor): con el fixture sin tenant el load de categorías falla
  (`No se pudo determinar tenant_id`) y el gate nuevo rechaza `Aplicar`,
  devolviendo null donde el test espera el href. Corrección pendiente del
  owner concurrente (fixture tenant-scoped o loader inyectable).
- [x] Bundle storefront release dentro del presupuesto (ver gate de Fase 6).

### Base de datos

- [x] pgTAP enfocado local: 29/29.
- [x] pgTAP production-derived: 29/29.
- [x] Producción: migración aplicada, leída y registrada.
- [x] Health crítico ERP: verde.
- [x] Tenant isolation, page scope, lista vacía y rollback inducido cubiertos.

### Evidencia conocida no verde

- [x] Reconciliación del `just db-test` completo (2026-07-30): 115 archivos /
  3.618 tests. La suite del refactor
  (`supabase/tests/website_page_blocks_replace.sql`) pasa completa dentro del
  run. Fallan 17 archivos, TODOS de dominios concurrentes ajenos al refactor:
  16 idénticos al log previo `.tmp/db/pgtap-20260729-155220.log`
  (auth provisioning, credit balance, mechanic_job*, messaging, online_order*
  correcciones/documentos/vouchers, purchase*, push notifications,
  `storefront_sales_contact` — este último era el "caso storefront" señalado
  y falla idéntico ANTES del refactor, por lo que no es atribuible a él —
  y workshop payments); delta respecto del log previo:
  `hr_payroll_authorization_hardening` quedó corregido por su owner y
  `employee_self_service_scope` es un fallo nuevo, también del dominio
  HR/payroll concurrente. Evidencia: log de sesión db_test 2026-07-30.
  Ninguno de los 17 pertenece al alcance Website; sus owners concurrentes
  los tienen en curso.
- [ ] Falta la auditoría visual final desktop/tablet/teléfono sobre el árbol
  post-F5/F6; la matriz widget de 4A–4D está verde.

Un fallo fuera de la suite RPC no se oculta ni se usa para invalidar sus 29/29;
la atribución quedó reconciliada arriba.

## Estado de release y producción

| Artefacto | Estado |
|---|---|
| RPC `replace_page_blocks` | ✅ Productiva y registrada |
| Datos productivos | ✅ No fueron modificados por la migración DDL |
| Código Flutter del refactor | 🟡 Local en checkout compartido; release autorizado al cerrar todos los gates |
| Commit | ⏳ No realizado |
| Push / PR | ⏳ No realizado |
| Deploy de aplicación ERP/storefront | 🟡 Autorizado por el owner; pendiente de gate y artefacto final |

Consecuencia: la API atómica ya existe en producción y está lista antes del
cliente nuevo. El cliente público/productivo sólo utilizará esa RPC después de
publicar el código Flutter; hasta ese release, un build antiguo puede conservar
el camino de guardado anterior.

El owner autorizó el 2026-07-29 commit, push, deploy y publicación dentro del
alcance. No se hará un release intermedio: se completarán Fases 4–6 y el gate
acumulado antes de preparar el artefacto, para no publicar dos veces el mismo
refactor ni mezclar un build parcial con el checkout concurrente.

## Inventario de paths del refactor

Este inventario identifica paths/hunks propios del refactor. El `git status`
global no atribuye cambios: el checkout contiene trabajo concurrente.

### Documentación

- `.github/copilot-instructions.md` (sólo hunks Website Builder)
- `docs/architecture/canonical-ui-surfaces.md`
- `docs/architecture/website-builder-agent-handoff.md`
- `docs/architecture/website-editor-contract.md`
- `docs/architecture/website-builder-refactor-guardrails.md`
- `docs/development/AGENT_DATABASE_CONTRACT.md`
- `docs/development/WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md`

### Núcleo Website

- `lib/modules/website/models/website_action.dart`
- `lib/modules/website/models/website_block_capabilities.dart`
- `lib/modules/website/models/website_block_document_sanitizer.dart`
- `lib/modules/website/models/website_editor_mode_route_binding.dart`
- `lib/modules/website/widgets/website_editor_document_binding.dart`
- `lib/modules/website/models/website_block_geometry.dart`
- `lib/modules/website/models/website_page_composition.dart`
- `lib/modules/website/providers/website_edit_mode_provider.dart`
- `lib/modules/website/services/website_service.dart`
- `lib/modules/website/services/website_save_coordinator.dart`
- `lib/modules/website/widgets/block_spacer_handle.dart`
- `lib/modules/website/widgets/canvas_block.dart`
- `lib/modules/website/widgets/deferred_editable_block_renderer.dart`
- `lib/modules/website/widgets/deferred_canvas_block.dart`
- `lib/modules/website/widgets/editable_block_renderer.dart`
- `lib/modules/website/widgets/inline_editable_text_v2.dart`
- `lib/modules/website/widgets/website_action_button.dart`
- `lib/modules/website/widgets/website_about_block_content.dart`
- `lib/modules/website/widgets/website_block_content_presenters.dart`
- `lib/modules/website/widgets/website_block_icon_resolver.dart`
- `lib/modules/website/widgets/website_block_renderer.dart`
- `lib/modules/website/widgets/website_canvas_editor_binding.dart`
- `lib/modules/website/widgets/website_carousel_edit_binding.dart`
- `lib/modules/website/widgets/website_contact_block_content.dart`
- `lib/modules/website/widgets/website_cta_block_content.dart`
- `lib/modules/website/widgets/website_editor_navigation_guard.dart`
- `lib/modules/website/widgets/website_editor_panel.dart`
- `lib/modules/website/widgets/website_faq_block_content.dart`
- `lib/modules/website/widgets/website_features_block_content.dart`
- `lib/modules/website/widgets/website_gallery_block_content.dart`
- `lib/modules/website/widgets/website_hero_block_content.dart`
- `lib/modules/website/widgets/website_inline_action_editor.dart`
- `lib/modules/website/widgets/website_pricing_block_content.dart`
- `lib/modules/website/widgets/website_services_block_content.dart`
- `lib/modules/website/widgets/website_stats_block_content.dart`
- `lib/modules/website/widgets/website_team_block_content.dart`
- `lib/modules/website/widgets/website_testimonials_block_content.dart`
- `lib/modules/website/widgets/website_text_block_content.dart`

### Storefront y rutas

- `lib/public_store/pages/dynamic_website_page.dart`
- `lib/public_store/pages/public_home_page.dart`
- `lib/public_store/pages/static_policy_page.dart`
- `lib/public_store/providers/public_store_tenant_provider.dart`
- `lib/public_store/widgets/page_composition.dart`
- `lib/public_store/widgets/persistent_editor_shell.dart`
- `lib/public_store/routes/public_store_router.dart`
- `lib/public_store/widgets/public_store_layout.dart`
- `lib/public_store/widgets/search_overlay.dart`
- `lib/public_store/widgets/storefront_navigation_guard_scope.dart`
- `lib/public_store/widgets/website_page_content.dart` (eliminado)
- `lib/shared/routes/app_router.dart` (sólo hunks Website)

### Base de datos

- `supabase/sql/core_schema.sql`
- `supabase/migrations/20260729010000_atomic_replace_page_blocks.sql`
- `supabase/tests/website_page_blocks_replace.sql`

### Pruebas

- `test/unit/public_store_navigation_fluency_test.dart`
- `test/unit/static_policy_publication_contract_test.dart`
- `test/unit/website_action_value_test.dart`
- `test/unit/website_block_capabilities_test.dart`
- `test/unit/website_block_collection_normalization_test.dart`
- `test/unit/website_page_blocks_rpc_client_test.dart`
- `test/unit/website_page_composition_projection_test.dart`
- `test/unit/website_repeater_edit_command_test.dart`
- `test/unit/website_save_coordinator_test.dart`
- `test/unit/website_save_tenant_projection_test.dart`
- `test/widgets/page_composition_test.dart`
- `test/widgets/persistent_editor_save_error_retry_test.dart`
- `test/unit/storefront_programmatic_navigation_inventory_test.dart`
- `test/widgets/static_policy_page_composition_test.dart`
- `test/widgets/website_editor_history_guardrail_test.dart`
- `test/widgets/website_editor_navigation_guard_test.dart`
- `test/widgets/website_about_block_content_test.dart`
- `test/widgets/website_contact_block_content_test.dart`
- `test/widgets/website_cta_block_content_test.dart`
- `test/widgets/website_faq_block_content_test.dart`
- `test/widgets/website_features_block_content_test.dart`
- `test/widgets/website_gallery_block_content_test.dart`
- `test/widgets/website_hero_block_content_test.dart`
- `test/widgets/website_carousel_block_content_contract_test.dart`
- `test/widgets/website_pricing_block_content_test.dart`
- `test/widgets/website_renderer_convergence_test.dart`
- `test/widgets/website_services_block_content_test.dart`
- `test/widgets/website_stats_block_content_test.dart`
- `test/widgets/website_team_block_content_test.dart`
- `test/widgets/website_testimonials_block_content_test.dart`
- `test/widgets/website_storefront_projection_regression_test.dart`
- `test/widgets/website_canvas_renderer_convergence_test.dart`
- `test/unit/website_canvas_document_sanitization_test.dart`
- `test/widgets/canvas_block_inline_controls_test.dart`
- `test/unit/website_editor_foundation_test.dart`
- `test/widgets/website_editor_mode_route_binding_test.dart`
- `test/widgets/website_editor_document_binding_test.dart`
- `test/widgets/public_store_layout_navigation_stability_test.dart`
- `test/unit/website_builder_workspace_architecture_test.dart` (sólo hunks
  Website: test Canvas/carousel actualizado al owner compartido y reparación
  mecánica de la expectativa `canStartPageBeforeCategories` que el trabajo
  concurrente de catálogo dejó obsoleta)

### Exclusiones explícitas

- No se toca `lib/main.dart`.
- No se toca `_WorkspaceShellState.build`.
- No se reclaman archivos de Nóminas, MainLayout, Workspace o sistema visual.
- `test/widgets/checkout_exit_navigation_test.dart` es concurrente y no
  pertenece a este refactor.

## Riesgos abiertos

| Riesgo | Severidad | Mitigación / siguiente evidencia |
|---|---|---|
| Build productivo antiguo aún usa el save anterior | Alta hasta release de app | RPC ya desplegada; publicar cliente autorizado al cerrar el gate |
| Builder Edit Canvas separado | Cerrado (2026-07-30) | Lote 4D atómico: owner único `DeferredCanvasBlock`, selección transitoria tipada, sanitización type-aware y matriz 24/24 |
| URL y provider aún compiten por el modo | Cerrado (2026-07-30) | FSM única en el provider; URI sólo comando de entrada + proyección write-through cubierta por suite |
| Timers/anti-rebounce legacy | Cerrado (2026-07-30) | Delays 220/260 ms, pending flags y sincronizadores duplicados eliminados con cobertura conductual |
| Navegaciones programáticas futuras fuera del guard | Media | Inventario suplementario y pruebas conductuales mantienen un solo entry-point |
| Política estática: respuesta síncrona antes de montaje | Cerrado | Carga inicial trasladada a `didChangeDependencies`; matriz 6/6 |
| Error/retry de save en el shell | Cerrado | Fallo visible, draft intacto y segundo `Guardar` cubiertos |
| Full DB suite con fallos fuera de la suite RPC, aún sin atribución completa | Media para gate global | Reconciliar cada fallo y rerun antes de release |
| Sin auditoría visual acumulada actual | Alta para cierre UX | Coordinar sesión canónica y revisar desktop/tablet/teléfono |
| Checkout concurrente puede solapar archivos Website | Alta | Inspección read-only antes de cada edit y ownership por hunk |

## Próxima secuencia obligatoria

1. ~~Implementar 4D y eliminar su builder viejo en el mismo lote~~ — hecho
   2026-07-30 (sin ronda Design, por mandato arquitectónico del owner).
2. ~~Cerrar la matriz final 24/24~~ — hecho 2026-07-30.
3. Ejecutar Fase 5 FSM.
4. Ejecutar Fase 6 como movimientos mecánicos.
5. Auditoría visual desktop/tablet/teléfono sobre el árbol final (cierra la
   revisión visual de Fase 4 una sola vez, después de F5/F6).
6. Ejecutar el gate completo y el release de aplicación ya autorizado.

## Aprobación cruzada Claude

**Estado:** **APROBADO TRAS RECONCILIACIÓN**.
**Modo requerido:** Claude Code, repo `bikeshop-erp`, Fable 5 u Opus 5,
`Effort: Ultracode`.
**Alcance:** revisión read-only del plan y evidencia; sin edit, commit, push,
deploy, publicación ni escritura productiva.

### Preflight

- [x] Surface visible: Code.
- [x] Repo visible: `bikeshop-erp`.
- [x] Modelo visible: Fable 5.
- [x] Esfuerzo visible: `Effort: Ultracode`.
- [x] Chat `Website Builder arquitectura diagnóstico` verificado inmediatamente
  antes de enviar.

### Veredicto solicitado

- [ ] Aprobado sin cambios obligatorios.
- [x] Aprobado con correcciones obligatorias.
- [ ] Rechazado; requiere replanificación.
- [x] Aprobado tras reconciliación final.

Claude debe indicar:

1. hechos reproducidos frente a hipótesis;
2. fases/casillas incorrectas o incompletas;
3. severidad y blast radius de cada finding;
4. corrección propuesta y alternativas;
5. regresión mínima requerida;
6. si el orden Fase 4 → 5 → 6 es seguro;
7. qué decisiones de Fase 4 necesitan Design antes de código;
8. incertidumbre restante.

### Resultado de Claude

Primera pasada read-only del 2026-07-29:

- reprodujo 94/94 pruebas enfocadas;
- reprodujo analyzer del núcleo sin issues y los 12 infos ajenos de
  `app_router.dart`;
- verificó en vivo RPC, registro, ACL sin `anon` y health crítico verde;
- confirmó coordinador único, composición compartida, 10/24 renderers y línea
  base física;
- no encontró dueño paralelo ni big-bang en el plan;
- veredicto: **APROBADO CON CORRECCIONES OBLIGATORIAS**, todas documentales o
  de rigor de gates, ninguna arquitectónica.

Incertidumbre declarada por Claude: no reejecutó pgTAP, muestreó 17 de los 36
archivos del analyzer, no hizo pass visual/runtime y no releyó la semántica
interna de `can_edit_tenant_settings`. Esas limitaciones no sustituyen la
evidencia Codex ya registrada.

Segunda pasada breve: Claude releyó los cinco hunks corregidos, reprodujo
109/174 para Fases 0–6 y 51/52 para Fases 0+1, confirmó una sola fila canónica
de composición y emitió **APROBADO TRAS RECONCILIACIÓN**. Correcciones suyas
pendientes: ninguna.

Para F4B, Claude Design realizó una revisión adicional en
`Website Builder - Renderer Convergence`, conceptos `2a`–`2i`, y aprobó
conservar los árboles públicos, usar ancho útil real, evitar samples/copy
ficticio y mantener los controles de colección fuera de la geometría
visitante. Codex integró ese veredicto y cerró la matriz conductual 4B.

### Cross-review de cierre (2026-07-30, logic-cross-reviewer independiente)

Revisión adversarial read-only sobre los 5 seams (FSM, adapter de ruta,
sanitización, partición F6, multi-tenant). Veredicto: arquitectura confirmada
(FSM único real sin timers/sincronizadores; sanitización type-aware sólida;
partición sin duplicados ni colisiones; tenant-scope correcto en los archivos
nuevos). Disposición de hallazgos:

- **Corregidos en el mismo cierre, con regresión:** H2 (residuo
  `provider || URL` en los loaders de Dynamic/Policy → enrutado por el helper
  canónico `websiteEditorModeRequestFromUri`, misma tabla de verdad), H3 (el
  page navigator forzaba `edit=true` desde Preview → ahora proyecta el modo
  actual con el helper canónico, según el contrato del page selector), H5
  (`uriProjectsWebsiteEditorMode` comparaba strings crudos → igualdad
  semántica de flags, con matriz de regresión de query ajena multivalor y
  combinaciones no canónicas), H6 (`updateBlockDataSilent` marcaba dirty sin
  el guard de no-op → mismo guard que `updateBlockData`). Suites focales
  reejecutadas en verde y árbol staged reverificado (sin errores nuevos).
- **H7 verificado correcto:** `WebsiteSaveCoordinator.save` usa
  `rethrowErrors: true` en todas las familias y lanza `StateError` ante
  cualquier fallo, por lo que el mensaje de éxito del shell nunca se muestra
  sobre un guardado parcial (cubierto además por
  `persistent_editor_save_error_retry_test`).
- **Para el paquete dual Codex (decisiones de comportamiento nuevas, no
  regresiones del refactor):** H1 — la entrada URL al modo editor no exige
  capacidad de edición y `bypassUnpublished` deriva de `isInEditorContext`
  (comportamiento preexistente al FSM; la autoridad servidor está intacta por
  RLS y `loadEditorPageWithBlocks`, pero el chrome y el contenido no publicado
  se muestran a anónimos; gate de capacidad propuesto). H2-fallback — degradar
  a lectura pública cuando el camino editor falla por autorización en enlaces
  `?edit=true` compartidos. H4 — riesgo latente de downgrade de modo en ERP
  nativo si un remount same-route reconsume una URI obsoleta (sin disparador
  identificado; guard de arranque propuesto). Incertidumbre declarada del
  revisor: SQL de `replace_page_blocks`/`get_public_checkout_capabilities` no
  auditado en esta pasada (cubierto por los 29/29 pgTAP production-derived de
  Fase 1) y pureza git de F6 (cubierta por analyzer + suites antes/después).

### Reconciliación Codex

- [x] La casilla CTA/navegación quedó limitada a call sites migrados y probados.
- [x] El porcentaje dejó de ser estimación opaca: muestra conteo mecánico y se
  declara informativo/no-gate.
- [x] `.github/copilot-instructions.md` quedó en el inventario y sus tres
  afirmaciones obsoletas de Website Builder fueron corregidas.
- [x] El gate F4 exige paridad geométrica por familia en
  desktop/tablet/teléfono y limita `previewMode` a chrome, sin alterar
  geometría guardada.
- [x] Las dos filas superpuestas de composición en
  `canonical-ui-surfaces.md` fueron consolidadas preservando ambos contratos.
- [x] La recomendación de evaluar un release intermedio después de Fases 1–3
  quedó registrada como decisión del owner, sin presumir autorización.
- [x] Claude confirma en una segunda lectura breve que las cinco correcciones
  quedaron resueltas.

## Cierre de emergencia — evidencia rerun 2026-07-30 (Claude, handoff exclusivo)

Estado verificado sobre el árbol actual (no checkboxes históricos):

- **Autoridad/lease**: snapshot tipado con `authorityEpoch` derivando `granted`;
  adopción con takeover central (fingerprint O epoch); owners tipados de sesión y
  documento; suspend/revoke con revisión de identidad separada de la generación.
- **Lecturas editor**: exclusivamente `rpc('load_editor_page_with_blocks')`
  (REST origin estructuralmente published-only); captura pre-primer-await y
  supersesión tipada (`WebsiteEditorReadSupersededException`); parser fail-closed
  (`WebsiteCmsReadContractException`, con cause) para payload/página/bloques/
  order_index/block_data; denial latch durable compartido lectura/escritura.
- **Guardado**: preflight sesión+documento vs lease Y capability del servicio
  (fingerprint+epoch); `writeGuard` en cada request mutable interno y tras cada
  response ANTES de proyección local (settings/SEO/página/navegación/replace);
  fallos tardíos no-auth reclasificados superseded; ACKs sólo con autoridad
  vigente; `delete_website_navigation` idempotente authority-bound (dueño único,
  guard estructural cero DELETE directo); shell sin éxito engañoso.
- **OAuth**: intent único tipado/versionado con nonce
  (`WebsiteEditorOAuthIntentGate`/`Store`: peek/take/restoreIfNonce/clearIfNonce);
  `connect()` valida capability del consumidor antes de persistir y limpia sólo
  su nonce; callback valida y navega SÓLO el path sanitizado (sin edit/preview);
  consumidor take-before-await; sólo transitorio clasificado restaura el mismo
  nonce; restore valida identidad/tenant/fingerprint ANTES de toda mutación.
- **Subtree estable (H)**: un solo Scaffold + anchor
  `storefront_content_anchor` con viewport de cadena constante
  (`storefront_content_viewport`, LayoutBuilder real) para public|preview|edit y
  desktop|tablet|mobile; keys por modo eliminadas en Cart/Checkout/Contact/
  Catalog/Detail; recarga por modo del catálogo eliminada; keepAlive restaurado
  en Contact/Catalog/Detail/Home/Dynamic; matriz conductual de retención de
  State/texto/foco/scroll con toggles de modo y device (0 disposes/remounts).

Gates rerun (flutter test por lote con timeout explícito): analyzer 0 errores/
0 warnings en `lib/modules/website`, `lib/public_store`,
`auth_callback_page.dart`, `tenant_service.dart`; seis suites núcleo editor
67/67; persistencia/guardado/OAuth/convergencia 55/55; Home/Dynamic/Policy/
nav-delete/canvas 23/23; contratos F6/arquitectura 87/87; pgTAP local 7 archivos
135/135; validación derivada de producción (scratch desde catálogo productivo)
49/49; `git diff --check` scoped y completo 0.

**SQL productivo CERRADO (2026-07-30)**:
`20260730091630_harden_website_editor_reads.sql` fue validada 135/135 en local
y 49/49 contra el catálogo productivo, desplegada por el flujo guardado de
Codex y leída de vuelta antes del registro. Checksum del artefacto:
`29e2952622b518b8aecb0e6ba626553833c428ab02df9cbb2f7232904b117b45`.
Los cuerpos productivos coinciden con local
(`delete_website_navigation=16b3db73099e07e08811eb9020ad9951`,
`load_editor_page_with_blocks=34a77f7ae9a8558709a1429a9c3609f3`);
owner, volatilidad, `SECURITY DEFINER`, `search_path`, comentarios, ACL, RLS y
políticas pasaron el readback. Los agregados permanecieron en 9 páginas,
36 bloques y 122 enlaces, con cero bloques huérfanos/cross-tenant y cero
parents de navegación cross-tenant. La versión quedó registrada exactamente
como `20260730091630`; `db-health production` cerró con cero violaciones
críticas y los 18 warnings históricos de stock.
