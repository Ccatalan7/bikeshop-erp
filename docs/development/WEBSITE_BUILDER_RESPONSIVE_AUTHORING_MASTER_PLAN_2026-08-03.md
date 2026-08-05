# Plan maestro de autoría responsive del Website Builder

**Fecha:** 2026-08-03  
**Estado:** implementación autorizada; Fase 5 cerrada localmente y bajo
hardening transversal
**Prioridad de producto:** edición profesional desde teléfono, sin degradar la
autoría desktop  
**Ámbito:** Website Builder — Edit, Preview y storefront público  
**Owners:** Claude lidera diseño visual e interacción; Codex lidera contratos,
estado, persistencia, migración, integración y verificación

**Checkpoint de implementación 2026-08-04:** el host inline de Fase 5 ya
conserva selección y scroll al alternar Edit/Preview, mide y reserva el dock
real, revela el bloque exacto tras reorder/undo y abre la edición CTA en la
sheet contextual compartida. La sesión nativa verificó además texto inline,
viewport y alcance independientes, foco móvil con conflicto legacy explícito,
reorder y restauración por Undo sin guardar datos productivos. Persistencia,
recuperación y round-trip de save/reload se cierran con fixtures stateful y el
store local del editor; una prueba contra producción no sustituye ese límite.
El cierre nativo se ejecutó además en `Claude iPhone 17 Pro` (iOS 26.5) con el
harness sin autenticación: teclado real `335`, borde inferior de la sheet
`539`, `Listo` en `531` y borde superior del teclado `539`; resultado 1/1
verde. El fixture no leyó ni escribió backend y queda repetible en
`integration_test/website_phone_authoring_ios_smoke_test.dart`.

## 1. Propósito y autoridad

Este documento define el plan específico para convertir el Website Builder en
un sistema de autoría responsive coherente. Responde a dos necesidades que hoy
están mezcladas:

1. editar cómodamente un sitio **desde un teléfono**, manteniendo el contenido
   visible y haciendo la edición principalmente inline e in-page; y
2. editar **las variantes desktop, tablet y móvil** desde cualquier host,
   entendiendo qué propiedad es común, cuál se hereda y cuál tiene un override.

No es una repetición del refactor general del editor. Complementa:

- `WEBSITE_EDITOR_PROFESSIONAL_UX_REBUILD_PLAN_2026-07-17.md`;
- `WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md`;
- `website-editor-contract.md`;
- las guías canónicas de GUI desktop, móvil y componentes universales.

Para este ámbito, este plan reemplaza la idea antigua de dejar “Responsive y
paridad” como una fase tardía. La composición móvil y la autoría responsive son
fundaciones del editor, no una revisión final.

Crear este documento, revisarlo o aprobarlo **no autoriza** cambios de código,
datos, migraciones, commits, pushes, builds, deploys ni publicaciones. La
implementación comienza únicamente con autorización explícita del dueño.

## 2. Decisión ejecutiva

El problema no es que falten algunos controles móviles. El Website Builder hoy
tiene un preview responsive y varias excepciones responsive, pero no posee un
**modelo de autoría responsive**.

La solución será una arquitectura con tres ejes independientes:

| Eje | Pregunta que responde | Ejemplos |
|---|---|---|
| Host de autoría | ¿Desde qué dispositivo se está editando? | desktop, teléfono |
| Viewport objetivo | ¿Qué composición se está viendo/editando? | desktop, tablet, móvil |
| Alcance de escritura | ¿El cambio es común o sólo de este viewport? | compartido, override móvil |

Estos ejes no se pueden inferir uno del otro. Abrir el editor desde un teléfono
no transforma todo cambio en dato móvil; mostrar un canvas móvil en desktop no
debe convertir el inspector en un host de teléfono; y cambiar un valor común no
debe crear tres copias silenciosas.

La arquitectura objetivo tendrá:

- un solo owner de breakpoints;
- un solo resolver de propiedades responsive usado por Edit, Preview y público;
- políticas responsive declaradas por propiedad, no por excepciones de bloque;
- controles universales que entienden herencia y override mediante un wrapper
  compartido;
- una composición desktop con viewport y alcance visibles;
- una composición de teléfono donde el canvas permanece montado y la edición
  nace en el bloque seleccionado;
- migración compatible y reversible de los datos legacy;
- pruebas parametrizadas para las 24 familias de bloque y los tres viewports.

## 3. Evidencia del estado actual

La línea base de este plan viene de una auditoría conjunta del código, los
contratos actuales y la aplicación real. Los números son evidencia de alcance,
no una invitación a reabrir una auditoría completa antes de cada fase.

### 3.1 Registro y controles

- Existen **24** valores canónicos de `WebsiteBlockType`.
- El registro declara actualmente **119** instancias de
  `WebsiteBlockFieldSchema`.
- `edit_block_tab.dart` sólo enruta a inspectores dedicados para Carousel,
  Canvas y Products; los otros **21** tipos pasan por el control genérico.
- Cuatro clases bespoke (`_CategoryGridBlockControls`,
  `_VideoBannerBlockControls`, `_PartnersBannerBlockControls` y
  `_BrandLogosBlockControls`) permanecen como código muerto: el dispatch activo
  envía esas familias al genérico. Se retirarán al migrar sus familias, una vez
  que un guard confirme que no quedan consumidores.
- `WebsiteBlockFieldSchema` conoce tipo y claves de campo, pero no declara una
  política responsive por propiedad.
- `WebsiteBlockDefinition.supportsResponsive` es un booleano demasiado grueso:
  no distingue contenido compartido, geometría, visibilidad, art direction ni
  propiedades que nunca deben divergir.

### 3.2 Preview no equivale a autoría

- `DevicePreviewMode` cambia el marco o ancho del preview.
- No existe un `writeScope` que distinga “Común” de “Sólo este viewport”.
- El editor puede mostrar Mobile mientras sigue escribiendo claves compartidas,
  o mostrar controles móviles simultáneamente con controles desktop sin
  explicar cuál resolverá el renderer.
- El inspector conserva un ancho desktop fijo de 380 px; no hay una composición
  de autoría para un host de teléfono.

### 3.3 Deuda responsive fragmentada

Conviven, al menos, estos modelos parciales:

- `visibility.desktop/tablet/mobile`;
- `mobileFocalPointX/Y`;
- `mobileDesignWidth`;
- `mobileBgAlignment`;
- `hideOnMobile` / `showOnMobile`;
- aliases o expectativas `mobileImageUrl` / `desktopImageUrl`;
- capas o copy duplicados con sufijos `_desktop` y `_mobile` en Canvas.

También conviven umbrales distintos:

- visibilidad pública: 640 / 1024;
- foco, Canvas y gran parte del renderer: 600;
- clases responsive canónicas del producto: 600 / 900.

