# Matriz de familias y prerrequisitos de ficha

Diseño: 2026-09-05; estado actualizado el 2026-09-06. **Matriz objetivo de
cobertura; la base transversal ya está implementada.** Complementa el
[contrato de fichas](product-technical-specifications-contract.md) y la
[base de conocimiento K01–K30](bicycle-compatibility-knowledge.md).

La matriz define qué debe saber el sistema, qué decisión depende de otra y
qué falta para declarar compatibilidad. No es una tabla completa de valores
permitidos ni autoriza sembrar opciones por analogía. Los nombres de familias
actuales son las claves leídas en producción; los de extensiones son propuestas.
Cada futura regla necesita casos positivos, negativos y desconocidos, además
de evidencia propia para sus modelos. Una fila con fuentes base no significa
que todos los repuestos comerciales de esa familia estén certificados.

El [resultado implementado](../development/product-specs-research-2026-09-05/implementation-result.md)
usa las 37 plantillas activas, con identidad, roles de campo, requisitos tipados,
fuente y guardado común. Las dependencias específicas nuevas se concentran en
cadenas/conectores; las demás conservan su visibilidad declarada y validación de
tipo/vocabulario. Las reglas históricas de opciones son orientativas hasta su
revisión mecánica. Esta matriz no se ha convertido automáticamente en bloqueos.
El catálogo documental contiene las tres ediciones iniciales X8 EU, eGlide US y
X11 US, más seis modelos de conectores KMC y Z8.3/Z7 de presentación exacta,
verificados en la [segunda entrega](../development/product-specs-research-2026-09-05/chain-connector-implementation-2026-09-06.md).
HV408 y los modelos de las demás familias siguen pendientes de fuente exacta.
La auditoría del llenado encuentra 742 productos físicos sin familia asignada
(706 activos); esta matriz y el [plan del catálogo](../development/product-specs-research-2026-09-05/catalog-fill-execution-plan-2026-09-06.md)
deben evolucionar juntos, sin asignar familias por analogía ni excluir accesorios.

La [auditoría global del 6 de septiembre](../development/product-specs-research-2026-09-05/global-audit-and-sanitation-2026-09-06.md)
leyó los 1.664 registros y las 136 definiciones. Los 35 dominios numéricos
corregidos están desplegados en 22 plantillas; siguen pendientes relaciones,
cardinalidad, rangos aplicables, kits y nuevas clases. Las 108 clases candidatas
de productos sin ficha no implican 108 plantillas nuevas. El llenado espera el
saneamiento global, también de cafetería, electrónica, scooter y accesorios.

## 1. Contrato transversal de cada familia

Todas incluyen identidad/variante, unidades, alcance de medición, procedencia,
estado y revisión. Las propiedades pueden ser parciales. Un selector físico
usa vocabulario extensible gobernado o medidas con tolerancia, no una lista
cerrada arbitraria derivada del stock que hoy tiene la tienda.

La familia define: decisiones iniciales; campos dependientes; interfaces de
entrada y salida; discriminadores de variante; condiciones de publicación;
preguntas pendientes para montaje; y fuentes del fabricante aún necesarias.
No inferir «compatible» porque se completaron todos los campos de una plantilla
todavía incompleta.

## 2. Las 36 familias actuales

`complete_brake` tiene dos plantillas, hidráulica y mecánica: 37 en total.
Los conteos de campos actuales se conservan en el [snapshot](../development/product-specs-research-2026-09-05/templates.json).

