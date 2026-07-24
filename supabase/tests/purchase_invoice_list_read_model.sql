begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(16);

select has_view(
  'public',
  'purchase_invoice_list_read_model',
  'purchase invoice list read model exists'
);
select columns_are(
  'public',
  'purchase_invoice_list_read_model',
  array[
    'id',
    'tenant_id',
    'invoice_number',
    'supplier_id',
    'supplier_name',
    'supplier_rut',
    'date',
    'due_date',
    'status',
    'subtotal',
    'tax',
    'total',
    'net_amount',
    'paid_amount',
    'balance',
    'supplier_refunded_amount',
    'credited_amount',
    'supplier_credit_balance',
    'prepayment_model',
    'sent_date',
    'confirmed_date',
    'received_date',
    'paid_date',
    'items',
    'created_at',
    'updated_at',
    'receipt_state',
    'receipt_expected_quantity',
    'receipt_accepted_quantity',
    'receipt_reported_difference_quantity',
    'receipt_resolved_difference_quantity',
    'receipt_nonphysical_resolution_quantity',
    'receipt_unresolved_difference_quantity',
    'receipt_physical_remaining_quantity',
    'receipt_remaining_quantity',
    'receipt_count',
    'receipt_latest_received_at',
    'receipt_legacy_received'
  ],
  'read model preserves the list preview and canonical receipt contract'
);
select ok(
  coalesce((
    select 'security_invoker=true' = any(reloptions)
    from pg_class
    where oid = 'public.purchase_invoice_list_read_model'::regclass
  ), false),
  'read model executes with invoker security'
);
select ok(
  has_table_privilege(
    'authenticated',
    'public.purchase_invoice_list_read_model',
    'SELECT'
  ),
  'authenticated clients can read the list projection'
);
select ok(
  not has_table_privilege(
    'anon',
    'public.purchase_invoice_list_read_model',
    'SELECT'
  ),
  'anonymous clients cannot read the list projection'
);

insert into public.tenants (id, shop_name)
values
  (
    '9c240000-0000-4000-8000-000000000001',
    'Purchase Invoice List Read Model Test'
  ),
  (
    '9c240000-0000-4000-8000-000000000002',
    'Purchase Invoice List Other Tenant'
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
  '9c240000-0000-4000-8000-000000000099',
  'authenticated',
  'authenticated',
  'purchase-invoice-list-read-model@example.invalid',
  '',
  now(),
  '{}'::jsonb,
  jsonb_build_object(
    'tenant_id',
    '9c240000-0000-4000-8000-000000000001'
  ),
  now(),
  now()
);
insert into public.user_profiles (user_id, tenant_id, role)
values (
  '9c240000-0000-4000-8000-000000000099',
  '9c240000-0000-4000-8000-000000000001',
  'admin'
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '9c240000-0000-4000-8000-000000000099',
    'role',
    'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '9c240000-0000-4000-8000-000000000099',
  true
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
  received_date,
  items
) values
  (
    '9c240000-0000-4000-8000-000000000003',
    '9c240000-0000-4000-8000-000000000001',
    'FC-LIST-NONE',
    'Read Model Supplier',
    'draft',
    3000,
    3000,
    0,
    3000,
    3000,
    null,
    '[{"line_id":"none-line","quantity":3,"unit_cost":1000}]'::jsonb
  ),
  (
    '9c240000-0000-4000-8000-000000000004',
    '9c240000-0000-4000-8000-000000000001',
    'FC-LIST-LEGACY',
    'Read Model Supplier',
    'draft',
    2000,
    2000,
    0,
    2000,
    2000,
    '2026-07-20 09:00:00+00',
    '[{"line_id":"legacy-line","quantity":2,"unit_cost":1000}]'::jsonb
  ),
  (
    '9c240000-0000-4000-8000-000000000005',
    '9c240000-0000-4000-8000-000000000001',
    'FC-LIST-CLAMPED',
    'Read Model Supplier',
    'draft',
    10000,
    10000,
    0,
    10000,
    10000,
    '2026-07-20 09:00:00+00',
    '[{"line_id":"clamped-line","quantity":10,"unit_cost":1000}]'::jsonb
  ),
  (
    '9c240000-0000-4000-8000-000000000006',
    '9c240000-0000-4000-8000-000000000001',
    'FC-LIST-INEFFECTIVE',
    'Read Model Supplier',
    'draft',
    10000,
    10000,
    0,
    10000,
    10000,
    null,
    '[{"line_id":"ineffective-line","quantity":10,"unit_cost":1000}]'::jsonb
  ),
  (
    '9c240000-0000-4000-8000-000000000007',
    '9c240000-0000-4000-8000-000000000001',
    'FC-LIST-ACCEPTED-CLAMP',
    'Read Model Supplier',
    'draft',
    10000,
    10000,
    0,
    10000,
    10000,
    null,
    '[{"line_id":"accepted-clamp-line","quantity":10,"unit_cost":1000}]'::jsonb
  ),
  (
    '9c240000-0000-4000-8000-000000000008',
    '9c240000-0000-4000-8000-000000000001',
    'FC-LIST-LATER',
    'Read Model Supplier',
    'draft',
    10000,
    10000,
    0,
    10000,
    10000,
    null,
    '[{"line_id":"later-line","quantity":10,"unit_cost":1000}]'::jsonb
  ),
  (
    '9c240000-0000-4000-8000-000000000009',
    '9c240000-0000-4000-8000-000000000002',
    'FC-LIST-OTHER-TENANT',
    'Other Tenant Supplier',
    'draft',
    1000,
    1000,
    0,
    1000,
    1000,
    null,
    '[{"line_id":"other-line","quantity":1,"unit_cost":1000}]'::jsonb
  );

