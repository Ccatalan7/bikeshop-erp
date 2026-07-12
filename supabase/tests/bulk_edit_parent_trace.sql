begin;
select set_config('request.jwt.claims','{}',true);select set_config('request.jwt.claim.sub','',true);select plan(12);
insert into public.tenants(id,shop_name)values('99930000-0000-4000-8000-000000000001','Bulk Parent Trace Test');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99930000-0000-4000-8000-000000000099','authenticated','authenticated','bulk@example.invalid','',now(),'{}'::jsonb,jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99930000-0000-4000-8000-000000000001'),now(),now());
insert into public.user_profiles(user_id,tenant_id,role)values('99930000-0000-4000-8000-000000000099','99930000-0000-4000-8000-000000000001','admin');update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','99930000-0000-4000-8000-000000000001')where id='99930000-0000-4000-8000-000000000099';
select set_config('request.jwt.claims',jsonb_build_object('sub','99930000-0000-4000-8000-000000000099','role','authenticated')::text,true);select set_config('request.jwt.claim.sub','99930000-0000-4000-8000-000000000099',true);
insert into public.products(id,tenant_id,name,sku,price,cost,product_type,is_service,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level)values
('99930000-0000-4000-8000-000000000002','99930000-0000-4000-8000-000000000001','Bulk A','BULK-A',1000,500,'product',false,true,5,5,0,20),
('99930000-0000-4000-8000-000000000003','99930000-0000-4000-8000-000000000001','Bulk B','BULK-B',1000,500,'product',false,true,5,5,0,20);
create temp table child_a on commit drop as select public.apply_inventory_stock_adjustment('99930000-0000-4000-8000-000000000002',1,'IN','count','Conteo masivo',now(),'mass_edit_panel')payload;
create temp table child_b on commit drop as select public.apply_inventory_stock_adjustment('99930000-0000-4000-8000-000000000003',2,'OUT','count','Conteo masivo',now(),'mass_edit_panel')payload;
insert into public.product_bulk_edit_history(id,tenant_id,operation,scope_source,status,scope_product_count,enabled_product_count,succeeded_product_count,skipped_product_count,failed_product_count,product_changes,created_by)
values('99930000-0000-4000-8000-000000000010','99930000-0000-4000-8000-000000000001','stock','selected','completed',2,2,2,0,0,'[]','99930000-0000-4000-8000-000000000099');
create temp table parent on commit drop as select public.link_product_bulk_edit_operations('99930000-0000-4000-8000-000000000010',array[(select(payload->>'operation_id')::uuid from child_a),(select(payload->>'operation_id')::uuid from child_b)])payload;
select ok(not(select(payload->>'replayed')::boolean from parent),'first parent link is newly created');
select is((select(payload->>'child_operation_count')::integer from parent),2,'parent records both stock-changing children');
select is((select operation_id from public.product_bulk_edit_history where id='99930000-0000-4000-8000-000000000010'),(select(payload->>'operation_id')::uuid from parent),'history points to its common parent operation');
select ok(exists(select 1 from public.inventory_accounting_operations where id=(select(payload->>'operation_id')::uuid from parent)and source_channel='mass_edit_panel'and action='batch_update'and outcome='completed'),'parent operation is completed and source classified');
select is((select count(*)::integer from public.inventory_accounting_operations where context->>'parent_operation_id'=(select payload->>'operation_id'from parent)),2,'both child operations point back to the parent');
select ok(exists(select 1 from public.inventory_accounting_checkpoints where operation_id=(select(payload->>'operation_id')::uuid from parent)and phase='inventory_applied'and(payload->>'child_operation_count')::integer=2),'parent checkpoint summarizes child application');
select is((select inventory_qty from public.products where id='99930000-0000-4000-8000-000000000002'),6,'first child stock is correct');
select is((select inventory_qty from public.products where id='99930000-0000-4000-8000-000000000003'),3,'second child stock is correct');
select ok((public.link_product_bulk_edit_operations('99930000-0000-4000-8000-000000000010',array[(select(payload->>'operation_id')::uuid from child_a),(select(payload->>'operation_id')::uuid from child_b)])->>'replayed')::boolean,'parent linking is idempotent');
select is((select count(*)::integer from public.inventory_accounting_operations where document_type='product_bulk_edit'and document_id='99930000-0000-4000-8000-000000000010'),1,'retry creates no second parent');
select throws_ok($$select public.link_product_bulk_edit_operations('99930000-0000-4000-8000-000000000088','{}')$$,'P0001','Bulk edit history not found for current tenant','unknown history is rejected');
select is((select count(*)::integer from public.journal_entries where operation_id in((select(payload->>'operation_id')::uuid from child_a),(select(payload->>'operation_id')::uuid from child_b))and total_debit=total_credit),2,'each stock child retains its own balanced value journal');
select * from finish();rollback;
