# Design ⇄ Code sync contract

How Claude Code reads the authoritative visual truth from the Claude Design
project **ERP Bikeshop UI Mockups**
(`a0fa3196-6315-4b96-bde7-7cc801e7a74e`) without asking the owner for
screenshots, and how it proves it is not implementing against a stale turn.

This is a standing rule. It is requested from Design **once**; every later turn
follows it automatically.

## Why it exists

Code can read the Design project directly with `DesignSync`, subject to one
hard limit: **a single file is capped at 256 KiB**. Canvas pages
(`<page>.dc.html`) can exceed that, so a long page arrives **truncated at the
cap** — the sections past it are simply absent.

**Correction, 2026-07-30 (second reading).** An earlier version of this
contract also claimed those pages come back "full of `{{ }}` placeholders",
and used that to demote `DesignSync` below screenshotting the window. That is
wrong and it cost real rounds. The `{{ }}` bindings appear only in the
*interactive demo* wiring (`onClick="{{ toggleDp }}"`, `<sc-if value="{{ … }}">`).
Every static value — hex, radius, shadow, spacing, font — arrives **literal and
exact**. Reading `GUÍA GENERAL Viñabike - Componentes.dc.html` returned, byte
for byte:

```text
raised   0 1px  2px rgba(12,37,55,.06)
popover  0 6px 22px rgba(12,37,55,.13)
overlay  0 12px 40px rgba(12,37,55,.22)
```

The real failure that day was not the API: it was an agent **eyeballing values
off screenshots and inventing the rest**, producing a popover surface that was
never in any design. The truncation is a boundary to work around, not a reason
to guess.

Consequence, observed earlier the same day: turn 4 (`handoff/`, small files)
was read byte-exact and implemented correctly, while turn 5 — which existed
only inside the canvas page — was invisible to Code. Payroll was built against
the older turn until the owner pasted screenshots by hand. The fix is not "send
more screenshots"; it is reading the file and publishing per-frame artifacts.

## Primary path — MANDATORY: values come from `DesignSync`, never from pixels

**Standing rule.** Every visual value an agent writes into this repository —
colour, radius, shadow, border, spacing, font, height — is read from a Design
file through `DesignSync`. Looking at the Design window and reproducing what it
seems to look like is **prohibited**. If a value cannot be read, the agent says
so and stops; it does not estimate.

```text
DesignSync list_files   → what exists, and the highest handoff-t<N>/
DesignSync get_file     → the authoritative source, with literal values
```

### Cómo se abre el proyecto — el id va explícito (corrección 2026-08-18)

**`projectId = a0fa3196-6315-4b96-bde7-7cc801e7a74e`**, proyecto
`ERP Bikeshop UI Mockups`. Se pasa a `list_files` y `get_file` **siempre**.

**`DesignSync list_projects` devuelve `[]` y eso es correcto.** Ese método lista
únicamente proyectos de tipo **design-system**, filtrados a los escribibles. El
proyecto de este ERP es `PROJECT_TYPE_PROJECT`, y ese tipo es **inmutable desde
su creación**: no hay ajuste, permiso ni login que lo haga aparecer en esa
lista. Nunca.

**Un `[]` no es falta de autorización.** Comprobación de un segundo:

```
DesignSync get_project  projectId=a0fa3196-6315-4b96-bde7-7cc801e7a74e
→ {"name":"ERP Bikeshop UI Mockups","type":"PROJECT_TYPE_PROJECT","canEdit":true}
```

**El costo real de no tener esto escrito.** El 2026-08-18 una sesión declaró
«falta autorización de Design» como su único bloqueo, dejó una condición del
corte sin verificar y se la devolvió al dueño como algo que sólo él podía
resolver. Una segunda sesión repitió la conclusión sin probar la herramienta. No
había nada que aprobar: el acceso estaba completo, con `canEdit: true`, y con
los 600+ archivos del proyecto disponibles. Lo que faltaba era esta línea.

