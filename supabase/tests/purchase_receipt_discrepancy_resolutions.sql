begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(56);

select has_table(
  'public',
  'purchase_receipt_resolution_cases',
  'purchase receipt discrepancy cases are durable documents'
);
select has_table(
  'public',
  'purchase_receipt_resolution_allocations',
  'purchase receipt resolution allocations are durable evidence'
);
select has_view(
  'public',
  'purchase_receipt_resolution_case_view',
  'case view exposes effective resolution state'
);
select has_view(
  'public',
  'purchase_receipt_resolution_allocation_view',
  'allocation view exposes effective linked-document state'
);
select has_column(
  'public',
  'purchase_receipt_resolution_allocation_view',
  'purchase_credit_note_number',
  'allocation view matches the Dart credit-note link contract'
);
select has_column(
  'public',
  'purchase_receipt_resolution_allocation_view',
  'void_reason',
  'allocation view exposes the linked-document void reason'
);
select has_function(
  'public',
  'resolve_purchase_receipt_with_credit_note',
  array[
    'uuid',
    'jsonb',
    'timestamp with time zone',
    'text',
    'text',
    'text',
    'text'
  ],
  'credit-note resolution wrapper exists'
);
select has_function(
  'public',
  'resolve_purchase_receipt_with_documented_loss',
  array['uuid', 'jsonb', 'timestamp with time zone', 'text', 'text'],
  'documented-loss command exists'
);
select has_function(
  'public',
  'void_purchase_receipt_documented_loss',
  array['uuid', 'text', 'text'],
  'documented-loss reversal command exists'
);
select has_trigger(
  'public',
  'purchase_receipt_lines',
  'trg_purchase_receipt_line_00_guard_economic_quantity',
  'receipt accepted quantity is capped by effective economic resolutions'
);
select has_trigger(
  'public',
  'purchase_receipt_lines',
  'trg_purchase_receipt_line_10_create_resolution_cases',
  'receipt discrepancies automatically create cases'
);
select has_trigger(
  'public',
  'purchase_receipt_lines',
  'trg_purchase_receipt_line_20_allocate_later_delivery',
  'later accepted receipts automatically resolve oldest cases'
);
select has_trigger(
  'public',
  'purchase_receipts',
  'trg_prevent_receipt_void_with_active_resolutions',
  'source receipt void is guarded by active resolutions'
);
select has_trigger(
  'public',
  'purchase_invoices',
  'trg_guard_purchase_invoice_hard_delete',
  'purchase invoice hard deletion is limited to drafts'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.purchase_receipt_resolution_cases',
    'INSERT'
  ),
  'authenticated clients cannot insert cases directly'
);
select ok(
  not has_table_privilege(
    'authenticated',
    'public.purchase_receipt_resolution_allocations',
    'UPDATE'
  ),
  'authenticated clients cannot mutate allocations directly'
);
select ok(
  has_table_privilege(
    'authenticated',
    'public.purchase_receipt_resolution_case_view',
    'SELECT'
  ),
  'authenticated clients can read effective case state'
);

insert into public.tenants (id, shop_name)
values (
  '9a240000-0000-4000-8000-000000000001',
  'Purchase Receipt Resolution Test'
);

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values (
  '9a240000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'purchase-receipt-resolution@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type',
    'public_store_customer',
    'customer_tenant_id',
    '9a240000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);

insert into public.user_profiles (user_id, tenant_id, role)
values (
  '9a240000-0000-4000-8000-000000000099',
  '9a240000-0000-4000-8000-000000000001',
  'admin'
);

update auth.users
set raw_user_meta_data = raw_user_meta_data || jsonb_build_object(
  'tenant_id',
  '9a240000-0000-4000-8000-000000000001'
)
where id = '9a240000-0000-4000-8000-000000000099';

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '9a240000-0000-4000-8000-000000000099',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9a240000-0000-4000-8000-000000000099',
  true
);

insert into public.products (
  id,
  tenant_id,
  name,
  sku,
  price,
  cost,
  product_type,
  is_service,
  track_stock,
  inventory_qty,
  stock_quantity,
  min_stock_level,
  max_stock_level
) values (
  '9a240000-0000-4000-8000-000000000002',
  '9a240000-0000-4000-8000-000000000001',
  'Resolution Product',
  'RESOLUTION-001',
  2000,
  1000,
  'product',
  false,
  true,
  0,
  0,
  0,
  100
);