Cambiar al owner 600/900 afecta dos bandas de documentos ya guardados:

| Ancho lógico | Semántica pública actual | Semántica canónica objetivo |
|---|---|---|
| 600–639 | móvil | tablet |
| 900–1023 | tablet | desktop |

Esto no se tratará como una sustitución mecánica de constantes. Un bloque con
`mobile: false` a 620 px cambiaría de oculto a visible. La migración debe
inventariar contenido con visibilidad no uniforme, conservar semántica legacy
por versión hasta una decisión explícita y probar 620 y 1000 como canarios.

### 3.4 Duplicación de UX

El mismo problema de imagen, encuadre, foco y foco móvil está implementado en
por lo menos tres rutas:

- controles schema genéricos;
- controles de Carousel;
- controles de Canvas.

Cada ruta compone los mismos conceptos de forma distinta. El screenshot que
motivó este plan —múltiples previews grandes, foco general y foco móvil visibles
a la vez— es un síntoma de esa falta de owner, no un problema aislado de
Carousel.

### 3.5 Cobertura insuficiente de autoría compacta

Hay pruebas del renderer a anchos móviles, pero no existe una matriz completa
que monte el host real de Edit aproximadamente a 390 px y demuestre selección,
edición, teclado, sheets, SafeArea, undo, guardado y retorno de contexto.

### 3.6 Fortalezas que se deben preservar

No se reconstruirá todo desde cero. Ya existen bases valiosas:

- la FSM de `WebsiteEditModeProvider`, drafts, dirty state, history y save;
- composición y renderers compartidos entre editor y storefront;
- `WebsiteBlockContentPresenters` para edición inline;
- `InlineEditableTextV2`;
- `WebsiteMediaPicker` e `InlineEditableImage`;
- `FocalPointPicker`;
- `WebsiteActionEditor` y el modelo canónico de destinos;
- `WebsiteColorPickerField`;
- registry, schema y capability profiles para las 24 familias;
- contratos fuertes de paridad Edit → Preview → guardado/reload → público.

El objetivo es darles un protocolo responsive común y eliminar owners
paralelos, no reemplazar capacidades ya probadas.

## 4. Principios de producto

### 4.1 Una identidad de contenido, varias presentaciones

Un bloque, slide, item o capa conserva una identidad estable. Desktop, tablet y
móvil pueden variar su presentación sin convertirse en tres documentos
independientes.

### 4.2 Compartido por defecto, override explícito

Desktop es la composición base y su valor se comparte con tablet y móvil hasta
que éstos reciben un override. La interfaz siempre muestra el estado efectivo:

- `Base (Escritorio)`;
- `Heredado de Escritorio`;
- `Personalizado para móvil`;
- `Personalizado para tablet`.

No se comunicará estado sólo por color.

### 4.3 Herencia directa, sin cascada entre dispositivos

La resolución recomendada es:

```text
override(viewport actual) ?? valor compartido
```

No se usará `móvil → tablet → desktop/base`. Una cascada cruzada hace que
editar tablet cambie móvil indirectamente y vuelve difícil explicar o resetear
el resultado. Tablet y móvil heredan directamente del valor base hasta que
cada uno recibe su propio override.

### 4.4 Preview no escribe; Edit no miente

- Preview y público son consumidores visitantes del mismo valor resuelto.
- Edit presenta exactamente ese valor y añade chrome de edición.
- Cambiar el marco de preview no escribe datos.
- Cambiar el alcance de escritura sí determina dónde se guarda la operación.

### 4.5 Móvil no es desktop comprimido

Editar desde teléfono tendrá una composición propia. No se montará el inspector
desktop en una pantalla angosta ni se reemplazará el canvas por una ruta de
formularios desconectada del contenido.

### 4.6 Inline primero, contexto siempre visible

En teléfono, toda operación comienza en el bloque o elemento seleccionado. Los
controles profundos pueden abrir una sheet contextual, pero esa sheet es una
extensión in-page: el canvas y su contexto siguen montados y visibles.

### 4.7 Capacidad compartida, owner compartido

Si dos bloques pueden editar imagen, foco, tipografía, acción, spacing,
visibilidad o color, consumen el mismo owner y el mismo contrato. Un bloque sólo
crea UI propia cuando la capacidad es realmente exclusiva de su dominio.

### 4.8 Design define los valores visuales

Este plan define arquitectura, estados, información, lógica y flujos. No fija
colores, radios, sombras, alturas ni geometrías visuales nuevas. Claude debe
diseñar las superficies en un canvas dedicado y entregar esos valores por
DesignSync antes de implementarlos.

## 5. Modelo conceptual de autoría

### 5.1 Contexto único

El editor necesita un owner equivalente a:

```dart
WebsiteAuthoringContext(
  hostClass: AuthoringHostClass.desktop | phone,
  previewViewport: WebsiteViewport.desktop | tablet | mobile,
  writeScope: WebsiteWriteScope.shared | viewport,
)
```

Los nombres finales pueden cambiar. El contrato no:

- `hostClass` decide la composición de herramientas;
- `previewViewport` decide el ancho y el valor efectivo mostrado;
- `writeScope` decide si una operación actualiza base o un override.

Cambiar uno no muta silenciosamente los otros. Sí se permiten defaults UX
seguros: en un host teléfono, al editar una propiedad visual responsive, el
alcance inicial recomendado es el override móvil; una propiedad `sharedOnly`
ignora ese default y sigue escribiendo la base.

Desktop no tiene un slot de override separado: **es la base**. Cuando
`previewViewport == desktop`, `writeScope: viewport` es inválido y se coacciona
a `shared`. La UI mantiene visible el alcance, deshabilitado, con una razón
legible; no lo oculta ni simula una personalización desktop que no puede
persistir.

### 5.2 Owner único de breakpoints

Todo Website Builder usará el owner responsive canónico del producto:

| Clase | Contrato |
|---|---|
| Teléfono | ancho lógico `< 600` |
| Tablet | ancho lógico `600–899` |
| Desktop | ancho lógico `>= 900` |

Las cifras ya pertenecen a las guías del producto; no son valores visuales
inventados por este plan. Los consumidores no vuelven a declarar 600, 640, 900
o 1024 localmente para decidir la misma clase.

Si un bloque necesita un ajuste interno por contenido, ese umbral no puede
cambiar su viewport semántico ni su persistencia responsive.

### 5.3 Valor responsive tipado

El modelo conceptual es:

```dart
ResponsiveValue<T>(
  shared: T,
  overrides: {
    WebsiteViewport.tablet: T?,
    WebsiteViewport.mobile: T?,
  },
)
```

No es obligatorio exponer esta clase literalmente en todo el JSON. Sí es
obligatorio que exista un resolver tipado y una representación canónica única.

Operaciones mínimas del owner:

