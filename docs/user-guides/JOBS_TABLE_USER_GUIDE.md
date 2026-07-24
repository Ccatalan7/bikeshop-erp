# Manual de usuario - Jobs Table

**Versión:** 1.0 · **Área:** Taller · **Lectura estimada:** 7 minutos

Jobs Table es el centro operativo del taller. Desde una sola tabla puedes
encontrar un trabajo, entender qué recibió la tienda, cambiar su estado,
consultar tiempos, abrir el documento comercial y entrar a la ficha completa.

## 1. Orientación rápida

- **Buscar:** encuentra por número de trabajo, cliente, teléfono, bicicleta,
  solicitud, notas o ítems del trabajo.
- **Selector Estado:** filtra los estados activos sin ocultar el historial; no
  decide ni valida cuál debería ser el siguiente estado.
- **Vista:** alterna entre tabla, calendario y otras vistas disponibles.
- **Vencidos / Sin pagar:** filtros rápidos para priorizar atención.
- **Personalizar columnas:** muestra solo la información necesaria para la tarea.
- **Encabezados:** en escritorio, haz clic en los ordenables y arrastra los
  separadores de las columnas redimensionables.
- **Fila / N° trabajo:** abre el detalle. En escritorio puedes activar el panel
  dividido para revisar sin perder la lista.

> Regla práctica: filtra primero, actúa desde los chips y abre la ficha solo
> cuando necesites editar el contenido del trabajo.

## 2. Elegir el tipo correcto al crear

| Elección | Úsala cuando | Efecto principal |
|---|---|---|
| Servicio normal | Se recibe una bicicleta | Conserva bicicleta, ficha, diagnóstico y trabajo solicitado. Por defecto permite presupuestar antes de facturar. |
| Ítem / Accesorio | Se recibe solo un componente suelto | No inventa una bicicleta ni aumenta la capacidad de bicicletas del taller. |
| Garantía | Se revisa un trabajo o producto cubierto | Mantiene el vínculo con el origen y exige una decisión de cobertura. |
| Cotización | Aún no se recibe ningún objeto | Planifica productos/servicios sin mover stock, cobrar ni contabilizar. |
| Venta / cobro | Solo se venden productos | No crea diagnóstico ni agenda mecánica. La factura controla stock, IVA y pagos. |

## 3. Flujo recomendado de un servicio

```flow
Recepción -> Diagnóstico -> Presupuesto -> Aprobación -> Trabajo -> Listo -> Entrega
```

Los nombres exactos pueden variar según la configuración. El **chip Estado**
muestra los estados activos y registra cada cambio. Elige el hito que realmente
ocurrió: el orden visual no constituye una validación del siguiente paso. No
cambies el estado editando datos por fuera de ese control.

### Presupuesto y cotización

1. Agrega al menos un producto o servicio.
2. Presiona el nombre **Presupuesto** o **Cotización** en la columna Factura
   para abrir directamente sus Productos y Servicios y editarlos mientras la
   propuesta siga pendiente.
3. Usa la flecha mínima del lado derecho del chip para `Descargar` el PDF.
4. Registra la decisión desde el chip de propuesta.
5. Si se aprueba un **Presupuesto**, abre la misma flecha y usa
   `Facturar presupuesto`.
6. Si se aprueba una **Cotización**, elige Venta, Bicicleta o Componente según
   lo que realmente se recibirá.

Una propuesta no aprobada no crea factura, movimiento de stock, IVA, ingreso ni
cuenta por cobrar. La conversión mantiene el mismo trabajo y su historial.

## 4. Acciones seguras dentro de la tabla

- **Estado:** avanza o corrige el ciclo operacional.
- **Presupuesto / Cotización:** el nombre abre Productos y Servicios; la flecha
  derecha descarga el PDF y, después de aprobar, muestra la conversión
  permitida.
- **Factura:** abre el documento comercial vinculado.
- **Bicicleta:** abre directamente la ficha cuando existe una sola bicicleta.
- **REVISAR MODO:** clasifica el registro como Bicicleta, Componente o Venta.
- **Garantía:** registra `Cubierto` o `No cubierto`. Si existen pagos vigentes,
  `Cubierto` queda bloqueado hasta revisar, reversar o reembolsar el pago desde
  la factura. El respaldo creado es interno, no tributario.
- **Exportar:** copia al portapapeles, en formato CSV, el conjunto filtrado o
  seleccionado.
- **Selección múltiple:** aplica acciones masivas solo a filas compatibles.
- **Mover a eliminados:** retira el trabajo de la lista activa, pero conserva la
  venta vinculada y su historial contable.

> Si una acción informa resultado incierto, usa REINTENTAR desde el mismo aviso
> —reutiliza la operación— o actualiza para verificar el estado. No inicies la
> acción nuevamente desde otro control.

<!-- pagebreak -->

## 5. Lectura de tiempos y métricas

La columna **Flujo** utiliza hitos creíbles del trabajo: recepción, primer
inicio, término y primera entrega. Si falta evidencia muestra `Sin dato`; no
inventa una duración. Un trabajo reabierto conserva su primera entrega.

- **Decisión cliente:** recepción hasta decisión registrada.
- **Espera a taller:** aprobación, si existe, o recepción hasta primer inicio.
- **Ejecución:** primer inicio creíble hasta término.
- **Ciclo total:** recepción hasta primera entrega.
- **`n=` en el dashboard:** cantidad de trabajos con evidencia suficiente para
  calcular esa mediana.

No confundas estas duraciones con horas pagadas al mecánico. La asistencia,
horario del negocio y horas explícitas de trabajo se comparan por separado en
los KPIs estratégicos.

## 6. Qué no hacer

- No confirmes pagos editando el total o el estado manualmente.
- No elimines una factura vinculada para “deshacer” un trabajo.
- No conviertas un componente suelto en bicicleta para que aparezca en agenda.
- No factures un presupuesto pendiente, rechazado, vencido o sin líneas.
- No uses Venta / cobro para trabajo mecánico.
- No repitas una acción después de un corte de red sin actualizar primero.

## 7. Rutina recomendada

### Apertura

1. Filtra `Activos`, luego `Vencidos` y `Sin pagar`.
2. Revisa promesas y prioridades.
3. Ajusta la vista o columnas según la reunión del taller.

### Durante el día

1. Cambia estados desde su chip.
2. Registra diagnóstico y productos/servicios en la ficha.
3. Factura solo desde la acción vinculada.

### Cierre

1. Revisa trabajos listos que aún no se entregan.
2. Revisa saldos pendientes.
3. Actualiza y confirma que no queden filas `REVISAR MODO`.

## 8. Dónde resolver cada tarea

| Necesitas | Acción correcta |
|---|---|
| Priorizar y registrar hitos | Combina `Activos`, `Vencidos` o `Sin pagar` con la búsqueda; usa el chip Estado para cada hito. |
| Revisar, editar o descargar una propuesta | El nombre abre directamente Productos y Servicios; la flecha derecha ofrece Descargar. |
| Revisar factura u otro contenido | Abre la factura desde su columna; para el resto, abre la fila y usa la ficha completa o el panel dividido. |
