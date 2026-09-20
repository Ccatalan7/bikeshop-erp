-- Verifier: fails until every Chilean-Spanish label and helper is live.
select 1/(case when (select count(*) from public.spec_definitions where tenant_id is null and key='spec_evidence_source' and label='Fuente del dato')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_old_mm' and label='Ancho de la maza entre apoyos (OLD)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_hole_count' and label='Cantidad de rayos / hoyos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_spoke_head_interface' and label='Tipo de rayo (con codo o recto)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bearing_system' and label='Tipo de rodamiento')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rotor_mount_type' and label='Fijación del disco')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_drive_receiver_present' and label='Tiene montaje para piñón')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_drive_receiver_kind' and label='Sistema de montaje del piñón')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_drive_receiver_reference' and label='Modelo exacto del núcleo o la rosca')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='flange_pcd_left_mm' and label='Diámetro del círculo de hoyos izquierdo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='flange_pcd_right_mm' and label='Diámetro del círculo de hoyos derecho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='center_to_flange_left_mm' and label='Del centro al círculo de hoyos izquierdo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='center_to_flange_right_mm' and label='Del centro al círculo de hoyos derecho')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_flange_to_flange_mm' and label='Distancia entre los círculos de hoyos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_hole_diameter_mm' and label='Diámetro de cada hoyo para rayo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_axle_diameter_datum' and label='Punto donde se mide el diámetro del eje')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_supplied_thru_axle_reference' and label='Modelo del eje pasante incluido')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hub_package_pieces' and label='Mazas de este juego')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_backsweep_deg' and label='Ángulo del manubrio hacia atrás')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_drop_mm' and label='Caída del manubrio')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_reach_mm' and label='Alcance del manubrio')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_rise_mm' and label='Elevación del manubrio')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_upsweep_deg' and label='Ángulo del manubrio hacia arriba')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_width_drops_mm' and label='Ancho del manubrio en la parte baja')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bar_width_hoods_mm' and label='Ancho del manubrio en las manillas')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fork_offset_mm' and label='Avance de la horquilla')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='reach_adjust' and label='Ajuste de distancia de la manilla')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='stem_kind' and label='Tipo de tee / potencia')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='dropper_actuation' and label='Accionamiento del tubo telescópico')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_saddle_length_max_mm' and label='Para asiento de largo hasta')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_saddle_length_min_mm' and label='Para asiento de largo desde')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='fits_saddle_width_max_mm' and label='Para asiento de ancho hasta')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_kind' and label='Tipo de tubo de asiento')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_offset_mm' and label='Retroceso del tubo de asiento')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='seatpost_saddle_configurations' and label='Anclajes de asiento documentados')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_bcd_mm' and label='Diámetro del círculo de pernos (BCD)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_bolt_count' and label='Cantidad de pernos del plato')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_direct_mount_generation' and label='Sistema de montaje directo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_mount_type' and label='Fijación del plato')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_mounting' and label='Fijación de los platos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='chainring_offset_mm' and label='Desplazamiento lateral del plato')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='derailleur_cage_length' and label='Largo de la pata del cambio')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='derailleur_clutch' and label='Con estabilizador de cadena (clutch)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='drivetrain_mode' and label='Tipo de transmisión')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='drivetrain_platform' and label='Familia de transmisión')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='drivetrain_primary_ecosystem' and label='Sistema principal de transmisión')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='freehub_type' and label='Tipo de núcleo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='front_derailleur_swing' and label='Movimiento del desviador delantero')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hanger_derailleur_interface' and label='Unión con el cambio trasero')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hanger_frame_interface' and label='Unión con el cuadro')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='hanger_interface' and label='Tipo de pata / postiza')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='quick_link_included' and label='Incluye conector rápido')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rear_derailleur_hanger_interface' and label='Unión con la pata de cambio')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rear_derailleur_mount_type' and label='Fijación del cambio trasero')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_asymmetric_offset_mm' and label='Desplazamiento lateral del aro')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_bead_profile' and label='Borde del aro (con o sin gancho)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_erd_datum' and label='Cómo se midió el diámetro efectivo del aro (ERD)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_erd_mm' and label='Diámetro efectivo del aro (ERD)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_etrto' and label='Medida normalizada del aro (ETRTO)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='rim_tubeless_ready' and label='Apto para usar sin cámara (Tubeless Ready)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_bend_type' and label='Tipo de rayo (con codo o recto)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_head_interface' and label='Tipo de rayo (con codo o recto)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='spoke_holes' and label='Cantidad de hoyos para rayos')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tire_etrto' and label='Medida normalizada del neumático (ETRTO)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='tire_tubeless_ready' and label='Apto para usar sin cámara (Tubeless Ready)')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='cable_pull_required' and label='Recorrido de cable que necesita')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='caliper_mount_interface' and label='Fijación del cáliper')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='front_derailleur_cable_pull' and label='Entrada del cable al desviador')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lever_cable_pull' and label='Recorrido de cable de la manilla')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='lockout' and label='Con bloqueo')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='mount_standard' and label='Sistema de fijación')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bb_declared_systems' and label='Sistemas de motor declarados')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bb_shell_interface' and label='Fijación en la caja de motor')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bb_thread_standard' and label='Rosca de la caja de motor')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bottom_bracket_family' and label='Familia de motor / caja de motor')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bottom_bracket_included' and label='Incluye motor / caja de motor')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='bottom_bracket_required' and label='Motor / caja de motor requerido')=1
 and (select count(*) from public.spec_definitions where tenant_id is null and key='crankset_bottom_bracket_supplied' and label='Motor / caja de motor incluido')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='bottom_bracket' and name='Motor / caja de motor' and description='Conjunto que permite girar el volante dentro del cuadro; se confirma por caja, rosca, eje y sistema de biela.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='brake_caliper' and name='Cáliper de freno' and description='Cálipers completos, hidráulicos o mecánicos.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='cassette' and name='Cassette' and description='Conjunto de piñones que se instala sobre un núcleo; se confirma por sistema de núcleo, velocidades y rango.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='cassette_spacer' and name='Espaciador de cassette' and description='Anillo espaciador para instalar un cassette sobre un núcleo.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='chainring' and name='Plato / corona' and description='Plato del volante; se confirma por dientes, fijación, velocidades y desplazamiento lateral.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='crank_arm' and name='Biela suelta' and description='Una biela individual; se confirma por lado, largo, unión al eje y rosca del pedal.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='crankset' and name='Volante / juego de bielas' and description='Conjunto de bielas y platos; se confirma por platos, eje, motor y velocidades.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='derailleur_hanger' and name='Pata / postiza de cambio' and description='Pieza reemplazable que une el cambio trasero al cuadro; se confirma por cuadro, modelo y fijación.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='derailleur_hanger_extender' and name='Extensor de pata de cambio' and description='Extensor que cambia la posición del cambio trasero.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='freewheel' and name='Piñón roscado / rueda libre' and description='Conjunto de piñones que se enrosca directamente en la maza; se confirma por rosca y velocidades.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and name='Maza' and description='Mazas delanteras, traseras o juegos, con ancho, eje, rayos, freno y montaje del piñón.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='rim' and name='Aro / llanta' and description='Aro de rueda; se confirma por diámetro, ancho, hoyos para rayos y agujero de válvula.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='rim_strip' and name='Fondo de aro / cubre cámara' and description='Cinta o banda que cubre los hoyos interiores del aro.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='saddle' and name='Asiento' and description='Asiento de bicicleta.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='saddle_cover' and name='Funda para asiento' and description='Funda que cubre el asiento.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='seatpost' and name='Tubo de asiento' and description='Tubo que une el asiento al cuadro, fijo o telescópico.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='spoke' and name='Rayo' and description='Rayo de rueda; se confirma por largo, calibre, rosca y tipo de entrada a la maza.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='tire' and name='Neumático' and description='Neumático de bicicleta; se confirma por aro, ancho, construcción y uso con o sin cámara.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='bottom_bracket' and form_contract->'helpers'->>'spindle_interface'='Sistema de eje que trae este motor. Si no trae eje, la unión que acepta se declara por separado.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='brake_caliper' and form_contract->'helpers'->>'cable_pull_required'='Recorrido de cable que este cáliper necesita de la manilla. No se deduce de la marca.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='brake_caliper' and form_contract->'helpers'->>'caliper_mount_interface'='Fijación física de este cáliper. Conserva el nombre exacto del estándar: Post Mount, Flat Mount o IS.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='brake_caliper' and form_contract->'helpers'->>'brake_conversion_location'='En un cáliper híbrido, la conversión de cable a presión ocurre dentro de la misma pieza. Un convertidor externo es otra pieza.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='chainring' and form_contract->'helpers'->>'chainring_direct_mount_generation'='Sistema exacto de montaje directo que publica el fabricante. La frase direct mount por sí sola no identifica piezas intercambiables.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='chainring' and form_contract->'helpers'->>'chainring_offset_declarations'='Desplazamiento lateral medido desde la referencia que indica el fabricante. No es la línea de cadena del conjunto armado.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='crankset' and form_contract->'helpers'->>'chainring_mounting'='Indica si los platos se sacan con pernos, van remachados o usan montaje directo al brazo.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='crankset' and form_contract->'helpers'->>'bottom_bracket_included'='Que el volante necesite un motor determinado y que ese motor venga en la caja son dos respuestas distintas.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='crankset' and form_contract->'helpers'->>'bottom_bracket_required'='Una fila por combinación documentada de caja, motor, largo de eje y línea de cadena.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='crankset' and form_contract->'helpers'->>'crankset_bottom_bracket_supplied'='Identifica el motor o caja de motor que viene en el envase. Si no viene incluido, déjalo vacío.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='front_derailleur' and form_contract->'helpers'->>'front_derailleur_swing'='Indica dónde pivota la jaula. No es la ruta del cable: top swing y top pull describen cosas distintas.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='front_derailleur' and form_contract->'helpers'->>'front_derailleur_cable_pull'='Indica desde dónde entra el cable: por arriba, por abajo o por ambos lados. No describe el pivote de la jaula.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='rear_derailleur' and form_contract->'helpers'->>'rear_derailleur_mount_type'='Cómo se fija este cambio al cuadro: a la pata, por montaje directo o mediante una uña sujeta al eje.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='rear_derailleur' and form_contract->'helpers'->>'rear_derailleur_supplied_mount_adapter'='Una uña es una pieza incluida que se sostiene con la tuerca del eje o el cierre rápido. No cambia la fijación que ofrece el cuadro.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='rim' and form_contract->'helpers'->>'rim_erd_datum'='Indica desde qué punto midió el fabricante el diámetro efectivo del aro (ERD), incluyendo niple o arandela cuando corresponda. No es el diámetro de apoyo del neumático.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='seatpost' and form_contract->'helpers'->>'seatpost_kind'='Tubo de asiento completo. Un adaptador reductor tiene su propia ficha.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='spoke' and form_contract->'helpers'->>'spoke_head_elbow_angle_deg'='Ángulo del codo según el dibujo del fabricante. No se supone que todos los rayos con codo midan 90°.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='tire' and form_contract->'helpers'->>'tire_tubeless_ready'='Apto para usar sin cámara sólo con un aro, válvula y sellante compatibles. En la caja suele aparecer como Tubeless Ready.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_package_position'='Qué viene en la caja: una maza delantera, una trasera, o el juego de las dos. Si es el juego, cada maza va en su propia fila más abajo y no se llena un solo ancho ni una sola perforación.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'spec_evidence_source'='Pega el link de la página del fabricante, o escribe «manual» o «caja» si lo leíste ahí. Sin fuente, los demás datos quedan como no confirmados.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_old_mm'='Ancho exterior de la maza, medido entre las dos caras que apoyan en el cuadro o la horquilla. En catálogos aparece como OLD. Valores comunes: 100 mm delante; 135 mm atrás con cierre rápido; 142 o 148 mm con eje pasante.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'spoke_hole_count'='Cantidad total de rayos que lleva la maza. Cuenta los hoyos de ambos lados: una maza de 32H tiene 32 en total, normalmente 16 por lado.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_axle_mount_kind'='Cierre rápido: eje hueco con palanca (9 o 10 mm). Eje pasante: eje grueso de 12 o 15 mm que se enrosca al cuadro. Con tuercas: eje macizo con una tuerca a cada lado.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_spoke_head_interface'='Con codo es el rayo tradicional: la cabeza doblada entra por un hoyo lateral de la maza. Recto entra sin codo. En fichas del fabricante pueden aparecer como J-bend y straight pull.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_rotor_mount_present'='Sí si la maza trae una fijación para disco de freno. No si sólo sirve para freno de llanta.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'rotor_mount_type'='6 pernos: el disco se atornilla con seis pernos. Center Lock: el disco entra en una estría y se asegura con un anillo.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'bearing_system'='Sellados: rodamientos de cartucho, se cambian enteros. Bolas sueltas: bolitas con conos y tazas, se ajustan y se engrasan.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_drive_receiver_present'='Sólo para mazas traseras. Sí si trae núcleo para cassette, hilo para piñón roscado u otro montaje documentado para el piñón.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_drive_receiver_kind'='Cómo se instala el piñón en esta maza trasera: sobre un núcleo estriado, en una rosca o mediante el sistema específico del fabricante.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_drive_receiver_reference'='Nombre exacto publicado por el fabricante, por ejemplo HG 8-11v, Micro Spline, XD o la medida de la rosca.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'flange_pcd_left_mm'='Diámetro del círculo que forman los hoyos del lado izquierdo. Se mide desde el centro de un hoyo hasta el centro del hoyo opuesto. En catálogos puede aparecer como PCD.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'flange_pcd_right_mm'='Diámetro del círculo que forman los hoyos del lado derecho. Se mide desde el centro de un hoyo hasta el centro del hoyo opuesto. En catálogos puede aparecer como PCD.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'center_to_flange_left_mm'='Desde el centro de la maza hasta el plano donde están los hoyos del lado izquierdo. Si el fabricante mide desde el apoyo exterior, convierte la medida antes de escribirla.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'center_to_flange_right_mm'='Desde el centro de la maza hasta el plano donde están los hoyos del lado derecho, medido igual que el lado izquierdo.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_flange_to_flange_mm'='Distancia entre los dos planos donde están los hoyos de los rayos. Debe coincidir con la suma de las dos distancias medidas desde el centro.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'spoke_hole_diameter_mm'='Diámetro de un hoyo lateral por donde entra el rayo. Valores comunes: 2,5 o 2,6 mm.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_axle_diameter_datum'='Indica en qué parte se midió: en la zona que entra al cuadro o la horquilla, dentro de la maza u otro punto publicado por el fabricante. El perno fino del cierre rápido no es el diámetro del eje.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_axle_diameter_mm'='Grosor del eje en el punto que indicaste arriba. Cierre rápido: 9 o 10 mm. Pasante: 12 o 15 mm.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_thru_axle_supplied'='Sí sólo si el eje pasante viene en la caja.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_supplied_thru_axle_reference'='El código del eje que viene. Su rosca y su largo son del eje y del cuadro, no de la maza.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_package_pieces'='Sólo lo que viene en la caja: una fila por maza. No es la lista de variantes del fabricante ni una rueda armada.')=1
 and (select count(*) from public.spec_templates where tenant_id is null and key='hub' and form_contract->'helpers'->>'hub_package_piece_count'='Cuántas mazas trae el juego (normalmente dos: delantera y trasera). Confírmalo con la fuente, no por el título.')=1 then 1 else 0 end);
