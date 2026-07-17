# Rediseño integral de modos de trabajo del taller

**Estado:** contrato de base 010–100 desplegado, registrado y verificado en
producción. El cliente rediseñado permanece pendiente de commit/publicación
coordinada y smoke del binario exacto.

**Fecha:** 2026-07-16

**Superficie principal:** `/taller/pegas`

**Principio operativo:** mantener una sola tabla y el flujo conocido por los
trabajadores, corrigiendo internamente la arquitectura y haciendo explícitas
solo las decisiones que realmente cambian el comportamiento del negocio.

## 1. Problema que resuelve

El campo histórico `mechanic_jobs.job_type` mezcla dos conceptos diferentes:

1. la etapa o responsabilidad comercial del registro (`presupuesto`,
   `servicio`, `garantía`); y
2. lo que el cliente dejó físicamente en el taller (`bicicleta`, `componente`
   o todavía nada).

Esa mezcla provoca actualmente:

- presupuestos que parecen facturas o que no pueden generar un PDF propio;
- conversiones que cambian datos directamente sin una transacción auditable;
- componentes contados erróneamente como bicicletas;
- servicios antiguos sin bicicleta que muestran un ícono genérico y `—`;
- garantías pendientes o rechazadas cuya relación con una factura no es clara;
- riesgo de que una cotización afecte inventario o contabilidad antes de ser
  aprobada;
- pérdida de contexto al convertir un presupuesto o una garantía a un trabajo
  cobrable.

## 2. Resultado esperado

Los trabajadores seguirán usando la misma ficha y tabla, ahora con cinco
accesos explícitos:

| Opción visible | Significado operativo | Factura | Inventario / contabilidad |
|---|---|---|---|
| Servicio | El cliente dejó una o más bicicletas; el trabajador elige `Presupuestar primero` (default nuevo) o `Facturar ahora` | Solo al facturar ahora o al aprobar/convertir el presupuesto | Propiedad exclusiva de la factura cuando esta existe |
| Componente | El cliente dejó solo una rueda, horquilla u otro componente | Sí, sin aumentar el contador de bicicletas | Propiedad exclusiva de la factura |
| Cotización | Consulta comercial sin bicicleta ni componente recibido | No | No reserva, descuenta ni contabiliza stock |
| Garantía | Reclamo vinculado a un trabajo entregado previamente | Solo respaldo interno si está cubierta; factura cobrable si no está cubierta | La factura asociada sigue siendo el único dueño del movimiento y asiento |
| Venta / cobro | Venta de producto registrada en la tabla sin bicicleta ni componente recibido | Sí; admite abonos parciales | Propiedad exclusiva de la factura y sus pagos |

No se agregará otra columna permanente a la tabla. La diferencia se comunicará
en los chips, íconos, textos secundarios, menús y acciones existentes.

## 3. Arquitectura de datos objetivo

Se conservará `job_type` por compatibilidad, pero se introducirán dos ejes
canónicos aditivos:

- `workflow_kind`: `service`, `quotation`, `warranty` o `sale`;
- `intake_kind`: `bike`, `component`, `none` o `unspecified`.

Mapeo compatible:

| `job_type` legado | `workflow_kind` | `intake_kind` |
|---|---|---|
| `service` | `service` | `bike` |
| `quotation` (fachada compatible de Servicio) | `quotation` | `bike` |
| `item_service` | `service` | `component` |
| `quotation` | `quotation` | `unspecified`, hasta su conversión |
| `warranty` | `warranty` | heredado del trabajo original |
| `service` (fachada compatible) | `sale` | `none` |

Se agregarán además:

- `mode_needs_review`: marca conservadora para registros históricos ambiguos;
- `mode_review_reason`: explica por qué no se puede clasificar automáticamente;
- un ledger append-only de eventos de modo y presupuesto, con actor, timestamp
  de servidor, clave idempotente, motivo y snapshot del registro/ítems.
- un ledger append-only separado para cada transición operativa de estado, con
  estado anterior/nuevo, actor, timestamp de servidor, request y resultado.

Los eventos cubrirán como mínimo:

- creación y clasificación inicial;
- cambio de estado de presupuesto;
- conversión de presupuesto a servicio o componente;
- decisión de garantía no cubierta y creación de su factura cobrable;
- clasificación/backfill histórico;
- separación segura de una factura borrador creada por el flujo legado.

## 4. Invariantes obligatorias en base de datos

