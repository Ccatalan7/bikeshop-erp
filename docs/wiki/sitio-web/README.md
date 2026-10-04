# Wiki del sitio web — cómo funciona y cómo se mantiene

Este wiki es el conocimiento experto sobre **vinabike.cl y el editor del sitio
del ERP**: cómo está armado de punta a punta, por qué, qué dice el oficio (Google,
web.dev, Flutter, Merchant, GA4) y qué falta. Lo escriben y lo mantienen los
agentes (Claude o Codex); el dueño lo lee cuando quiere. Sigue el patrón «LLM
Wiki» de Andrej Karpathy, igual que el
[wiki de compatibilidad](../compatibilidad/README.md). Empieza por
[index.md](index.md).

Lo pidió el dueño el 2026-10-03: «una nueva carpeta de second brain pero esta vez
como una especie de master schema experto en nuestro sitio web y editor del
sitio». Es a la vez el **mapa** (qué archivo, tabla, función o consola es dueña de
cada cosa) y el **criterio** (qué hace bien un sitio de comercio y qué pide
Google).

El objetivo del dueño (2026-10-04): una tienda **premium, moderna, segura y
bien conectada**, con el flujo de venta —pedido, pago, correos y creación de
cuenta— funcionando de forma impecable ([principios](paginas/principios.md)).

La regla que manda sobre todas: **lo que un agente cambia en el sitio queda
hecho como lo habría hecho una persona en el editor**, editable ahí sin ningún
agente; nunca una implementación paralela
([principios, regla 1](paginas/principios.md)).

## Las tres capas

| Capa | Dónde | Quién la cambia |
|---|---|---|
| **Fuentes** | [fuentes/](fuentes/) — una ficha por fuente externa (Google, web.dev, Flutter…) o interna (contratos del repo, consolas): qué se consultó, cuándo y con qué cuidado leerla | se agrega al ingerir; no se reescribe lo ya consultado |
| **Páginas** | [paginas/](paginas/) — una por tema (editor, rutas, SEO, checkout…), con palabras propias | el agente, cada vez que aprende algo |
| **Esquema** | este archivo y la skill `.claude/skills/sitio-web/SKILL.md` | sólo cuando el método cambia |

Este wiki **no reemplaza** los contratos que ya mandan; los resume y apunta:

- [`docs/architecture/website-editor-contract.md`](../../architecture/website-editor-contract.md)
  — el contrato de ingeniería del editor (dueño → control → operación →
  consumidor, paridad Edit/Preview/público, SEO en tres planos).
- [`docs/architecture/website-builder-agent-handoff.md`](../../architecture/website-builder-agent-handoff.md)
  — mapa de dueños del Website Builder y plan del catálogo.
- [`docs/architecture/storefront-instant-page.md`](../../architecture/storefront-instant-page.md)
  — la página instantánea (HTML antes de Flutter).
- [`docs/runbooks/ONLINE_ORDER_OPERATIONS.md`](../../runbooks/ONLINE_ORDER_OPERATIONS.md)
  — pedidos online, pagos, documentos y Merchant.
- [`docs/architecture/canonical-ui-surfaces.md`](../../architecture/canonical-ui-surfaces.md)
  — el registro de superficies (cada pantalla del editor y de la tienda).
- `.github/copilot-instructions.md` — «Public Store Quality Bar», «Public Store
  Performance & Freshness Doctrine» y «HTML-first storefront evolution is allowed».

Si una página del wiki y un contrato se contradicen, manda el contrato y la
página se corrige en la misma tarea (o el contrato, si la evidencia lo superó,
con fecha).

## Reglas de escritura

1. **El repositorio es público.** Nunca credenciales, claves, connection
   strings, correos de clientes ni datos personales. Un hueco de seguridad
   **abierto** no se describe aquí: primero se cierra y se despliega, después
   se documenta (`repo-publico-y-main-estricto`). Lo que sí va: cómo está
   cerrado y qué no hay que reabrir.
2. **Palabras propias, nunca copia.** La documentación de Google, web.dev y
   Flutter tiene derechos de autor. Se guardan hechos (umbrales, reglas,
   nombres de propiedades) y el enlace; nunca párrafos ni tablas copiadas.
