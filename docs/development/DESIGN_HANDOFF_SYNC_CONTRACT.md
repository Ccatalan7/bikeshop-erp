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

### When the window is still allowed

Only two cases, and never for reading values:

1. **Past the 256 KiB cap.** A long page is cut off; sections beyond it exist
   only in the window. Read them there, and mark any value taken that way as
   unsourced until it can be read from a file.
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

## A new module gets its own canvas, not an edit to the guide

The guide holds the **shared vocabulary**. How a given module composes that
vocabulary into screens belongs in a **new Design page for that module** (as
`Nóminas - Rediseño` and `Arquitectura de Paletas` already do).

- Designing a module → ask Design for a new canvas for it, and implement from
  the `handoff-t<N>/` it publishes.
- Discovering that a *shared* control is missing or wrong → that is a change to
  the guide, and it applies everywhere. Do not fork a module-local variant.

## Un turno no está entregado hasta que trae oscuro y compacto

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

**La base visual del oscuro y del compacto también la entrega Design.** La
división no cambia por cambiar de brightness o de ancho: Design sigue mandando
el *look* —superficies, bordes, sombras, tinte, jerarquía, estados— y el agente
sigue aportando criterio, lógica, UX y palabras **al implementarla**. Lo que
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

## What Design publishes (per turn, small files only)

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

## What Code does (every round, before editing UI)

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

If the newest turn has no `handoff-t<N>/`, Code says so explicitly and stops
guessing: the visual source is missing, not "probably the same as last time".

### The one thing that is never acceptable

Shipping a visual value that came from an agent's judgement instead of a Design
file. If the source cannot be read, the correct output is a sentence saying so
— not a plausible number. Any value that has to ship unsourced is marked as
such in the code, at the line, so the next reader can replace it.

## Division of judgement (unchanged by this contract)

Design owns the **looking**: palette, type, surfaces, borders, radii, shadows,
chips, buttons, tables, inputs, popovers, hierarchy and states — replicated
faithfully. Code owns **layout adaptation, information architecture, wording,
UX and logic**: it may reorganise blocks, pick a better control for the data,
and must correct copy that does not fit the domain (for example the module
never says "imputar" or "ganado" where they are wrong), reporting each
deliberate deviation in the handoff.

See [`CODEX_CLAUDE_COLLABORATION.md`](CODEX_CLAUDE_COLLABORATION.md) for the
review gate and [`../architecture/appearance-palette-contract.md`](../architecture/appearance-palette-contract.md)
for how palettes/brightness resolve.
