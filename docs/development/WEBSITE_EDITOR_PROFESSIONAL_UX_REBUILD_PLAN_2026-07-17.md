# Plan integral de reconstrucción UX del Website Editor

**Fecha:** 2026-07-17  
**Estado:** Fundaciones y flujo principal implementados; fases avanzadas en seguimiento  
**Alcance:** editor visual, inspector, edición inline, inserción, capas, medios,
responsive, Preview y los 24 tipos de bloque registrados  
**Contrato obligatorio:**
[`docs/architecture/website-editor-contract.md`](../architecture/website-editor-contract.md)

## Entrega implementada el 2026-07-17

La primera entrega funcional ya cubre el flujo principal que estaba roto:

- selección Canvas anidada transitoria, sincronizada entre slide, canvas, lista
  de capas e inspector, sin serializar estado UI ni activar `Guardar`;
- defaults de bloques servidos por `WebsiteBlockRegistry`, con prueba
  parametrizada para los 24 tipos registrados;
- drag-and-drop con payloads tipados para bloques de página y capas Canvas;
- conversión de coordenadas a unidades de diseño antes de aplicar límites, por
  lo que el drop respeta la escala del editor;
- `Agregar` separado en `Capas` e `Insertar`, con búsqueda y grupos distintos
  para estructura, elementos y capas arrastrables;
- inspector contextual de capa con breadcrumb, identidad, Contenido, Diseño y
  Estilo; posición, tamaño, rotación, bloqueo y visibilidad responsive quedan
  accesibles sin recorrer el formulario completo del carrusel; las propiedades
  de contenido y apariencia se muestran en una sola pestaña responsable, no se
  duplican entre ambas;
- colecciones schema-driven con un solo item activo y revelado progresivo;
- biblioteca de medios canónica, buscable y reutilizable, con `Subir` como flujo
  principal y URL sólo en opciones avanzadas;
- reemplazo de imagen inline, desde inspector y desde toolbar Canvas conectado
  al mismo picker; PNG/WebP/GIF conservan transparencia;
- visibilidad de bloque Desktop/Tablet/Móvil persistida y consumida por el
  renderer público/Preview;
- prueba interactiva real en la versión web actual de `/tienda?edit=true`, sin
  guardar mutaciones de auditoría.

Validación de esta entrega:

- analyzer focalizado: sin issues;
- 31 pruebas unitarias/widget/arquitectura: todas aprobadas;
- auditoría visual: Capas, Insertar, Carousel Slide 3, selección de imagen,
  biblioteca de medios, geometría y CategoryGrid verificados en vivo.

Las fases posteriores del documento —command controller completo, overrides
responsive heredables, convergencia total de renderers, multi-select,
group/ungroup, accesibilidad exhaustiva y rollout— permanecen como evolución
incremental; no deben implementarse creando estados o controles paralelos a
estas fundaciones.

## Decisión de producto

El editor debe comportarse como un único sistema profesional de composición,
no como una colección de formularios independientes por bloque.

La arquitectura objetivo tendrá:

- un inserter/librería para agregar bloques, capas y medios;
- un árbol de página y capas para navegar contenido complejo;
- un canvas que permita selección y manipulación directa;
- un inspector contextual para precisión y opciones secundarias;
- un único modelo de selección, comandos, medios, CTA, tema y renderizado;
- paridad real entre Editar, Vista previa y sitio publicado.

Cada acción que un agente haga seguirá siendo una operación que el usuario
puede encontrar, modificar, deshacer y reproducir desde estos controles.

## Línea base verificada

La auditoría interactiva válida se realizó contra
`/Users/Claudio/Applications/Vinabike ERP.app`, actualizada el 2026-07-17 a las
23:06. Se descartó la evidencia obtenida inicialmente desde el binario Debug del
2026-07-16.

En la versión actual se confirmó:

- El carrusel vigente tiene el Slide 3 `EQUIPAMIENTO PARA TU RUTA / CÁMARAS /
  PARA SEGUIR RODANDO` y 33 capas, por lo que la auditoría corresponde al diseño
  actualizado.