insert into public.inventory_accounting_operations (
  id,
  tenant_id,
  operation_key,
  source_channel,
  action,
  document_type,
  document_id,
  actor_id,
  outcome,
  completed_at
) values
  (
    '9c240000-0000-4000-8000-000000000101',
    '9c240000-0000-4000-8000-000000000001',
    'list-read-model-voided',
    'test',
    'create',
    'purchase_receipt',
    '9c240000-0000-4000-8000-000000000003',
    '9c240000-0000-4000-8000-000000000099',
    'completed',
    now()
  ),
  (
    '9c240000-0000-4000-8000-000000000102',
    '9c240000-0000-4000-8000-000000000001',
    'list-read-model-clamped',
    'test',
    'create',
    'purchase_receipt',
    '9c240000-0000-4000-8000-000000000005',
    '9c240000-0000-4000-8000-000000000099',
    'completed',
    now()
  ),
  (
    '9c240000-0000-4000-8000-000000000103',
    '9c240000-0000-4000-8000-000000000001',
    'list-read-model-ineffective',
    'test',
    'create',
    'purchase_receipt',
    '9c240000-0000-4000-8000-000000000006',
    '9c240000-0000-4000-8000-000000000099',
    'completed',
    now()
  ),
  (
    '9c240000-0000-4000-8000-000000000104',
    '9c240000-0000-4000-8000-000000000001',
    'list-read-model-accepted-a',
    'test',
    'create',
    'purchase_receipt',
    '9c240000-0000-4000-8000-000000000007',
    '9c240000-0000-4000-8000-000000000099',
    'completed',
    now()
  ),
  (
    '9c240000-0000-4000-8000-000000000105',
    '9c240000-0000-4000-8000-000000000001',
    'list-read-model-accepted-b',
    'test',
    'create',
    'purchase_receipt',
    '9c240000-0000-4000-8000-000000000007',
    '9c240000-0000-4000-8000-000000000099',
    'completed',
    now()
  ),
  (
    '9c240000-0000-4000-8000-000000000106',
    '9c240000-0000-4000-8000-000000000001',
    'list-read-model-later-source',
    'test',
    'create',
    'purchase_receipt',
    '9c240000-0000-4000-8000-000000000008',
    '9c240000-0000-4000-8000-000000000099',
    'completed',
    now()
  ),
  (
    '9c240000-0000-4000-8000-000000000107',
    '9c240000-0000-4000-8000-000000000001',
    'list-read-model-later-delivery',
    'test',
    'create',
    'purchase_receipt',
    '9c240000-0000-4000-8000-000000000008',
    '9c240000-0000-4000-8000-000000000099',
    'completed',
    now()
  ),
  (
    '9c240000-0000-4000-8000-000000000108',
    '9c240000-0000-4000-8000-000000000001',
    'list-read-model-clamped-resolution',
    'test',
    'resolve',
    'purchase_receipt_resolution',
    '9c240000-0000-4000-8000-000000000005',
    '9c240000-0000-4000-8000-000000000099',
    'completed',
    now()
  ),
  (
    '9c240000-0000-4000-8000-000000000109',
    '9c240000-0000-4000-8000-000000000001',
    'list-read-model-ineffective-resolution',
    'test',
    'resolve',
    'purchase_receipt_resolution',
    '9c240000-0000-4000-8000-000000000006',
    '9c240000-0000-4000-8000-000000000099',
    'completed',
    now()
  );

