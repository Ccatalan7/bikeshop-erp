-- Manual verification: a mixed purchase invoice with one inventory item and one
-- workshop consumable, WITH IVA, should:
-- 1) increase stock only for the inventory item,
-- 2) leave workshop consumable stock unchanged,
-- 3) debit 1105 for the inventory subtotal,
-- 4) debit 5101 for the workshop consumable subtotal,
-- 5) debit 2120 for IVA,
-- 6) credit 2101 for the invoice total including IVA.
--
-- IMPORTANT:
-- This script uses multiple statements on purpose so the trigger-created stock
-- movements and journal entry are visible when inspected.
--
-- TAX SCOPE:
-- Purchase invoices treat IVA as ADDED on top of the subtotal.
-- This verifier mirrors the real purchase form behavior:
--   net_amount = subtotal
--   tax        = subtotal * 0.19
--   total      = subtotal + tax
--
-- NOTE:
-- In the standard purchase flow, stock is posted when the invoice reaches
-- 'received'. Accounting can exist from 'confirmed', but inventory should not
-- move until receipt.

drop table if exists tmp_wc_purchase_tax_context;
drop table if exists tmp_wc_purchase_tax_test;

create temporary table tmp_wc_purchase_tax_context as
with params as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    'TEST-WCP-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS') as invoice_number,
    0.19::numeric(12,4) as tax_rate,
    2::integer as inventory_qty,
    500.00::numeric(12,2) as inventory_unit_cost,
    1::integer as workshop_qty,
    2000.00::numeric(12,2) as workshop_unit_cost
),
workshop_product as (
  select
    p.id,
    p.tenant_id,
    p.sku,
    p.name,
    p.inventory_qty,
    p.stock_quantity,
    p.purchase_treatment,
    p.track_stock
  from public.products p
  join params x on x.tenant_id = p.tenant_id
  where p.id = coalesce(
    (
      select p_known.id
      from public.products p_known
      where p_known.id = 'ca14c728-690d-4bee-9ffc-7aad041efb77'::uuid
        and p_known.tenant_id = x.tenant_id
      limit 1
    ),
    (
      select p_any.id
      from public.products p_any
      where p_any.tenant_id = x.tenant_id
        and coalesce(p_any.purchase_treatment, 'inventory') = 'workshop_consumable'
        and coalesce(p_any.product_type, 'product') = 'product'
        and coalesce(p_any.is_set, false) = false
      order by p_any.updated_at desc nulls last, p_any.created_at desc nulls last
      limit 1
    )
  )
),
inventory_product as (
  select
    p.id,
    p.tenant_id,
    p.sku,
    p.name,
    p.inventory_qty,
    p.stock_quantity,
    p.purchase_treatment,
    p.track_stock
  from public.products p
  join params x on x.tenant_id = p.tenant_id
  where coalesce(p.purchase_treatment, 'inventory') = 'inventory'
    and coalesce(p.track_stock, true) = true
    and coalesce(p.product_type, 'product') = 'product'
    and coalesce(p.is_set, false) = false
    and p.id <> coalesce((select id from workshop_product limit 1), '00000000-0000-0000-0000-000000000000'::uuid)
  order by p.updated_at desc nulls last, p.created_at desc nulls last
  limit 1
)
select
  x.tenant_id,
  x.invoice_number,
  x.tax_rate,
  x.inventory_qty,
  x.inventory_unit_cost,
  (x.inventory_qty * x.inventory_unit_cost)::numeric(12,2) as inventory_subtotal,
  x.workshop_qty,
  x.workshop_unit_cost,
  (x.workshop_qty * x.workshop_unit_cost)::numeric(12,2) as workshop_subtotal,
  ((x.inventory_qty * x.inventory_unit_cost) + (x.workshop_qty * x.workshop_unit_cost))::numeric(12,2) as invoice_subtotal,
  round((((x.inventory_qty * x.inventory_unit_cost) + (x.workshop_qty * x.workshop_unit_cost)) * x.tax_rate), 2)::numeric(12,2) as invoice_tax,
  round((((x.inventory_qty * x.inventory_unit_cost) + (x.workshop_qty * x.workshop_unit_cost)) * (1 + x.tax_rate)), 2)::numeric(12,2) as invoice_total,
  ip.id as inventory_product_id,
  ip.sku as inventory_product_sku,
  ip.name as inventory_product_name,
  coalesce(ip.inventory_qty, 0) as inventory_before_inventory_qty,
  coalesce(ip.stock_quantity, 0) as inventory_before_stock_qty,
  wp.id as workshop_product_id,
  wp.sku as workshop_product_sku,
  wp.name as workshop_product_name,
  coalesce(wp.inventory_qty, 0) as workshop_before_inventory_qty,
  coalesce(wp.stock_quantity, 0) as workshop_before_stock_qty
from params x
left join inventory_product ip on true
left join workshop_product wp on true;