| Familia actual | Decisión inicial → dependencias | Evaluación de montaje / dato que falta | Base |
|---|---|---|---|
| `chain` | Referencia y transmisión declarada → filas sistema/velocidades; medidas, orientación y cierre | Cadena–dentado y conjunto de transmisión; no derivar aprobación por ancho ni marca | K01–K07 |
| `chain_link` | Tipo de conector y referencia → modelos de cadena, geometría/pasador, reutilización | Conector exacto–cadena; no heredar automáticamente todo el perfil de una cadena | K06 |
| `cassette` | Montaje en núcleo/revisión → piñones, secuencia, dentado, cuerpo/longitud y espaciadores | Núcleo + indexación + cadena + límites de cambio; velocidades no fijan núcleo | K08–K10 |
| `freewheel` | Rueda libre roscada y rosca → dimensiones axiales, piñones, rango, dentado | Maza roscada y espacio disponible; no ofrecer XD/Micro Spline como montajes | K08 |
| `fixed_cog` | Piñón fijo roscado/estriado específico → rosca/interfaz, retención, ancho dentado y dientes | Maza, contratuerca cuando aplique y cadena; no clasificar como rueda libre | K01, K08; completar manual del montaje |
| `cassette_spacer` | Cuerpo y cassette objetivo → espesor y ubicación en receta | Exigir combinación concreta y dirección; un espesor aislado no es universal | K09 |
| `rear_derailleur` | Modelo/revisión y accionamiento → interfaz de control, montaje, velocidades/rango admitidos | Indexación o protocolo, piñón máximo/mínimo, capacidad y holgura; no comparar sólo velocidades | K10, K13 |
| `front_derailleur` | Modelo, montaje y configuración de platos → clamp sólo si existe, tiro/control, línea y geometría | Plato mayor, diferencia entre platos y accionamiento delantero; un desviador activo no resuelve una configuración 1x | K10 |
| `shifter` | Función/lado y mecánico/electrónico/IGH → indexación, protocolo o tiro por subsistema | Mandos combinados se componen de cambio + freno; izquierdo/derecho no sustituye función | K10–K11, K23 |
| `derailleur_hanger` | Referencia de cuadro y tipo de interfaz → patrón, fijación, rosca, versión | Patilla exacta o UDH documentada; forma parecida no prueba identidad | K13; dibujo/modelo de cuadro pendiente |
| `derailleur_pulley` | Cambio objetivo y posición guía/tensión → dientes, eje, separadores, orientación | Kit/revisión del cambio y espacio de jaula; cantidad de dientes no basta | K10; despiece exacto pendiente |
| `chainring` | BCD/patrón o direct mount específico → dientes, offset, posición y perfil dentado | Biela/araña + cadena + línea + pareja de platos; no ofrecer BCD para direct mount | K12 |
| `crankset` | Construcción/eje y configuración de platos → caja admitida, montaje de platos, longitud y línea | Cuadro/pedalier + platos/cadena + pedales; componentes incluidos no sustituyen interfaces | K12, K18, K22 |
| `crank_arm` | Lado y sistema de unión → longitud, interfaz/eje y rosca de pedal | Pareja/eje y modelo compatible; biela e-bike requiere interfaz específica | K18, K22; despiece exacto pendiente |
| `drivetrain_kit` | Lista de componentes exactos → roles y variantes de cada componente | Evaluar receta completa y faltantes; no sumar las specs en una ficha plana | K05, K10, K13 |
| `chain_guide` | Montaje y modelo → dientes/diámetro admisible, línea, offset y posición | Cuadro + plato + biela; reglas por manual de guía, no por marca de transmisión | K12–K13; manual exacto pendiente |
| `bottom_bracket` | Caja del cuadro → rosca o alojamiento + ancho; luego eje/biela | Interfaz al cuadro y a la biela, longitud/espaciadores/línea; BSA no implica cuadradillo | K18 |
| `bottom_bracket_axle` | Sistema de eje → interfaz, longitudes y asimetría | Copas/rodamientos + bielas + cadena; longitud total y línea no son sinónimos | K18 |
| `bottom_bracket_cup` | Lado/construcción y caja → rosca/sentido o pressfit, asiento y rodamiento | Pareja/eje o referencia de cartucho; ocultar campos ajenos sin perder un borrador conflictivo | K18 |
| `bottom_bracket_bearing` | Rodamiento suelto/cartucho/canastillo → ID/OD/ancho o diámetro/cantidad de bolas | Asiento, eje, carga y geometría; mismo OD no certifica reemplazo | K18; catálogo exacto de rodamiento pendiente |
| `bearing` | Tipo y referencia → diámetro interior/exterior, ancho, contacto y sellos | Carga, tolerancia/ajuste y alojamiento; «sellado» no es identidad | K19; fuente industrial exacta pendiente |
| `brake_caliper` | Llanta/disco y mecánico/hidráulico/híbrido → montaje + tiro o circuito | Manilla, fluido/conexión si aplica, pastilla, rotor/pista y adaptador | K23–K26 |
| `brake_lever` | Función y accionamiento → tiro o modelo de circuito, abrazadera, puertos y lado | Freno objetivo y conexión; para mando combinado agregar función de cambio | K23, K26 |
| `complete_brake` | Composición del kit y tipo → roles manilla/cáliper/manguera/rotor/adaptador incluidos | Certificar kit contra cuadro/horquilla/rueda; no asumir rotor o adaptador incluido | K23–K26 |
| `brake_pad` | Llanta/disco y patrón/respaldo → referencia, retención, compuesto y alerones | Cáliper/porta-goma y pista/material/espesor admitidos; modelos compatibles como relaciones | K24–K25 |
| `rim_brake` | V, cantilever, cáliper u otro montaje → tiro, alcance, pernos y gomas | Posición del cuadro, pista de llanta y manilla; no habilitar campos de rotor | K23 |
| `rotor` | Interfaz de maza y referencia → diámetro, espesor nominal, pista y lockring | Maza/eje + cáliper/pastillas + adaptador + límites de cuadro/horquilla | K24 |
| `hub` | Posición y construcción → eje/OLD, rotor, bridas; núcleo sólo si hay transmisión externa | Interfaces con cuadro/horquilla, cassette/fijo/IGH y armado; conversiones necesitan kit exacto | K08–K11, K17 |
| `rim` | Tipo de neumático/asiento y BSD → ancho interior, talón, presión, perforaciones y ERD | Neumático y freno más geometría de armado; BSD, ERD y aro comercial son distintos | K14–K17 |
| `spoke` | J-bend/recto/propietario → longitud, diámetro/perfil, rosca y cabeza | Geometría real de rueda, cruce y niple; no seleccionar longitud desde «aro 27,5» | K17 |
| `rim_strip` | Protección de cámara o sellado tubeless → ancho, diámetro/longitud y aplicación | Canal/llanta/condiciones de cinta; no confundir cinta protectora con cinta sellante | K15 |
| `tire` | Tipo tubular/con talón y BSD → ancho, construcción, tubeless/hookless y límites | Llanta exacta, tabla ancho/presión y holgura; disciplina no prueba ajuste | K14–K16 |
| `tube` | Material y rango(s) de uso declarado(s) → BSD/ancho por rango, válvula y longitud | Neumático + agujero/profundidad de llanta; no cruzar BSD y anchuras de rangos distintos | K14, K16; tabla del fabricante de cámara pendiente |
| `tubeless_valve` | Referencia/base y sistema → diámetro/agujero, longitud, núcleo y conexión | Perfil/profundidad de llanta, insertos y base; Presta por sí solo no garantiza sellado | K15 |
| `tubeless_consumable` | Subtipo sellante/mecha/adhesivo → material, envase y aplicación | Compatibilidad química y de neumático/llanta por ficha concreta; separar recetas de dosificación | K15; ficha técnica de consumible pendiente |
| `headset` | Superior/inferior y SHIS → interfaces de cuadro/horquilla y rodamientos | Conjunto por ambos extremos, altura/pista/ángulos; «integrado 1 1/8» es insuficiente | K19 |

