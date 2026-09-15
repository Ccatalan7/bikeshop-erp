# Cadenas y conectores: flujo, prerrequisitos y casos — revisión independiente de Claude, 2026-09-06

Autor: Claude (Fable 5.1, modo Code), a petición de Claudio vía Codex.
Alcance: propuesta de sólo lectura para completar `chain` y `chain_link` con un
flujo corto y prerrequisitos mecánicos respaldados, también cuando el producto
no tiene referencia documentada. Codex implementa; yo no toqué código, SQL ni
datos. Único archivo escrito: éste.

Qué leí: el
[contrato](../../architecture/product-technical-specifications-contract.md), la
[matriz](../../architecture/product-spec-family-matrix.md) (filas `chain` y
`chain_link`), K01–K07 de la
[base de conocimiento](../../architecture/bicycle-compatibility-knowledge.md),
el [resultado](implementation-result.md) y la
[resolución de hallazgos](claude-implementation-review.md); en producción, sólo
lectura, las dos plantillas activas con sus 24 campos, su `form_contract`
(versión 2) y los 40 productos mapeados a esas familias con sus hechos. No
repito la auditoría global del 2026-09-05.

Fuentes obligatorias consultadas: Park Tool
[Chain Compatibility](https://www.parktool.com/en-us/blog/repair-help/chain-compatibility)
y [Chain Replacement: Derailleur Bikes](https://www.parktool.com/en-us/blog/repair-help/chain-replacement-derailleur-bikes);
Sheldon Brown [Speeds](https://www.sheldonbrown.com/speeds.html),
[Glossary: chain](https://www.sheldonbrown.com/gloss_ch.html),
[Chain maintenance, Connecting/disconnecting](https://www.sheldonbrown.com/chains.html)
y [cribsheet de espaciado](https://www.sheldonbrown.com/cribsheet-spacing.html).
Fuentes OEM exactas: KMC Europa, KMC USA, KMC global, Shimano `bike.shimano.com`
y soporte SRAM; cada una se cita donde se usa. Las páginas de Shimano y SRAM
rechazan el fetch automático (403) y se leyeron con el navegador integrado; las
citas son del texto renderizado.

## 0. Lo que el inventario real obliga a resolver

| Observación en los 40 productos | Consecuencia para el flujo |
|---|---|
| Ningún producto tiene `drivetrain_mode`; 18 tienen `chain_speeds` sin modo | El modo debe salir casi solo: derivado de 1/8, o una sola pregunta al inicio |
| 6 cadenas 1/8 (HV410, K710, S1) sólo tienen `chain_width_family=1/8` | Para ellas velocidades, plataforma, ecosistemas y direccional sobran |
| Modelo estructurado vacío en los 40; el modelo vive en el nombre | La referencia no puede ser prerrequisito de nada; el flujo manual es el camino normal |
| HV408 Grey/brown trae `chain_outer_width_mm=7.1`, ancho «Desconocido» y `drivetrain_primary_ecosystem=Otro`, todo `import` | Nada de eso contradice nada; se conserva y se revisa, no se borra |
| 9 conectores: 4 KMC (CL573R 6/7/8, 9 «Titanio», 10, 11) y 5 Risk (6-7-8, 9, 10, 11, 12), sin hechos | El conector se describe por clase de velocidad y modelo; hereda cero preguntas de la cadena completa |
| Dos «Z8.3» distintos (116 eslabones DISPLAY y «Gris») y dos «X8» | Una referencia europea de 114 eslabones no puede vincularse a un pack de 116; son ediciones distintas |

## 1. Decisiones, derivados, dependencias y sobrantes

### 1.1 Cadena (`chain`)

Orden propuesto de captura sin referencia. Con referencia, todo lo que ella
declara se deriva y se muestra con fuente, como ya hace el editor.

| # | Campo | Decisión o derivado | Depende de | Fuente | Sobra cuando |
|---|---|---|---|---|---|
| 1 | `drivetrain_mode` | Decisión inicial única: Derailleur o Single speed / BMX / IGH. Se deriva a Single cuando `chain_width_family = 1/8` | nada | KMC glosario: 1/8 «only for single speed/internal geared»; Sheldon glosario: 1/8 en single speed e IGH | nunca |
| 2 | `chain_speeds` | Derailleur: elegir entre 5…13 (nunca 1). Single/IGH: derivado `{1}` como invariante del esquema, sin pregunta | 1 | invariante propio; KMC glosario reserva 1/8 para single/IGH | Single (derivado, no se muestra) |
| 3 | `chain_width_family` | Denominación nominal copiada del envase, opcional. Derailleur: 3/32, 11/128 u Otro. Single/IGH: 1/8, 3/32 u Otro | 1 | KMC glosario: 1/8 sólo single/IGH; 3/32 single/IGH y desviador hasta 8; 11/128 desviador 9–12. Park: 3/32 «not a true measurement» | nunca; es dato de identidad |
| 4 | `chain_outer_width_mm` | Medida sobre el pasador, opcional, nunca deriva velocidades | ninguna | Park: anchos nominales que se solapan (9v 6,5–7 mm frente a 6/7/8 7 mm) | nunca |
| 5 | `spec_evidence_source` | Fuente de lo que se declara en 6 y 7 | ninguna | contrato §4.2 | cuando 6 y 7 están vacíos |
| 6 | `drivetrain_declared_compatible_ecosystems` | Sistemas declarados **no exclusivos** por el fabricante | 1 = Derailleur, 2, 5 | KMC Z6/Z7/Z8/X8 «all … systems»; X11 «Shimano, SRAM, Campagnolo» | Single/IGH |
| 7 | `drivetrain_platform` | Renombrar a «Sistema exclusivo declarado»: sólo cuando el fabricante restringe (LINKGLIDE, Flattop, T-Type, Campagnolo, HG+) | 1 = Derailleur, 2 contiene 9…13, 5 | KMC eGlide «LinkGlide systems only»; Park: Flattop «proprietary»; Sheldon: 7/9/10 «close enough» entre marcas | ≤ 8 velocidades y Single (oculto salvo que tenga valor) |
| 8 | `link_count` | Contenido del pack | ninguna | contrato §4: pack ≠ longitud instalada | nunca |
| 9 | `quick_link_included` | Contenido del pack, tres estados | ninguna | KMC Z6/Z7/Z8/X8 «Includes a MissingLink» | nunca |
| 10 | `chain_directional` | Declarado por modelo, tres estados | 1 = Derailleur | Shimano CN-HG701-11 «directional»; Park: logos hacia fuera | Single/IGH |
| 11 | `chain_ebike_rated` | Declarado, tres estados | ninguna | KMC eGlide, e-series | nunca |
| — | `drivetrain_primary_ecosystem`, `chain_profile_family` | Legacy: sólo lectura con «Retirar dato anterior» | — | contrato §2 | siempre |

Con esto un operador que carga una cadena 1/8 responde una pregunta (modo, o
ninguna si copió 1/8 del envase) y opcionalmente eslabones. Una cadena de
desviador de 8 velocidades responde dos (modo y velocidades) y lo demás es
opcional. Sólo desde 9 velocidades aparece la pregunta de sistema exclusivo, y
sólo desde 12 conviene insistir en ella como pendiente.

### 1.2 Conector (`chain_link`)

El conector se describe por su clase y su declaración de cadenas objetivo. No
hereda eslabones, direccional, e-bike ni «incluye conector».

| # | Campo | Decisión o derivado | Depende de | Fuente | Sobra cuando |
|---|---|---|---|---|---|
| 1 | `chain_connector_type` | Decisión inicial: eslabón rápido de dos placas (MissingLink, PowerLock, Quick-Link), pasador de unión, medio eslabón, otro (clip 1/8) | nada | Park: «connecting rivet … specific to the make and model»; Sheldon: master link de clip en 1/8; KMC glosario: half link serie HL | nunca |
| 2 | `drivetrain_mode` | Medio eslabón o clip 1/8: derivado Single/IGH. Pasador: sugerido Derailleur. Eslabón rápido: pregunta | 1 | KMC glosario half link para single/IGH; KMC 410H «1/2" x 1/8"» clip; Sheldon: Shimano 9+ «special new link pin» | medio eslabón y clip |
| 3 | `chain_speeds` | «Clase de velocidad de la cadena objetivo». Derailleur: 5…13; Single: `{1}` derivado | 1, 2 | KMC CL573R «6, 7 and 8 speed», CL566R 9, CL559R 10, CL555R 11, CL552 12 | medio eslabón, clip |
| 4 | `chain_outer_width_mm` | Relabel «Longitud de pasador que acepta (mm)», opcional | ninguna | KMC glosario: el pasador «is always adjusted to the total width of a chain» | pasador de unión |
| 5 | `chain_width_family` | Sólo para single/IGH y medio eslabón: 1/8 o 3/32 | 2 = Single | KMC 410H 1/8; glosario | Derailleur (oculto salvo valor) |
| 6 | `chain_link_reusable` | Declarado por modelo, tres estados. Pasador de unión: derivado `false` | 1 | KMC teach: reusable «3 to 5 times», no reusable «only once»; Shimano SM-CN910-12 «Non-reusable»; SRAM PowerLock «single use only»; Sheldon: pin nuevo cada vez | nunca |
| 7 | `spec_evidence_source` | Fuente de 8 y 9 | ninguna | contrato | cuando 8 y 9 vacíos |
| 8 | `drivetrain_declared_compatible_ecosystems` | Relabel «Cadenas compatibles declaradas» (marca de la cadena, no de la bici) | 3, 7 | KMC CL555R «KMC, SHIMANO&SRAM 11 speed chains»; CL559R sólo «KMC&Shimano» | Single |
| 9 | `drivetrain_platform` (**campo nuevo** en esta plantilla) | «Sistema exclusivo declarado» para 12/13: Flattop, Eagle, T-Type, HG+ | 3 contiene 12 o 13, 7 | SRAM: Flattop, Eagle y T-Type PowerLock «different»; Shimano SM-CN910-12 «HG 12-speed», «Not compatible current HG-X11» | ≤ 11 |
| 10 | `chain_link_pack_qty` | Contenido | ninguna | KMC tarjetas de 2; SRAM kits de 4 | nunca |
| — | `drivetrain_primary_ecosystem`, `chain_profile_family` | Legacy | — | — | siempre |

Opcional y de bajo costo: un texto `chain_link_target_models` («Modelos de
cadena declarados», por ejemplo «X8/Z8.3/Z7/Z6») en rol declaración, porque KMC
declara por lista de modelos y esa lista es lo que el taller necesita para
cruzar conector y cadena. También un valor nuevo «Eslabón con clip (1/8)» en
`chain_connector_type`, ya que el 410H no es ni MissingLink ni pasador.

## 2. Reglas generales respaldadas frente a restricciones de modelos exactos

### 2.1 Reglas generales, con severidad

| ID | Regla | Severidad propuesta | Respaldo | Límite que la fuente impone |
|---|---|---|---|---|
| G1 | 1/8 es sólo single speed/IGH; Derailleur + 1/8 + velocidades ≥ 5 es contradicción | Bloqueante con los tres datos presentes; pendiente si falta alguno | [KMC glosario](https://www.kmcchain.eu/service/glossary) «Wide chains are 1/2x1/8" sized and only for single speed/internal geared bikes»; [Sheldon glosario](https://www.sheldonbrown.com/gloss_ch.html) | [Sheldon Speeds](https://www.sheldonbrown.com/speeds.html): sistemas antiguos de 2–3 piñones usaron 1/8; por eso se exige ≥ 5 |
| G2 | Single/IGH ⇒ `chain_speeds = {1}` | Derivación de sistema, sin fuente externa: invariante del esquema (§5.1 del contrato) | — | No es un hecho mecánico; no se muestra como declaración del fabricante |
| G3 | En desviador de ≤ 8 velocidades la marca de la cadena no es una decisión; el «sistema exclusivo» no se pregunta | Ocultar, no bloquear | [Sheldon Speeds](https://www.sheldonbrown.com/speeds.html): en 7, 9 y 10 el espaciado entre marcas «rarely causes any difficulty»; [Park](https://www.parktool.com/en-us/blog/repair-help/chain-compatibility): 6/7/8 comparten 7 mm; KMC Z6/Z7/Z8/X8 «all … systems» | Sheldon: Campagnolo 8 y Shimano 8 difieren en el cassette (5,0 frente a 4,8 mm); es un problema de indexación rueda–mando, **no de la cadena**. No se convierte en regla de cadena |
| G4 | La denominación nominal no fija velocidades; sólo aviso cuando contradice la nomenclatura del **mismo fabricante** | No bloqueante (`verify_model`, ya existe para KMC ≤ 8 + 11/128; propongo el espejo KMC ≥ 9 + 3/32) | KMC glosario: 3/32 hasta 8, 11/128 de 9 a 12; Park: «not a true measurement» | Sólo KMC tiene esta nomenclatura verificada; Shimano no publica tamaño en sus fichas web leídas. No extender el aviso a otras marcas |
| G5 | El ancho sobre el pasador no fija velocidades; sólo aviso de plausibilidad por familia nominal | No bloqueante | KMC glosario: 1/8 8–10 mm, 3/32 7,0–7,8 mm, 11/128 5,2–6,6 mm; Park: 9v 6,5–7 mm se solapa con 6/7/8 | Dentro de 11/128 no separa 9/10/11/12 |
| G6 | Los conteos solos nunca producen «incompatible» | Cadena declara N y bici N: «coinciden, confirmar»; cadena un escalón más estrecha que la bici: «posible con compromisos»; cadena más ancha que la bici: «sin confirmar» | Sheldon Speeds: «A chain one size narrower than standard rarely presents any problem»; Park: «stick to the drivetrain manufacturer's chains» | K07: posibilidad no es aprobación |
| G7 | En 12/13 la exclusividad de sistema es real y, sin declaración, el resultado es «pendiente», nunca «universal» | Pendiente no bloqueante | Park: Flattop «proprietary and are not cross-compatible»; [SRAM](https://support.sram.com/hc/en-us/articles/6526696046363): PowerLock Eagle, T-TYPE y road «PLCK-D1» distintos; Shimano SM-CN910-12 «HG 12-speed» y «Not compatible current HG-X11» | Un 12v sin plataforma es incompleto, no incompatible |
| G8 | Conector y cadena deben coincidir en clase de velocidad; dentro de la clase, entre marcas sólo si el fabricante del conector lo declara | Clases declaradas disjuntas: incompatible (interfaz conector–cadena). Marca no declarada: sin confirmar | [Sheldon Chains](https://www.sheldonbrown.com/chains.html): PowerLink 7/8 «works with SRAM and Shimano chains», PowerLink 9 «reportedly may lead to a Shimano chain's jumping»; KMC CL559R declara sólo KMC y Shimano | Es una relación conector–cadena; no certifica el montaje en la bici |
| G9 | La reutilización es un hecho del modelo, nunca de la clase; un pasador de unión no se reutiliza | Pasador ⇒ `false` derivado; el resto declarado | [KMC teach](https://www.kmcchain.com/en/teach/missinglink): reusable «3 to 5 times», no reusable «only once»; [Shimano](https://bike.shimano.com/products/components/pdp.P-SM-CN910-12.html) «Non-reusable»; [SRAM Eagle](https://support.sram.com/hc/en-us/articles/5928476316571) «single use only»; Sheldon: Shimano 9+ «special new link pin» | Desconocido no habilita reutilizar en el taller |
| G10 | Direccional se declara por modelo | Tres estados, sin derivación | Shimano CN-HG701-11 «directional»; Park: «Some chains are directional» | — |
| G11 | Medio eslabón es herramienta de tensión para single/IGH | Deriva modo Single | KMC glosario: «half link chain (KMC HL-Series)» para single/IGH | — |
| G12 | Eslabones y cantidad por pack son contenido, independientes de todo | Sin dependencias | contrato §4 | — |

### 2.2 Restricciones de modelos exactos que propongo sembrar

Cada fila es una edición inmutable con su página. Sólo se cargan hechos que la
página muestra; «ausente» queda ausente.

| Edición | Hechos verificados | Declaración | Fuente |
|---|---|---|---|
| KMC Z8 Silver/Grey BZ08NG114 | 6/7/8, 1/2×3/32, pasador 7,3 mm, 114 eslabones, MissingLink incluido | «Compatible with all 6-, 7- and 8-speed systems» | [kmcchain.eu](https://www.kmcchain.eu/products/z8-silver-grey) |
| KMC Z7 Grey/Brown BZ07GB114 | **6/7**, 3/32, 7,3 mm, 114, MissingLink | «all 6- and 7-speed systems» | [kmcchain.eu](https://www.kmcchain.eu/products/z7-grey-brown) |
| KMC Z6 Grey BZ06G0114 | **5/6**, 3/32, 7,3 mm, 114, MissingLink | «all 5- and 6-speed derailleur systems» | [kmcchain.eu](https://www.kmcchain.eu/products/z6-grey) |
| KMC X9 US, 116 eslabones | 9, 1/2×11/128, 116, 277 g; MPN ausente en la página | «Shimano, SRAM, Campagnolo» | [kmcchain.us](https://kmcchain.us/products/x9) |
| KMC X10 | 10, 1/2×11/128; eslabones y MPN ausentes | «SHIMANO, Campagnolo and SRAM 10 speed» | [kmcchain.com](https://www.kmcchain.com/en/product/bicycle-chain-x10-10-speed) |
| KMC CL573R | clase 6/7/8; reutilizable | «KMC X8/ Z8.3/ Z7/ Z6 chains»; la ficha US de 7,3 mm añade Shimano 6/7/8 (K06) | [kmcchain.com](https://www.kmcchain.com/en/product/connector-missing-link-cl573r-8s-7s-6s-speed) |
| KMC CL566R | 9; reutilizable | «KMC, SHIMANO&SRAM 9 speed chains» | [kmcchain.com](https://www.kmcchain.com/en/product/connector-missing-link-cl566r-9-speed) |
| KMC CL559R | 10; reutilizable | «KMC&Shimano 10 speed chains» (SRAM **no** aparece en la página oficial; un minorista lo agrega, no se importa) | [kmcchain.com](https://www.kmcchain.com/en/product/connector-missing-link-cl559r-10-speed) |
| KMC CL555R | 11; reutilizable | «KMC, SHIMANO&SRAM 11 speed chains» | [kmcchain.com](https://www.kmcchain.com/en/product/connector-missing-link-cl555r-11-speed) |
| KMC CL552 | 12; **no reutilizable** | «KMC, SHIMANO, SRAM MTB & CAMPAGNOLO 12 speed chains (not for any Flattop)» → claim con `excludes: [SRAM FlatTop]` | [kmcchain.com](https://www.kmcchain.com/en/product/connector-missing-link-cl552-12-speed) |
| KMC 410H Connector | 1/2×1/8, clip de 3 piezas, «non-reusable C-clip» | para «410H» y «B1H-Wide» | [kmcchain.us](https://kmcchain.us/products/410h_connector) |
| Shimano SM-CN910-12 | Quick-Link 12; «Non-reusable» | «Compatible chain HG 12-speed»; «Not compatible current HG-X11 chain» → `exclusive` HG+ 12 | [bike.shimano.com](https://bike.shimano.com/products/components/pdp.P-SM-CN910-12.html) |
| Shimano CN-M7100 | 12, HG+, quick-link SM-CN910-12 incluido, «Non-reusable» | «Compatible with 12-speed drivetrain» (HG 12) | [bike.shimano.com](https://bike.shimano.com/products/components/pdp.P-CN-M7100.html) |
| Shimano CN-HG701-11 | 11, HG-X11, **direccional**, 114 eslabones 257 g | «MTB, Road, E-BIKE 11-speed» | [bike.shimano.com](https://bike.shimano.com/products/components/pdp.P-CN-HG701-11.html) |
| SRAM Flattop PowerLock 12s | no reutilizable; kit de 4 (00.2518.036.003) | «Use only the SRAM Flattop 12-speed PowerLock for Flattop 12-speed road chains» → `exclusive` Flattop | [support.sram.com](https://support.sram.com/hc/en-us/articles/6042741344667), [reutilización](https://support.sram.com/hc/en-us/articles/6042755556251) |
| SRAM Eagle PowerLock | «single use only», sólo se retira con alicate | Eagle 12 | [support.sram.com](https://support.sram.com/hc/en-us/articles/5928476316571) |

Huecos OEM registrados en esta ronda, con búsqueda acotada a dominios de KMC y
Shimano:

- **HV408**: no aparece en kmcchain.com, .eu, .us ni .com.tw (dos búsquedas
  restringidas por dominio). Los minoristas coinciden en 1/2×3/32, 116
  eslabones, 6/7/8 y cierre por pasador ([Rideshop](https://rideshop.cl/products/kmc-cadena-1-2-x-3-32-hv408-caja),
  [EvoSportz](https://www.evosportz.com/kmc-hv408-chain-678-speed),
  [La Bicicletería](https://www.labicicleteria.pe/products/cadena-kmc-hv-408-1-2x3-32-116-l-6-7-v)),
  pero no hay ficha del fabricante. Recomendación: identidad `family_known`,
  hechos sólo desde el envase, sin referencia y sin vincular X8; si el dueño
  fotografía la caja, se crea la edición con `sources: [envase]`.
- **HV410 y K710** como cadenas: tampoco en los sitios actuales de KMC; el US
  lista «K710 Half Link» y «KK710 Wide». Mismo tratamiento que HV408.
- **Shimano CN-HG53, CN-HG54, CN-HG40**: la ficha pública de CN-HG53 devuelve
  «Page Not Found»; no se leyeron HG54 ni HG40. Quedan sin referencia.
- **Risk y ZTTO**: sin documentación OEM localizable. Manuales, con evidencia
  «envase» cuando exista.

### 2.3 Incompatible frente a desconocido

| Resultado | Cuándo se puede afirmar | Ejemplo |
|---|---|---|
| Incompatible | Sólo con datos presentes y regla respaldada: G1; sistema exclusivo declarado contra plataforma conocida contraria; clases de conector y cadena declaradas y disjuntas; exclusión explícita del fabricante | eGlide en HG 10; CL552 con Flattop; SM-CN910-12 con HG-X11 |
| En conflicto | Dos hechos del propio producto o producto contra referencia | 11/128 manual con X8 EU vinculada |
| Sin confirmar | Falta un dato, la cobertura declarada no incluye el caso, o el fabricante del conector no nombra la marca | Z7 (6/7) en 8v; CL559R con cadena SRAM 10 |
| Compatible con condiciones | Interfaz declarada coincide; faltan otras interfaces del montaje | X11 en Campagnolo 11: falta confirmar platos y conector |
| Compatible confirmado | Sólo interfaz conector–cadena con lista de modelos del fabricante | CL573R con Z8 EU |

Nunca se afirma «incompatible» por ancho, por marca, por conteo o por ausencia
de declaración. Falta de datos no es contradicción.

## 3. Casos

Entrada, resultado esperado con el vocabulario del contrato §8, regla o
referencia, alcance y fuente.

| # | Tipo | Entrada | Resultado esperado | Regla / referencia y alcance | Fuente |
|---|---|---|---|---|---|
| C01 | positivo | Z8 EU BZ08NG114 vinculada; bici 7v Shimano HG/SIS | Compatible con condiciones: «coinciden 7v; confirmar platos y conector» | Referencia + G3 + G6. Alcance cadena–piñones; no certifica el conjunto | [Z8 EU](https://www.kmcchain.eu/products/z8-silver-grey), Park, Sheldon Speeds |
| C02 | positivo | X11 CN11665 vinculada; bici Campagnolo 11 | Compatible con condiciones | Declaración «Shimano, SRAM, Campagnolo» del modelo | [X11 US](https://kmcchain.us/products/x11) |
| C03 | negativo | eGlide CN11245 vinculada; bici 10v, plataforma Shimano HG/SIS conocida | Incompatible: «uso exclusivo LINKGLIDE» | Claim `exclusive` contra plataforma contraria conocida. Con plataforma desconocida: cautela LINKGLIDE, no incompatible | [eGlide US](https://kmcchain.us/products/eglide) |
| C04 | desconocido | «Cadena 1/2 X 3/32 Kmc Hv408 Caja Grey/brown»: modelo vacío, ancho «Desconocido», 7,1 `import`, ecosistema legacy «Otro» | Identidad `family_known`; ficha guardable; taller: Sin confirmar para cualquier bici; sin aviso `verify_model` | Sin referencia; 7,1 mm se conserva como medida importada; el legacy se muestra para retirar | Hueco OEM registrado en §2.2 |
| C05 | negativo | Manual: modo Derailleur, ancho 1/8, velocidades {7} | En conflicto, bloqueante: «1/8 es sólo single speed/IGH» | G1, con los tres datos presentes | KMC glosario, Sheldon glosario |
| C06 | positivo | «Cadena KMC HV-410 1 Vel.»: ancho 1/8 copiado del nombre | Modo derivado Single/IGH, velocidades `{1}` derivadas, sin más preguntas; bici IGH: Compatible con condiciones «confirma que piñón y plato sean 1/8» | G1 derivación + G2. HV410 sin ficha OEM: identidad `family_known` | KMC glosario, Sheldon glosario |
| C07 | desconocido | Z7 BZ07GB114 vinculada (declara 6/7); bici 8v | Sin confirmar: «8v queda fuera de la cobertura declarada» | Mismo ancho nominal que una 8v, pero el fabricante no lo declara; Park y Sheldon no lo prueban | [Z7 EU](https://www.kmcchain.eu/products/z7-grey-brown) |
| C08 | positivo con compromisos | X9 US (9) sin plataforma; bici 8v | Compatible con condiciones, prioridad baja: «un escalón más estrecha; funciona con compromisos según Sheldon; no declarada por KMC» | G6, tramo «más estrecha» | Sheldon Speeds; [X9 US](https://kmcchain.us/products/x9) |
| C09 | positivo y negativo | Conector CL573R vinculado con (a) Z8 EU y (b) X9 | (a) Compatible confirmado, interfaz conector–cadena; (b) Incompatible: «clase 6/7/8 frente a cadena 9» | G8 + lista de modelos del fabricante. Alcance sólo conector–cadena | [CL573R](https://www.kmcchain.com/en/product/connector-missing-link-cl573r-8s-7s-6s-speed), [KMC teach](https://www.kmcchain.com/en/teach/missinglink) |
| C10 | negativo | Conector CL552 con (a) cadena SRAM Flattop, (b) Shimano CN-M7100; y PowerLock Flattop con cadena Eagle | (a) Incompatible «not for any Flattop»; (b) Compatible con condiciones y `reusable=false`; PowerLock Flattop + Eagle: Incompatible | Exclusión explícita y exclusividad declarada; G9 para la reutilización | [CL552](https://www.kmcchain.com/en/product/connector-missing-link-cl552-12-speed), [SRAM Flattop PowerLock](https://support.sram.com/hc/en-us/articles/6042741344667) |
| C11 | negativo y desconocido | Shimano SM-CN910-12 con (a) CN-HG701-11 y (b) KMC X12 | (a) Incompatible «no compatible con HG-X11»; (b) Sin confirmar: Shimano declara HG 12, no nombra KMC | Exclusión OEM frente a ausencia de declaración | [SM-CN910-12](https://bike.shimano.com/products/components/pdp.P-SM-CN910-12.html), [CN-HG701-11](https://bike.shimano.com/products/components/pdp.P-CN-HG701-11.html) |
| C12 | desconocido | «Missinglink RISK 10 V Par»: tipo eslabón rápido, clase {10}, pack 2, reutilizable sin dato | Ficha válida e incompleta; con cualquier cadena 10: Sin confirmar; el taller no ofrece reutilizarlo | G8 y G9: marca no declarada, reutilización desconocida ≠ reutilizable | sin OEM |

Los doce casos se derivan de las fuentes y del inventario, no del validador. Los
positivos exigen la referencia o los hechos declarados; ninguno se satisface
sólo con ancho o conteo.

## 4. Cambios mínimos al contrato y riesgos para datos existentes

### 4.1 `chain`, sólo `form_contract` y reglas de campo

1. `constraint_rules` en `chain_speeds`: modo Derailleur ⇒ `allow [5…13]`;
   modo Single ⇒ `allow [1]`. Derivación `{1}` como invariante de sistema con
   procedencia propia, no como declaración del fabricante.
2. `constraint_rules` en `chain_width_family`: `all [modo Derailleur, velocidades
   contains_any 5…13]` ⇒ `allow [3/32, 11/128, Otro]`; modo Single ⇒
   `allow [1/8, 3/32, Otro]`. Es G1; bloquea sólo con los datos presentes.
3. `visibility_rules`: `drivetrain_platform` visible con Derailleur y
   velocidades `contains_any 9…13`; `drivetrain_declared_compatible_ecosystems`
   y `chain_directional` visibles con Derailleur. El editor ya muestra un valor
   existente aunque el campo esté oculto; eso conserva las respuestas manuales.
4. `labels`: `drivetrain_platform` → «Sistema exclusivo declarado»;
   `drivetrain_declared_compatible_ecosystems` → «Sistemas declarados
   compatibles». `helpers` en el mismo sentido.
5. Aviso no bloqueante espejo de `verify_model`: KMC + velocidades
   `contains_any 9…13` + 3/32. Y aviso de plausibilidad de `chain_outer_width_mm`
   por familia nominal con los rangos del glosario KMC.
6. `validation_rules` de `chain_outer_width_mm`: `max 7.8` → `10` (KMC: 1/8 mide
   8–10 mm; Park: 1/8 ≈ 9 mm). Hoy una cadena 1/8 no puede registrar su ancho.

### 4.2 `chain_link`

1. `prerequisites`: `chain_speeds ← [chain_connector_type, drivetrain_mode]`;
   `drivetrain_declared_compatible_ecosystems ← [chain_speeds,
   spec_evidence_source]`. Retirar del contrato el prerrequisito de
   `drivetrain_platform` mientras el campo no exista en esta plantilla, o añadir
   el campo (punto 4).
2. `constraint_rules`: `chain_link_reusable`: tipo Pin ⇒ `allow [false]`.
   `chain_speeds`: mismo par de reglas que la cadena por modo.
3. `visibility_rules`: `chain_speeds` oculto para medio eslabón;
   `chain_width_family` visible con modo Single; `chain_outer_width_mm` oculto
   para pasador de unión.
4. Fila nueva en `spec_template_fields`: `drivetrain_platform` para `chain_link`,
   visible con velocidades `contains_any [12, 13]`, rol declaración.
5. `labels`: `chain_outer_width_mm` → «Longitud de pasador que acepta»;
   `drivetrain_declared_compatible_ecosystems` → «Cadenas compatibles
   declaradas»; `chain_speeds` → «Clase de velocidad de la cadena objetivo».
6. Opcionales: definición `chain_link_target_models` (texto, declaración) y
   valor «Eslabón con clip (1/8)» en `chain_connector_type`.

### 4.3 Referencias y motor

- Sembrar las ediciones de §2.2 con `claims` que distingan `systems`,
  `exclusive`, `excludes` y `chain_models`. CL552 necesita `excludes`; el motor
  hoy sólo lee `exclusive`.
- Relación conector–cadena en el scorer: clase de velocidad, `chain_models`
  cuando ambos tienen referencia, `excludes`, y reutilización como dato de
  servicio, no de compatibilidad.
- G6 en el scorer: separar «un escalón más estrecha» (Sheldon) de «más ancha»
  y de «fuera de cobertura», con prioridades distintas y sin verde.

### 4.4 Riesgos para los datos existentes

| Cambio | Efecto sobre los 40 productos y el resto |
|---|---|
| Constraints que leen `drivetrain_mode` | Inertes hoy: ningún producto lo tiene; desconocido no activa una regla. Los 18 con velocidades y sin modo siguen como pendiente no bloqueante |
| G1 bloqueante | No alcanza a nadie: ninguna 1/8 tiene modo ni velocidades |
| Avisos KMC de nomenclatura | «Cadena Kmc X9 1/2" X11/28"» no tiene hechos; los Z9/X9/X10 con 11/128 y 9/10 no disparan. Cero avisos retroactivos |
| Cambiar `validation_rules`, etiquetas o campos | El trigger sube `contract_version`: cualquier editor abierto recibe «La plantilla cambió. Recarga» al guardar. Aceptable si se hace en una sola migración |
| Añadir `drivetrain_platform` a `chain_link` | Ningún conector tiene hechos; sin efecto retroactivo |
| Vincular referencias a productos existentes | Riesgo real de mezclar ediciones: los dos «Z8.3» (116 DISPLAY y «Gris») y los dos «X8» no son BZ08NG114/BX08NG114 de 114 eslabones sin comprobar la caja. La auditoría de inventario decide por envase, no por nombre |
| HV408 Grey/brown | Conserva 7,1 `import`, ancho desconocido y el legacy «Otro» visible para retirar; no se le asigna X8 ni referencia alguna |
| Proyección pública | Los pendientes no bloqueantes ya se conservan; G1 bloqueante sólo ocultaría campos de un producto con los tres datos contradictorios, que hoy no existe |
| `save_product_spec_facts_v1` y `record_product_spec_reading_v1` | Los constraints nuevos sólo bloquean con datos presentes y contradictorios; una lectura del nombre que escriba ancho 1/8 sobre un producto con modo Derailleur y velocidades ≥ 5 fallaría, y ése es el comportamiento deseado |

### 4.5 Lo que no propongo

- Ninguna tabla universal ancho→velocidades ni marca→ecosistema.
- Ninguna corrección masiva: el modo de las 18 cadenas con velocidades se
  completa producto por producto, o sale solo al copiar 1/8 del envase.
- Ningún claim tomado de minoristas: HV408, HV410, Risk y ZTTO quedan manuales.
- Ninguna regla de cadena por la diferencia de espaciado Campagnolo/Shimano de
  8 velocidades: es del cassette y del mando.

---

## Revisión crítica de la segunda entrega — 2026-09-06, 14:00 PDT

Sólo lectura. Revisé `20260906103000_chain_connector_spec_contract.sql` (estado
de las 13:56, md5 `c84675868ba15bcef2c906922c0e1b20`, 219 líneas), las dos
fixtures nuevas, `product_spec_contract.dart`, `product_form_page.dart`,
`product_spec_boolean_field.dart`, `bike_product_compatibility_service.dart`,
`chain_connector_spec_contract.sql` y `chain_connector_spec_contract_test.dart`,
más lecturas de producción y de la base local. No edité código, SQL ni datos.

### Verificaciones OEM que sostienen la entrega

- **Catálogo KMC Europa 2026, revisión de junio, página PDF 30.** Extraje el
  texto con Ghostscript. Z8.3: «Compatible with all 8-, 7- and 6-speed systems»,
  «Includes a MissingLink», «114 links – 1/60 box», «Art. Nr.: BZ08NG114».
  Z7: «Compatible with all 7- and 6-speed systems», BZ07GB114, 114. Z6:
  «Compatible with all 6-speed systems», BZ06G0114, 114. Confirmo la
  discrepancia Z6 (web 5/6 frente a catálogo 6) y que no sembrarla es correcto.
  La misma página lista presentaciones propias: WPZ8NG116 «116 links – 25
  pcs/box + 25 CL», WPZ8G0116, BZ08EP114 y WRZ8GY000 «50 m roll + 40 CL».
  El seed Z8.3 sólo toma lo que la página muestra; no asume peso ni envase.
- **CL571R** ([kmcchain.com](https://www.kmcchain.com/en/product/connector-missing-link-cl571r-8s-single-speed)):
  «Missinglink Reusable», «Non directional design», cadenas «Z8.1, Z8.1 EPT,
  Z8.1 RB». El seed coincide; la palabra «single speed» aparece sólo en la
  URL, no en el cuerpo, y el seed no la convierte en cobertura.
- Los otros cinco CL, Z7, SM-CN910-12, CN-M7100, CN-HG701-11 y los tres
  artículos de SRAM ya estaban verificados arriba; los ocho seeds reproducen
  esas páginas sin agregar marcas ni cantidades.
- Índices que la migración presupone, leídos en producción: parcial
  `(key) where tenant_id is null` en `spec_definitions`, único
  `(spec_definition_id, code)` en `spec_definition_values`, único
  `(template_id, spec_definition_id)` en `spec_template_fields`. Existen los
  tres; no hay copias por tenant de las definiciones tocadas; `link_count` y
  `chain_outer_width_mm` sólo se usan en estas dos plantillas.

### Hallazgo bloqueante, corregido durante la revisión

**La base local y la fixture tenían una regla que la migración no crea.**
A las 13:50 la base local mostraba en `chain_speeds` de ambas plantillas la
restricción `drivetrain_mode = Single speed / BMX / IGH → allow ["1"]`, citando
el cribsheet de espaciado de Sheldon, que no habla de eso. La fixture exportada
la traía y las pruebas Dart corrían contra ella; la migración no la escribía.
Producción habría quedado distinta de la fixture, y en `chain_link` la regla
leía un campo ya declarado legacy. A las 13:56 la migración incorporó el reset
explícito (línea 116) y la fixture se regeneró sin la regla; el pgTAP nuevo
(línea 16) lo afirma. Lo que queda por hacer antes del deploy, porque
`contract_version` 13 y 59 en la fixture delatan muchas ediciones locales
fuera de la migración:

1. Reconstruir la base local sólo desde migraciones, volver a correr los
   85 pgTAP y las pruebas Dart, y **re-exportar las dos fixtures desde ese
   estado**, no desde la base editada.
2. Que el archivo `--verify` del deploy afirme el estado final, no sólo la
   existencia: `constraint_rules = '[]'` en `chain_speeds` de `chain` y
   `chain_link`; la regla de `chain_width_family` con sus dos fuentes; la
   regla `Pin → [false]` en `chain_link_reusable`; la visibilidad `neq Pin` en
   `chain_outer_width_mm`; `validation_rules` sin `min`/`max` en los tres
   campos numéricos; el valor `clip`; los dos campos nuevos en la plantilla; y
   las ocho referencias con `reviewed_on = 2026-09-06`.

### Correcciones baratas que conviene hacer en esta misma migración

Ninguna rompe producción; las tres son de una línea y evitan bakear algo
inmutable o citar mal una fuente.

| # | Qué | Por qué | Dónde |
|---|---|---|---|
| A | La regla `Pin → reusable=false` cita sólo Park Tool | La frase de Park dice que el remache es «specific to the make and model», no que sea de un solo uso. Lo que sostiene la regla es Sheldon: Shimano 9+ se reune «only by inserting a special new link pin». Añadir esa URL al `source` de la regla | migración, línea 172 |
| B | `spec_evidence_source` viaja como **hecho** de la referencia y entra en el bucle de `reference_conflict` | Un operador que escribió «envase» como fuente y luego vincula CL573R recibe un conflicto bloqueante y sólo puede salir aceptando la URL del fabricante, perdiendo su nota. Las tres referencias ya desplegadas tienen el mismo hecho y son inmutables, así que la salida es en el validador: excluir `spec_evidence_source` del bucle de conflicto en SQL (línea 26 del validador) y en Dart (`validateProductSpecDraft`, bucle sobre `reference.facts`). La migración ya reemplaza esa función | validador SQL y Dart |
| C | Las dos referencias de cadena guardan la cobertura en `claims[].platform` como texto libre («Todos los sistemas de 6/7/8 velocidades») | El tokenizador devuelve `null` para ese texto, así que hoy es inocuo, pero `platform` es la clave que el motor lee para exclusividad, y la referencia es inmutable. `systems` o una clave `coverage` deja la semántica limpia y evita que un futuro texto con «Eagle» o «HG+» se tokenice como plataforma. La X8 desplegada ya tiene esa forma; al menos no repetirla | seed JSON de la migración |

### Lo que revisé y está bien

- **Integridad de la migración.** `create or replace` del validador difiere del
  desplegado sólo en `positive`/`integer`; misma firma; los consumidores
  (`spec_validate_product_internal_v1`, proyección pública) ya filtran por
  `blocking`. Los `on conflict` tienen índice. El seed resuelve etiquetas por
  UUID y aborta si falta una. Hechos existentes: 116 y 126 eslabones enteros,
  7,1 mm positivo; nada retroactivo.
- **Semántica.** 1/8 sólo se prohíbe con modo Derailleur y velocidades 5…13
  presentes; sin modo o sin velocidades queda pendiente no bloqueante. No hay
  derivación desde ancho ni desde modo. El conector empieza por tipo, la
  fuente precede a modelos/reutilización/sentido, `chain_link_pack_qty` no se
  infiere del texto «2 pcs» y el ancho montado se oculta para pasador. Los
  valores legacy se conservan para revisar.
- **Alcance OEM en el motor.** `_assessDetailedChainLinkCompatibility` nunca
  compara la clase del conector con los piñones de la bici; muestra cadenas
  admitidas, exclusiones y «un solo uso». Una referencia sin MPN no borra el
  MPN manual (formulario y pgTAP línea 54). `suggestProductSpecModels` exige
  que el código del modelo esté en el nombre y nunca vincula solo.
- **Dart/SQL.** Paridad en positivo, entero, prerrequisitos no bloqueantes y
  visibilidad de tres estados.

### Ampliaciones futuras, no defectos de esta entrega

- **Alias de modelo.** El mismo BZ08NG114 es «Z8.3» en el catálogo y «Z8
  Silver/Grey» en la web; la identidad exige igualdad de texto, y el extractor
  canónico no resuelve «Z8.3» desde el nombre. Un campo `model_aliases` en la
  referencia evitaría que el operador tenga que teclear exactamente «Z8.3».
- **Presentaciones del catálogo.** WPZ8NG116 (DISPLAY 116, «+25 CL») y el rollo
  WRZ8GY000 pueden sembrarse como ediciones propias cuando se necesiten; hoy
  el DISPLAY que vende la tienda no tiene referencia y eso es correcto.
- **Resumen del claim.** `productSpecClaimSummary` imprime el texto de
  `platform` y luego «· 6/7/8 velocidades»; con la clave C corregida el resumen
  deja de repetirse.
- **`chain_width_family` en conectores de pasador** sigue visible aunque no
  aplique; inocuo.
- **Los seis conectores del inventario sin código en el nombre** (KMC 9, 10 y
  11 «speed», y Risk) sólo pueden vincularse tecleando el modelo; la
  auditoría de inventario decide por envase.

---

## Revisión de las correcciones A, B y C — 2026-09-06, 14:30 PDT

Sólo lectura sobre la migración `20260906103000` (md5
`8a17eff7a66240a29f92aae7559ce056`, 302 líneas), `product_spec_contract.dart`,
`product_form_page.dart`, `chain_connector_spec_contract.sql` y
`chain_connector_spec_contract_test.dart`. No edité código, SQL ni datos.

### Verificado

| Corrección | Estado | Dónde lo comprobé |
|---|---|---|
| A. La regla `Pin → reusable=false` cita Park Tool y Sheldon | Correcto | migración, línea 255, `sources` con ambas URLs |
| C. Las cadenas nuevas usan `claims[].coverage`, sin `platform` | Correcto | seed Z8.3 y Z7: `"coverage":"Todos los sistemas"`; `productSpecClaimSummary` lee `coverage`; el motor sólo lee `platform` + `exclusive`, así que la cobertura no puede tokenizarse como plataforma |
| B1. `spec_evidence_source` fuera del bucle de `reference_conflict` | Correcto en SQL y Dart | migración línea 25; `product_spec_contract.dart` línea 132; la regla `unsupported_declaration` ya lo excluía |
| B2. La evidencia enviada por el operador se guarda como `mechanic` | Correcto | writer, líneas 126–131: la clave se quita de `v_reference` cuando viene en `p_values`, así el merge la deja al operador y `source` resulta `mechanic` |
| B3. El formulario mantiene la evidencia visible y editable con referencia | Correcto | no se bloquea (`_isSpecFieldAutoLocked`, línea 1541), no se oculta como «suministrada» (línea 7683), no aparece en la tarjeta de la referencia (línea 7530), helper propio (línea 1484) |

Flujos de evidencia que tracé por el código, con la regresión que los cubre:

1. Referencia vinculada, operador escribe «Envase revisado» → payload la envía
   explícita → `mechanic` → el snapshot no la lista en `catalog_keys` → al
   reabrir no es automática → al desvincular se conserva. pgTAP líneas 58–64.
2. Referencia vinculada, operador no escribe nada → la URL del fabricante se
   deriva, se omite del payload, se guarda `catalog` → al desvincular se retira
   junto con los demás datos automáticos. Coherente con «sus datos».
3. Operador borra su nota con la referencia vinculada → el formulario rellena
   la URL derivada → el servidor reescribe el hecho como `catalog`. Correcto:
   con referencia siempre hay una fuente.
4. Cambio de referencia con nota propia → la nota sigue explícita y `mechanic`;
   los hechos de la referencia anterior se podan y se borran en servidor.
5. La rama «sin cambios» del writer (líneas 165–172) conserva `supplier_text`,
   `import` y `name_reading` cuando el valor no cambia y no hay referencia
   sobre esa clave. Es lo que evita reescribir las 18 cadenas al tocar un precio.

### Un bloqueo concreto que queda, del mismo tipo que B

**El carve-out de B se aplica sólo a `spec_evidence_source`; cualquier otro
hecho manual preexistente igual al de la referencia se reatribuye a `catalog`
y se pierde al desvincular.** Traza en el writer: si el producto ya tenía
`chain_width_family = 3/32` con `source = supplier_text` y el operador vincula
Z7 (cuyos hechos incluyen 3/32), el cliente envía la clave explícita porque no
era automática; en el servidor `v_reference ? key` es verdadero, la rama «sin
cambios» exige `f.source = 'catalog'` y no se cumple, así que reescribe el
hecho con `source = 'catalog'`. Al reabrir, `catalog_keys` lo incluye, el
formulario lo trata como automático y desvincular lo poda y lo borra. Caso real
del inventario: «Cadena 1/2" X 3/32" Kmc Z7», que hoy tiene ese hecho de texto
del proveedor.

Es la misma pérdida que B corrigió para la evidencia, y la corrección es la
misma línea generalizada: quitar de `v_reference` **todas** las claves que
vienen en `p_values`, no sólo la de evidencia. El cliente sólo envía explícito
lo que no es automático, así que «explícito» ya significa «del operador»; la
igualdad con la referencia la sigue garantizando `reference_conflict`, y la
guarda «la referencia requiere sus datos documentados» sigue satisfecha porque
el hecho está presente. Con eso la rama «sin cambios» conserva `supplier_text`
y `catalog_keys` queda reducido a lo que de verdad se derivó. Regresión a
añadir en pgTAP: hecho `mechanic` previo igual al de la referencia → vincular →
`source` sigue `mechanic` y no aparece en `catalog_keys` → desvincular lo
conserva. Mientras el writer no esté desplegado, es un cambio de una expresión;
después, será otra migración.

### Observaciones sin bloqueo

- La rama «sin cambios» recalcula `spec_payload_display_internal_v1` del
  producto completo en cada iteración del bucle. Con fichas de 10 a 15 hechos
  es despreciable; si alguna familia crece, conviene calcularlo una vez antes
  del bucle.
- El plan de verificación local (fixture histórico, reaplicar exactamente
  `20260906070000` y luego `20260906103000`, reexportar fixtures, pgTAP) cubre
  la deriva que encontré antes. En el read-back de producción, además de
  plantillas y referencias, comparar `pg_get_functiondef` de
  `spec_write_payload_internal_v2` y `spec_validate_draft_internal_v1` con el
  texto de la migración; son las dos funciones que esta migración reemplaza.

---

## Veredicto sobre el writer corregido — 2026-09-06, 15:00 PDT

Migración `20260906103000` con md5 `2725bea01239b77e13349943533d162e`, 301
líneas. Sólo lectura.

**Correcto; no queda bloqueo.** El writer resta de `v_reference` todas las
claves presentes en `p_values` antes del merge, así que «explícito» significa
«del operador» para cualquier hecho, no sólo para la evidencia. Consecuencias
que tracé y que las regresiones cubren:

- Hecho `mechanic` o `supplier_text` previo igual al de la referencia:
  llega explícito, cae en la rama «sin cambios» con `not (ref ? key)` y
  `source <> 'catalog'`, y conserva fuente, lecturas y `updated_at`. pgTAP
  línea 75. Al reabrir no está en `catalog_keys` (línea 76); al desvincular
  sobrevive (líneas 77–78).
- Hecho igual pero con `source = 'catalog'` de un guardado anterior, que el
  operador vuelve a teclear: no se salta y se reescribe como `mechanic`. Es la
  lectura correcta: el operador lo afirmó.
- Hecho distinto al de la referencia: `reference_conflict` sigue bloqueando el
  guardado, y la guarda «la referencia requiere sus datos documentados» sigue
  satisfecha porque el hecho está presente y conocido.
- `p_values` vacío: `jsonb - text[]` con arreglo vacío no altera la referencia;
  el flujo automático queda como antes.
- Lecturas del nombre (`name_reading`) iguales al catálogo conservan su recibo,
  porque la rama «sin cambios» ya no las reatribuye.

Efecto visible que conviene saber, no un defecto: un hecho manual igual al de
la referencia sigue oculto de la sección editable mientras la referencia está
vinculada, porque `_buildSpecSection` lo trata como suministrado; reaparece
como manual al desvincular. Coherente con el contrato.