- `resolveResponsiveProperty(...)`;
- `setSharedProperty(...)`;
- `setResponsiveProperty(...)`;
- `clearResponsiveOverride(...)`;
- `hasResponsiveOverride(...)`.

`copyViewportOverrides(...)` es una mejora posterior. No forma parte del
primer vertical slice ni del contrato mínimo de persistencia.

Todas pasan por la transacción, history, dirty state, draft y save existentes.
No habrá un segundo store de estado para el inspector responsive.

### 5.4 Política por propiedad

`WebsiteBlockFieldSchema` —o el registry canónico que lo alimente— declarará la
política de cada propiedad:

| Política | Significado | Ejemplos |
|---|---|---|
| `sharedOnly` | Nunca diverge por viewport | ID, producto/categoría, destino CTA, alt text, semántica de negocio |
| `responsiveOptional` | Valor común con override deliberado | asset para art direction, foco, fit, alineación, spacing, tamaño visual |
| `responsiveVisibility` | Estado independiente por viewport | mostrar/ocultar bloque o capa |
| `perViewportGeometry` | Geometría propia por viewport | x/y/w/h, layout Canvas, columnas |
| `responsiveDisplayCopy` | Copy corto excepcional autorizado a divergir | lista blanca inicialmente vacía |

`responsiveDisplayCopy` será una lista blanca que **nace vacía**. Cada entrada
requiere un caso demostrado que no se resuelva con tipografía, ancho, layout o
spacing. No habilita duplicar contenido de negocio indiscriminadamente. Alt
text, destino, binding de producto, precios, inventario y otros datos
semánticos permanecen compartidos.

El valor base es la verdad canónica para HTML inicial, metadata, JSON-LD,
imagen social, sitemap, Merchant y cualquier consumidor sin viewport. Los
overrides son presentación. Una imagen ligada a producto no admite cambiar de
sujeto por viewport: usa el asset compartido, o como máximo un reencuadre del
mismo sujeto. Esta misma limitación aplica a art direction cuando el alt text
es compartido.

El schema también debe declarar:

- familia de propiedad (`media`, `typography`, `geometry`, `visibility`, etc.);
- superficies admitidas (`inline`, `contextSheet`, `inspector`);
- si el control admite reset/copy;
- si la propiedad es compatible con migración legacy;
- label y descripción de intención, no el nombre de la clave serializada.

El capability profile de un bloque se deriva de estas declaraciones cuando sea
posible. No se mantendrán dos inventarios manuales que puedan divergir.

## 6. Persistencia y compatibilidad

### 6.1 Formato canónico recomendado

Se recomienda una estructura anidada por owner —bloque, slide, item o capa—:

```json
{
  "title": "Texto común",
  "focalPointX": 0.5,
  "responsive": {
    "mobile": {
      "focalPointX": 0.72,
      "headline": "Texto móvil opcional"
    }
  }
}
```

Razones:

- hace visible qué es override;
- permite reset sin adivinar aliases;
- evita proliferar `mobileFoo`, `fooMobile`, `foo@mobile` y booleanos dobles;
- permite validar políticas del schema antes de guardar;
- conserva una identidad común;
- simplifica inspección, migración y pruebas de round-trip.

El nombre exacto se cierra con el codec, pero no llevará prefijo `_`: ese
prefijo comunica dato privado/transitorio y vuelve probable que un sanitizer o
consumidor futuro lo descarte. Se descarta como formato objetivo seguir
agregando claves planas por cada viewport.

Invariantes de normalización:

- no existen mapas de viewport vacíos;
- no existe `responsive` vacío;
- escribir un override igual a la base se normaliza a “sin override”;
- `clearResponsiveOverride` elimina la propiedad y también el mapa de viewport
  cuando queda vacío;
- crear y restablecer un override produce igualdad profunda con el documento
  original y no deja `Guardar` habilitado.

### 6.2 Adaptadores legacy

La lectura reconocerá temporalmente:

- `mobileFocalPointX/Y`;
- `mobileBgAlignment`;
- `mobileDesignWidth`;
- `hideOnMobile/showOnMobile`;
- mapas legacy de visibility;
- aliases de imágenes desktop/mobile;
- pares Canvas `_desktop` / `_mobile`.

El flujo será:

```text
JSON legacy → adaptador normalizado → resolver canónico → Edit/Preview/Public
```

La selección o el preview nunca migran datos. La escritura canónica ocurre sólo
en una operación de edición/guardado explícita y queda cubierta por undo y
round-trip.

### 6.3 Requisitos de migración

- preservar IDs de páginas, bloques, slides, items y capas;
- preservar resultado visual exacto por viewport antes y después;
- migración versionada, idempotente y reejecutable;
- lectura backward-compatible durante el rollout;
- no borrar aliases hasta probar ausencia de consumidores activos;
- inventariar bloques con visibility no uniforme antes de cambiar 640/1024;
- mantener semántica 640/1024 para documentos legacy mediante versión/adaptador
  hasta una migración explícita a 600/900;
- comparar salida visible a 620 y 1000 antes y después; los generadores SEO sin
  viewport siguen usando la base, pero también se verifica ese no-impacto;
- extender el sanitizer type-aware a la estructura `responsive`, sin un scrub
  recursivo indiscriminado que pueda borrar datos autorales;
- realizar copia profunda de mapas anidados antes de sanear o normalizar;
- impedir que selección, `activeElementId` u otra clave transitoria sobreviva
  dentro de un override;
- rollback sin pérdida de contenido;
- no escribir producción antes de una autorización separada y el contrato de DB.

## 7. Universal Responsive Field Protocol

### 7.1 `ResponsiveFieldShell`

El componente central no reemplaza `WebsiteMediaPicker`, `FocalPointPicker`,
el editor de acciones, inputs o selectores. Los envuelve y les entrega:

- viewport actual;
- valor base;
- valor efectivo;
- override del viewport;
- estado legible (`Común`, `Heredado`, `Sólo móvil`, etc.);
- acción `Personalizar para este viewport`;
- acción `Restablecer al común` sólo cuando existe override;
- acción posterior opcional `Copiar desde...`;
- operación de escritura correcta según schema y `writeScope`.

El control interior no conoce claves legacy ni decide dónde persistir. De este
modo, mejorar el picker o el estado de herencia mejora todas las familias.

### 7.2 Bindings de presentación inline

`WebsiteBlockContentPresenters` se ampliará con bindings que nombren la
propiedad y su política. Un presenter no recibirá sólo un callback de “cambiar
imagen”; recibirá el contexto suficiente para escribir la propiedad canónica
sin inventar claves de bloque.

Capacidades iniciales:

- texto compartido o display-copy autorizado;
- asset y art direction;
- foco/crop/fit;
- acción y destino;
- visibilidad;
- geometría y transform para Canvas;
- spacing y alineación;
- collections/repeaters cuando el bloque lo requiera.

