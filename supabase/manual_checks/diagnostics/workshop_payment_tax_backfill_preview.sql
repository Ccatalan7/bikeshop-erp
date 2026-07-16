-- Read-only, aggregate-only production diagnostic for the explicit workshop
-- repair command. It intentionally returns no customer, bicycle, invoice, or
-- job identifiers.

with
linked_jobs as (
  select mj.*,
         si.tenant_id as invoice_tenant_id,
         si.customer_id as invoice_customer_id,
         si.total as invoice_total,
         si.iva_amount as invoice_iva,
         si.tax_treatment as invoice_tax_treatment,
         si.items as invoice_items
    from public.mechanic_jobs mj
    join public.sales_invoices si on si.id = mj.invoice_id
   where mj.deleted_at is null
),
invoice_line_counts as (
  select lj.id as job_id,
         jsonb_array_length(coalesce(lj.invoice_items, '[]'::jsonb)) as invoice_count,
         (select count(*)
            from public.mechanic_job_items mji
           where mji.job_id = lj.id) as job_count
    from linked_jobs lj
),
invoice_lines as (
  select lj.id as job_id, line.ordinality, line.value as line
    from linked_jobs lj
    cross join lateral jsonb_array_elements(
      coalesce(lj.invoice_items, '[]'::jsonb)
    ) with ordinality line(value, ordinality)
),
line_match_counts as (
  select il.job_id, il.ordinality, count(mji.id) as candidate_count
    from invoice_lines il
    left join public.mechanic_job_items mji
      on mji.job_id = il.job_id
     and lower(btrim(coalesce(mji.product_name, ''))) =
         lower(btrim(coalesce(il.line ->> 'product_name', '')))
     and mji.quantity = coalesce((il.line ->> 'quantity')::numeric, 0)
     and mji.unit_price = coalesce((il.line ->> 'unit_price')::numeric, 0)
     and (
       coalesce(il.line ->> 'product_id', '') = ''
       or il.line ->> 'product_id' in (
         coalesce(mji.product_id::text, ''),
         coalesce(mji.service_product_id::text, '')
       )
     )
     and (
       coalesce(il.line ->> 'job_bike_id', '') = ''
       or il.line ->> 'job_bike_id' = coalesce(mji.job_bike_id::text, '')
     )
   group by il.job_id, il.ordinality
),
metrics as (
  select 'active_linked_jobs'::text as metric, count(*)::bigint as value
    from linked_jobs
  union all
  select 'duplicate_invoice_links', count(*)
    from (
      select invoice_id
        from public.mechanic_jobs
       where invoice_id is not null and deleted_at is null
       group by invoice_id
      having count(*) > 1
    ) duplicates
  union all
  select 'job_invoice_tenant_or_customer_drift', count(*)
    from linked_jobs
   where tenant_id is distinct from invoice_tenant_id
      or customer_id is distinct from invoice_customer_id
  union all
  select 'job_invoice_total_drift', count(*)
    from linked_jobs
   where abs(coalesce(total_cost, 0) - coalesce(invoice_total, 0)) > 0.01
  union all
  select 'job_invoice_tax_drift', count(*)
    from linked_jobs
   where abs(coalesce(tax_amount, 0) - coalesce(invoice_iva, 0)) > 0.01
      or tax_treatment is distinct from invoice_tax_treatment
  union all
  select 'job_item_null_tenant', count(*)
    from public.mechanic_job_items
   where tenant_id is null
  union all
  select 'job_item_wrong_tenant', count(*)
    from public.mechanic_job_items mji
    join public.mechanic_jobs mj on mj.id = mji.job_id
   where mji.tenant_id is distinct from mj.tenant_id
  union all
  select 'job_bike_cost_drift', count(*)
    from public.mechanic_job_bikes mjb
   where abs(
     coalesce(mjb.subtotal, 0) - coalesce((
       select sum(mji.total_price)
         from public.mechanic_job_items mji
        where mji.job_bike_id = mjb.id
     ), 0)
   ) > 0.01
  union all
  select 'invoice_job_line_count_mismatch', count(*)
    from invoice_line_counts
   where invoice_count <> job_count
  union all
  select 'invoice_lines_without_stable_job_item_id', count(*)
    from invoice_lines il
   where coalesce(il.line ->> 'id', '') !~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or not exists (
        select 1
          from public.mechanic_job_items mji
         where mji.job_id = il.job_id
           and mji.id::text = il.line ->> 'id'
      )
  union all
  select 'invoice_lines_unique_deterministic_match', count(*)
    from line_match_counts
   where candidate_count = 1
  union all
  select 'invoice_lines_without_deterministic_match', count(*)
    from line_match_counts
   where candidate_count = 0
  union all
  select 'invoice_lines_with_ambiguous_match', count(*)
    from line_match_counts
   where candidate_count > 1
  union all
  select 'payment_invoice_tax_metadata_drift', count(*)
    from public.sales_payments p
    join public.sales_invoices si on si.id = p.invoice_id
   where p.tenant_id is distinct from si.tenant_id
      or p.tax_treatment is distinct from si.tax_treatment
      or abs(
        coalesce(p.net_amount, 0) - case
          when si.tax_treatment = 'tax_included'
            then public.clp_round(p.amount / 1.19)
          else p.amount end
      ) > 0.01
      or abs(
        coalesce(p.iva_amount, 0) - case
          when si.tax_treatment = 'tax_included'
            then p.amount - public.clp_round(p.amount / 1.19)
          else 0 end
      ) > 0.01
  union all
  select 'fractional_diagnosis_wear_values', count(*)
    from public.mechanic_job_bikes mjb
   where coalesce(
           mjb.diagnosis_sheet_data #>> '{drivetrain,chain_wear_percent}',
           ''
         ) ~ '^0\.[0-9]+$'
      or coalesce(
           mjb.diagnosis_sheet_data #>> '{front_brake,pad_wear_percent}',
           ''
         ) ~ '^0\.[0-9]+$'
      or coalesce(
           mjb.diagnosis_sheet_data #>> '{rear_brake,pad_wear_percent}',
           ''
         ) ~ '^0\.[0-9]+$'
)
select metric, value
  from metrics
 order by metric;