- `Canvas Elements (33) > Imagen` no agrega una capa ni abre un selector de
  medios. El contador permanece en 33 y no aparece ningún flujo de subida.
- Al seleccionar una imagen anidada, el inspector continúa identificado como
  `Carrusel Hero` y obliga a atravesar controles de carrusel/slide antes de
  llegar a la capa. El objeto seleccionado no se convierte en el contexto
  principal del inspector.
- El inspector combina navegación, contenido del bloque, comportamiento,
  selección de slide, reglas del canvas, lista de capas y propiedades de la
  capa dentro de una misma columna larga.
- Las acciones inline y las del inspector no forman todavía un flujo único y
  predecible de selección, edición, foco y desplazamiento.

La auditoría de código confirmó además:

- El registro declara 24 tipos de bloque, pero el dispatcher del inspector es
  un `switch` separado. `hero` termina en el inspector de carrusel y
  `googleReviews` declara editor propio sin tener una ruta activa hacia él.
- Las opciones por defecto están duplicadas entre
  `WebsiteBlockRegistry` y `WebsiteEditModeProvider`; ya existen diferencias de
  claves y estructuras para About, Testimonials, Stats, FAQ, Team, Partners,
  Google Reviews, Footer y Canvas.
- Editar y publicar usan dos switches de renderizado. Varios bloques caen al
  renderer público dentro del editor, por lo que selección, edición inline y
  paridad dependen del tipo.
- La selección Canvas todavía puede escribir `activeElementId` en datos del
  bloque y marcar el draft como modificado aunque no cambie contenido.
- El click-add de Canvas sólo reconoce Canvas standalone; no reconoce de forma
  equivalente un carrusel compuesto que usa el mismo renderer.
- El cálculo de drop mezcla píxeles renderizados con unidades de diseño antes
  de convertir la escala, creando límites invisibles a la derecha/abajo.
- El inserter usa payloads `String` compartidos para bloques y capas; el destino
  de página puede aceptar por error un payload de capa Canvas.
- La subida inline y la privada del inspector usan servicios, paths y reglas de
  optimización diferentes. La misma imagen puede comportarse distinto y perder
  transparencia según dónde se cambie.
- Existen inspectores y uploaders duplicados/no usados dentro de
  `website_editor_panel.dart`, mientras los tests actuales validan sobre todo
  presencia de código y no la interacción real.

## Objetivos medibles

1. Una persona nueva puede agregar una imagen, subirla, ubicarla, recortarla y
   reemplazarla sin conocer URLs ni buscar controles en varias secciones.
2. Seleccionar un bloque, item repetible o capa siempre abre exactamente su
   inspector y deja visibles su identidad y sus acciones principales.
3. Ningún inspector muestra todos los datos serializados como una lista extensa;
   usa agrupación, navegación y revelado progresivo.
4. Los 24 tipos de bloque cumplen el mismo contrato de selección, inspector,
   media, CTA, tema, responsive, guardado y paridad según sus capacidades.
5. Click, drag-and-drop, atajos e inserción contextual usan la misma fábrica y
   producen los mismos valores por defecto.
6. Editar, Vista previa y público consumen el mismo contenido y la misma
   geometría. Sólo el chrome de edición puede diferir.
7. Selección, hover, modo crop, pestaña abierta y scroll del inspector son estado
   transitorio: no habilitan `Guardar` ni entran al historial.

## No objetivos

- No reemplazar el CMS por contenido hardcodeado o seed data que el editor no
  pueda representar.
- No crear un segundo dueño de páginas, navegación, categorías, CTA, tema o
  productos.
- No eliminar capacidades para reducir visualmente el inspector.
- No reescribir todo el Website Builder en un solo cambio riesgoso.
- No copiar la interfaz de Wix o WordPress; se adopta su modelo de interacción,
  adaptado al lenguaje visual y flujo ERP de Viñabike.

## Arquitectura UX objetivo

