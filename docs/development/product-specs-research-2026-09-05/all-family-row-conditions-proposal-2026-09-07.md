# Propuesta de condiciones por fila para las 48 definiciones — 2026-09-07

Revisadas las **48 definiciones de filas y sus 94 usos en plantillas** sobre la base congelada indicada. La propuesta añade **14 parches de plantilla sobre 12 definiciones reutilizadas**, sin crear definiciones ni cambiar esquemas de columnas. Las otras 36 quedan separadas en 18 sin una condición local adicional necesaria y 18 con carencias explícitas. Ninguna de esas clasificaciones declara completa la compatibilidad mecánica de una familia.

Base: `f3178bd3c860c421d2365961fe3ff057581d2d038bb999bc59f5f0f959937072`. Casos previos: `3aea8e7a6a7c3d7d91bd24a8135ce91c36674699acfa5c9f283d408dd980cf42`. JSON de propuesta: `94faca196c4572e2faeb8cf748dd9b8843c9c63e531c1f021803a4146bb4f5d0`.

Estado: **propuesta congelada para adjudicación de Codex raíz; no aplicada al catálogo ni a productos**. Todas las puertas globales, incluida `fill_allowed`, siguen en `false`. El agente raíz informó el despliegue de 2200; esta revisión comprobó su archivo y el código local, no ejecutó lecturas ni escrituras SQL, producción o runtime.

## Qué cambia y qué significa

Hay 26 entradas `required_when` de completitud, contando su repetición por plantilla, y una lista `allowed_options`. Las primeras generan `row_required_missing` cuando el requisito es conocido y falta el dato, o `row_prerequisite` cuando el requisito aún es desconocido; ambos son avisos no bloqueantes. No crean filas, no completan valores, no eliminan un dato dependiente ni convierten la falta de evidencia en una incompatibilidad.

| Campo | Regla concreta | Límite conservado |
| --- | --- | --- |
| `rotor_size_recipe`, `tool_capabilities` | Adaptador requerido → identificarlo. | `false` permite conservar un adaptador opcional o evaluado en una exclusión. |
| `seatpost_saddle_configurations` | Estado con kit → pieza de abrazadera. | No infiere rieles admitidos ni inclusión por geometría. |
| `bar_clamp_configurations` | Espaciador o variante → identificación. | Directo no borra información opcional. |
| `tool_bits_included` | Medida para Allen, Torx y cuatro tipos de llaves dimensionadas. | No impone medida a destornilladores, desmontadores, corta cadenas u Otro. |
| `light_member_configurations` | Alimentación externa → entrada declarada; Otra → detalles. | La entrada puede ser cable directo. No deduce carga, capacidad ni conector por marca de motor. |
| `nutrition_facts` | Otro → nombre y unidad; porción → cantidad y unidad de base; servida → referencia. | No transforma sal en sodio ni convierte bases. |
| `co2_cartridge_configurations` | Roscado → designación; presentación → cantidad; compatible declarado → contraparte literal. | El alcance puede ser el modelo o conjunto que el OEM declaró; no se exige inventar uno. |
| `brake_fluid_approvals` | Producto, formulación o especificación OEM del fluido. | Una especificación OEM puede bastar sin marca comercial; no se aprueban equivalencias de aceites. |
| `rotor_adapter_fitments` | Rosca especificada → designación. | Centerlock conserva detalles del anillo; máximo ausente no significa ilimitado. |
| `power_port_profile_configurations` | Tensión fija → tensión; rango → ambos extremos; Otro → nombre del perfil. | No calcula ni exige V/A/W ajenos a lo declarado y no deduce el tipo desde un número. |
| `light.kit_members` | Lista actual de familias, excluyendo sólo `light`. | Único bloqueo nuevo (`row_option`): la tabla de luces físicas es `light_member_configurations`. Otros kits pueden contener luces. |