### 7.3 Controles universales prioritarios

| Capacidad | Owner objetivo | Consumidores iniciales |
|---|---|---|
| Media responsive | `ResponsiveMediaField` + picker canónico | schema, Carousel, Canvas, Hero, Gallery, banners |
| Foco y encuadre | focal owner único sobre imagen/canvas real | covers, media fields, Canvas |
| Texto inline responsive | presenter + toolbar compartido | Hero, Carousel, CTA, Text, Canvas |
| Acción | action editor + presenter compartido | Hero, Carousel, CTA, Pricing, Button, Canvas |
| Visibilidad | field shell + resolver | bloque, item, slide, capa |
| Layout/spacing | controles semánticos compartidos | familias de bloque y Canvas |
| Colecciones | navigator compartido | slides, testimonios, FAQ, equipo, logos, categorías |

No se crearán variantes visuales feature-locales de componentes existentes.
Cada owner visual se trazará a la guía de componentes por su ID.

## 8. Experiencia desktop objetivo

### 8.1 Selector de viewport

El editor tendrá un selector visible y estable:

```text
Escritorio | Tablet | Móvil
```

La implementación visual se basará en `S-04 VbSegmented` sólo después de leer
su spec vigente con DesignSync. El selector cambia coordinadamente:

- ancho del canvas;
- guías y safe area;
- valor efectivo renderizado;
- estado de Layers;
- propiedades pertinentes del inspector;
- label de alcance.

No borra selección, scroll ni draft.

### 8.2 Alcance de escritura explícito

El usuario verá una autoridad separada del viewport, con copy final definido
por Design. Semánticamente será:

```text
Base | Personalizar este viewport
```

La autoridad efectiva está en cada `ResponsiveFieldShell`, no en un modo global
oculto. El contexto general sólo muestra y fija el **default** para las próximas
operaciones. Cada campo atribuye dónde aterrizará el cambio y permite
cambiar/resetear la excepción de forma reversible. En Desktop, personalizar
este viewport está deshabilitado porque Desktop es la base.

### 8.3 Inspector consciente del viewport

- Desktop no despliega controles móviles completos por defecto.
- Un campo heredado muestra un resumen compacto y una acción para personalizar.
- Un override móvil no se pierde cuando se vuelve a desktop; aparece como badge
  o resumen en el grupo correspondiente.
- Ir al override cambia el viewport y preserva el bloque/campo seleccionado.
- El inspector mantiene Content / Design / Style y progressive disclosure.
- Repetidores muestran overview + un item activo, nunca todos expandidos.
- Las propiedades compartidas siguen editables sin aparentar pertenecer a un
  viewport particular.

### 8.4 Comparación

Una vista de comparación opcional permite ver dos viewports en paralelo:

- uno activo para escribir;
- otro read-only;
- selección enlazada;
- scroll enlazado cuando sea estable;
- diferencias/overrides resaltados;
- sin duplicar la instancia de estado editable ni crear dos drafts.

La comparación es productividad posterior; no bloquea Fase 0 ni el primer
vertical slice y no necesita un frame Design en el primer handoff.

### 8.5 Layers y navegación de contexto

Layers indica:

- visible/oculto en el viewport actual;
- override presente;
- elemento heredado;
- identidad compartida;
- acción para saltar al viewport donde existe una personalización.

Un elemento oculto sigue seleccionable y reparable en Edit. Preview y público
respetan su visibilidad resuelta.

## 9. Experiencia de autoría desde teléfono

### 9.1 Regla principal

En un teléfono, el Website Builder no abre un inspector lateral ni navega a un
formulario separado del preview. El canvas permanece montado durante toda la
operación. La edición es inline, in-page e in-block.

“Inline” no significa que cada control de precisión deba vivir permanentemente
sobre la imagen. Significa que toda edición nace en el objeto real, conserva su
contexto y vuelve a él sin cambiar de ruta o reconstruir el documento.

### 9.2 Tres capas de interacción

#### Capa 1 — manipulación directa

- tap selecciona bloque o elemento;
- segundo tap restaura/mantiene contexto;
- texto y CTA se editan sobre el contenido;
- reemplazo de imagen nace en la imagen;
- el foco se mueve directamente sobre el encuadre real;
- Canvas permite mover/resize/rotate con handles touch-safe cuando corresponda;
- ninguna herramienta modifica la geometría publicada por existir en Edit.

#### Capa 2 — dock contextual

Un dock compacto acompaña la selección y expone sólo acciones frecuentes:

- identidad del bloque/elemento;
- viewport y alcance actuales;
- undo/redo;
- mover arriba/abajo;
- duplicar;
- visibilidad;
- acceso a más opciones.

Los targets táctiles cumplen al menos 48 px. Drag/reorder siempre tiene una
alternativa accesible de mover arriba/abajo.

#### Capa 3 — sheet contextual

Controles profundos usan una sheet con detents, no una página nueva:

- el canvas continúa visible;
- el bloque activo permanece identificado;
- la sheet respeta SafeArea y teclado;
- se restaura foco y scroll al cerrar;
- el canvas puede desplazarse para mantener visible el elemento editado;
- sólo existe un scroll owner principal por superficie enfocada;
- cambiar entre grupo, viewport o propiedad no desmonta el documento.

La anatomía y geometría visual se definirán en Design. No se fija un porcentaje
de pantalla desde este plan.

### 9.3 Texto y teclado

- toolbar de texto inmediatamente sobre el teclado;
- campo activo desplazado fuera de `viewInsets`;
- Enter, Done y cancelación con semántica consistente;
- cerrar teclado no cancela silenciosamente el cambio;
- cambiar de propiedad preserva selección;
- dirty state e history se actualizan por operaciones, no por focus/selección.

### 9.4 Foco de imagen en el contenido real

El flujo objetivo no muestra tres thumbnails grandes:

1. la imagen del bloque es el preview principal;
2. `Cambiar imagen` abre el picker universal;
3. `Reencuadrar` activa el pin/gesto de foco sobre esa misma imagen;
4. el viewport actual decide qué foco efectivo se muestra;
5. si móvil hereda, se muestra `Heredado` y `Personalizar para móvil`;
6. restablecer elimina el override, no copia números;
7. alt text permanece compartido.

En desktop, el inspector muestra una fila compacta de media y estado, no una
segunda galería paralela al canvas.

### 9.5 Scope seguro en teléfono

Default recomendado:

- propiedades visuales responsive: override móvil;
- propiedades `sharedOnly`: común;
- display copy: común salvo campo explícitamente autorizado y acción deliberada
  `Personalizar copy móvil`;
- nunca convertir automáticamente bindings, destinos, alt text o datos de
  negocio en overrides móviles.