create temporary table tmp_wc_purchase_tax_test as
with inserted_invoice as (
  insert into public.purchase_invoices (
    tenant_id,
    invoice_number,
    supplier_id,
    supplier_name,
    date,
    due_date,
    status,
    subtotal,
    net_amount,
    tax_treatment,
    tax,
    total,
    paid_amount,
    balance,
    items
  )
  select
    c.tenant_id,
    c.invoice_number,
    null,
    'TEST MIXED WORKSHOP PURCHASE WITH IVA',
    now(),
    now(),
    'received',
    c.invoice_subtotal,
    c.invoice_subtotal,
    'tax_included',
    c.invoice_tax,
    c.invoice_total,
    0.00,
    c.invoice_total,
    jsonb_build_array(
      jsonb_build_object(
        'product_id', c.inventory_product_id,
        'product_sku', c.inventory_product_sku,
        'product_name', c.inventory_product_name,
        'quantity', c.inventory_qty,
        'unit_cost', c.inventory_unit_cost,
        'discount', 0,
        'purchase_treatment', 'inventory'
      ),
      jsonb_build_object(
        'product_id', c.workshop_product_id,
        'product_sku', c.workshop_product_sku,
        'product_name', c.workshop_product_name,
        'quantity', c.workshop_qty,
        'unit_cost', c.workshop_unit_cost,
        'discount', 0,
        'purchase_treatment', 'workshop_consumable'
      )
    )
  from tmp_wc_purchase_tax_context c
  where c.inventory_product_id is not null
    and c.workshop_product_id is not null
  returning id, tenant_id, invoice_number, status, subtotal, tax, total, items, created_at
)
select * from inserted_invoice;