1. Un presupuesto no puede quedar vinculado a `sales_invoices`.
2. Crear o editar ítems de un presupuesto no mueve inventario ni genera
   asientos.
3. Un servicio cobrable de bicicleta debe tener una bicicleta activa y válida
   del mismo cliente y tenant.
4. Un trabajo cobrable de componente debe identificar el objeto recibido con
   un sujeto activo del mismo tenant o una descripción manual explícita; no
   crea una fila ficticia en `mechanic_job_bikes` para satisfacer la UI.
5. Una garantía debe conservar el vínculo al trabajo original y su decisión
   auditada.
6. Una garantía cubierta tiene valor cliente cero y usa un documento interno
   para registrar costo de garantía y salida de inventario, sin ingreso, IVA,
   cuenta por cobrar ni pago.
7. Una garantía no cubierta solo genera cobro mediante una decisión explícita,
   justificada y auditada; la factura se crea en esa misma transacción.
8. Toda conversión crea/sincroniza la factura en la misma transacción o falla
   completa, sin estados intermedios.
9. Las claves de operación permiten repetir la misma solicitud sin duplicar
   factura, vínculo, evento, movimiento ni asiento. Reutilizar una clave con
   otro trabajo, tipo de evento o payload falla explícitamente.
10. El tenant se valida en cada tabla, FK y comando RPC.
11. Aprobar un presupuesto captura sus campos comerciales e ítems exactos en
    un evento append-only con hash; la conversión vuelve a comparar ese mismo
    snapshot y falla si el contenido cambió.
12. Un presupuesto aprobado no se edita directamente: para corregirlo se
    reabre con motivo, se modifica y se aprueba una nueva versión. El servicio
    resultante de una conversión sí continúa editable de forma normal.
13. Los precios del presupuesto son montos brutos para el cliente: antes de
    existir factura su IVA persistido es cero y el único ajuste al total es el
    descuento explícito. La clasificación tributaria sigue perteneciendo al
    panel de pago de la factura.
14. La sincronización factura→trabajo no puede borrar el `job_bike_id` de un
    ítem estable cuando el JSON comercial omite esa atribución física, la deja
    vacía o contiene `null`. Un valor explícito solo es válido si referencia una
    bicicleta vinculada al mismo trabajo y tenant; cualquier otro valor aborta
    la transacción.
15. Los cambios operativos de estado usan un único comando idempotente que
    deriva `status`, `status_id` y timestamps en el servidor. Guardar la ficha
    no reenvía esas columnas; una garantía cubierta con evidencia de pago falla
    antes de ejecutar efectos financieros.

## 5. Flujos de usuario

### 5.1 Servicio de bicicleta

1. Seleccionar o crear cliente.
2. Seleccionar o crear una o más bicicletas mediante la ficha canónica.
3. Completar solicitud, diagnóstico, ficha técnica, productos y servicios.
4. Elegir la ruta comercial sin cambiar de ficha:
   - `Presupuestar primero` (default solo para trabajos nuevos): guardar el
     agregado estable de trabajo, bicicletas e ítems sin factura ni efectos
     financieros; compartir un PDF **PRESUPUESTO** y, al aprobar, convertir el
     mismo trabajo reutilizando sus bicicletas.
   - `Facturar ahora`: crear o sincronizar la factura cobrable después de
     persistir los ítems, conservando el comportamiento histórico.
5. Inventario, IVA, ingreso, costo y pago se ejecutan únicamente desde la
   factura y su panel de pago. Un servicio histórico cobrable nunca cambia al
   nuevo default al volver a abrirse.

### 5.2 Componente

1. Seleccionar cliente.
2. Elegir el componente recibido (por ejemplo, rueda completa) y agregar una
   descripción identificadora.
3. Completar diagnóstico narrativo, productos y servicios sin exigir una
   bicicleta ficticia.
4. Guardar y crear la factura cobrable.
5. Mostrar el componente en la columna `Bicicleta`, pero excluirlo del contador
   de bicicletas y contarlo como `Ítem`.

### 5.3 Cotización sin objeto recibido

1. Seleccionar cliente y describir lo que se cotiza.
2. Agregar productos/servicios propuestos, descuento y vigencia.
3. Guardar siempre como `Pendiente`, sin factura ni movimientos financieros.
4. Descargar/compartir un PDF titulado **COTIZACIÓN**, con número de trabajo,
   vigencia, cliente, líneas y total; nunca debe decir `Factura` ni `Saldo
   adeudado`.
