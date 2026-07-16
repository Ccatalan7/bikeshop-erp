# Rediseño integral de modos de trabajo del taller

**Estado:** implementado y verificado; schema desplegado en producción

**Fecha:** 2026-07-15

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

Los trabajadores seguirán viendo los cuatro accesos conocidos:

| Opción visible | Significado operativo | Factura | Inventario / contabilidad |
|---|---|---|---|
| Servicio | El cliente dejó una o más bicicletas | Sí, una vez guardados sus ítems | Propiedad exclusiva de la factura |
| Componente | El cliente dejó solo una rueda, horquilla u otro componente | Sí, sin aumentar el contador de bicicletas | Propiedad exclusiva de la factura |
| Presupuesto | Propuesta comercial; todavía no existe recepción de un objeto ni obligación de cobro | No | No reserva, descuenta ni contabiliza stock |
| Garantía | Reclamo vinculado a un trabajo entregado previamente | Solo respaldo interno si está cubierta; factura cobrable si no está cubierta | La factura asociada sigue siendo el único dueño del movimiento y asiento |

No se agregará otra columna permanente a la tabla. La diferencia se comunicará
en los chips, íconos, textos secundarios, menús y acciones existentes.

## 3. Arquitectura de datos objetivo

Se conservará `job_type` por compatibilidad, pero se introducirán dos ejes
canónicos aditivos:

- `workflow_kind`: `service`, `quotation` o `warranty`;
- `intake_kind`: `bike`, `component` o `unspecified`.

Mapeo compatible:

| `job_type` legado | `workflow_kind` | `intake_kind` |
|---|---|---|
| `service` | `service` | `bike` |
| `item_service` | `service` | `component` |
| `quotation` | `quotation` | `unspecified`, hasta su conversión |
| `warranty` | `warranty` | heredado del trabajo original |

Se agregarán además:

- `mode_needs_review`: marca conservadora para registros históricos ambiguos;
- `mode_review_reason`: explica por qué no se puede clasificar automáticamente;
- un ledger append-only de eventos de modo y presupuesto, con actor, timestamp
  de servidor, clave idempotente, motivo y snapshot del registro/ítems.

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
3. Un servicio cobrable debe tener una bicicleta válida del mismo cliente y
   tenant.
4. Un trabajo de componente debe tener un componente/ítem identificado y no
   crea una fila en `mechanic_job_bikes` solo para satisfacer la UI.
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

## 5. Flujos de usuario

### 5.1 Servicio de bicicleta

1. Seleccionar o crear cliente.
2. Seleccionar o crear una o más bicicletas mediante la ficha canónica.
3. Completar solicitud, diagnóstico, ficha técnica, productos y servicios.
4. Guardar el agregado estable de trabajo, bicicletas e ítems.
5. Crear o sincronizar la factura cobrable después de persistir los ítems.
6. Inventario, IVA, ingreso, costo y pago se ejecutan únicamente desde la
   factura y su panel de pago.

### 5.2 Componente

1. Seleccionar cliente.
2. Elegir el componente recibido (por ejemplo, rueda completa) y agregar una
   descripción identificadora.
3. Completar diagnóstico narrativo, productos y servicios sin exigir una
   bicicleta ficticia.
4. Guardar y crear la factura cobrable.
5. Mostrar el componente en la columna `Bicicleta`, pero excluirlo del contador
   de bicicletas y contarlo como `Ítem`.

### 5.3 Presupuesto

1. Seleccionar cliente y describir lo que se cotiza.
2. Agregar productos/servicios propuestos, descuento y vigencia.
3. Guardar siempre como `Pendiente`, sin factura ni movimientos financieros.
4. Descargar/compartir un PDF titulado **PRESUPUESTO**, con número de trabajo,
   vigencia, cliente, líneas y total; nunca debe decir `Factura` ni `Saldo
   adeudado`.
5. Registrar aprobación, rechazo o expiración mediante comando auditado.
   La aprobación congela un snapshot exacto de campos e ítems; para revisarlo
   se vuelve a `Pendiente` con motivo y se genera una aprobación nueva.
6. Al aprobar, escoger qué recibió el taller:
   - `Bicicleta`: seleccionar/crear bicicleta del cliente;
   - `Componente`: seleccionar el componente recibido.
7. Convertir atómicamente el mismo registro a trabajo cobrable, conservar el
   snapshot original del presupuesto y generar la factura recién entonces.

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

