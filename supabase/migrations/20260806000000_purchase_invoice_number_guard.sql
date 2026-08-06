-- 20260806000000_purchase_invoice_number_guard.sql
--
-- Por qué existe: el flujo «Compras del día» de AliExpress deriva el número
-- de factura del día del pedido (AE060426 = 06/04/26). Re-ejecutar el mismo
-- día —cosa fácil: basta repetir la importación— regeneraba el mismo número
-- y NADA impedía guardar una segunda factura idéntica: sin restricción en la
-- base y sin validación en el cliente (verificado 2026-08-05: cero unique
-- constraints sobre purchase_invoices). Una factura duplicada corrompe
-- compras, inventario y contabilidad a la vez.
--
-- El candado va donde no se puede esquivar: la base. Único por tenant,
-- proveedor y número, sólo cuando hay número real — los borradores sin número
-- no se bloquean entre sí. Verificado antes de crear: cero duplicados
-- existentes en producción.
--
-- Estado de despliegue: aplicada a producción el 2026-08-05 vía
-- `scripts/db/query.sh production --write --file` y verificada con read-back.

create unique index if not exists uq_purchase_invoices_supplier_number
  on public.purchase_invoices (tenant_id, supplier_id, invoice_number)
  where coalesce(trim(invoice_number), '') <> '';
