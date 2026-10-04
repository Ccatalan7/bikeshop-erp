# Claude Code Instructions (Repo-Wide)

@AGENTS.md

Vinabike ERP — Flutter client, Supabase backend, accounting-first business
logic with strict multi-tenant isolation.

`.github/copilot-instructions.md` is the repository source of truth. Read it
before making changes. The pointers below exist so the right section is loaded
before the first command of a task, not to restate it.

## Routing

| Work | Read first |
|---|---|
| Supabase / database / SQL / pgTAP | `docs/development/AGENT_DATABASE_CONTRACT.md` |
| Any UI or frontend | `.github/GUI_DESIGN_PRINCIPLES.md` |
| Mobile, tablet, compact, adaptive, responsive UI | the GUI guide **and** `.github/GUI_MOBILE_DESIGN_PRINCIPLES.md` |
| Business-workflow UI | `docs/architecture/canonical-ui-surfaces.md`, and update its registry when a surface changes |
| **Probar la app** (sesión de debug, clics, lectura de pantalla, capturas) | `docs/development/AGENT_VISUAL_WORKFLOW.md` — es el procedimiento; el runbook macOS es la referencia de cada herramienta |
| Running, clicking and screenshotting the app | `docs/development/AGENT_MACOS_APP_CONTROL.md` |
| Palettes, light/dark, semantic roles | `docs/architecture/appearance-palette-contract.md` |
| **Cómo se ve el ERP** (colores, medidas, componentes) | la sección «El diseño del ERP es abierto» de abajo |
| Duplicados, matching de catálogo, «¿ya existe este producto?» | `docs/architecture/product-identity-matching-contract.md` |
| **Compatibilidad de partes** («¿calza?», estándares de bicicleta, fichas y motor de compatibilidad) | `docs/wiki/compatibilidad/index.md` y la skill `compatibilidad` |
| **Sitio web y su editor** (vinabike.cl, tienda, editor del sitio, SEO, checkout, portal, Merchant, GA4, rendimiento) | `docs/wiki/sitio-web/index.md` y la skill `sitio-web` |
| Bike workshop architecture | `BIKE_WORKSHOP_MASTER_SCHEMA.md`, updated in the same task when behavior/schema/data-flow changes |

## El diseño del ERP es abierto (dueño, 2026-09-27)

«necesito que dejes abierto el diseño del ERP, no más guías que aseguran
resultados outdated y horribles; los que estás creando con Design son mucho
más modernos y bonitos» — el dueño, al ver una propuesta para la ficha del
trabajo hecha en un lienzo de Claude Design.

Corrige la regla anterior (valores sólo desde `GUÍA GENERAL Viñabike -
Componentes` vía `DesignSync`, Codex como único líder de diseño, compuerta de
seis dimensiones por frame). Desde ese día el ERP sigue lo que el sitio
público ya tenía desde el 2026-09-24:

- **El aspecto lo decide el agente que hace el trabajo, Claude o Codex:**
  color, radio, sombra, borde, espaciado, tipografía, alto, contenedores y la
  anatomía de cada control, y también la dirección visual y la composición.
  No se leen de la guía ni con `DesignSync`, no se reportan como «ilegibles»,
  nadie espera un `/design-login` y no hay compuerta por frame. La vara:
  moderno, serio y con personalidad; nunca anticuado ni «AI'ish».
- **Proponer en un lienzo de Claude Design es bienvenido** (Artifact de tipo
  Design) antes de un cambio grande: es lo que el dueño elogió. Se arma con
  datos reales del negocio y después se construye en la app.
- **Sigue valiendo el funcionamiento, no el aspecto:** retorno de navegación
  (`ReturnNavigation.close`), el registro de superficies canónicas, estados,
  palabras de taller, accesibilidad (contraste, foco, tamaño de toque),
  teléfono y tableta, claro y oscuro. Los colores pasan por los roles del
  tema (`lib/shared/themes/`, `docs/architecture/appearance-palette-contract.md`)
  para que el oscuro funcione; cambiar el tema mismo para modernizarlo está
  permitido. Un control compartido (`VbButton`, `VbStatusBadge`…) se mejora en
  su dueño, no se copia suelto en un módulo.
- **Se demuestra igual:** capturas reales de la app (escritorio y teléfono,
  claro y oscuro) antes de darlo por listo.

Las dos guías del repo (`.github/GUI_DESIGN_PRINCIPLES.md` y
`.github/GUI_MOBILE_DESIGN_PRINCIPLES.md`) quedan como contrato de
funcionamiento; lo que prescriben del aspecto es historia, no regla. Tampoco
son precedente los prompts antiguos, las capturas, los planes, los widgets
existentes ni los tests de aspecto.

El proyecto de Design `ERP Bikeshop UI Mockups`
(`projectId = a0fa3196-6315-4b96-bde7-7cc801e7a74e`) queda como consulta
opcional. Si se lee: `list_projects` devuelve `[]` por diseño y el id va
explícito; el procedimiento está en
`docs/development/DESIGN_HANDOFF_SYNC_CONTRACT.md`.

## Database work in one line