```text
Barra de gestión
  Editar página | Catálogo | Estructura | Ajustes | Más
  Página | Desktop/Tablet/Móvil | Deshacer/Rehacer | Preview | Guardar | Publicar

Rail izquierdo          Canvas central                 Inspector derecho
  Insertar                Renderer real                  Breadcrumb
  Capas                   Edición directa                Identidad + acciones
  Páginas                 Drop zones/guías               Contenido | Diseño | Estilo
  Medios                  Chrome superpuesto             Propiedades del seleccionado
```

### Responsabilidad de cada superficie

| Superficie | Responsabilidad exclusiva |
|---|---|
| Barra de gestión | Cambiar workspace, página, breakpoint, Preview, guardado y publicación |
| Rail Insertar | Buscar, hacer click o arrastrar bloques/capas/patrones |
| Rail Capas | Jerarquía, selección, nombre, orden Z, visibilidad y bloqueo |
| Rail Páginas | Navegar la página real y proteger drafts pendientes |
| Rail Medios | Buscar, subir, reutilizar y administrar assets |
| Canvas | Seleccionar, editar texto, mover, redimensionar, rotar, crop y drop |
| Inspector | Valores precisos, data binding, responsive, estados y opciones secundarias |

El inspector derecho deja de alojar `Agregar`, `Página`, `Tema` y `Google` como
pestañas equivalentes a las propiedades. Tema y Google vuelven a sus workspaces
canónicos; páginas, capas, inserción y medios usan el rail izquierdo.

## Modelo único de selección

Crear un `WebsiteEditorSelectionController` con una ruta de selección tipada:

```text
pageId
  -> blockId | header | footer
    -> repeaterItemId | slideId
      -> canvasElementId
```

Reglas:

- La selección vive fuera de `block_data` y fuera del historial.
- Canvas, lista de capas, lista de items/slides e inspector leen y escriben este
  único estado.
- Seleccionar una capa restaura automáticamente página, bloque padre y slide.
- Repetir click sobre el mismo objeto vuelve a emitir el contexto; nunca deja el
  inspector vacío.
- Click en fondo sube un nivel: capa -> slide/bloque -> página.
- El breadcrumb muestra, por ejemplo,
  `Inicio > Carrusel principal > Slide 3 > Imagen Maxxis`.
- Escape sale de crop/text editing antes de limpiar selección.
- Cambiar selección vuelve a `Contenido`, hace scroll al inicio y conserva el
  foco únicamente cuando corresponde al mismo campo.

## Modelo único de comandos

Crear un `WebsiteEditorCommandController`. Inline e inspector no escriben datos
por caminos distintos.

Cada comando contiene:

- owner tipado (página, bloque, item, slide o capa);
- property path canónico;
- breakpoint;
- valor anterior y nuevo;
- origen (`inline`, `inspector`, `drag`, `keyboard`, `media`);
- política de historial y dirty state.

Un gesto de mover/redimensionar/rotar/crop puede previsualizar muchos frames,
pero confirma un solo comando al terminar. Undo/redo, Guardar y Descartar operan
sobre este mismo modelo.

## Inspector contextual

### Shell universal

Todo objeto seleccionable usa el mismo `WebsiteInspectorShell`:

- breadcrumb y botón Atrás;
- icono, nombre editable y tipo;
- visible/oculto, bloquear, duplicar y eliminar;
- `Contenido`, `Diseño` y `Estilo` siempre en el mismo orden;
- encabezado sticky; cuerpo scrolleable independiente;
- una sola acción principal por contexto;
- estado vacío con una acción concreta, no una pared en blanco.

Cuando se selecciona una imagen dentro del carrusel, la identidad debe ser
`Imagen`, no `Carrusel Hero`; el carrusel y slide permanecen en el breadcrumb.

### Propiedad de cada pestaña

| Pestaña | Controles |
|---|---|
| Contenido | texto/datos, items, fuente catálogo, medio, alt, CTA/destino |
| Diseño | x/y/w/h, layout, alineación, spacing, fit/focal, orden y responsive |
| Estilo | color, tipografía override, fondo/overlay, radio, borde, sombra, animación |

