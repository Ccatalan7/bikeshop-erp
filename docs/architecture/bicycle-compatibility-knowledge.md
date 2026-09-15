# Conocimiento de bicicleta para las fichas técnicas

Fecha de consulta inicial: 2026-09-05; ampliación de cadenas/conectores: 2026-09-06.
Estado: investigación documentada con implementación incremental; no constituye
un catálogo exhaustivo de compatibilidad. El resultado de cada entrega registra
las reglas efectivamente desplegadas. Fuentes base elegidas por el dueño:
**Sheldon Brown y Park Tool**. Fabricantes complementan los modelos y generaciones.
Contrato consumidor: [arquitectura de fichas](product-technical-specifications-contract.md).

## Cómo conservar y utilizar este conocimiento

Cada afirmación siguiente tiene un ámbito y una fuente. Es una síntesis propia,
no una copia de artículos o tablas. Los identificadores K01–K30 permiten vincular
futuras reglas, fixtures y preguntas con su evidencia.

- Una guía mecánica explica qué comparar. Una tabla del fabricante identifica
  qué combinaciones concretas declara ese fabricante. Una medición describe un
  ejemplar. Son evidencias distintas; ninguna se convierte en otra por inferencia.
- Registrar autor/editor, título, URL, sección/página, fecha de consulta,
  revisión/modelo/mercado, afirmación y exclusiones. «Consultado hoy» no significa
  «publicado hoy». Sheldon incluye artículos de otros autores y revisiones de
  John Allen; atribuir la página concreta, no todo a Sheldon personalmente.
- Una afirmación histórica, un consejo de reparación o una combinación que
  funciona con modificaciones no se transforma en aprobación general moderna.
- Ante desacuerdo, comparar el ámbito. Una prohibición específica del modelo
  impide certificar ese montaje aunque una guía general describa intercambios
  posibles. Conservar ambos testimonios y la razón; no votar por mayoría.
- No almacenar textos comerciales, artículos completos ni imágenes ajenas.
  Conservar referencias y hechos acotados. Una página inaccesible deja un hueco,
  no autoriza inventar el dato. Las páginas citadas se consultaron por navegador
  de investigación o contenido indexado; no se presupone haber inspeccionado
  visualmente todas las tablas PDF enlazadas.

## Transmisión

### K01 — Las velocidades no identifican por sí solas una cadena

