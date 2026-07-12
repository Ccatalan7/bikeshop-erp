-- READ-ONLY: current linked-workshop invoice stock expectation versus movement net.
-- Expands product sets to their components and treats draft/sent/cancelled invoices
-- as non-posted. No statement mutates data.

with tenant as (
  select '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id
), linked as (
  select
    job.id as job_id,
    job.job_number,
    job.status as job_status,
    invoice.id as invoice_id,
    invoice.tenant_id,
    invoice.invoice_number,
    invoice.status as invoice_status,
    invoice.items,
    not (
      lower(coalesce(invoice.status, 'draft')) = any (array[
        'draft','borrador',
        'sent','enviado','enviada','issued','emitido','emitida',
        'cancelled','cancelado','cancelada','anulado','anulada'
      ])
    ) as is_posted
  from tenant
  join public.mechanic_jobs job on job.tenant_id = tenant.tenant_id
  join public.sales_invoices invoice
    on invoice.id = job.invoice_id
   and invoice.tenant_id = job.tenant_id
), raw_items as (
  select
    linked.job_id,
    linked.job_number,
    linked.job_status,
    linked.invoice_id,
    linked.invoice_number,
    linked.invoice_status,
    linked.is_posted,
    coalesce(
      nullif(item.value->>'product_id', '')::uuid,
      product_by_sku.id
    ) as product_id,
    coalesce(nullif(item.value->>'quantity', '')::numeric, 0)::integer as quantity,
    coalesce(nullif(item.value->>'purchase_treatment', ''), 'inventory') as purchase_treatment
  from linked
  cross join lateral jsonb_array_elements(coalesce(linked.items, '[]'::jsonb)) item(value)
  left join lateral (
    select product.id
    from public.products product
    where product.tenant_id = linked.tenant_id
      and product.sku = nullif(item.value->>'product_sku', '')
    order by product.id
    limit 1
  ) product_by_sku on true
), expected_expanded as (
  select
    item.job_id,
    item.job_number,
    item.job_status,
    item.invoice_id,
    item.invoice_number,
    item.invoice_status,
    case when product.is_set then component.component_product_id else product.id end as product_id,
    case
      when item.is_posted then
        item.quantity * case when product.is_set then component.quantity_in_set else 1 end
      else 0
    end as expected_net_out
  from raw_items item
  join public.products product
    on product.id = item.product_id
   and coalesce(product.is_service, false) = false
   and coalesce(product.track_stock, true) = true
  left join public.product_set_components component
    on product.is_set
   and component.set_product_id = product.id
  where item.quantity > 0
    and item.purchase_treatment <> 'workshop_consumable'
    and (not product.is_set or component.component_product_id is not null)
), expected as (
  select
    job_id,
    job_number,
    job_status,
    invoice_id,
    invoice_number,
    invoice_status,
    product_id,
    sum(expected_net_out)::numeric as expected_net_out
  from expected_expanded
  group by job_id, job_number, job_status, invoice_id, invoice_number, invoice_status, product_id
), actual as (
  select
    linked.job_id,
    linked.job_number,
    linked.job_status,
    linked.invoice_id,
    linked.invoice_number,
    linked.invoice_status,
    movement.product_id,
    -sum(
      case
        when movement.type in ('OUT', 'TRANSFER_OUT') then -abs(movement.quantity)
        when movement.type in ('IN', 'TRANSFER_IN') then abs(movement.quantity)
        else movement.quantity
      end
    ) as actual_net_out
  from linked
  join public.stock_movements movement
    on movement.tenant_id = linked.tenant_id
   and movement.reference = 'sales_invoice:' || linked.invoice_id::text
  group by linked.job_id, linked.job_number, linked.job_status,
           linked.invoice_id, linked.invoice_number, linked.invoice_status, movement.product_id
), comparison as (
  select
    coalesce(expected.job_id, actual.job_id) as job_id,
    coalesce(expected.job_number, actual.job_number) as job_number,
    coalesce(expected.job_status, actual.job_status) as job_status,
    coalesce(expected.invoice_id, actual.invoice_id) as invoice_id,
    coalesce(expected.invoice_number, actual.invoice_number) as invoice_number,
    coalesce(expected.invoice_status, actual.invoice_status) as invoice_status,
    coalesce(expected.product_id, actual.product_id) as product_id,
    product.sku,
    product.name as product_name,
    coalesce(expected.expected_net_out, 0) as expected_net_out,
    coalesce(actual.actual_net_out, 0) as actual_net_out,
    coalesce(actual.actual_net_out, 0) - coalesce(expected.expected_net_out, 0) as variance
  from expected
  full join actual using (job_id, invoice_id, product_id)
  join public.products product
    on product.id = coalesce(expected.product_id, actual.product_id)
)
select jsonb_build_object(
  'generated_at', now(),
  'mode', 'read_only',
  'compared_product_rows', (select count(*) from comparison),
  'exact_rows', (select count(*) from comparison where variance = 0),
  'mismatch_rows', (select count(*) from comparison where variance <> 0),
  'affected_jobs', (select count(distinct job_id) from comparison where variance <> 0),
  'mismatches', (
    select coalesce(jsonb_agg(to_jsonb(row_data) order by row_data.job_number, row_data.sku), '[]'::jsonb)
    from comparison row_data
    where row_data.variance <> 0
  )
) as workshop_invoice_stock_reconciliation;