**Regla operativa: antes de reportar un bloqueo de Design, corre `get_project`
sobre el id.** Si devuelve `canEdit: true`, el bloqueo no existe.

Rutas que se usan casi siempre —el listado completo sale de `list_files`—:

| Ruta | Para qué |
|---|---|
| `GUÍA GENERAL Viñabike - Componentes.dc.html` | componentes compartidos, ids `S-05`/`O-02`/`I-01`, escala tipográfica |
| `Arquitectura de Paletas - Viñabike.dc.html` | roles semánticos y modo oscuro |
| `<módulo>.dc.html` | la **composición** del módulo, que el `spec.json` no trae |
| `handoff-t<N>/spec.json` | tablas de medidas del turno |
| `handoff-t<N>/frames/…` | los frames, con `-dark`, `-phone`, `-tablet` |

### Reading a large page without burning context

A `get_file` result above roughly 50 KB is written to a file on disk and only a
short preview enters the agent's context. That is the whole technique: **search
the file, don't load it.**

```bash
# The tool result already names the path it saved. Parse and grep it:
python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['content'])" \
  "<saved-tool-result>.txt" > /tmp/guia.html
grep -o 'box-shadow:[^;\"]*' /tmp/guia.html | sort -u
```

A 260 KB component guide costs a 2 KB preview this way, and every value in it
becomes greppable. There is no context argument for guessing.

### Corrección 2026-08-04 — la guía de componentes YA cruzó el cap

`GUÍA GENERAL Viñabike - Componentes.dc.html` pesa **260,9 KB**. `get_file`
corta el contenido en exactamente **262 144 bytes** (256 KiB) y no lo avisa
dentro del texto: el archivo guardado termina a mitad de una etiqueta.

Lo que se pierde hoy es concreto: la página cierra con **`X-01 VbSurfaceState`**
(loading · empty · error · no-results · read-only · sin permiso), y el corte cae
**dentro de esa sección**. Sólo llega su encabezado. Todo lo anterior —`F-01`…
`F-06`, `A-01`…`A-03`, `I-*`, `S-*`, `D-01`, `E-*`, `O-01`…`O-05`, `T-01`…`T-05`—
se lee completo y literal.

Consecuencia operativa, no teórica: **una ronda que diseñe un estado vacío, de
carga o de error no tiene fuente legible para `X-01` y se detiene ahí.** La
ventana **no** la desbloquea: sirve para confirmar que la sección existe y dónde
cae el corte, y nada más. Sus valores siguen siendo *unreadable* — leerlos de la
ventana es exactamente el «eyeballing» que este contrato prohíbe y que ya costó
un popover inventado. Se reanuda cuando Design publique `X-01` como artefacto
fuente propio bajo el cap (o un frame legible en su `handoff-t<N>/`).

Cómo comprobar el corte antes de confiar en lo leído:

```bash
wc -c <archivo-extraído>   # 262144 ⇒ vino truncado
```

El payload crudo capea en **262 144**. Si el conteo da 262 145 es porque el
comando de extracción del ejemplo (`python3 -c "…print(…)"`) agrega un `\n`
final; el byte extra es del `print`, no del archivo.

### Corrección 2026-08-17 — un handoff de PNG no trae composición legible

`handoff-t23/` entregó **28 PNG** y un `spec.json`. Ese spec es normativo para
las **medidas** —geometría por frame, roles semánticos, escala tipográfica— pero
**no describe la composición**: no dice que el bloque de captura sea un panel, ni
que la columna vaya centrada. De un PNG no se lee ningún valor, y de una tabla de
medidas no se deduce un layout.

La composición sí es legible, y está en la página fuente que el propio spec
nombra en `source.page`. Para t23 es
`Compras · Asistente inteligente navegable.dc.html` — 207 KB, bajo el cap — y
trae el bloque escrito literal:

