# Aplicación de investigación: candidato local

El llenado continúa en cero y el saneamiento global sigue abierto. Ya existe
código para preparar un comando por producto y ejecutarlo transaccionalmente;
no se ha desplegado ni registrado un permiso o comando en producción.

- `scripts/inventory/prepare_product_spec_application.py` vuelve a comprobar la
  propuesta v2, la revisión del otro agente, la evidencia archivada, la
  preimagen autenticada y **todo** el efecto del preview. Conserva los decimales
  como texto, el backup completo y hashes del comando/paquete. Produce un
  archivo exclusivo con permisos 0600; no contiene una opción de escritura.
- `scripts/inventory/sql/product_spec_application_candidate.sql` define el
  registro privilegiado de comandos, la habilitación global por tenant y el
  aplicador autenticado. Ningún cliente puede insertar su propio permiso. No
  hay habilitación inicial; las tablas no son escribibles por authenticated
  ni service_role. El comando sólo permite modelo/MPN/GTIN, referencia y delta
  técnico del producto existente. Marca requiere el propietario canónico de
  marca/brand_id y no se aplica como una etiqueta aislada.
- El servidor bloquea el producto, sus observaciones y la metadata; relee la
  preimagen, repite el preview y exige el mismo resultado. No reemplaza una
  ficha con un subconjunto ni retira filas/celdas omitidas. Compara todas las
  columnas del producto fuera del cambio explícito y todas las observaciones
  no afectadas antes de crear el recibo en esa misma transacción.
- `research` distingue una lectura documental de `mechanic`. Un hecho igual
  conserva fuente y confirmación. Reemplazar uno físicamente confirmado exige
  un conflicto resuelto expresamente en la propuesta revisada. El recibo
  archiva íntegramente las lecturas y opciones anteriores; una lectura vieja
  no queda atribuida al nuevo valor. Repetir una operación devuelve el recibo
  sin ejecutar sus cambios de nuevo, incluso si se deshabilitó el llenado.

La [revisión independiente](research-application-independent-review-2026-09-07.md)
se realizó sobre el primer candidato, sólo por lectura. Identificó que el
candado debía normalizar el UUID: corregido con cast a uuid antes de formar la
llave. La consecuencia exacta de la carrera propuesta por Claude no quedó
demostrada: el writer viejo también ejecuta el trigger de revisión, que bloquea
la fila de producto. Sí había llaves distintas y un orden de bloqueos que no
conviene dejar divergente. No se llama a esto una prueba de concurrencia.

Validación actual: **32 pruebas Python del preparador/registrador/transporte,
26 del simulador y 42 SQL con rollback**. Incluyen UUID canónico, estado de
registro, ACL y preservación de campos ajenos. El arnés
`test_product_spec_application_roundtrip.py` además recorrió las funciones SQL
reales de lectura/preview, el preparador Python, el SQL exacto del registrador,
su repetición, el aplicador bajo rol authenticated y la verificación íntegra del
recibo. Una edición posterior de costo y la ausencia posterior del archivo de
fuente no impiden recuperar el recibo ni provocan repetir la aplicación.

La contención se probó con dos conexiones locales reales: aplicación primero y
guardado normal después; orden inverso; y dos intentos del mismo comando. Las
tres operaciones contendientes terminaron con `55P03`, sin escrituras de esos
intentos. Ambas transacciones de las sondas se revirtieron y la preimagen entera
se volvió a comparar antes de la aplicación definitiva de la fixture. No se
atribuye esto a una prueba exhaustiva de todos los escritores del ERP.

El verificador actual también leyó el recibo SQL real y rechazó cuatro copias
alteradas, incluida una identidad diferente en la proyección. El recorrido
completo rechazó además un cambio monetario aunque se recalculara el hash del
producto. Fixtures, objetos candidatos, extensión de prueba propia y constraint
de procedencia quedaron retirados/restaurados con lectura posterior. La primera
corrida corrigió dos defectos de la fixture: una fuente de fila que no era URL
y eventos diferidos pendientes antes de restaurar el constraint. Esas fallas
no se cuentan como defectos de productos ni como avances de dominio.