insert into public.purchase_invoices (
  id,
  tenant_id,
  invoice_number,
  supplier_name,
  status,
  subtotal,
  net_amount,
  tax,
  total,
  balance,
  items
) values (
  '9a240000-0000-4000-8000-000000000003',
  '9a240000-0000-4000-8000-000000000001',
  'FC-RESOLUTION-001',
  'Resolution Supplier',
  'draft',
  10500,
  10500,
  0,
  10500,
  10500,
  jsonb_build_array(
    jsonb_build_object(
      'line_id',
      'resolution-line-001',
      'product_id',
      '9a240000-0000-4000-8000-000000000002',
      'product_name',
      'Resolution Product',
      'product_sku',
      'RESOLUTION-001',
      'quantity',
      10,
      'unit_cost',
      1000,
      'discount',
      0,
      'purchase_treatment',
      'inventory',
      'is_service',
      false
    ),
    jsonb_build_object(
      'line_id',
      'resolution-line-002',
      'product_id',
      '9a240000-0000-4000-8000-000000000002',
      'product_name',
      'Resolution Workshop Consumable',
      'product_sku',
      'RESOLUTION-CONSUMABLE-001',
      'quantity',
      1,
      'unit_cost',
      500,
      'discount',
      0,
      'purchase_treatment',
      'workshop_consumable',
      'is_service',
      false
    )
  )
);

update public.purchase_invoices
set status = 'confirmed', confirmed_date = now()
where id = '9a240000-0000-4000-8000-000000000003';

select throws_ok(
  $$
    delete from public.purchase_invoices
    where id = '9a240000-0000-4000-8000-000000000003'
  $$,
  null::character(5),
  null,
  'a confirmed purchase invoice cannot erase accounting evidence'
);

insert into public.purchase_invoices (
  id,
  tenant_id,
  invoice_number,
  supplier_name,
  status,
  subtotal,
  net_amount,
  tax,
  total,
  balance,
  items
) values (
  '9a240000-0000-4000-8000-000000000004',
  '9a240000-0000-4000-8000-000000000001',
  'FC-DRAFT-DELETE-001',
  'Draft Delete Supplier',
  'draft',
  100,
  100,
  0,
  100,
  100,
  '[]'::jsonb
);
select lives_ok(
  $$
    delete from public.purchase_invoices
    where id = '9a240000-0000-4000-8000-000000000004'
  $$,
  'a true draft purchase invoice can still be hard-deleted'
);

insert into public.purchase_receipt_control_settings (
  tenant_id,
  control_mode,
  activated_at,
  activated_by
) values (
  '9a240000-0000-4000-8000-000000000001',
  'enforce',
  now(),
  '9a240000-0000-4000-8000-000000000099'
);
insert into public.purchase_credit_note_control_settings (
  tenant_id,
  control_mode,
  activated_at,
  activated_by
) values (
  '9a240000-0000-4000-8000-000000000001',
  'enforce',
  now(),
  '9a240000-0000-4000-8000-000000000099'
);

create temp table resolution_stock_baseline on commit drop as
select inventory_qty
from public.products
where id = '9a240000-0000-4000-8000-000000000002';

create temp table source_receipt_result on commit drop as
select public.create_purchase_goods_receipt(
  '9a240000-0000-4000-8000-000000000003',
  '[{"line_index":0,"accepted_quantity":6,"damaged_quantity":1,"shortage_quantity":2,"discrepancy_reason":"Caja incompleta y una unidad dañada"},{"line_index":1,"shortage_quantity":1,"discrepancy_reason":"Consumible de taller no recibido"}]'::jsonb,
  '2026-07-20 12:00:00+00',
  'GUIA-RES-001',
  'Bodega principal',
  'Recepción con diferencias',
  'resolution-source-receipt'
) as payload;

select is(
  (
    select count(*)::integer
    from public.purchase_receipt_resolution_cases
  ),
  3,
  'one case is created for each non-zero discrepancy kind'
);
select is(
  (
    select discrepancy_quantity
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'shortage'
      and source_line_index = 0
  ),
  2,
  'shortage case preserves its exact quantity'
);
select is(
  (
    select discrepancy_quantity
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'damaged'
  ),
  1,
  'damaged case preserves its exact quantity'
);
select is(
  (
    select count(*)::integer
    from public.purchase_receipt_resolution_case_view
    where effective_status = 'open'
  ),
  3,
  'new discrepancy cases start open'
);