Una propiedad no puede aparecer en dos pestañas. Las secciones frecuentes
comienzan abiertas; las avanzadas, secundarias o vacías comienzan cerradas.
Campos incompatibles o inactivos deben ocultarse o explicar por qué están
deshabilitados.

### Colecciones y repeaters

Carousel, CategoryGrid, Services, Testimonials, Features, Gallery, FAQ,
Pricing, Team, Stats, BrandLogos, PartnersBanner y Footer usan un mismo
`WebsiteCollectionNavigator`:

- overview compacto con miniatura/título/estado;
- un solo item expandido;
- agregar, duplicar, ordenar, ocultar y eliminar junto al overview;
- drag reordering con indicador visible;
- contenido del item primero; media, CTA y opciones avanzadas colapsadas;
- selección sincronizada entre canvas, Layers e inspector.

## Layers: jerarquía visible y navegable

Mover `Canvas Elements (33)` fuera del formulario de carrusel a un modo Layers
persistente:

```text
Inicio
  Header
  Carrusel principal
    Slide 1
    Slide 2
    Slide 3
      Fondo
      Grupo copy
        Equipamiento para tu ruta
        Cámaras
        Para seguir rodando
      Imagen Maxxis
      Imagen RideXC
      Imagen 10Ten
      CTA Ver cámaras
  Productos destacados
  Categorías
  Footer
```

Debe soportar rename, buscar, drag reorder, visibilidad, bloqueo y selección de
elementos ocultos. Orden visual y orden Z son el mismo dato. Layers no contiene
formularios de propiedades.

## Inserter único

Reemplazar `AddBlockDialog`, `_AddBlocksTab` y botones Canvas privados por un
`WebsiteInserter` respaldado exclusivamente por
`WebsiteBlockRegistry` y `CanvasElementFactory`.

Características:

- búsqueda inmediata;
- categorías: Secciones, Contenido, Comercio, Media, Conversión y Elementos;
- recientes/favoritos y patrones iniciales;
- click-add y drag-add con la misma fábrica/defaults;
- destino contextual tipado: página, Canvas standalone o slide compuesto;
- `+` entre bloques y empty states dentro de Canvas/colecciones;
- al insertar, seleccionar el objeto y enfocar su primer control útil;
- payloads tipados (`PageBlockDragPayload`, `CanvasLayerDragPayload`,
  `MediaAssetDragPayload`), nunca `String` ambiguos;
- un target de página rechaza capas y un Canvas rechaza bloques de página;
- si no existe un destino válido, mostrar elección explícita en vez de un
  snackbar sin resultado.

Canvas soportará desde todos los entry points: Texto, Botón, Imagen, Forma,
Producto y Galería de productos, siempre que su schema compartido los soporte.

## Biblioteca y selector de medios

Crear un único `WebsiteMediaPicker` y un único `WebsiteMediaService` para inline,
inspector, backgrounds, logos, galleries, categorías, productos y Canvas.

### Flujo principal

1. `Biblioteca`: buscar/reutilizar assets, recientes, tipo, dimensiones,
   transparencia y usos.
2. `Subir`: click o drop, progreso, validación, retry y preservación de PNG/WebP.
3. `Producto`: elegir imagen real del catálogo cuando el campo permite binding.
4. `URL`: sólo en `Opciones avanzadas`.

El picker retorna una referencia estructurada con asset, URL compatible, alt,
dimensiones, tipo, focal points, original/derivado y transparencia. Las URLs
legacy siguen funcionando, pero dejan de ser la experiencia primaria.

Inline e inspector abren exactamente el mismo picker. La eliminación de fondo
crea un derivado reutilizable, conserva el original y cambia sólo el binding
staged del bloque/capa.

## Edición inline profesional

### Contrato universal