insert into public.purchase_receipts (
  id,
  tenant_id,
  purchase_invoice_id,
  receipt_number,
  status,
  received_at,
  idempotency_key,
  operation_id,
  created_by,
  created_at
) values
  (
    '9c240000-0000-4000-8000-000000000201',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000003',
    'REC-LIST-VOIDED',
    'voided',
    '2026-07-20 10:00:00+00',
    'list-read-model-voided',
    '9c240000-0000-4000-8000-000000000101',
    '9c240000-0000-4000-8000-000000000099',
    '2026-07-20 10:00:00+00'
  ),
  (
    '9c240000-0000-4000-8000-000000000202',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000005',
    'REC-LIST-CLAMPED',
    'posted',
    '2026-07-20 11:00:00+00',
    'list-read-model-clamped',
    '9c240000-0000-4000-8000-000000000102',
    '9c240000-0000-4000-8000-000000000099',
    '2026-07-20 11:00:00+00'
  ),
  (
    '9c240000-0000-4000-8000-000000000203',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000006',
    'REC-LIST-INEFFECTIVE',
    'posted',
    '2026-07-20 12:00:00+00',
    'list-read-model-ineffective',
    '9c240000-0000-4000-8000-000000000103',
    '9c240000-0000-4000-8000-000000000099',
    '2026-07-20 12:00:00+00'
  ),
  (
    '9c240000-0000-4000-8000-000000000204',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000007',
    'REC-LIST-ACCEPTED-A',
    'posted',
    '2026-07-20 13:00:00+00',
    'list-read-model-accepted-a',
    '9c240000-0000-4000-8000-000000000104',
    '9c240000-0000-4000-8000-000000000099',
    '2026-07-20 13:00:00+00'
  ),
  (
    '9c240000-0000-4000-8000-000000000205',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000007',
    'REC-LIST-ACCEPTED-B',
    'posted',
    '2026-07-20 14:00:00+00',
    'list-read-model-accepted-b',
    '9c240000-0000-4000-8000-000000000105',
    '9c240000-0000-4000-8000-000000000099',
    '2026-07-20 14:00:00+00'
  ),
  (
    '9c240000-0000-4000-8000-000000000206',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000008',
    'REC-LIST-LATER-SOURCE',
    'posted',
    '2026-07-20 15:00:00+00',
    'list-read-model-later-source',
    '9c240000-0000-4000-8000-000000000106',
    '9c240000-0000-4000-8000-000000000099',
    '2026-07-20 15:00:00+00'
  ),
  (
    '9c240000-0000-4000-8000-000000000207',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000008',
    'REC-LIST-LATER-DELIVERY',
    'posted',
    '2026-07-20 16:00:00+00',
    'list-read-model-later-delivery',
    '9c240000-0000-4000-8000-000000000107',
    '9c240000-0000-4000-8000-000000000099',
    '2026-07-20 16:00:00+00'
  );

-- The voided row proves that only posted receipt evidence participates.
insert into public.purchase_receipt_lines (
  id,
  tenant_id,
  receipt_id,
  purchase_invoice_id,
  source_line_key,
  source_line_index,
  product_name,
  expected_quantity,
  previously_received_quantity,
  accepted_quantity,
  damaged_quantity,
  rejected_quantity,
  shortage_quantity,
  remaining_quantity,
  unit_cost,
  line_snapshot
) values (
  '9c240000-0000-4000-8000-000000000301',
  '9c240000-0000-4000-8000-000000000001',
  '9c240000-0000-4000-8000-000000000201',
  '9c240000-0000-4000-8000-000000000003',
  'none-line',
  0,
  'Voided evidence',
  3,
  0,
  3,
  0,
  0,
  0,
  0,
  1000,
  '{"quantity":3}'::jsonb
);