### 9.6 Continuidad

Se debe preservar al abrir/cerrar controles o cruzar un breakpoint:

- ruta y página;
- bloque, item, slide y capa activos;
- posición de scroll;
- viewport y alcance;
- draft y dirty state;
- teclado/focus cuando sea válido;
- inspector/sheet y grupo contextual;
- undo/redo.

### 9.7 Dependencias bloqueantes del host teléfono

El flujo inline no puede empezar sobre el chrome desktop actual. Estas
dependencias forman parte del plan, con owner explícito:

| Dependencia | Owner objetivo | Cierre mínimo |
|---|---|---|
| Barra superior adaptable | `WebsiteEditorChromeLayout` sobre el shell existente | identidad, modo y acción segura visibles; el resto en overflow contextual |
| Geometría del editor | un owner compartido consumido por `PublicStoreLayout`, `PersistentEditorShell`, panel normal y deferred | reemplazar las cuatro constantes independientes de 380 px |
| SafeArea y teclado | shell del host teléfono | un solo inset owner, `viewInsets` y scroll-to-focus sin doble SafeArea |
| Densidad y touch | componente/density owner universal | chrome y handles táctiles de al menos 48 px; sin hover-only |
| Borrador durable | `WebsiteEditorDraftStore` integrado al provider/save coordinator | snapshot local tenant+página, sanitizado, versionado, con fingerprint/epoch y restaurar/descartar explícito |

El borrador durable es prerequisito de salida móvil. History en memoria no
protege contra recarga, suspensión o desalojo del proceso. No se aceptará una
ventana conocida de pérdida de trabajo como estado final de Fase 5.

## 10. Tablet

Tablet es una transición deliberada, no una tercera aplicación que diluya la
prioridad del teléfono.

- Usa el mismo modelo de propiedades y resolver.
- Hereda directamente de la base por defecto.
- Admite override tablet cuando exista una necesidad real.
- El modelo de datos soporta tablet desde Fase 1; una UI completa de overrides
  tablet no bloquea el primer rollout desktop + teléfono.
- Puede usar inspector colapsable/split pane si el ancho mantiene canvas y
  controles útiles; de lo contrario usa la composición contextual del teléfono.
- El cruce 899/900 no desmonta una edición mutable.
- `T-05 VbSplitPane/VbCollapsiblePane` es una referencia de componente a
  validar con DesignSync, no una geometría ya aprobada.

## 11. Arquitectura de renderer y paridad

La cadena objetivo es única:

```text
datos persistidos
    ↓
adaptador legacy + normalización
    ↓
resolver responsive canónico
    ↓
modelo de contenido efectivo
    ↓
renderer compartido
    ├── Edit: presenters + selección + chrome
    ├── Preview: interacción visitante, sin escritura
    └── Público: interacción visitante, datos guardados
```

Reglas:

- ningún renderer lee directamente una clave legacy;
- ningún inspector calcula un fallback distinto al renderer;
- el canvas de Edit no sustituye valores “para que se vea bien”;
- Preview no reutiliza flags de Edit para desactivar interacción visitante;
- theme, CTA, media, geometry, clipping y responsive se resuelven antes del
  wrapper de edición;
- las tres superficies consumen el mismo valor efectivo para el mismo viewport.
- la clase responsive se deriva del **ancho lógico del lienzo** en Edit, del
  frame seleccionado en Preview y del viewport visitante en público; nunca de
  la ventana host del ERP. Una ventana desktop con inspector abierto puede
  contener un lienzo tablet y debe renderizarlo como tablet.

## 12. Canvas: migración estructural

Canvas es el caso de mayor riesgo y no debe definir el modelo general mediante
sus excepciones.

Objetivo:

- una sola identidad por layer;
- contenido compartido por defecto;
- geometría, visibilidad, foco y presentación como overrides tipados;
- copy móvil sólo si el campo está permitido;
- renderer y handles usan el mismo espacio de coordenadas;
- selección transitoria fuera del documento persistido.

Los pares `title_desktop/title_mobile`, capas duplicadas o listas completas por
dispositivo se migran después de probar el resolver con bloques menos complejos.
La migración de Canvas debe:

- emparejar identidades sin adivinar cuando no exista correspondencia segura;
- preservar z-order, bindings y destinos;
- demostrar equivalencia de geometría y clipping;
- ser idempotente y reversible;
- mantener lectura legacy durante el rollout.

Los documentos ambiguos quedan marcados para revisión y siguen renderizando por
el adaptador; no se fusionan destructivamente. Ese estado debe ser visible en
Layers/inspector, explicar por qué no se migró y ofrecer un flujo deliberado de
resolución; no puede existir sólo en logs.

## 13. Diseño requerido antes de implementar UI

Claude debe crear o completar un canvas dedicado del Website Builder. La guía
general sólo aporta componentes compartidos; no sustituye el diseño del editor.

Referencias ya localizadas en `ERP Bikeshop UI Mockups`:

- `S-04 VbSegmented` — selector de viewport/estado;
- `T-05 VbSplitPane / VbCollapsiblePane` — posible composición adaptable;
- `F-06 VbDensity` — densidad, cuando corresponda.

El handoff de Design debe incluir, como mínimo:

| Superficie | Estados obligatorios |
|---|---|
| Desktop authoring | desktop/tablet/móvil; común/heredado/override; light/dark |
| Inspector de media | heredado, override, reemplazo, foco, error/loading |
| Layers | visible, oculto, heredado, override, selección anidada |
| Phone inline | selección, edición de texto, media/foco, CTA, reorder |
| Phone sheet | cerrada, detents, teclado abierto, error, confirmación |
| Tablet | split válido y fallback contextual |
| Canvas legacy ambiguo | estado visible, explicación y resolución deliberada |

Cada superficie llega en claro, oscuro y compacto 390, con valores legibles por
DesignSync y un `handoff-t<N>` trazable. Si un valor no es legible, no se
estima. El gate se marca bloqueado con el ID/archivo exacto y Design republica
el artefacto legible; no se mantiene al agente esperando indefinidamente ni se
rellena el valor por criterio propio.

## 14. Plan de implementación por fases

Las fases son verticales y tienen gates. No se abrirá una auditoría completa
nueva entre fases: sólo se investiga una brecha nueva, concreta y evidenciada.

### Fase 0 — Dirección visual y contrato de producto

**Lead:** Claude  
**Cross-review:** Codex

Entregables:

1. canvas dedicado y handoff Design de las superficies de la sección 13;
2. vocabulario final de viewport, común, heredado, override y reset;
3. flujos desktop, teléfono y tablet;
4. mapa componente → ID de la guía → rol semántico;
5. matriz de propiedades aprobada;
6. comportamiento de phone inline y sheet contextual;
7. decisiones explícitas sobre display copy responsive.

Gate:

