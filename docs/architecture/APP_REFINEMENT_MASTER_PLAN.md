# Plan maestro de refinamiento integral de la aplicación

**Estado:** contrato normativo y plan de ejecución gradual  
**Vigente desde:** 2026-08-02  
**Primer módulo piloto:** Nóminas

## 1. Objetivo

La migración visual de Viñabike ERP no es un cambio cosmético. Cada módulo que
se lleve a la nueva UI debe quedar refinado como producto completo: aspecto,
flujo de trabajo, reglas de negocio, persistencia, seguridad, contabilidad,
inventario, correcciones y evidencia operativa.

La prioridad de ejecución es la UI porque es la superficie desde la que se
descubren y ordenan los flujos. Sin embargo, **ningún módulo se considera
terminado si sólo cambió su presentación**.

## 2. Qué significa refinar un módulo

Cada ronda debe evaluar y, cuando corresponda, corregir estas dimensiones:

1. **UI y sistema visual**
   - fidelidad a la propuesta vigente de Design;
   - componentes universales, roles semánticos y ausencia de variantes locales;
   - estados claro/oscuro, escritorio, tablet y teléfono;
   - carga, vacío, error, parcial, bloqueado, éxito y contenido real.
2. **UX y flujo operativo**
   - palabras propias del negocio y siguiente acción inequívoca;
   - navegación, retorno, foco, teclado, accesibilidad y prevención de errores;
   - corrección guiada sin obligar al usuario a recurrir a soporte o SQL;
   - comportamiento consistente en todas las superficies registradas.
3. **Lógica de dominio y negocio**
   - estados y transiciones que realmente existen en Viñabike;
   - autoridad única para cada dato y operación;
   - restricciones deliberadas, no heredadas accidentalmente de la UI vieja;
   - manejo explícito de parciales, reaperturas, cancelaciones y reemplazos.
4. **Backend e integridad de datos**
   - comandos tenant-aware, autorizados, atómicos, idempotentes y seguros ante
     reintentos y concurrencia;
   - invariantes, RLS, trazabilidad, errores recuperables y compatibilidad de
     clientes distribuidos;
   - una sola autoridad de escritura; el cliente no coordina efectos parciales.
5. **Contabilidad, dinero e inventario**
   - propietario inequívoco del asiento y, si aplica, del movimiento de stock;
   - asientos balanceados, continuidad de cuentas y conciliación de saldos;
   - stock físico, valoración, pagos, impuestos y documentos sin doble posteo;
   - efecto directo y efecto inverso certificados juntos.
6. **Seguridad, auditoría y operación**
   - actor, tenant, fecha efectiva, fecha de registro, motivo y evidencia;
   - permisos por capacidad, no sólo por visibilidad del botón;
   - observabilidad suficiente para reconstruir el resultado y repararlo sin
     alterar silenciosamente la historia.

## 3. Modelo obligatorio de análisis

Antes de implementar, el agente documenta dos cadenas para cada flujo mutante:

```text
Owner -> Control -> Operation -> Consumers
Source -> Forward effect -> Correction/Reversal -> Projections -> Evidence
```

- **Owner:** entidad o documento que posee el efecto de negocio.
- **Control:** superficie canónica desde donde el usuario actúa.
- **Operation:** comando/RPC que valida y ejecuta atómicamente.
- **Consumers:** listas, reportes, estados, notificaciones e integraciones.
- **Source:** documento, pago, recepción, movimiento o decisión original.
- **Forward effect:** cambios de negocio, contabilidad, stock y proyecciones.
- **Correction/Reversal:** operación formal que neutraliza o reemplaza el
  efecto sin borrar la evidencia original.
- **Evidence:** operación, checkpoints, documentos, asientos y actor que
  permiten reconstruir ambos sentidos.

La auditoría debe buscar todas las superficies y todos los consumidores, no
sólo la ruta mostrada en el pantallazo que inició el trabajo.

## 4. Contrato transversal de corrección y reversa