insert into public.purchase_receipt_lines (
  id,
  tenant_id,
  receipt_id,
  purchase_invoice_id,
  source_line_key,
  source_line_index,
  product_name,
  expected_quantity,
  previously_received_quantity,
  accepted_quantity,
  damaged_quantity,
  rejected_quantity,
  shortage_quantity,
  remaining_quantity,
  unit_cost,
  discrepancy_reason,
  line_snapshot
) values
  (
    '9c240000-0000-4000-8000-000000000302',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000202',
    '9c240000-0000-4000-8000-000000000005',
    'clamped-line',
    0,
    'Clamped line',
    10,
    0,
    6,
    0,
    0,
    4,
    4,
    1000,
    'Faltante de prueba',
    '{"quantity":10}'::jsonb
  ),
  (
    '9c240000-0000-4000-8000-000000000303',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000203',
    '9c240000-0000-4000-8000-000000000006',
    'ineffective-line',
    0,
    'Ineffective line',
    10,
    0,
    6,
    0,
    0,
    4,
    4,
    1000,
    'Faltante de prueba',
    '{"quantity":10}'::jsonb
  ),
  (
    '9c240000-0000-4000-8000-000000000306',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000206',
    '9c240000-0000-4000-8000-000000000008',
    'later-line',
    0,
    'Later-delivery source',
    10,
    0,
    6,
    0,
    0,
    4,
    4,
    1000,
    'Faltante de prueba',
    '{"quantity":10}'::jsonb
  );

-- These deliberately impossible cumulative rows exercise the same defensive
-- per-line accepted clamp as PurchaseReceiptFulfillment.derive.
alter table public.purchase_receipt_lines
  disable trigger trg_purchase_receipt_line_00_guard_economic_quantity;
insert into public.purchase_receipt_lines (
  id,
  tenant_id,
  receipt_id,
  purchase_invoice_id,
  source_line_key,
  source_line_index,
  product_name,
  expected_quantity,
  previously_received_quantity,
  accepted_quantity,
  remaining_quantity,
  unit_cost,
  line_snapshot
) values
  (
    '9c240000-0000-4000-8000-000000000304',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000204',
    '9c240000-0000-4000-8000-000000000007',
    'accepted-clamp-line',
    0,
    'Accepted clamp A',
    10,
    0,
    8,
    2,
    1000,
    '{"quantity":10}'::jsonb
  ),
  (
    '9c240000-0000-4000-8000-000000000305',
    '9c240000-0000-4000-8000-000000000001',
    '9c240000-0000-4000-8000-000000000205',
    '9c240000-0000-4000-8000-000000000007',
    'accepted-clamp-line',
    0,
    'Accepted clamp B',
    10,
    0,
    7,
    3,
    1000,
    '{"quantity":10}'::jsonb
  );
alter table public.purchase_receipt_lines
  enable trigger trg_purchase_receipt_line_00_guard_economic_quantity;

-- A later accepted line creates an effective later-delivery allocation.
insert into public.purchase_receipt_lines (
  id,
  tenant_id,
  receipt_id,
  purchase_invoice_id,
  source_line_key,
  source_line_index,
  product_name,
  expected_quantity,
  previously_received_quantity,
  accepted_quantity,
  remaining_quantity,
  unit_cost,
  line_snapshot
) values (
  '9c240000-0000-4000-8000-000000000307',
  '9c240000-0000-4000-8000-000000000001',
  '9c240000-0000-4000-8000-000000000207',
  '9c240000-0000-4000-8000-000000000008',
  'later-line',
  0,
  'Later delivery',
  10,
  6,
  1,
  3,
  1000,
  '{"quantity":10}'::jsonb
);