La última regla detecta una clasificación explícita en el propietario incorrecto. No decide si dos nombres iguales son la misma luz, ni detecta una luz mal clasificada como accesorio, ni convierte fecha de consulta en revisión OEM. Esas ambigüedades siguen abiertas.

## Fuentes y contraejemplos leídos

La política usa Sheldon Brown y Park Tool como fundamento y OEM concreto para ejemplos de alcance. El JSON distingue fuentes locales de representación, fundamentos y documentación del fabricante. No atribuye ningún ejemplo a una existencia de inventario.

- [Park Tool: rotores y adaptadores](https://www.parktool.com/en-us/blog/repair-help/disc-brake-rotor-removal-installation) y [Sheldon Brown: frenos sobre pivotes](https://www.sheldonbrown.com/cantilever-adjustment.html) sustentan la separación de interfaces y revisión del sistema concreto; no se importan límites numéricos históricos como universales.
- [Park Tool: roscas](https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts) muestra por qué no debe condicionarse TPI al diámetro fraccional. [El IB-3](https://www.parktool.com/en-us/product/i-beam-mini-fold-up-with-chain-tool-ib-3) documenta herramientas dimensionadas y un destornillador plano sin medida: conservar la fuente no requiere fabricar esa medida.
- [SRAM Maven](https://support.sram.com/hc/en-us/articles/23147687539099-Which-is-the-right-brake-fluid-for-my-SRAM-Maven-mineral-oil-brake) identifica Maxima Mineral Brake Oil. La fila completa con DOT 5 de la fixture RCF37 sigue siendo un **contracaso mecánico**: el motor de completitud no es el consumidor de aprobación OEM.
- [Ritchey WCS Carbon 1-Bolt clampset](https://ritcheylogic.com/bike/seatposts/wcs-carbon-1-bolt-seatpost-complete-clampset) justifica identificar el kit concreto, conservando su alcance de tija y riel. No permite copiar ese alcance a todas las tijas.
- [Lezyne 16 g, presentación de cinco](https://ride.lezyne.com/products/16g-co2-cartridge) publica roscado sin designación exacta de rosca: RCF31 conserva el dato y el pendiente. El [manual 73725-B1 de las luces HV](https://cdn.shopify.com/s/files/1/0043/1246/5494/files/73725-MANUAL-Y14-MICRO_LITE_PRO-EBIKE-R0B1.pdf?v=1633510382) documenta cableado directo; una inconsistencia AC/DC dentro del manual impide usarlo aquí para aprobar AC.
- [Anker A2663](https://service.anker.com/product-description/a085g000004x2BTAAY/anker-715-charger-nano-ii-65w%3Fref=Home_Page) distingue perfiles fijos de PPS. La corriente PPS contiene un literal mal escrito; el caso conserva sólo los límites legibles y no calcula amperios. [SiS GO, tabla por sabor](https://www.scienceinsport.com/shop-sis/team-sis/go-isotonic-energy-gels-mixed) diferencia la base de porción y sal, utilizadas como ejemplos descriptivos sin conversiones.

## Dictamen por cada campo

“Sin condición adicional” significa que no se encontró un requisito local sustentable adicional a su esquema y contrato actual. “Gap” significa que el cierre requiere otra capacidad o información; no se implementa mediante aproximaciones. Todos mantienen carencias de investigación o de adopción cuando corresponda. Los usos exactos, IDs de definición, columnas revisadas y hashes de cada esquema están en `row_field_audits` del JSON.

| Campo | Dictamen local | Motivo y alcance |
| --- | --- | --- |
| `kit_members` | Condición propuesta | En light, family excluye únicamente light para que las luces físicas se describan en light_member_configurations. Los demás usos conservan toda la lista. |
| `rotor_size_recipe` | Condición propuesta | adapter_required=true exige adapter_model para completar. false permite conservar un adaptador opcional; no resuelve diámetros ni estándares por sí solo. |
| `compatible_caliper_models` | Sin condición adicional | Marca, modelo y fuente ya son obligatorios. Generación/posición/variante y condiciones sólo se agregan cuando el alcance OEM lo necesita; ningún valor genérico habilita todos los modelos. |
| `cog_sequence` | Sin condición adicional | Posición y dientes ya son requeridos, positivos y únicos por posición. Secuencia parcial no permite derivar velocidades o una receta universal. |
| `freehub_bodies_accepted` | Sin condición adicional | Interfaz, separador y fuente ya se conservan en una misma fila; cero es medida válida del separador. No se infiere separador por marca o número de velocidades. |
| `chainring_teeth_rows` | Sin condición adicional | Posición y dientes ya son requeridos y únicos. Esta tabla describe contenido; no autoriza cruces de platos, desviadores o líneas de cadena. |
| `bottom_bracket_required` | Gap explícito | Interfaz de caja y ancho no identifican eje/biela ni montaje. No se fuerza model_or_family mediante una heurística de la caja. |
| `compatible_frames` | Sin condición adicional | Marca, modelo y fuente ya son requeridos. Años y generación necesitan alcance del fabricante; no se deducen de la categoría de bicicleta. |
| `compatible_derailleur_models` | Sin condición adicional | Marca, modelo y fuente ya son requeridos. Sin una matriz OEM no procede otro requisito local universal. |
| `shifter_models_compatible` | Sin condición adicional | Marca, modelo y fuente ya son requeridos; transmisión completa y generaciones siguen siendo relaciones por modelo. |
| `tire_width_range_mm` | Sin condición adicional | Los dos extremos y fuente ya son requeridos, positivos y ordenados. W01–W11 y tablas OEM siguen pendientes; no añade reglas de aro/neumático. |
| `derailleur_models_compatible` | Sin condición adicional | La fila ya obliga marca, modelo y fuente. No se usa cantidad de velocidades para completar un modelo. |
| `tube_fit_rows` | Sin condición adicional | BSD y ambos anchos ya son requeridos y el rango está ordenado. No se inventa equivalencia por medida comercial. |
| `bead_seat_diameters_supported` | Sin condición adicional | La única columna BSD es requerida; no hay dependencia local adicional que expresar. |
| `compatible_brake_models` | Sin condición adicional | Marca, modelo y fuente ya son requeridos en todos sus usos. Fuente y condiciones por modelo siguen necesarias para el dictamen, sin atajos por fluido o marca. |
| `wheel_configurations` | Gap explícito | Posición no permite una prohibición universal de interfaz de tracción en una rueda delantera. Modelos de montaje y alcance de medidas pertenecen a W01–W11/revisión OEM. |
| `pedal_bearing_configurations` | Gap explícito | Cartucho no exige necesariamente código grabado; puede describirse por medidas o repuesto OEM. El esquema actual no tiene ese conjunto de interfaces/medidas alternativo. |
| `seatpost_saddle_configurations` | Condición propuesta | Los dos estados con kit requieren clamp_part. De fábrica permite conservar una pieza documentada. No prohíbe rieles por geometría sin modelo/kit. |
| `eyewear_lens_configurations` | Gap explícito | Ser fotocromática no obliga a publicar simultáneamente VLT y categoría ni permite convertirlas. Los pares opcionales ya ordenan extremos conocidos; completar un extremo desde presencia del otro necesita otro contrato. |
| `fastener_kit_members` | Gap explícito | No se condiciona TPI al dialecto fraccional ni pitch_mm a M. No adivina pieza roscada por member_role. Paso alternativo, referencia de largo y límites opcionales requieren presencia/discriminador. |
| `tool_capabilities` | Condición propuesta | adapter_required=true exige adapter_model para completar; false no excluye información opcional ni supported=false se interpreta como ausencia de herramienta. |
| `tool_bits_included` | Condición propuesta | Pide size en seis interfaces dimensionadas. Conserva Desmontador, Corta cadena, destornilladores y Otro sin imponer medida inexistente en la fuente. |
| `light_member_configurations` | Condición propuesta | Alimentación externa exige su entrada declarada (admite cable directo); Otro exige detalles. No clasifica carga ni batería interna desde el tipo de alimentación. |
| `light_mode_configurations` | Gap explícito | Los modos enlazan una luz por ID, pero no pueden exigir autonomía en función de la alimentación de otra fila. No exige lumens_secondary por patrón ni crea identidad por nombre de modo. |
| `bar_clamp_configurations` | Condición propuesta | Los dos estados con espaciador y variante distinta requieren spacer_or_variant; Directo permite conservarlo. No infiere incluido=true ni compatibilidad por diámetro. |
| `sensor_support_configurations` | Gap explícito | supported y scope ya son requeridos; una declaración válida puede cubrir perfil o familia sin modelo individual. Tipo/transporte no bastan para identidad ni aprobación de todos los sensores. |
| `computer_contents` | Sin condición adicional | Artículo y cantidad requerida describen contenido, no compatibilidad ni número completo de piezas. Interfaz de montaje se conserva si está declarada. |
| `power_port_configurations` | Gap explícito | ID, conector y dirección ya son requeridos; bidireccional necesita alcance del perfil para no confundir entrada/salida. No deduce protocolo ni V/A/W desde USB-C. |
| `power_budget_configurations` | Sin condición adicional | Configuración, puerto enlazado y potencia son requeridos. No suma filas parciales ni mezcla configuraciones para obtener capacidad agregada. |
| `nutrition_facts` | Condición propuesta | Otro exige nombre/unidad; porciones declarada/servida exigen cantidad/unidad de base; servida además referencia de porción o receta. No convierte sal a sodio ni bases entre sí. |
| `conflicting_claims` | Sin condición adicional | Campo, valor y tipo de fuente ya se conservan como afirmaciones. Fecha más reciente no elige ganador ni versión OEM; se mantiene el conflicto. |
| `security_rating_configurations` | Gap explícito | Emisor y nivel ya son requeridos. Un score de fabricante no se convierte en certificación ni existe traducción universal entre escalas. Falta alcance estructurado de certificación para reglas más fuertes. |
| `rack_top_interface` | Gap explícito | Interfaz libre y condiciones no son discriminadores de required_part. No se identifica plataforma o generación por coincidencia de texto. |
| `rack_mount_configurations` | Gap explícito | El punto de montaje no determina rangos universales. No reutiliza requirement como descripción obligatoria de Otro; extremos y método dependen del sistema. |
| `bag_rack_interface` | Gap explícito | Interfaz libre, generación y parte requerida necesitan alcance estructurado; no se activa un requisito por nombre de plataforma. |
| `auxiliary_part_requirements` | Sin condición adicional | Configuración y pieza ya son requeridas; incluida y requerida son conceptos distintos. No fuerza included ni elimina accesorios opcionales. |
| `bag_member_configurations` | Gap explícito | Dimensiones, volumen y referencia de medición son observaciones independientes. Sin presence no se exige measurement_reference sólo cuando corresponde; no calcula volumen ni total de un kit. |
| `co2_cartridge_configurations` | Condición propuesta | Roscado exige designación para completar; presentación exige cantidad incluida; compatible declarado exige contraparte literal (modelo o alcance OEM expreso). No inventa rosca ni hereda identidad del nombre. |
| `certification_configurations` | Gap explícito | Norma literal y tipo de evidencia ya son requeridos. No añade reglas de nivel/región por una shortlist de normas sin edición/modelo/certificado exactos; nunca transforma un claim en certificación válida. |
| `brake_fluid_approvals` | Condición propuesta | Cada aprobación pide producto/formulación o especificación OEM literal además de la clase y sistema. No exige una marca comercial cuando el OEM sólo prescribe una especificación. |
| `brake_hydraulic_connections` | Gap explícito | Un extremo podría documentarse por fitting_model o connection_spec; exigir ambos sería excesivo. El enlace circuit_id puede usar row_coherence pero no está configurado aquí. |
| `brake_bleed_ports` | Gap explícito | Necesita conservar las alternativas de interfaz de conexión, herramienta o procedimiento OEM. No inventa rosca de purga, adaptador ni fluido por marca. |
| `rim_brake_mount_fitments` | Gap explícito | Montaje, modelo, posición y fuente son requeridos. Rangos opcionales ya ordenados; un extremo faltante y adaptación exacta siguen pendientes. |
| `brake_assembly_configurations` | Gap explícito | No obliga todas las piezas: hay presentaciones parciales y sistemas híbridos. Faltan discriminadores de contenido y presencia para requerir sólo identidades realmente incluidas. |
| `brake_adapter_fitments` | Sin condición adicional | Montajes, posición, rotor, adaptador y fuente ya son requeridos. Máximo de diámetro y compatibilidad son declaraciones del conjunto OEM, no ecuaciones generales del adaptador. |
| `rotor_adapter_fitments` | Condición propuesta | Rosca especificada exige hub_thread_spec para completar. No prohíbe información de rosca de anillo en Centerlock; máximo ausente nunca significa ilimitado. |
| `control_cable_end_options` | Sin condición adicional | Extremo, propósito, perfil y fuente son requeridos. No deduce tiraje o modelo de maneta desde la cabeza, diámetro o longitud. |
| `power_port_profile_configurations` | Condición propuesta | Tensión fija exige tensión; rango exige ambos extremos; Otro exige nombre de perfil. No pide ni calcula A/W y no deriva profile_kind desde el número. |

## Carencias que quedan abiertas

- **G01 — Presencia y alternativas de columnas** (`engine_gap`): No existe exists/is_known ni al-menos-uno de columnas. No simular presencia con >0 o texto inferido. Las exigencias mutuas entre extremos también forman ciclos prohibidos.
- **G02 — Igualdad booleana condicional sin ocultar datos** (`engine_gap`): allowed_options sólo estrecha tokens; allowed_when sobre un booleano prohíbe cualquier valor conocido, incluido el que se quería exigir. Con kit incluido y included=false requiere aserción condicional, no borrado.
- **G03 — Compatibilidad por modelo, generación, instalación y fuente** (`coverage_gap`): Un documento de filas bien formado no prueba compatibilidad. Las relaciones schema2 todavía requieren integración y matrices OEM con alcance, exclusiones y condiciones; nunca deducir modelo desde marca, velocidades o nombre libre.
- **G04 — Predicados sobre un miembro enlazado** (`engine_gap`): row_conditions sólo lee columnas de la fila actual. row_coherence puede verificar IDs de enlace, pero no proyecta battery_kind, direction o generación del miembro para predicados locales.
- **G05 — Un ID de fila no demuestra una identidad física o revisión OEM** (`identity_gap`): Excluir family=light en kit_members cierra el segundo dueño explícito. Una luz mal rotulada como accesorio, dos filas con igual nombre o dos revisiones contradictorias aún necesitan resolución de identidad/evidencia; fecha de consulta no es revisión.
- **G06 — Faltan discriminadores estructurados para exigir campos con seguridad** (`metadata_gap`): Texto libre como configuration, member_kind, interface o conditions no se puede interpretar como hechos estructurados. Faltan algunos alcances de medición/parte incluida/certificación que distingan cuándo un dato es necesario.
- **G07 — Fuentes y datos desconocidos no equivalen a aprobación** (`evidence_gap`): No exigir source_url duplicado donde row.sources ya documenta la evidencia; el motor local no pregunta por fuentes del sobre. Un valor desconocido o faltante debe seguir pendiente, nunca rellenarse desde el ejemplo OEM.
- **G08 — Alcance de la tabla puede ser más estrecho que el dominio de sus filas** (`parent_contract_gap`): nutrition_facts sólo aplica a preparation_kind=Envasado; Por porción servida representa una porción declarada del envasado, no habilita productos preparados en barra. bar_clamp_configurations está limitado a Soporte de teléfono + medidas discretas. Este addendum no amplía esas guardas.
- **G09 — Completo para la fila no equivale a catálogo investigado** (`consumer_gap`): No se derivan modes_count, ports_count, lúmenes, potencia agregada, cantidad comercial o contenido completo de filas parciales. Los requisitos nuevos producen avisos de completitud, no bloqueo de observaciones válidas incompletas.

No se utiliza `allowed_when` para simular una igualdad condicional de booleanos: borraría o prohibiría también un dato válido. No se sustituye presencia por `>0`, ni se incorporan predicados sobre una fila enlazada. `row_coherence` ya dispone de enlaces por ID; configurar un enlace aún faltante es una tarea de metadatos distinta, mientras que consultar atributos de ese miembro requiere una capacidad adicional.

## Prueba ejecutable y delta de los casos

**242/242 pruebas Flutter/Dart pasan** en el probe propio: 105 contratos completos, 48 fixtures nuevas, 84 casos previos, cuatro negativas de metadatos y una comprobación de cobertura/preimágenes. El validador Python también acepta las 14 preimágenes y los 105 contratos y rechaza los cuatro contratos no soportados. No se ejecutó SQL para este paquete: la paridad SQL/Dart de la carga integrada corresponde al gate de integración.

La primera comparación de los 84 casos previos detectó un único delta esperado: `light_kit_member_inside_kit_members_undetectable` pasa de cero bloqueos a `row_option:kit_members`. El JSON contiene `case_overrides` y la preimagen completa bajo `case_override_preimages`; conserva el ID histórico y corrige la nota para no declarar resuelta la identidad física. Los otros 83 mantienen su conjunto de bloqueos.

Las fixtures comprueban unknown, false y accesorios opcionales, aislamiento entre filas, completitud sin inferencias, medidas exactas como texto y preservación del borrador. Incluyen carencias conocidas que **no** deben interpretarse como aprobaciones: Maven + DOT 5, incluido contradictorio, miembros con igual nombre y falta de alcance eléctrico. El rango invertido es un rechazo de forma del esquema previo, no una nueva regla física.

Consumo comprobado en el código local: [SpecTemplate.rowConditions](/Users/Claudio/Dev/bikeshop-erp/lib/modules/inventory/services/spec_engine_service.dart:192) construye metadatos de campos activos; [validateProductSpecDraft](/Users/Claudio/Dev/bikeshop-erp/lib/modules/inventory/models/product_spec_contract.dart:343) conserva código, fila, columna y severidad; el [formulario](/Users/Claudio/Dev/bikeshop-erp/lib/modules/inventory/pages/product_form_page.dart:7872) pasa las condiciones al editor de filas junto a las referencias. Estos son consumidores de representación, no un dictamen de compatibilidad física.

Reproducción sin DB:

```sh
fvm flutter test --no-pub .tmp/product-spec-catalog/row-condition-family-review-probe.dart --reporter expanded
```

Probe SHA256: `e1312559cfa2695097c28a300a3551dd800e2bca856046864bb0b7252925ecbe`. Log SHA256: `24a4db39fc9c0523572b3d2aac7163d506f67c59c4a43dbf7118a21f33531bc9`. La migración 2200 revisada tiene SHA256 `6d18c2e1e985d73ca935987a5615bf6365e8a32e26720a5068e78bbb878f16a7`. Los demás pins están en `verification.checked_implementation_sha256` del JSON.

Antes de adoptar: adjudicar los 14 parches y el override de caso, integrar con preimágenes exactas, comprobar paridad SQL/Dart y publicación de metadatos frente a referencias/datos existentes, y mantener las puertas globales cerradas hasta sanear y revisar productos/fuentes. Este paquete no contiene un aplicador, no cambia productos y no autoriza llenado.