## 6. Diseño de la tabla única

No se agregan columnas. Se reutilizan las existentes así:

- `Bicicleta`:
  - bicicleta real: ícono y nombre habitual;
  - componente: ícono de herramienta y nombre del componente;
  - presupuesto: ícono de documento y descripción resumida;
  - ambiguo legado: texto explícito `Clasificación pendiente`, nunca `—`.
- `Estado`: mantiene el estado operativo y añade un sublabel compacto para el
  estado comercial o de garantía cuando corresponde.
- `Factura`:
  - presupuesto: chip `Presupuesto` que descarga/abre su PDF;
  - servicio/componente: estado real de la factura;
  - garantía cubierta: `Respaldo interno`;
  - garantía pendiente: `En evaluación`, sin fingir que existe una factura.
- menú `⋮`:
  - presupuesto: descargar PDF, aprobar/convertir, rechazar;
  - garantía: resolver desde el chip de estado; una decisión no cubierta deja
    disponible su factura cobrable sin un segundo cambio de tipo;
  - registro ambiguo: editar y completar clasificación;
  - acciones comunes existentes se conservan.

Los contadores quedan definidos así:

- `Bicicletas`: solo recepciones físicas con filas válidas en
  `mechanic_job_bikes`;
- `Ítems`: trabajos de componente;
- `Presupuestos`: `workflow_kind = quotation`;
- `Garantías`: reclamos de garantía activos según su fase operativa.

## 7. Formulario y navegación

- Mantener los cuatro botones y el layout general conocido.
- Agregar una explicación de una línea bajo cada modo seleccionado.
- Mostrar únicamente campos pertinentes al modo.
- El selector de tipo se bloquea después de guardar; los cambios de obligación
  se hacen con acciones de conversión auditadas.
- El presupuesto no permite cambiar arbitrariamente a `Aprobado` desde un
  dropdown que solo edita una columna: usa una acción con confirmación.
- La conversión solicita bicicleta/componente dentro del mismo diálogo y
  valida propiedad del cliente antes de confirmar.
- En errores o respuestas inciertas, mantener el formulario y datos visibles;
  no mostrar éxito ni permitir una segunda conversión ciega.
- La tabla, calendario, formulario routed y formulario embedded consumen los
  mismos servicios y read models.

## 8. PDF de presupuesto

Se reutilizará el generador visual de documentos comerciales con un tipo de
documento explícito y default compatible para facturas.

El presupuesto debe incluir:

- logo y datos de Viñabike;
- título `PRESUPUESTO`;
- número de trabajo/presupuesto;
- fecha de emisión y `Válido hasta`;
- cliente y RUT cuando exista;
- descripción, cantidad, precio y total por línea;
- subtotal, descuento y total propuesto;
- texto claro de que no es una factura ni acredita pago/recepción.

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

Hallazgos de producción que guían el backfill inicial (snapshot 2026-07-15):

- 395 servicios, cuatro sin bicicleta ni `mechanic_job_bikes`;
- dos trabajos de componente correctamente excluidos del contador;
- un presupuesto canónico sin factura;
- siete garantías con historia financiera heredada;
- `PG-00397`: evidencia suficiente de rueda/componente;
- `PG-00455`: evidencia suficiente de presupuesto legado con factura borrador,
  sujeto a los invariantes de seguridad anteriores;
- `PG-00465` y `PG-00344`: ambiguos; deben quedar marcados para revisión, no
  reclasificados automáticamente.

## 11. Estrategia de despliegue sin interrupción

1. Capturar fingerprint previo de trabajos, facturas, pagos, stock, movimientos
   y asientos.
2. Aplicar migración aditiva local y ejecutar pgTAP focalizado y suite completa.
3. Ejecutar analyzer/tests Flutter y tests de arquitectura.
4. Verificar los cuatro modos en browser local por el camino normal del
   trabajador.
5. Aplicar la migración en producción mediante el runbook autorizado.
6. Ejecutar invariantes posteriores y comparar el fingerprint.
7. Desplegar Flutter solo después de confirmar compatibilidad de schema.
8. Repetir smoke test autenticado en producción.

No se eliminarán columnas ni funciones legadas durante esta fase. La reversión
de UI puede hacerse sin perder datos; los eventos append-only permanecen como
evidencia. Una falla de migración revierte la transacción completa.

## 12. Verificación obligatoria

### Base de datos