- DesignSync entrega todos los valores visuales;
- claro, oscuro y 390 existen;
- Codex valida que el diseño conserve state, navegación, acciones canónicas,
  touch, keyboard, SafeArea y paridad;
- cualquier valor ilegible vuelve a Design con su referencia exacta; no se
  estima y tampoco deja una espera abierta sin owner;
- no existe un panel lateral comprimido como solución móvil.

### Fase 1 — Fundación de verdad responsive

**Lead:** Codex  
**Cross-review:** Claude sobre semántica del estado

Entregables:

1. owner único de `WebsiteViewport` y breakpoints;
2. modelo/resolver responsive tipado;
3. políticas por propiedad;
4. adaptadores legacy de lectura;
5. operaciones provider mínimas para set/clear/resolve;
6. integración con history, dirty state, draft y save;
7. serialización canónica probada, todavía sin migración productiva;
8. normalización sin mapas vacíos ni overrides iguales a la base;
9. sanitizer type-aware y copia profunda para la estructura responsive;
10. inventario de visibility no uniforme y estrategia versionada para las
    bandas 600–639 y 900–1023.

Gate:

- tests de resolución `override actual ?? shared`;
- tests de reset y ausencia de cascada móvil/tablet;
- crear y resetear un override devuelve igualdad profunda y dirty=false;
- ninguna clave transitoria sobrevive dentro de `responsive`;
- mismos valores en Edit/Preview/Public;
- documentos legacy conservan 640/1024 hasta migración explícita; documentos
  canónicos usan 600/900 sin mezclar semánticas;
- canarios visibles 620 y 1000 pasan antes de habilitar la nueva versión;
- ninguna lectura o cambio de preview muta datos.

### Fase 2 — Protocolo universal de controles

**Lead visual/interacción:** Claude  
**Lead de API/estado:** Codex

Entregables:

1. `ResponsiveFieldShell`;
2. metadata responsive en registry/schema;
3. bindings scoped de presenters;
4. badges/labels accesibles de herencia y override;
5. reset compartido; copy queda diferido;
6. guards contra controles feature-locales duplicados;
7. capability matrix derivada y completa para 24 tipos.

Gate:

- el mismo control puede montar shared/inherited/override sin conocer el bloque;
- estado comprensible sin color;
- keyboard, pointer y touch cubiertos;
- ningún control escribe una clave serializada directamente fuera del owner.

### Fase 3 — Shell mínimo de teléfono + vertical slice de media y foco

**Lead:** Claude en UX; Codex en datos e integración

Primeros consumidores:

- schema genérico;
- Carousel;
- Hero;
- Canvas como consumidor, sin migrar todavía su modelo completo.

Entregables:

1. detección de `hostClass`;
2. owner único de geometría del editor y barra superior adaptable;
3. contenedores mínimos de dock y sheet;
4. plumbing de SafeArea, `viewInsets`, focus y scroll;
5. density/touch contract del chrome compacto;
6. borrador local durable, sanitizado y restaurable;
7. un `ResponsiveMediaField`;
8. un picker canónico;
9. foco/fit/crop sobre el canvas real;
10. shared asset + art direction limitada al mismo sujeto;
11. alt text compartido;
12. eliminación de las tres composiciones duplicadas;
13. desktop viewport/scope y primer flujo phone inline para esta capacidad.

Gate:

- el screenshot que originó el plan ya no puede reproducirse;
- desktop no muestra dos editores de foco completos simultáneamente;
- phone puede reemplazar/reencuadrar sin salir de la página;
- barra, panel, SafeArea, touch y draft durable cierran los prerequisitos de
  §9.7;
- Edit = Preview = Público después de save/reload;
- legacy focus conserva resultado exacto.

### Fase 4 — Autoría desktop completa

**Lead:** Claude  
**Cross-review:** Codex

Entregables:

1. selector de viewport;
2. alcance común/viewport;
3. inspector consciente de herencia;
4. Layers con estados responsive;
5. preserve selection/scroll/draft;
6. comparación read-only si el vertical slice demuestra su valor;
7. responsive controls para tipografía, spacing, layout, alineación,
   visibilidad y CTA presentation.

Gate:

- el usuario puede explicar qué cambiará antes de operar;
- cada override puede localizarse y resetearse;
- no hay controles irrelevantes expandidos para otro viewport;
- cruzar desktop/tablet/móvil no pierde contexto ni crea history.

### Fase 5 — Host de teléfono inline

**Lead:** Claude  
**Lead de estado/integración:** Codex

Esta fase se ejecuta antes de migrar masivamente las 24 familias. Así las
familias se migran una vez contra las superficies finales desktop + phone.

Entregables:

1. selección y chrome compacto;
2. dock contextual;
3. sheet contextual con detents;
4. texto/CTA/media/foco inline;
5. reorder touch y acciones alternativas;
6. teclado, focus, SafeArea y scroll owner;
7. preservation de draft/selection/viewport/writeScope;
8. Semantics estables para automatización.

Gate:

- flujo completo a ~390×844: abrir editor, seleccionar, editar texto, cambiar
  imagen, ajustar foco, modificar una presentación móvil, reordenar, undo,
  Preview y guardar/reabrir en fixture autorizada;
- ninguna operación obligatoria depende de hover;
- targets de al menos 48 px;
- la sheet no desmonta ni oculta por completo el objeto editado;
- teclado no cubre el control ni la acción principal.
- suspender/reabrir o recargar ofrece restaurar el draft sanitizado y no pierde
  trabajo sin aviso.

### Fase 6 — Migración de las 24 familias

**Lead de implementación visual:** Claude  
**Owner de contratos y aceptación:** Codex

Orden recomendado:

1. campañas/covers: Hero, Carousel, CTA, Video Banner, Partners Banner;
2. elementos simples: Text, Button, Divider;
3. catálogo: Products, Category Grid, Brand Logos;
4. colecciones: Gallery, Testimonials, Google Reviews, Team, FAQ;
5. contenido: Services, About, Features, Stats;
6. conversión/especiales: Pricing, Contact, Footer;
7. Canvas se cierra en su fase estructural.

Al migrar Category Grid, Video Banner, Partners Banner y Brand Logos se retiran
las cuatro clases bespoke muertas sólo después del guard de referencias.

Cada lote entrega simultáneamente:

- desktop Edit;
- phone Edit;
- Preview y público;
- light/dark;
- shared/override/reset;
- save/reload;
- pruebas de capability matrix.

Gate:

- ninguna familia queda en fallback accidental;
- ninguna capacidad compartida tiene implementación privada;
- 24/24 registradas con políticas completas;
- la migración de una familia no cambia semántica de negocio.

### Fase 7 — Migración Canvas

**Lead de interacción/visual:** Claude  
**Lead de migración/geometry:** Codex

Entregables:

1. una identidad por layer;
2. overrides tipados de geometry/visibility/media/presentation;
3. adaptador de pares desktop/mobile;
4. migración versionada e idempotente;
5. resize/rotate/focal en desktop y touch;
6. clipping y coordinate spaces compartidos;
7. documentos ambiguos preservados sin fusión destructiva.

Gate:

- equivalencia visual exacta antes/después en los tres viewports;
- z-order, bindings, CTA e IDs preservados;
- undo/save/reload válidos;
- 100%, 80% y canvas escalado pasan interacción en los cuatro bordes;
- rollback probado.

### Fase 8 — Hardening, documentación y rollout

**Lead:** Codex  
**Final visual review:** Claude

Entregables:

1. matriz completa automatizada e interactiva;
2. guard estático de breakpoints y aliases legacy;
3. guard de registry/capability/policy para 24 tipos;
4. documentación canónica actualizada;
5. feature flags y rollback;
6. migración gradual sólo con autorización;
7. cierre visual en app real por Claude.

Gate:

- Definition of Done de la sección 19;
- no deuda P0/P1 abierta;
- publicación, si se solicita, tiene autorización y verificación separadas.

## 15. Matriz de verificación

### 15.1 Anchuras y estados

| Clase del lienzo | Canarios |
|---|---|
| Teléfono | ~390×844; 599; legacy 620 |
| Transición teléfono/tablet | 599 → 600 → 599 |
| Tablet | 600, ancho representativo, 899; legacy 1000 |
| Transición tablet/desktop | 899 → 900 → 899 |
| Desktop | 900, 1440; zoom de app 80% y 100% cuando corresponda |

Las mediciones usan el ancho lógico **del lienzo**, no el ancho de la ventana
ERP. DPR o zoom no cambian la clase de un teléfono real. La matriz incluye el
caso normal “ventana host desktop >=900 con lienzo <900 por inspector/rails” y
demuestra que el bloque sigue la clase del lienzo.

### 15.2 Modos

Para cada capacidad migrada:

```text
Edit(shared)
Edit(inherited)
Edit(override)
Preview
Público guardado
save/reload
light/dark
desktop/tablet/phone
```

### 15.3 Interacciones

- primera y segunda selección;
- selección anidada slide/item/layer;
- inline → control profundo → inline;
- set override → reset; copy sólo cuando entre en una fase posterior;
- cambiar viewport con draft limpio y dirty;
- undo/redo por operación;
- teclado Enter/Space/focus y virtual keyboard;
- touch y alternativa a drag;
- sheet/menu abierto al cruzar breakpoint;
- scroll y selección después de retorno;
- ocultar/reparar elemento en Edit;
- Preview visitor interaction;
- save/reload/público.

### 15.4 Datos legacy

- cada alias reconocido;
- precedencia determinista;
- semántica legacy probada a 620 y 1000;
- inventario de visibility no uniforme antes de activar 600/900;
- lectura legacy sin escritura;
- migración idempotente;
- resultado visual equivalente;
- round-trip sin perder claves desconocidas;
- rollback;
- Canvas ambiguo sin fusión automática.

### 15.5 Automatización mínima

- unit tests de resolver/policy/serialization;
- widget tests del field shell;
- smoke parametrizado para 24 tipos;
- host desktop y host teléfono realistas;
- Edit/Preview/Public parity tests;
- tests de 599/600 y 899/900;
- tests de 620 y 1000 para compatibilidad legacy;
- host desktop ancho con canvas efectivo tablet;
- tests de keyboard/SafeArea/sheet;
- goldens o screenshots estructurados de estados Design aprobados;
- smoke real en browser y, cuando aplique, iOS Simulator.

## 16. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Un cuarto modelo de claves responsive | deuda y paridad rota | formato canónico + adaptadores; no más aliases locales |
| Migrar Canvas demasiado pronto | pérdida/alteración de campañas | pilotar resolver en bloques simples; Canvas separado y reversible |
| Phone editor convertido en formularios | pérdida de contexto y baja usabilidad | canvas montado, inline first, sheet contextual |
| Un control responsive por bloque | regresiones y velocidad baja | protocol universal + guards + capability matrix |
| Copy o datos de negocio divergentes | inconsistencia semántica | `sharedOnly` por defecto y display-copy en lista blanca |
| Tablet multiplica el trabajo | demora sin valor | transición deliberada; mismo resolver; override opcional |
| Visuales inventados durante código | incoherencia y dark mode roto | canvas dedicado + DesignSync antes de implementar |
| Feature flag duplica owners indefinidamente | dos editores permanentes | rollout con fecha/gate de retiro y static guards |
| Tests sólo de renderer | phone host sigue inutilizable | matriz de autoría real a ~390 px |
| Cambiar viewport crea history | undo ruidoso | preview/selection transitorios fuera del documento |
| Override invisible | usuario no confía en el resultado | estado textual, jump, reset y Layers awareness |
| Cambiar 640/1024 altera contenido visible | bloques aparecen/desaparecen en 620 o 1000 | adapter versionado, inventario y migración explícita |
| Draft sólo en memoria en teléfono | pérdida al suspender/recargar | store local sanitizado, scoped y restaurable antes del rollout móvil |
| Host window decide el breakpoint del bloque | canvas tablet renderiza como desktop | derivar clase del ancho lógico del lienzo |
| Full audit loop por cada defecto | días de retraso | rondas acotadas por fase y sólo reabrir evidencia nueva |

## 17. Decisiones adoptadas y decisiones de producto

### 17.1 Adoptadas por este plan

- Teléfono se diseña inline/in-page; no inspector lateral.
- La sheet contextual está permitida sólo como extensión que conserva canvas.
- Tablet hereda directamente de la base; no hereda de móvil.
- Un override resuelve directamente sobre la base.
- Persistencia objetivo estructurada; aliases planos quedan sólo en adaptadores.
- Phone host adelanta su implementación antes de migrar masivamente familias.
- No se fijan valores visuales sin DesignSync.
- Se permite art direction por viewport sólo para reencuadrar el mismo sujeto;
  media ligada a producto conserva el asset compartido.
- Alt text, bindings, destinos y datos de negocio son compartidos.
- El valor base es la verdad de HTML indexable, metadata, JSON-LD, social y
  Merchant.

### 17.2 Recomendación sobre copy móvil

La lista blanca comienza vacía. Sólo se agrega un campo de presentación cuando
un caso real demuestra que tipografía, ancho, layout y spacing no resuelven la
composición. Aun entonces, se limita a headline o subtítulo corto explícito y
el valor base sigue siendo la verdad indexable. Body copy semántico, alt text,
precios, producto, categoría, CTA destination y metadatos de negocio
permanecen compartidos.

Esta política equilibra composición real con coherencia editorial y evita que
la tienda se convierta en tres contenidos independientes.