insert into public.journal_entries (
  id,
  tenant_id,
  entry_number,
  entry_date,
  description,
  type,
  source_module,
  source_reference,
  status,
  total_debit,
  total_credit
) values
  (
    '9c240000-0000-4000-8000-000000000401',
    '9c240000-0000-4000-8000-000000000001',
    'JE-LIST-POSTED',
    now(),
    'Effective receipt resolution',
    'adjustment',
    'purchase_receipt_resolution',
    'FC-LIST-CLAMPED',
    'posted',
    7000,
    7000
  ),
  (
    '9c240000-0000-4000-8000-000000000402',
    '9c240000-0000-4000-8000-000000000001',
    'JE-LIST-DRAFT',
    now(),
    'Ineffective receipt resolution',
    'adjustment',
    'purchase_receipt_resolution',
    'FC-LIST-INEFFECTIVE',
    'draft',
    4000,
    4000
  );

insert into public.purchase_receipt_resolution_allocations (
  tenant_id,
  case_id,
  resolution_group_id,
  outcome,
  resolved_quantity,
  net_amount,
  operation_id,
  journal_entry_id,
  reason,
  resolved_at,
  created_by
) values
  (
    '9c240000-0000-4000-8000-000000000001',
    (
      select resolution_case.id
      from public.purchase_receipt_resolution_cases resolution_case
      where resolution_case.purchase_invoice_id
        = '9c240000-0000-4000-8000-000000000005'
        and resolution_case.discrepancy_kind = 'shortage'
    ),
    '9c240000-0000-4000-8000-000000000501',
    'documented_loss',
    7,
    7000,
    '9c240000-0000-4000-8000-000000000108',
    '9c240000-0000-4000-8000-000000000401',
    'Overallocated fixture proves defensive clamps',
    now(),
    '9c240000-0000-4000-8000-000000000099'
  ),
  (
    '9c240000-0000-4000-8000-000000000001',
    (
      select resolution_case.id
      from public.purchase_receipt_resolution_cases resolution_case
      where resolution_case.purchase_invoice_id
        = '9c240000-0000-4000-8000-000000000006'
        and resolution_case.discrepancy_kind = 'shortage'
    ),
    '9c240000-0000-4000-8000-000000000502',
    'documented_loss',
    4,
    4000,
    '9c240000-0000-4000-8000-000000000109',
    '9c240000-0000-4000-8000-000000000402',
    'Draft journal must not resolve fulfillment',
    now(),
    '9c240000-0000-4000-8000-000000000099'
  );

select is(
  (
    select jsonb_build_object(
      'state', receipt_state,
      'expected', receipt_expected_quantity,
      'accepted', receipt_accepted_quantity,
      'difference', receipt_reported_difference_quantity,
      'resolved', receipt_resolved_difference_quantity,
      'nonphysical', receipt_nonphysical_resolution_quantity,
      'unresolved', receipt_unresolved_difference_quantity,
      'physical_remaining', receipt_physical_remaining_quantity,
      'remaining', receipt_remaining_quantity,
      'count', receipt_count,
      'legacy', receipt_legacy_received
    )
    from public.purchase_invoice_list_read_model
    where id = '9c240000-0000-4000-8000-000000000003'
  ),
  '{
    "state":"none",
    "expected":3,
    "accepted":0,
    "difference":0,
    "resolved":0,
    "nonphysical":0,
    "unresolved":0,
    "physical_remaining":3,
    "remaining":3,
    "count":0,
    "legacy":false
  }'::jsonb,
  'voided receipts do not become physical receipt evidence'
);

select is(
  (
    select jsonb_build_object(
      'state', receipt_state,
      'expected', receipt_expected_quantity,
      'accepted', receipt_accepted_quantity,
      'physical_remaining', receipt_physical_remaining_quantity,
      'remaining', receipt_remaining_quantity,
      'count', receipt_count,
      'legacy', receipt_legacy_received
    )
    from public.purchase_invoice_list_read_model
    where id = '9c240000-0000-4000-8000-000000000004'
  ),
  '{
    "state":"complete",
    "expected":2,
    "accepted":2,
    "physical_remaining":0,
    "remaining":0,
    "count":0,
    "legacy":true
  }'::jsonb,
  'legacy received evidence applies only without posted receipt rows'
);

