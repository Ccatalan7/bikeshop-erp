-- Read-only certification audit for POS, Quick Sale, ecommerce, and legacy order writers.
-- This file intentionally performs no updates, inserts, deletes, or DDL.

\pset pager off
\set ON_ERROR_STOP on

select 'sales_invoices_by_source_status' as audit_section;
select
  coalesce(source, '<legacy-null>') as source,
  lower(status) as status,
  count(*) as invoice_count,
  sum(total) as invoiced_total,
  sum(paid_amount) as recorded_paid,
  sum(balance) as recorded_balance
from public.sales_invoices
group by coalesce(source, '<legacy-null>'), lower(status)
order by source, status;

select 'sales_channel_trace_coverage' as audit_section;
select
  coalesce(invoice.source, '<legacy-null>') as source,
  count(*) as invoice_count,
  count(*) filter (where operation.document_id is not null) as invoices_with_trace,
  count(*) filter (where movement.source_document_id is not null) as invoices_with_linked_movement,
  count(*) filter (where journal.source_document_id is not null) as invoices_with_linked_journal
from public.sales_invoices invoice
left join lateral (
  select operation.document_id
  from public.inventory_accounting_operations operation
  where operation.tenant_id = invoice.tenant_id
    and operation.document_type = 'sales_invoice'
    and operation.document_id = invoice.id
  limit 1
) operation on true
left join lateral (
  select movement.source_document_id
  from public.stock_movements movement
  where movement.tenant_id = invoice.tenant_id
    and movement.source_document_type = 'sales_invoice'
    and movement.source_document_id = invoice.id
  limit 1
) movement on true
left join lateral (
  select journal.source_document_id
  from public.journal_entries journal
  where journal.tenant_id = invoice.tenant_id
    and journal.source_document_type = 'sales_invoice'
    and journal.source_document_id = invoice.id
  limit 1
) journal on true
group by coalesce(invoice.source, '<legacy-null>')
order by source;

select 'possible_channel_retry_duplicates' as audit_section;
select
  tenant_id,
  source,
  customer_id,
  total,
  date_trunc('minute', created_at) as created_minute,
  count(*) as candidate_count,
  array_agg(invoice_number order by created_at) as invoice_numbers
from public.sales_invoices
where source in ('pos', 'quick_sale', 'ecommerce')
group by tenant_id, source, customer_id, total, date_trunc('minute', created_at)
having count(*) > 1
order by created_minute desc;

select 'online_order_status_summary' as audit_section;
select
  status,
  payment_status,
  payment_method,
  count(*) as order_count,
  sum(total) as order_total
from public.online_orders
group by status, payment_status, payment_method
order by status, payment_status, payment_method;

select 'online_order_link_integrity' as audit_section;
select
  count(*) as total_orders,
  count(*) filter (where sales_invoice_id is not null) as linked_orders,
  count(*) filter (where sales_invoice_id is not null and invoice.id is null) as dangling_invoice_links,
  count(*) filter (where payment_status = 'paid' and sales_invoice_id is null) as paid_without_invoice,
  count(*) filter (
    where payment_status = 'paid'
      and invoice.id is not null
      and lower(invoice.status) not in ('paid', 'pagado', 'pagada')
  ) as paid_order_invoice_not_paid,
  count(*) filter (
    where orders.status = 'cancelled'
      and orders.sales_invoice_id is not null
  ) as cancelled_order_preserving_invoice,
  count(*) filter (
    where orders.status = 'cancelled'
      and orders.sales_invoice_id is null
  ) as cancelled_order_without_invoice
from public.online_orders orders
left join public.sales_invoices invoice
  on invoice.id = orders.sales_invoice_id
 and invoice.tenant_id = orders.tenant_id;

select 'online_order_duplicate_invoice_links' as audit_section;
select tenant_id, sales_invoice_id, count(*) as linked_order_count,
       array_agg(order_number order by created_at) as order_numbers
from public.online_orders
where sales_invoice_id is not null
group by tenant_id, sales_invoice_id
having count(*) > 1;

select 'ecommerce_invoice_reconciliation' as audit_section;
select
  count(*) as ecommerce_invoice_count,
  count(*) filter (where orders.id is null) as ecommerce_invoice_without_order,
  count(*) filter (
    where lower(invoice.status) in ('confirmed', 'confirmado', 'confirmada', 'paid', 'pagado', 'pagada')
      and not exists (
        select 1 from public.stock_movements movement
        where movement.tenant_id = invoice.tenant_id
          and (
            (movement.source_document_type = 'sales_invoice' and movement.source_document_id = invoice.id)
            or movement.reference = invoice.invoice_number
          )
      )
  ) as posted_without_stock_movement,
  count(*) filter (
    where lower(invoice.status) in ('confirmed', 'confirmado', 'confirmada', 'paid', 'pagado', 'pagada')
      and not exists (
        select 1 from public.journal_entries journal
        where journal.tenant_id = invoice.tenant_id
          and (
            (journal.source_document_type = 'sales_invoice' and journal.source_document_id = invoice.id)
            or journal.source_reference = invoice.invoice_number
          )
      )
  ) as posted_without_journal,
  count(*) filter (
    where orders.payment_status = 'paid'
      and not exists (
        select 1 from public.sales_payments payment
        where payment.invoice_id = invoice.id
          and payment.deleted_at is null
      )
  ) as paid_order_without_active_payment
from public.sales_invoices invoice
left join public.online_orders orders
  on orders.tenant_id = invoice.tenant_id
 and orders.sales_invoice_id = invoice.id
where invoice.source = 'ecommerce';

select 'online_order_amount_integrity' as audit_section;
select
  count(*) filter (where abs(orders.total - coalesce(items.items_total, 0)) > 0.01) as order_item_total_mismatches,
  count(*) filter (
    where invoice.id is not null
      and abs(orders.total - invoice.total) > 0.01
  ) as order_invoice_total_mismatches,
  count(*) filter (
    where invoice.id is not null
      and abs(invoice.paid_amount - coalesce(payments.payment_total, 0)) > 0.01
  ) as invoice_payment_total_mismatches
from public.online_orders orders
left join public.sales_invoices invoice on invoice.id = orders.sales_invoice_id
left join lateral (
  select sum(item.subtotal) as items_total
  from public.online_order_items item
  where item.order_id = orders.id
) items on true
left join lateral (
  select sum(payment.amount) as payment_total
  from public.sales_payments payment
  where payment.invoice_id = invoice.id
    and payment.deleted_at is null
) payments on true;

select 'legacy_direct_order_writer_usage' as audit_section;
select
  (select count(*) from public.orders) as legacy_orders,
  (select count(*) from public.order_items) as legacy_order_items,
  (select max(created_at) from public.orders) as latest_legacy_order,
  (select max(created_at) from public.order_items) as latest_legacy_item;

select 'legacy_order_trigger_definition' as audit_section;
select
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
from information_schema.triggers
where event_object_schema = 'public'
  and event_object_table = 'order_items'
order by trigger_name, event_manipulation;

select 'online_function_execution_privileges' as audit_section;
select
  routine_name,
  grantee,
  privilege_type
from information_schema.routine_privileges
where specific_schema = 'public'
  and routine_name in (
    'create_public_online_order',
    'process_online_order',
    'cancel_online_order',
    'confirm_online_order_payment'
  )
order by routine_name, grantee;
