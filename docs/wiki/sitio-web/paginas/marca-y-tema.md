---
titulo: Marca, tema y aspecto
resumen: de dónde salen los colores, fuentes y logo del sitio, quién decide el aspecto y qué le gusta y qué no al dueño
fuentes: [repositorio, referentes]
archivos: [lib/public_store/theme/public_store_theme.dart, lib/public_store/theme/public_store_surface_theme.dart, packages/vinabike_public_core/lib/modules/website/models/website_font_registry.dart, packages/vinabike_public_core/lib/public_store/models/storefront_logo_source.dart, .github/GUI_DESIGN_PRINCIPLES.md]
tablas: [website_settings, tenants]
revisado: 2026-11-17
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
| `theme_accent_color` | naranjo `#FF6F00`: el valor de partida del editor, guardado sin elegir el 2025-12-05 junto con el verde, y además el `defaultAccentColor` de `website_resolved_theme.dart`. En la tienda pinta los botones llenos, la etiqueta «La más completa», el número del carrito y el foco `[Prod 2026-11-01]` |
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
- **Lo que la página ofrece, en la primera pantalla (2026-11-18):** la portada
  de /servicios medía 413 px a 1280 de ancho y la tabla de precios quedaba
  bajo el borde. El dueño: «there's a lot of fucking space between price table
  and the top of this page… make it way more compact and optimized». Es el
  mismo reclamo que hizo dos veces en el ERP («la lista manda», en
  `.github/GUI_DESIGN_PRINCIPLES.md`). Una portada de página interior es una
  franja baja, con título, texto y acción en una o dos líneas. La vara es que
  lo que la página vende (planes, productos, la lista) asome sin bajar en
  1280×720. Se mide con captura real, y también lo que va heredado encima
  ([catálogo](catalogo-y-fichas.md)) `[Dueño]`.
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

- **Partir de la base del sitio vivo (2026-11-01):** la versión 3 de la vista
  previa inventó su encabezado, un logo de texto, sus tarjetas y su pie, y el
  dueño la rechazó: «debiste haber partido por la base que ya estaba y eso
  modificarlo con lo que correspondiera, no hacer un diseño from scratch». La
  versión 4 copia el HTML y el CSS publicados (encabezado, menú de Componentes
  y Accesorios, tarjetas, categorías, marcas, reseñas, pie y botón del chat) y
  cambia sólo lo que el plan cambia `[Dueño]`.
- **Imágenes que no se notan de IA (2026-11-01):** el carrusel de Better Bike
  funciona porque sus imágenes son simples: fondos limpios y figuras que no
  intentan el detalle realista. La vara es la foto del sendero, con el ciclista
  de espaldas y lejos, «el desenfoque justo» y los bordes que se oscurecen.
  Rechazó las manos sucias en el centrador con herramientas detrás («se nota
  mucho que es IA») y la calle mojada «tipo Londres», que «intenta ser realista
  pero le sale a medias». Además, la imagen tiene que calzar con el tema: una
  bici urbana para hablar de tubeless es un error, porque el tubeless es de MTB
  `[Dueño]`.
- **La receta para que una foto generada pase piola (dueño, 2026-11-22):** «nos conviene generar con efectos como blur o fades… porque si intentamos hacer cosas muy detalladas y con efectos cinematográficos, ahí es cuando se ve más IA». Funcionó a la primera, en el destacado de Navidad con la vara de Fox Racing, describir un momento humano y no una escena posada:
  - quién y qué pasa: un papá suelta el asiento en la primera vuelta del niño;
  - cámara: f/2 y 85 mm, fondo deshecho en bokeh y movimiento leve en lo que no es el producto;
  - personas: la cara del niño medio girada y no del todo nítida, el adulto cortado por el cuadro;
  - acabado: colores naturales algo apagados, grano suave, luces que se funden; sin HDR, sin luz de contorno dramática, sin brillo plástico ni simetría perfecta.
  El producto va nítido y sale de su foto del catálogo. La Navidad de Chile es en verano: parque al atardecer, nada de nieve `[Dueño 2026-11-22]`.
