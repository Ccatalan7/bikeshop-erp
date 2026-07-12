begin;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
select set_config('app.test_direct_product_stock_trace','true',true);
select plan(30);

insert into public.tenants(id,shop_name)
values('99930000-0000-4000-8000-000000000001','Direct Stock Boundary Test');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values(
  '99930000-0000-4000-8000-000000000099','authenticated','authenticated',
  'direct-stock@example.invalid','',now(),'{}'::jsonb,
  jsonb_build_object(
    'tenant_id','99930000-0000-4000-8000-000000000001',
    'account_type','public_store_customer',
    'customer_tenant_id','99930000-0000-4000-8000-000000000001'
  ),now(),now()
);
insert into public.user_profiles(user_id,tenant_id,role)
values('99930000-0000-4000-8000-000000000099','99930000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims',jsonb_build_object('sub','99930000-0000-4000-8000-000000000099','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99930000-0000-4000-8000-000000000099',true);

insert into public.products(
  id,tenant_id,name,sku,price,cost,product_type,purchase_treatment,is_service,
  track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level
) values (
  '99930000-0000-4000-8000-000000000002','99930000-0000-4000-8000-000000000001',
  'Initially stocked product','DIRECT-1',2000,500,'product','inventory',false,true,3,3,0,10
);

select is((select inventory_qty from public.products where id='99930000-0000-4000-8000-000000000002'),3,'initial stock preserves inventory quantity');
select is((select stock_quantity from public.products where id='99930000-0000-4000-8000-000000000002'),3,'initial stock keeps both columns equal');
select is((select count(*)::integer from public.inventory_accounting_operations where document_id='99930000-0000-4000-8000-000000000002' and action='record_initial_stock' and outcome='completed'),1,'initial stock creates one completed operation');
select ok(exists(select 1 from public.stock_movements m join public.inventory_accounting_operations o on o.id=m.operation_id where o.document_id='99930000-0000-4000-8000-000000000002' and m.stock_before=0 and m.stock_after=3 and m.quantity=3),'initial stock movement stores exact arithmetic and lineage');
select ok(exists(select 1 from public.journal_entries j join public.inventory_accounting_operations o on o.id=j.operation_id where o.document_id='99930000-0000-4000-8000-000000000002' and j.total_debit=1500 and j.total_credit=1500),'initial stock posts a balanced opening-value journal');
select ok(exists(select 1 from public.journal_lines l join public.journal_entries j on j.id=l.entry_id join public.inventory_accounting_operations o on o.id=j.operation_id where o.document_id='99930000-0000-4000-8000-000000000002' and l.account_code='3101' and l.credit_amount=1500),'initial stock uses opening inventory equity');

update public.products set inventory_qty=5 where id='99930000-0000-4000-8000-000000000002';
select is((select stock_quantity from public.products where id='99930000-0000-4000-8000-000000000002'),5,'one-column legacy update is synchronized');
select is((select count(*)::integer from public.inventory_accounting_operations where document_id='99930000-0000-4000-8000-000000000002' and action='record_compatibility_stock_change' and outcome='completed'),1,'direct update creates one completed operation');
select ok(exists(select 1 from public.stock_movements m join public.inventory_accounting_operations o on o.id=m.operation_id where o.document_id='99930000-0000-4000-8000-000000000002' and o.action='record_compatibility_stock_change' and m.stock_before=3 and m.stock_after=5 and m.quantity=2),'direct increase has exact movement arithmetic');
select ok(exists(select 1 from public.journal_entries j join public.inventory_accounting_operations o on o.id=j.operation_id where o.document_id='99930000-0000-4000-8000-000000000002' and o.action='record_compatibility_stock_change' and j.total_debit=1000 and j.total_credit=1000),'direct increase posts a balanced value journal');
select ok(exists(select 1 from public.inventory_accounting_operations o where o.document_id='99930000-0000-4000-8000-000000000002' and o.action='record_compatibility_stock_change' and o.context->>'trigger'='trg_prepare_direct_product_stock_trace' and o.actor_id='99930000-0000-4000-8000-000000000099'),'operation records trigger and actor footprint');

select throws_ok($$update public.products set stock_quantity=6,inventory_qty=7 where id='99930000-0000-4000-8000-000000000002'$$,'23514','Direct stock update is ambiguous: stock_quantity 6 differs from inventory_qty 7','disagreeing stock columns are rejected');
select throws_ok($$update public.products set stock_quantity=-1 where id='99930000-0000-4000-8000-000000000002'$$,'23514','Direct product stock writes cannot create negative stock (-1)','direct negative stock is rejected');
select is((select count(*)::integer from public.inventory_accounting_operations where document_id='99930000-0000-4000-8000-000000000002'),2,'failed direct writes leave no operation residue');
select is((select count(*)::integer from public.inventory_accounting_operations o where o.document_id='99930000-0000-4000-8000-000000000002' and not exists(select 1 from public.inventory_accounting_checkpoints c where c.operation_id=o.id and c.phase='invariants_verified' and c.outcome='completed')),0,'every accepted direct write has a passed invariant checkpoint');
select is((select count(*)::integer from public.stock_movements m join public.inventory_accounting_operations o on o.id=m.operation_id where o.document_id='99930000-0000-4000-8000-000000000002'),2,'each accepted write creates exactly one movement');

update public.products set stock_quantity=4 where id='99930000-0000-4000-8000-000000000002';
select is((select inventory_qty from public.products where id='99930000-0000-4000-8000-000000000002'),4,'one-column decrease keeps the legacy balance synchronized');
select ok(exists(select 1 from public.stock_movements m join public.inventory_accounting_operations o on o.id=m.operation_id where o.document_id='99930000-0000-4000-8000-000000000002' and o.action='record_compatibility_stock_change' and m.type='OUT' and m.stock_before=5 and m.stock_after=4 and m.quantity=1),'direct decrease has exact outbound arithmetic');
select ok(exists(select 1 from public.journal_entries j join public.inventory_accounting_operations o on o.id=j.operation_id where o.document_id='99930000-0000-4000-8000-000000000002' and o.action='record_compatibility_stock_change' and (o.before_snapshot->>'stock')::integer=5 and j.total_debit=500 and j.total_credit=500),'direct decrease posts the exact inventory value');
select ok(exists(select 1 from public.journal_lines l join public.journal_entries j on j.id=l.entry_id join public.inventory_accounting_operations o on o.id=j.operation_id where o.document_id='99930000-0000-4000-8000-000000000002' and (o.before_snapshot->>'stock')::integer=5 and l.account_code='6198' and l.debit_amount=500),'direct decrease uses the inventory-difference expense');

insert into public.products(
  id,tenant_id,name,sku,price,cost,product_type,purchase_treatment,is_service,
  track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level
) values
('99930000-0000-4000-8000-000000000003','99930000-0000-4000-8000-000000000001','Bulk initial A','DIRECT-BULK-A',1000,100,'product','inventory',false,true,1,1,0,10),
('99930000-0000-4000-8000-000000000004','99930000-0000-4000-8000-000000000001','Bulk initial B','DIRECT-BULK-B',1000,200,'product','inventory',false,true,2,2,0,10);
select is((select count(*)::integer from public.inventory_accounting_operations where document_id in ('99930000-0000-4000-8000-000000000003','99930000-0000-4000-8000-000000000004') and outcome='completed'),2,'multi-row insert completes one operation per product');
select is((select count(*)::integer from public.stock_movements where product_id in ('99930000-0000-4000-8000-000000000003','99930000-0000-4000-8000-000000000004') and operation_id is not null),2,'multi-row insert preserves per-product movement lineage');
select is((select count(*)::integer from public.journal_entries where source_reference in ('99930000-0000-4000-8000-000000000003','99930000-0000-4000-8000-000000000004') and operation_id is not null),2,'multi-row insert posts one balanced journal per product');
select is((select count(*)::integer from public.direct_product_stock_trace_pending),0,'compatibility bridge leaves no committed pending rows');

insert into public.tenants(id,shop_name)
values('99930000-0000-4000-8000-000000000006','Other Direct Stock Tenant');
select throws_ok($$insert into public.products(id,tenant_id,name,sku,price,cost,product_type,purchase_treatment,is_service,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level) values('99930000-0000-4000-8000-000000000006','99930000-0000-4000-8000-000000000006','Cross tenant stock','DIRECT-CROSS',1000,100,'product','inventory',false,true,1,1,0,10)$$,'42501','Cross-tenant direct product stock write is not allowed','authenticated direct writer cannot cross tenants');
select is((select count(*)::integer from public.inventory_accounting_operations where document_id='99930000-0000-4000-8000-000000000006'),0,'rejected cross-tenant write leaves no trace residue');

select set_config('request.jwt.claims',jsonb_build_object('role','service_role')::text,true);
select set_config('request.jwt.claim.sub','',true);
insert into public.products(
  id,tenant_id,name,sku,price,cost,product_type,purchase_treatment,is_service,
  track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level
) values (
  '99930000-0000-4000-8000-000000000005','99930000-0000-4000-8000-000000000001',
  'Service role imported stock','DIRECT-SERVICE',1000,300,'product','inventory',false,true,1,1,0,10
);
select ok(exists(select 1 from public.inventory_accounting_operations where document_id='99930000-0000-4000-8000-000000000005' and source_channel='product_creation' and executor='database_compatibility_trigger' and actor_id is null and outcome='completed'),'service-role legacy writer receives a completed system-identity operation');
select ok(exists(select 1 from public.stock_movements where product_id='99930000-0000-4000-8000-000000000005' and operation_id is not null and stock_before=0 and stock_after=1),'service-role legacy writer receives exact movement lineage');
select ok(exists(select 1 from public.journal_entries where source_reference='99930000-0000-4000-8000-000000000005' and operation_id is not null and total_debit=300 and total_credit=300),'service-role legacy writer receives balanced value accounting');
select is((select count(*)::integer from public.direct_product_stock_trace_pending),0,'service-role completion also clears its context bridge');

select * from finish();
rollback;