5. Registrar aprobación, rechazo o expiración mediante comando auditado.
   La aprobación congela un snapshot exacto de campos e ítems; para revisarlo
   se vuelve a `Pendiente` con motivo y se genera una aprobación nueva.
6. Al aprobar y si el cliente trae el objeto, escoger qué recibió el taller:
   - `Bicicleta`: seleccionar/crear bicicleta del cliente;
   - `Componente`: seleccionar el componente recibido.
7. Convertir atómicamente el mismo registro a trabajo cobrable, conservar el
   snapshot original de la cotización y generar la factura recién entonces.

La relación fuerte usa una sola fuente de verdad:
`mechanic_jobs.invoice_id -> sales_invoices.id`. Desde el trabajo se abre la
factura directamente y desde la factura se busca el trabajo por ese mismo FK;
no se duplica el vínculo en una segunda columna susceptible a desincronizarse.
Una factura vinculada tampoco puede borrarse por separado desde Ventas: el FK
usa `ON DELETE RESTRICT` y no existe cascada factura→trabajo. Así, borrar un
borrador nunca destruye silenciosamente la ficha autoritativa del taller.
Al aprobar, rechazar o expirar explícitamente un presupuesto de servicio, la
base de datos también congela sus filas `mechanic_job_bikes` (bicicleta
recibida, ficha y diagnóstico) hasta que una reapertura auditada lo devuelva a
`pending`.

### 5.4 Garantía

1. Seleccionar cliente y trabajo original entregado.
2. Heredar bicicleta o componente desde ese trabajo.
3. Mostrar vigencia calculada desde el ledger inmutable de entrega.
4. Guardar el reclamo pendiente sin generar una factura de cliente.
5. Decidir:
   - `Cubierta`: documento interno a valor cliente cero, costo de garantía e
     inventario respaldados por la factura interna;
   - `No cubierta`: motivo obligatorio y creación atómica de la factura
     cobrable, conservando el trabajo como reclamo de garantía;
   - fuera de plazo: motivo obligatorio incluso cuando se acepta.
6. Conservar siempre el trabajo original, la ventana evaluada, el actor, la
   decisión y la justificación.

### 5.5 Venta / cobro

1. Seleccionar cliente y al menos un producto de catálogo.
2. Guardar sin bicicleta, componente, diagnóstico ni planificación mecánica.
3. Crear la factura normal; stock, ingreso, IVA, cuenta por cobrar y pagos
   continúan siendo propiedad exclusiva de ella.
4. Registrar cada abono desde el panel de pago existente. Un saldo parcial
   mantiene la venta en `Activos`; saldo cero la retira de esa vista.
5. Un texto como “$10.000 semanal” es una nota operativa, nunca un segundo
   ledger de cuotas.

## 6. Diseño de la tabla única

No se agregan columnas. Se reutilizan las existentes así:

- `Bicicleta`:
  - bicicleta real: ícono y nombre habitual;
  - componente: ícono de herramienta y nombre del componente;
  - presupuesto de servicio: la bicicleta real, porque sí fue recibida;
  - cotización: ícono de documento, descripción resumida y `Sin objeto recibido`;
  - venta/cobro: ícono de venta, producto resumido y `Sin objeto recibido`;
  - ambiguo legado: texto explícito `Clasificación pendiente`, nunca `—`.
- `Estado`: mantiene el estado operativo y añade un sublabel compacto para el
  estado comercial o de garantía cuando corresponde.
- `Factura`:
  - presupuesto de servicio: el chip `Presupuesto` descarga su PDF mientras
    está pendiente; una vez aprobado abre un menú compacto con `Descargar
    presupuesto` y `Facturar presupuesto`. Facturar reutiliza el comando
    auditado/idempotente de conversión y nunca crea una segunda ruta de factura.
    La aprobación exige por contrato al menos una línea de producto/servicio,
    y cada cambio de estado reemplaza cualquier aviso transitorio anterior;
  - cotización: chip `Cotización` que descarga/abre su PDF;
  - servicio/componente: estado real de la factura;
  - venta/cobro: estado real, abono y saldo de la misma factura;
  - garantía cubierta: `Respaldo interno`;
  - garantía pendiente: `En evaluación`, sin fingir que existe una factura.
