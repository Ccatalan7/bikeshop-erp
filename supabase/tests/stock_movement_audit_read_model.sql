begin;

select plan(14);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name)
values ('98000000-0000-4000-8000-000000000001', 'Movement Audit Read Test');

select set_config('request.jwt.claim.sub', '', true);

insert into public.products (
  id, tenant_id, name, sku, price, cost, product_type, is_service,
  track_stock, inventory_qty, stock_quantity, min_stock_level, max_stock_level
)
values (
  '98000000-0000-4000-8000-000000000002',
  '98000000-0000-4000-8000-000000000001',
  'Movement Audit Product', 'MOVEMENT-AUDIT-001', 5000, 2500,
  'product', false, true, 0, 0, 0, 20
);

insert into public.stock_adjustments (
  id, tenant_id, product_id, adjustment_type, quantity,
  stock_before, stock_after, reason, adjustment_date, created_at
) values (
  '98000000-0000-4000-8000-000000000003',
  '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000002',
  'manual', -9, 9, 0, 'Ajuste Manual',
  '2026-07-02 19:15:05+00', '2026-07-02 19:15:05+00'
);

insert into public.stock_movements (
  id, tenant_id, product_id, date, type, movement_type, quantity,
  reference, notes, created_at
) values (
  '98000000-0000-4000-8000-000000000004',
  '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000002',
  '2026-06-30 04:00:00+00', 'OUT', 'purchase_invoice_reversal', 10,
  'purchase_invoice:98000000-0000-4000-8000-000000000005',
  'Legacy reversal test', '2026-07-02 19:15:05+00'
);

select is(
  (select stock_before from public.stock_movements_audit_view
    where source_document_id = '98000000-0000-4000-8000-000000000003'),
  9,
  'adjustment movement uses its exact source stock-before balance'
);

select is(
  (select stock_after from public.stock_movements_audit_view
    where source_document_id = '98000000-0000-4000-8000-000000000003'),
  0,
  'adjustment movement uses its exact source stock-after balance'
);

select is(
  (select integrity_status from public.stock_movements_audit_view
    where source_document_id = '98000000-0000-4000-8000-000000000003'),
  'legacy_duplicate_footprint',
  'automatic legacy adjustment is explicitly classified as duplicate evidence'
);

select is(
  (select reconciled_quantity from public.stock_movements_audit_view
    where source_document_id = '98000000-0000-4000-8000-000000000003'),
  0,
  'duplicate adjustment is excluded from movement summaries'
);

select is(
  (select stock_before from public.stock_movements_audit_view
    where id = '98000000-0000-4000-8000-000000000004'),
  9,
  'legacy purchase reversal inherits the proven source balance'
);

select is(
  (select stock_after from public.stock_movements_audit_view
    where id = '98000000-0000-4000-8000-000000000004'),
  0,
  'legacy purchase reversal inherits the proven ending balance'
);

select is(
  (select raw_quantity from public.stock_movements_audit_view
    where id = '98000000-0000-4000-8000-000000000004'),
  -10,
  'legacy purchase reversal preserves the raw emitted quantity'
);

select is(
  (select actual_stock_delta from public.stock_movements_audit_view
    where id = '98000000-0000-4000-8000-000000000004'),
  -9,
  'legacy purchase reversal exposes the actual stock delta'
);

select is(
  (select reconciled_quantity from public.stock_movements_audit_view
    where id = '98000000-0000-4000-8000-000000000004'),
  -9,
  'summary quantity uses actual delta for the canonical reversal'
);

select is(
  (select integrity_status from public.stock_movements_audit_view
    where id = '98000000-0000-4000-8000-000000000004'),
  'legacy_purchase_reversal_collision',
  'legacy purchase reversal collision is visible'
);

select is(
  (select source_document_type from public.stock_movements_audit_view
    where source_document_id = '98000000-0000-4000-8000-000000000003'),
  'stock_adjustment',
  'new adjustment movement stores explicit source identity'
);

select is(
  (select balance_provenance from public.stock_movements_audit_view
    where source_document_id = '98000000-0000-4000-8000-000000000003'),
  'persisted_movement',
  'new adjustment movement stores persisted balances'
);

insert into public.stock_adjustments (
  id, tenant_id, product_id, adjustment_type, quantity,
  stock_before, stock_after, reason, adjustment_date, created_at
) values
(
  '98000000-0000-4000-8000-000000000006',
  '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000002',
  'correction', -2, 4, 2, 'Ambiguous legacy test A',
  '2026-04-02 03:10:14+00', '2026-04-02 03:10:14+00'
),
(
  '98000000-0000-4000-8000-000000000007',
  '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000002',
  'correction', -2, 4, 2, 'Ambiguous legacy test B',
  '2026-04-02 03:10:14+00', '2026-04-02 03:10:14+00'
);

insert into public.stock_movements (
  id, tenant_id, product_id, date, type, movement_type, quantity,
  notes, created_at
) values (
  '98000000-0000-4000-8000-000000000008',
  '98000000-0000-4000-8000-000000000001',
  '98000000-0000-4000-8000-000000000002',
  '2026-04-02 03:10:14+00', 'OUT', 'correction', 2,
  'Ambiguous legacy movement', '2026-04-02 03:10:14+00'
);

select is(
  (select count(*)::integer from public.stock_movements_audit_view
    where id = '98000000-0000-4000-8000-000000000008'),
  1,
  'ambiguous legacy source matches never duplicate movement rows'
);

select is(
  (select integrity_status from public.stock_movements_audit_view
    where id = '98000000-0000-4000-8000-000000000008'),
  'legacy_ambiguous_adjustment_match',
  'ambiguous legacy source matches are surfaced instead of guessed'
);

select * from finish();
rollback;