```text
columna   max-width:780px; margin:0 auto; gap:11px   (contenedor padding:14px)
panel     background:var(--surface); border:1px solid var(--border);
          border-radius:10px; padding:12px 13px
campo     min-height:60px; padding:10px 11px; border-radius:8px;
          border:1px solid var(--borderStrong); font:400 12.5px/1.55
acciones  margin-top:9px; flex; gap:12px; «Ejemplos» = texto 600 11px act;
          spacer flex:1; atajo 400 10px mono inkFaint
```

Dos niveles de borde —`border` en el panel, `borderStrong` en el campo de
adentro— son parte del lenguaje, no un detalle.

**Regla: si el handoff más alto son imágenes, la composición se lee de
`source.page` antes de escribir una línea.** No se deduce del `spec.json`, no se
mira en el PNG y no se estima.

### Coincidir en los números no es fidelidad visual (2026-08-17)

Un módulo puede tener todas las constantes del spec correctas y no parecerse al
diseño. Ya pasó: `PurchaseSurfaceGeometry` reproduce medida por medida las
tablas del t23 —imágenes 38/46/64/76, split pane 420/330/600, columna 780,
badge 20, subrayado 2— y la pantalla resultante no tiene panel contenedor, no
centra la columna y usa el tipo ~25% más grande que el diseño.

**Una constante que coincide no es evidencia.** La evidencia de fidelidad visual
es el **frame real de la app al lado del frame de Design**, en la misma celda de
tema y host. Declarar una superficie implementada sin ese par de imágenes es
declarar otra cosa, y fue exactamente lo que costó el rediseño del Asistente de
compras.

### When the window is still allowed

Only two cases, and never for reading values:

1. **Past the 256 KiB cap.** A long page is cut off; the window may confirm
   that later sections exist and where the cut occurs, but their values remain
   unreadable. Stop until Design publishes a file or handoff frame that exposes
   those values through `DesignSync`.
2. **Confirming the built result** looks like the design — the same role
   screenshots of the running app play.

```bash
scripts/dev/design_window.sh shot        # capture the Design window frame only
scripts/dev/design_window.sh scroll -12
```

It captures **only that window's frame**, never a blind full-screen grab, which
would expose unrelated private windows.

## The component library is `GUÍA GENERAL Viñabike - Componentes`

That page is the **standing source for every shared component**: buttons,
inputs, selects, popovers, menus, sheets, dialogs, date pickers, tables, chips,
the depth ladder, motion, focus and the anti-patterns. Its own first rule is
`PROHIBIDO EL HEX LITERAL EN CUALQUIER WIDGET — VbTokens es la fuente`.

Two obligations follow:

- **Look there before inventing a control.** A component that already exists in
  the guide is implemented from the guide, under its id (`S-05`, `O-02`, `I-01`…)
  and its `Vb*` name. Naming that id in the handoff is what makes the claim
  checkable.
- **Bind values to roles, never paste the hex.** The guide's `#FFFFFF` is the
  `surface` role, `#E2E7ED` is `divider`, `rgba(12,37,55,…)` is the shell
  canvas. Copying the literal freezes light mode into a widget and is the exact
  defect the palette work spent a day removing.

The guide also settles which component a case needs — for example `S-05` caps a
short select at "~7 opciones" and states the menu is not scrollable, so a
sixteen-option list is an `S-06` searchable select, not a taller `S-05`. Read
the limit before choosing.

## A module composes the guide; a dedicated canvas is optional

The guide holds the **shared vocabulary**. Codex composes that vocabulary from
the operator's workflow, domain truth, navigation and responsive hosts. A
dedicated module page can be useful reference material, but it is not required
before implementation and does not own the workflow or layout.

- Designing a module → use the canonical guide and running app; ask for a
  module canvas only when the owner explicitly requests Claude/Design input.
- Discovering that a *shared* control is missing or wrong → that is a change to
  the guide, and it applies everywhere. Do not fork a module-local variant.

