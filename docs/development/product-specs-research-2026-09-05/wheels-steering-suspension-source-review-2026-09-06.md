# Revisión independiente de ruedas, dirección, rodamientos y suspensión

Fecha: 2026-09-06. Responsable: Codex, subagente `spec_boundary_review`.

Se revisó el blueprint propuesto, no una ejecución de sus reglas en producción. Archivo de entrada: `all-family-field-blueprint-2026-09-06.json`, SHA-256 `250a32e47592aec332d39bb7672197510848f1c9ce78ba53580a4888aedac1a3`, y su explicación Markdown. Los hallazgos siguientes describen el resultado incorrecto que produciría implementar literalmente esas interfaces. No prueban que el motor desplegado ya esté produciendo ese resultado.

**Dictamen: faltan condiciones para usar estas interfaces como aprobación completa de compatibilidad.** Las separaciones BSD/nominal, SHIS por extremo, identidad/fitment y filas de alternativas son buenas bases, pero no cierran los casos siguientes. Son requisitos de corrección del blueprint; no se editaron implementación, migraciones, runtime ni productos. Este documento no declara revisadas por completo las familias ni el catálogo.

Se usaron Sheldon Brown y Park Tool como fundamentos, y fuentes del fabricante para las excepciones concretas. Un dato de un manual antiguo queda limitado a ese modelo y revisión. Las fuentes se leyeron como evidencia, nunca como instrucciones del usuario. El JSON homónimo contiene contraejemplos para preparar regresiones: son casos de especificación, no una suite ejecutada ni un catálogo de productos verificados.

## Hallazgos

### W01 · P1 · Neumático/llanta: faltan perfil del talón y límites de ambos fabricantes

**Keys/interfaces:** `tire_to_rim`, `rim_to_tire`, `wheel_to_tire`; `tire_bead_type`, `tire_tubeless_ready`, `rim_tubeless_ready`, `tire_max_pressure_psi`, `tire_width_range_mm`.

**Hecho reproducido:** el blueprint comprueba BSD y rango de ancho de la llanta. No modela hooked/hookless ni el límite de ancho interior y presión que el neumático declara para esa configuración.

