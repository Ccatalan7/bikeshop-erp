---
titulo: Cómo se juzga un cambio en el sitio
resumen: las reglas que deciden si un cambio en la tienda o el editor está bien hecho; la primera, que lo que hace un agente queda hecho como en el editor y no en paralelo
fuentes: [repositorio, google-search-central, flutter-web]
archivos: [docs/architecture/website-editor-contract.md, docs/architecture/website-builder-agent-handoff.md]
tablas: [website_settings, website_pages, website_blocks]
revisado: 2026-10-04
---

# Cómo se juzga un cambio en el sitio

## El objetivo (dueño, 2026-10-04)

«El objetivo principal de todo esto es tener una página web premium, que cautive
al usuario, con UI moderna, segura y con APIs de calidad y bien conectadas.
También todo el flujo de venta con notificaciones vía email y creación de usuario
tienen que estar funcionando de forma impecable» `[Dueño]`. Y en el mismo día:
«lo otro súper importante es el SEO: absolutamente toda la configuración de SEO
que ocupan sitios web de venta profesionales, u otros referentes de venta de
bicicletas, nosotros debemos aplicar lo mismo. Queremos llegar a público, siendo
visibles de forma óptima en internet» `[Dueño]`. La vara del SEO es lo que hacen
los referentes, medido en vivo ([seo-de-referentes](seo-de-referentes.md)). Cada cambio del sitio
se juzga contra eso: si no acerca a una tienda premium y a una venta que funciona
sin fallas (pedido, pago, correo, cuenta), no es prioridad.

## Lo esencial

vinabike.cl no es un sitio aparte del ERP: es **el ERP mostrado al público**. Los
productos, precios, stock, categorías, servicios y la marca salen de la misma base
que usa el taller, y el editor del sitio es el único lugar donde se decide cómo se
ven `[Repo: website-editor-contract.md]`. De ahí salen ocho reglas, y la
primera manda sobre las demás.

## Regla 1 — Lo que hace un agente queda hecho como en el editor

Un agente (Claude, Codex) que cambia el sitio **opera el editor**, no construye
al lado. El resultado tiene que ser **indistinguible de lo que habría hecho una
persona en el editor**: una persona puede abrirlo, ver cada valor en su control,
cambiarlo o borrarlo, guardar, previsualizar y publicar **sin ningún agente**. Si
eso no se cumple, el trabajo no está terminado aunque la tienda se vea bien
`[Repo: website-builder-agent-handoff.md «The non-negotiable invariant»,
website-editor-contract.md «Agent-created campaigns are real editor operations»]`.

```text
pedido del dueño
  → una capacidad que el editor ya tiene (o que se le agrega primero, reutilizable)
  → el dueño canónico del dato, con un valor válido guardado
  → el control visible donde se edita
  → el mismo guardado del editor («Guardar»)
  → Edit, Vista previa y la tienda lo leen igual
  → al recargar, el mismo control muestra el mismo valor
```

| Se puede | No se puede |
|---|---|
| llamar el mismo servicio o comando que usa el control del editor | una condición en el renderizador para una campaña o categoría puntual |
| crear el bloque, la diapositiva o la capa Canvas con el mismo esquema y valores por defecto que el editor | claves JSON inventadas que ningún control muestra ni edita |
| sembrar contenido inicial con un script y después comprobar la ida y vuelta en el editor | dejar el contenido en una constante de Dart, un CSS, una fixture o un seed que la tienda lea en vivo |
| subir una imagen por el servicio de medios y elegirla como cualquier otra | apuntar a una URL local, temporal o externa que el selector de medios no administra |
| elegir el destino tipado (página, categoría, producto, filtro de catálogo) | escribir a mano una ruta o un query string dentro de un banner |
| agregar primero al editor el control que falta, y recién después usarlo | estilizar una instancia en el código porque el editor no tiene el control |
| migraciones para cambiar el esquema y backfills explícitos de compatibilidad | SQL directo como camino normal para crear o editar contenido |

**Si el editor no puede representar lo pedido, el agente es libre de
construirlo** `[Dueño 2026-10-04]`: «si el owner llega a pedir algo que el agente
piensa que no podría replicar en el editor, es libre de crear la nueva función,
componente, etc. primero en el editor y después aplicar el cambio». No pide
permiso aparte, no responde «el editor no lo permite» y no lo hace por fuera:
1. construye en el editor la capacidad que falta — un tipo de bloque, una capa,
   un control del inspector, una función, un campo del tema — **reutilizable**,
   no hecha a la medida de este pedido, con su esquema, su control, su guardado
   y todos sus consumidores (Edit, Vista previa, tienda y, si Google lo lee, el
   snapshot HTML);