- menú `⋮`:
  - propuesta: descargar el PDF con su nombre correcto, aprobar/convertir o
    rechazar; el presupuesto reutiliza su bicicleta y solo la cotización abre
    el selector de recepción;
  - garantía: resolver desde el chip de estado; una decisión no cubierta deja
    disponible su factura cobrable sin un segundo cambio de tipo;
  - registro ambiguo: `Revisar modo` abre la misma clasificación compacta que
    el chip de alerta, sin obligar a navegar a otra pantalla;
  - acciones comunes existentes se conservan.

Los contadores quedan definidos así:

- `Bicicletas`: solo recepciones físicas con filas válidas en
  `mechanic_job_bikes`;
- `Ítems`: trabajos de componente;
- `Presupuestos`: `workflow_kind = quotation AND intake_kind = bike`; también
  cuentan sus bicicletas reales;
- `Cotizaciones`: `workflow_kind = quotation AND intake_kind != bike`; no
  consumen capacidad mecánica;
- `Garantías`: reclamos de garantía activos según su fase operativa.
- `Ventas / cobros`: `workflow_kind = sale`; no incrementan los contadores de
  bicicletas, ítems recibidos ni garantías.

## 7. Formulario y navegación

- Mantener el layout general conocido y mostrar los cinco modos.
- Agregar una explicación de una línea bajo cada modo seleccionado.
- Mostrar únicamente campos pertinentes al modo.
- El selector de tipo se bloquea después de guardar; los cambios de obligación
  se hacen con acciones de conversión auditadas.
- El presupuesto no permite cambiar arbitrariamente a `Aprobado` desde un
  dropdown que solo edita una columna: usa una acción con confirmación.
- La conversión de un presupuesto de servicio confirma y reutiliza la(s)
  bicicleta(s) ya vinculada(s), sin selector. Solo la Cotización solicita
  bicicleta/componente dentro del mismo diálogo y valida propiedad del cliente.
- `Revisar modo` solo aparece en registros conservadores marcados
  `mode_needs_review`. Para bicicleta lista únicamente bicicletas activas del
  cliente; para componente acepta un sujeto activo del tenant o una descripción
  manual. La acción admite una razón de auditoría y llama al comando idempotente
  `classify_mechanic_job_intake`.
- Para una venta sin objeto, la misma revisión llama al comando hermano
  `classify_mechanic_job_as_sale`; nunca convierte todos los casos ambiguos por
  inferencia.
- Si falla la carga opcional del catálogo de componentes, la descripción manual
  sigue disponible. Ningún error de catálogo convierte ni borra el trabajo.
- En errores o respuestas inciertas, mantener el formulario y datos visibles;
  no mostrar éxito ni permitir una segunda conversión ciega. La clasificación
  genera una sola clave de operación por intento y conserva esa misma clave
  durante el readback/replay posterior a un ACK perdido; una respuesta incierta
  se muestra como tal hasta reconciliar el recibo, nunca como un rollback
  confirmado.
- La tabla, calendario, formulario routed y formulario embedded consumen los
  mismos servicios y read models.

## 8. PDF de propuesta

Se reutilizará el generador visual de documentos comerciales con un tipo de
documento explícito y default compatible para facturas.

El tipo explícito decide el título: el servicio con bicicleta recibida genera
**PRESUPUESTO** y la consulta sin objeto recibido genera **COTIZACIÓN**. Ambos
deben incluir:

- logo y datos de Viñabike;
- título y nombre de archivo coherentes con el tipo;
- número de trabajo/presupuesto;
- fecha de emisión y `Válido hasta`;
- cliente y RUT cuando exista;
- descripción, cantidad, precio y total por línea;
- subtotal, descuento y total propuesto;
- texto claro de que no es una factura ni acredita pago; la Cotización tampoco
  acredita recepción, mientras el Presupuesto puede identificar la bicicleta
  que ya está en custodia del taller.

No debe incluir:

- número de factura;
- `Facturar a`;
- saldo adeudado, pago realizado o estado de pago;
- lenguaje que implique que la bicicleta/componente fue recibido si aún no lo
  fue.

## 9. Inventario, contabilidad e impuestos

- El trabajo permanece como documento operativo.
- La factura es el único documento financiero dueño de:
  - salida de stock;
  - costo de venta o costo de garantía;
  - ingreso;
  - IVA;
  - cuenta por cobrar;
  - pago/reembolso.
- El impuesto se elige y registra únicamente en el panel de pago; el trabajo
  solo refleja el resultado persistido.