### 17.3 Lo que puede decidirse durante Design sin detener al dueño

- copy exacto de labels y estados;
- ubicación y progresive disclosure de controles;
- cuándo tablet usa split pane versus sheet;
- anatomía del dock y de la sheet;
- qué comparación entra en el primer rollout;
- orden de controles dentro de una familia.

Siempre dentro de los invariantes de este plan y las guías canónicas.

## 18. Protocolo de colaboración y velocidad

Para evitar repetir ciclos de varios días:

1. una sola dirección Design para la fase;
2. un paquete de evidencia acotado;
3. Claude define interacción y looking con DesignSync;
4. Codex cierra contrato, datos, migración y criterios;
5. ownership de archivos explícito y sin writers concurrentes;
6. una implementación coherente por vertical slice;
7. autor congela (`FREEZE`);
8. revisor ejecuta diff, analyzer, tests y app real;
9. sólo se reabre con un error concreto reproducible;
10. cada aprendizaje durable actualiza su contrato owner.

No se crea un nuevo chat/agente por defecto. Se continúa la misma sesión
mientras tenga contexto suficiente; un handoff es recuperación, no ritual.

### 18.1 Partición de ownership por fase

Antes de cada fase se reemplaza esta matriz de familias por una lista exacta de
archivos bloqueados. Ningún writer empieza sin ese lock.

| Fase | Writer principal | Paths/familias que reserva | Revisor read-only |
|---|---|---|---|
| 0 | Claude Design | canvas y `handoff-t<N>` de Design; sin source Flutter | Codex |
| 1 | Codex | modelos/registry/codec, provider, sanitizer y tests de datos | Claude |
| 2 | secuencial: Codex API, luego Claude UI | schema/capability/presenters; después field shell y tests visuales | agente no-writer |
| 3 | secuencial por boundary | Codex: chrome/state/draft; Claude: media/foco/phone interaction | agente no-writer |
| 4 | Claude | shell/inspector/Layers desktop ya sobre APIs congeladas | Codex |
| 5 | Claude + Codex por capas separadas | Claude: composición phone; Codex: persistencia, insets, state y guards | revisión cruzada |
| 6 | Claude por lote | renderer/control/tests de la familia declarada | Codex |
| 7 | Codex migración; Claude interacción | codec/migración separados de Canvas UI/handles | revisión cruzada |
| 8 | Codex | gates, docs, flags, migración autorizada | Claude visual final |

Si un archivo concentra capas de ambos owners —en especial
`public_store_layout.dart`— las rondas son secuenciales con `FREEZE`, nunca
simultáneas.

## 19. Definition of Done

El refactor responsive del Website Builder termina sólo cuando:

1. existe un solo owner de breakpoints y viewport semántico;
2. existe un solo resolver de propiedades responsive;
3. las 24 familias declaran políticas por propiedad;
4. no quedan controles responsive duplicados por familia para capacidades
   compartidas;
5. cada campo muestra en texto si es común, heredado u override;
6. cambiar viewport preserva selección, scroll y draft sin crear history;
7. cada override se puede localizar y restablecer; copiar es una mejora
   posterior, no un requisito de salida inicial;
8. Edit, Preview y público resuelven lo mismo para el mismo viewport;
9. save/reload conserva esa paridad;
10. el host teléfono permite editar end-to-end sin salir del canvas;
11. ningún flujo obligatorio depende de hover o de targets menores de 48 px;
12. teclado, SafeArea, focus, sheets y scroll pasan la matriz compacta;
13. Canvas usa identidades compartidas y overrides, no twins como modelo
    principal;
14. legacy sigue legible y su migración es idempotente/reversible;
15. los documentos legacy conservan su visibilidad en 620/1000 hasta una
    migración explícita;
16. el host móvil restaura un draft durable tras suspensión/recarga;
17. claro, oscuro, desktop, tablet y móvil tienen evidencia real;
18. no existen valores visuales nuevos sin source Design trazable;
19. capability matrix y static guards cubren las 24 familias;
20. HTML indexable, metadata, social y Merchant usan la verdad base;
21. no quedan P0/P1 de pérdida de datos, paridad, navegación o usabilidad móvil;
22. documentación canónica refleja la arquitectura implementada;
23. Claude aprueba la lectura visual final y Codex aprueba integración/estado.

## 20. Primer lote ejecutable después de autorización

La primera autorización de implementación debería abarcar únicamente:

1. Fase 0 completa de Design;
2. Fase 1 de resolver/policy/adaptadores sin escritura productiva;
3. Fase 2 mínima del `ResponsiveFieldShell`;
4. Fase 3A del shell mínimo, barra, geometría, SafeArea y draft durable;
5. Fase 3B vertical slice de media/foco en schema + Hero + Carousel;
6. el primer flujo phone inline de media/foco;
7. verificación Edit/Preview/Public y save/reload sobre fixture autorizada.

Ese lote valida arquitectura, desktop, teléfono, datos y paridad antes de
migrar las 24 familias. Si falla, se corrige el owner una vez; no se acumulan
24 implementaciones locales que luego haya que rehacer.

## 21. Revisión cruzada Claude y reconciliación

Claude revisó este archivo completo en la sesión `Auditoría Website Builder
bikeshop-erp`, en Code, proyecto `bikeshop-erp`, Opus 5 y Effort: Ultracode.
Permaneció read-only y terminó en `FREEZE` sin editar archivos.

Veredicto: **adoptable**. Claude consideró superiores a su propuesta previa las
tres decisiones centrales de este plan:

- `writeScope` como eje independiente;
- herencia directa `override(viewport) ?? base`, sin cascada;
- persistencia anidada en lugar de sufijos planos.

También identificó la política declarativa por propiedad como la pieza que
convierte el trabajo en arquitectura y no en una colección de arreglos.

Cambios incorporados desde su revisión:

- Desktop declarado como base sin slot de override;
- compatibilidad explícita para ambas bandas legacy, 600–639 y 900–1023;
- prohibición de mapas vacíos y overrides iguales a la base;
- sanitizer type-aware para el mapa responsive;
- shell mínimo de teléfono adelantado a Fase 3;
- prerequisitos de top bar, geometría, touch, SafeArea y draft durable;
- canarios medidos sobre el lienzo, no la ventana host;
- base como verdad SEO/Merchant y límites de art direction/product media;
- comparison, copy entre viewports, UI tablet completa y telemetría fuera del
  primer gate;
- lista blanca de display copy inicialmente vacía;
- ownership de archivos por fase y estado visible para Canvas ambiguo.

Único desacuerdo material reconciliado: el alcance global no decide en silencio
dónde aterrizan todas las ediciones. Sólo fija el default; cada
`ResponsiveFieldShell` es la autoridad visible y reversible de su propiedad.