- Un click selecciona.
- Segundo click mantiene/restaura contexto.
- Doble click en texto/botón entra a edición de texto.
- Doble click en imagen entra a crop/reframe.
- El toolbar contiene acciones frecuentes por tipo y un grupo universal compacto.
- Opciones precisas o poco frecuentes viven en el inspector.
- Toolbar y handles se reposicionan arriba/abajo y se limitan al viewport.
- Chrome de edición se pinta en una capa separada; nunca cambia geometría del
  contenido ni aparece en Preview/público.

### Capacidades por tipo de capa

| Tipo | Inline principal | Inspector de precisión |
|---|---|---|
| Texto | editar, formato, alineación | rol tipográfico, tamaño, spacing, responsive |
| Botón | texto, destino, variante | geometría, theme override, estados |
| Imagen | reemplazar, crop, focal, remover fondo | asset/alt/fit, geometría, responsive |
| Forma | tipo, fill, border | geometría, radio, sombra, opacidad |
| Producto | cambiar binding/imagen visible | catálogo, fuente, display, CTA |
| Galería | administrar items | layout, fuente, spacing, responsive |

Mover, resize, rotación, crop, orden, align/distribute, duplicate/delete,
nudge y lock comparten comandos y disponibilidad. Los ocho handles y el handle
de rotación deben ser alcanzables en los cuatro bordes y con canvas escalado.

## Responsive y breakpoints

Reemplazar la duplicación `desktop/mobile layers` como mecanismo principal por
contenido compartido con overrides de diseño:

- Compartido: copy, producto/categoría, destino CTA y asset principal.
- Overrideable: x/y/w/h, rotación, alineación, tamaño tipográfico, visibilidad,
  fit/focal, spacing y estilos seleccionados.
- Desktop es base; Tablet y Móvil heredan hasta que el usuario cambia un valor.
- El control muestra `Heredado` o `Override` y permite `Restablecer`.
- Layers muestra elementos ocultos en el breakpoint actual.
- El selector Desktop/Tablet/Móvil siempre está visible en composición.
- Editar, Preview y público usan el mismo resolver de breakpoint.

La primera entrega debe soportar overrides tipados de geometría/visibilidad sin
duplicar contenido. Scale proporcional, ancho relativo y stretch pueden llegar
después sobre el mismo contrato.

## Paridad de renderizado

Converger `EditableBlockRenderer` y `WebsiteBlockRenderer` hacia un renderer de
contenido compartido. Editar agrega únicamente:

- hit targets;
- selección/hover;
- guías y drop zones;
- toolbar/handles;
- Semantics de automatización.

Transforms, padding, fonts, media fit, clipping, theme, CTA y responsive se
resuelven antes del wrapper de edición. Carousel/hero/cards mantienen un límite
de paint explícito; chrome de selección vive fuera de ese clip.

## Integración con configuración y gestión

El rediseño no crea dueños paralelos:

- `Catálogo web` sigue siendo dueño de publicación, categorías y destacados.
- `Estructura > Páginas` sigue siendo dueño de páginas CMS.
- `Estructura > Navegación y menús` sigue siendo dueño de header/footer.
- `Estructura > Destinos y enlaces` audita CTA y rutas.
- `Tema` controla tokens globales consumidos por todos los bloques.
- El editor visual controla bloques, slides, items y presentación.

El inspector puede ofrecer `Configurar categoría`, `Abrir navegación` o
`Administrar medios`, pero hace handoff al workspace canónico y vuelve al mismo
contexto/selección. Una CTA de campaña no crea automáticamente un item de menú
ni una página duplicada.

## Migración por familias de bloques

| Familia | Tipos | Inspector objetivo |
|---|---|---|
| Campaña/cover | `hero`, `carousel`, `cta`, `videoBanner`, `partnersBanner` | medio/focal, overlay, copy, acción; Carousel añade slides/transición |
| Canvas | `canvas` y slides compuestos | Layers + inspector contextual por capa |
| Catálogo | `products`, Product layer, ProductsGallery layer | fuente, filtros/categoría, selección manual, display, CTA |
| Colecciones | `categoryGrid`, `services`, `features`, `testimonials`, `gallery`, `faq`, `pricing`, `team`, `stats`, `brandLogos` | navigator compacto + un item activo |
| Simples | `text`, `button`, `divider`, `about`, `contact` | inspector mínimo y edición inline directa |
| Operacional | `googleReviews` | apariencia staged; conexión/sync inmediata y claramente separada |
| Especial | `footer`, Header especial | mismo shell; navegación delegada al owner canónico |

