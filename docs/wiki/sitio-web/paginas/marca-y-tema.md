---
titulo: Marca, tema y aspecto
resumen: de dónde salen los colores, fuentes y logo del sitio, quién decide el aspecto y qué le gusta y qué no al dueño
fuentes: [repositorio, referentes]
archivos: [lib/public_store/theme/public_store_theme.dart, lib/public_store/theme/public_store_surface_theme.dart, packages/vinabike_public_core/lib/modules/website/models/website_font_registry.dart, packages/vinabike_public_core/lib/public_store/models/storefront_logo_source.dart, .github/GUI_DESIGN_PRINCIPLES.md]
tablas: [website_settings, tenants]
revisado: 2026-11-01
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
- **Que el sitio tenga vida (2026-11-01):** moderno, premium y aventurero, con un
  poco más de MTB sin cerrar la puerta a otras bicis. Sus referencias: GoPro,
  DJI, Canyon, Fox, Cannondale, Commencal, RockShox, SRAM y los talleres con ese
  gusto. Que la portada cambie y nunca prometa algo que no se hace `[Dueño]`.
  El plan quedó en el documento [«Darle vida a vinabike.cl»](https://claude.ai/artifact/3fn5NfDnTQSx4gkHgyZSkr).
- **Imágenes generadas, sí, «pero bien hechas» (2026-11-01):** el contraejemplo
  es una tienda de Viña que publicó portadas con bicis mal dibujadas `[Dueño]`.
- **Las referencias se miran, no se leen (2026-11-01):** la primera vista previa
  salió de los títulos y botones de esas páginas, bajados con un script y sin
  verlas, y el dueño la encontró «AI'ish», a años luz de ellas. La segunda (v3,
  mismo lienzo) partió de capturas a 1440 px y tomó lo que repiten todas: una
  foto a todo el ancho con 3 a 6 palabras enormes y uno o dos botones; blanco,
  negro y gris con un solo acento; titulares condensados en mayúscula; producto
  sobre un gris parejo; pocas secciones grandes; el taller como foto oscura con
  sus precios, como «Service» en SRAM y RockShox. De Better Bike (tienda
  chilena, referencia del dueño) tomó el buscador visible y la fila de marcas
  `[Dueño]`.

## Imágenes generadas (2026-11-01)

Una imagen generada se revisa pieza por pieza al 100 % antes de subirla, y se
descarta si falla una: cadena en un solo lazo (plato, cassette y las dos
roldanas), cassette y cambio a la derecha, discos a la izquierda, dos bielas
opuestas, una maza y rayos parejos por rueda, una manilla por lado y un solo
cambio, manos de cinco dedos, ni una letra ni un logo inventado, y luz sin HDR.
El texto va encima, como texto del editor; un paisaje generado no dice que es
Viña. Lo que falló en la prueba del 2026-11-01, con Gemini: en 2 de 3 bicis
enteras vistas por el lado de la cadena, el disco delantero quedó de ese lado;
en el primer plano de la transmisión, la cadena dio una vuelta alrededor de
nada. Al pedir una corrección, Gemini sacó el disco pero inventó letras en los
neumáticos, y a la segunda devolvió el disco: cada versión se revisa de nuevo.
Salieron bien el sendero visto desde atrás, las manos en el centrador y una
bici urbana de noche ([el documento](https://claude.ai/artifact/3fn5NfDnTQSx4gkHgyZSkr)). Cómo generarlas está en la
memoria del agente (Gemini en el Chrome del dueño, gratis; Codex sin cuota
hasta el 16-nov; la API de Google cobra de US$0,034 a US$0,134 por imagen)
`[Prod 2026-11-01]`. La API de imágenes de OpenAI también se paga por uso, sin
ChatGPT. Según sitios que no son de OpenAI, cuesta de US$0,006 a US$0,21 por
imagen de 1024 px, según la calidad. Necesita una llave del dueño con crédito
cargado `[Ref 2026-11-01]`. El dueño está probando Muse, de Meta, que es gratis
`[Dueño 2026-11-01]`.
Las fotos de producto que traen texto de AliExpress encima («1000 LUMEN»,
«Choice», medidas) van chicas, en grillas; en los bloques grandes de la portada
sólo van las limpias.

## Trampas

- Un color o una fuente escrita en el código del sitio: rompe el multi-empresa y
  la paridad con el editor.
- `header_nav_links` (con URL `/tienda/...`) es una clave vieja que el código ya
  no lee; los menús son de `website_navigation`.
- Contraste: el texto sobre el primario navy tiene que ser claro; el editor usa
  `public_header_contrast.dart` para el encabezado.
- Un lienzo de Claude Design se mira antes de entregarlo.
  `scripts/dev/design_board_shot.cjs` lo dibuja en local, con props, `--blob
  id=archivo` y `--mobile`. Lo que se revisa es la copia local, no el lienzo. El
  2026-11-01 no lo encontré, porque ninguna página lo nombraba, y armé otro
  igual.
- En titulares condensados en mayúscula con interlineado bajo 0,95, el acento
  de Á, É, Í, Ó y Ú choca con la línea de arriba: en «PINCHAZOS / CÁMARA» la C
  pareció una Ç. La tilde de la Ñ se corta si el bloque tiene `overflow:hidden`.

## En el código y la base

- Tema: `public_store_theme.dart`, `public_store_surface_theme.dart`,
  `WebsiteResolvedTheme` / `WebsiteThemeBuilder` en el editor, fuentes en
  `website_font_registry.dart`.
- Claves: `theme_*`, `header_*`, `logo_url` en `website_settings`;
  `tenants.logo_url`.
- Íconos: `web/favicon.png` (16 px) y `web/icons/Icon-192.png` (el «VB» con la
  llave), que Hosting sirve en la raíz. `web/index.html` los declara para la
  tienda Flutter y, desde el 2026-10-24, `sitePage` (`site_layout.dart`,
  `storeIconPath`) para cada página del servidor HTML; `/favicon.ico` responde
  301 al de 192 px. Antes las páginas HTML no declaraban ninguno y
  `/favicon.ico` daba 404 desde la migración: la pestaña salía sin marca y
  Google no tenía ícono para el resultado `[Prod 2026-10-24]`.