create temp table later_receipt_result on commit drop as
select public.create_purchase_goods_receipt(
  '9a240000-0000-4000-8000-000000000003',
  '[{"line_index":0,"accepted_quantity":2}]'::jsonb,
  '2026-07-20 13:00:00+00',
  'GUIA-RES-002',
  'Bodega principal',
  'Entrega posterior',
  'resolution-later-receipt'
) as payload;

select is(
  (
    select resolved_quantity
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'shortage'
      and source_line_index = 0
  ),
  2,
  'later delivery resolves the oldest shortage first'
);
select ok(
  exists (
    select 1
    from public.purchase_receipt_resolution_allocation_view allocation
    where allocation.outcome = 'later_delivery'
      and allocation.resolved_quantity = 2
      and allocation.later_receipt_id
        = (select (payload->>'receipt_id')::uuid from later_receipt_result)
      and allocation.is_effective
  ),
  'later-delivery allocation links the exact receipt line and document'
);
select is(
  (
    select inventory_qty
    from public.products
    where id = '9a240000-0000-4000-8000-000000000002'
  ),
  (select inventory_qty + 8 from resolution_stock_baseline),
  'only accepted quantities from both receipts enter stock'
);

select public.void_purchase_goods_receipt(
  (select (payload->>'receipt_id')::uuid from later_receipt_result),
  'Entrega posterior anulada',
  'resolution-later-receipt-void'
);

select is(
  (
    select inventory_qty
    from public.products
    where id = '9a240000-0000-4000-8000-000000000002'
  ),
  (select inventory_qty + 6 from resolution_stock_baseline),
  'voiding later delivery reverses only its accepted stock'
);
select is(
  (
    select open_quantity
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'shortage'
      and source_line_index = 0
  ),
  2,
  'voiding later delivery reopens its case quantity'
);

create temp table resolution_credit_result on commit drop as
select public.resolve_purchase_receipt_with_credit_note(
  '9a240000-0000-4000-8000-000000000003',
  jsonb_build_array(
    jsonb_build_object(
      'case_id',
      (
        select id
        from public.purchase_receipt_resolution_cases
        where discrepancy_kind = 'shortage'
          and purchase_receipt_line_id in (
            select id
            from public.purchase_receipt_lines
            where source_line_index = 0
          )
      ),
      'quantity',
      1
    )
  ),
  '2026-07-20 14:00:00+00',
  'missing_goods',
  'Proveedor emitió nota de crédito por faltante',
  'NC-PROV-RES-001',
  'resolution-credit-note'
) as payload;

select ok(
  exists (
    select 1
    from public.purchase_receipt_resolution_allocation_view allocation
    where allocation.outcome = 'credit_note'
      and allocation.purchase_credit_note_id
        = (
          select (payload->>'purchase_credit_note_id')::uuid
          from resolution_credit_result
        )
      and allocation.purchase_credit_note_number is not null
      and allocation.is_effective
  ),
  'credit resolution links the exact posted credit-note line'
);
select is(
  (
    select effective_status
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'shortage'
      and source_line_index = 0
  ),
  'partially_resolved',
  'posted credit note partially closes the selected shortage case'
);
select is(
  (
    select inventory_qty
    from public.products
    where id = '9a240000-0000-4000-8000-000000000002'
  ),
  (select inventory_qty + 6 from resolution_stock_baseline),
  'credit-note resolution has zero stock effect'
);
select throws_ok(
  format(
    'select public.void_purchase_goods_receipt(%L::uuid,%L,%L)',
    (select payload->>'receipt_id' from source_receipt_result),
    'Intento bloqueado',
    'resolution-source-void-blocked'
  ),
  'P0001',
  'Void active receipt discrepancy resolutions before voiding this purchase receipt',
  'source receipt cannot be voided while a resolution is active'
);

select throws_ok(
  format(
    $sql$
      select public.create_purchase_goods_receipt(
        %L::uuid,
        %L::jsonb,
        %L::timestamp with time zone,
        %L,
        %L,
        %L,
        %L
      )
    $sql$,
    '9a240000-0000-4000-8000-000000000003',
    '[{"line_index":0,"accepted_quantity":4}]',
    '2026-07-20 14:10:00+00',
    'GUIA-RES-CAP-EXCESS',
    'Bodega principal',
    'Entrega que excede saldo económico',
    'resolution-economic-cap-excess'
  ),
  'P0001',
  'Purchase receipt accepted quantity exceeds economically open invoice line 0',
  'partial nonphysical resolution rejects an excessive later receipt atomically'
);