3. **Cada afirmación dice de dónde sale**, con una etiqueta al final:
   - `[GSC]` Google Search Central (documentación y ayuda de Search Console),
   - `[MC]` ayuda de Google Merchant Center, `[GA]` GA4, `[WD]` web.dev,
     `[FL]` documentación de Flutter, `[SO]` schema.org, `[Ref]` medición en vivo
     de tiendas de referencia,
   - `[Repo]` contrato, código o documento del repositorio (la frase nombra cuál),
   - `[Prod]` lectura de producción con `scripts/db/query.sh` o de
     `https://vinabike.cl` (con fecha),
   - `[Consola]` lectura en Search Console, GA4 o Merchant (con fecha),
   - `[Dueño]` decisión del dueño (con fecha).
4. **Un número tiene fecha.** Indexación, URLs del sitemap, tiempos de carga,
   productos publicados: todo cambia. Se escribe «1.315 URL en el sitemap
   (2026-10-03)», nunca «el sitemap tiene 1.315 URL».
5. **Tres planos de evidencia SEO, nunca mezclados**: lo que la app permite hoy,
   lo que el build desplegado contiene (`release.json`, `sitemap.xml`,
   `robots.txt`) y lo que Google dice (Search Console). Guardar en el editor no
   es publicar; publicar no es que Google lo haya leído
   ([principios](paginas/principios.md)).
6. **Un cron es la hora pedida, no la de ejecución** (GitHub atrasa `schedule`
   de 35 min a 6 h en este repo). Antes de prometer cuándo llega algo, leer las
   corridas reales.
7. **Cada página termina en «En el código y la base»**: qué archivos, tablas,
   funciones y consolas son dueños del tema, y qué falta. Así el wiki es el
   mapa del sistema.
8. Español claro de Chile; los términos técnicos en su forma original
   (canonical, sitemap, LCP, JSON-LD, CanvasKit).

## Plantilla de página

```markdown
---
titulo: SEO técnico
resumen: una línea que diga para qué sirve la página
fuentes: [google-search-central, repositorio]
archivos: [scripts/generate_product_seo_snapshots.dart]
tablas: [website_settings]
revisado: 2026-10-03
---

# SEO técnico

## Lo esencial
## (secciones del tema)
## Trampas
## En el código y la base
## Fuentes
```

`archivos` son rutas del repositorio (el lint comprueba que existan); `tablas`
son tablas de `public` (con `--db production` el lint comprueba que existan en
producción).

## Cómo se asegura que se use

Igual que el wiki de compatibilidad, en cuatro capas:

1. **Al empezar cada sesión de Claude**, `.claude/hooks/session-context.sh` dice
   que el sitio y el editor pasan por la skill `sitio-web`. Codex lo lee en
   `AGENTS.md`; los dos lo tienen en la tabla de rutas de `CLAUDE.md`.
2. **Cuando el pedido trata del sitio** (tienda, SEO, editor, checkout,
   Merchant…), el hook `.claude/hooks/site_wiki_router.py` (UserPromptSubmit)
   recuerda usar la skill, una vez por sesión.
3. **Cuando se edita la tienda, el editor, el generador, `web/`, `firebase.json`
   o una función del sitio**, el mismo hook (PostToolUse) recuerda actualizar la
   página y correr el lint, una vez por sesión.
4. **En cada publicación** (gate de CI, para Claude y Codex por igual),
   `test/unit/site_wiki_contract_test.dart` falla si aparece una ruta pública, un
   evento de GA4, una pantalla de administración del sitio o una función del
   sitio que el wiki no nombra, o si una página no está en el índice.

## Las tres operaciones

**Consultar.** Leer [index.md](index.md), abrir las páginas del tema y
**contrastar con lo vivo** antes de afirmar algo: `scripts/db/query.sh
production` (lectura), `https://vinabike.cl/release.json`, el `sitemap.xml`, el
HTML de una ficha, y las consolas cuando la pregunta es sobre Google. Si la
respuesta enseña algo que el wiki no tenía, se archiva en su página y en
[log.md](log.md).

**Ingerir.** Una fuente nueva (artículo de Google, cambio de política de
Merchant, una medición de PageSpeed, una lección de una ronda):
1. agregarla a su ficha en `fuentes/` (URL, fecha, qué cubre);
2. actualizar **todas** las páginas que toca;
3. una línea en [log.md](log.md) y, si nace una página, en [index.md](index.md).

**Revisar (lint).** `python3 scripts/knowledge/lint_site_wiki.py [--db
production]` revisa páginas fuera del índice, enlaces internos, campos de la
plantilla, fuentes y etiquetas, que cada `archivos` exista en el repo y, con
`--db`, que cada `tablas` exista. A mano: contradicciones entre páginas, números
viejos que una medición nueva superó y huecos (algo del sistema sin página).
