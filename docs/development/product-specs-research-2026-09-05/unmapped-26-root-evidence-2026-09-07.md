# Verificación de 26 registros sin ficha asignados a Root

Se leyó la propuesta de Claude para los 33 registros, se comprobaron las claves,
IDs y familias contra el catálogo `934ce172…` y se consultó producción sólo para
los 26 asignados a Root. Los otros siete permanecen en el seguimiento de Claude.
El [JSON](unmapped-26-root-evidence-2026-09-07.json) conserva los originales
completos, la preimagen actual, fuentes, hashes y decisión de cada ID.

| Resultado de estos 26 | Cantidad |
| --- | ---: |
| Familia respaldada por imagen abierta; espera compuertas globales | 2 |
| Familia respaldada con conflicto de identidad comercial | 1 |
| Intervención de servicio respaldada por ventas | 2 |
| Identidad o clasificación de negocio sigue pendiente | 21 |

Los dos ejes `PO02770019255` y `PO02633001073` muestran eje de maza con conos y
contratuercas. Root abrió ambos archivos y verificó sus hashes y URL actual:
`hub_axle` representa el objeto. No se dedujeron diámetros, roscas, largos,
compatibilidad de mazas ni cantidad incluida desde las condiciones de compra.

La funda 17367 muestra «FUNDA PROTECTORA PARA BICICLETAS», VISION y el código
17367. Respalda `bike_protection`; BEST/VISION sigue sin resolver. Se conserva
la lectura impresa «200 x 58 x 100 cm» como evidencia pendiente de vinculación,
sin adjudicar ejes dimensionales ni convertir «todos los tamaños» en calce
universal. No se rellenó el producto.

Las ventas de NNV43 y NNV155 describen intervenciones de limpieza y retiro de
óxido. La corrección corresponde al contrato de servicios/materiales y requiere
revisar sus referencias antes de cambiar `product_type`. No se reescribieron
ventas ni se creó una ficha ficticia de disco o cadena para la mano de obra.

## Correcciones al dictamen independiente

- ALIEXPRESS y BETTABIKES no están demostrados como registros administrativos
  por aparecer como nombres en otros productos. Siguen pendientes.
- Los cinco inactivos permanecen dentro del saneamiento encargado por el dueño.
- M010 tiene dos ventas pagadas y una salida de stock como cámara más servicio.
  No puede excluirse el material físico ni partirse el paquete por conveniencia
  de la ficha.
- `Test` tiene una venta pagada y movimientos de stock. No es desechable por
  nombre; un movimiento refiere otra factura y requiere rastrear el linaje.
- NNV111 tiene movimientos de apertura y regularización, sin nota de crédito
  enlazada en lo consultado. Su título no autoriza asignar `tube` ni borrarlo.
- Que no exista aprobación OEM de un uso no autoriza escribirlo como prohibido
  en `not_for`. Falta de evidencia y exclusión explícita son estados distintos.
- La presencia/ausencia de eje no define por sí sola un pedalier completo. Un
  eje puede pertenecer a las bielas y los kits deben conservar la unidad vendida.
- El `source_preimage` de Claude es una proyección, no el registro literal
  completo que anuncia su documento. Sus valores retenidos sí coinciden con
  el origen; Root conserva aquí también los originales completos de sus 26 IDs.

## Límite de la consulta

La lectura cruzó `product_id` normalizado en líneas actuales de compras/ventas
y movimientos de stock, con tenant e IDs exactos. Cero coincidencias no prueba
ausencia en documentos archivados, texto libre, registros de taller o enlaces
antiguos. Los siguientes discriminantes quedan asignados a Codex/Claude; no a
entrada rutinaria del dueño. No hubo asignación, llenado, aprobación mecánica
ni cambio de tipo comercial.

SQL/recibos locales: `.tmp/db/unmapped-26-root-live-research.sql`,
`.tmp/db/unmapped-26-root-live-research.json` y
`.tmp/db/unmapped-root-business-movements.json`.
