# Manual de usuario - Sitio Web y venta online

**Versión:** 1.0 · **Área:** Sitio Web · **Lectura estimada:** 9 minutos

El módulo Sitio Web reúne contenido, catálogo, pedidos e integraciones. Su
objetivo es que lo publicado, lo vendido y lo registrado en el ERP sean una
misma realidad, sin mantener datos paralelos.

## 1. Mapa del módulo

| Espacio | Para qué sirve |
|---|---|
| Contenido y estructura | Páginas, navegación, botones, rutas y campañas. |
| Catálogo y ventas | Visibilidad, productos destacados y pedidos online. |
| Configuración y alcance | Datos públicos, reglas de compra, integraciones y SEO. |

Usa **Vista previa** para revisar la experiencia sin editar. Usa **Abrir editor
visual** para cambiar la página y guarda desde el control global del editor.

## 2. Publicar con seguridad

Antes de habilitar un producto confirma:

1. Nombre, SKU, precio e imagen correctos.
2. Stock real o política explícita de no seguimiento.
3. Clasificación tributaria: Afecto IVA 19% o Exento.
4. Categoría y visibilidad web.
5. Descripción y atributos coherentes con el producto entregado.

La visibilidad del sitio y la elegibilidad para Google Merchant son controles
relacionados, pero distintos. Un producto puede quedar visible para corregirlo
sin ser enviado a Merchant cuando le falta información obligatoria.

## 3. Qué ocurre cuando un cliente compra

```flow
Catálogo -> Carrito -> Checkout seguro -> Pedido + reserva -> Validar pago y Venta ERP -> Preparación -> Entrega
```

En el checkout el servidor vuelve a calcular productos, IVA, descuentos y
despacho. El pedido reserva las unidades con seguimiento sin descontar stock
físico. La reserva se consume cuando la venta ERP se contabiliza y genera el
movimiento de stock; se libera al cancelar o vencer. Servicios e ítems sin
seguimiento no generan una reserva física.

<!-- pagebreak -->

### Mercado Pago

- La preferencia se crea con el total guardado en el servidor.
- El webhook confirma el pago automáticamente.
- Si Mercado Pago sigue pendiente, espera o concilia el webhook. No uses
  **Confirmar** como sustituto de la validación del pago.
- Si el pago fue recibido pero falló stock/contabilidad, el pedido muestra
  `Revisar`; el cobro no desaparece.

### Transferencia

- Confirma solo después de comprobar el abono en el banco.
- Registra referencia y fecha efectiva desde el chip Pago.
- El comprobante de transferencia no sustituye la boleta.

## 4. Trabajar con Pedidos online

La tabla permite buscar, ordenar y redimensionar columnas. Haz clic en una fila
para abrir el inspector sin perder el contexto.

| Elemento | Acción del usuario |
|---|---|
| Estado | Usa el chip para avanzar únicamente al siguiente estado permitido. |
| Pago | Mercado Pago es automático; transferencia permite confirmación verificada. |
| Venta ERP | Abre la venta que controla stock, IVA, pagos y contabilidad. |
| Inspector > Documentos | Muestra evidencia fiscal verificable y, cuando fue registrado y asociado al pedido, el comprobante de Mercado Pago. |
| Inspector > Comunicaciones | Muestra entrega o rebote de emails; no reescribe el historial. |

### Flujo operativo

```flow
Pendiente -> Confirmado -> En proceso -> Hito según modalidad -> Entregado
```

Desde `En proceso`, el camino exacto es **Listo para retiro**, seguido de
**Entregado**, para **Retiro**; o **Enviado**, seguido de **Entregado**, para
**Despacho**. Los estados terminales no vuelven hacia atrás mediante edición
manual. Una devolución o cancelación pagada usa el flujo formal de corrección y
reembolso.

`Confirmado` indica que existe una venta ERP vinculada; no significa `Pagado`.
En transferencias puede aparecer automáticamente. Antes de avanzar a **En
proceso**, comprueba Pago = Pagado, venta ERP vinculada, modalidad de entrega y
ausencia de alertas `Revisar` o `Conciliar`. Para **Enviado**, registra
transportista y/o seguimiento: el sistema exige evidencia de despacho.

<!-- pagebreak -->

## 5. Correcciones y excepciones

- **Pedido impago:** puede cancelarse; libera reserva y vence enlaces de pago.
- **Pedido pagado:** no se cancela como si nada hubiera ocurrido. Usa corrección
  y reembolso para preservar stock, contabilidad y trazabilidad.
- **Pago confirmado con acción pendiente:** abre `Revisar`; reintenta solo el
  efecto interno permitido. No vuelvas a cobrar.
- **Sin stock al procesar:** no edites líneas ni stock manualmente. Revisa
  `Revisar/Conciliar` y resuelve mediante reposición o corrección/reembolso
  formal. Pedidos online todavía no ofrece una acción de sustitución.
- **Email rebotado:** usa teléfono u otro canal y conserva el rebote como
  evidencia. Pedidos online no permite reenviarlo a otro destinatario.

## 6. Emails y documentos

Los cambios relevantes generan emails desde `ventas@vinabike.cl`: pedido
recibido, pago confirmado, preparación, retiro/despacho, entrega, cancelación o
reembolso según corresponda. La entrega es asíncrona; consulta su resultado en
**Inspector > Comunicaciones**.

```flow
Evento del pedido -> Cola segura -> Resend -> Entrega / Rebote -> Evidencia en inspector
```

- **Resumen del pedido:** informa productos y totales; no acredita pago ni es
  documento tributario.
- **Comprobante de Mercado Pago:** acredita el pago; en la integración actual
  no es boleta ni factura. Si no aparece en Documentos, eso por sí solo no
  demuestra que falte el pago: contrasta el chip Pago con la Venta ERP y abre
  `Conciliar` si existe una diferencia.
- **Boleta electrónica (DTE):** el ERP actual no la emite. Solo puede mostrarla
  si un emisor autorizado registra folio y artefacto oficial verificable.
- **Venta ERP:** es respaldo interno y no constituye documento tributario.
- **Factura:** no se ofrece en el checkout B2C actual.

## 7. Google Merchant y coherencia pública

Merchant compara el feed con la página, carrito y checkout. Mantén idénticos:

- precio y moneda;
- disponibilidad;
- identidad, dirección y contacto;
- despacho, devoluciones y privacidad;
- nombre, marca y atributos del producto.

El feed se actualiza desde el ERP. No corrijas diferencias editando Merchant a
mano si la fuente sigue equivocada: corrige primero el producto o configuración
canónica.

## 8. Rutina recomendada

| Momento | Revisión mínima |
|---|---|
| Cada mañana | Revisa pendientes/excepciones, pagos manuales y entregas comprometidas. |
| Antes de publicar | Vista previa; enlaces; producto, precio, IVA y stock; guarda y reabre. |
| Al cerrar | Actualiza entregas y emails fallidos; concilia todo pago recibido. |