create temp table capped_receipt_result on commit drop as
select public.create_purchase_goods_receipt(
  '9a240000-0000-4000-8000-000000000003',
  '[{"line_index":0,"accepted_quantity":3}]'::jsonb,
  '2026-07-20 14:20:00+00',
  'GUIA-RES-CAP-VALID',
  'Bodega principal',
  'Entrega limitada al saldo económico',
  'resolution-economic-cap-valid'
) as payload;

select is(
  (
    select sum(receipt_line.accepted_quantity)::integer
    from public.purchase_receipt_lines receipt_line
    where receipt_line.receipt_id = (
      select (payload->>'receipt_id')::uuid
      from capped_receipt_result
    )
  ),
  3,
  'a later receipt exactly capped by prior accepted plus credit resolution succeeds'
);
select is(
  (
    select inventory_qty
    from public.products
    where id = '9a240000-0000-4000-8000-000000000002'
  ),
  (select inventory_qty + 9 from resolution_stock_baseline),
  'the valid capped receipt adds only its accepted physical quantity'
);

select public.void_purchase_goods_receipt(
  (select (payload->>'receipt_id')::uuid from capped_receipt_result),
  'Entrega de prueba anulada',
  'resolution-economic-cap-valid-void'
);
select is(
  (
    select inventory_qty
    from public.products
    where id = '9a240000-0000-4000-8000-000000000002'
  ),
  (select inventory_qty + 6 from resolution_stock_baseline),
  'voiding the capped receipt restores its stock and later-delivery allocations'
);

select public.void_purchase_credit_note(
  (
    select (payload->>'purchase_credit_note_id')::uuid
    from resolution_credit_result
  ),
  'Nota de crédito corregida',
  'resolution-credit-note-void'
);
select is(
  (
    select open_quantity
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'shortage'
      and source_line_index = 0
  ),
  2,
  'credit-note void automatically reopens the shortage'
);

create temp table resolution_loss_result on commit drop as
select public.resolve_purchase_receipt_with_documented_loss(
  '9a240000-0000-4000-8000-000000000003',
  jsonb_build_array(
    jsonb_build_object(
      'case_id',
      (
        select id
        from public.purchase_receipt_resolution_cases
        where discrepancy_kind = 'damaged'
      ),
      'quantity',
      1
    ),
    jsonb_build_object(
      'case_id',
      (
        select id
        from public.purchase_receipt_resolution_case_view
        where discrepancy_kind = 'shortage'
          and source_line_index = 1
      ),
      'quantity',
      1
    )
  ),
  '2026-07-20 15:00:00+00',
  'Proveedor no respondió; pérdida autorizada',
  'resolution-documented-loss'
) as payload;