The next handoff requirements apply **only when the owner explicitly requested
a module-specific Claude/Design proposal**. Without that request, Codex does not
stop for a missing module canvas or `handoff-t<N>`: it composes the canonical
guide, responsive guides and running application directly, and still verifies
light/dark plus desktop/tablet/phone.

## A requested Design turn includes dark and compact

**Claro-escritorio no es una entrega: es un tercio de una.** Un diseño que sólo
existe en claro a 1440 obliga a inventar las otras dos vistas, que es
exactamente lo que este contrato prohíbe.

Para CADA superficie que un turno toca, Design entrega:

| Vista | Por qué no es opcional |
|---|---|
| **Claro** | La referencia |
| **Oscuro** | No es el claro invertido. Necesita capas propias, y los tonos semánticos NO se recolorean. Sin el frame, Code termina estimando |
| **Compacto (390)** | Composición **propia**, no la tabla comprimida: un objetivo por pantalla, targets táctiles |

Y en al menos **dos presets materialmente distintos** cuando el turno toca
color, para que se vea qué cambia con la paleta y qué no.

**La base visual del oscuro y del compacto también la entrega Design cuando
existe ese handoff solicitado.** La división no cambia por cambiar de
brightness o de ancho: la guía sigue mandando superficies, bordes, sombras,
tinte y anatomía de controles; Codex sigue poseyendo jerarquía, composición,
criterio, lógica, UX y palabras. Lo que
está prohibido es lo mismo de siempre: derivar el oscuro invirtiendo el claro,
o inventar la composición móvil comprimiendo la de escritorio. Si el frame no
existe, se pide; no se deduce.

Reglas que se derivan:

- **No se acepta "el oscuro después".** Diferir una brightness convierte el
  módulo en deuda: hoy el plan de Nóminas todavía arrastra un pase de dark y
  compacto que quedó abierto por haberse pospuesto.
- **Móvil no es una fase aparte.** Se cierra junto con su superficie, no en una
  etapa final donde ya nadie recuerda las decisiones.
- **Code verifica las tres antes de declarar terminada una superficie**, en la
  app corriendo, y lo dice en el handoff de la ronda. Un frame implementado
  sólo en claro-escritorio no está implementado.
- Si un turno llega sin el frame oscuro o sin el compacto, **Code lo dice y lo
  pide** — no lo deduce. Deducirlo es inventar, con otro nombre.

Cómo resuelven paleta y brightness:
[`../architecture/appearance-palette-contract.md`](../architecture/appearance-palette-contract.md).
Reglas de composición compacta:
[`../../.github/GUI_MOBILE_DESIGN_PRINCIPLES.md`](../../.github/GUI_MOBILE_DESIGN_PRINCIPLES.md).

## What Design publishes (per explicitly requested turn, small files only)

For every turn that changes UI, Design writes a folder `handoff-t<N>/` in the
project. Every file must stay **under 200 KiB**:

| Path | Content |
|---|---|
| `handoff-t<N>/spec.json` | One object per frame (`5a`…`5j`): name, blocks, geometry per breakpoint (1440 / 1116 / 834 / 390), states, and the exact copy. |
| `handoff-t<N>/frames/<id>.png` | Render of **each frame separately** (never the whole page), ~1400 px wide. |
| `handoff-t<N>/<surface>.dart` | The exact snippet per new or changed surface (queue, history, OCR steps 1–4, payments, cash, payment method…). |
| `handoff-t<N>/CHANGELOG.md` | What changed against the previous turn, frame by frame. |

Rules that keep this readable:

- Never leave a frame's only representation inside `*.dc.html`; that file is
  above the read limit and arrives truncated.
- Split anything approaching the cap instead of shipping one large file.
- Keep frame ids stable across turns (`5a` stays `5a`), so a diff is meaningful.
- A turn is considered published only once `spec.json` and its `frames/` exist.