- Antes de convertirse, el presupuesto se calcula como suma bruta de líneas
  menos descuento, con `tax_treatment = no_tax` y `tax_amount = 0`. No se suma
  un 19% ficticio por fuera del precio que se mostró al cliente.
- Un presupuesto no crea reservas contables implícitas ni stock comprometido.
- La conversión copia las líneas preservando sus IDs técnicos y luego usa el
  bridge bidireccional existente con la factura.
- `sale/none` usa exactamente el mismo bridge, pago parcial y ledger de factura;
  no crea tablas paralelas de saldo, inventario o contabilidad.

## 10. Backfill y compatibilidad histórica

El backfill será conservador y aditivo:

1. mapear sin alterar totales únicamente registros anteriores al corte fijo
   `2026-07-16 05:15:00+00`; ese corte nunca se mueve en una reejecución;
2. clasificar automáticamente solo cuando hay evidencia inequívoca;
3. dejar `mode_needs_review = true` cuando la evidencia no alcanza;
4. no inventar bicicletas ni componentes;
5. no reescribir facturas pagadas, movimientos o asientos históricos;
6. separar una factura borrador de un presupuesto legado solo si simultáneamente:
   - la factura está en borrador;
   - no tiene pagos vigentes;
   - no tiene movimientos de stock;
   - no tiene asientos contables;
   - el texto histórico identifica inequívocamente una cotización;
7. revalidar y cancelar primero esa factura borrador, preservándola como
   evidencia histórica; solo después registrar el evento y separarla del
   trabajo, todo en la misma transacción;
8. registrar cada reclasificación en el ledger de modos.

La instalación del contrato y la reparación de datos están separadas
deliberadamente:

- `20260716030000_harden_quotation_approval_contract.sql` define primero todas
  las funciones. Solo al final solicita, con `NOWAIT`, el bloqueo DDL mínimo
  necesario para reemplazar constraints/triggers; usa `lock_timeout = 750ms` y
  `statement_timeout = 20s`, por lo que aborta la transacción completa en vez de
  quedar en cola y bloquear la operación normal del taller.
- `20260716035000_normalize_quotation_non_posting_candidate.sql` es el único
  backfill de este endurecimiento. Usa `SHARE ROW EXCLUSIVE NOWAIT` —las lecturas
  siguen disponibles—, `statement_timeout = 12s`, el fingerprint congelado de
  `PG-00468`, una actualización de una sola fila y un evento inmutable. Cero
  candidatos es replay seguro; cualquier candidato distinto aborta. No crea ni
  reejecuta facturas, pagos, stock o asientos.
- `20260716060000_preserve_workshop_invoice_bike_attribution.sql` reemplaza una
  función de sincronización y no contiene backfill: no reescribe el JSON de
  facturas ni la atribución histórica.
- `20260716070000_harden_warranty_source_object_contract.sql` reemplaza la
  vista/RPC de garantía, los dos entrypoints compartidos y agrega guards de
  snapshot/pago; no contiene ningún backfill ni DML de negocio al instalar.
  Expone `intake_kind` y hereda exactamente bicicleta o componente. Los caminos
  RPC bloquean factura antes que trabajo, igual que pagos. Estado pagado,
  `paid_amount` positivo o pago activo impiden entrar o salir de `Cubierto`.
  Tras cualquier historia financiera, el sync genérico conserva byte por byte
  ambos lados comerciales, pagos, stock y asientos: nunca limpia historia
  antigua de forma implícita.
- `20260716080000_add_canonical_mechanic_job_status_transition.sql` crea el
  ledger inmutable y el comando exact-key de estado. No contiene backfill ni
  DML de negocio al instalar. Bloquea factura antes que trabajo, usa el reloj
  del servidor y convierte un cambio al mismo estado en un recibo no-op sin
  disparar triggers de ciclo de vida.
- `20260716090000_complete_non_warranty_nested_invoice_traces.sql` reemplaza
  dos funciones de trigger existentes. El ciclo de garantía publica y restaura
  un marcador transaccional exacto de tenant/trabajo/factura; el restaurador de
  trazas completa en la misma transacción las raíces creadas por estados de
  servicio/componente y conserva abierta únicamente la raíz que coincide con
  ese marcador de garantía cubierta, porque todavía debe adjuntar stock/costo
  desde su escritor invoice-owned. No reescribe filas de negocio ni ejecuta
  backfill histórico.