All SQL — local and hosted — goes through `scripts/db/query.sh`; the Supabase
CLI never runs SQL and is invoked through `scripts/supabase_cli.sh` for
control-plane work only. Start with `just db-preflight`. Reads are autonomous;
guarded writes are agent-run too since 2026-08-05 («los agentes deben correr
los querys siempre, sin pedir confirmación» — el dueño; corrige «writes need
the owner's go-ahead»). The full contract, including the autonomy boundary and
the guarded-read defaults, is in
`docs/development/AGENT_DATABASE_CONTRACT.md`.

Never use `supabase db query`, `supabase db push`, ad hoc hosted `psql`, or the
hosted SQL Editor.

## Limpia lo que generas, antes de cerrar la ronda

El Mac del dueño se llena una y otra vez con basura de las sesiones de agente
(2026-08-20: 867 MB libres; 2026-09-18: 28 GB de 460), y está harto de
repetirlo. **Cada ronda deja el disco como lo encontró:**

- Lo que generaste fuera del repo —capturas, PDFs, renders, descargas,
  candidatos en el scratchpad— se va a la Papelera antes de cerrar.
- Si corriste pruebas, `build/test_cache/` crece sin techo con cada corrida
  (15 GB el 2026-09-18) y no lo usa la sesión de debug: va a la Papelera.
- Mide con `df -h /System/Volumes/Data`. Bajo 50 GB libres, aplica «Local
  Storage Hygiene» de `.github/copilot-instructions.md` sin esperar a que el
  dueño lo pida.
- `rm -rf` y `kill` los bloquea el hook: se **mueve** a
  `~/.Trash/limpieza-<fecha>/` y el dueño vacía la Papelera. Nunca se toca la
  media de WhatsApp, los volúmenes de Colima ni la otra cuenta del Mac.

## Escribe lo que aprendes, antes de cerrar la ronda

Si esta ronda descubrió algo que le habría ahorrado tiempo a quien venga
después —una trampa de una herramienta, una preferencia tuya del dueño, un
documento que resultó falso, una regla de dominio que sólo aparece con datos
reales— **se escribe en la misma tarea**, no al final del proyecto.

`.github/copilot-instructions.md` es el documento padre y tiene la tabla de
qué aprendizaje va a qué archivo. Si el proceso descrito ahí resulta
equivocado o mejorable, **se corrige ahí**: no se rodea ni se documenta la
excepción en otro lado.

Escribe la **causa**, no el síntoma; fecha la corrección cuando contradice algo
anterior; y di el costo real cuando lo hubo — eso es lo que hace que el
siguiente lo lea.

No escribas el relato de la sesión, ni lo que ya se ve en el código o en git.

## Working agreements

- This repository accepts collaborative Claude work only from **Code** mode
  with **Fable 5** (preferred) or **Opus 5**. Use **Effort: Ultracode** when
  workflows/subagents are enabled; use **Effort: xhigh** while the owner has
  them suspended. This is not a quality downgrade: Anthropic defines
  Ultracode as `xhigh` plus automatic workflow orchestration, so the two modes
  cannot truthfully coexist with a zero-subagent rule. Before the first prompt,
  and again after switching chats, verify the visible model, effort,
  `bikeshop-erp` repository and intended chat title/URL immediately before
  Send.
- Never print credential values, full connection strings, or credential-bearing
  commands. Check presence only.
- Multi-tenant: every tenant-scoped query filters `tenant_id`. A missing filter
  is a defect, not a style issue.
- Run the affected tests yourself and report real output. A local pass is not a
  production deployment.
- When the owner explicitly requests collaboration with Codex, follow
  `docs/development/CODEX_CLAUDE_COLLABORATION.md`. Claude remains an
  independent reviewer; Codex retains product/layout ownership. Do not silently
  agree with Codex: test its assumptions and report evidence. Never edit the
  same files concurrently with another agent.
- The dual-diagnosis gate is for P0/P1 findings and seams involving financial
  integrity, security, tenant isolation, concurrency, navigation ownership or
  another broad invariant. Local visual/mechanical defects are corrected by
  the active lead and bundled into the next block checkpoint; do not stop a
  feature for one review session per control.
- Invoke the `cross-review` skill at a coherent feature/block boundary, not
  after every widget. While subagents are suspended, Claude and Codex perform
  that review directly in the existing primary sessions; do not launch the
  `ui-design-lead`, `logic-cross-reviewer` or `ui-cross-reviewer` agents.
- **Sin techo de herramientas** remains the general project rule, but the owner
  suspended Workflow, agent teams and subagents for the current Payroll
  migration after repeated stalls. The current user settings enforce that
  suspension. Work sequentially in one session until the owner lifts it.
  Browser, Computer Use, DesignSync and the native debug tooling remain
  available.
  **Corrección del dueño, 2026-08-09, precisada el 2026-08-20:** una tarea de
  implementar, arreglar, terminar, ship o deploy incluye el rollout productivo
  normal, no destructivo y ya revisado, y **Claude lo corre**. Migraciones
  in-scope van por `scripts/db/deploy_migration.sh` con
  `VINABIKE_DB_WRITE_CONFIRM=production` y su archivo `--verify`; el hook no las
  deniega —verificado corriendo, no leyendo, el 2026-08-20—. No se le entrega el
  SQL a Codex ni se le devuelve al dueño una confirmación rutinaria, y no se
  conserva un `no production writes` de un subtask anterior después de una
  instrucción posterior de terminar. Lo que se reporta es el read-back. Análisis,
  diagnóstico, draft y `local-only` siguen read-only mientras sean la
  instrucción vigente. Reparaciones destructivas, rotación de credenciales,
  targets ambiguos, publicación más amplia y cambios ajenos al alcance sí
  requieren una decisión explícita. Antes de mover `origin` se comprueba que
  Codex no esté publicando desde este mismo checkout —árbol limpio, sin procesos
  de gate y `HEAD == origin`—.
