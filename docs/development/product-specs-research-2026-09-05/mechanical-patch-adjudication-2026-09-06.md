# Adjudicación independiente de la propuesta mecánica — 2026-09-06

Revisadas **67 operaciones** contra el contrato congelado: **17 aceptar, 32 corregir y 18 rechazar**. Las 67 rutas/preimages coinciden. Ninguna operación fue aplicada. La revisión cubre esta propuesta de frenos/transmisión; no certifica familias completas ni el llenado del catálogo.

El JSON homónimo conserva cada `patch_id`, su ruta exacta, decisión, modificación acotada, fuentes y 18 casos de dominio/guardia. Son casos escritos, todavía no ejecutados. `aceptar` valida el contenido acotado, no reemplaza la compilación ni el rollout.

## Hallazgos que impiden aplicar la propuesta completa

- **Full Mount ≠ T-Type.** RED XPLR AXS 13 es Full Mount y exige Road Flattop; el puerto UDH tampoco elimina las restricciones del cuadro. [SRAM Full Mount](https://www.sram.com/en/learn/understanding-udh-and-full-mount), [cadena RED XPLR](https://support.sram.com/hc/en-us/articles/27120282414747-What-chains-are-compatible-with-SRAM-RED-XPLR-AXS-Can-I-use-a-T-type-chain).
- **MC-14-brake_lever está invertido.** Copia los extremos del cáliper y bloquea una maneta mecánica con HY/RD, que TRP documenta como entrada por cable. [TRP HY/RD](https://trpcycling.com/products/hy-rd).
- **MC-17a confunde plantilla con puerto.** ST-R8000-R integra freno y cambio; una regla por `template_key` no puede decidir qué cable acepta cada entrada. [Shimano ST-R8000-R](https://bike.shimano.com/es-ES/products/components/pdp.P-ST-R8000-R.html).
- **C-731 contiene excepciones que deben excluirse de las filas generales.** La fila ROAD11 no debe ocultar el suplemento de HG800/HG700/RS400, ni la fila 10/9/8 el segundo suplemento de los seis ROAD10 indicados. [Shimano C-731](https://productinfo.shimano.com/en/compatibility/C-731).
- **Una URL o `exhaustive=true` en alguna fila no cierra el universo.** La ausencia de un modelo fuera del alcance declarado queda desconocida; una exclusión expresa conserva su sujeto, condiciones y versión. Es una conclusión sobre el modelo de datos, ilustrada por las exclusiones acotadas del [GoatLink 11](https://www.wolftoothcomponents.com/products/goatlink-11).
- **Roscar el piñón fijo no acredita su retención.** Se necesitan por separado rosca derecha y retención izquierda; la maza de rueda libre carece de esta última. Las conversiones históricas descritas por Sheldon no se transforman aquí en permisos universales. [Sheldon Brown](https://www.sheldonbrown.com/fixed-conversion.html).
- **Adaptador no investigado no significa imposibilidad mundial.** SM-RTAD05 tiene dirección y exclusiones concretas; el manual prueba máximo 203 mm y exclusión RT86/RT76, no un mínimo 160 mm. [Shimano DM-MDBR001-06](https://si.shimano.com/en/pdfs/dm/MDBR001/DM-MDBR001.pdf), [Park Tool](https://www.parktool.com/en-us/blog/repair-help/disc-brake-rotor-removal-installation).

## Dictamen por grupo

### A01 · ACEPTAR · Rótulo HG L sin separador universal

Parches: `MC-01-shar0`, `MC-01-defi1`, `MC-01-defi2`, `MC-01-defi3`. Riesgo si se aplica tal cual: `none`.

El texto anterior imponía 1.85 + 1.0 mm a toda corona ROAD 10; el nuevo remite a filas.

**Cambio acotado:** Aceptar el rótulo nuevo y mantener el identificador de estándar separado de sus condiciones. No usar el texto como prueba de todas las coronas de terceros.

**Contraejemplo / control:** La condición adicional de seis ROAD 10 pertenece a modelos concretos en C-731.

**Gate residual:** Alias atómicos y referencias: las cuatro ocurrencias del token anterior están cubiertas por los cuatro parches; las filas MC-03 se adjudican aparte.

Fuentes: [Shimano C-731: freehub and cassette spline compatibility](https://productinfo.shimano.com/en/compatibility/C-731).

### A02 · ACEPTAR · Rótulo HG M conserva excepciones

Parches: `MC-02-4`, `MC-02-5`, `MC-02-6`, `MC-02-7`. Riesgo si se aplica tal cual: `none`.

El nuevo texto deja ROAD 11 y 7 bajo filas y LINKGLIDE bajo su tabla separada.

**Cambio acotado:** Aceptar el rótulo como nombre orientador. C-649 y otros fabricantes requieren su propia evidencia y no se consideran revisados por este rótulo.

**Contraejemplo / control:** No toda corona de 7 velocidades queda automáticamente aprobada para M.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Shimano C-731: freehub and cassette spline compatibility](https://productinfo.shimano.com/en/compatibility/C-731).

### A03 · CORREGIR · Filas C-731 deben ser mutuamente excluyentes

Parches: `MC-03`. Riesgo si se aplica tal cual: `P1`.

Las filas genéricas ROAD 11 y 10/9/8 se solapan con las excepciones nominales; models_only vacío no excluye modelos especiales.

**Cambio acotado:** Dar ámbito Shimano/edición a todas las filas. Excluir CS-HG800/700/RS400 de L+ROAD11 sin suplemento; excluir CS-7900/7800/6700/6600/5700/5600 de las filas genéricas 10/9/8 en L y M. Mantener suplementos correlacionados dentro de cada fila. Modelo desconocido no resuelve una excepción. No extrapolar celdas ausentes fuera del ámbito C-731.

**Contraejemplo / control:** CS-HG800 en L puede ser capturado por ROAD11 genérico sin 1.85; CS-5700 en L puede ser capturado por 10/9/8 con sólo 1.85.

**Gate residual:** Antes de motor: normalizar modelos y ámbito; casos de intersección/exclusión y modelo desconocido; no compilar frases de cassette como códigos medidos.

Fuentes: [Shimano C-731: freehub and cassette spline compatibility](https://productinfo.shimano.com/en/compatibility/C-731).

### A04 · CORREGIR · Lista de modelos requiere un tipo implementado

Parches: `MC-04-9`, `MC-04-10`. Riesgo si se aplica tal cual: `P1`.

La intención de limitar por modelo es válida; text_list/optional/semantics no son una columna ejecutable de rows_schema 190.

**Cambio acotado:** Traducir a filas por marca+modelo+generación/variante, o a una relación de conjuntos soportada. En 190 las columnas admiten text/token/decimal/integer/boolean/url; no insertar text_list ni metadata desconocida.

**Contraejemplo / control:** Una fila cuyo modelo no coincide no puede aprovechar una coincidencia sólo del ancho o de la marca.

**Gate residual:** Separar blueprint explicativo de schema ejecutable; validar compilación y fuentes por fila.

Fuentes: [Shimano C-731: freehub and cassette spline compatibility](https://productinfo.shimano.com/en/compatibility/C-731).

### A05 · RECHAZAR · URL OEM no cierra el universo de compatibilidad

Parches: `MC-05-cassette`, `MC-05-hub`, `MC-05-wheel`. Riesgo si se aplica tal cual: `P1`.

El no_row_matches propuesto convierte no listado en incompatible sólo por venir de C-731/C-649/S16. La URL no acredita ámbito ni completitud.

**Cambio acotado:** Mantener unknown/outside_declared_scope para ausencias. Emitir incompatible sólo por una exclusión explícita de la pareja/configuración o una tabla cerrada con ambos sujetos identificados dentro de su ámbito y edición. Separador exigido significa requisito pendiente, nunca permiso de uso sin él.

**Contraejemplo / control:** Un cassette de tercero no listado en C-731 no hereda una exclusión mecánica mundial.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Shimano C-731: freehub and cassette spline compatibility](https://productinfo.shimano.com/en/compatibility/C-731), [Wolf Tooth GoatLink 11](https://www.wolftoothcomponents.com/products/goatlink-11).

### A06 · CORREGIR · RD: puerto de cuadro, patilla instalada y adaptador

Parches: `MC-06`. Riesgo si se aplica tal cual: `P1`.

Corregir eq entre vocabularios es necesario, pero el fallback por par ausente y FullMount=T-Type crean errores nuevos. La fila Direct mount no puede universalizar RD-M8000/M9000.

**Cambio acotado:** Modelar frame_port UDH por separado de hanger_installed. Añadir Full Mount sin T-Type; evaluar plataforma y restricciones de cuadro por modelo. Mantener conversión de bracket sólo para modelos revisados y con la pieza requerida. Pares sin fila quedan unknown; claw necesita puntera/retención confirmadas.

**Contraejemplo / control:** RED XPLR AXS 13 usa Full Mount y Road Flattop; una bicicleta UDH no queda aprobada si falla la geometría OEM.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [SRAM: Understanding UDH and Full Mount](https://www.sram.com/en/learn/understanding-udh-and-full-mount), [SRAM RED XPLR AXS: chains and T-type](https://support.sram.com/hc/en-us/articles/27120282414747-What-chains-are-compatible-with-SRAM-RED-XPLR-AXS-Can-I-use-a-T-type-chain), [SRAM RED XPLR AXS: frame requirements](https://support.sram.com/hc/en-us/articles/27118530717467-What-kind-of-bike-frame-is-compatible-with-SRAM-RED-XPLR-AXS), [Shimano DM-RD0004-09-ENG, RD-M9000 / RD-M8000](https://si.shimano.com/en/pdfs/dm/RD0004/DM-RD0004-09-ENG.pdf).

### A07 · CORREGIR · Full Mount no es sinónimo de T-Type

Parches: `MC-07`, `MC-07b`. Riesgo si se aplica tal cual: `P1`.

El nuevo token incluye una equivalencia falsa en su nombre y verified=true no tiene alcance de modelo.

**Cambio acotado:** Usar Full Mount (sin patilla) como código de montaje, conservar T-Type/Eagle Transmission y XPLR 13 como plataformas distintas y fuentes por pareja.

**Contraejemplo / control:** Full Mount RED XPLR AXS 13 con cadena Road Flattop.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [SRAM: Understanding UDH and Full Mount](https://www.sram.com/en/learn/understanding-udh-and-full-mount), [SRAM RED XPLR AXS: chains and T-type](https://support.sram.com/hc/en-us/articles/27120282414747-What-chains-are-compatible-with-SRAM-RED-XPLR-AXS-Can-I-use-a-T-type-chain).

### A08 · CORREGIR · FD: E-type, direct mount y configuración 1x

Parches: `MC-08`. Riesgo si se aplica tal cual: `P1`.

El token de cuadro sigue fusionando dos fijaciones; 1x describe configuración y no demuestra ausencia física de montaje. La adaptación inversa de abrazadera a braze-on no está acreditada.

**Cambio acotado:** Separar puerto físico y configuración. Distinguir E-type con/sin placa de pedalier y direct mount por modelo. Aceptar sólo la dirección braze-on a abrazadera respaldada por el adaptador exacto. Unknown para tokens fusionados, otros adaptadores o pares no investigados.

**Contraejemplo / control:** SM-AD91 adapta un desviador braze-on a cuadro apto para abrazadera; no prueba el camino contrario ni que un cuadro configurado 1x carezca de puerto.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Shimano DM-FD0003-06-ENG, front derailleurs](https://si.shimano.com/en/pdfs/dm/FD0003/DM-FD0003-06-ENG.pdf), [Shimano SM-AD91-L clamp band adapter](https://bike.shimano.com/en-UK/products/components/pdp.P-SM-AD91-L.html).

### A09 · CORREGIR · FD: diámetro y suplemento direccional

Parches: `MC-09`. Riesgo si se aplica tal cual: `P1`.

La proyección decimal es razonable; es falso asumir que todo 34.9 trae suplementos 31.8/28.6. Un diámetro distinto no tiene siempre solución por suplemento.

**Cambio acotado:** Proyectar sólo tokens numéricos conocidos a decimal. Separar diámetro base, diámetro objetivo, adaptador homologado e incluido. Clamp menor que tubo mayor falla encaje directo; clamp mayor sólo tiene ruta condicional si el suplemento exacto está documentado. Otro=unknown y No aplica=not_applicable explícito.

**Contraejemplo / control:** Una abrazadera 28.6 no abraza un tubo 34.9; una 34.9 sin información de suplemento no satisface automáticamente 28.6.

**Gate residual:** Capturar manual/ficha íntegros del embalaje antes de automatizar incluido=true. La nota FD-M4100 indexada es evidencia auxiliar, no cierre OEM.

Fuentes: [Shimano DM-FD0003-06-ENG, front derailleurs](https://si.shimano.com/en/pdfs/dm/FD0003/DM-FD0003-06-ENG.pdf), [Shimano SM-AD91-L clamp band adapter](https://bike.shimano.com/en-UK/products/components/pdp.P-SM-AD91-L.html).

### A10 · CORREGIR · Rueda libre: código de rosca y fuente correcta

Parches: `MC-10`. Riesgo si se aplica tal cual: `P2`.

La proyección entre códigos es útil, pero S12 de la propuesta es una página de pastillas de freno y no respalda roscas. ISO/británica/italiana no son el mismo diámetro escrito.

**Cambio acotado:** Reasignar fuente a Sheldon freewheels. Mantener código de estándar separado de medida y tolerancia; tokens legacy 1.37 ISO deben normalizarse como código confirmado, no como medición exacta. Conservar francés/italiano unknown si falta puerto preciso. Limitar exclusión ISO↔M30 al encaje directo conocido.

**Contraejemplo / control:** Sheldon diferencia ISO 1.375x24 y británica 1.370x24; la rosca francesa no es la ISO, pese a cercanía dimensional.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Sheldon Brown: Traditional Thread-on Freewheels](https://www.sheldonbrown.com/freewheels.html).

### A11 · RECHAZAR · Piñón fijo: roscar no satisface la retención

Parches: `MC-11`. Riesgo si se aplica tal cual: `P1`.

La alternativa maza de rueda libre sin rosca izquierda queda en caution y podría pasar un agregador que sólo bloquea incompatible. Falta un requisito necesario.

**Cambio acotado:** Separar rosca derecha del piñón, rosca izquierda de maza, estándar y presencia de contratuerca. La pareja puede pasar el subchequeo de rosca del piñón, pero la ausencia confirmada de retención requerida impide aprobar el montaje fijo; desconocido deja requisitos pendientes. No codificar una adaptación histórica como permiso universal.

**Contraejemplo / control:** Una maza ISO de rueda libre permite roscar un piñón pero carece de la retención izquierda del montaje de pista.

**Gate residual:** Probar que nunca se aprueba ensamblaje fijo con contratuerca requerida ausente, aunque la rosca derecha coincida.

Fuentes: [Sheldon Brown: Fixed Gear Conversions](https://www.sheldonbrown.com/fixed-conversion.html).

### A12 · CORREGIR · Freno de llanta: extremo delantero o trasero explícito

Parches: `MC-12`. Riesgo si se aplica tal cual: `P1`.

Los aliases de anclaje ayudan, pero brake_mount_front|brake_mount_rear no es un campo ni selecciona el extremo montado. Dos pivotes no bastan para identificar U-brake o cantilever.

**Cambio acotado:** Resolver un endpoint por posición elegida. Comparar el código exacto del montaje directo; desconocido para vocabulario incompleto. Evaluar alcance de zapata, posición de pivotes, llanta y tiro en interfaces adicionales.

**Contraejemplo / control:** Un cuadro puede tener montaje delantero y trasero distintos; no debe aprobarse el trasero por el dato delantero.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Sheldon Brown: Brakes with Brazed-on Fittings](https://www.sheldonbrown.com/cantilever-adjustment.html).

### A13 · ACEPTAR · Unificar alias de tiro largo

Parches: `MC-13-22`, `MC-13-23`, `MC-13-fixtures-192-product-lever_pull_required`, `MC-13-fixtures-192-counterpart-lever_cable_pull`, `MC-13-fixtures-193-product-lever_pull_required`, `MC-13-fixtures-194-product-lever_pull_required`. Riesgo si se aplica tal cual: `none`.

Las seis sustituciones cubren todas las ocurrencias exactas de Tiro largo en el contrato congelado.

**Cambio acotado:** Aceptar el alias común; no inferir el tiro de una maneta o freno concreto sólo por un nombre comercial V-brake o disco. La fixture sigue siendo sintética.

**Contraejemplo / control:** El mismo tiro declarado no debe discrepar sólo por usar un rótulo corto frente al canónico.

**Gate residual:** Se verificó cobertura textual 6/6; faltan compilación e interfaz real, no se computan como demostración OEM.

Fuentes: [Sheldon Brown: Brakes with Brazed-on Fittings](https://www.sheldonbrown.com/cantilever-adjustment.html).

### A14C · CORREGIR · Accionamiento del cáliper como requisito parcial

Parches: `MC-14-brake_caliper`. Riesgo si se aplica tal cual: `P1`.

La dirección Hybrid→Mechanical es correcta; compartir Hidráulico no demuestra una pareja maneta/cáliper compatible.

**Cambio acotado:** Conservar la proyección como compatibilidad del puerto de accionamiento solamente. Conectar las reglas de tiro para cable y matriz de modelos/latiguillo/fluido para hidráulico. No traducir un par no modelado en exclusión global.

**Contraejemplo / control:** TRP HY/RD recibe cable mecánico pero tiene un conjunto de manetas de ruta declarado por TRP.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [TRP HY/RD caliper](https://trpcycling.com/products/hy-rd), [SRAM GEN.0000000006520 Rev M: lever/caliper compatibility](https://www.sram.com/globalassets/document-hierarchy/compatibility-map/mtb-and-road-hydraulic-disc-brake-lever-and-caliper-compatibility.pdf).

### A14L · RECHAZAR · Proyección de la maneta está invertida

Parches: `MC-14-brake_lever`. Riesgo si se aplica tal cual: `P1`.

Se copió la tabla del cáliper. En la plantilla brake_lever no existe Hybrid; falta Mechanical→Hybrid, por lo que el caso real cae en incompatible.

**Cambio acotado:** Invertir endpoints: maneta Mechanical puede satisfacer entrada de cáliper Mechanical o Hybrid, sujeto al tiro/modelo; Hydraulic sólo abre evaluación hidráulica específica. Mantener dirección explícita y pruebas recíprocas.

**Contraejemplo / control:** Maneta de ruta mecánica Shimano/SRAM 11 y TRP HY/RD es una combinación declarada; la propuesta la bloquea desde la maneta.

**Gate residual:** Regresión bidireccional de la misma pareja; inspección del conjunto permitido de brake_lever.fields[0].

Fuentes: [TRP HY/RD caliper](https://trpcycling.com/products/hy-rd).

### A15 · ACEPTAR · El cáliper híbrido necesita especificar tiro de cable

Parches: `MC-15a`, `MC-15b`. Riesgo si se aplica tal cual: `none`.

HY/RD demuestra una entrada por cable aunque el accionamiento interno sea hidráulico.

**Cambio acotado:** Aceptar cable_pull_required permitido y requerido para Mechanical o Hybrid. Mantener especificación por modelo.

**Contraejemplo / control:** HY/RD debe declarar el tiro de la entrada por cable.

**Gate residual:** La condición fluid_type del cáliper ya admite Hydraulic o Hybrid en el congelado; no duplicar una corrección innecesaria.

Fuentes: [TRP HY/RD caliper](https://trpcycling.com/products/hy-rd).

### A16 · CORREGIR · Direct mount genérico no se puede borrar sin resolver identidad

Parches: `MC-16`. Riesgo si se aplica tal cual: `P2`.

Eliminar el duplicado es útil sólo si sus referencias y productos corresponden realmente al Shimano Direct mount. Un extensor tiene dos extremos y alcance de modelo.

**Cambio acotado:** Retirar el alias ambiguo de opciones nuevas y conservar legacy. Resolver por fuente a Shimano Direct mount o unknown, actualizar allowed_options y fixtures. No equipararlo a Full Mount ni afirmar que todos los extensores sirven para cuadros direct mount.

**Contraejemplo / control:** GoatLink 11 tiene modelos concretos y excluye cuadros Shimano direct mount nativos.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Wolf Tooth GoatLink 11](https://www.wolftoothcomponents.com/products/goatlink-11), [Shimano DM-RD0004-09-ENG, RD-M9000 / RD-M8000](https://si.shimano.com/en/pdfs/dm/RD0004/DM-RD0004-09-ENG.pdf), [SRAM: Understanding UDH and Full Mount](https://www.sram.com/en/learn/understanding-udh-and-full-mount).

### A17A · RECHAZAR · La plantilla no identifica el puerto de cable

Parches: `MC-17a`. Riesgo si se aplica tal cual: `P1`.

Freno→brake_lever y Cambio→shifter bloquea funciones de productos integrados. template_key no es sustituto del contrato de entrada.

**Cambio acotado:** Crear puertos por función en el modelo de producto: brake_cable_input y shift_cable_input, cada uno con cabeza y requisitos. Seleccionar el puerto real; conservar ambas funciones en manetas integradas.

**Contraejemplo / control:** Shimano ST-R8000-R posee freno de llanta y cambio mecánico de 11: un cable de freno debe poder evaluarse en su puerto de freno aunque la plantilla sea shifter.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Shimano ST-R8000-R Dual Control](https://bike.shimano.com/es-ES/products/components/pdp.P-ST-R8000-R.html).

### A17B · CORREGIR · Cabeza de cable: desactivar sin un campo resoluble

Parches: `MC-17b`. Riesgo si se aplica tal cual: `P2`.

Cambiar mismatch a unknown es correcto; counterpart_field=null no debe llegar como regla ejecutable inválida.

**Cambio acotado:** Mantener la regla deshabilitada con motivo de campo ausente y resultado unknown. Añadir luego requisito por puerto de freno y de cambio, con cabeza canónica/medidas del modelo. No confundir maneta con sólo freno.

**Contraejemplo / control:** ST-R8000 requiere evaluar el cable contra el puerto concreto, no contra la clasificación comercial global.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Shimano ST-R8000-R Dual Control](https://bike.shimano.com/es-ES/products/components/pdp.P-ST-R8000-R.html).

### A18 · CORREGIR · Fluidos permitidos por sistema; sin clases de equivalencia globales

Parches: `MC-18-brake_caliper`, `MC-18-brake_lever`, `MC-18-brake_fluid`. Riesgo si se aplica tal cual: `P1`.

DOT4/DOT5.1 están admitidos en ciertos manuales SRAM, pero esa autorización no se extiende a todos los sistemas DOT. Mineral tampoco es una formulación única.

**Cambio acotado:** Eliminar equivalence_classes globales. Guardar accepted_fluids por modelo/generación y fluido exacto; distinguir DOT5 siliconado. Mismatch documentado de fluidos se bloquea, dato insuficiente queda unknown. Comparar maneta/cáliper mediante matriz propia, no sólo fluido.

**Contraejemplo / control:** Maven exige Maxima; compartir mineral o DOT no aprueba cualquier pareja de maneta/cáliper.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [SRAM S-900 Aero HRD Service Manual](https://www.sram.com/globalassets/document-hierarchy/service-manuals/sram-road/brakes/gen.0000000005452-rev-a-s-900-aero-hrd-service-manual.pdf), [SRAM Maven: correct mineral oil](https://support.sram.com/hc/en-us/articles/23147687539099-Which-is-the-right-brake-fluid-for-my-SRAM-Maven-mineral-oil-brake), [SRAM GEN.0000000006520 Rev M: lever/caliper compatibility](https://www.sram.com/globalassets/document-hierarchy/compatibility-map/mtb-and-road-hydraulic-disc-brake-lever-and-caliper-compatibility.pdf), [SRAM: mixing Maven and Motive levers/calipers](https://support.sram.com/hc/en-us/articles/46533533422363-Can-I-mix-and-match-between-SRAM-Maven-and-Motive-levers-and-calipers).

### A19 · CORREGIR · Rotor: adaptación direccional y límites demostrados

Parches: `MC-19-hub`, `MC-19-rotor`, `MC-19-wheel`. Riesgo si se aplica tal cual: `P1`.

SM-RTAD05 es una ruta real; el inverso no listado no prueba imposibilidad mundial. El mínimo 160 mm no quedó demostrado en el manual leído.

**Cambio acotado:** Separar direct_fit de adapter_path. Usar SM-RTAD05 sólo para rotor seis pernos→maza Center Lock; mantener max 203 mm y exclusión RT86/RT76. No inventar mínimo 160. En ruta inversa, direct_fit=false y adapter_path=unknown, sin aprobación de ensamblaje. Exigir las demás condiciones del kit.

**Contraejemplo / control:** Rotor RT86 de seis pernos no queda aprobado con SM-RTAD05 aunque el montaje y diámetro parezcan servir.

**Gate residual:** Conservar source revision y piezas de retención; si se quiere límite mínimo, obtener OEM que lo declare.

Fuentes: [Park Tool: Disc Brake Rotor Removal and Installation](https://www.parktool.com/en-us/blog/repair-help/disc-brake-rotor-removal-installation), [Shimano DM-MDBR001-06: SM-RTAD05](https://si.shimano.com/en/pdfs/dm/MDBR001/DM-MDBR001.pdf).

### A20 · CORREGIR · Código libre de pastilla no es interfaz mecánica

Parches: `MC-20-brake_caliper`, `MC-20-brake_pad`. Riesgo si se aplica tal cual: `P1`.

Texto distinto puede ser alias; texto igual tampoco demuestra geometría/material/retención. En brake_pad se deja row_match sobre pad_shape_code de texto.

**Cambio acotado:** Desactivar comparación mecánica por texto libre; usar unknown hasta normalizar familia/modelo de pastilla y relación con cáliper. Si se conserva una comparación textual, que sea sólo estructural y no apruebe ni bloquee. Eliminar referencia a exhaustive=true como cierre global.

**Contraejemplo / control:** TRP declara pastillas M525/M515 para HY/RD aunque un vendedor utilice un código distinto.

**Gate residual:** Resolver el tipo del operador antes de compilar; una regla rows no recibe un escalar de código.

Fuentes: [TRP HY/RD caliper](https://trpcycling.com/products/hy-rd).

### A21 · RECHAZAR · Exhaustive por fila es un cierre global inválido

Parches: `MC-21-compatible_caliper_models-43`, `MC-21-compatible_caliper_models-44`, `MC-21-shifter_models_compatible-45`, `MC-21-shifter_models_compatible-46`, `MC-21-derailleur_models_compatible-47`, `MC-21-derailleur_models_compatible-48`, `MC-21-compatible_brake_models-49`, `MC-21-compatible_brake_models-50`, `MC-21-compatible_derailleur_models-51`, `MC-21-compatible_derailleur_models-52`, `MC-21-compatible_frames-53`, `MC-21-compatible_frames-54`. Riesgo si se aplica tal cual: `P1`.

Una bandera por fila no describe el universo cubierto por una tabla, su edición, modelos/generaciones ni condiciones. Una URL no le añade esa información.

**Cambio acotado:** No añadir exhaustive como permiso de negación. Si hace falta tabla cerrada, definir coverage_scope a nivel de relación: fabricante, familias/modelos/generaciones, interfaz/posición, edición, condiciones y regla OEM explícita sobre ausencias. Aplicarla sólo cuando ambas identidades estén dentro de ese ámbito; preferir exclusiones explícitas.

**Contraejemplo / control:** GoatLink 11 puede excluir un montaje concreto dentro de su alcance; eso no permite que cualquier lista parcial de compatible_frames prohíba todos los cuadros no escritos.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Wolf Tooth GoatLink 11](https://www.wolftoothcomponents.com/products/goatlink-11), [SRAM GEN.0000000006520 Rev M: lever/caliper compatibility](https://www.sram.com/globalassets/document-hierarchy/compatibility-map/mtb-and-road-hydraulic-disc-brake-lever-and-caliper-compatibility.pdf).

### A22 · CORREGIR · Mantener unknown sin la excepción exhaustive+URL

Parches: `MC-22-rear_derailleur`, `MC-22-shifter`, `MC-22-brake_small_part`, `MC-22-derailleur_pulley`, `MC-22-derailleur_hanger`. Riesgo si se aplica tal cual: `P1`.

El cambio principal a unknown es correcto; su nota vuelve a permitir la misma negación global del grupo MC-21.

**Cambio acotado:** Aceptar no listado=unknown y quitar la excepción some_row.exhaustive + source_url. Consumir sólo exclusiones expresas o cobertura cerrada validada y acotada a la configuración seleccionada.

**Contraejemplo / control:** Una lista parcial de repuestos o generaciones anteriores no excluye automáticamente un modelo todavía no investigado.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Wolf Tooth GoatLink 11](https://www.wolftoothcomponents.com/products/goatlink-11), [SRAM GEN.0000000006520 Rev M: lever/caliper compatibility](https://www.sram.com/globalassets/document-hierarchy/compatibility-map/mtb-and-road-hydraulic-disc-brake-lever-and-caliper-compatibility.pdf).

### A23 · ACEPTAR · BBRight / OSBB legacy es ambiguo

Parches: `MC-23`. Riesgo si se aplica tal cual: `none`.

El valor combina nombres que no resuelven un único diámetro ni ancho; mapearlo a PF46 afirmaba más de lo observado.

**Cambio acotado:** Aceptar unknown y conservar el texto legado como evidencia. Resolver luego por cuadro/modelo/año y medidas documentadas.

**Contraejemplo / control:** Park distingue BBright Direct Fit bajo PF42 y BBright Press Fit bajo PF46.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [Park Tool: Bottom Bracket Standards and Terminology](https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-standards-and-terminology).

### A24 · CORREGIR · Migración legacy no puede inventar rosca ni variante

Parches: `MC-24`. Riesgo si se aplica tal cual: `P1`.

Separar diccionarios por plantilla es correcto; Rosca fija / contratuerca se convierte indebidamente en ISO 1.29 y varias salidas son prosa condicional, no tokens.

**Cambio acotado:** Mapear sólo códigos inequívocos del campo/plantilla original. Dejar rosca fija genérica y HG genérico en unknown; resolver HG Road11 por modelo/fuente y conservar relación de cuerpos aceptados aparte. Emitir tokens válidos con provenance, nunca frases con salvo o un cassette XD también entra.

**Contraejemplo / control:** Una maza antigua Campagnolo/Phil Wood usa contratuerca 1.32x24; el legacy genérico no puede transformarla en 1.29x24.

**Gate residual:** El diccionario necesita compilación y revisión de valores reales antes de relleno; no aplicar datos por el nombre comercial.

Fuentes: [Sheldon Brown: Fixed Gear Conversions](https://www.sheldonbrown.com/fixed-conversion.html), [Sheldon Brown: Traditional Thread-on Freewheels](https://www.sheldonbrown.com/freewheels.html), [Shimano C-731: freehub and cassette spline compatibility](https://productinfo.shimano.com/en/compatibility/C-731).

### A25 · CORREGIR · Velocidades: pertenencia de la configuración elegida

Parches: `MC-25`. Riesgo si se aplica tal cual: `P1`.

La conversión integer→token debe fijar dirección. Un conjunto de cobertura no se compara por igualdad o subconjunto contra el único número de la bicicleta.

**Cambio acotado:** Evaluar bike.rear_speeds ∈ chain.declared_supported_speeds tras proyección exacta. Coincidencia es sólo ese requisito. Si una fuente excluye el modelo/perfil, bloquear por esa exclusión aunque el número coincida; si sólo falta declaración, unknown/outside_declared_scope y sin aprobación global.

**Contraejemplo / control:** KMC X8 declara [6,7,8]; bicicleta 8 satisface esta condición sin que el conjunto [6,7,8] deba ser subconjunto de [8].

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [KMC X8 Silver BX08NP114](https://www.kmcchain.eu/products/x8-silver), [SRAM RED XPLR AXS: chains and T-type](https://support.sram.com/hc/en-us/articles/27120282414747-What-chains-are-compatible-with-SRAM-RED-XPLR-AXS-Can-I-use-a-T-type-chain).

### A26 · CORREGIR · Conector: anchura no sustituye modelo/perfil

Parches: `MC-26`. Riesgo si se aplica tal cual: `P1`.

Bajar cualquier desajuste a caution y llamar al ancho la comparación física podría aprobar el conector equivocado. Coberturas multivelocidad también necesitan configuración común.

**Cambio acotado:** Usar relación conector→cadena por modelo/perfil y condiciones de reutilización. Velocidad y medidas son filtros parciales; coincidencia de 11/128 o de ancho exterior no basta. Exclusión OEM expresa bloquea; ausencia de evidencia mantiene unknown.

**Contraejemplo / control:** KMC FLATNR declara X FLAT/X SL FLAT y no reutilización; KMC 7/8R nombra X8. No se obtiene esa elección sólo del número de velocidades.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [KMC MissingLink FLATNR Gold CFLATGNRO](https://www.kmcchain.eu/products/missinglink-flatnr-gold), [KMC MissingLink 7/8R EPT Silver 7.3 C78EPTR73](https://www.kmcchain.eu/products/missinglink-7-8r-ept-silver-73), [Park Tool: Chain Replacement, Derailleur Bikes](https://www.parktool.com/en-us/blog/repair-help/chain-replacement-derailleur-bikes), [SRAM RED XPLR AXS: chains and T-type](https://support.sram.com/hc/en-us/articles/27120282414747-What-chains-are-compatible-with-SRAM-RED-XPLR-AXS-Can-I-use-a-T-type-chain).

### A27 · CORREGIR · Verified no debe significar URL registrada

Parches: `MC-27`. Riesgo si se aplica tal cual: `P1`.

La propuesta admite una diferencia esencial pero conserva un nombre equívoco y permite bloquear cualquier diferencia del mismo vocabulario. Además omite como grado válido un manual OEM realmente leído.

**Cambio acotado:** Separar source_registered, contract_validated y domain_assertion_verified por afirmación/pareja/alcance. Incluir manual OEM leído y locator. Un contraste estructural prueba consistencia de datos, no incompatibilidad mecánica universal; política de unknown y adapter_path explícita.

**Contraejemplo / control:** Mismo fluido o mismo vocabulario no implica misma compatibilidad de maneta/cáliper.

**Gate residual:** Recalcular metadata y contadores; mantener evidencia de fixtures fuera de assertions OEM.

Fuentes: [SRAM GEN.0000000006520 Rev M: lever/caliper compatibility](https://www.sram.com/globalassets/document-hierarchy/compatibility-map/mtb-and-road-hydraulic-disc-brake-lever-and-caliper-compatibility.pdf).

### A28 · CORREGIR · Fixture OEM y producto observado son pruebas distintas

Parches: `MC-28`. Riesgo si se aplica tal cual: `P2`.

Es correcto no llamar reales a fixtures compiladas; es demasiado restrictivo exigir un producto y contraparte del catálogo para toda evidencia de un caso físico.

**Cambio acotado:** Registrar origin=synthetic_compiled, source_grounded_oem, catalogue_observed y runtime_verified como ejes separados. Un caso OEM documentado puede ser válido sin estar en stock; una fixture que copia la regla no demuestra dominio.

**Contraejemplo / control:** La combinación HY/RD con entrada por cable está documentada aunque no haya ese cáliper en inventario.

**Gate residual:** Compilar y probar la interfaz direccional y sus estados desconocidos; no equivale a ensamblaje completo.

Fuentes: [TRP HY/RD caliper](https://trpcycling.com/products/hy-rd).

### A29 · CORREGIR · Contador de verificación derivado del nuevo contrato

Parches: `MC-29`. Riesgo si se aplica tal cual: `P2`.

Poner verified_rules=0 mientras los objetos mantienen verified=true deja datos contradictorios.

**Cambio acotado:** Separar conteos de reglas compiladas, fuentes registradas y afirmaciones OEM verificadas. Calcularlos desde los registros después de migrar grading; cero sólo si el conjunto realmente está vacío.

**Contraejemplo / control:** Una nueva cifra no corrige el significado de las banderas en las reglas.

**Gate residual:** Chequeo de consistencia interno; ninguna cifra representa cobertura completa del catálogo.

Fuentes: [SRAM GEN.0000000006520 Rev M: lever/caliper compatibility](https://www.sram.com/globalassets/document-hierarchy/compatibility-map/mtb-and-road-hydraulic-disc-brake-lever-and-caliper-compatibility.pdf).

## Límites de la evidencia y trazabilidad

- Se consultaron Sheldon Brown y Park Tool como fundamentos, además de OEM por modelo. Una fuente general no sustituye un manual del producto.
- `S12` de la propuesta señala un artículo Park Tool de pastillas de freno, pero sus `states` contienen roscas. Esa atribución es incorrecta: MC-10/11 deben usar una fuente que trate roscas. El JSON usa Sheldon freewheels/fixed conversion.
- La tabla SRAM GEN.0000000006520 Rev M se leyó en notas/leyenda textual. La captura web devolvió referencias sin imagen; no se convirtió ninguna celda coloreada en regla. La FAQ Maven/Motive respalda únicamente el alcance que declara.
- La nota FD-M4100-M sobre suplemento S y paquete OTC apareció en fuente primaria indexada; la apertura del handbook v035 dio 404 y la página dinámica no expuso esa tabla. Queda auxiliar y pendiente; no se utiliza para bloqueo o relleno.
- La comprobación de rutas, tipos y aliases es reproducible sobre los dos SHA de abajo. No es una prueba del mundo físico. `text_list` está fuera de las columnas admitidas por `20260906190000_product_spec_structured_rows.sql` (text/token/decimal/integer/boolean/url); su compilador puede traducir la intención, pero no pasar la propuesta directamente.
- Los 18 casos del JSON separan `source_grounded_oem`, `source_grounded_reference` e `inference_guard`; ninguno fue ejecutado ni enlazado aquí con una pareja real del inventario. Un caso OEM puede ser evidencia sin existir en stock.

Entradas congeladas:

- `docs/development/product-specs-research-2026-09-05/all-family-mechanical-corrections-2026-09-06.json` — SHA-256 `e3cc7d120e0f44453b61a64de4d0fb130e5165b55d4c72646f6d3640983a6b0e`.
- `docs/development/product-specs-research-2026-09-05/all-family-compiled-contract-2026-09-06.json` — SHA-256 `785cd11a39011b643e4bcb1422ab805c242f8a7aae0108b399c6aff0c0d78175`.

No se cambió el contrato compilado, la propuesta de Claude, ninguna migración aplicada ni el runtime. Esta adjudicación entrega los cambios que el integrador debe aceptar o reescribir; no es una receta de aplicación automática.