- **Productos que destacan (2026-11-01):** como en la portada de GoPro, tonos
  de color, cambios de contraste, bloques, contraste de letra y productos
  puestos en primer plano. Son la lógica y no un molde («no te lo tomes tan
  literal»): las diapositivas no van todas oscuras con letra blanca. La versión
  5 mezcla tres clases. Una es foto, la del sendero. Otra es producto real
  recortado sobre un tono claro u oscuro, con su precio. La tercera es de
  precios en letra grande `[Dueño]`.
- **Sin tonos inventados, y premium (2026-11-01):** la versión 5 puso
  productos sobre un beige y un gris azulado escogidos a mano, y la guía en un
  bloque azul junto a uno beige. El dueño la vio como «la presentación de un
  niño de 5 años» y pidió dejar de elegir colores «horribles o hardcodeados».
  La versión 6 pone los productos sobre las fotos de cerro y de sendero que el
  sitio ya publica en su menú, desenfocadas y oscurecidas solo un poco, con una
  luz suave detrás de cada pieza. La guía tiene una franja que pasa sus piezas
  sola, se detiene al pasar el mouse y queda quieta si el sistema pide menos
  movimiento. Lo que lleva color sale del tema: el azul primario en las
  diapositivas de precios y el acento en los botones `[Dueño]`. **Corregido el
  mismo día:** «para hacer diseños vistosos o elegantes, los colores del tema no
  son los indicados». Lo que rechazó fue ese beige y ese gris azulado, no el
  color fuera del tema. Cada diapositiva lleva el color de su referencia o de su
  producto: negro como Fox y GoPro, rojo como RockShox, el cielo de DJI y el
  azul del empaque de OnGuard. El tema sigue mandando en el resto del sitio
  `[Dueño]`.
- **Imágenes nuevas, de MTB y con poco desenfoque (2026-11-01):** «lo más
  importante para darle vida a la página es ir generando imágenes nuevas
  constantemente», no reusar las fotos del menú. Tienen que ser de MTB:
  bosques, desierto como las carreras de California y Utah, cerros. El
  desenfoque es leve, como en una foto normal. Cuando pedí a Gemini «poca
  profundidad de campo» y «movimiento borroso», las imágenes salieron «todas
  pixeleadas», y encima les agregué desenfoque con CSS. Las dos cosas
  sobraron `[Dueño]`.
- **Sendero solo y luz normal (2026-11-01, más tarde):** detrás de los
  productos no va un ciclista: «puede ser un sendero de MTB nomás», bonito y
  de naturaleza. Tampoco va luz de película: los rayos de sol entre los
  árboles se ven «medio falsos». Pidió buscar fotos reales de senderos en
  Google Imágenes y hacer algo parecido. Esas fotos tienen día nublado o de
  mediodía, verdes y cafés apagados, y el sendero de tierra como la línea que
  guía la vista. También pidió más sombra en la mitad izquierda de la guía,
  para que las piezas de la franja «vayan desapareciendo» en ella. En la
  versión 8 la sombra va encima de la franja y debajo del texto, así las
  piezas se apagan al llegar en vez de cortarse en el borde `[Dueño]`.
- **Cada diapositiva, un diseño distinto (2026-11-01):** «no todos tienen
  que ser iguales… no todos con una letra gigante y botones naranjos…
  tampoco todos con fondo de naturaleza», y «básate en los diseños de las
  referencias que encontraste». La versión 10 usa una referencia por
  diapositiva:
  - Canyon: foto y título chico abajo;
  - RockShox: producto en primer plano y campo de color;
  - Fox: negro y una cifra enorme;
  - Cannondale: dos fotos, una en blanco y negro;
  - Better Bike: estudio claro con un sello redondo;
  - DJI: cielo, título fino y el producto al centro;
  - Commencal: título apilado sobre una foto oscura;
  - GoPro: las piezas juntas sobre negro;
  - SRAM: bloques de color en los bordes.

  Cada una lleva su letra, sus botones y su fondo, y hay una sola foto de
  naturaleza por mes. Además: «para de usar la imagen del mismo neumático
  siempre». Un producto no se repite entre diapositivas ni bloques `[Dueño]`.