Evidencia: `.tmp/db/product-spec-application-roundtrip-run.log`,
`.tmp/product-spec-application-roundtrip/` (SQL y recibo sintéticos),
`.tmp/product-spec-catalog/research-application-receipt-boundary.log`,
`.tmp/product-spec-catalog/research-application-prepare-tests.log`,
`.tmp/product-spec-catalog/research-simulator-project-tests.log` y
`.tmp/db/product-spec-research-application-candidate.log`.

`prepare_product_spec_registration.py` exige proyecto/tenant del cierre global,
fuentes actuales y una simulación autenticada nueva que reproduzca exactamente
el paquete completo. Su SQL no habilita el cierre ni reemplaza un registro
distinto; sólo acepta inserción o repetición exacta. Los literales conservan
comillas, barras y delimitadores SQL como datos. `apply_product_spec_research.py`
comprueba proyecto/actor y estado del registro antes de una única llamada de
aplicación, sin reintentos automáticos de escritura. Si ya hay recibo lo recupera
sin simular un delta obsoleto. El transporte HTTP se probó con respuestas
controladas; **no se invocó una escritura HTTP contra producción**.

Antes de operar: revisión independiente del diff final, pin de objetos/ACL y
ventana de cambio del constraint de procedencia, despliegue guardado/read-back,
smoke del transporte autenticado publicado y cierre verificable del saneamiento
global. Registrar un hash es trazabilidad, no prueba criptográfica de que un
agente leyó una fuente. El registrador es una frontera privilegiada y requiere
la misma revisión que el writer. No hay registro o habilitación productiva ni
migración desplegable de este candidato. Este documento no habilita fill.

## Revisión final independiente y correcciones 2026-09-08

[Claude reprodujo dos huecos](research-application-final-review-2026-09-07.md).
El transporte confundía HTTPError con un timeout porque hereda de URLError;
ahora distingue rechazos 4xx de respuestas inciertas (408/429/5xx/transporte).
Conserva HTTP y código seguro, y sólo muestra mensajes literales propios
permitidos: no presupone que un cuerpo de error arbitrario esté libre de
credenciales. Un rechazo describe ese intento, no afirma que no exista un
recibo de una operación anterior. Una lectura fallida tampoco afirma que hubo
un intento de escritura.

La respuesta de APPLY, no el STATUS anterior, decide `recovered_existing_receipt`.
Si otra sesión aplica después del preflight, `replayed: true` se conserva en la
salida. Se exige booleano real y coincidencia del resultado con el recibo íntegro;
un resultado inválido pide recuperar el mismo ID y nunca repite la escritura.
El candado del registrador también normaliza ambos UUID antes de formar su llave.

El límite de confianza propuesta↔revisión permanece explícito: el servidor
no prueba que un agente leyó la fuente ni recalcula el cuerpo de aprobación
como firma de un humano. El registro privilegiado valida propuesta/evidencia y
simulación fresca; su autoridad es parte de la frontera revisada, no un hash.

Si el actor registrado pierde su acceso, el recibo no se recupera iniciando
sesión como otro actor ni mediante service_role. La recuperación administrativa
requiere la vía privilegiada de base de datos, mediante el wrapper canónico,
localizando el ID de operación y comprobando tenant/actor/producto del bundle.
No se cambia el actor ni se crea otra aplicación para recuperar una anterior.

Después de F-1/F-2 y de normalizar el candado del registrador se repitió el
recorrido completo SQL/Python, incluida la contención entre sesiones, APPLY,
recibo, repetición y recuperación tras una edición posterior del costo. Pasó,
y la lectura final confirmó retirada de fixtures/objetos y restauración del
constraint. Evidencia de esta segunda ejecución:
`.tmp/db/product-spec-application-roundtrip-review-fixes.log` y
`.tmp/product-spec-application-roundtrip-review-fixes/`. Las pruebas de
transporte también cubren conexión cortada durante la respuesta: recuperación
por el mismo ID, sin otra escritura automática. Sigue pendiente la revisión
independiente del delta y el despliegue; no se ha habilitado llenado.
