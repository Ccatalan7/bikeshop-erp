-- Canonical one-row purchase-invoice list projection.
--
-- Financial invoice fields and physical receipt fulfillment are deliberately
-- read in one database snapshot so the list never has to paint a financial
-- status first and replace it after a second receipt query.

begin;

create or replace view public.purchase_invoice_list_read_model
with (security_invoker = true)
as
with invoice_lines as (
  select
    invoice.id as purchase_invoice_id,
    (source.ordinality - 1)::integer as source_line_index,
    round(
      coalesce(nullif(source.item ->> 'quantity', '')::numeric, 0)
    )::integer as expected_quantity
  from public.purchase_invoices invoice
  cross join lateral jsonb_array_elements(
    coalesce(invoice.items, '[]'::jsonb)
  )
    with ordinality as source(item, ordinality)
),
posted_line_totals as (
  select
    receipt_line.purchase_invoice_id,
    receipt_line.source_line_index,
    coalesce(sum(receipt_line.accepted_quantity), 0)::integer
      as accepted_quantity,
    coalesce(sum(
      receipt_line.damaged_quantity
        + receipt_line.rejected_quantity
        + receipt_line.shortage_quantity
    ), 0)::integer as difference_quantity
  from public.purchase_receipt_lines receipt_line
  join public.purchase_receipts receipt
    on receipt.id = receipt_line.receipt_id
   and receipt.tenant_id = receipt_line.tenant_id
   and receipt.status = 'posted'
  group by
    receipt_line.purchase_invoice_id,
    receipt_line.source_line_index
),
posted_receipt_totals as (
  select
    receipt_line.purchase_invoice_id,
    count(distinct receipt.id)::integer as receipt_count,
    max(receipt.received_at) as latest_received_at,
    coalesce(sum(
      receipt_line.damaged_quantity
        + receipt_line.rejected_quantity
        + receipt_line.shortage_quantity
    ), 0)::integer as reported_difference_quantity
  from public.purchase_receipt_lines receipt_line
  join public.purchase_receipts receipt
    on receipt.id = receipt_line.receipt_id
   and receipt.tenant_id = receipt_line.tenant_id
   and receipt.status = 'posted'
  group by receipt_line.purchase_invoice_id
),
effective_resolution_totals as (
  select
    allocation.purchase_invoice_id,
    allocation.source_line_index,
    coalesce(sum(allocation.resolved_quantity), 0)::integer
      as resolved_difference_quantity,
    coalesce(sum(allocation.resolved_quantity) filter (
      where allocation.outcome in ('credit_note', 'documented_loss')
    ), 0)::integer as nonphysical_resolution_quantity
  from public.purchase_receipt_resolution_allocation_view allocation
  where allocation.is_effective
    and allocation.outcome in (
      'credit_note',
      'documented_loss',
      'later_delivery'
    )
  group by
    allocation.purchase_invoice_id,
    allocation.source_line_index
),
line_fulfillment as (
  select
    invoice_line.purchase_invoice_id,
    invoice_line.source_line_index,
    invoice_line.expected_quantity,
    least(
      greatest(coalesce(posted.accepted_quantity, 0), 0),
      invoice_line.expected_quantity
    )::integer as accepted_quantity,
    greatest(coalesce(posted.difference_quantity, 0), 0)::integer
      as difference_quantity,
    greatest(
      coalesce(resolution.resolved_difference_quantity, 0),
      0
    )::integer as raw_resolved_difference_quantity,
    greatest(
      coalesce(resolution.nonphysical_resolution_quantity, 0),
      0
    )::integer as raw_nonphysical_resolution_quantity
  from invoice_lines invoice_line
  left join posted_line_totals posted
    on posted.purchase_invoice_id = invoice_line.purchase_invoice_id
   and posted.source_line_index = invoice_line.source_line_index
  left join effective_resolution_totals resolution
    on resolution.purchase_invoice_id = invoice_line.purchase_invoice_id
   and resolution.source_line_index = invoice_line.source_line_index
),
line_fulfillment_totals as (
  select
    line.purchase_invoice_id,
    coalesce(sum(line.expected_quantity), 0)::integer
      as expected_quantity,
    coalesce(sum(line.accepted_quantity), 0)::integer
      as accepted_quantity,
    coalesce(sum(
      least(
        line.raw_resolved_difference_quantity,
        line.difference_quantity
      )
    ), 0)::integer as resolved_difference_quantity,
    coalesce(sum(
      least(
        line.raw_nonphysical_resolution_quantity,
        line.expected_quantity - line.accepted_quantity
      )
    ), 0)::integer as nonphysical_resolution_quantity
  from line_fulfillment line
  group by line.purchase_invoice_id
),
raw_fulfillment as (
  select
    invoice.id as purchase_invoice_id,
    coalesce(line_totals.expected_quantity, 0)::integer
      as expected_quantity,
    coalesce(line_totals.accepted_quantity, 0)::integer
      as accepted_quantity,
    coalesce(receipt_totals.reported_difference_quantity, 0)::integer
      as reported_difference_quantity,
    coalesce(line_totals.resolved_difference_quantity, 0)::integer
      as resolved_difference_quantity,
    coalesce(line_totals.nonphysical_resolution_quantity, 0)::integer
      as nonphysical_resolution_quantity,
    greatest(
      coalesce(line_totals.expected_quantity, 0)
        - coalesce(line_totals.accepted_quantity, 0),
      0
    )::integer as physical_remaining_quantity,
    coalesce(receipt_totals.receipt_count, 0)::integer as receipt_count,
    receipt_totals.latest_received_at,
    (
      coalesce(receipt_totals.receipt_count, 0) = 0
      and (
        invoice.status = 'received'
        or invoice.received_date is not null
      )
    ) as legacy_received
  from public.purchase_invoices invoice
  left join line_fulfillment_totals line_totals
    on line_totals.purchase_invoice_id = invoice.id
  left join posted_receipt_totals receipt_totals
    on receipt_totals.purchase_invoice_id = invoice.id
),
derived_fulfillment as (
  select
    raw.*,
    greatest(
      raw.physical_remaining_quantity
        - raw.nonphysical_resolution_quantity,
      0
    )::integer as remaining_quantity,
    greatest(
      raw.reported_difference_quantity
        - raw.resolved_difference_quantity,
      0
    )::integer as unresolved_difference_quantity
  from raw_fulfillment raw
)
select
  invoice.id,
  invoice.tenant_id,
  invoice.invoice_number,
  invoice.supplier_id,
  invoice.supplier_name,
  invoice.supplier_rut,
  invoice.date,
  invoice.due_date,
  invoice.status,
  invoice.subtotal,
  invoice.tax,
  invoice.total,
  invoice.net_amount,
  invoice.paid_amount,
  invoice.balance,
  invoice.supplier_refunded_amount,
  invoice.credited_amount,
  invoice.supplier_credit_balance,
  invoice.prepayment_model,
  invoice.sent_date,
  invoice.confirmed_date,
  invoice.received_date,
  invoice.paid_date,
  invoice.items,
  invoice.created_at,
  invoice.updated_at,
  case
    when fulfillment.legacy_received
      or (
        fulfillment.expected_quantity > 0
        and fulfillment.physical_remaining_quantity = 0
      )
      then 'complete'
    when fulfillment.expected_quantity > 0
      and fulfillment.remaining_quantity = 0
      and fulfillment.nonphysical_resolution_quantity > 0
      then 'closed_with_difference'
    when fulfillment.legacy_received
      or fulfillment.receipt_count > 0
      or fulfillment.accepted_quantity > 0
      or fulfillment.reported_difference_quantity > 0
      then 'open'
    else 'none'
  end::text as receipt_state,
  fulfillment.expected_quantity as receipt_expected_quantity,
  case
    when fulfillment.legacy_received
      then fulfillment.expected_quantity
    else fulfillment.accepted_quantity
  end::integer as receipt_accepted_quantity,
  fulfillment.reported_difference_quantity
    as receipt_reported_difference_quantity,
  fulfillment.resolved_difference_quantity
    as receipt_resolved_difference_quantity,
  fulfillment.nonphysical_resolution_quantity
    as receipt_nonphysical_resolution_quantity,
  fulfillment.unresolved_difference_quantity
    as receipt_unresolved_difference_quantity,
  case
    when fulfillment.legacy_received then 0
    else fulfillment.physical_remaining_quantity
  end::integer as receipt_physical_remaining_quantity,
  case
    when fulfillment.legacy_received then 0
    else fulfillment.remaining_quantity
  end::integer as receipt_remaining_quantity,
  fulfillment.receipt_count,
  fulfillment.latest_received_at as receipt_latest_received_at,
  fulfillment.legacy_received as receipt_legacy_received
from public.purchase_invoices invoice
join derived_fulfillment fulfillment
  on fulfillment.purchase_invoice_id = invoice.id;

revoke all on public.purchase_invoice_list_read_model
  from public, anon;
grant select on public.purchase_invoice_list_read_model
  to authenticated, service_role;

comment on view public.purchase_invoice_list_read_model is
  'Tenant-scoped purchase-invoice list projection with canonical posted-receipt and effective-resolution fulfillment derived in the same database snapshot.';

commit;