## 3. Familias faltantes y categorías reales que las necesitan

Las 72 hojas sin plantilla se conservan con ruta y conteo de productos en la
[auditoría](../development/product-specs-research-2026-09-05/leaves.json).
Las categorías comerciales no se renombrarán automáticamente. Por ejemplo,
«Adaptadores» aparece en varios lugares; necesita identificar qué adapta.
«Motor» en el catálogo chileno puede referirse al pedalier: nunca clasificarlo
como motor eléctrico sólo por la palabra.

| Familia/ramificación propuesta | Hojas o productos que cubre | Prerrequisitos y límites | Base / trabajo por cerrar |
|---|---|---|---|
| `seatpost`, `seatpost_shim`, `seat_clamp` | Tija, Adaptadores de tija, Collerín | Referencia/tipo → diámetros interior/exterior según papel; camisa con dirección; inserción y materiales | K20–K21; variantes locales |
| `saddle`, `saddle_cover` | Asiento, Cubre Asientos | Sillín → riel/abrazadera o montaje propietario; funda → dimensiones del asiento destino | K20; manual riel/abrazadera y dimensiones de funda |
| `stem`, `handlebar` | Tee, Manubrios | Construcción → interfaces horquilla/manubrio/controles; ancho/longitud/ángulo después | K20; límites de fabricante |
| `grip`, `bar_tape` | Puños, Cinta Manillar | Tipo de manubrio y control → diámetro/zona/longitud; distinguir cinta por pieza/rollo/kit | K20; medidas de producto |
| `headset_small_part` | Araña, Espaciadores | Función → interfaz y material de espiga, diámetros/altura; expansor no es araña genérica | K19; aprobación de horquilla |
| `fork` | Horquillas | Modelo/rígida/suspensión → espiga, largo, asiento, rueda/eje, freno; recorrido/offset y repuestos por revisión | K19, K24, K28; homologación de cuadro/horquilla |
| `rear_shock`, `suspension_service_kit` | Shock; futuros kits | Modelo/año → ojos/carrera/montajes/herrajes/espacio; fluidos y repuestos de esa revisión | K28–K29 |
| `brake_adapter` | Componentes/Frenos/Adaptadores | Montaje origen/destino y posición → diámetro actual/objetivo, pernos y receta exacta | K24; tabla de adaptadores |
| `hydraulic_hose`, `hydraulic_fitting` | Cable Freno Hidráulico, Fittings Hidráulicos | Circuito/modelos → manguera y extremos por lado, oliva/inserto/banjo, fluido | K26; tablas OEM indispensables |
| `control_cable`, `control_housing`, `control_terminal` | Fundas y piolas/Cambios/Frenos/Terminales y topes | Uso y construcción → diámetro, cabezal/extremo, longitud y terminal | K27; definición exacta de cada SKU |
| `cable_adjuster`, `brake_noodle` | Reguladores de tensión, Noodles | Función y pieza receptora → rosca, interfaz y recorrido/ángulo; no confundir regulador con funda | K23, K27; dimensiones del modelo |
| Protección de cable de freno | Gomas V-Brake | La imagen del producto 49b90689 confirma un fuelle protector de cable, no una pastilla. Diámetros, longitud y conexión deben investigarse; no usar patrón de pastilla ni compuesto de frenado | K23; revisión de imagen del catálogo |
| `pedal`, `cleat`, `pedal_peg` | Pedales, BMX/Pedalines; futuras calas | Pedal → rosca/lado y retención; cala → pedal exacto y zapato; peg → eje, posición y dimensiones | K22; manual de peg/cala |
| `wheel_retention`, `hub_axle`, `hub_cone`, `hub_locknut` | Agujas, Conos, Contratuerca | Identificar cierre/eje/cono → diámetro, paso, largo/sentido, contacto/rodamiento y maza | K17; despiece exacto; no deducir cono sólo por rosca |
| `spoke_nipple` | Niples | Rayo/rosca y asiento de llanta → longitud, cuerpo/cabeza y llave | K17; interfaz exacta |
| Extensión de consumibles tubeless | O'rings, Tripas Tubeless | Pieza/sistema destino → material y dimensiones o sistema de reparación | K15; química y geometría pendientes |
| `fastener` | Pernos/Tornillos/Otros | Función y rosca → diámetro/paso, largo útil, cabeza, material/grado y retención | Dibujo/especificación requerida; no rellenar torque por tamaño |
| `adapter` con extremos tipados | Accesorios/Adaptadores, Viñabike/Adaptadores | Primero identificar ambos extremos; después usar la familia concreta | Relación direccional del contrato; no crear compatibilidad «universal» |
| `pump`, `inflation_adapter` | Bombines | Tipo y válvula → cabezal, presión/volumen y rango de uso | Ficha de fabricante; una bomba de shock no se infiere de su aspecto |
| `accessory_mount`, `rack_basket`, `bottle_cage` | Soporte Celular, Canastos, Porta Caramagiola, Campanillas | Objeto y anclaje → diámetro/patrón, dimensiones, carga y holguras | Medidas y carga declaradas del modelo; no heredarlas de la bicicleta |
| `fender`, `training_wheel` | Tapabarros, Rueda Estabilizadora | Montaje/cuadro/rueda → rango de neumático, anclajes y restricciones de uso | K14 para diámetro; fuente de montaje/carga pendiente |
| `light`, `cycle_computer`, `sensor` | Luces, Ciclocomputadores, Reflectantes | Activo/pasivo y alimentación → anclaje, batería o entrada, protocolo y accesorios | Datos de fabricante; no deducir homologación por forma o lúmenes |
| `ebike_drive`, `battery`, `charger`, `controller` | Extensión prevista, no deducida de «Motores» | Modelo/sistema/generación → interfaz mecánica, eléctrica, protocolo/firmware y receta | Cobertura técnica pendiente; no activar compatibilidad eléctrica por voltaje/conector iguales |
| `workshop_tool` | Herramientas, Corta Cadena | Operación e interfaz de servicio → modelos/rango/herramienta de accionamiento | K30; catálogo y manual de cada herramienta |
| `workshop_chemical` | Grasa, Líquido Frenos, Lubricantes, Desengrasantes, Silicona, Abrillantadores; mixtos Viñabike | Uso y formulación → materiales/sistemas admitidos, envase y preparación | K26 para frenos; ficha técnica del químico/SDS, no reglas por color |
| `tube_repair`, `applicator` | Parches, Pegamento parches, Botellas aplicadoras | Material y proceso de reparación → adhesivo/parche compatible y contenido | Fabricante del sistema; butilo/TPU/látex no se tratan como equivalentes |
| `rider_equipment` con subtipos | Cascos, Guantes, Jerseys, Poleras, Lentes, Mochilas, Protectores | Tipo/modelo → talla/medidas, uso y certificación documentada si corresponde | Tablas de marca; ninguna homologación inferida desde nombre de categoría |
| `general_accessory` con subtipos | Audífonos, Botella de Agua, Candados, Cuerdas, Fundas, Souvenirs, Otros | Tipo real → atributos propios, contenido y dimensiones; vínculo al montaje sólo si existe | No forzar velocidades/ecosistema; revisar hoja genérica antes de especializar |
| Composición de kit | Groupset | Reutilizar `drivetrain_kit` y lista de componentes; no plantilla duplicada por categoría | K05, K10, K13 |
| Servicio | Servicio | Conservar `service_profiles`; materiales y repuestos apuntan a familias de producto | Backbone existente; auditar productos físicos clasificados aquí, sin recategorizarlos por esta lectura |