- `20260716100000_restrict_expense_period_details_acl.sql` corrige el privilegio
  explícito que los defaults de Supabase podían conservar para `anon` y
  `service_role` sobre el RPC `SECURITY DEFINER` del drill-down de gastos. Es
  DDL de permisos solamente: conserva `authenticated`, no lee ni modifica filas
  de negocio y no ejecuta backfill.

Hallazgos de producción que guían el backfill inicial (snapshot 2026-07-15):

- 395 servicios, cuatro sin bicicleta ni `mechanic_job_bikes`;
- dos trabajos de componente correctamente excluidos del contador;
- un presupuesto canónico sin factura;
- siete garantías con historia financiera heredada;
- `PG-00248`: garantía pendiente con factura pagada; su factura debe seguir
  visible y permanecer inmutable hasta una decisión/reverso financiero
  explícito, nunca repararse mediante backfill;
- `PG-00397`: evidencia suficiente de rueda/componente;
- `PG-00455`: presupuesto válido que no debe ser modificado por 030;
- `PG-00468`: único candidato conocido para la normalización acotada de 030;
  no tiene factura, pago, stock ni asiento, y la migración solo puede tocarlo si
  su fingerprint completo sigue coincidiendo al momento de aplicar;
- `PG-00465` y `PG-00344`: ambiguos; deben quedar marcados para revisión, no
  reclasificados automáticamente.

## 11. Estrategia de despliegue sin interrupción

1. Capturar fingerprint previo de trabajos, facturas, pagos, stock, movimientos
   y asientos.
2. Aplicar migración aditiva local y ejecutar pgTAP focalizado y suite completa.
3. Ejecutar analyzer/tests Flutter y tests de arquitectura.
4. Verificar los cinco modos en browser local por el camino normal del
   trabajador.
5. Aplicar la migración en producción mediante el runbook autorizado.
6. Ejecutar invariantes posteriores y comparar el fingerprint.
7. Desplegar Flutter solo después de confirmar compatibilidad de schema.
8. Repetir smoke test autenticado en producción.

Estado del rollout al 2026-07-16:

- `20260716010000_redesign_mechanic_job_modes.sql`: desplegada y registrada;
- `20260716020000_repair_nested_invoice_trace_context.sql`: desplegada,
  registrada y verificada con trazas completas;
- `20260716030000_harden_quotation_approval_contract.sql`: desplegada,
  registrada y leída de vuelta;
- `20260716035000_normalize_quotation_non_posting_candidate.sql`:
  desplegada y registrada; normalizó exactamente `PG-00468`, conservó
  `PG-00455` y no cambió pagos, stock ni asientos;
- `20260716040000_add_mechanic_job_intake_classification_command.sql`:
  desplegada, registrada y verificada mediante RPC/ACL/guards;
- `20260716050000_harden_online_manual_payment_trace_linkage.sql`:
  desplegada, registrada y verificada sin correlación por reloj;
- `20260716060000_preserve_workshop_invoice_bike_attribution.sql`:
  desplegada, registrada y verificada; no ejecutó backfill;
- `20260716070000_harden_warranty_source_object_contract.sql`: desplegada,
  registrada y leída de vuelta; seis guards, RPC y ACL confirmados, sin
  cambios en filas de negocio;
- `20260716080000_add_canonical_mechanic_job_status_transition.sql`: desplegada,
  registrada y leída de vuelta; ledger vacío al instalar, trigger inmutable,
  RPC autenticado y lock de 750 ms confirmados;
- `20260716090000_complete_non_warranty_nested_invoice_traces.sql`: desplegada,
  registrada y leída de vuelta; publicador/consumidor del marcador exacto y
  cierre de raíz ordinaria confirmados, sin trazas antiguas iniciadas;
- `20260716100000_restrict_expense_period_details_acl.sql`: desplegada,
  registrada y leída de vuelta; `authenticated` conserva `EXECUTE` y PUBLIC,
  `anon` y `service_role` quedan bloqueados;
- cliente aislado con `Revisar modo` y contrato
  030/035/040/050/060/070/080/090/100:
  **pendiente de publicación y smoke normal del trabajador**. La base ya es
  compatible tanto con el cliente anterior como con el nuevo.

No se eliminarán columnas ni funciones legadas durante esta fase. La reversión
de UI puede hacerse sin perder datos; los eventos append-only permanecen como
evidencia. Una falla de migración revierte la transacción completa.

## 12. Verificación obligatoria

