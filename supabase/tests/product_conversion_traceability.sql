begin;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
select plan(16);

insert into public.tenants(id,shop_name)values('99910000-0000-4000-8000-000000000001','Product Conversion Trace Test');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99910000-0000-4000-8000-000000000099','authenticated','authenticated','conversion@example.invalid','',now(),'{}'::jsonb,jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99910000-0000-4000-8000-000000000001'),now(),now());
insert into public.user_profiles(user_id,tenant_id,role)values('99910000-0000-4000-8000-000000000099','99910000-0000-4000-8000-000000000001','admin');
update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','99910000-0000-4000-8000-000000000001')where id='99910000-0000-4000-8000-000000000099';
select set_config('request.jwt.claims',jsonb_build_object('sub','99910000-0000-4000-8000-000000000099','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99910000-0000-4000-8000-000000000099',true);
insert into public.products(id,tenant_id,name,sku,price,cost,product_type,purchase_treatment,is_service,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level)
values('99910000-0000-4000-8000-000000000002','99910000-0000-4000-8000-000000000001','Convertible Product','CONVERT-1',2000,1000,'product','inventory',false,true,2,2,0,10);

create temp table conversion on commit drop as select public.convert_product_inventory_to_non_stock('99910000-0000-4000-8000-000000000002','workshop_consumable','product','Uso interno permanente')payload;
select is((select inventory_qty from public.products where id='99910000-0000-4000-8000-000000000002'),0,'conversion clears available stock');
select is((select purchase_treatment from public.products where id='99910000-0000-4000-8000-000000000002'),'workshop_consumable','conversion changes inventory treatment');
select ok(exists(select 1 from public.inventory_accounting_operations where document_id='99910000-0000-4000-8000-000000000002'and source_channel='product_conversion'and action='convert'and outcome='completed'),'conversion creates a completed common trace');
select ok(exists(select 1 from public.stock_movements movement join public.inventory_accounting_operations operation on operation.id=movement.operation_id where operation.document_id='99910000-0000-4000-8000-000000000002'and operation.action='convert'and movement.type='OUT'and movement.quantity=2 and movement.stock_before=2 and movement.stock_after=0),'conversion movement is attached with exact balances');
select ok(exists(select 1 from public.journal_entries entry join public.inventory_accounting_operations operation on operation.id=entry.operation_id where operation.document_id='99910000-0000-4000-8000-000000000002'and operation.action='convert'and entry.total_debit=2000 and entry.total_credit=2000),'conversion value journal is attached and balanced');
select ok(exists(select 1 from public.inventory_accounting_checkpoints checkpoint join public.inventory_accounting_operations operation on operation.id=checkpoint.operation_id where operation.document_id='99910000-0000-4000-8000-000000000002'and operation.action='convert'and checkpoint.phase='completed'),'conversion trace reaches a completed checkpoint');
select is((select created_by from public.stock_movements movement join public.inventory_accounting_operations operation on operation.id=movement.operation_id where operation.document_id='99910000-0000-4000-8000-000000000002'and operation.action='convert'limit 1),'99910000-0000-4000-8000-000000000099'::uuid,'conversion movement preserves the actor');

create temp table restoration on commit drop as select public.restore_product_conversion_state('99910000-0000-4000-8000-000000000002','Conversión revertida',true,(select payload->>'reference'from conversion))payload;
select is((select inventory_qty from public.products where id='99910000-0000-4000-8000-000000000002'),2,'safe restoration returns original physical stock');
select is((select purchase_treatment from public.products where id='99910000-0000-4000-8000-000000000002'),'inventory','restoration returns original inventory treatment');
select ok(exists(select 1 from public.inventory_accounting_operations where document_id='99910000-0000-4000-8000-000000000002'and source_channel='product_conversion'and action='restore'and outcome='completed'),'restoration creates its own completed trace');
select ok(exists(select 1 from public.stock_movements movement join public.inventory_accounting_operations operation on operation.id=movement.operation_id where operation.document_id='99910000-0000-4000-8000-000000000002'and operation.action='restore'and movement.quantity=2 and movement.stock_before=0 and movement.stock_after=2),'restoration movement is attached with exact balances');
select ok(exists(select 1 from public.stock_movements restore join public.stock_movements original on original.id=restore.reversal_of_id join public.inventory_accounting_operations operation on operation.id=restore.operation_id where operation.action='restore'and original.reference=(select payload->>'reference'from conversion)),'restoration movement points to the conversion movement');
select ok(exists(select 1 from public.journal_entries restore join public.journal_entries original on original.id=restore.reversal_of_id join public.inventory_accounting_operations operation on operation.id=restore.operation_id where operation.action='restore'and restore.total_debit=restore.total_credit),'restoration journal points to and reverses the conversion journal');
select is((select count(*)::integer from public.inventory_accounting_operations where document_id='99910000-0000-4000-8000-000000000002'and source_channel='product_conversion'),2,'conversion lifecycle has exactly one operation per accepted action');
select is((select count(*)::integer from public.stock_movements movement join public.inventory_accounting_operations operation on operation.id=movement.operation_id where operation.document_id='99910000-0000-4000-8000-000000000002'and operation.source_channel='product_conversion'),2,'conversion lifecycle has exactly two linked physical movements');
select is((select inventory_qty-stock_quantity from public.products where id='99910000-0000-4000-8000-000000000002'),0,'conversion lifecycle preserves dual-column equality');

select * from finish();
rollback;