- presupuesto no puede vincular ni crear factura;
- ítems de presupuesto no cambian stock/journals;
- conversión repetida con la misma clave devuelve replay sin duplicados;
- servicio exige bicicleta del cliente/tenant;
- componente exige sujeto y no crea bicicleta;
- conversión crea exactamente una factura y conserva líneas;
- garantía cubierta/no cubierta mantiene los invariantes existentes;
- eventos son inmutables y tenant-scoped;
- backfill no cambia pagos, totales, stock ni balance de asientos.

### Flutter

- parsing compatible con filas previas a la migración;
- estado efectivo de presupuesto expira por fecha sin perder el estado
  persistido/auditado;
- tabla no muestra `—` para registros ambiguos;
- contador de bicicletas excluye componentes y presupuestos;
- generador de factura conserva su output actual;
- generador de presupuesto usa lenguaje correcto.

### Browser

1. crear y guardar servicio con cliente/bicicleta/diagnóstico/ítems;
2. crear componente sin bicicleta y comprobar contador/factura;
3. crear presupuesto, descargar PDF y comprobar ausencia de factura/stock;
4. aprobar presupuesto, elegir bicicleta o componente y confirmar una sola
   factura;
5. crear garantía dentro y fuera de plazo, guardar justificación y comprobar
   respaldo interno o conversión cobrable;
6. recargar cada registro y confirmar persistencia;
7. revisar consola, requests y terminal durante cada flujo.

## 13. Definition of Done

El rediseño está terminado solo cuando:

- los cuatro modos funcionan de punta a punta en la tabla única;
- presupuesto tiene PDF propio y nunca se presenta como factura;
- conversión es atómica, auditable e idempotente;
- componente representa una recepción física sin bicicleta y no altera el
  contador;
- garantía conserva origen, plazo, decisión, motivo y respaldo financiero
  correcto;
- no hay divergencia entre trabajo, factura, inventario, pago y contabilidad;
- el backfill de producción está aplicado y verificado con invariantes antes y
  después;
- `supabase/sql/core_schema.sql`, la documentación maestra y el registro de
  superficies canónicas reflejan exactamente la implementación desplegada;
- los tests locales, pgTAP, analyzer y recorridos browser pasan con evidencia.

## 14. Evidencia de implementación (2026-07-15)

- La migración `20260716010000_redesign_mechanic_job_modes.sql` fue aplicada y
  registrada en producción (`xzdvtzdqjeyqxnkqprtf`) después de generar un
  backup cifrado verificable.
- El backfill clasificó conservadoramente los registros inequívocos y dejó
  `PG-00344` y `PG-00465` en revisión humana. No cambió pagos, stock, totales
  financieros ni balances contables existentes.
- La reconstrucción canónica y la suite completa de pgTAP pasaron: 47 archivos,
  1.020 assertions. El gate focalizado posterior pasó 253 assertions.
- La UI conservó una sola tabla. Se validaron en el browser autenticado:
  componente sin bicicleta, diagnóstico y recarga; presupuesto de $22.000,
  PDF, aprobación y conversión atómica a componente con una sola factura; y
  garantía vigente/vencida con justificación obligatoria fuera de plazo.
- Dos defectos detectados solo en runtime quedaron corregidos y cubiertos por
  regresión: la narrativa de trabajos sin bicicleta no se hidrataba al editar,
  y la celda compacta de plazo podía desbordarse a 1.280 px.
- Los cuatro trabajos QA detectados fueron archivados y sus facturas anuladas
  mediante los triggers oficiales. El pago QA y sus asientos se revirtieron;
  el cliente y la bicicleta QA también quedaron inactivos. Quedaron cero
  trabajos, pagos, asientos, facturas, clientes o bicicletas QA activos.
  Inventario permaneció en 2.489 movimientos y con cero diferencias de stock;
  los asientos finales quedaron balanceados en $74.607.147,70 por lado.
- Pasaron 33 tests Flutter focalizados y `just build-erp`. El analyzer no
  reportó errores ni warnings bloqueantes; conserva únicamente lints
  informativos preexistentes en los archivos grandes del taller.
- La publicación del frontend queda deliberadamente fuera de esta ejecución:
  el worktree contiene cambios concurrentes y no relacionados. Publicar ese
  artefacto mezclaría funcionalidades ajenas al rediseño y violaría el límite
  seguro de release. El schema desplegado es aditivo y compatible con el
  cliente actual mientras se prepara un release aislado.