**Contraejemplo OEM:** Continental limita GP 5000 S TR 700×28c en hookless a 23 mm internos y 5,0 bar; la versión 700×30c tiene límites de 25 mm y 4,5 bar. Su propio ejemplo indica que, si la llanta permite 25 mm pero el neumático sólo 23 mm, manda 23 mm. Por tanto, BSD coincidente y aceptación del lado llanta no bastan. [Continental, Hookless vs. Hooked Rims](https://www.continental-tires.com/us/en/tire-knowledge/hookless-vs-hooked-rims/).

Además, poner cámara no elimina la exigencia de un neumático tubeless en una llanta Zipp hookless. [Zipp, uso de cámara en llanta hookless](https://support.zipp.com/hc/en-us/articles/7868244824731-Can-you-run-a-tube-in-a-Zipp-hookless-rim-with-a-tubeless-tire).

**Propuesta:** filas por modelo/variante de neumático y configuración de llanta, con perfil, ancho interior admisible, método de montaje y límite de presión con unidad y fuente. Intersectar las restricciones de ambos componentes sin combinar celdas de filas diferentes. Una presión máxima universal del producto no representa los dos montajes. Si falta una condición necesaria, conservar `unknown`; no aprobar a partir de la regla orientativa ancho/llanta. Esta última es una guía histórica, no una homologación de hookless. [Sheldon Brown, Tire Sizing](https://www.sheldonbrown.com/tire-sizing.html), [Park Tool, Tubeless Tire Compatibility](https://www.parktool.com/en-us/blog/repair-help/tubeless-tire-compatibility).

**Alcance:** neumáticos, llantas y ruedas armadas. Regresión: 28c/25 mm hookless no se aprueba con la fila de 30c; 4,5 bar no se reemplaza por el máximo de otra variante.

### W02 · P1 · Amortiguador/cuadro: las tres medidas no resuelven la interferencia

**Keys/interfaces:** `shock_to_frame`, `R20_shock_e2e_stroke`, `eye_to_eye_mm`, `stroke_mm`, `mount_kind`, `mounting_hardware_included`; `frame.rear_shock_size`.

**Hecho reproducido:** sólo entrecentros, carrera y montaje participan en `exact_match`; únicamente la ausencia de medidas del cuadro genera desconocido. El hardware se representa por un booleano de contenido.

**Contraejemplo OEM:** RockShox documenta posible contacto del depósito RC2T con el cuadro Specialized Demo 2020+ al comprimir. También identifica variantes específicas por modelo/talla, y distingue carrera del amortiguador de recorrido de rueda. [RockShox, Rear Suspension Fitment](https://www.sram.com/en/service/articles/RockShox-fitment-article).

**Propuesta:** la coincidencia dimensional sólo supera el control dimensional. Requerir identidad y generación de amortiguador/cuadro, talla cuando aplique, envolvente/depósito y condiciones durante todo el recorrido. Representar por separado cada extremo de fijación: tipo, diámetro de perno, ancho del hardware y referencia/adaptadores requeridos. `incluido` no significa `apropiado para este cuadro`. Añadir relaciones OEM de aprobación, exclusión o verificación pendiente, conservando tune y modificaciones autorizadas cuando corresponda.

**Alcance:** amortiguador, cuadro y kits de montaje. Regresión: el Demo/RC2T permanece pendiente de resolución de la interferencia aunque se hayan hecho coincidir las tres medidas; el aviso OEM de que puede tocar no se convierte en una exclusión universal de todo amortiguador RockShox.

### W03 · P1 · Rodamientos: envolvente y código corto no equivalen a función compatible

**Keys/interfaces:** `bearing_cartridge_fit`, `bearing_size_code`, `bearing_construction`, `bearing_application`; mismo riesgo para cualquier consumidor de ID/OD/ancho como aprobación total.

**Hecho reproducido:** `bearing_size_code` se presenta como código ISO; la nota permite igualdad exacta de código **o** ID/OD/ancho. `bearing_application` se declara orientación, sin efecto sobre la interfaz. `Cartucho sellado` no distingue la construcción interna.

**Contraejemplo OEM:** Enduro advierte que existen tamaños idénticos en mazas y pivotes, pero desaconseja intercambiar sus rodamientos MAX de pivote y los de maza. Difieren en retención de bolas, sellado/lubricación y cargas/rotación previstas. [Enduro, Help Center, “Can I use MAX suspension pivot bearing in my hubs…”](https://cycling.endurobearings.com/en-ca/apps/help-center).

**Propuesta:** separar designación original del fabricante, código dimensional normalizado y referencia de repuesto completa; conservar sufijos. Hacer de ID/OD/ancho un filtro de envolvente, no una prueba suficiente. Registrar construcción y destino funcional requeridos, o una equivalencia OEM específica. “Cabe” y “aprobado para este uso” deben tener resultados distintos. La advertencia de uso inadecuado no debe reinterpretarse como imposibilidad geométrica.

**Alcance:** mazas, dirección, pedalier, pivotes y repuestos que reutilicen el comparador. Regresión: misma envolvente con función desconocida no produce `compatible`; incompatibilidad funcional documentada conserva su motivo y fuente.

### W04 · P1 · Dirección: un ángulo escalar no representa los dos biseles

**Keys/interfaces:** `bearing_contact_angle_deg`, `bearing_cartridge_fit`.

**Hecho reproducido:** el campo admite un único número, es opcional y no aparece entre los campos requeridos de la interfaz; su nota dice que sin él no se aprueba dirección. La nota y el contrato estructurado no coinciden.

**Contraejemplo OEM:** Cane Creek especifica pares 36×45 y 45×45; IS47/33 y EC44/33 son excepciones explícitas de sus conjuntos completos. Un único `45` pierde qué superficie tiene ese ángulo. [Cane Creek Forty, Product specification](https://www.canecreek.com/products/40).

**Propuesta:** par interno/externo con convención documentada, por rodamiento y por extremo superior/inferior, más envolvente y referencias de asiento. El gate debe requerir ambos cuando esa interfaz los necesite. No deducirlos del sufijo SHIS ni mezclar el superior de una alternativa con el inferior de otra.

**Alcance:** cartuchos de dirección y repuestos. Regresión: 36×45 y 45×45 no se colapsan al mismo valor; un ángulo faltante no confirma montaje.

### W05 · P2 · SHIS del conjunto no es un identificador único del alojamiento del cuadro

**Keys/interfaces:** `headset_to_frame_and_fork`, `frame.headset_upper_shis`, `frame.headset_lower_shis`, `fork_to_headset_and_frame`.

**Hecho reproducido:** el blueprint bloquea un código superior/inferior diferente del registrado para el tubo de dirección. Esto puede confundir la dirección original de la bici con todas las direcciones aceptables por el alojamiento.

**Contraejemplo OEM:** Cane Creek explica que, con el mismo tubo de 44 mm y horquilla recta, sirven tanto ZS44/28.6 + EC44/30 como ZS44/28.6 + ZS44/30. Cambia el stack inferior. También explica el redondeo de 41,8 mm a IS42. [Cane Creek, Everything you need to know about Headsets](https://support.canecreek.com/support/solutions/articles/62000202657-full-article-everything-you-need-to-know-about-headsets-).

**Propuesta:** puertos de cuadro y horquilla separados: tipo de asiento, diámetro nominal de alojamiento, profundidad/stack admisible, espiga superior y asiento de corona. La dirección declara cómo conecta esos puertos. Mantener SHIS del montaje original como evidencia de configuración, sin convertirlo en una lista exhaustiva. Dimensión medida, código nominal y tolerancia de montaje requieren significado distinto; no probar ajuste por igualdad de números medidos. Park Tool publica diámetros de alojamiento, cazoleta y rodamiento en columnas diferentes. [Park Tool, Headset Standards](https://www.parktool.com/en-us/blog/repair-help/headset-standards).

**Alcance:** cuadro, dirección y horquilla. Regresión: la alternativa EC44/30 frente a ZS44/30 supera el control de alojamiento; el montaje completo sigue sujeto al stack y longitud disponible de espiga.

### W06 · P2 · Dirección: posiciones parciales y códigos válidos quedan fuera

**Keys:** `headset_upper_shis.required_when=always`, `headset_lower_shis.required_when=always`, `shared_vocabularies.headset_shis_code.pattern`.

**Hecho reproducido:** ambos extremos son obligatorios en todo producto. La expresión regular contiene una lista cerrada y omite 62 en el alojamiento y 38,1 en la espiga. Un `fullmatch` local devuelve `false` para `ZS62/40` y `EC49/38.1`.

**Fuente OEM:** Forty ofrece conjuntos superiores, inferiores y completos; sus opciones incluyen 62/40 y 49/38.1|49/40. No se asignó un MPN a partir de la posición de los selectores HTML. [Cane Creek Forty, selectores Type & Position / Head Tube Size](https://www.canecreek.com/products/40).

**Propuesta:** identidad inicial `assembly_scope = upper | lower | complete`; requerir sólo los extremos vendidos. Parser sintáctico separado del registro ampliable de combinaciones documentadas. Sintaxis desconocida o estándar aún no investigado conserva el literal y `unknown`; no implica una combinación físicamente imposible. Tampoco admitir todo producto cartesiano que pase la regex.

**Alcance:** altas, investigación y reemplazos de direcciones. Regresión: una mitad inferior no exige inventar extremo superior; vocabulario extensible sin aprobar automáticamente nuevos códigos.

### W07 · P1 · Horquilla: falta envolvente del neumático y geometría admitida por el cuadro

**Keys/interfaces:** `fork_to_tire`, `fork_to_headset_and_frame`, `max_tire_width_mm`; faltan altura/diámetro exterior inflado y longitud eje-corona.

**Hecho reproducido:** el neumático sólo se cruza por BSD y ancho máximo. La conexión al cuadro sólo pide espiga, rosca y asiento de corona. `travel_mm` y `fork_offset_mm` son medidas sin gate contra el cuadro.

**Contraejemplo OEM:** el manual FOX 40 de 2013, columna 40 mm/26", limita neumático inflado a 694 mm de diámetro de pico, 670 mm de borde y 71 mm de ancho. Un caso construido de ancho 70 mm y pico 695 mm incumple aunque pase ancho y nominal. El mismo manual requiere verificar stack total de 105–166,8 mm para la corona direct mount. [FOX 2013, Installing the 40](https://tech.ridefox.com/fox_tech_center/owners_manuals/013/Content/Forks/40/40withDMS_Installation.html).

**Propuesta:** conservar límites y método de medición OEM de envolvente, holguras y comprobación durante compresión/giro; filas de combinaciones rueda/neumático admitidas por la horquilla. El cuadro debe expresar restricciones de horquilla por modelo/talla: geometría, tipo de corona y recorrido/longitud cuando el fabricante lo exija. BSD es el código de asiento neumático/llanta; una horquilla no tiene ese asiento y su lista de ruedas admitidas puede contener alternativas.

**Alcance:** horquilla, cuadro y neumático. Regresión: la coincidencia de dirección no confirma geometría; el caso construido fuera de la envolvente FOX no se aprueba. Los límites de esta horquilla histórica no se aplican a otras generaciones.

### W08 · P2 · OLD: `integer` pierde 132,5 mm y la igualdad universal rechaza un caso OEM

**Keys/interfaces:** `shared_vocabularies.hub_old_mm.type=integer`, `frame.rear_hub_old_mm`, `bicycle.rear_hub_old_mm`, `hub_to_frame_dropout`, `wheel_to_frame_or_fork`, `R10_hub_old_plus_axle`.

**Contraejemplo OEM:** Surly Pack Rat especifica espaciado Gnot-rite de 132,5 mm que admite mazas de 130 o 135 mm. Es un caso expresamente diseñado así; no autoriza a forzar cualquier cuadro. La ficha de cuadro lo dice también en su apartado de punteras. [Surly Pack Rat](https://surlybikes.com/products/pack-rat), [Surly Pack Rat Frame Sheet, revisión 85-000633_INST_A](https://surlybikes.com/uploads/downloads/surly-pack-rat-framesheet-85-000633_INST.pdf).

**Propuesta:** distinguir ancho físico entre punteras de interfaces nominales de maza aceptadas. La primera magnitud debe preservar decimal; las segundas son filas OEM por tipo de retención/diámetro/ancho y extremo. No redondear 132,5 a 132/133 ni crear un intervalo abierto 130–135. Otros enteros, como conteos o códigos nominales BSD, no necesitan cambiar a decimal por este hallazgo.

**Alcance:** cuadro, bicicleta, rueda y maza. Regresión: almacenar 132,5 exactamente y permitir 130/135 sólo dentro del alcance documentado; no inferir aceptación de 131 ni intercambiabilidad general 130↔135.

### W09 · P2 · Eje pasante: vocabulario incompleto y retención separada de OLD

**Keys/interfaces:** `shared_vocabularies.thru_axle_thread`, `retention_to_hub_and_frame`, `fork_to_front_wheel`, `R10_hub_old_plus_axle`.

**Hecho reproducido:** lista cerrada M12/M15 × 1,0/1,5. La propia S28 enumera además M12×1,75 y M20×1,0/1,5/1,75. [Park Tool, TAP-TA-SET](https://www.parktool.com/en-us/product/thru-axle-tap-set-tap-ta-set). Como contraejemplo comercial exacto, Robert Axle LIG601 tiene diámetro 12 mm, longitud 174 mm y paso 1,75 mm; su ficha distingue expresamente longitud de eje de estándar de maza. [Robert Axle, LIG601](https://robertaxleproject.com/product/lightning-bolt-on-axle-rear-12-mm-x-174-mm-x-1-75-thread/).

**Propuesta:** rosca estructurada/extensible con sistema, diámetro nominal y paso; preservar la denominación OEM. Separar conexión maza-punteras de fijación eje-cuadro/horquilla y hacer condicional el requisito de rosca a retención pasante. Para aprobar un eje de recambio hacen falta sus condiciones OEM de longitud útil, asiento de cabeza, arandelas/adaptadores y enganche de rosca; no igualar longitud a OLD. No se propone aquí una tolerancia universal de longitud.

**Alcance:** mazas, horquillas, cuadros y repuestos de retención. Regresión: LIG601 se representa sin `unknown` artificial en la rosca; QR no queda pendiente por carecer de rosca de eje pasante. Una ficha dimensional del eje, por sí sola, no confirma una bicicleta concreta.

### W10 · P2 · Radio: calibre del alambre no es diámetro de rosca

**Keys/interfaces:** `spoke_thread_diameter_mm`, `spoke_gauge`, `spoke_nipple.nipple_thread`, `spoke_to_wheel_geometry`.

**Hecho reproducido:** la nota de `spoke_thread_diameter_mm` propone 2,0 para 14G y 1,8 para 15G. Mezcla diámetro del alambre con designación de su rosca.

**Contraejemplo OEM:** Sapim explica que la rosca se lamina, no se corta, y denomina FG 2.3 mm la de su radio estándar de 2 mm. Se leyó el párrafo “Thread”, página 8 de la edición taiwanesa; no se extrajo una relación de una tabla ni se asumió equivalencia entre traducciones. [Sapim, folleto 2018, p. 8](https://www.sapim.be/sites/default/files/Sapim%20brochure%202018%20def%20A5%202018-Taiwanese%20LR.pdf).

**Propuesta:** conservar `wire_diameter_at_thread_mm`/calibre y `spoke_thread_standard` como significados distintos. Si se recoge diámetro real de rosca, debe ser una medición rotulada, no copiar 14G→2 mm. El niple debe declarar la interfaz de rosca con la misma convención y, para sistemas específicos, referencia compatible OEM.

**Alcance:** radios y niples. Regresión: un radio Sapim de 2 mm no resulta incompatible con su niple correcto porque uno se haya registrado como FG2.3 y el otro como “14G”. La normalización documentada conserva ambos significados.

### W11 · P2 · Radiado: ±1 mm y mismo número de agujeros no son leyes universales

**Keys/interfaces:** `spoke_to_wheel_geometry`, `rim_to_spokes_hub`, `R19_spoke_geometry`.

**Hecho reproducido:** el blueprint bloquea largo distinto del calculado fuera de ±1 mm y cualquier diferencia entre conteos de agujeros.

**Evidencia:** la fuente S24 distingue calculadoras que incorporan o no compensación por tensado; el margen depende también del niple y longitud de rosca. Describe un rango típico, advierte que algunos sistemas toleran menos y reconoce combinaciones útiles con conteos diferentes. No prescribe las dos reglas universales anteriores. [Sheldon Brown / John Allen, Measurements for Spoke-Length Calculations](https://www.sheldonbrown.com/spoke-length.html).

**Propuesta:** una receta de armado debe identificar lado, geometría, patrón, método de cálculo, compensación y niple. Sin rango validado para ese montaje, diferencia respecto a la calculadora requiere revisión; no crear una aprobación por ±1 mm ni reemplazarla por ±3 mm. Mantener mismo conteo como camino estándar; una excepción necesita receta completa y evidencia. La mera ausencia de receta tampoco prueba imposibilidad física universal.

**Alcance:** armado de ruedas y búsqueda de repuestos. Regresión: un cálculo sin metadato de compensación no produce un bloqueo definitivo por un milímetro; no se aprueba un radiado alternativo sólo porque su conteo aparezca en una lista.

## Gates de integración y preparación del llenado

1. Resolver W01, W02, W03, W04 y W07 antes de emitir compatibilidad completa para esos pares. Los datos parciales pueden conservarse con procedencia y resultado desconocido.
2. Incorporar las correcciones de representación W06, W08, W09 y W10 antes de importar hechos de forma masiva: un esquema incapaz de representar un dato obliga a perderlo, redondearlo o inventar otro.
3. No confundir validación de la ficha con aprobación de un montaje. Un producto completo en sus campos intrínsecos todavía puede necesitar identidad del destino y una configuración concreta.
4. Cada comparación debe conservar sus extremos y una fila completa de evidencia. No sumar, por ejemplo, el ancho de una variante, la presión de otra y la aprobación de un tercer fabricante.
5. Contrastar cualquier nuevo fixture ejecutable con el contrato real del motor. Los fixtures adjuntos expresan obligaciones semánticas, no aseguran que la API actual tenga esos nombres o estados.

## Límites de esta revisión

La comprobación local sólo leyó el blueprint y evaluó su patrón SHIS; no ejecutó el motor ni guardó productos. Las pruebas SQL/Dart de la revisión de fronteras anterior no son evidencia de estas reglas mecánicas.

Las páginas OEM en HTML se leyeron directamente. Algunos PDF públicos no pudieron descargarse/renderizarse; se utilizó únicamente el texto primario indexado de los párrafos de Sapim y Surly indicados. No se asignaron columnas ambiguas de la tabla RockShox 2020 de neumáticos a modelos concretos. No se incorporó como ley el margen de +15 mm de válvula ni una tolerancia universal de ejes, porque no se cerró aquí su evidencia.

La revisión deja pendientes por diseño las recetas concretas de cada modelo del catálogo y la comprobación del montaje real. No acredita todas las ruedas, direcciones, rodamientos o suspensiones por los once contraejemplos documentados.
