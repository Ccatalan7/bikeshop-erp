# Wiki del sitio web — índice

vinabike.cl y el editor del sitio del ERP: cómo están armados de punta a punta,
qué pide Google y el oficio, qué está en vivo y qué falta. Cómo se mantiene:
[README.md](README.md). Qué cambió: [log.md](log.md).

## Empezar aquí

- [Cómo se juzga un cambio en el sitio](paginas/principios.md) — **regla 1: lo
  que hace un agente queda hecho como en el editor, nunca en paralelo** (y la
  prueba de ida y vuelta); un dato un dueño, paridad Edit/Preview/público,
  guardar ≠ publicar ≠ Google, HTML para Google, marca desde el editor.
- [Mapa del sistema](paginas/mapa-del-sistema.md) — editor → base → build →
  Firebase → Worker → navegador, con cada tabla, función y archivo dueño.
- [Estado y pendientes](paginas/estado-y-pendientes.md) — qué está en vivo, qué
  falta y de quién depende.

## El editor y el contenido

- [El editor del sitio](paginas/editor-del-sitio.md) — dos planos de control,
  espacios de administración, bloques, guardar, teléfono.
- [Marca, tema y aspecto](paginas/marca-y-tema.md) — colores, fuentes, logo,
  quién decide el aspecto y el gusto del dueño.
- [Rutas, redirecciones y navegación](paginas/rutas-y-navegacion.md) — cada URL
  pública, qué se indexa, redirecciones, 404, menús.
- [Publicación y despliegue](paginas/publicacion-y-despliegue.md) — cuándo lo
  guardado llega al HTML de Google, el build de la tienda, `release.json`, el
  build diario y «Publicar» desde el editor.

## Catálogo y comercio

- [Catálogo, categorías y fichas](paginas/catalogo-y-fichas.md) — qué producto
  sale y por qué, agotados, categorías, facetas, búsqueda.
- [Carrito, checkout y pedidos online](paginas/checkout-y-pedidos.md) — pagos,
  reservas de stock, estados, correos.
- [Portal de clientes](paginas/portal-de-clientes.md) — `/cuenta`, dirección
  «Sendero», lo pendiente.

## Google y rendimiento

- [SEO de los referentes y lo que nos falta](paginas/seo-de-referentes.md) —
  medición en vivo de Oxford Store, Better Bike, Cycling Store, Canyon y otros
  contra vinabike.cl; las brechas en orden de impacto.
- [SEO técnico](paginas/seo-tecnico.md) — cómo lee Google una tienda Flutter,
  snapshots, canonical, sitemap, centro SEO, cómo leer Search Console.
- [Datos estructurados (JSON-LD)](paginas/datos-estructurados.md) — qué
  declaramos, qué pide Google, qué falta.
- [Merchant Center y perfil de Google](paginas/merchant-y-perfil-de-google.md) —
  la suspensión, el feed, la ficha de Google y las reseñas.
- [Rendimiento y carga](paginas/rendimiento.md) — peso de Flutter, página
  instantánea, Core Web Vitals, imágenes, borde.
- [Medición](paginas/medicion.md) — eventos GA4, píxel de Meta, consolas.

## Seguridad e historia

- [Seguridad y privacidad](paginas/seguridad.md) — qué puede leer un visitante,
  un cliente y el personal; lo que se cerró y no se reabre.
- [Historia y decisiones](paginas/historia.md) — de Odoo a Flutter, refactors,
  diagnóstico de septiembre, decisiones vigentes del dueño.

## Fuentes

- Externas: [Google Search Central](fuentes/google-search-central.md) ·
  [Merchant Center](fuentes/merchant-center.md) · [web.dev](fuentes/web-dev.md) ·
  [Flutter web](fuentes/flutter-web.md) · [GA4](fuentes/ga4.md) ·
  [schema.org](fuentes/schema-org.md) · [tiendas de referencia](fuentes/referentes.md)
- Internas: [contratos del repositorio](fuentes/repositorio.md) ·
  [consolas de Google](fuentes/consolas-google.md)
- Wiki hermano: [compatibilidad de partes](../compatibilidad/index.md) (fichas
  técnicas que muestra la tienda).