2. la verifica como cualquier capacidad del editor;
3. recién con ella aplica lo pedido, como lo haría una persona, y cierra con la
   prueba de ida y vuelta. Lo mismo vale para el HTML que ve Google y para la página
instantánea: son **consumidores** de los dueños del editor, nunca un segundo CMS
`[Repo: copilot-instructions.md «HTML-first storefront evolution is allowed»]`.

**La prueba de ida y vuelta**, para cada valor que un agente crea o cambia `[Repo]`:

1. abrir la superficie real en modo Edit;
2. seleccionar el dueño (bloque, diapositiva, capa, página, categoría, producto,
   menú o ajuste del tema);
3. ver que su control muestra exactamente el valor;
4. cambiar un valor reversible por ese control y confirmar el borrador;
5. comparar Edit con Vista previa;
6. guardar con el «Guardar» global cuando el guardado está autorizado;
7. recargar y ver que el control y la tienda reconstruyen lo mismo;
8. probar el destino o la consulta de productos de verdad, no sólo su valor guardado.

Un precedente propio: el 2026-09-23 los textos SEO del sitio, el `website_name`
de un producto y el bloque «MARCAS» se corrigieron con escrituras SQL directas
sobre sus dueños canónicos (quedaron archivos de reversión `.sql`). Los valores
viven donde el editor los muestra, pero la prueba de ida y vuelta no quedó
registrada: el camino normal es el control o su servicio, y la prueba se hace
`[Repo]`.

## Las otras siete reglas

2. **Un dato, un dueño.** Cada valor tiene una tabla dueña, un control en el
   editor o en el ERP, una sola operación de guardado y consumidores que lo leen
   igual: el lienzo del editor, la vista previa, la tienda Flutter, los snapshots
   HTML, el sitemap, el feed de Merchant y los correos. Un cambio que deja dos
   copias del mismo valor (un texto en el código y otro en `website_settings`)
   está mal aunque se vea bien `[Repo: website-editor-contract.md «Core invariant»]`.
3. **Edit, Vista previa y Publicado significan lo mismo.** La única diferencia
   permitida son los controles de edición (bordes, manijas, barras). Una rama
   `editable ? transformado : crudo` que cambia el contenido es un defecto, y el
   arreglo va en el renderizador compartido, no en los datos de una campaña
   `[Repo]`.
4. **Guardar no es publicar, y publicar no es que Google lo vea.** Guardar
   cambia la base y la tienda Flutter lo muestra al recargar; el HTML que lee
   Google, el sitemap y las redirecciones cambian sólo cuando corre el build de
   la tienda (un push de código o el build diario). Google lo lee cuando vuelve a
   rastrear. Toda afirmación de SEO dice de cuál de los tres planos habla
   `[Repo: website-editor-contract.md «SEO visibility and evidence»]`.
5. **Lo que Google necesita, en HTML.** Flutter web dibuja en un `<canvas>`;
   su propia documentación dice que no sirve para contenido crítico de SEO
   `[FL]`. Por eso cada ficha, categoría y página indexable tiene un snapshot HTML
   con su título, descripción, canonical, JSON-LD y enlaces `<a href>` reales, y la
   app agrega semántica para rastreadores `[GSC]` `[Repo]`. Un contenido nuevo que
   sólo existe dentro de Flutter no existe para Google.
6. **La marca viene del editor, no del código.** Colores, fuentes, logo, textos
   y contacto salen de `website_settings` y de las páginas; el mismo código sirve
   a otra empresa (multi-tenant). Nada de literales de Viñabike en la tienda
   `[Repo: GUI_DESIGN_PRINCIPLES.md «El sitio público no pasa por Design»]`.
7. **Cada consulta filtra por empresa** (`tenant_id`), y lo que un visitante sin
   cuenta puede leer está acotado a columnas y funciones públicas
   ([seguridad](seguridad.md)).
8. **Se demuestra en vivo.** Un cambio de la tienda se cierra con la página real
   (escritorio y teléfono), el HTML desplegado (`release.json` con el commit) y,
   si toca SEO, con lo que Google renderiza (Prueba de resultados enriquecidos)
   `[Repo]`.

## Cómo se ve (2026-09-24, dueño)

El aspecto del sitio lo decide el agente que hace el trabajo: serio, profesional
y con personalidad; nunca «AI'ish» ni infantil (saludos de relleno, baldosas con
ceros, la misma cifra dos veces, todo en cajas iguales) `[Dueño]`. Los valores
salen del tema del editor ([marca-y-tema](marca-y-tema.md)).

## Trampas

- «Arreglar» una campaña o una página en el código porque el editor no tiene el
  control: se agrega el control al editor y se usa.
- Dar por terminado un cambio del sitio sin haberlo reabierto en el editor.
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
