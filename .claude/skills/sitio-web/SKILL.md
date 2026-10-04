---
name: sitio-web
description: Experto en vinabike.cl y el editor del sitio del ERP (tienda pública Flutter, Website Builder, catálogo web, checkout, portal de clientes, SEO, datos estructurados, Google Merchant, GA4, rendimiento, Firebase Hosting, build de la tienda). Úsala siempre que la tarea toque la tienda o el sitio público, el editor del sitio o sus páginas de administración (/website/*), lib/public_store, lib/modules/website, web/index.html, firebase.json, el generador de snapshots SEO, el sitemap o robots, el feed o la cuenta de Merchant, Search Console, Analytics, PageSpeed, el checkout o los pedidos online, el portal /cuenta, o cuando haya que explicar por qué algo no aparece en Google o en la tienda; y para ingerir una fuente nueva (Google, web.dev, Flutter, Merchant) en el wiki.
disable-model-invocation: false
---

# Sitio web (wiki + lo vivo)

El conocimiento vive en `docs/wiki/sitio-web/` (patrón «LLM Wiki» de Karpathy,
igual que el de compatibilidad). Esta skill es el método para usarlo y
mantenerlo. El esquema completo está en `docs/wiki/sitio-web/README.md`.

## Responder una pregunta sobre el sitio

1. Leer `docs/wiki/sitio-web/index.md` y abrir las páginas del tema. Siempre
   `paginas/principios.md` si la pregunta es «¿está bien hecho?» y
   `paginas/mapa-del-sistema.md` si es «¿dónde vive esto?».
2. **Contrastar con lo vivo antes de afirmar**, con fecha:
   - qué está desplegado: `https://vinabike.cl/release.json`, el `sitemap.xml`,
     el HTML de la ruta (JSON-LD, canonical, robots);
   - los datos: `scripts/db/query.sh production` (lectura, siempre con
     `tenant_id`);
   - lo que dice Google: Search Console / GA4 / Merchant en el Chrome del dueño
     (`fuentes/consolas-google.md` dice cómo entrar y cómo no leerlas mal).
3. Decir de cuál de los tres planos habla cada afirmación: lo que la app permite,
   lo que el build desplegado tiene, lo que Google dice. Guardar ≠ publicar ≠
   indexado.
4. Responder en español simple, con las etiquetas de origen (`[GSC]`, `[Repo]`,
   `[Prod fecha]`, `[Consola fecha]`, `[Dueño]`…).
5. Si la respuesta enseñó algo que el wiki no tenía, **archivarlo** en su página
   y una línea en `log.md`. Un pendiente nuevo va a `paginas/estado-y-pendientes.md`.

## Cambiar la tienda o el editor

- Antes: leer la página del tema, el contrato que manda
  (`docs/architecture/website-editor-contract.md` para el editor) y la fila de
  `docs/architecture/canonical-ui-surfaces.md`.
- Mientras: un dato, un dueño; paridad Edit / Vista previa / público; lo que
  Google necesita va al snapshot HTML; la marca sale del tema del editor.
- Después: actualizar «En el código y la base» de cada página tocada (y el mapa
  si nace una tabla, función, ruta o evento), correr el lint y verificar en vivo
  tras el build de la tienda (`release.json` con el commit).
- `test/unit/site_wiki_contract_test.dart` falla en CI si nace una ruta pública,
  un evento de GA4, una página de administración del sitio o una función del
  sitio que el wiki no nombra.

## Ingerir una fuente

1. Registrarla en su ficha de `fuentes/` (URL, fecha, qué cubre).
2. Actualizar **todas** las páginas que toca, con palabras propias (el repo es
   público: nunca copiar texto de Google ni de nadie).
3. Línea en `log.md`; página nueva → `index.md`.

## Revisar

```bash
python3 scripts/knowledge/lint_site_wiki.py --db production
```

Revisa índice, enlaces, plantilla, fuentes, etiquetas, que existan los
`archivos` y, con `--db`, las `tablas`. A mano: números viejos que una medición
nueva superó, contradicciones entre páginas y partes del sistema sin página.

## Límites

- Nunca describir en el wiki (ni en un commit) un hueco de seguridad abierto:
  primero se cierra y se despliega.
- Un cron es la hora pedida, no la de ejecución.
- Un número sin fecha no vale: se escribe con la fecha en que se midió.