select is(
  (
    select jsonb_build_object(
      'state', receipt_state,
      'expected', receipt_expected_quantity,
      'accepted', receipt_accepted_quantity,
      'difference', receipt_reported_difference_quantity,
      'resolved', receipt_resolved_difference_quantity,
      'nonphysical', receipt_nonphysical_resolution_quantity,
      'unresolved', receipt_unresolved_difference_quantity,
      'physical_remaining', receipt_physical_remaining_quantity,
      'remaining', receipt_remaining_quantity,
      'count', receipt_count,
      'legacy', receipt_legacy_received
    )
    from public.purchase_invoice_list_read_model
    where id = '9c240000-0000-4000-8000-000000000005'
  ),
  '{
    "state":"closedWithDifference",
    "expected":10,
    "accepted":6,
    "difference":4,
    "resolved":4,
    "nonphysical":4,
    "unresolved":0,
    "physical_remaining":4,
    "remaining":0,
    "count":1,
    "legacy":false
  }'::jsonb,
  'accepted and effective resolution quantities are clamped per line'
);
select is(
  (
    select receipt_latest_received_at
    from public.purchase_invoice_list_read_model
    where id = '9c240000-0000-4000-8000-000000000005'
  ),
  '2026-07-20 11:00:00+00'::timestamp with time zone,
  'latest receipt time comes only from posted receipt evidence'
);

select is(
  (
    select jsonb_build_object(
      'state', receipt_state,
      'resolved', receipt_resolved_difference_quantity,
      'nonphysical', receipt_nonphysical_resolution_quantity,
      'unresolved', receipt_unresolved_difference_quantity,
      'remaining', receipt_remaining_quantity
    )
    from public.purchase_invoice_list_read_model
    where id = '9c240000-0000-4000-8000-000000000006'
  ),
  '{
    "state":"open",
    "resolved":0,
    "nonphysical":0,
    "unresolved":4,
    "remaining":4
  }'::jsonb,
  'a draft accounting artifact is not an effective resolution'
);

select is(
  (
    select jsonb_build_object(
      'state', receipt_state,
      'expected', receipt_expected_quantity,
      'accepted', receipt_accepted_quantity,
      'physical_remaining', receipt_physical_remaining_quantity,
      'count', receipt_count
    )
    from public.purchase_invoice_list_read_model
    where id = '9c240000-0000-4000-8000-000000000007'
  ),
  '{
    "state":"complete",
    "expected":10,
    "accepted":10,
    "physical_remaining":0,
    "count":2
  }'::jsonb,
  'cumulative accepted quantity is clamped to the invoice line'
);
select is(
  (
    select receipt_latest_received_at
    from public.purchase_invoice_list_read_model
    where id = '9c240000-0000-4000-8000-000000000007'
  ),
  '2026-07-20 14:00:00+00'::timestamp with time zone,
  'latest posted receipt survives multi-receipt aggregation'
);

select is(
  (
    select jsonb_build_object(
      'state', receipt_state,
      'accepted', receipt_accepted_quantity,
      'difference', receipt_reported_difference_quantity,
      'resolved', receipt_resolved_difference_quantity,
      'nonphysical', receipt_nonphysical_resolution_quantity,
      'unresolved', receipt_unresolved_difference_quantity,
      'remaining', receipt_remaining_quantity,
      'count', receipt_count
    )
    from public.purchase_invoice_list_read_model
    where id = '9c240000-0000-4000-8000-000000000008'
  ),
  '{
    "state":"open",
    "accepted":7,
    "difference":4,
    "resolved":1,
    "nonphysical":0,
    "unresolved":3,
    "remaining":3,
    "count":2
  }'::jsonb,
  'later delivery resolves a difference without nonphysical closure'
);

set local role authenticated;
select is(
  (
    select count(*)::integer
    from public.purchase_invoice_list_read_model
  ),
  6,
  'security-invoker projection exposes only the active tenant invoices'
);
select ok(
  not exists (
    select 1
    from public.purchase_invoice_list_read_model
    where tenant_id = '9c240000-0000-4000-8000-000000000002'
  ),
  'security-invoker projection cannot leak another tenant'
);
reset role;

select * from finish();
rollback;