select is(
  (
    select effective_status
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'damaged'
  ),
  'resolved',
  'documented loss closes the selected damaged quantity'
);
select is(
  (
    select effective_status
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'shortage'
      and source_line_index = 1
  ),
  'resolved',
  'documented loss also closes workshop-consumable shortages'
);
select is(
  (
    select debit_amount
    from public.journal_lines
    where entry_id = (
      select (payload->>'journal_entry_id')::uuid
      from resolution_loss_result
    )
      and account_code = '5208'
  ),
  1500::numeric,
  'documented loss debits account 5208 for both purchase treatments'
);
select is(
  (
    select credit_amount
    from public.journal_lines
    where entry_id = (
      select (payload->>'journal_entry_id')::uuid
      from resolution_loss_result
    )
      and account_code = '1105'
  ),
  1000::numeric,
  'documented loss credits inventory account 1105'
);
select is(
  (
    select credit_amount
    from public.journal_lines
    where entry_id = (
      select (payload->>'journal_entry_id')::uuid
      from resolution_loss_result
    )
      and account_code = '5101'
  ),
  500::numeric,
  'workshop-consumable loss reclassifies account 5101 into account 5208'
);
select is(
  (
    select count(*)::integer
    from public.stock_movements
    where operation_id = (
      select (payload->>'operation_id')::uuid
      from resolution_loss_result
    )
  ),
  0,
  'documented loss creates zero stock movements'
);
select is(
  (
    select inventory_qty
    from public.products
    where id = '9a240000-0000-4000-8000-000000000002'
  ),
  (select inventory_qty + 6 from resolution_stock_baseline),
  'documented loss leaves physical stock unchanged'
);
select ok(
  (
    public.resolve_purchase_receipt_with_documented_loss(
      '9a240000-0000-4000-8000-000000000003',
      jsonb_build_array(
        jsonb_build_object(
          'case_id',
          (
            select id
            from public.purchase_receipt_resolution_cases
            where discrepancy_kind = 'damaged'
          ),
          'quantity',
          1
        ),
        jsonb_build_object(
          'case_id',
          (
            select id
            from public.purchase_receipt_resolution_case_view
            where discrepancy_kind = 'shortage'
              and source_line_index = 1
          ),
          'quantity',
          1
        )
      ),
      '2026-07-20 15:00:00+00',
      'Proveedor no respondió; pérdida autorizada',
      'resolution-documented-loss'
    )->>'replayed'
  )::boolean,
  'documented loss command is replay-safe'
);
select is(
  (
    select count(*)::integer
    from public.purchase_receipt_resolution_allocations
    where outcome = 'documented_loss'
  ),
  2,
  'documented loss replay creates no duplicate allocation'
);

create temp table resolution_loss_void_result on commit drop as
select public.void_purchase_receipt_documented_loss(
  (
    select (payload->>'resolution_group_id')::uuid
    from resolution_loss_result
  ),
  'Pérdida reclasificada por corrección',
  'resolution-documented-loss-void'
) as payload;

select is(
  (
    select open_quantity
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'damaged'
  ),
  1,
  'documented-loss void reopens its exact case quantity'
);
select is(
  (
    select open_quantity
    from public.purchase_receipt_resolution_case_view
    where discrepancy_kind = 'shortage'
      and source_line_index = 1
  ),
  1,
  'documented-loss void reopens the workshop-consumable shortage too'
);
select ok(
  exists (
    select 1
    from public.journal_entries reversal
    where reversal.id = (
      select (payload->>'journal_entry_id')::uuid
      from resolution_loss_void_result
    )
      and reversal.reversal_of_id = (
        select (payload->>'journal_entry_id')::uuid
        from resolution_loss_result
      )
      and reversal.total_debit = reversal.total_credit
  ),
  'documented-loss void appends an exact balanced journal reversal'
);
select is(
  (
    select debit_amount
    from public.journal_lines
    where entry_id = (
      select (payload->>'journal_entry_id')::uuid
      from resolution_loss_void_result
    )
      and account_code = '5101'
  ),
  500::numeric,
  'documented-loss void exactly reverses the workshop-consumable reclassification'
);
select is(
  (
    select count(*)::integer
    from public.stock_movements
    where operation_id = (
      select (payload->>'operation_id')::uuid
      from resolution_loss_void_result
    )
  ),
  0,
  'documented-loss void creates zero stock movements'
);

select lives_ok(
  format(
    'select public.void_purchase_goods_receipt(%L::uuid,%L,%L)',
    (select payload->>'receipt_id' from source_receipt_result),
    'Todas las resoluciones activas fueron revertidas',
    'resolution-source-void-final'
  ),
  'source receipt can be voided after downstream resolutions are reversed'
);
select is(
  (
    select status
    from public.purchase_receipts
    where id = (
      select (payload->>'receipt_id')::uuid
      from source_receipt_result
    )
  ),
  'voided',
  'source receipt remains as voided evidence'
);
select is(
  (
    select inventory_qty
    from public.products
    where id = '9a240000-0000-4000-8000-000000000002'
  ),
  (select inventory_qty from resolution_stock_baseline),
  'final source receipt void restores only its accepted stock'
);
select is(
  (
    select count(*)::integer
    from public.purchase_receipt_resolution_case_view
    where effective_status = 'voided'
  ),
  3,
  'cases derive voided status from their source receipt'
);
select throws_ok(
  $$
    update public.purchase_receipt_resolution_allocations
    set reason = 'rewrite'
    where outcome = 'documented_loss'
  $$,
  '23514',
  'Purchase receipt resolution evidence is append-only',
  'resolution allocations remain append-only even for privileged SQL'
);

select * from finish();
rollback;
