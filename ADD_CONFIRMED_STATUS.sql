-- Add 'confirmed' status to sales_invoices table constraint
-- Lines 3047-3055 from core_schema.sql

-- Drop existing constraint
alter table sales_invoices drop constraint if exists sales_invoices_status_check;

-- Add new constraint with confirmed status
alter table sales_invoices add constraint sales_invoices_status_check
  check (lower(status) = any (array[
    'draft','borrador',
    'sent','enviado','enviada','emitido','emitida','issued',
    'confirmed','confirmado','confirmada',
    'paid','pagado','pagada',
    'overdue','vencido','vencida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  ]));