### Base de datos

- ninguna propuesta pendiente puede vincular ni crear factura;
- ítems de presupuesto/cotización no cambian stock/journals;
- conversión repetida con la misma clave devuelve replay sin duplicados;
- servicio de bicicleta exige una bicicleta activa del cliente/tenant;
- servicio de componente exige sujeto activo o descripción explícita y no
  crea bicicleta;
- clasificación manual solo opera sobre service/warranty en revisión, es
  idempotente y no crea efectos financieros;
- clasificación con ACK perdido reutiliza la misma clave y reconcilia el recibo
  antes de permitir otro intento;
- conversión crea exactamente una factura y conserva líneas;
- confirmación manual online enlaza sus trazas hijas por sus claves de operación
  determinísticas exactas, nunca por un rango de `created_at`, y revierte si una
  hija falta o no está completa;
- invoice→job conserva `job_bike_id` para el mismo ID estable cuando el espejo de
  factura no lo informa, y rechaza referencias explícitas inválidas o de otro
  trabajo/tenant;
- garantía cubierta/no cubierta mantiene los invariantes existentes;
- transición de estado deriva mirror/timestamps en el servidor, reusa la misma
  clave ante ACK perdido y no altera pagos, stock ni asientos de un servicio
  normal pagado;
- cada update anidado de factura de servicio/componente deja una raíz de traza
  completada; garantía cubierta conserva su raíz hasta que su escritor adjunta
  los efectos de stock/costo y la completa;
- eventos son inmutables y tenant-scoped;
- backfill no cambia pagos, totales, stock ni balance de asientos.

### Flutter

- parsing compatible con filas previas a la migración;
- estado efectivo de presupuesto expira por fecha sin perder el estado
  persistido/auditado;
- tabla no muestra `—` para registros ambiguos;
- contador de bicicletas incluye presupuestos con bicicleta recibida y excluye
  componentes y cotizaciones sin objeto;
- generador de factura conserva su output actual;
- generador de presupuesto y cotización usa títulos mutuamente excluyentes.

### Browser

1. crear y guardar Servicio → Presupuestar primero con cliente, bicicleta,
   ficha, diagnóstico e ítems; comprobar ausencia de factura;
2. aprobar/facturar ese presupuesto y confirmar que reutiliza la bicicleta y
   crea una sola factura recíproca;
3. crear Servicio → Facturar ahora y comprobar el comportamiento histórico;
4. crear componente sin bicicleta y comprobar contador/factura;
5. crear Cotización, descargar PDF y comprobar ausencia de factura/stock;
6. aprobar Cotización, elegir bicicleta o componente y confirmar una sola
   factura;
7. crear garantía dentro y fuera de plazo, guardar justificación y comprobar
   respaldo interno o conversión cobrable;
8. recargar cada registro y confirmar persistencia;
9. revisar consola, requests y terminal durante cada flujo.

## 13. Definition of Done

El rediseño está terminado solo cuando:

- los cinco modos funcionan de punta a punta en la tabla única;
- presupuesto y cotización tienen PDF propio, con nombre correcto, y nunca se
  presentan como factura;
- conversión es atómica, auditable e idempotente;
- componente representa una recepción física sin bicicleta y no altera el
  contador;
- garantía conserva origen, plazo, decisión, motivo y respaldo financiero
  correcto;
- tabla, lista, calendario y formularios usan el mismo comando de estado y no
  existen escritores cliente directos de `mechanic_jobs.status`;
- no hay divergencia entre trabajo, factura, inventario, pago y contabilidad;
- el backfill de producción está aplicado y verificado con invariantes antes y
  después;
- `supabase/sql/core_schema.sql`, la documentación maestra y el registro de
  superficies canónicas reflejan exactamente la implementación desplegada;
- los tests locales, pgTAP, analyzer y recorridos browser pasan con evidencia.

## 14. Evidencia y estado de implementación (2026-07-16)

- La base `20260716010000_redesign_mechanic_job_modes.sql` fue aplicada y
  registrada en producción (`xzdvtzdqjeyqxnkqprtf`) después de generar un
  backup cifrado verificable. Su backfill conservador dejó los casos ambiguos
  en revisión y no cambió pagos, stock, totales financieros ni balances
  contables existentes.
- La reparación `20260716020000_repair_nested_invoice_trace_context.sql` también
  está desplegada. El readback confirmó cero raíces de operación incompletas y
  totales de stock, pagos y asientos sin cambios.
