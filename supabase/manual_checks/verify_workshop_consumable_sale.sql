-- Manual verification: selling a workshop consumable should
-- 1) create the commercial sales entry,
-- 2) create no stock movement,
-- 3) create no 1105 inventory credit,
-- 4) create no 5100 COGS debit.
--
-- IMPORTANT:
-- This script uses multiple statements on purpose.
-- The previous one-statement version could give a false negative for
-- journal_entries/journal_lines because the invoice insert and the trigger side
-- effects were being inspected inside the same top-level SQL statement.

drop table if exists tmp_wc_sale_test;

create temporary table tmp_wc_sale_test as
with params as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    'ca14c728-690d-4bee-9ffc-7aad041efb77'::uuid as product_id,
    'TEST-WC-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS') as invoice_number
),
product_data as (
  select
    p.id,
    p.tenant_id,
    p.sku,
    p.name,
    p.cost,
    p.price,
    p.purchase_treatment,
    p.track_stock,
    p.inventory_qty,
    p.stock_quantity
  from public.products p
  join params x
    on x.product_id = p.id
   and x.tenant_id = p.tenant_id
),
inserted_invoice as (
  insert into public.sales_invoices (
    tenant_id,
    invoice_number,
    customer_id,
    customer_name,
    date,
    due_date,
    status,
    subtotal,
    net_amount,
    iva_amount,
    total,
    paid_amount,
    balance,
    tax_treatment,
    items
  )
  select
    x.tenant_id,
    x.invoice_number,
    null,
    'TEST WORKSHOP CONSUMABLE',
    now(),
    now(),
    'confirmed',
    1000.00,
    1000.00,
    0.00,
    1000.00,
    0.00,
    1000.00,
    'no_tax',
    jsonb_build_array(
      jsonb_build_object(
        'product_id', p.id,
        'product_sku', p.sku,
        'product_name', p.name,
        'quantity', 1,
        'unit_price', 1000.00,
        'price', 1000.00,
        'cost', coalesce(p.cost, 0),
        'discount', 0,
        'is_service', false,
        'purchase_treatment', 'workshop_consumable'
      )
    )
  from params x
  join product_data p on true
  returning id, tenant_id, invoice_number, status, total, items, created_at
)
select * from inserted_invoice;

select jsonb_pretty(
  jsonb_build_object(
    'created_invoice',
    coalesce(
      (
        select to_jsonb(t)
        from tmp_wc_sale_test t
        limit 1
      ),
      '{}'::jsonb
    ),
    'product_after',
    coalesce(
      (
        select to_jsonb(p)
        from public.products p
        join tmp_wc_sale_test t
          on p.id = 'ca14c728-690d-4bee-9ffc-7aad041efb77'::uuid
         and p.tenant_id = t.tenant_id
        limit 1
      ),
      '{}'::jsonb
    ),
    'stock_movements_for_invoice',
    coalesce(
      (
        select jsonb_agg(to_jsonb(sm))
        from public.stock_movements sm
        join tmp_wc_sale_test t
          on sm.tenant_id = t.tenant_id
         and sm.reference = 'sales_invoice:' || t.id::text
      ),
      '[]'::jsonb
    ),
    'journal_entry',
    coalesce(
      (
        select to_jsonb(je)
        from public.journal_entries je
        join tmp_wc_sale_test t
          on je.tenant_id = t.tenant_id
         and je.source_module = 'sales_invoices'
         and je.source_reference = t.invoice_number
        order by je.created_at desc
        limit 1
      ),
      '{}'::jsonb
    ),
    'journal_lines',
    coalesce(
      (
        select jsonb_agg(to_jsonb(jl))
        from public.journal_lines jl
        where jl.entry_id in (
          select je.id
          from public.journal_entries je
          join tmp_wc_sale_test t
            on je.tenant_id = t.tenant_id
           and je.source_module = 'sales_invoices'
           and je.source_reference = t.invoice_number
        )
      ),
      '[]'::jsonb
    ),
    'checks',
    jsonb_build_object(
      'invoice_created',
      exists(select 1 from tmp_wc_sale_test),
      'line_snapshot_is_workshop_consumable',
      coalesce(
        (
          select (items -> 0 ->> 'purchase_treatment') = 'workshop_consumable'
          from tmp_wc_sale_test
          limit 1
        ),
        false
      ),
      'no_stock_movements_created',
      coalesce(
        (
          select count(*) = 0
          from public.stock_movements sm
          join tmp_wc_sale_test t
            on sm.tenant_id = t.tenant_id
           and sm.reference = 'sales_invoice:' || t.id::text
        ),
        true
      ),
      'product_still_zero_stock',
      coalesce(
        (
          select coalesce(p.inventory_qty, 0) = 0
             and coalesce(p.stock_quantity, 0) = 0
          from public.products p
          join tmp_wc_sale_test t
            on p.id = 'ca14c728-690d-4bee-9ffc-7aad041efb77'::uuid
           and p.tenant_id = t.tenant_id
          limit 1
        ),
        false
      ),
      'journal_has_receivable_1130',
      coalesce(
        (
          select count(*) filter (where jl.account_code = '1130') > 0
          from public.journal_lines jl
          where jl.entry_id in (
            select je.id
            from public.journal_entries je
            join tmp_wc_sale_test t
              on je.tenant_id = t.tenant_id
             and je.source_module = 'sales_invoices'
             and je.source_reference = t.invoice_number
          )
        ),
        false
      ),
      'journal_has_revenue_4100',
      coalesce(
        (
          select count(*) filter (where jl.account_code = '4100') > 0
          from public.journal_lines jl
          where jl.entry_id in (
            select je.id
            from public.journal_entries je
            join tmp_wc_sale_test t
              on je.tenant_id = t.tenant_id
             and je.source_module = 'sales_invoices'
             and je.source_reference = t.invoice_number
          )
        ),
        false
      ),
      'journal_has_no_inventory_credit_1105',
      coalesce(
        (
          select count(*) filter (
            where jl.account_code = '1105'
              and coalesce(jl.credit_amount, 0) > 0
          ) = 0
          from public.journal_lines jl
          where jl.entry_id in (
            select je.id
            from public.journal_entries je
            join tmp_wc_sale_test t
              on je.tenant_id = t.tenant_id
             and je.source_module = 'sales_invoices'
             and je.source_reference = t.invoice_number
          )
        ),
        true
      ),
      'journal_has_no_cogs_debit_5100',
      coalesce(
        (
          select count(*) filter (
            where jl.account_code = '5100'
              and coalesce(jl.debit_amount, 0) > 0
          ) = 0
          from public.journal_lines jl
          where jl.entry_id in (
            select je.id
            from public.journal_entries je
            join tmp_wc_sale_test t
              on je.tenant_id = t.tenant_id
             and je.source_module = 'sales_invoices'
             and je.source_reference = t.invoice_number
          )
        ),
        true
      ),
      'journal_is_balanced',
      coalesce(
        (
          select abs(coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)) < 0.01
          from public.journal_lines jl
          where jl.entry_id in (
            select je.id
            from public.journal_entries je
            join tmp_wc_sale_test t
              on je.tenant_id = t.tenant_id
             and je.source_module = 'sales_invoices'
             and je.source_reference = t.invoice_number
          )
        ),
        false
      )
    )
  )
) as verification_report;

-- Cleanup after test:
-- Replace the invoice number below with the one returned in created_invoice.invoice_number.
--
-- delete from public.sales_invoices
-- where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
--   and invoice_number = 'PEGA_AQUI_EL_INVOICE_NUMBER';