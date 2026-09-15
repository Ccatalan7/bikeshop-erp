begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select has_column(
  'public',
  'purchase_invoice_lines',
  'source_need_id',
  'a canonical purchase line preserves its originating supply need'
);

select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.purchase_invoice_lines'::regclass
      and constraint_row.conname =
        'purchase_invoice_lines_source_need_fkey'
      and pg_get_constraintdef(constraint_row.oid) like
        '%FOREIGN KEY (tenant_id, source_need_id)%'
      and pg_get_constraintdef(constraint_row.oid) like
        '%REFERENCES supply_needs(tenant_id, id)%'
  ),
  'purchase provenance is tenant-scoped through a composite foreign key'
);

select has_function(
  'public',
  'preserve_purchase_invoice_line_supply_need_v1',
  array[]::text[],
  'one trigger owner validates source snapshots and immutability'
);

select has_trigger(
  'public',
  'purchase_invoice_lines',
  'trg_preserve_purchase_invoice_line_supply_need',
  'every normalized purchase line passes the provenance guard'
);

insert into public.tenants(id, shop_name) values
  ('99bd0000-0000-4000-8000-000000000001', 'Purchase provenance A'),
  ('99bd0000-0000-4000-8000-000000000002', 'Purchase provenance B');

-- Tenant bootstrap temporarily publishes a tenant claim while seeding. It is
-- not an authenticated user and must not become purchase audit evidence.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.supply_needs(
  id, tenant_id, origin_kind, original_description, quantity, unit,
  identity_state, supply_state, usage_state
) values
  (
    '99bd0000-0000-4000-8000-000000000011',
    '99bd0000-0000-4000-8000-000000000001',
    'ad_hoc', 'Piñón de rescate', 1, 'unit',
    'unresolved', 'open', 'pending'
  ),
  (
    '99bd0000-0000-4000-8000-000000000012',
    '99bd0000-0000-4000-8000-000000000001',
    'ad_hoc', 'Alternativa local', 1, 'unit',
    'unresolved', 'open', 'pending'
  ),
  (
    '99bd0000-0000-4000-8000-000000000021',
    '99bd0000-0000-4000-8000-000000000002',
    'ad_hoc', 'Necesidad ajena', 1, 'unit',
    'unresolved', 'open', 'pending'
  );

insert into public.purchase_invoices(
  id, tenant_id, invoice_number, status, subtotal, tax, total, balance, items
) values (
  '99bd0000-0000-4000-8000-000000000031',
  '99bd0000-0000-4000-8000-000000000001',
  'FC-PROVENANCE-1',
  'draft', 8990, 0, 8990, 8990,
  jsonb_build_array(jsonb_build_object(
    'source_need_id', '99bd0000-0000-4000-8000-000000000011',
    'product_id', '',
    'product_name', 'Piñón de rescate',
    'description', 'Piñón de rescate',
    'purchase_treatment', 'inventory',
    'quantity', 1,
    'unit_cost', 8990,
    'discount', 0,
    'iva_rate', 0
  ))
);

select is(
  (
    select source_need_id
    from public.purchase_invoice_lines
    where purchase_invoice_id =
      '99bd0000-0000-4000-8000-000000000031'
      and line_kind = 'item'
  ),
  '99bd0000-0000-4000-8000-000000000011'::uuid,
  'normalization promotes the seed provenance into the typed foreign key'
);

select throws_ok(
  $$update public.purchase_invoice_lines
    set source_need_id = '99bd0000-0000-4000-8000-000000000012'
    where purchase_invoice_id =
      '99bd0000-0000-4000-8000-000000000031'
      and line_kind = 'item'$$,
  '22023',
  'Purchase line supply need provenance disagrees with its source snapshot.',
  'a later edit cannot retarget a purchased line to another need'
);

select throws_ok(
  $$insert into public.purchase_invoice_lines(
      tenant_id, purchase_invoice_id, line_number, line_kind,
      line_nature, classification_status, description, quantity,
      unit_cost, net_amount, tax_amount, total_amount, source_item
    ) values (
      '99bd0000-0000-4000-8000-000000000001',
      '99bd0000-0000-4000-8000-000000000031',
      99, 'item', 'other', 'needs_review', 'Necesidad ajena', 1,
      0, 0, 0, 0,
      '{"source_need_id":"99bd0000-0000-4000-8000-000000000021"}'::jsonb
    )$$,
  '23503',
  null,
  'a purchase line cannot cite another tenant supply need'
);

select throws_ok(
  $$insert into public.purchase_invoice_lines(
      tenant_id, purchase_invoice_id, line_number, line_kind,
      line_nature, classification_status, description, quantity,
      unit_cost, net_amount, tax_amount, total_amount, source_item
    ) values (
      '99bd0000-0000-4000-8000-000000000001',
      '99bd0000-0000-4000-8000-000000000031',
      100, 'item', 'other', 'needs_review', 'Origen inválido', 1,
      0, 0, 0, 0, '{"source_need_id":"not-a-uuid"}'::jsonb
    )$$,
  '22023',
  'Invalid supply need provenance.',
  'malformed model or client provenance fails closed'
);

select * from finish();
rollback;