### Matriz obligatoria de los 24 tipos

Cada fila debe terminar sin gaps accidentales en el capability registry:

| Tipo | Selección/inline | Contenido | Diseño/Style | Media/CTA/repeater | Responsive/paridad |
|---|---|---|---|---|---|
| hero | sí | propio de hero, no slides falsos | sí | cover + CTA | sí |
| carousel | bloque/slide/capa | slides | sí | cover + CTA + layers | sí |
| canvas | bloque/capa | layers | sí | media/product/gallery | sí |
| text | texto inline | sí | sí | n/a | sí |
| button | botón inline | sí | sí | CTA universal | sí |
| divider | bloque | mínimo | sí | n/a | sí |
| products | bloque/producto | fuente catálogo | sí | selección + CTA | sí |
| services | bloque/item | navigator | sí | CTA universal | sí |
| about | bloque/texto/imagen | sí | sí | media | sí |
| testimonials | bloque/item | navigator | sí | avatar | sí |
| features | bloque/item | navigator | sí | CTA si aplica | sí |
| cta | bloque/texto/botón | sí | sí | CTA universal | sí |
| gallery | bloque/item | navigator | sí | media library | sí |
| contact | bloque/campo | sí | sí | CTA/form binding | sí |
| faq | bloque/item | navigator | sí | n/a | sí |
| pricing | bloque/item | navigator | sí | CTA universal | sí |
| team | bloque/item | navigator | sí | avatar/media | sí |
| stats | bloque/item | navigator | sí | n/a | sí |
| footer | especial/item | navigator | sí | navegación canónica | sí |
| categoryGrid | bloque/item | navigator | sí | media + categoría + CTA | sí |
| videoBanner | bloque | sí | sí | video/image + CTA | sí |
| partnersBanner | bloque/item | navigator | sí | media/CTA si aplica | sí |
| brandLogos | bloque/logo | navigator | sí | media + alt/link | sí |
| googleReviews | bloque/reseña | apariencia | sí | sync separado | sí |

## Arquitectura de código propuesta

Crear o extraer componentes pequeños; reducir gradualmente el archivo gigante
`website_editor_panel.dart`:

- `editor/state/website_editor_selection_controller.dart`
- `editor/state/website_editor_command_controller.dart`
- `editor/state/website_editor_breakpoint_controller.dart`
- `editor/inspector/website_inspector_shell.dart`
- `editor/inspector/website_inspector_section.dart`
- `editor/inspector/website_collection_navigator.dart`
- `editor/inserter/website_inserter.dart`
- `editor/inserter/website_drag_payload.dart`
- `editor/layers/website_layers_panel.dart`
- `editor/media/website_media_picker.dart`
- `editor/media/website_media_service.dart`
- `editor/rendering/website_content_renderer.dart`
- inspectores por familia, no por campos duplicados.

`WebsiteBlockRegistry` será el único owner de definición, schema, defaults,
familia, capacidades e inserción. El provider deja de mantener defaults
paralelos. Header/Footer usan el mismo shell aunque su persistencia siga siendo
especial.

## Plan de implementación

### Fase 0 — Guardrails y medición

1. Capturar goldens actuales de Edit/Preview/público y un inventario de los 24
   tipos.
2. Agregar Semantics estables para canvas, inspector, inserter, tabs, items y
   capas; esto permite pruebas sin coordenadas frágiles.
3. Crear tests que reproduzcan antes de tocar UI:
   - botón Canvas `Imagen` sin resultado;
   - selección que ensucia el draft;
   - click-add en carrusel compuesto;
   - drop al 50% cerca de los cuatro bordes;
   - Hero/Google Reviews con inspector incorrecto;
   - defaults Registry/Provider diferentes;
   - upload inline vs inspector;
   - Preview/Edit geometry.
