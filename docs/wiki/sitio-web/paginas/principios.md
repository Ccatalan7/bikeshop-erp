---
titulo: Cómo se juzga un cambio en el sitio
resumen: las reglas que deciden si un cambio en la tienda o el editor está bien hecho, antes de mirar el detalle
fuentes: [repositorio, google-search-central, flutter-web]
archivos: [docs/architecture/website-editor-contract.md, docs/architecture/website-builder-agent-handoff.md]
tablas: [website_settings, website_pages, website_blocks]
revisado: 2026-10-03
---

# Cómo se juzga un cambio en el sitio

## Lo esencial

vinabike.cl no es un sitio aparte del ERP: es **el ERP mostrado al público**. Los
productos, precios, stock, categorías, servicios y la marca salen de la misma base
que usa el taller, y el editor del sitio es el único lugar donde se decide cómo se
ven `[Repo: website-editor-contract.md]`. De ahí salen siete reglas.

## Las siete reglas

1. **Un dato, un dueño.** Cada valor tiene una tabla dueña, un control en el
   editor o en el ERP, una sola operación de guardado y consumidores que lo leen
   igual: el lienzo del editor, la vista previa, la tienda Flutter, los snapshots
   HTML, el sitemap, el feed de Merchant y los correos. Un cambio que deja dos
   copias del mismo valor (un texto en el código y otro en `website_settings`)
   está mal aunque se vea bien `[Repo: website-editor-contract.md «Core invariant»]`.
2. **Edit, Vista previa y Publicado significan lo mismo.** La única diferencia
   permitida son los controles de edición (bordes, manijas, barras). Una rama
   `editable ? transformado : crudo` que cambia el contenido es un defecto, y el
   arreglo va en el renderizador compartido, no en los datos de una campaña
   `[Repo]`.
3. **Guardar no es publicar, y publicar no es que Google lo vea.** Guardar
   cambia la base y la tienda Flutter lo muestra al recargar; el HTML que lee
   Google, el sitemap y las redirecciones cambian sólo cuando corre el build de
   la tienda (un push de código o el build diario). Google lo lee cuando vuelve a
   rastrear. Toda afirmación de SEO dice de cuál de los tres planos habla
   `[Repo: website-editor-contract.md «SEO visibility and evidence»]`.
4. **Lo que Google necesita, en HTML.** Flutter web dibuja en un `<canvas>`;
   su propia documentación dice que no sirve para contenido crítico de SEO
   `[FL]`. Por eso cada ficha, categoría y página indexable tiene un snapshot HTML
   con su título, descripción, canonical, JSON-LD y enlaces `<a href>` reales, y la
   app agrega semántica para rastreadores `[GSC]` `[Repo]`. Un contenido nuevo que
   sólo existe dentro de Flutter no existe para Google.
5. **La marca viene del editor, no del código.** Colores, fuentes, logo, textos
   y contacto salen de `website_settings` y de las páginas; el mismo código sirve
   a otra empresa (multi-tenant). Nada de literales de Viñabike en la tienda
   `[Repo: GUI_DESIGN_PRINCIPLES.md «El sitio público no pasa por Design»]`.
6. **Cada consulta filtra por empresa** (`tenant_id`), y lo que un visitante sin
   cuenta puede leer está acotado a columnas y funciones públicas
   ([seguridad](seguridad.md)).
7. **Se demuestra en vivo.** Un cambio de la tienda se cierra con la página real
   (escritorio y teléfono), el HTML desplegado (`release.json` con el commit) y,
   si toca SEO, con lo que Google renderiza (Prueba de resultados enriquecidos)
   `[Repo]`.

## Cómo se ve (2026-09-24, dueño)

El aspecto del sitio lo decide el agente que hace el trabajo: serio, profesional
y con personalidad; nunca «AI'ish» ni infantil (saludos de relleno, baldosas con
ceros, la misma cifra dos veces, todo en cajas iguales) `[Dueño]`. Los valores
salen del tema del editor ([marca-y-tema](marca-y-tema.md)).

## Trampas

- Medir indexación con la vista por defecto de Search Console (suma todo lo que
  Google conoce) en vez de filtrar al sitemap ([seo-tecnico](seo-tecnico.md)).
- Probar en Chrome con user agent de Googlebot y concluir lo que ve Google: no es
  el render de Google ([fuente](../fuentes/consolas-google.md)).
- Prometer una hora de publicación por el cron: es la hora pedida, GitHub la
  atrasa ([publicacion-y-despliegue](publicacion-y-despliegue.md)).
- Describir en un commit una puerta abierta antes de cerrarla: el repo es público.

## En el código y la base

- El contrato que manda: `docs/architecture/website-editor-contract.md`; el
  mapa de dueños: `docs/architecture/website-builder-agent-handoff.md`.
- Dueños de datos del sitio: `website_settings` (marca, SEO, integraciones),
  `website_pages` y `website_blocks` (páginas y bloques), `website_navigation`,
  `products` y `product_categories` (catálogo) — ver [mapa-del-sistema](mapa-del-sistema.md).

## Fuentes

[repositorio](../fuentes/repositorio.md) ·
[google-search-central](../fuentes/google-search-central.md) ·
[flutter-web](../fuentes/flutter-web.md)