## What Code does when consuming an explicitly requested Design turn

0. If the round touches a shared control, read it from
   `GUÍA GENERAL Viñabike - Componentes` **first**, with `get_file`, and note
   its id. Skipping this is how a hand-invented component reaches `lib/shared/`.
1. `DesignSync list_files` — detect new/changed paths and the highest
   `handoff-t<N>/`.
2. Download the current turn's artifacts into the local mirror
   `.tmp/design-mirror/t<N>/` (never committed; it is a cache, not a source).
3. `scripts/dev/design_mirror.sh manifest t<N>` — record SHA-256 per file.
4. `scripts/dev/design_mirror.sh diff t<N>` — compare against the previous
   manifest and report exactly which frames moved.
5. Name, in the handoff, the turn and frame ids implemented, the component ids
   from the guide, plus the hash of the spec used. A round that cannot name
   them is not verified.

If an explicitly requested turn has no `handoff-t<N>/`, Code reports that the
optional proposal cannot be verified and continues from the canonical guide
unless the owner asked to block on that proposal.

### The one thing that is never acceptable

Shipping a visual value that came from an agent's judgement instead of a Design
file. If the source cannot be read, the correct output is a sentence saying so
— not a plausible number. Any value that has to ship unsourced is marked as
such in the code, at the line, so the next reader can replace it.

## Division of judgement (unchanged by this contract)

The canonical guide owns the **visual grammar**: palette, type, surfaces,
borders, radii, shadows and shared component anatomy. Codex owns **workflow,
hierarchy, states, layout adaptation, information architecture, wording, UX
and logic**: it may reorganise blocks, pick a better control for the data,
and must correct copy that does not fit the domain (for example the module
never says "imputar" or "ganado" where they are wrong), reporting each
deliberate deviation in the handoff.

See [`CODEX_CLAUDE_COLLABORATION.md`](CODEX_CLAUDE_COLLABORATION.md) for the
review gate and [`../architecture/appearance-palette-contract.md`](../architecture/appearance-palette-contract.md)
for how palettes/brightness resolve.

## `fontFamily: '<nombre>'` sobre un rol ya resuelto vuelve a colarse (2026-08-18)

**Nueve sitios vivos en un módulo que ya documentaba la trampa como corregida.**

El proyecto registra en `pubspec.yaml` **sólo Oswald y Barlow**. Los roles
tipográficos del handoff resuelven su familia con las APIs específicas de
`google_fonts` (`GoogleFonts.ibmPlexMono()`, `GoogleFonts.poppins()`), y eso es
justamente lo que los hace independientes del recorrido previo del operador.

Escribir después `.copyWith(fontFamily: 'IBM Plex Mono')` sobre uno de esos
roles **deshace ese arreglo**: reemplaza la familia ya resuelta por un nombre
que sólo existe si alguna otra pantalla cargó esa familia antes en la misma
sesión. Se ve bien casi siempre —porque el propio módulo la carga— y por eso
sobrevive a las revisiones.

Dos formas y su corrección:

- **El rol ya trae esa familia** (`metricSmall`, `metricMedium`, `panelTitle`,
  `moduleTitle`): el `fontFamily` es redundante y dañino. Se borra.
- **Se quiere otra familia a propósito** —un `meta` que debe ser mono porque
  lleva una cantidad o una edad de evidencia—: no se pide por nombre, se
  **agrega el rol**. Para eso existe `PurchaseType.metaNumeric`: las métricas
  exactas de `meta` con `typography.families.numeric`, que el spec reserva para
  «números comparables, códigos, metadatos de conteo». Agregar un rol con las
  medidas de otro **no** es inventar un valor; pedir una familia por nombre sí
  es romper el contrato.

Cómo se detecta en un comando, y conviene correrlo al cerrar cualquier ronda
tipográfica:

```bash
grep -rn "fontFamily: '" lib/modules/<módulo>/ | grep -v visual_language
```