Toda operación con efecto persistente debe tener una salida formal proporcional
a su impacto. No todas se llaman igual: puede ser **corregir**, **reversar**,
**anular**, **reabrir**, **devolver**, **emitir nota de crédito** o
**reemplazar**. Lo obligatorio es que el negocio pueda deshacer o corregir el
efecto de manera coherente.

### 4.1 Reglas no negociables

1. No borrar ni reescribir evidencia posteada para ocultar un error.
2. Preservar el original y agregar una reversa, anulación o supersesión ligada.
3. Exigir motivo; registrar actor, tenant, fecha efectiva y fecha de registro.
4. Ejecutar la corrección en un comando atómico e idempotente con bloqueo y
   control de versión cuando exista concurrencia posible.
5. Revertir dependencias en su orden correcto y exactamente una vez.
6. Crear asientos compensatorios balanceados enlazados al asiento original;
   nunca editar o eliminar silenciosamente el asiento posteado.
7. Crear movimientos inversos de stock sólo cuando el efecto físico original
   realmente lo requiera; un cambio exclusivamente financiero mueve cero stock.
8. Recalcular saldos, estados y proyecciones desde la evidencia canónica, no
   mediante valores forzados desde Flutter.
9. Conservar documentos externos, asignaciones OCR, conciliaciones y adjuntos;
   marcarlos como reversados/supersedidos y mantener su linaje.
10. Una “edición” de una transacción ya posteada se implementa como
    **reversa + reemplazo** cuando mutar el original rompería la auditoría.
11. Reintentar la misma llave devuelve el mismo recibo y no duplica dinero,
    stock, asiento ni evidencia.
12. Toda reversa se prueba junto al camino directo, incluyendo autorización,
    otro tenant, parciales, último pago, concurrencia y fallo intermedio.

### 4.2 Resultado mínimo visible para el usuario

La UI debe mostrar:

- qué operación se corregirá y qué efectos tendrá;
- un motivo obligatorio y, cuando corresponda, la fecha efectiva;
- el original como `Reversado`/`Anulado`, sin hacerlo desaparecer;
- quién y cuándo hizo la corrección;
- el vínculo con la reversa y con su reemplazo, si existe;
- el saldo/estado recalculado y una acción clara para registrar el dato correcto.

No se acepta una posibilidad técnica oculta sólo en SQL como sustituto de un
flujo de corrección normal para usuarios autorizados.

### 4.3 Efectos que deben auditarse por familia

| Familia | Correcciones y efectos que deben certificarse |
|---|---|
| Ventas, POS y tienda online | pagos, anulaciones, devoluciones, notas de crédito, impuestos, CxC, ingreso, COGS y stock físico |
| Compras y recepción | pagos, recepción parcial, devolución a proveedor, crédito, CxP, inventario y valoración |
| Gastos y Nóminas | pago/anticipo, conciliación, obligación, gasto, caja/banco y reapertura del saldo |
| Inventario | ajuste, conteo, transferencia, conversión, set, merma y movimiento/valor inverso ligado al original |
| Taller | documento dueño del cobro y stock, cancelación/reapertura y sincronización sin doble posteo |
| Documentos no contables | anulación/supersesión y consumidores derivados, sin inventar asientos o stock inexistentes |

El detalle del kernel compartido de inventario y contabilidad sigue siendo
propiedad de `docs/architecture/INVENTORY_ACCOUNTING_TRACEABILITY_PLAN.md`.

## 5. Secuencia de refinamiento por módulo

1. **Baseline real:** inventariar rutas, superficies, comandos, tablas,
   triggers, datos de producción y deuda conocida.
2. **Evaluación de Design:** registrar página, turno y componentes; decidir qué
   se copia, adapta, descarta y agrega según negocio real.
3. **Mapa de autoridad:** completar las dos cadenas del apartado 3 y el mapa de
   estados/transiciones.
4. **Auditoría bidireccional:** probar creación/avance y también
   corrección/reversa, incluyendo consecuencias contables y de stock.
5. **Implementación integral:** primero el owner y comando atómico, luego todas
   las superficies y consumidores; no crear una segunda autoridad temporal.
6. **Regresiones:** DB/pgTAP, servicios y widgets; incluir reintento,
   concurrencia, aislamiento de tenant y estados adversos.
