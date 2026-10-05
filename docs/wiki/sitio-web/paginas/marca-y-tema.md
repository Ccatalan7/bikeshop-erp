---
titulo: Marca, tema y aspecto
resumen: de dónde salen los colores, fuentes y logo del sitio, quién decide el aspecto y qué le gusta y qué no al dueño
fuentes: [repositorio]
archivos: [lib/public_store/theme/public_store_theme.dart, lib/public_store/theme/public_store_surface_theme.dart, packages/vinabike_public_core/lib/modules/website/models/website_font_registry.dart, packages/vinabike_public_core/lib/public_store/models/storefront_logo_source.dart, .github/GUI_DESIGN_PRINCIPLES.md]
tablas: [website_settings, tenants]
revisado: 2026-10-03
---

# Marca, tema y aspecto

## Lo esencial

El aspecto del sitio sale del **tema del editor** (`Tema`, claves `theme_*` y
`header_*` de `website_settings`), nunca de literales en el código: el mismo
código sirve a otra empresa y el editor, la vista previa, la tienda y la página
instantánea leen los mismos valores `[Repo]`.

## El tema de Viñabike (2026-10-03)

| Clave | Valor |
|---|---|
| `theme_primary_color` | navy `#123F68` (desde el 2026-09-26; antes un verde guardado sin elegir el 2025-12-05) |
| `theme_accent_color` | naranjo `#FF6F00` («te necesita» en el portal) |
| `theme_background_color` / `theme_text_color` | blanco / negro al 87 % |
| `theme_heading_font` / `theme_body_font` | Oswald / Barlow |
| `theme_heading_size` / `theme_body_size` | 48 / 16 |
| `theme_section_spacing` / `theme_container_padding` | 64 / 24 |
| `header_style`, `header_bg_color`, `header_color_mode` | `sticky`, blanco, `auto` |

Flutter dibuja Oswald, que es una fuente variable, en su instancia por
defecto: un título «bold» sale con los anchos de letra del 400 y el trazo
engordado por Skia. La tienda HTML lo imita (`400` y `-webkit-text-stroke`);
con un `700` real los títulos de la ficha cortaban una línea antes
`[Repo 2026-10-05]`.

Los colores se guardan como enteros ARGB (p. ej. `4279385960` = `#FF123F68`) y los
lee `parseWebsiteThemeColorValue`, el mismo lector para tema, tienda e instantánea
`[Prod]` `[Repo]`.

**Logo:** `logo_url` del sitio → `tenants.logo_url` → el logo empaquetado (sólo
en la tienda canónica). Hoy `logo_url` está vacío y se usa el siguiente
(`storefrontFirstLogoSource`, `StorefrontLogoResolution`) `[Prod]`.

## Quién decide el aspecto

- **Sitio público, desde el 2026-09-24:** el agente que hace el trabajo, sin pasar
  por Design ni esperar valores de una guía. **Todo el ERP, desde el 2026-09-27**
  `[Dueño]` (`.github/GUI_DESIGN_PRINCIPLES.md` «El sitio público no pasa por
  Design» y «El diseño del ERP es abierto»).
- Lo que no cambia: la marca (colores, fuentes, logo) la pone el dueño en el
  editor; el agente decide composición, jerarquía y piezas con esos valores.

## El gusto del dueño

- Quiere un sitio **serio, profesional y con personalidad**; no aburrido.
- No quiere lo «AI'ish and childish»: saludos y lemas de relleno («sin
  fricción»), baldosas de métricas con ceros, la misma cifra dos veces, todo en
  cajas iguales (2026-09-24) `[Dueño]`.
- Aprobó «Sendero» para el portal (2026-09-26): la estética de las marcas MTB —
  contenedores rectos, títulos condensados en mayúsculas, un solo acento, líneas
  de 1 px, foto a sangre ([portal-de-clientes](portal-de-clientes.md)).
- Le gusta proponer en un lienzo de Claude Design antes de un cambio grande, con
  datos reales, y después construirlo.

## Trampas

- Un color o una fuente escrita en el código del sitio: rompe el multi-empresa y
  la paridad con el editor.
- `header_nav_links` (con URL `/tienda/...`) es una clave vieja que el código ya
  no lee; los menús son de `website_navigation`.
- Contraste: el texto sobre el primario navy tiene que ser claro; el editor usa
  `public_header_contrast.dart` para el encabezado.

## En el código y la base

- Tema: `public_store_theme.dart`, `public_store_surface_theme.dart`,
  `WebsiteResolvedTheme` / `WebsiteThemeBuilder` en el editor, fuentes en
  `website_font_registry.dart`.
- Claves: `theme_*`, `header_*`, `logo_url` en `website_settings`;
  `tenants.logo_url`.
