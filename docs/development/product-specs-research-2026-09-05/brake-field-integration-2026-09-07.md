# Integración local del paquete de frenos

2026-09-07. El catálogo combinado tiene 105 plantillas, 680 definiciones,
47 campos de filas y 1.185 usos de campos. Pasan las 105 guardas de metadata
y 71 casos de representación en una transacción local terminada en ROLLBACK.
Hechos e identidades quedan idénticos. Las 82 pruebas Dart del paquete
independiente también pasan sobre el resultado integrado.

`compile_product_spec_mechanical_addenda.py` reproduce primero A/B y sus
correcciones y luego aplica `brake-family-root-decisions-2026-09-07.json`:
73 aceptaciones, 13 correcciones y un rechazo. El rechazo es el rango de
alcance de freno de llanta ya incorporado, sin forzar su preimagen anterior.
Doce retiros conservan historia y desactivan explícitamente la edición;
la otra corrección separa la fijación de la zapata del accionamiento. Que
MAGURA HS tenga una interfaz específica no demuestra que todo sistema
hidráulico deba excluir cualquier poste.

Los resultados locales son `all-family-reviewed-fields-integrated-2026-09-07.json`
y `all-family-representation-cases-integrated-2026-09-07.json`. El catálogo A/B
anterior permanece congelado para que las revisiones se reproduzcan.
Evidencias: `.tmp/db/spec-mechanical-addenda-trial.log` y
`.tmp/product-spec-catalog/brake-packet-root-integration.log`.

Los 13 claims schema2 y sus 65 casos permanecen candidatos separados. Sus
pruebas demuestran la ejecución de ese lenguaje, no la investigación de
todos los productos ni su integración con el componente instalado. La
publicación requiere cerrar sus fuentes/versiones y la proyección por
rueda, circuito y contraparte. Continúan los gates EG01–EG10 según su
alcance, la investigación de genéricos y el diagnóstico de unidades null.

No se publicaron estas plantillas, no se asignaron productos y el llenado
continúa en cero. La corrección del consumidor fluido/familia→disco se
documenta aparte en `brake-consumer-integration-2026-09-07.md`.
