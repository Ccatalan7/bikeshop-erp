begin;
select set_config('request.jwt.claims','{}',true);select set_config('request.jwt.claim.sub','',true);select plan(17);
insert into public.tenants(id,shop_name)values('99920000-0000-4000-8000-000000000001','Product Import Command Test');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99920000-0000-4000-8000-000000000099','authenticated','authenticated','import@example.invalid','',now(),'{}'::jsonb,jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99920000-0000-4000-8000-000000000001'),now(),now());
insert into public.user_profiles(user_id,tenant_id,role)values('99920000-0000-4000-8000-000000000099','99920000-0000-4000-8000-000000000001','admin');
update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','99920000-0000-4000-8000-000000000001')where id='99920000-0000-4000-8000-000000000099';
select set_config('request.jwt.claims',jsonb_build_object('sub','99920000-0000-4000-8000-000000000099','role','authenticated')::text,true);select set_config('request.jwt.claim.sub','99920000-0000-4000-8000-000000000099',true);
insert into public.products(id,tenant_id,name,sku,price,cost,product_type,purchase_treatment,is_service,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level)values
('99920000-0000-4000-8000-000000000002','99920000-0000-4000-8000-000000000001','Imported Product','IMPORT-1',2000,1000,'product','inventory',false,true,2,2,0,10),
('99920000-0000-4000-8000-000000000003','99920000-0000-4000-8000-000000000001','Imported Service','IMPORT-SVC',2000,0,'service','inventory',true,false,0,0,0,0);

create temp table import_up on commit drop as select public.apply_product_import_stock('99920000-0000-4000-8000-000000000002',5,'catalogo-julio.csv','batch-1:row-2')payload;
select is((select inventory_qty from public.products where id='99920000-0000-4000-8000-000000000002'),5,'import command applies an absolute target quantity');
select is((select stock_after from public.stock_adjustments where id=((select payload->>'adjustment_id'from import_up)::uuid)),5,'import adjustment stores the resulting balance');
select is((select adjustment_origin from public.stock_adjustments where id=((select payload->>'adjustment_id'from import_up)::uuid)),'product_import','import adjustment preserves its real source');
select is((select source_channel from public.inventory_accounting_operations where id=((select payload->>'operation_id'from import_up)::uuid)),'product_import','common trace identifies the import channel');
select ok(exists(select 1 from public.stock_movements where operation_id=((select payload->>'operation_id'from import_up)::uuid)and type='IN'and quantity=3 and stock_before=2 and stock_after=5),'import movement stores exact before/change/after');
select ok(exists(select 1 from public.journal_entries where operation_id=((select payload->>'operation_id'from import_up)::uuid)and total_debit=3000 and total_credit=3000),'import value journal is balanced');
select ok((public.apply_product_import_stock('99920000-0000-4000-8000-000000000002',5,'catalogo-julio.csv','batch-1:row-2')->>'replayed')::boolean,'same import row retry is idempotent');
select is((select count(*)::integer from public.product_import_stock_commands where idempotency_key='batch-1:row-2'),1,'retry creates no second command');
select is((select count(*)::integer from public.stock_adjustments where operation_id=((select payload->>'operation_id'from import_up)::uuid)),1,'retry creates no second adjustment');
select throws_ok($$select public.apply_product_import_stock('99920000-0000-4000-8000-000000000002',4,'catalogo-julio.csv','batch-1:row-2')$$,'23000','Import key was already used with different stock content','same key cannot change target stock');

create temp table import_down on commit drop as select public.apply_product_import_stock('99920000-0000-4000-8000-000000000002',1,'catalogo-julio.csv','batch-1:row-3')payload;
select is((select inventory_qty from public.products where id='99920000-0000-4000-8000-000000000002'),1,'later import target can reduce stock explicitly');
select ok(exists(select 1 from public.stock_movements where operation_id=((select payload->>'operation_id'from import_down)::uuid)and type='OUT'and quantity=4 and stock_before=5 and stock_after=1),'import decrease has exact movement arithmetic');
select ok(exists(select 1 from public.journal_entries where operation_id=((select payload->>'operation_id'from import_down)::uuid)and total_debit=4000 and total_credit=4000),'import decrease posts exact value reclassification');
select throws_ok($$select public.apply_product_import_stock('99920000-0000-4000-8000-000000000002',-1,'catalogo-julio.csv','batch-1:bad')$$,'P0001','Import target stock must be zero or positive','negative import target is blocked');
select throws_ok($$select public.apply_product_import_stock('99920000-0000-4000-8000-000000000003',1,'catalogo-julio.csv','batch-1:service')$$,'P0001','Imported non-stock product cannot receive stock','service import cannot invent stock');
select is((public.apply_product_import_stock('99920000-0000-4000-8000-000000000002',1,'catalogo-julio.csv','batch-1:no-change')->>'status'),'no_change','equal target is recorded as an explicit no-op');
select is((select count(*)::integer from public.inventory_accounting_operations where source_channel='product_import'),2,'only stock-changing import rows create posting operations');
select * from finish();rollback;