- La migración 030 desplegada endurece aprobación/conversión de presupuestos: congela y
  vuelve a validar el snapshot comercial, valida sujetos activos del tenant y
  mantiene un puente estrecho y auditado para clientes anteriores. Instala sus funciones antes de solicitar una
  ventana DDL mínima `ACCESS EXCLUSIVE NOWAIT`, de modo que contención operativa
  causa un aborto limpio en vez de una espera que congele el taller. El readback
  confirmó las funciones, guards, constraint y cuatro triggers.
- La migración 035 ejecutó por separado la reparación acotada. Comparó el
  fingerprint exacto y normalizó únicamente `PG-00468`; `PG-00455` permaneció
  como presupuesto válido sin cambios. Su lock `SHARE ROW EXCLUSIVE NOWAIT` permitió lecturas y el
  postflight exige evidencia inmutable y cero efectos financieros reejecutados.
- La migración 040 y la UI `Revisar modo` resuelven solo registros
  `mode_needs_review` mediante un comando idempotente. Bicicleta exige propiedad
  activa del cliente/tenant; componente exige sujeto activo o descripción
  manual; el evento declara explícitamente cero efectos financieros. El cliente
  conserva una clave por intento y reconcilia el mismo recibo ante un ACK
  perdido, sin declarar falsamente que no hubo cambios.
- La migración 050 endurece la confirmación manual de pagos online: localiza las
  operaciones hijas de factura/pago por su identidad determinística exacta y
  aborta atómicamente si falta una traza completa. No usa comparaciones de reloj
  o `created_at`, que pueden retroceder durante una corrección del host.
- La migración 060 desplegada preserva el `job_bike_id` existente solo para el mismo ítem
  estable cuando la factura omite el espejo; un ID explícito debe pertenecer al
  mismo trabajo/tenant. Es un reemplazo de función sin backfill ni cambios de
  datos al instalarse.
- La migración 070 desplegada mantiene garantía, pago y sync bajo el mismo orden
  de locks; sus RPC que esperan filas fijan `lock_timeout = 750ms` como
  configuración de función, no solo durante la instalación.
- La migración 080 desplegada centraliza todas las superficies de estado en un
  RPC idempotente y ledger inmutable, sin backfill. El portal cliente conserva
  historia de taller de solo lectura; se retiraron sus dos escritores directos
  no ruteados en vez de debilitar la autorización del comando de empleados.
- La migración 090 desplegada cierra la raíz contable anidada de cada cambio de
  estado de servicio/componente, sin inventar movimientos o asientos, y deja la
  garantía cubierta bajo su finalizador financiero explícito. Es reemplazo de
  función sin reparación histórica.
- La validación de release no usó staging ni una base reconstruida desde
  `core_schema.sql`. Un dump read-only fresco del `public` productivo
  (`xzdvtzdqjeyqxnkqprtf`, SHA-256
  `8763682235c79cda166c9fa8c54a40db56ba23412bc5e5d046ccff94a041d608`)
  se restauró en una base efímera; sobre ella se aplicaron solo 070–100 y los
  15 contratos de taller/factura/pago/IVA/inventario/contabilidad aprobaron
  594 assertions. Las mismas cuatro migraciones también se aplicaron
  directamente al esquema live dentro de una transacción finalizada con
  `ROLLBACK` antes del despliegue real.
- En producción, el fingerprint de 16 tablas conservó exactamente los mismos
  counts y digests después de cada migración. El health final quedó con cero
  fallas críticas; conserva 22 existencias negativas históricas como
  advertencia operativa conocida. El snapshot de pagos conserva 400 trabajos
  enlazados, 194 diferencias exclusivamente históricas/pagadas y cero
  diferencias abiertas o cobrables.
- El fingerprint productivo posterior conservó 747 pagos por CLP 18.130.590,
  2.489 movimientos y 2.160 asientos balanceados por CLP 74.607.147,70. La
  normalización no creó ninguna de esas evidencias ni modificó sus totales.
- Todo trabajo del frontend se consolida directamente en el checkout operativo
  `/Users/Claudio/Dev/bikeshop-erp`, rama `smartpegas1.0`. No se usan worktrees,
  ramas aisladas ni sesiones debug de otra copia; antes de publicar se comprueba
  que filesystem, VS Code, `HEAD` y `origin/smartpegas1.0` refieren al mismo
  commit verificado.