7. **Verificación real:** sesión de debug con datos reales, claro/oscuro y
   escritorio/compacto/teléfono; comparar visual y estructuralmente con Design.
8. **Cierre:** actualizar registro de superficies, matriz de transición,
   documentación de dominio y evidencia local/desplegada por separado.

## 6. Puerta de término

Un módulo sólo puede marcarse terminado cuando existe evidencia de que:

- la UI vigente cubre todas sus superficies registradas y estados reales;
- el flujo es usable y correcto en escritorio, móvil, claro y oscuro;
- los términos, permisos y transiciones coinciden con el negocio;
- cada mutación tiene dueño único, comando atómico e idempotencia;
- cada operación material tiene corrección/reversa formal o una razón de
  dominio explícita por la que no corresponde;
- los caminos directo e inverso dejan contabilidad balanceada, stock coherente,
  saldos correctos y evidencia append-only;
- las pruebas relevantes, analyzer y verificaciones de DB están verdes;
- la app real fue operada con datos reales y no sólo mediante placeholders o
  snapshots sintéticos;
- cualquier despliegue requerido fue leído de vuelta desde el destino; un
  cambio local verde no se reporta como publicado.

Si falta una de estas pruebas, el estado es `parcial` o `bloqueado`, nunca
`terminado`.

## 7. Artefacto mínimo por módulo

Cada módulo mantiene una matriz compacta, dentro de su plan de cierre o en un
documento dedicado, con estas columnas:

| Flujo/superficie | Owner | Comando | Efecto directo | Corrección/reversa | Contabilidad | Stock | Consumidores | Pruebas | Runtime |
|---|---|---|---|---|---|---|---|---|---|

La matriz registra hechos y gaps concretos; no sustituye los documentos
canónicos ni repite código visible en git.

## 8. Prioridad gradual

1. **Nóminas:** piloto actual. Debe cerrar pagos, anticipos, OCR/conciliación,
   historial y reversa auditada de liquidaciones antes de declararse terminado.
2. **Flujos diarios con dinero o stock:** ventas/POS, compras/recepción,
   gastos, taller, inventario y tienda online.
3. **Operación y soporte:** clientes, proveedores, RR.HH. adyacente, archivos,
   reportes y herramientas.
4. **Administración y baja frecuencia:** configuración y superficies restantes.

La prioridad puede cambiar por riesgo o frecuencia, pero no se rebaja la puerta
de término. Los componentes compartidos descubiertos en un módulo se corrigen
en su owner canónico para beneficiar a los siguientes.

## 9. Nóminas como piloto

El cierre de Nóminas debe demostrar este contrato de punta a punta:

- el pago o anticipo original permanece inmutable y visible;
- un usuario autorizado puede corregirlo mediante reversa auditada con motivo;
- la operación compensa caja/banco y obligación de nómina con un asiento
  balanceado ligado al original;
- la línea y semana recuperan exactamente su saldo/estado anterior;
- conciliación/OCR preserva el documento original y muestra su supersesión;
- el reemplazo puede registrarse desde el flujo normal;
- reintentos, concurrencia, parciales y otro tenant no duplican ni filtran datos;
- historial, cola, detalle y evidencia muestran la misma verdad.

El RPC legado que elimina pagos de una semana completa no satisface este
contrato y no debe exponerse como la nueva solución de producto.

## 10. Documentos relacionados

- `.github/GUI_DESIGN_PRINCIPLES.md`
- `.github/GUI_MOBILE_DESIGN_PRINCIPLES.md`
- `docs/development/AGENT_VISUAL_WORKFLOW.md`
- `docs/development/DESIGN_HANDOFF_SYNC_CONTRACT.md`
- `docs/architecture/universal-ui-component-system.md`
- `docs/architecture/canonical-ui-surfaces.md`
- `docs/development/AGENT_DATABASE_CONTRACT.md`
- `docs/architecture/INVENTORY_ACCOUNTING_TRACEABILITY_PLAN.md`

Este documento gobierna la amplitud y la puerta de término del refinamiento;
los documentos especializados siguen siendo dueños de sus contratos técnicos.