La arquitectura también admite conjuntos completos y piezas estructurales aunque
no aparezcan como hojas sin plantilla en esta captura. No inferir de su ausencia
que el ERP deba excluirlas:

| Extensión prevista | Decisiones e interfaces | Base / trabajo por cerrar |
|---|---|---|
| `frame`, `frameset` | Modelo/año/talla → dirección, pedalier, rueda/ejes, frenos, tija, patilla y suspensión; componentes incluidos por variante | K13, K18–K21, K24, K29; geometría, límites y manual del cuadro |
| `wheel`, `wheelset` | Composición y posición → maza/eje/retención, llanta/neumático, freno y núcleo trasero; rueda delantera y trasera con roles propios | K08–K09, K14–K17, K24; fichas de los miembros y límites del conjunto |
| `complete_bicycle` | Modelo/año/talla/variante → cuadro y lista de componentes por posición; separar equipamiento original de unidad serializada y modificaciones instaladas | Reutilizar `bike_profiles` y recetas de componentes; la ficha de venta no reemplaza el estado del taller |
| `freehub_body`, kits de conversión de maza | Maza/revisión y núcleo objetivo → unión interna, eje/end caps/rodamientos y espaciadores incluidos | K09 para cassette–núcleo; despiece OEM indispensable para núcleo–maza |

## 4. Reglas de cobertura para familias futuras

- Una familia nueva declara interfaces y preguntas mínimas antes de recibir un
  badge de compatibilidad. Puede existir sin reglas de compatibilidad todavía.
- Modelar adaptadores por ambos extremos y kits por miembros; no usar cadenas
  de texto con nombres de modelos como motor de reglas.
- No inventar familia técnica por una palabra en una descripción de uso.
  Una categoría comercial puede servir a varias variantes de una misma familia.
- Reutilizar las claves/IDs de interfaz compartidos con bicicletas; ampliar el
  tipo o añadir un atributo más preciso cuando el anterior sea ambiguo,
  conservando una proyección explícita para clientes antiguos.
- Registrar por familia: variantes con evidencia, reglas aprobadas, críticos
  faltantes, escritores migrados, superficies verificadas y fuentes por revisar.
  Cobertura de datos y porcentaje de formulario llenado son métricas diferentes.
- Un caso positivo real, uno negativo real y uno desconocido constituyen el
  mínimo de dominio; añadir adaptadores, conflictos y cambios de prerrequisitos
  cuando correspondan. No derivar las fixtures del validador que se está probando.