select jsonb_pretty(
  jsonb_build_object(
    'selected_products',
    coalesce(
      (
        select to_jsonb(c)
        from tmp_wc_purchase_tax_context c
        limit 1
      ),
      '{}'::jsonb
    ),
    'created_invoice',
    coalesce(
      (
        select to_jsonb(t)
        from tmp_wc_purchase_tax_test t
        limit 1
      ),
      '{}'::jsonb
    ),
    'inventory_product_after',
    coalesce(
      (
        select to_jsonb(p)
        from public.products p
        join tmp_wc_purchase_tax_context c
          on p.id = c.inventory_product_id
         and p.tenant_id = c.tenant_id
        limit 1
      ),
      '{}'::jsonb
    ),
    'workshop_product_after',
    coalesce(
      (
        select to_jsonb(p)
        from public.products p
        join tmp_wc_purchase_tax_context c
          on p.id = c.workshop_product_id
         and p.tenant_id = c.tenant_id
        limit 1
      ),
      '{}'::jsonb
    ),
    'stock_movements_for_invoice',
    coalesce(
      (
        select jsonb_agg(to_jsonb(sm) order by sm.created_at, sm.product_id)
        from public.stock_movements sm
        join tmp_wc_purchase_tax_test t
          on sm.tenant_id = t.tenant_id
         and sm.reference = 'purchase_invoice:' || t.id::text
      ),
      '[]'::jsonb
    ),
    'journal_entry',
    coalesce(
      (
        select to_jsonb(je)
        from public.journal_entries je
        join tmp_wc_purchase_tax_test t
          on je.tenant_id = t.tenant_id
         and je.source_module = 'purchase_invoices'
         and je.source_reference = t.invoice_number
        order by je.created_at desc
        limit 1
      ),
      '{}'::jsonb
    ),
    'journal_lines',
    coalesce(
      (
        select jsonb_agg(to_jsonb(jl) order by jl.account_code, jl.created_at)
        from public.journal_lines jl
        where jl.entry_id in (
          select je.id
          from public.journal_entries je
          join tmp_wc_purchase_tax_test t
            on je.tenant_id = t.tenant_id
           and je.source_module = 'purchase_invoices'
           and je.source_reference = t.invoice_number
        )
      ),
      '[]'::jsonb
    ),
    'checks',
    jsonb_build_object(
      'inventory_product_found',
      exists(
        select 1
        from tmp_wc_purchase_tax_context
        where inventory_product_id is not null
      ),
      'workshop_product_found',
      exists(
        select 1
        from tmp_wc_purchase_tax_context
        where workshop_product_id is not null
      ),
      'invoice_created',
      exists(select 1 from tmp_wc_purchase_tax_test),
      'tax_snapshot_ok',
      coalesce(
        (
          select tax = c.invoice_tax
             and total = c.invoice_total
             and subtotal = c.invoice_subtotal
             and (select tax_treatment from public.purchase_invoices where id = t.id) = 'tax_included'
          from tmp_wc_purchase_tax_test t
          join tmp_wc_purchase_tax_context c
            on c.tenant_id = t.tenant_id
          limit 1
        ),
        false
      ),
      'inventory_line_snapshot_ok',
      coalesce(
        (
          select (items -> 0 ->> 'purchase_treatment') = 'inventory'
          from tmp_wc_purchase_tax_test
          limit 1
        ),
        false
      ),
      'workshop_line_snapshot_ok',
      coalesce(
        (
          select (items -> 1 ->> 'purchase_treatment') = 'workshop_consumable'
          from tmp_wc_purchase_tax_test
          limit 1
        ),
        false
      ),
      'inventory_stock_increased',
      coalesce(
        (
          select coalesce(p.inventory_qty, 0) = c.inventory_before_inventory_qty + c.inventory_qty
             and coalesce(p.stock_quantity, 0) = c.inventory_before_stock_qty + c.inventory_qty
          from public.products p
          join tmp_wc_purchase_tax_context c
            on p.id = c.inventory_product_id
           and p.tenant_id = c.tenant_id
          limit 1
        ),
        false
      ),
      'workshop_stock_unchanged',
      coalesce(
        (
          select coalesce(p.inventory_qty, 0) = c.workshop_before_inventory_qty
             and coalesce(p.stock_quantity, 0) = c.workshop_before_stock_qty
          from public.products p
          join tmp_wc_purchase_tax_context c
            on p.id = c.workshop_product_id
           and p.tenant_id = c.tenant_id
          limit 1
        ),
        false
      ),
      'only_inventory_stock_movement_created',
      coalesce(
        (
          select count(*) filter (
                   where sm.product_id = c.inventory_product_id and sm.type = 'IN'
                 ) = 1
             and count(*) filter (where sm.product_id = c.workshop_product_id) = 0
          from public.stock_movements sm
          join tmp_wc_purchase_tax_test t
            on sm.tenant_id = t.tenant_id
           and sm.reference = 'purchase_invoice:' || t.id::text
          join tmp_wc_purchase_tax_context c
            on c.tenant_id = t.tenant_id
        ),
        false
      ),
      'journal_has_inventory_debit_1105',
      coalesce(
        (
          select count(*) filter (
                   where jl.account_code = '1105'
                     and abs(coalesce(jl.debit_amount, 0) - c.inventory_subtotal) < 0.01
                 ) > 0
          from public.journal_lines jl
          join tmp_wc_purchase_tax_context c on true
          where jl.entry_id in (
            select je.id
            from public.journal_entries je
            join tmp_wc_purchase_tax_test t
              on je.tenant_id = t.tenant_id
             and je.source_module = 'purchase_invoices'
             and je.source_reference = t.invoice_number
          )
        ),
        false
      ),
      'journal_has_workshop_debit_5101',
      coalesce(
        (
          select count(*) filter (
                   where jl.account_code = '5101'
                     and abs(coalesce(jl.debit_amount, 0) - c.workshop_subtotal) < 0.01
                 ) > 0
          from public.journal_lines jl
          join tmp_wc_purchase_tax_context c on true
          where jl.entry_id in (
            select je.id
            from public.journal_entries je
            join tmp_wc_purchase_tax_test t
              on je.tenant_id = t.tenant_id
             and je.source_module = 'purchase_invoices'
             and je.source_reference = t.invoice_number
          )
        ),
        false
      ),
      'journal_has_iva_debit_2120',
      coalesce(
        (
          select count(*) filter (
                   where jl.account_code = '2120'
                     and abs(coalesce(jl.debit_amount, 0) - c.invoice_tax) < 0.01
                 ) > 0
          from public.journal_lines jl
          join tmp_wc_purchase_tax_context c on true
          where jl.entry_id in (
            select je.id
            from public.journal_entries je
            join tmp_wc_purchase_tax_test t
              on je.tenant_id = t.tenant_id
             and je.source_module = 'purchase_invoices'
             and je.source_reference = t.invoice_number
          )
        ),
        false
      ),
      'journal_has_payable_credit_2101',
      coalesce(
        (
          select count(*) filter (
                   where jl.account_code = '2101'
                     and abs(coalesce(jl.credit_amount, 0) - c.invoice_total) < 0.01
                 ) > 0
          from public.journal_lines jl
          join tmp_wc_purchase_tax_context c on true
          where jl.entry_id in (
            select je.id
            from public.journal_entries je
            join tmp_wc_purchase_tax_test t
              on je.tenant_id = t.tenant_id
             and je.source_module = 'purchase_invoices'
             and je.source_reference = t.invoice_number
          )
        ),
        false
      ),
      'journal_entry_balanced',
      coalesce(
        (
          select abs(coalesce(je.total_debit, 0) - coalesce(je.total_credit, 0)) < 0.01
          from public.journal_entries je
          join tmp_wc_purchase_tax_test t
            on je.tenant_id = t.tenant_id
           and je.source_module = 'purchase_invoices'
           and je.source_reference = t.invoice_number
          order by je.created_at desc
          limit 1
        ),
        false
      )
    )
  )
);