El paso, ancho interior, anchura exterior, forma de placas y rodillos y sistema
de cierre son dimensiones distintas. El paso habitual de 1/2″ tampoco prueba
intercambiabilidad. El número de piñones traseros no es el número de marchas
totales de una bicicleta. Las fichas deben preguntar qué magnitud se declara.
[Park Tool: Chain Compatibility](https://www.parktool.com/en-us/blog/repair-help/chain-compatibility).

### K02 — KMC y compatibilidad entre marcas pueden coexistir

KMC X8 Silver/Grey, referencia BX08NG114, declara 6/7/8 velocidades, medida
1/2″ × 3/32″ y longitud de pasador de 7,3 mm. Su versión europea consultada
incluye 114 eslabones. Por tanto, para **esa referencia**, 11/128″ contradice
su especificación. No afirmar que es el modelo de los screenshots: allí no se
ve un identificador suficiente.
[KMC Europe: X8 Silver/Grey](https://www.kmcchain.eu/products/x8-silver-grey).

La página estadounidense X8 declara compatibilidad Shimano, SRAM y Campagnolo
y 116 eslabones. Es evidencia de que marca comercial y destinos compatibles
son ejes diferentes, y de que «X8» sin variante/mercado no fija el contenido.
[KMC USA: X8](https://kmcchain.us/products/x8).

### K03 — 11/128″ tampoco significa universal 9–11

La KMC X11 declara 1/2″ × 11/128″ y compatibilidad con los sistemas de 11
velocidades indicados en su ficha. Esa medida no permite convertirla en una
cadena universal de 9, 10 y 11 velocidades.
[KMC USA: X11](https://kmcchain.us/products/x11).

Un ancho nominal, una medida de laboratorio entre placas y una longitud de
pasador no deben compartir campo sin definir el método. El esquema conservará
qué se midió; no impondrá bandas numéricas universales para deducir velocidades.

### K04 — Un conjunto de velocidades válido puede depender del sistema

KMC eGlide declara compatibilidad **sólo** con LINKGLIDE de 9/10/11 velocidades.
Es una relación condicionada, no tres números independientes de la plataforma.
[KMC USA: eGlide](https://kmcchain.us/products/eglide).

La documentación de Shimano muestra además cassettes LINKGLIDE de 9 velocidades
que admiten cadenas LINKGLIDE/HG de 11. Se debe registrar la fila concreta de
compatibilidad y sus componentes, sin igualar las velocidades comerciales de
todos los componentes del conjunto.
[Shimano: catálogo E-BIKE 2026, sección CS-LG400-9 / CS-LG300-9 / CN-LG500](https://si.shimano.com/en/pdfs/sm/2026_E-BIKE_CAT_US/SM-2026_E-BIKE_CAT-000-ENG-US.pdf).

### K05 — SRAM Eagle, Road Flattop y T-Type requieren distinción

SRAM excluye el intercambio de la cadena Road Flattop con Eagle convencional.
[SRAM: Road Flattop y Eagle](https://support.sram.com/hc/en-us/articles/6526784724379-Will-a-road-Flattop-chain-work-on-a-SRAM-Eagle-drivetrain-and-vise-versa).
También distingue T-Type de Road Flattop; documenta un montaje mixto con
volante Road 1x y cambio/cassette T-Type que conserva cadena T-Type. Una regla
«todo el grupo de la misma marca/disciplina» rechazaría esta excepción válida.
[SRAM: T-Type y transmisión AXS de ruta](https://support.sram.com/hc/en-us/articles/13821170884891-Can-I-use-the-XX-SL-or-other-SRAM-Eagle-Transmission-T-type-chains-on-my-AXS-road-drivetrain).

### K06 — El cierre es otra pieza con compatibilidad propia

MissingLink 7,3 mm ML57305 enumera KMC X8/Z8.3/Z7/Z6 y cadenas Shimano
6/7/8. La referencia, geometría y condición de reutilización son parte de la
ficha del conector; «incluye missing link» sólo describe el contenido del pack.
[KMC: Missing Link 8/7/6](https://kmcchain.us/products/missing-link-7-3).
Usar «eslabón rápido» como nombre genérico y reservar MissingLink/PowerLock para
sus líneas comerciales. No deducir el conector a partir de la marca de la caja.

**Ampliación 2026-09-06 — anatomía y alcance del conector.** Tipo de cierre,
clase de cadena admitida, modelos objetivo, reutilización y sentido son ejes
distintos. CL573R declara X8/Z8.3/Z7/Z6; CL571R declara Z8.1 aunque la URL diga
«single-speed». CL552 declara cadenas de 12 velocidades de las familias
enumeradas, excluye cualquier Flattop y no es reutilizable. Una coincidencia
de marca o número no reemplaza esas condiciones. Dos placas de un cierre
rápido cuentan como un conector completo; no convertir «2 piezas» de un nombre
en cantidad de cierres.
[KMC CL573R](https://www.kmcchain.com/en/product/connector-missing-link-cl573r-8s-7s-6s-speed),
[CL571R](https://www.kmcchain.com/en/product/connector-missing-link-cl571r-8s-single-speed),
[CL552](https://www.kmcchain.com/en/product/connector-missing-link-cl552-12-speed).

Un pasador nuevo de unión es una pieza de reemplazo específica; la punta guía
no es el ancho exterior del cierre montado. El mandato de usar un pasador nuevo
de Shimano no se debe atribuir a una frase de Park que sólo habla de marca y
modelo. No trasladar reglas de reutilización de una familia de cierre a otra.
[Sheldon: Chains](https://www.sheldonbrown.com/chains.html),
[Park: Chain Replacement](https://www.parktool.com/en-us/blog/repair-help/chain-replacement-derailleur-bikes).

**Medidas y presentaciones.** El glosario KMC describe cadenas anchas de 8–10 mm:
7,8 mm no es un techo universal. Los conteos deben ser enteros positivos, sin
techo universal de 136 eslabones. El catálogo KMC Europa 2026, revisión de junio,
página PDF 30 / impresa 59, separa Z8.3 BZ08NG114 (114), DISPLAY WPZ8NG116
(116) y rollo WRZ8GY000. Sólo la primera presentación se incorporó en esta
entrega. Z6 BZ06G0114 declara 5/6 en web y 6 en ese catálogo: conservar la
discrepancia y posponer su referencia. Un tamaño de muestra usado para pesar
una cadena tampoco identifica el contenido del envase.
[Glosario KMC](https://www.kmcchain.eu/service/glossary),
[catálogo KMC 2026](https://www.datocms-assets.com/104526/1781274377-kmc-2026-dealer-catalogue-en-260612.pdf),
[Z6](https://www.kmcchain.eu/products/z6-grey).

### K07 — Posibilidad mecánica y aprobación no son lo mismo

Sheldon/John Allen describe intercambios de cadenas algo más estrechas en
transmisiones antiguas, con compromisos de funcionamiento. Eso impide afirmar
«11/128 nunca puede moverse en 8 velocidades», pero no prueba compatibilidad
de una referencia desconocida. Mantener el montaje documentado como caso
acotado, con condiciones, y no como una regla para todas las cadenas modernas.
[Sheldon Brown: Speeds, sección Chains](https://www.sheldonbrown.com/speeds.html).

### K08 — Cassette, rueda libre y piñón fijo son ramas distintas

En la rueda libre roscada el mecanismo de rueda libre forma parte del conjunto
que se enrosca; en el cassette permanece en la maza. La interfaz de montaje y
la herramienta de extracción son propiedades distintas.
[Park Tool: Freewheel Removal and Installation](https://www.parktool.com/en-us/blog/repair-help/freewheel-removal-and-installation).
Los cassettes también tienen excepciones de retención y espaciadores; registrar
el cuerpo concreto, no sólo «Shimano» o «SRAM».
[Park Tool: Cassette Removal and Installation](https://www.parktool.com/en-us/blog/repair-help/cassette-removal-and-installation).

### K09 — Los adaptadores hacen que la relación sea direccional

SRAM permite un cassette XD sobre cuerpo XDR con espaciador de 1,85 mm; un
cassette XDR requiere cuerpo XDR. «Compatible con adaptador» debe incluir qué
pieza y en qué dirección. No fabricar una equivalencia XD = XDR.
[SRAM: Eagle Transmission, Cassette Installation](https://docs.sram.com/en-US/publications/5jblJ4SRpeHwjcuWG1vPy4/UM%20-%20Transmission?installation-or-maintenance-=maintenance).
Campagnolo también documenta un kit N3W para cassettes anteriores concretos:
un nombre de cuerpo no sustituye la tabla del cassette/adaptador.
[Campagnolo: Hyperon, Accessories](https://www.campagnolo.com/us-en/hyperon/WWRHYPERON.html).

### K10 — Indexación, capacidad y montaje son requisitos separados

Los mandos indexados posicionan el cambio mediante desplazamientos de cable;
un mismo número de velocidades no fija esa relación. El desviador delantero
tiene además montaje, tiro, geometría y configuración de platos propios.
[Sheldon Brown: Derailer Adjustment](https://www.sheldonbrown.com/derailer-adjustment.html),
[Sheldon Brown: Front Derailers](https://sheldonbrown.com/front-derailers.html).
Para homologar un conjunto: comprobar también capacidad total, piñón máximo,
combinación de platos, línea de cadena y límites del modelo. Las fórmulas
geométricas pueden descartar; no reemplazan una tabla de indexación.

### K11 — Marchas internas y piñones externos no son el mismo eje

Las mazas con cambios internos pueden requerir recorridos de cable desiguales
entre marchas. Igualar el promedio o el número de posiciones no prueba que
dos mandos sean intercambiables. Registrar familia/modelo y secuencia admitida;
en sistemas híbridos mantener separado el cambio interno y el cassette.
[Sheldon Brown: Internal Gear Hub Cable Pull](https://sheldonbrown.com/cribsheet-IG-cable-pull.html).

### K12 — Coincidir en BCD es necesario en ciertos montajes, no suficiente

El patrón incluye cantidad de pernos, distribución y simetría. Hay patrones
asimétricos; pueden existir otras restricciones aun cuando coincidan agujeros.
Los direct mount necesitan su interfaz/revisión, no un BCD ficticio.
[Sheldon Brown: Crank/Chainring BCD](https://www.sheldonbrown.com/cribsheet-bcd.html).

### K13 — Interfaz de patilla y sistema de accionamiento son independientes

UDH describe una interfaz de cuadro. Full Mount elimina la patilla en el
montaje que lo requiere. No significa que cualquier conjunto trasero sea
compatible ni que todo T-Type sea electrónico: SRAM también publica Eagle
70/90 mecánicos. Modelar montaje, transmisión y control por separado.
[SRAM: Understanding UDH and Full Mount](https://www.sram.com/en/learn/understanding-udh-and-full-mount),
[SRAM: Eagle 70/90](https://support.sram.com/hc/en-us/articles/34719461229595-Does-Eagle-90-and-Eagle-70-Transmission-shift-as-well-as-AXS-Transmission-systems).

## Ruedas, neumáticos y cámaras

### K14 — El diámetro de asiento del talón manda sobre el nombre en pulgadas

La designación ISO distingue ancho y BSD. «26 pulgadas» tiene varios diámetros
incompatibles; 700C y 29 suelen nombrar BSD 622, pero eso no decide ancho,
holgura ni tubeless. Mantener el código nominal como alias contextual.
[Sheldon Brown: Tire Sizing Systems](https://www.sheldonbrown.com/tire-sizing.html).

### K15 — Tubeless se evalúa como conjunto

Neumático, llanta, cinta, válvula y sellante deben formar una combinación
admitida. Compartir la palabra «tubeless» no prueba que los componentes encajen.
[Park Tool: Tubeless Tire Compatibility](https://www.parktool.com/en-us/blog/repair-help/tubeless-tire-compatibility).
La descripción histórica de llantas con gancho de esa guía no debe convertirse
en una prohibición de hookless: Schwalbe documenta modelos TLE/TLR admisibles
con límites de ancho y presión del fabricante de la llanta, incluso al usar
cámara. La aprobación debe quedar ligada al modelo/año.
[Schwalbe: Hookless](https://www.schwalbe.com/en/technology-faq/hookless/).

### K16 — Ancho de neumático y ancho de llanta son dos magnitudes

Además del BSD, se debe contrastar el ancho interior de la llanta con el ancho
del neumático y la tabla admitida. La anchura montada depende de la llanta;
una etiqueta no certifica la holgura del cuadro.
[Schwalbe: Tire Dimensions](https://www.schwalbe.com/en/technology-faq/tire-dimensions/).

### K17 — Un rayo no tiene «aro compatible» como medida intrínseca

La longitud necesaria depende de geometría de llanta/maza y patrón de armado:
ERD, bridas, desplazamientos, perforaciones y cruces. «Rayo para 27,5» no basta.
Guardar la longitud real del repuesto y evaluar la rueda de destino aparte.
[Sheldon Brown / John Allen: Spoke Length](https://sheldonbrown.com/spoke-length.html).
La coincidencia del número de agujeros corresponde al armado convencional;
existen armados especiales documentados. No confundirlos con montaje directo.
[Sheldon Brown: Special Spoking](https://www.sheldonbrown.com/special-spoking.html).

## Pedalier, dirección y puntos de contacto

### K18 — El pedalier conecta dos interfaces independientes

Primero caja del cuadro: roscada o pressfit, estándar y anchura. Después,
interfaz de biela/eje. BB30, PF30 y PF41 no son sinónimos; el número puede
describir dimensiones distintas. «24 mm» no determina por sí solo la caja.
[Park Tool: Bottom Bracket Standards and Terminology](https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-standards-and-terminology).
Las roscas BSA, italiana, francesa y suiza tampoco se colapsan por diámetro
parecido; conservar paso y sentido por lado.
[Sheldon Brown: Threaded Bottom Brackets](https://www.sheldonbrown.com/cribsheet-bottombrackets.html).

### K19 — SHIS describe por separado la dirección superior e inferior

EC, ZS e IS son construcciones diferentes. SHIS combina tipo y código del
asiento con la interfaz de horquilla; su código de diámetro no siempre es la
medida exacta de taller. Un conjunto puede mezclar tipos arriba y abajo.
[Park Tool: SHIS](https://www.parktool.com/en-us/blog/repair-help/standardized-headset-identification-system).
En repuestos de rodamientos conservar también dimensiones y ángulos de contacto,
especialmente para referencias antiguas.
[Park Tool: Headset Standards](https://www.parktool.com/en-us/blog/repair-help/headset-standards).

### K20 — Diámetros de tija, collarín y tee no son intercambiables

Una tija debe coincidir con el alojamiento; un diámetro cercano no equivale a
compatibilidad. Una camisa reductora es una pieza adicional identificable.
[Park Tool: Seatpost Removal and Installation](https://www.parktool.com/en-us/blog/repair-help/how-to-remove-and-install-a-seatpost).
La tee tiene interfaces con horquilla y manubrio; conservar ambas.
[Park Tool: Threadless Stem](https://www.parktool.com/en-us/blog/repair-help/stem-removal-installation-threadless).
No usar tablas históricas de tijas como valor por defecto para cuadros actuales.
[Sheldon Brown: Seatpost Sizes](https://www.sheldonbrown.com/seatpost-sizes.html).

### K21 — La tija telescópica necesita más que diámetro y recorrido

Longitud total, inserción disponible, altura útil y accionamiento/ruteo
condicionan el montaje. El recorrido deseado es requisito del usuario, no
prueba de que esa tija cabe en el cuadro.
[Park Tool: Dropper Size and Compatibility](https://www.parktool.com/en-us/blog/repair-help/determining-dropper-post-size-and-compability).

### K22 — Pedal, biela, cala y zapatilla forman interfaces distintas

La rosca tiene lateralidad: el pedal izquierdo no se instala como el derecho.
[Park Tool: Pedal Installation](https://www.parktool.com/en-us/blog/repair-help/pedal-installation-and-removal).
SPD y SPD-SL son sistemas separados; el patrón de fijación de la zapatilla es
otro requisito y no garantiza por sí solo la retención con cualquier pedal.
[Shimano: Indoor Footwear Technology](https://bike.shimano.com/technologies/details/indoor-footwear-technology.html).

## Frenos, cables y suspensión

### K23 — Accionamiento mecánico no significa tiro universal

Los V-brake convencionales requieren una relación de tiro distinta de frenos
convencionales de tiro corto. Una manilla de posición incorrecta o sin ajuste
admitido no queda validada por ser de la misma marca.
[Sheldon Brown: Direct-pull Cantilevers](https://www.sheldonbrown.com/canti-direct.html).
Hay discos mecánicos para tiro de ruta y para tiro largo; se declara por modelo.
[Sheldon Brown: Disc Brakes](https://www.sheldonbrown.com/disc-brakes.html).

### K24 — Rotor, maza, cáliper y adaptador tienen comprobaciones propias

Diámetro, espesor, pista de frenado, interfaz de maza y posición del cáliper
deben concordar. El lockring también puede tener restricciones por eje. No
usar un límite de desgaste genérico como espesor nominal del producto nuevo.
[Park Tool: Disc Rotor Removal and Installation](https://www.parktool.com/en-us/blog/repair-help/disc-brake-rotor-removal-installation).

### K25 — La pastilla se identifica por forma/interfaz, no por marca de freno

La geometría del respaldo y retención corresponden al cáliper. La composición,
aletas y espesor son atributos separados. Exigir lista de modelos o interfaz
documentada antes de declarar equivalencia entre referencias.
[Park Tool: Disc Brake Pad Removal and Installation](https://www.parktool.com/en-us/blog/repair-help/disc-brake-pad-removal-installation).

### K26 — Fluido y conexión hidráulica requieren un ámbito exacto

DOT y aceite mineral son circuitos de servicio distintos; las herramientas de
purga no se comparten contaminadas entre ambos. La familia de fluido no prueba
que cualquier manguera, oliva, inserto o manilla sirva en cualquier cáliper.
La receta y los repuestos deben apuntar al modelo/manual concreto.
[Park Tool: instrucciones BKD-1.2](https://www.parktool.com/assets/doc/product/BKD-1.2_instructions_EN.pdf).

### K27 — Funda de cambio y funda de freno no son la misma pieza

La construcción habitual de funda indexada de cambio no es adecuada para
frenado. Registrar uso certificado, construcción, diámetro y terminales.
No convertir esto en «toda funda sin compresión es de cambio»: una funda de
freno expresamente diseñada para ese uso necesita su propia referencia.
[Sheldon Brown: Cables](https://sheldonbrown.com/cables.html).

### K28 — Suspensión exige modelo y revisión para repuestos de servicio

Una guía Park Tool de Pike describe una generación concreta: su volumen de
aceite no debe aplicarse a toda horquilla con el mismo diámetro de barras.
[Park Tool: RockShox Pike Service](https://www.parktool.com/en-us/blog/repair-help/rockshox-pike-suspension-fork-service).
La arquitectura debe vincular kits, fluido y ajustes al manual del modelo/año,
sin inferirlos desde la disciplina MTB.

### K29 — Largo entre ojos, carrera y recorrido de rueda son diferentes

El shock necesita largo, carrera, montaje y herrajes; la holgura se comprueba
durante todo el movimiento. Igual largo entre ojos no garantiza montaje.
[RockShox: Rear Suspension Fitment](https://www.sram.com/en/service/articles/RockShox-fitment-article).
Cambiar la carrera también depende del cuerpo y piezas internas de la revisión.
[RockShox: Eyelet and Damper Shaft Service](https://www.sram.com/globalassets/document-hierarchy/service-manuals/rockshox/rear-suspension/2023-eyelet-and-damper-shaft-replacement-service-manual-english.pdf).

### K30 — La herramienta compatible depende de la interfaz de servicio

Forma, diámetro y cantidad de muescas de extracción son campos propios. No
deducir la herramienta sólo del sistema instalado en la bicicleta.
[Park Tool: Bottom Bracket Tool Finder](https://www.parktool.com/en-int/category/crank-bottom-bracket/tool-finder).

## Límites y ampliaciones pendientes

La [matriz de familias](product-spec-family-matrix.md) cubre las 36 familias
presentes y las extensiones que requieren las categorías reales. Esto no
significa que estén verificadas todas sus referencias comerciales.

Antes de activar reglas de e-bike/electrónica se necesitan tablas exactas de
batería, cargador, tensión, conector, protocolo y firmware de cada proveedor.
Esta ronda no obtuvo una fuente Bosch suficientemente específica para sembrarlas.
Tampoco certifica cascos, cargas de portaequipajes, productos químicos,
rodamientos industriales ni tallas de ropa: sus campos se diseñan, pero la
validación de cada modelo necesita fuentes propias. El motor devolverá
«sin confirmar» mientras falte esa cobertura, sin retirar la familia del ERP.


### K31 — Diferencia de montaje actual no es incompatibilidad universal (2026-09-06)

Sheldon [Tire Sizing](https://www.sheldonbrown.com/tire-sizing.html) distingue rótulos comerciales del BSD: 700C y 29 pulgadas comparten 622 mm, y un rótulo 24 pulgadas puede designar varios diámetros. Por tanto comparar sólo `wheel_size` no prueba montaje ni incompatibilidad. El BSD y el intervalo de ancho de una cámara deben pertenecer a la misma declaración; cubierta/llanta requieren además construcción y límites OEM.

Park Tool [Rotor Removal & Installation](https://www.parktool.com/en-us/blog/repair-help/disc-brake-rotor-removal-installation), artículo del 2018 consultado el 2026-09-06, separa sustitución de mismo diámetro de cambio de tamaño con cáliper/adaptador. Que el rotor instalado sea 180 no demuestra que 203 esté prohibido: faltan los límites del cuadro/horquilla y la configuración concreta. Tampoco lo autoriza. No reutilizar sus ejemplos de espesores como límites universales actuales.

El [artículo de válvulas de Jobst Brandt en Sheldon](https://www.sheldonbrown.com/brandt/presta-schrader.html) distingue diámetros de vástago/orificio. El tipo de válvula instalado no es una medición del agujero real ni una declaración de adaptación; una diferencia exige verificar agujero, base, longitud y uso admitido. El scorer conserva estos casos como revisión pendiente, con los datos necesarios explícitos, sin aprobar taladrados ni adaptaciones.


### K32 — Código de interfaz y medida real no son intercambiables (2026-09-06)

[Park Tool, SHIS](https://www.parktool.com/en-us/blog/repair-help/standardized-headset-identification-system), consultado hoy, distingue el código de alojamiento del diámetro medido: EC34 no declara un agujero medido de 34 mm. Conservar código, tolerancia/medición y extremo superior/inferior por separado. La suma de altura superior e inferior también consume espiga; el diámetro nominal por sí solo no resuelve montaje. Las tablas históricas incluyen sistemas obsoletos y ejemplos con diferencias internas: no generar diccionarios universales sólo redondeando cifras.

[Shimano C-731](https://productinfo.shimano.com/en/compatibility/C-731), consultada hoy, exige conservar las notas por cassette/cuerpo. CS-HG800, CS-HG700 y CS-RS400 de ruta 11v son excepciones explícitas: HG spline M figura compatible y HG spline L requiere espaciador de 1,85 mm. No extrapolarlo a todo cassette de 11v ni a LINKGLIDE, cuya tabla es C-649. La longitud exterior del cuerpo de la tabla es una medición con superficies de referencia definidas, no el nombre genérico «Shimano».

### K33 — La pieza, su configuración y su herramienta tienen interfaces distintas (2026-09-06)

El [Mallet Enduro](https://www.crankbrothers.com/products/mallet-e) combina
mecanismo de cala, pines y apoyos interiores/exteriores de diferente
construcción. El tipo comercial del pedal no puede excluir pines ni forzar
un único tipo de rodamiento. Las calas incluidas son contenido de la edición,
no una consecuencia de ver calas en un despiece.

El [clampset Ritchey WCS Carbon 1-Bolt](https://ritcheylogic.com/bike/seatposts/wcs-carbon-1-bolt-seatpost-complete-clampset)
documenta una cobertura concreta de rieles para su kit 7x10. No convierte
7x9, 7x9.6 y 7x10 en una geometría única ni prueba que ese kit venga incluido.
La ficha conserva geometría, material, modelo de abrazadera y piezas de cada
configuración por separado.

[Park Tool, cassette removal](https://www.parktool.com/en-us/blog/repair-help/cassette-removal-and-installation)
indica herramientas FR-5.2 para la interfaz de servicio de SRAM XD. Se
rechaza la propuesta «extractor HG no sirve en XD»: el montaje del cassette
sobre el cuerpo no es la interfaz donde trabaja el extractor.

### K34 — Opciones independientes no deben excluirse (2026-09-06)

[Julbo REACTIV 2-4 Polarized](https://www.julbo.com/en_gb/sunglasses/photochromic-2-4-polarized-sunglasses)
declara fotocromía y polarización en la misma lente. Se registran propiedades
por lente/variante, conservando cuáles se incluyen. La evidencia de una lente
no se extiende a las otras presentaciones del mismo anteojo.

### K35 — El fluido no determina el accionamiento ni la superficie (2026-09-07)

[TRP HY/RD](https://eu.trpcycling.com/products/hy-rd) recibe cable y tiene un
circuito hidráulico en el cáliper; [MAGURA HS33](https://magura.com/product/hs/)
es hidráulico y frena sobre la llanta. Ninguno autoriza la inferencia
`fluido informado → disco hidráulico`. El consumidor retiró esa inferencia,
manteniendo pendientes las interfaces que no conoce de la bici. Alcance,
fuentes fundamentales y prueba: [integración de frenos](../development/product-specs-research-2026-09-05/brake-consumer-integration-2026-09-07.md).

### K36 — Identidad de una fila requiere su alcance (2026-09-07)

Una columna obligatoria no se vuelve por ello una clave física. El
[ABUS GRANIT XPlus 540](https://www.abus.com/usa/Products/Bicycle-locks/U-Locks-Bike/GRANIT-XPlus-540)
figura en dos programas Sold Secure con niveles distintos. El
[Topeak MTX TrunkBag DXP](https://www.topeak.com/us/en/product/122-mtx-trunkbag-dxp)
tiene estados de expansión. Emisor y componente, o nombre de miembro, no
identifican programa, edición o estado. Sólo se prohíbe un duplicado cuando la
identidad completa está demostrada; una igualdad de texto no sustituye esa
demostración. Las contradicciones con alcance incierto siguen sin confirmar.

### K37 — Presión y dimensiones conservan qué se midió (2026-09-07)

El [AirBooster G2](https://www.topeak.com/us/en/product/1202-AIRBOOSTER%20G2)
declara una escala de manómetro, no una presión garantizada al inflar. La
estimación con CO2 necesita cartucho, neumático, cantidad y condiciones. Una
botella con fijación propietaria tiene dimensiones físicas aunque el diámetro
de acople con un portabidón de aro no le corresponda. La referencia de la
medida y la configuración se conservan junto al valor.

### K38 — MAX y contacto angular pueden coexistir (2026-09-07)

[Enduro 7001 1ZS MAX](https://cycling.endurobearings.com/products/7001-1zs-max)
contradice tanto MAX sin canal de llenado como MAX excluyente de contacto
angular. Diseño interno, retención de elementos, sellado y geometría exterior
son ejes distintos. Los dos ángulos de apoyo de un cartucho de dirección
descritos por [Park Tool](https://www.parktool.com/en-us/blog/repair-help/headset-standards)
no son el ángulo interno entre bolas y pistas. No se solicitan biseles de
cartucho a una bolsa de bolas sueltas.

### K39 — Una función integrada no crea un kit (2026-09-07)

[ABUS PURL-Y ACE](https://www.abus.com/int/Consumer/Bike-helmets/Urban/PURL-Y-ACE)
incluye una luz trasera recargable con fijación magnética;
[Noxgear Tracer2](https://www.noxgear.com/tracer2) es un chaleco con iluminación
LED. Una identidad comercial puede combinar funciones. La categoría no basta
para prohibirlas, ni permite tratar toda función integrada como otra pieza
entregada en la caja. El contenido debe estar documentado para esa edición.

`kit_members` declara piezas, cantidades, posición y texto de marca/modelo;
ese texto no enlaza productos del catálogo ni les atribuye sus medidas o
certificaciones. La ausencia de familia conserva una fila pendiente, sin
inventar una clasificación. El estrechamiento de `light` resuelve sus dos
tablas de miembros y no se extiende a otras plantillas. La revisión PUB-D01
que proponía extenderlo fue retirada tras comprobar qué datos posee cada
tabla. Buscar sólo nombres literales en código no demuestra que no existan
lectores genéricos: también se revisa la proyección y el papel semántico.

### K40 — Formato, función, contenido y alcance son ejes distintos (2026-09-07)

[Topeak HYBRIDROCKET HP](https://www.topeak.com/global/en/product/407-HYBRIDROCKET-HP)
combina minibomba e inflador CO₂. El formato manual no excluye esa capacidad;
el cartucho incluido y los cartuchos admitidos son declaraciones distintas.
El booleano de capacidad adicional sólo aplica cuando el formato no la declara
ya. Su ausencia no significa «no». No se excluyen otros formatos por analogía.

La [CamelBak M.U.L.E. 5 Waist Pack](https://www.camelbak.com/product/m.u.l.e.%C2%AE-5-waist-pack-with-crux%C2%AE-1.5l-lumbar-reservoir/CB-2815.html)
se vende como riñonera con depósito Crux de 1,5 L. El depósito incluido no es
capacidad de alojamiento para uno opcional. El alcance de carga/hidratación
y el alcance por unidad/conjunto deben poder expresarse simultáneamente.
La lectura disponible no confirma qué incluye el volumen nominal del bolso:
no restar 1,5 L de un nombre comercial ni inventar una capacidad de carga.

[Sheldon Brown](https://www.sheldonbrown.com/tire-sizing.html) distingue las
designaciones nominales del diámetro de asiento. Un rango nominal en pulgadas
puede comprobar su orden sin convertir sus extremos a BSD. Una lista OEM no
se convierte en un intervalo continuo, y ninguna de esas declaraciones prueba
por sí sola holgura, fijación o carga de un accesorio.

[Park Tool INF-2](https://www.parktool.com/en-us/product/shop-inflator-inf-2)
publica la escala del manómetro en psi y bar. Se conservan ambas unidades con
su magnitud; no se convierten en dos capacidades de trabajo ni se reemplaza
una cifra publicada por una conversión calculada. El cero u otro origen de
escala se conserva en la declaración si importa; no se asume universalmente.

Corrección de revisión DL-5: `legacy` ya retira el campo de validación,
coherencia y escritura de hechos; la UI conserva la observación para revisión.
`allowed_when: never` con rol activo representa una incompatibilidad de campo,
no una retirada. Tampoco se ofrece un campo legacy o una tabla por miembro
como predicado escalar de compras; un criterio guardado que el editor no
pueda expresar se conserva al guardar cambios en otros campos.

### K41 — El apriete conserva rango, unidad y configuración (2026-09-07)

[ODI v2.1](https://www.odigrips.com/pages/install) publica un rango de apriete
en in-lb y Nm, junto con condiciones de material, diámetro y fijación. Un
escalar no representa ese rango: convertirlo silenciosamente en su máximo
cambia la declaración. La ficha separa valor nominal, intervalo y máximo,
conserva las unidades publicadas y comprueba el orden sólo dentro del intervalo
de una misma fila. No compara las cifras OEM redondeadas entre unidades.

El [manual Ergon GP1 de 06/2014](https://www.ergonbike.com/infocenter/downloads/manual_gp1.pdf),
página 2, publica el apriete en Nm y ft-lb. Ambas lecturas conservan su modelo
y edición, igual que las longitudes por lado de la versión Rohloff/Nexus.
Ninguna de esas cifras se copia a otros puños como un ajuste universal.

[Park Tool](https://www.parktool.com/en-us/blog/repair-help/handlebar-grip-installation-flat-bars)
distingue el ajuste por fricción/interferencia de los puños deslizantes y
la fijación mediante collarín de los lock-on. El interior físico medido y
el diámetro nominal previsto ya tenían nombres y papeles distintos en la
ficha; CP-1 no demostraba que dos números diferentes fueran incompatibles.
La medición necesita zona y condición —pieza libre o montada—, sin inventar
una igualdad ni una tolerancia universal que el fabricante no haya declarado.

### K42 — Diámetro, paso y uso de una pieza de rueda son ejes separados (2026-09-07)

[Park Tool, Basic Thread Concepts](https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts)
documenta el eje de 10 mm × 26 TPI. La unidad del diámetro no determina la
del paso; un selector único «métrica/pulgadas» excluía esa pieza real. Las
dos unidades se declaran por separado, sin conversión ni paso supuesto.
La [guía de llaves de radios](https://www.parktool.com/en-us/blog/repair-help/spoke-wrench-tool-selection)
distingue geometría y posición de herramienta; calibre del radio y tamaño de
llave no son intercambiables. El [TRA225](https://robertaxleproject.com/product/12mm-thru-axle-for-trainer-180-mm-with-1-25-mm-thread/)
justifica conservar paso 1,25 mm, longitud y configuración exacta; no prueba
que otra longitud, asiento u OLD sea equivalente.

El [VP-1C de Park](https://www.parktool.com/en-us/product/vulcanizing-patch-kit-vp-1)
declara materiales de cámara admitidos y excluye TPU y cuerpo de neumático
tubeless. Una excepción del [artículo UST](https://www.parktool.com/en-int/blog/repair-help/tubeless-tire-mounting-and-repair)
pertenece a su superficie y condiciones; no autoriza toda la familia de parches.
El [Topeak TFV-05](https://www.topeak.com/us/en/product/1440-VALVE-EXTENDER-28MM)
necesita obús desmontable; la condición corresponde al extensor que reubica
el obús, sin proyectarla a todos los extensores.

### K43 — Material de la espiga y superficie de anclaje son distintos (2026-09-07)

El [manual Cervélo de horquilla v3](https://cervelo.cdn.prismic.io/cervelo/ffe12d7a-81fc-499c-981e-65904298ad93_fork_owners_manualv3.pdf),
página impresa 3, prescribe un inserto de aleación suministrado con araña
preinstalada. Refuta el bloqueo basado sólo en «araña + espiga de carbono».
El contacto directo con carbono y el anclaje en un inserto OEM necesitan
declaraciones distintas; el inserto conserva identidad, objetivo, fuente y
condiciones. No autoriza un manguito cualquiera ni hereda un procedimiento
de montaje a otra horquilla. Se corrigió el candidato antes de publicarlo.

La [ficha Wolf Tooth del expansor](https://www.wolftoothcomponents.com/products/compression-plug)
no convierte el rango de espiga metálica en medida universal de toda espiga.
El par de tapa y el de expansión conservan sus elementos, unidades y condiciones.
La [ficha FOX FLOAT DPS PERFORMANCE](https://ridefox.com/products/fox-float-dps-performance)
publica tamaños por referencia: longitud y recorrido se conservan juntos,
con unidades y extremos vinculados a esa configuración. No sustituir una
referencia por una etiqueta visible al enlazar filas.

### K44 — Alcance OEM y configuración individualizan un veredicto (2026-09-07)

[Wolf Tooth RoadLink](https://www.wolftoothcomponents.com/pages/roadlink-tech-page)
separa DM y Standard, cambio, velocidades, jaula/capacidad y montaje. Su lista
DM clasifica 11–42 como aceptable y 10–42 sin soporte, aunque un comentario
adicional declara mejora parcial para este último. El apartado de fuente y
su salvedad se conservan; una mejora parcial no se transforma en soporte OEM.
Un límite de piñón máximo no debe inventar el menor de un cassette. Dos
veredictos opuestos para una configuración completa requieren adjudicación.

[Sheldon, Lockring](https://www.sheldonbrown.com/gloss_l.html) distingue rosca
del anillo, objetivo, generación y piñón exterior; el anillo de piñón fijo no
posee también la rosca derecha del piñón. [OneUp V2, junio 2023](https://int.oneupcomponents.com/blogs/bashguides-chainguides/bashguard-chainguide-install-instructions)
publica placas de cobertura distinta: placa disponible no implica placa incluida.
La presentación debe individualizar el estado instalado.

### K45 — Cable, extremo, funda y forro conservan sus ámbitos (2026-09-07)

[Sheldon](https://www.sheldonbrown.com/cables.html) excluye para frenos la funda
longitudinal de cambio sostenida por plástico. [Jagwire KEB](https://www.jagwire.com/en/article/154-585/brake-housing-5mm-keb-slick-lube)
usa refuerzo Kevlar: sin compresión no identifica una sola construcción. El
veredicto de uso y construcción pertenecen a la misma fila; no basta el nombre
de la marca. El diámetro interno sigue desconocido si la fuente no lo publica.

Las tablas OEM indexadas de [Universal Sport XL](https://jagwire.com/products/diy-cable-kits/universal-sport-xl-brake-kit)
y [Elite Link 2017](https://jagwire.com/products/diy-cable-kits/2017mountain-elite-link-brake-kit)
muestran largos distintos por miembro y un forro más largo que los segmentos
metálicos que cubre. Las rutas directas no fueron legibles: esas tablas no se
presentan como un catálogo vivo de 2026. [Odyssey M2](https://shop.odysseybmx.com/collections/odyssey-gyros/products/odyssey-m2-dual-upper-cable-black)
sí publica 440 mm en su página; el modelo M2 no es el perfil de una cabeza.
Universal se conserva como designación, no como número o aprobación universal.


## K46 — Hidráulica: identidad física antes de aplicaciones (2026-09-07)

El largo que trae una manguera y la necesidad de cortarla son independientes.
Los extremos A/B tampoco equivalen automáticamente a maneta/cáliper: el
[catálogo Jagwire 2021](https://jagwire.com/files/general/2021_Jagwire_AM_Catalog_LowRes.pdf)
publica dos acoples de cáliper preinstalados en un tramo a cortar (texto OEM
indexado; sin imagen de PDF en esta ronda). Conservar etapa, miembro y adaptador
exactos; no presentar esa edición como SKU actual.

Un envase tiene una formulación. [SRAM](https://support.sram.com/hc/en-us/articles/5927424375451-Can-I-use-DOT-5-in-my-SRAM-DOT-brakes)
excluye DOT 5 en el contexto de sus frenos DOT. [FMVSS116](https://www.ecfr.gov/current/title-49/subtitle-B/chapter-V/part-571/subpart-B/section-571.116)
distingue DOT 5 con base silicona y DOT 5.1 sin ella; el número cercano no
implica sustitución. No se infiere el tipo de fluido desde la marca del freno.
Las listas de [Park BKM-1.2](https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-mineral-bkm-1-2)
y [BKD-1.2](https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-dot-bkd-1-2)
son de herramientas y adaptadores de purga; ambos se venden sin líquido.
No autorizan una botella para todos esos modelos.

Se corrige una afirmación demasiado amplia de la propuesta: no es cierto que
ningún aceite mineral tenga normas. El resumen oficial histórico de
[ISO9128:1987](https://www.iso.org/standard/16724.html), edición retirada, cita
ISO7308 para base petróleo. Es un contraejemplo al veto universal, no prueba de
conformidad ni aprobación de un líquido para bicicletas. Una norma de ensayo,
una especificación de formulación y una aplicación OEM tienen ámbitos distintos.

Regresión mínima: largo conocido con corte válido; A/B ambos para cáliper
válidos; un envase con dos bases contradice su identidad; mineral con grado
DOT y DOT5.1 con base silicona bloquean; modelos/aplicaciones requieren enlace
al miembro real. La adjudicación de la identidad y la aprobación OEM para cada
producto siguen siendo necesarias antes del llenado.


**Precisión de K46, HY-A (2026-09-07):** la designación comercial no es una
lista exclusiva de normas cumplidas. [Motul DOT5.1, TDS01/22](https://azupim01.motul.com/media/motulData/DO/base/DOT_5.1_en_FR_motul_27400_20220113.pdf)
publica cumplimiento DOT3/4/5.1 para la misma formulación. Prohibir DOT4 por
llamarse DOT5.1 sería una regla falsa. Se separan designación y cumplimiento
tipado, comprobando la base química; no se extrapola la aprobación a un freno
concreto ni se completan cumplimientos que el OEM no declare.

## K47 — Adaptadores: un puerto no es el anillo ni la posición del rotor (2026-09-07)

[Wolf Tooth Boostinator](https://www.wolftoothcomponents.com/products/boostinator) documenta kits traseros de seis pernos que incluyen endcap, separador y tornillos y requieren aparaguado; declara límite de rotor de 183 mm. Por eso conservar seis pernos en entrada y salida no significa ausencia de función. El contexto HR es Hope Pro2 EVO/Pro4 trasero; no extenderlo al Pro2 sin EVO ni a un separador suelto. No se tomó un offset numérico por analogía.

[Shimano DM-MDBR001-05](https://si.shimano.com/en/pdfs/dm/MDBR001/DM-MDBR001-05-ENG.pdf), prosa p.8, excluye SM-RT86/SM-RT76 con adaptador de aluminio al usar SM-RTAD05. El nombre del montaje por sí solo no sustituye las exclusiones OEM. Rosca a maza y rosca del anillo de cierre son interfaces distintas y pueden coexistir; cada una tiene su celda.

Park fundamenta nombres IS/Post/Flat; no fue fuente de dimensiones sintéticas. Evidencia y limitaciones en `brake-adapter-parts-root-decisions-2026-09-07.md` y checkpoint de integración. Las plantillas aplicadas no certifican montaje real ni habilitan llenado.

## K48 — Talla, configuración y geometría no son el mismo ámbito (2026-09-07)

[Sheldon Brown](https://sheldonbrown.com/frame-sizing.html) explica convenciones de medida de cuadro distintas: el datum forma parte del dato. [Surly Preamble](https://surlybikes.com/blogs/blog/a-preamble-to-the-surly-preamble) documenta650b en XS/SM y700c en otras tallas; no se copia todo el catálogo de variantes a un SKU. Una variante documental puede conservar alternativas OEM de montaje, cada una con su configuración.

[Cross-Check](https://surlybikes.com/products/cross_check_2000) declara42mm de cubierta y aproximadamente40con guardabarros, dependientes del montaje; su OLD físico132,5mm acepta mazas130/135según el OEM. Son declaraciones discretas condicionadas, no intervalos universales ni medidas intercambiables. Se leyó prosa y etiquetas de tabla; no se extrajo geometría de un diagrama no inspeccionado.

[Park Tool](https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-identification) distingue caja lisa y copas que se enroscan entre sí. La rosca de la copa no convierte la caja en roscada. El modelo conserva interfaces intrínsecas y aceptaciones OEM por separado.

Regresión: una ficha no mezcla dos variantes; cada geometría tiene configuración/datum, cada rueda tiene sus puertos y cada componente su tipo y propiedades en la misma fila. El enlace row_id sólo demuestra existencia del padre, no igualdad arbitraria de columnas. Una fila de batería no puede adquirir recorrido de horquilla. Datos ausentes quedan pendientes; fuentes sintéticas de pruebas no autorizan llenado.

## K49 — Mando combinado: pieza, salida y asignación (2026-09-07)

La salida de una maneta por cable puede accionar un cáliper con conversión hidráulica. Eso no convierte a la maneta en propietaria del fluido ni de las conexiones hidráulicas: [TRP HY/RD](https://eu.trpcycling.com/en-at/products/hy-rd) describe precisamente la hidráulica en el cáliper de un sistema accionado por cable. Los campos de fluido y manguera se condicionan a la pieza y configuración que contienen ese circuito; no a una etiqueta genérica de sistema híbrido.

El lado físico tampoco determina el cambio accionado: [SRAM AXS](https://support.sram.com/hc/en-us/articles/16420328834459-Can-I-change-assign-shifter-functions-in-the-AXS-app-e-g-move-the-derailleur-outboard-with-a-left-shifter-click) permite reasignar funciones. La asignación de botones y el destinatario de un claim son distintos del número de posiciones de un mando mecánico; las posiciones de trim no equivalen a platos adicionales ([Sheldon Brown](https://sheldonbrown.com/front-derailers.html)). Los datos de freno/cambio se conservan en la misma fila que su modo y sus condiciones, evitando que una referencia a otra fila pruebe sólo existencia sin probar su tipo.

Un paquete puede contener dos mandos idénticos: modelo, lado y edición no identifican una ocurrencia física. Cada miembro tiene su identificador; se impide duplicar esa ocurrencia, no vender dos piezas iguales. La cantidad se deriva de los miembros representados y no de una cantidad supuesta. [Adjudicación e integración](../development/product-specs-research-2026-09-05/combined-control-integration-2026-09-07.md). Estas reglas de representación no autorizan cruces mecánicos por marca ni reemplazan la fuente de la variante concreta.

## K50 — No borrar el bisel del rodamiento al distinguirlo de la rodadura (2026-09-07)

[Enduro S7806](https://cycling.endurobearings.com/collections/headset-bearings/products/bb-s7806-2rs-36deg) declara un bisel interior del propio rodamiento; [Cane Creek](https://www.canecreek.com/products/headset-bearings) distingue variantes por pares de ángulos. Esos dos apoyos permanecen separados del contacto entre elementos rodantes y pistas. La propuesta que los trasladaba exclusivamente a una cubeta se rechazó; la base congelada ya tenía bien esta distinción y se restauraron sus regresiones. Una cubeta también conserva su asiento físico aunque se venda con rodamiento incluido.

[NSK](https://www.nsk.com/tools-resources/abc-bearings/differentiating-rolling-bearings/) define el ángulo de rodadura y admite cero en el dominio radial. Una descripción de contacto angular sin cifra OEM publicada no autoriza inferirla de un par de biseles. La clasificación de carga y la descripción de construcción no deben convertirse en sinónimos por heurística.

[Wheels BB86-OUT-BB](https://wheelsmfg.com/collections/bb86-92/products/bb86-92-outboard-abec-3-bb-for-24mm-shimano-cranks?variant=53184938377384) separa ancho de caja admitido, anchura sobre rodamientos y espaciadores suministrados. El ancho admisible pertenece a una configuración; un intervalo requiere publicación explícita. Sumar las piezas incluidas no demuestra el stack instalado. [Park Tool](https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-identification) documenta copas que se roscan entre sí dentro de una caja lisa: hay que nombrar la contraparte de cada puerto. [Adjudicación y límites del candidato](../development/product-specs-research-2026-09-05/existing-bearing-bb-root-decisions-2026-09-07.md).

## K51 — El dato dimensional necesita pieza, variante y significado (2026-09-08)

Las revisiones de rayos, dirección y neumáticos detectaron el mismo fallo:
convertir una cifra o etiqueta compartida en una dependencia mecánica que la
fuente no declara. [Park, SHIS](https://www.parktool.com/en-us/blog/repair-help/standardized-headset-identification-system)
separa extremo superior/inferior y usa códigos nominales; no son medidas
literales de todos los asientos. [Park, llaves de rayos](https://www.parktool.com/en-us/blog/repair-help/spoke-wrench-tool-selection)
no hace depender la llave del calibre del alambre. [Sheldon, Wheelbuilding](https://www.sheldonbrown.com/wheelbuild.html)
distingue sección elíptica de plana, y rosca laminada de alambre: no basta un
solo selector de diámetro para las tres propiedades.

En neumáticos, el límite de operación declarado por el fabricante de la rueda
no se convierte en el máximo estampado del neumático ni en la presión de un
ensayo de retención. [Zipp](https://www.sram.com/en/zipp/campaigns/hookless-tire-compatibility)
y [ENVE](https://enve.com/blogs/journal/hookless-rim-technology-101) documentan
alcances distintos. [Stan's](https://stans.com/pages/sealant-refresh-reminder)
asigna dosis distintas a dos medidas MTB: una fila identificada sólo por
«MTB» impediría guardar ambos usos documentados. El volumen de un envase no
limita una aplicación que puede consumir más de un envase.

La regresión mínima mantiene los datos del mismo extremo/configuración juntos,
permite varias aplicaciones identificadas del mismo producto y deja desconocida
una contraparte fuera del alcance OEM. La evidencia puede ser documento o
envase identificado, con URL opcional tipada; exigir siempre una URL perdería
información verificable. Estos cambios de representación no sustituyen la
investigación de cada SKU ni certifican montajes por coincidencia dimensional.

## K52 — Peso del conjunto, identidad de la pieza y coherencia del esquema (2026-09-08)

[OneUp Bash Guide V2](https://www.oneupcomponents.com/products/bashguide-v2-iscg05)
presenta el peso del conjunto según la placa montada. Sus
[instrucciones](https://eu.oneupcomponents.com/blogs/bashguides-chainguides/bashguard-chainguide-install-instructions)
separan las tres placas suministradas y cuál viene instalada. El candidato de
Claude ponía los pesos del conjunto en las filas de placas sueltas: Root lo
corrigió con configuraciones montadas que referencian la pieza incluida. Una
masa con unidad correcta sigue siendo errónea si se asigna a otro objeto.

Dos roldanas con el mismo número de dientes no quedan identificadas por eso,
ni se les puede deducir la posición. [Park](https://www.parktool.com/en-us/blog/repair-help/how-a-rear-derailleur-works)
explica las funciones de guía y tensión; cada ocurrencia del envase conserva
sus propios datos y declaraciones. Un título con un solo número de dientes
no demuestra que las dos piezas sean idénticas.

Al trasladar cotas de un escalar a una fila hay que trasladar explícitamente
su coherencia al dueño de filas. ID < OD corresponde al mismo cuerpo anular;
un rango inclusivo conserva mínimo <= máximo. Las unidades deben coincidir y
la combinación de comparaciones no puede formar un ciclo con alguna relación
estricta: ninguna observación completa satisfaría ese esquema. Un fallo de
metadatos se rechaza al definir la regla, no como dato culpable del producto.
El candidato v2 lo verifica sin reescribir esquemas ni sobres ya persistidos.

### 2026-09-15 — casquillos de tija y zapatas de llanta

Un casquillo de tija tiene interfaces hacia la tija y hacia el alojamiento
interior del cuadro; no equivale a un separador axial. Pares discretos de diámetro
publicados por variante no forman un rango continuo. Inserción y restricciones
requieren la fuente del cuadro y de la tija. Fuentes y límites en
`seatpost-shim-architecture-evidence-2026-09-15.md` del directorio de investigación.

Park Tool distingue zapatas de carretera, espárrago roscado y espárrago liso,
y presentaciones enteras o de cartucho; la clave genérica «pastilla» no describe
esas interfaces. [Guía de reemplazo](https://www.parktool.com/en-us/blog/repair-help/brake-pad-replacement-rim-brakes).
El contenido de una caja no prueba que una zapata ajuste a cualquier freno de
llanta, ni que su espárrago sea equivalente al de una pastilla de disco.