4. Añadir una pantalla/debug report de capability matrix sólo para desarrollo.

**Gate:** fallos actuales reproducidos por tests, no sólo documentados.

### Fase 1 — Corrección del modelo

1. Extraer selección transitoria y evitar dirty/history por selección.
2. Introducir comandos compartidos y una sola transacción por gesto.
3. Convertir DnD a payloads tipados.
4. Hacer `WebsiteBlockRegistry` dueño de defaults y routing de inspector.
5. Corregir Hero y Google Reviews y eliminar rutas de inspector muertas.
6. Corregir math de escala: convertir puntero a design space antes de clamp.

**Gate:** selección, undo/redo, dirty state, click/drag y defaults pasan tests.

### Fase 2 — Shell, Layers e inspector

1. Construir el shell de tres áreas y mover Insertar/Capas/Páginas/Medios al rail.
2. Implementar breadcrumb y selección jerárquica.
3. Implementar Content/Design/Style sin duplicados.
4. Implementar `WebsiteCollectionNavigator`.
5. Migrar primero Carousel/Canvas y CategoryGrid como pruebas de complejidad.
6. Integrar Header/Footer al mismo shell.

**Gate:** ninguna selección compleja requiere recorrer el formulario padre para
llegar a sus propiedades.

### Fase 3 — Inserter y media universales

1. Unificar todos los add entry points con registry/factory.
2. Agregar búsqueda, context destination, click/drag equivalentes y empty states.
3. Implementar Media Library/Upload/Product/URL avanzada.
4. Migrar inline, schema fields, Canvas, cover, logo, gallery y backgrounds.
5. Eliminar uploaders/direct-Supabase y dialogs URL-only duplicados.

**Gate:** toda imagen se puede crear/reemplazar con el mismo picker y preservar
transparencia/metadata.

### Fase 4 — Migración completa de familias

Migrar en lotes:

1. Campaña/cover.
2. Catálogo.
3. Colecciones/repeaters.
4. Simples.
5. Operacional y especiales.

Después de cada lote, ejecutar la matriz completa de capacidades; no dejar un
bloque tocado en fallback accidental.

**Gate:** 24/24 tipos tienen inspector coherente y save/reload round-trip.

### Fase 5 — Responsive y paridad

1. Introducir overrides Desktop/Tablet/Móvil.
2. Migrar capas duplicadas a contenido compartido cuando sea seguro.
3. Converger renderers de Edit/público.
4. Unificar resolver de theme, CTA, media, geometry, clipping y breakpoints.
5. Verificar rutas `/productos`, filtros CTA y handoffs de gestión.

**Gate:** Edit, Preview y público coinciden en tres breakpoints y los cambios de
copy/destino no se duplican por dispositivo.

### Fase 6 — Productividad, accesibilidad y rollout

1. Multi-select, group/ungroup, align/distribute, copy/paste styles y context menu.
2. Atajos y ayuda de teclado.
3. Contraste, focus traversal, lectores de pantalla y targets mínimos.
4. Telemetría local/no sensible de fallos de comandos, picker y render.
5. Remover código muerto sólo después de confirmar ausencia de consumidores.
6. Rollout por feature flag interno; migración lazy de JSON legacy al abrir/salvar.

**Gate:** auditoría nativa macOS, web y compact/mobile aprobada.

## Estrategia de compatibilidad

- Leer keys legacy y normalizarlas al modelo canónico; escribir sólo el formato
  nuevo más los aliases estrictamente requeridos mientras dure compatibilidad.
- No migrar silenciosamente contenido al seleccionarlo. Migración de datos se
  ejecuta al editar/salvar y queda cubierta por round-trip tests.
- Preservar IDs de bloques, slides, items, capas, productos y destinos.
- Mantener URL legacy como fallback mientras el asset estructurado sea opcional.
- Feature flags separan shell nuevo, media picker y responsive overrides para
  rollback sin perder contenido.
