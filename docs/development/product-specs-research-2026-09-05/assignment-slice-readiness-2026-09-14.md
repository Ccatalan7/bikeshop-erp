# Primera tanda de asignaciones faltantes

Se revisaron individualmente 54 productos físicos sin plantilla: 31 candados,
16 luces y 7 cintas de manillar. En cada uno coinciden la clase nombrada por el
producto y su categoría; eso sustenta sólo la asignación de familia. No confirma
modelo, variante, medidas, contenido, certificaciones ni compatibilidad.

Las 54 lecturas autenticadas v2 confirmaron nombre, SKU y categoría actuales;
cero observaciones técnicas, referencias, perfiles e historial de piezas.
Ninguno es un servicio ni un set de stock. Los siete productos de la categoría
«Protectores» se excluyeron: mezcla protección de mochila, cuadro, transmisión
y neumáticos. No se asigna una ficha a toda esa categoría por su rótulo.

Preimágenes, propuesta y ensayo SQL privados:
`.tmp/product-spec-catalog/assignment-slice-20260914/`.
Cada decisión conserva actor, producto, revisión, timestamp, hash de la lectura
del servidor, hash del archivo y plantilla/versiones propuestas. Las lecturas
caducan como preimagen si cambia el producto; no se refrescan y aplican en silencio.

## Implementación reutilizada y comprobaciones

`assign_product_spec_template_v1` ya existe en producción. Se comprobó su cuerpo
vigente y se ejecutó su contrato local: **73 casos aprobados**, con conservación
de columnas comerciales, identidad, observaciones, fuentes y aislamiento entre
tenants. No hace falta crear un segundo escritor de asignaciones.

`scripts/inventory/prepare_product_spec_assignments.py` prepara únicamente un
ensayo que termina en rollback. Usa esa RPC, bloquea los productos/plantillas
exactos, exige la preimagen íntegra y la revisión de la plantilla, y comprueba
que sólo cambien asignación, revisión y timestamp. No emite modo commit ni
transporta solicitudes de escritura a producción. Sus archivos son privados.

Las cuatro pruebas del SQL generado ejecutaron RPCs locales reales: asignación
con conservación y rollback; rechazo si cambia precio; rechazo si cambia la
revisión de plantilla; rechazo si la clave de familia no corresponde al destino.
La razón con comillas, barras y texto `COMMIT` permaneció como dato. La primera
ejecución detectó precedencia ambigua entre extracción JSON y resta de claves;
se corrigió con paréntesis antes de aprobar esos cuatro recorridos.

Ocho pruebas del preparador cubren hash de archivo, actor, producto duplicado,
rechazo de cambios técnicos/de identidad, perfiles preexistentes, revisión
booleana y exclusión de servicios/sets. Evidencia:
`.tmp/db/assignment-existing-contract-20260914.log`,
`.tmp/db/assignment-rehearsal-tests-20260914/`,
`.tmp/product-spec-catalog/assignment-slice-20260914/preparation-tests.log`.

**Aplicadas y verificadas el 14 de septiembre, 23:51 UTC: 54 asignaciones;
productos rellenados: 0.** Root revisó los nombres/categorías, los contratos y
la conservación de datos de esta tanda, dentro del saneamiento ya autorizado.
La revisión de Claude no se completó por cuota; no se atribuye su aprobación a
esta tanda. La nueva habilitación de perfiles continúa separada y sin aplicar.

Se verificó nuevamente el respaldo formato 2 a las 23:45 UTC. El SQL exacto
revisado, derivado del ensayo ya probado, añadió sólo la fijación del cuerpo de
la RPC y el commit final. Se ejecutó mediante el wrapper de escritura guardada,
con el actor de la sesión Debug verificado previamente contra Auth, comprobación
de tenant y rol `authenticated` dentro de la transacción. Esto fue una operación
SQL controlada; no se presenta como transporte HTTP autenticado de escritura ni
como el futuro aplicador de llenado. No se modificó el lector autenticado.

La transacción confirmó 54 asignaciones y COMMIT. Las 54 lecturas posteriores
por la API con la sesión real verificaron destino, revisión incrementada,
conservación de todas las columnas de producto ajenas a asignación/revisión/fecha,
observaciones, referencias e historial de piezas. Se recuperaron 54 recibos
persistidos y coincidieron actor, producto, destino, revisiones y motivo.

- Propuesta SHA-256: `de4ca2713f86c5f64aedcd06cb5c49ddd4052b1e20895a0db62ba7335d7943a7`.
- Aplicación SHA-256: `8bcc68bec35e866c25071854138cf6d375a9d7007ea9084659a90cdc0effd37d`.
- Evidencia privada: `root-review.json`, `application.log`,
  `application-readback.json`, `receipts-and-counts.json` y `after/`, bajo la
  carpeta de la tanda.
- Conteo fresco a las 23:53 UTC: 1.673 registros, 59 servicios, 922 productos
  físicos con plantilla y 692 sin ella. La clasificación mecánica global no se
  considera cerrada por esta mejora de cobertura.

Recuperación: si la respuesta de una aplicación resulta incierta, consultar los
mismos 54 `operation_key` y recibos; no generar otra tanda ni refrescar preimágenes
para repetir a ciegas. Una reversión debe comprobar el estado posterior de cada
producto y preservar cualquier cambio legítimo posterior; el backup conserva el
estado anterior y los recibos contienen los snapshots de asignación.
Los otros 20 casos de asignación cuestionada y el saneamiento de las demás
familias mantienen sus propios pendientes.

Comprobación en la app Debug real: AE0165 abrió «Cinta o cubierta de manubrio»,
7290001284315 abrió «Candado» y AE0317 abrió «Luz». Las tres fichas conservaron
campos sin confirmar; la de luz mostró sus tres pendientes de posición, unidades
e información por modo. Sólo se leyó y navegó, sin pulsar Guardar. Semántica y
frames: `tape-editor`, `lock-editor`, `light-editor` en la carpeta privada de la
tanda. La muestra visual no sustituye la lectura autenticada de los 54 productos.
