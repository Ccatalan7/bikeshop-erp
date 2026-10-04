# Ficha de producto en HTML (prueba)

Prueba de la migración del sitio a HTML
(`docs/architecture/storefront-html-migration-plan.md`). Un servidor Dart que
arma una ficha de producto en cada visita, con datos reales y en sólo lectura:

- lee las mismas funciones públicas que la tienda Flutter
  (`get_public_products`, `get_public_product_technical_specs`,
  `get_public_store_data`, `get_public_online_shipping_tiers`) y las tablas de
  lectura pública `website_navigation`, `website_pages`, `product_categories`,
  `product_brands` y `products` (campos `website_*`);
- importa sin copiar el núcleo Dart de la tienda: proyección comercial, ficha
  técnica, texto SEO, rutas de categoría, tema, horario y datos estructurados.

No es la tienda: no tiene carrito (el botón lo dice), declara `noindex` y no
reemplaza ninguna ruta pública.

## Correrla

```bash
bash tool/storefront_html_prototype/run.sh
```

Abre `http://localhost:4325/` (redirige a la horquilla `H911`); cualquier ficha
publicada sirve con `/productos/<nombre>/<sku>`. La llave publicable sale del
Llavero de macOS (`Vinabike ERP Supabase publishable key`) o de
`SUPABASE_PUBLISHABLE_KEY`. Con `.claude/launch.json` se puede abrir con
`preview_start`; no se detiene con señales genéricas (el hook las bloquea).

## Medirla

```bash
node tool/storefront_html_prototype/measure.mjs "http://localhost:4325/productos/horquilla-suntour-29-auron-35-eq-lo-rc-160mm-15x110mm-blanco-2022/H911" prueba 3
```

Celular lento (1,6 Mbps, 150 ms, CPU ×4, 412×823), perfil nuevo por carga,
mediana. Con la URL de vinabike.cl mide la tienda actual: «lista» es cuando
Flutter retira la página instantánea. Resultados del 2026-10-04 en el plan.

Una captura de página completa (`fullPage`) no desplaza la página, así que las
fotos con `loading="lazy"` (relacionados, miniaturas) salen como cuadros
vacíos. Antes de capturar hay que recorrer la página con `scrollTo` y esperar
`img.complete && naturalWidth > 0`. La primera captura del 2026-10-04 salió así.