- No borrar inspectores antiguos hasta que los 24 tipos pasen la matriz y no
  existan referencias activas.

## Verificación automatizada

### Unit

- registry/default/schema/capability equivalence;
- selección no serializable/no dirty;
- command coalescing y undo;
- typed DnD acceptance/rejection;
- coordinate conversion a 100%, 80% y 50%;
- breakpoint inheritance/reset;
- media metadata/transparencia;
- CTA/theme/destination round-trip.

### Widget/integration

- smoke parametrizado para los 24 tipos;
- seleccionar bloque, item, slide, capa y repetir click;
- inline -> inspector e inspector -> inline;
- add por click y drag con defaults iguales;
- media picker upload/reuse/cancel/error;
- crop/rotate/resize real mediante puntero;
- toolbar collision en los cuatro bordes;
- collection add/duplicate/reorder/delete;
- Guardar/Descartar/reload;
- page selector y `/productos` con filtros.

### Golden/visual

- Edit, Preview y público en Desktop/Tablet/Móvil;
- 80% y 100% de zoom desktop;
- contenido rotado tocando cada borde;
- clipping entre carrusel y bloque siguiente;
- estados empty, loading, error, selected, hidden y locked;
- header contrast sobre fondos claros/oscuros.

### Auditoría interactiva final

1. Entrar por `Sitio Web > Abrir Editor` en la app actual.
2. Recorrer los 24 tipos mediante la página normal.
3. Crear bloque, item y capa con click y drag.
4. Subir/reutilizar una imagen, crop, rotar, reemplazar y remover fondo.
5. Cambiar breakpoint y crear/restablecer overrides.
6. Probar primera selección, repetición, fondo, Layers e inspector.
7. Abrir Preview, CTA y destino filtrado.
8. Guardar/reabrir sólo en un tenant/página de prueba autorizados.
9. Repetir web y macOS nativo.

## Criterios de aceptación

- `Imagen` siempre abre el picker o agrega una capa visible; nunca es un no-op.
- Una imagen seleccionada muestra `Imagen` como identidad y sus controles sin
  atravesar primero la configuración completa del carrusel.
- Ningún inspector de colección muestra todos sus items expandidos.
- No existe una propiedad en más de una pestaña principal.
- Click y drag crean los mismos defaults en página, Canvas y carrusel compuesto.
- Drop funciona cerca de cada borde al 100%, 80% y 50%.
- Seleccionar, abrir crop, cambiar tab o hacer scroll no habilita Guardar.
- Un gesto equivale a un undo.
- Todo campo de imagen usa el picker visual; URL es secundaria.
- Transparencia PNG/WebP se conserva.
- Toda CTA usa acción/destino universal y reaparece en auditoría de destinos.
- Tema global llega a todos los bloques salvo override explícito visible.
- Header/Footer usan el shell común y navegación canónica.
- Edit/Preview/público coinciden en geometry, transform, clipping, theme y CTA.
- Los 24 tipos guardan, recargan y reconstruyen sus controles.
- No se reproduce ningún crash de overlay, hit testing o `RenderBox.size`.

## Definition of Done

La reconstrucción termina sólo cuando:

1. Los 24 tipos pasan la capability matrix automatizada e interactiva.
2. No quedan defaults, media uploaders, CTA editors, inserters ni selección
   paralelos en rutas activas.
3. El usuario puede crear, encontrar, editar, mover, ocultar, duplicar y borrar
   cada objeto desde controles visibles.
4. El resultado sobrevive Guardar/reload y conserva paridad en Edit, Preview y
   público.
5. Las rutas/configuración canónicas siguen siendo los dueños de páginas,
   navegación, catálogo, tema y destinos.
6. `docs/architecture/website-editor-contract.md` y
   `docs/architecture/canonical-ui-surfaces.md` reflejan cualquier superficie o
   ownership nuevo implementado.
7. La app actual —no un binario cacheado o antiguo— supera la auditoría macOS y
   web por el recorrido normal del usuario.
