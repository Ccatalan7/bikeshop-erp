begin;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select plan(22);

insert into public.tenants(id, shop_name)
values('a2000000-0000-4000-8000-000000000001', 'Gradual Receipt Enforcement Test');
insert into auth.users(
  id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values (
  'a2000000-0000-4000-8000-000000000099','authenticated','authenticated',
  'gradual-receipt@example.invalid','',now(),'{}'::jsonb,
  jsonb_build_object(
    'account_type','public_store_customer',
    'customer_tenant_id','a2000000-0000-4000-8000-000000000001',
    'tenant_id','a2000000-0000-4000-8000-000000000001'
  ),now(),now()
);
insert into public.user_profiles(user_id,tenant_id,role)
values('a2000000-0000-4000-8000-000000000099','a2000000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000099',true);
select set_config('request.jwt.claims',jsonb_build_object('sub','a2000000-0000-4000-8000-000000000099','role','authenticated')::text,true);

insert into public.products(
  id,tenant_id,name,sku,price,cost,product_type,is_service,track_stock,
  inventory_qty,stock_quantity,min_stock_level,max_stock_level
) values
('a2000000-0000-4000-8000-000000000010','a2000000-0000-4000-8000-000000000001','Strict legacy product','GRADUAL-STRICT',1000,500,'product',false,true,0,0,0,100),
('a2000000-0000-4000-8000-000000000011','a2000000-0000-4000-8000-000000000001','Compatible legacy product','GRADUAL-LEGACY',1000,500,'product',false,true,0,0,0,100),
('a2000000-0000-4000-8000-000000000012','a2000000-0000-4000-8000-000000000001','Professional product','GRADUAL-PRO',1000,500,'product',false,true,0,0,0,100),
('a2000000-0000-4000-8000-000000000013','a2000000-0000-4000-8000-000000000001','Later strict product','GRADUAL-LATER',1000,500,'product',false,true,0,0,0,100);

insert into public.purchase_invoices(
  id,tenant_id,invoice_number,supplier_name,status,subtotal,net_amount,tax,total,balance,items
) values
('a2000000-0000-4000-8000-000000000020','a2000000-0000-4000-8000-000000000001','FC-GRADUAL-STRICT','Supplier','confirmed',1000,1000,0,1000,1000,'[{"line_id":"strict","product_id":"a2000000-0000-4000-8000-000000000010","product_name":"Strict legacy product","quantity":2,"unit_cost":500,"purchase_treatment":"inventory"}]'),
('a2000000-0000-4000-8000-000000000021','a2000000-0000-4000-8000-000000000001','FC-GRADUAL-LEGACY','Supplier','confirmed',1000,1000,0,1000,1000,'[{"line_id":"legacy","product_id":"a2000000-0000-4000-8000-000000000011","product_name":"Compatible legacy product","quantity":2,"unit_cost":500,"purchase_treatment":"inventory"}]'),
('a2000000-0000-4000-8000-000000000022','a2000000-0000-4000-8000-000000000001','FC-GRADUAL-PRO','Supplier','confirmed',2500,2500,0,2500,2500,'[{"line_id":"professional","product_id":"a2000000-0000-4000-8000-000000000012","product_name":"Professional product","quantity":5,"unit_cost":500,"purchase_treatment":"inventory"}]'),
('a2000000-0000-4000-8000-000000000023','a2000000-0000-4000-8000-000000000001','FC-GRADUAL-LATER','Supplier','confirmed',1000,1000,0,1000,1000,'[{"line_id":"later","product_id":"a2000000-0000-4000-8000-000000000013","product_name":"Later strict product","quantity":2,"unit_cost":500,"purchase_treatment":"inventory"}]');

insert into public.purchase_receipt_control_settings(
  tenant_id,control_mode,activated_at,activated_by
) values (
  'a2000000-0000-4000-8000-000000000001','enforce',now(),
  'a2000000-0000-4000-8000-000000000099'
);
select is((select legacy_untouched_compatibility from public.purchase_receipt_control_settings where tenant_id='a2000000-0000-4000-8000-000000000001'),false,'enforce defaults to strict professional-only receiving');
select throws_ok($$update public.purchase_invoices set status='received',received_date=now() where id='a2000000-0000-4000-8000-000000000020'$$,'P0001','Professional receiving is active; use the goods receipt command','strict enforce still blocks old clients');
select is((select inventory_qty from public.products where id='a2000000-0000-4000-8000-000000000010'),0,'strict rejection leaves stock unchanged');

update public.purchase_receipt_control_settings
set legacy_untouched_compatibility=true
where tenant_id='a2000000-0000-4000-8000-000000000001';
select lives_ok($$update public.purchase_invoices set status='received',received_date=now() where id='a2000000-0000-4000-8000-000000000021'$$,'old client can receive an untouched invoice during rollout');
select is((select inventory_qty from public.products where id='a2000000-0000-4000-8000-000000000011'),2,'compatible old route retains exactly one full receipt effect');
select is((select count(*)::integer from public.purchase_receipt_compatibility_events where purchase_invoice_id='a2000000-0000-4000-8000-000000000021'),1,'compatible old route leaves one append-only event');
select is((select control_mode from public.purchase_receipt_compatibility_events where purchase_invoice_id='a2000000-0000-4000-8000-000000000021'),'enforce','event proves legacy use during enforced rollout');

create temp table gradual_receipt_result on commit drop as
select public.create_purchase_goods_receipt(
  'a2000000-0000-4000-8000-000000000022',
  '[{"line_index":0,"accepted_quantity":2}]'::jsonb,
  now(),null,'Bodega principal','Recepción parcial','gradual-pro-1'
) payload;
select is((select inventory_qty from public.products where id='a2000000-0000-4000-8000-000000000012'),2,'current client can post a professional partial receipt');
select is((select status from public.purchase_invoices where id='a2000000-0000-4000-8000-000000000022'),'confirmed','partial receipt keeps accounting/payment status independent');
select ok(exists(select 1 from public.inventory_accounting_operations where id=((select payload->>'operation_id' from gradual_receipt_result)::uuid) and outcome='completed'),'professional receipt completes its operation');
select is(
  (
    select string_agg(first_phase.phase, ',' order by first_phase.first_id)
    from (
      select checkpoint.phase, min(checkpoint.id) as first_id
      from public.inventory_accounting_checkpoints checkpoint
      where checkpoint.operation_id = ((select payload->>'operation_id' from gradual_receipt_result)::uuid)
      group by checkpoint.phase
    ) first_phase
  ),
  'accepted,source_snapshotted,inventory_planned,inventory_applied,movement_recorded,accounting_planned,journal_posted,invariants_verified,completed',
  'professional receipt records the full ordered trace, including its explicit zero-journal accounting decision'
);
select throws_ok($$update public.purchase_invoices set status='received',received_date=now() where id='a2000000-0000-4000-8000-000000000022'$$,'P0001','This invoice already uses professional receipts; continue from the goods receipt workflow','old client cannot mix full status receipt over a partial receipt');
select is((select inventory_qty from public.products where id='a2000000-0000-4000-8000-000000000012'),2,'mixed-route rejection leaves partial stock exact');
select is((select count(*)::integer from public.stock_movements where product_id='a2000000-0000-4000-8000-000000000012'),1,'mixed-route rejection leaves no phantom movement');

select public.create_purchase_goods_receipt(
  'a2000000-0000-4000-8000-000000000022',
  '[{"line_index":0,"accepted_quantity":3}]'::jsonb,
  now(),null,'Bodega principal','Completa recepción','gradual-pro-2'
);
select is((select inventory_qty from public.products where id='a2000000-0000-4000-8000-000000000012'),5,'professional command completes the remaining quantity once');

create temp table gradual_receipt_void_result on commit drop as
select public.void_purchase_goods_receipt(
  ((select payload->>'receipt_id' from gradual_receipt_result)::uuid),
  'Void trace contract test',
  'gradual-pro-void-1'
) payload;
select is((select inventory_qty from public.products where id='a2000000-0000-4000-8000-000000000012'),3,'receipt void reverses only its original accepted quantity');
select is(
  (
    select string_agg(first_phase.phase, ',' order by first_phase.first_id)
    from (
      select checkpoint.phase, min(checkpoint.id) as first_id
      from public.inventory_accounting_checkpoints checkpoint
      where checkpoint.operation_id = ((select payload->>'operation_id' from gradual_receipt_void_result)::uuid)
      group by checkpoint.phase
    ) first_phase
  ),
  'accepted,source_snapshotted,inventory_planned,inventory_applied,movement_recorded,accounting_planned,journal_posted,invariants_verified,completed',
  'receipt void records the same complete ordered trace contract'
);
select ok(
  not exists(
    select 1 from public.journal_entries entry
    where entry.operation_id = ((select payload->>'operation_id' from gradual_receipt_void_result)::uuid)
  ) and exists(
    select 1 from public.inventory_accounting_checkpoints checkpoint
    where checkpoint.operation_id = ((select payload->>'operation_id' from gradual_receipt_void_result)::uuid)
      and checkpoint.phase = 'journal_posted'
      and checkpoint.payload->>'not_required' = 'true'
  ),
  'receipt void records the deliberate accounting no-op without duplicating purchase-invoice value'
);

update public.purchase_receipt_control_settings
set legacy_untouched_compatibility=false
where tenant_id='a2000000-0000-4000-8000-000000000001';
select throws_ok($$update public.purchase_invoices set status='received',received_date=now() where id='a2000000-0000-4000-8000-000000000023'$$,'P0001','Professional receiving is active; use the goods receipt command','retiring compatibility restores strict enforcement');
select is((select inventory_qty from public.products where id='a2000000-0000-4000-8000-000000000013'),0,'strict retirement rejection leaves stock unchanged');
select is((select rollout_status from public.purchase_receipt_rollout_status_view where tenant_id='a2000000-0000-4000-8000-000000000001'),'professional_only','rollout view proves strict professional-only state');
select is((select professional_receipt_count::integer from public.purchase_receipt_rollout_status_view where tenant_id='a2000000-0000-4000-8000-000000000001'),2,'rollout view counts immutable professional receipts');

select * from finish();
rollback;