- **Afirmar, no preguntar, y que cada diapositiva muestre algo (2026-11-02):**
  - «no abusemos de lo de usar preguntas para llamar la atención… ¿rueda
    chueca?… pregúntanos por WhatsApp… estás abusando de esos recursos».
    Las referencias titulan con afirmaciones («La nueva velocidad», «All-new
    LinearXL») y sus botones dicen «Ver…», «Comprar…» o «Saber más».
    WhatsApp va sólo donde es la acción misma.
  - Una diapositiva que es sólo «un fondo negro con un $4.000 gigante» no
    dice nada.
  - La del centrado de ruedas con la foto del centrador también le pareció
    «pésima»: el destacado promociona una categoría o una marca que llame la
    atención, como Maxxis.
  - La tabla «Precios del taller» va sólo en /servicios y no en la portada.

  `[Dueño]`
- **Planes como los de TradingView (2026-11-01):** los botones «Agendar por
  WhatsApp» quedaban a distinta altura, al final de listas de largo distinto,
  y el dueño lo encontró horrible. La respuesta fue una tabla: los cuatro
  planes en un solo bloque, con el botón bajo el precio y las mismas filas
  con ✓ o ✕ para compararlos. El texto de cada celda sale de la ficha
  publicada de esa mantención, sin agregar nada `[Dueño]`.

  **Corrección 2026-11-18:** esta entrada decía «ahora», pero la tabla
  existió sólo en el lienzo de la portada. El 2 de noviembre el dueño pidió
  sacarla de la portada y dejarla para /servicios. Se borró del lienzo y
  nunca se construyó en la tienda. Dieciséis días después volvió a ver los
  botones escalonados y preguntó si alguien lo había revertido. Se construyó
  ese día ([catalogo-y-fichas](catalogo-y-fichas.md)).

  Lo que se pide sobre un lienzo y cambia de página se anota como pendiente
  del sitio en ese momento ([estado](estado-y-pendientes.md)). Revertir el
  aspecto tampoco borra un arreglo: «vuelve el aspecto de antes del 24 de
  octubre» (`b9af0495`) deshizo también la marca «La más completa», que se
  salía de la tarjeta. Ese defecto siguió en vivo hasta que se publicó la
  tabla, el 2026-11-18.
