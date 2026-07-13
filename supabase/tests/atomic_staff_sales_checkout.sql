begin;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
select plan(27);

insert into public.tenants(id,shop_name) values('99800000-0000-4000-8000-000000000001','Atomic Checkout Test');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99800000-0000-4000-8000-000000000099','authenticated','authenticated','checkout@example.invalid','',now(),'{}'::jsonb,
jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99800000-0000-4000-8000-000000000001'),now(),now());
insert into public.user_profiles(user_id,tenant_id,role) values('99800000-0000-4000-8000-000000000099','99800000-0000-4000-8000-000000000001','admin');
update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','99800000-0000-4000-8000-000000000001') where id='99800000-0000-4000-8000-000000000099';
select set_config('request.jwt.claims',jsonb_build_object('sub','99800000-0000-4000-8000-000000000099','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99800000-0000-4000-8000-000000000099',true);

insert into public.products(id,tenant_id,name,sku,price,cost,product_type,is_service,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level)
values('99800000-0000-4000-8000-000000000002','99800000-0000-4000-8000-000000000001','Atomic Product','ATOMIC-1',1190,500,'product',false,true,5,5,0,100);
create temp view checkout_methods as select id,row_number()over(order by created_at,id)ord from public.payment_methods where tenant_id='99800000-0000-4000-8000-000000000001' and is_active;

create temp table pos_checkout on commit drop as select public.create_atomic_sales_checkout(
 'pos','pos-checkout-1',null,'Cliente Mostrador',null,'Caja 1','tax_included',
 '[{"product_id":"99800000-0000-4000-8000-000000000002","quantity":2,"unit_price":1190,"discount":0}]',
 jsonb_build_array(
  jsonb_build_object('payment_method_id',(select id from checkout_methods where ord=1),'amount',1000,'reference','split-a'),
  jsonb_build_object('payment_method_id',(select id from checkout_methods where ord=2),'amount',1380,'reference','split-b')
 ),'2026-07-11 20:00:00+00')payload;

select ok(not (select (payload->>'replayed')::boolean from pos_checkout),'first checkout is newly applied');
select is((select source from public.sales_invoices where id=((select payload->>'invoice_id'from pos_checkout)::uuid)),'pos','invoice preserves POS origin');
select is((select status from public.sales_invoices where id=((select payload->>'invoice_id'from pos_checkout)::uuid)),'paid','invoice and all payments commit in one transaction');
select is((select total from public.sales_invoices where id=((select payload->>'invoice_id'from pos_checkout)::uuid)),2380::numeric,'server derives exact checkout total');
select is((select net_amount from public.sales_invoices where id=((select payload->>'invoice_id'from pos_checkout)::uuid)),2000::numeric,'server derives whole-CLP tax-exclusive amount');
select is((select iva_amount from public.sales_invoices where id=((select payload->>'invoice_id'from pos_checkout)::uuid)),380::numeric,'server derives exact IVA remainder');
select is((select count(*)::integer from public.sales_payments where invoice_id=((select payload->>'invoice_id'from pos_checkout)::uuid)and deleted_at is null),2,'split payments are committed together');
select is((select sum(amount)from public.sales_payments where invoice_id=((select payload->>'invoice_id'from pos_checkout)::uuid)and deleted_at is null),2380::numeric,'split payments reconcile exactly to invoice');
select is((select inventory_qty from public.products where id='99800000-0000-4000-8000-000000000002'),3,'atomic checkout consumes stock once');
select ok(exists(select 1 from public.stock_movements where source_document_id=((select payload->>'invoice_id'from pos_checkout)::uuid)and quantity=-2 and stock_before=5 and stock_after=3),'checkout movement stores exact source and balances');
select ok(exists(select 1 from public.inventory_accounting_operations where document_id=((select payload->>'invoice_id'from pos_checkout)::uuid)and source_channel='pos'and outcome='completed'),'checkout owns a completed invoice trace');
select ok(exists(select 1 from public.inventory_accounting_checkpoints checkpoint join public.inventory_accounting_operations operation on operation.id=checkpoint.operation_id where operation.document_id=((select payload->>'invoice_id'from pos_checkout)::uuid)and checkpoint.phase='invariants_verified'and checkpoint.payload->>'atomic_checkout'='true'),'trace certifies the atomic payment/invoice invariant');
select ok((public.create_atomic_sales_checkout('pos','pos-checkout-1',null,'Cliente Mostrador',null,'Caja 1','tax_included','[{"product_id":"99800000-0000-4000-8000-000000000002","quantity":2,"unit_price":1190,"discount":0}]',jsonb_build_array(jsonb_build_object('payment_method_id',(select id from checkout_methods where ord=1),'amount',1000,'reference','split-a'),jsonb_build_object('payment_method_id',(select id from checkout_methods where ord=2),'amount',1380,'reference','split-b')),'2026-07-11 20:00:00+00')->>'replayed')::boolean,'same-key retry returns the original invoice');
select is((select count(*)::integer from public.sales_invoices where checkout_idempotency_key='pos:pos-checkout-1'),1,'retry creates no duplicate invoice');
select is((select inventory_qty from public.products where id='99800000-0000-4000-8000-000000000002'),3,'retry consumes no additional stock');
select throws_ok(format('select public.create_atomic_sales_checkout(%L,%L,null,%L,null,null,%L,%L::jsonb,%L::jsonb,now())','pos','pos-checkout-1','Different','tax_included','[{"product_id":"99800000-0000-4000-8000-000000000002","quantity":1,"unit_price":1190,"discount":0}]',jsonb_build_array(jsonb_build_object('payment_method_id',(select id from checkout_methods where ord=1),'amount',1190))::text),'23000','Checkout key was already used with different sale content','same key with different content is rejected');

select throws_ok(format('select public.create_atomic_sales_checkout(%L,%L,null,%L,null,null,%L,%L::jsonb,%L::jsonb,now())','pos','bad-method','Cliente','no_tax','[{"product_id":"99800000-0000-4000-8000-000000000002","quantity":1,"unit_price":1190,"discount":0}]','[{"payment_method_id":"99800000-0000-4000-8000-000000000088","amount":1190}]'),'P0001','Checkout payment method not found or inactive','invalid payment method aborts checkout');
select is((select count(*)::integer from public.sales_invoices where checkout_idempotency_key='pos:bad-method'),0,'failed payment validation leaves no invoice');
select is((select inventory_qty from public.products where id='99800000-0000-4000-8000-000000000002'),3,'failed payment validation leaves stock unchanged');
select throws_ok(format('select public.create_atomic_sales_checkout(%L,%L,null,%L,null,null,%L,%L::jsonb,%L::jsonb,now())','pos','bad-total','Cliente','no_tax','[{"product_id":"99800000-0000-4000-8000-000000000002","quantity":1,"unit_price":1190,"discount":0}]',jsonb_build_array(jsonb_build_object('payment_method_id',(select id from checkout_methods where ord=1),'amount',1189))::text),'P0001','Checkout payment total must equal invoice total','payment mismatch aborts before inventory');
select throws_ok(format('select public.create_atomic_sales_checkout(%L,%L,null,%L,null,null,%L,%L::jsonb,%L::jsonb,now())','pos','fractional-item','Cliente','no_tax','[{"product_id":"99800000-0000-4000-8000-000000000002","quantity":1.5,"unit_price":1190,"discount":0}]',jsonb_build_array(jsonb_build_object('payment_method_id',(select id from checkout_methods where ord=1),'amount',1785))::text),'P0001','Checkout items require a product, positive whole units, and valid whole-CLP prices','fractional stock units are rejected');
create temp table negative_stock_checkout on commit drop as
select public.create_atomic_sales_checkout(
 'pos','negative-stock',null,'Cliente',null,null,'no_tax',
 '[{"product_id":"99800000-0000-4000-8000-000000000002","quantity":4,"unit_price":1190,"discount":0}]',
 jsonb_build_array(jsonb_build_object('payment_method_id',(select id from checkout_methods where ord=1),'amount',4760)),now()
) payload;
select is((select status from public.sales_invoices where id=((select payload->>'invoice_id'from negative_stock_checkout)::uuid)),'paid','staff checkout remains operational when stock crosses below zero');
select is((select inventory_qty from public.products where id='99800000-0000-4000-8000-000000000002'),-1,'staff checkout records the exact negative stock balance');
select ok(exists(select 1 from public.stock_movements where source_document_id=((select payload->>'invoice_id'from negative_stock_checkout)::uuid)and quantity=-4 and stock_before=3 and stock_after=-1),'negative stock sale keeps exact movement and source-document evidence');

create temp table quick_checkout on commit drop as select public.create_atomic_sales_checkout('quick_sale','quick-1',null,'Cliente Mostrador',null,null,'no_tax','[{"product_id":"99800000-0000-4000-8000-000000000002","quantity":1,"unit_price":1190,"discount":0}]',jsonb_build_array(jsonb_build_object('payment_method_id',(select id from checkout_methods where ord=1),'amount',1190)),now())payload;
select is((select source from public.sales_invoices where id=((select payload->>'invoice_id'from quick_checkout)::uuid)),'quick_sale','same atomic command preserves Quick Sale origin');
select is((select status from public.sales_invoices where id=((select payload->>'invoice_id'from quick_checkout)::uuid)),'paid','Quick Sale invoice and payment commit together');
select is((select inventory_qty from public.products where id='99800000-0000-4000-8000-000000000002'),-2,'Quick Sale consumes stock exactly once from an already-negative balance');

select * from finish();
rollback;