- **Borde a borde, sin cajas flotando (2026-11-17):** al revisar el lienzo
  de las guías pidió identificar lo que hace que se vea hecho por IA: «no uses
  muchos floating blocks, me gustan el lenguaje visual que va edge to edge»,
  con «simetría y armonía» entre recuadros, secciones y chips. En ese lienzo
  lo delataban:
  - cajas redondeadas flotando sobre blanco, y cajas dentro de cajas;
  - el mismo radio y la misma sombra en todo;
  - chips de anchos distintos, números en círculos de color y etiquetas chicas
    en mayúscula sobre cada título;
  - una portada centrada con degradé, brillos y animaciones;
  - una sección oscura metida al medio para dar énfasis;
  - cifras gigantes y una lista para marcar con porcentaje.

  La versión 7 del lienzo pone en su lugar:
  - bandas a todo el ancho separadas por líneas de 1 px;
  - una sola grilla (dos mitades iguales o tercios), con los títulos en el
    mismo borde;
  - celdas que se tocan en vez de tarjetas;
  - controles como franjas de celdas iguales y tablas de líneas;
  - esquinas rectas y el acento sólo en los dibujos.

  Es lo mismo que ya había aprobado en «Sendero» y en la ficha de producto. Al
  2026-11-17 todavía no responde sobre la versión 7 `[Dueño]`.

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
bici urbana de noche ([el documento](https://claude.ai/artifact/3fn5NfDnTQSx4gkHgyZSkr)). **Corregido el mismo día:** de esas
tres queda sólo el sendero. Al verlas en la portada, el dueño rechazó las manos
y la calle mojada (ver «Imágenes que no se notan de IA», arriba). Cómo generarlas está en la
memoria del agente (Gemini en el Chrome del dueño, gratis; Codex sin cuota
hasta el 16-nov; la API de Google cobra de US$0,034 a US$0,134 por imagen)
`[Prod 2026-11-01]`. La API de imágenes de OpenAI también se paga por uso, sin
ChatGPT. Según sitios que no son de OpenAI, cuesta de US$0,006 a US$0,21 por
imagen de 1024 px, según la calidad. Necesita una llave del dueño con crédito
cargado `[Ref 2026-11-01]`. El dueño está probando Muse, de Meta, que es gratis
`[Dueño 2026-11-01]`.
**Un producto no se edita sobre una edición (2026-11-22).** Cada edición con la API de imágenes redibuja la imagen entera, también lo que se pide «dejar igual». Si la única referencia es la última salida, los defectos se acumulan como en una fotocopia de fotocopia. En el destacado de Navidad, tras cuatro ediciones seguidas (tercera a quinta versión y la foto sin interfaz), la biela y el plato de la Crown se derritieron, el disco y los rayos se desordenaron y la Freestyle perdió su «Royal». El dueño: «cada cambio se van distorsionando más… pareciera que hubiesen estado en Chernobyl». Desde entonces:
- En cada generación, cada producto se dibuja desde su foto del catálogo, que va otra vez como referencia, nunca desde la última salida.
- Lo que es interfaz (textos, encabezado, transición) se itera en HTML, no en la imagen.
- Cada vuelta se compara al 100 % contra la foto del catálogo, pieza por pieza, antes de mostrarla.
Una sola generación desde el catálogo (US$0,089) recuperó las bicis. Si hace falta el producto exacto, el recorte de la foto real (abajo) es la otra vía `[Dueño 2026-11-22]`.
**La escena con gente no es la base de una publicación (2026-11-24).** Tres publicaciones de producto seguidas salieron con un ciclista en un cerro, polvo y luz dorada, porque al dueño le había gustado una foto humana el 22-nov. Las vio y dijo que estaban «un poco exageradas y se nota demasiado que es IA». La causa: una persona en un paisaje es justo donde más se nota (piel, sudor, polvo a contraluz).
- Cada publicación elige su recurso según el producto: estudio, color plano, tipografía, detalle de una pieza, líneas técnicas o, a veces, una escena ([referentes](../fuentes/referentes.md)).
- Lo que salió a la primera: el casco solo sobre un fondo continuo de un color, con luz pareja, sombra de contacto y tres líneas técnicas, pidiendo «no person, no landscape… no dust, no light beams, no film grain».
- Un defecto chico se arregla en la misma imagen con `node scripts/dev/png_patch.mjs`, sin pagar otra generación, que además redibuja el producto. Copia una letra limpia sobre la deformada (`copy`), endereza una letra inclinada (`shear`) o quita un resto de color de una foto en blanco y negro (`mono`). Sirve para letras y restos de pocos píxeles, no para cambiar un objeto. El Mac no tiene PIL ni ImageMagick `[Dueño 2026-11-24]`.
Las fotos de producto que traen texto de AliExpress encima («1000 LUMEN»,
«Choice», medidas) van chicas, en grillas; en los bloques grandes de la portada
sólo van las limpias.
Cómo pedirlas para que salgan nítidas (2026-11-01). Funcionó escribir «shot
like a professional mountain bike photo at f/4 (o f/8 para paisaje): the rider
and the trail are in sharp focus, only the far background slightly soft; no
heavy blur, no motion blur, no grain». También el ciclista de lado o de
espaldas, chico en el cuadro y con ropa y bici lisas, sin letras, logos ni
números. Así salieron nítidos un sendero de noche con el haz de la luz
delantera y un cerro costero con el mar. **Corregido el mismo día:** un bosque
con rayos de sol y un ciclista, y un cañón al atardecer con un ciclista en
silueta, también salieron nítidos, pero el dueño rechazó el bosque por el
ciclista y la luz de película. El cañón tenía lo mismo y se cambió junto con él (ver «Sendero
solo y luz normal», arriba). Lo que salió bien al primer intento fue mirar
antes fotos reales en Google Imágenes y describir lo que muestran: «an empty
mountain bike singletrack trail…», «soft, even overcast daylight» o «bright
midday daylight», «natural muted colors, like an ordinary photo on a trail
guide website», «no people, no bikes, no sun rays, no fog, no sunset, no
dramatic or cinematic lighting», a f/8. Las fotos reales se buscan en el
Chrome del dueño, porque en el navegador de la app Google pide un reCAPTCHA
por «tráfico inusual». Si
Gemini contesta «Soy un modelo de lenguaje, así que no tengo esa capacidad», se
repite empezando con «Generate an image (16:9 photo):» y un texto más corto.
Un producto real se recorta de su foto con
`swift scripts/dev/cut_out_product.swift <foto> <salida.png>`, que usa Vision.
El 2026-11-01 salieron limpios 7 de 9: el neumático, el candado, dos luces,
el kit de tripas, el sellante y las válvulas. La luz con flechas dibujadas y el
bombín en su bolsa no sirvieron. Casi todas las fotos del catálogo miden entre
200 y 450 px, así que van a menos de 400 px de alto. La del Maxxis Rekon
(800 px) es la única que aguanta media diapositiva `[Prod 2026-11-01]`.
**Corregido el mismo día:** no era la única. Sólo había mirado neumáticos,
luces y candados. Con stock y foto limpia de 500 px o más también están:
- el cassette Shimano HG400 de 9 velocidades (1200 px);
- el neumático Kenda Moser 29 (1038 px);
- la cadena KMC X9 (748 px);
- el bombín de pie Billy (967 px de alto);
- el candado espiral OnGuard (500 px).

`[Prod 2026-11-01]`

## Publicaciones de producto (2026-11-24)

Diapositivas del destacado que venden un producto traído por la API del
proveedor. El dueño corrigió tres veces el mismo día, y las tres son la misma
regla: un «me gusta» aprueba esa pieza, no una plantilla.

- **Ni siempre persona al aire libre, ni siempre producto en estudio.** Cada
  publicación parte de otra referencia y cambia el recurso gráfico, la
  estructura (dónde va el texto y dónde el producto), el fondo y la letra.
- **El tono no cambia: MTB y aventura.** Tierra, polvo medido, curvas de
  nivel, cortes en diagonal, letra pesada, condensada o inclinada, negro y
  colores de tierra con un acento fuerte. Un fondo crema, una paleta suave o
  una serif de revista leen a moda.
- **Antes de cada una se mira una marca nueva** en su propio sitio y se anota
  en [referentes](../fuentes/referentes.md) lo que se vio.
- **El texto es de tienda, no de afiche (2026-11-25).** «Baja sin miedo.»,
  «Sube con calor. Baja tranquilo.» y «Que el cerro se ponga bravo.» le
  sonaron «cliché y AI»: «dale un tono más de tienda real». Una publicación
  dice qué es, de qué marcas, desde cuánto, si está en stock o cuándo llega,
  cómo se retira y la ayuda por WhatsApp, con cada dato comprobado en vivo.
  El «desde» es el precio más bajo que el sitio muestra. Una publicación de
  categoría no lista medidas («No incluyas tallas»).
- **El elástico de una cámara es negro y delgado (2026-11-25).** La imagen
  los trajo anchos y color caucho claro, y el dueño lo vio al tiro: «el
  elástico de las cámaras es siempre negro». Antes de dibujar un accesorio se
  mira en la foto del catálogo cómo viene de verdad.
- **Un objeto mal dibujado no se pinta encima: se vuelve a generar
  (2026-11-25).** Oscurecí los tres elásticos píxel a píxel y el dueño dijo
  «se ven super falsos… quedó super mal». La causa: lo malo no era sólo el
  color. Una banda ancha y plana pintada de negro sigue siendo ancha y plana,
  sin el relieve ni la sombra de un elástico delgado. Funcionó a la primera
  editar la imagen con «keep it exactly as it is… change only the rubber
  band», describiendo el elástico real y con las fotos del catálogo como
  referencia; las cajas no cambiaron ni una letra.
- **Lo que viene en caja se muestra con su caja (2026-11-25).** «Casi nunca
  he visto que marcas promocionen cámaras con las cámaras sueltas… son con su
  caja al lado». La caja sale de la foto del catálogo, que va como referencia,
  y sólo se nombran en el texto las marcas que el sitio muestra.
- **Varios productos no van en fila (2026-11-25).** «Estás haciendo mucho eso
  de poner un producto al lado de otro. Muchas tiendas o marcas los agrupan,
  los ponen juntos en diferentes ángulos». Tampoco sirvió amontonarlos sobre
  el mismo asfalto con una lista de precios al lado («no me gustaron.
  Ninguna»): se leía a volante de ofertas. Las marcas de accesorios los
  muestran puestos y en uso, o en juegos chicos y limpios.
- **La letra es seria (2026-11-25).** «No me están gustando las letras que
  estás usando a veces. Esa letra… está super infantil», por una redonda tipo
  VAG Rounded. Con la serif cursiva que leyó a moda, son dos familias fuera.
  Al generador se le nombran dos tipos concretos y se le prohíbe por nombre
  lo redondo y lo juguetón. Si la publicación es de una marca, su nombre va
  en su propio logotipo, con el logo de `product_brands.logo_url` como imagen
  de referencia. Cuando rechaza una letra se revisan las demás del tablero:
  la serif de bloque de las mantenciones también se cambió.
- **«Sutil y real» no es quieto (2026-11-25).** Para los neumáticos pidió
  «una publicación de Maxxis con algún rider… no la hagas tan exagerada… más
  sutil, que se vea cool, pero real». La primera respuesta fue un ciclista en
  polera, casi detenido, con el neumático gigante adelante: real y sin
  gracia. Lo exagerado son los efectos (polvo a contraluz, rayos, luz
  dorada). Lo que hace buena una foto de carrera es de verdad y se pide por
  su nombre: barrido con el fondo corrido, la bici llenando el cuadro,
  posición de ataque, casco integral y antiparras (sin cara hay menos que
  delate a la IA).
- **La pregunta antes de mostrar (2026-11-25):** ¿saldría esto en la portada
  de esa marca? Cumplir al pie de la letra la última frase del dueño dio tres
  rechazos seguidos, y cada uno le costó una vuelta. De un sitio de
  referencia se anota qué hace la foto, no sólo qué muestra
  ([referentes](../fuentes/referentes.md)).
- **Sin GPT y sin recortes: las publicaciones se hacen en Claude Design
  (2026-11-26).** Corrige lo de arriba sobre pedirle la diapositiva a GPT.
  El dueño, al ver la vuelta del 25-nov: «están demasiado IA, cosas deformes,
  que no tienen forma clara… el marco de la bicicleta se funde con la
  estructura del bike lock»; luego «evitar crear imágenes que tengan muchos
  detalles juntos», y al final «stop fucking using gpt, you do the designs on
  claude design». La causa: el generador redibuja el producto, y lo que tiene
  muchas piezas juntas sale deforme (bici con estacionamiento y candado, tacos
  de un neumático vistos de frente, el centro de un cassette, texto chico
  grabado). Una vuelta «simple» con un objeto por imagen mejoró las formas,
  pero el cassette todavía se volvía maraña al 100 % y el dueño ya había
  decidido. Cómo se hace ahora:
  - El tablero «Publicaciones hechas en Claude Design» del
    [lienzo](https://claude.ai/artifact/Pw8w5mWFtp3wLbgJzR3KKa) arma cada una
    en HTML, a 1440 × 750 y 390 × 750. El encabezado real se copia del
    tablero «Destacado de Navidad en HTML». Las letras son Oswald y Barlow,
    las del sitio, y los colores también son los del sitio.
  - Sólo fotos reales: catálogo o distribuidor (la de MKR del XS-1270 mide
    1500 px). **No se recorta el fondo:** al recortar a mano fotos de 200 a
    900 px quedaron bordes claros y blancos encerrados («you are cropping
    products background like shit»). La foto va entera con
    `mix-blend-mode: multiply` sobre un fondo claro, y su blanco desaparece.
    El color de marca va en un bloque aparte con el texto.
  - Con multiply, dos fotos se tiñen donde se cruzan: sólo se tocan por partes
    negras (el bombín sobre el cable del candado).
  - Sin foto real (el taller) no se inventa. La diapositiva es letra y
    precios, con curvas de nivel en vectores.

| Publicación | Recurso y estructura | Parte de | Qué dijo el dueño |
|---|---|---|---|
| RockShox Lyrik, original | Foto de acción; texto en una franja de sombra abajo | Fox | «también me gustó» |
| Smith Forefront 2 | Producto solo en estudio, fondo claro, líneas técnicas; texto a la izquierda | POC | «una dirección mucho mejor» |
| RockShox Lyrik, alternativa | Número gigante en contorno detrás del producto, fondo oscuro | RockShox | sin comentario |
| Leatt 3DF 5.0, mosaico | Cuatro bloques de color ortogonales, macro de textura, serif cursiva | Apple | «parece publicidad de ropa o perfumes» |
| Leatt 3DF 5.0, en diagonal | Tres paneles cortados en diagonal: foto de acción a un tono, producto sobre naranja, texto sobre carbón con curvas de nivel | YT Industries | «muchísimo mejor» |
| Cámaras en general | Bodegón sobre la tierra de un sendero, sin persona, cada cámara con su caja al lado; texto centrado arriba en letra de rótulo de taller; texto de tienda y sin medidas | Tubolito | «me gustó mucho», y pidió las cajas: las marcas no muestran cámaras sueltas |
| Mantenciones del taller | Pared de herramientas teñida de azul, sin personas; tres columnas con los precios de /servicios | Park Tool | sin comentario; la serif de bloque se cambió por una industrial condensada |
| Cassette SRAM XS-1270 | Pieza gigante cortada por el borde, una línea del piñón de 10 al de 52, letra cuadrada | SRAM | sin comentario |
| Neumáticos, dibujos en diagonal | Tres bandas de dibujo vistas desde arriba | Schwalbe | «weird as fuck, look for better references» |
| Neumáticos, de pie en fila | Tres neumáticos de frente sobre oscuro, título gigante detrás | Maxxis (línea de producto) | «no me gustó tampoco»; pidió Maxxis con un rider |
| Neumáticos Maxxis, foto tranquila | Ciclista en polera en una curva, el neumático en primer plano, texto chico | Maxxis (fotos de carrera) | «no me gustaron. Ninguna» |
| Neumáticos Maxxis, en barrido | Foto de carrera en barrido, la bici llena el cuadro; «Maxxis» en su logotipo | Vittoria y Maxxis | sin respuesta al 2026-11-25 |
| Accesorios, en fila | Cuatro productos en fila vistos desde arriba, precios en cinta | Schwalbe y Knog | letra «super infantil»; «mucho eso de poner un producto al lado de otro» |
| Accesorios, agrupados | Un grupo en tres cuartos sobre el asfalto, lista de precios al lado | Lezyne | «no me gustaron. Ninguna» |
| Accesorios, en uso | Bici de ciudad amarrada en la calle con los cuatro productos puestos; cada precio unido a su producto por una línea | Kryptonite, Knog y Topeak | «el marco de la bicicleta se funde con la estructura del bike lock» |
| Mantenciones, en Claude Design | Carta de precios: los tres planes de /servicios en filas, curvas de nivel en vectores sobre azul | Pirelli (un sistema para todo el carrusel) | sin respuesta al 2026-11-26 |
| Cassette XS-1270, en Claude Design | Foto de MKR entera sobre gris claro; el modelo como titular | Shimano y SRAM | sin respuesta al 2026-11-26 |
| Neumáticos Maxxis, en Claude Design | Foto del Assegai entera sobre claro; texto en grafito con corte en diagonal | Pirelli y YT Industries | sin respuesta al 2026-11-26 |
| Accesorios, en Claude Design | Tres productos con stock juntos sobre claro; texto en un bloque naranjo | ABUS | sin respuesta al 2026-11-26 |

Sin usar todavía: el producto en abanico de colores, una mano que lo
presenta, el mismo producto repetido en grilla, recortes en blanco y negro
sobre bloques de color, las manos trabajando la pieza, letras en casillas y
una ilustración. Falta pasar el texto de tienda a la Leatt, la Lyrik y el
Smith, cuyas frases van dibujadas en la imagen: se hace al armarlas en HTML. Las
imágenes están en el tablero «Publicaciones de producto» del
[lienzo](https://claude.ai/artifact/Pw8w5mWFtp3wLbgJzR3KKa) `[Dueño 2026-11-24]`.

## Trampas

- Un color o una fuente escrita en el código del sitio: rompe el multi-empresa y
  la paridad con el editor.
- `header_nav_links` (con URL `/tienda/...`) es una clave vieja que el código ya
  no lee; los menús son de `website_navigation`.
- Contraste: el texto sobre el primario navy tiene que ser claro; el editor usa
  `public_header_contrast.dart` para el encabezado.
- **Una clase de la tienda HTML es global**: cada página carga
  `storefront_css.dart`, así que una palabra corta ya tomada (`.sheet`,
  `.cart`, `.foot`, `.order`) le pega su regla a otra parte. Pasó cuatro veces,
  cada una costó una vuelta; la última, `.stock.order`, escondía «A pedido» en
  el teléfono (la fila «Ordenar por» es `.order` y se esconde ahí). Una clase
  nueva lleva el nombre de su dueño (`pt-`, `cart-page`, `on-order`,
  `srch-order`), y la prueba «no class is both a global rule and another
  part's modifier» (`services/storefront_html/test/storefront_handler_test.dart`)
  falla si una clase con regla propia aparece como modificador de otra
  (2026-11-03; encontró además `.pt-steps.sheet`, ahora `.pt-in-sheet`).
- Un lienzo de Claude Design se mira antes de entregarlo.
  `scripts/dev/design_board_shot.cjs` lo dibuja en local, con props, `--blob
  id=archivo` y `--mobile`. Lo que se revisa es la copia local, no el lienzo. El
  2026-11-01 no lo encontré, porque ninguna página lo nombraba, y armé otro
  igual.
- **El lienzo envuelve cada valor interpolado en `<span class="sc-interp">`
  (2026-11-20).** Una regla de la hoja real sobre un `span` descendiente le
  cae también a ese texto. Con `.stock span`, el punto verde de 6 px, la línea
  «Despacho en 3 a 5 días hábiles» salió en el teléfono del dueño una palabra
  por renglón y encima del resto. La herramienta de dibujo no envolvía los
  valores y no lo mostró; desde ese día los envuelve igual que el lienzo. En un
  tablero, el texto interpolado va en elementos con clase propia, y ninguna
  regla nueva apunta a un `span` suelto.
- **Una ficha «de marca grande» tiene un orden (2026-11-20).** El dueño pidió
  tomar como referencia páginas de bicicletas de prestigio internacional. La
  de Leatt y la de Specialized coinciden en el orden:
  1. marca, nombre y precio;
  2. el color como fotos chicas y la talla como botones, con las que faltan
     tachadas y la guía de tallas al lado;
  3. un solo recuadro de entrega y un botón fuerte;
  4. las garantías y los detalles plegados.

  Así quedó el tablero «Ficha con tallas y colores» del lienzo «Vinabike.cl
  con vida». La primera versión, la ficha de hoy con botones agregados, al
  dueño le pareció «un poco desordenada». La segunda: «muchísimo mejor… ahora
  casi no se nota que es IA». La diferencia fue ordenar sin borrar
  (`.github/GUI_DESIGN_PRINCIPLES.md`, «Ordenar sin borrar»): lo secundario
  bajó de peso en vez de desaparecer. Sin quedar minimalista ni perder vida.
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
- Ícono de la pestaña: `web/favicon-32.png`, `-48` y `-64` (2026-11-13),
  sacados del maestro de 512 px con un recorte centrado en el lienzo (el
  logo ocupa el 82 % del ancho). El maestro trae el logo un poco arriba del
  centro, porque la llave pesa menos que las letras: la primera versión lo
  recentró por su caja y el dueño lo vio caído («no se ve centrado como
  antes»); un ícono se acerca, no se recompone.
  Chrome puntúa cada ícono declarado contra 16 y 32 px y descarga uno solo:
  con sólo el de 16 y el de 192 ganaba el de 16 por calce exacto (el de 192
  pierde por demasiado grande frente a 16) y una pantalla Retina lo mostraba
  estirado al doble, pixelado `[Dueño 2026-11-13]`. Con el de 32 declarado
  gana ése. Los declaran `web/index.html` y, para cada página del servidor
  HTML, `sitePage` (`site_layout.dart`), antes del de 16 `[Repo]`.
