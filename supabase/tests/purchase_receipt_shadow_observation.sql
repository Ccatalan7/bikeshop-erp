begin;
select plan(13);

insert into public.tenants(id,shop_name)
values('a1000000-0000-4000-8000-000000000001','Receipt Shadow Observer Test');
insert into auth.users(
 id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at
)values(
 'a1000000-0000-4000-8000-000000000099','authenticated','authenticated',
 'receipt-shadow@example.invalid','',now(),'{}',
 jsonb_build_object('tenant_id','a1000000-0000-4000-8000-000000000001'),now(),now()
);
update public.user_profiles set tenant_id='a1000000-0000-4000-8000-000000000001',role='admin'
where user_id='a1000000-0000-4000-8000-000000000099';
update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','a1000000-0000-4000-8000-000000000001')
where id='a1000000-0000-4000-8000-000000000099';
select set_config('request.jwt.claim.sub','a1000000-0000-4000-8000-000000000099',true);
select set_config('request.jwt.claims',jsonb_build_object('sub','a1000000-0000-4000-8000-000000000099','role','authenticated')::text,true);

insert into public.products(
 id,tenant_id,name,sku,price,cost,product_type,is_service,track_stock,
 inventory_qty,stock_quantity,min_stock_level,max_stock_level
)values
 ('a1000000-0000-4000-8000-000000000010','a1000000-0000-4000-8000-000000000001','Disabled product','SHADOW-DISABLED',1000,500,'product',false,true,0,0,0,100),
 ('a1000000-0000-4000-8000-000000000011','a1000000-0000-4000-8000-000000000001','Shadow product','SHADOW-OBSERVED',1000,500,'product',false,true,0,0,0,100),
 ('a1000000-0000-4000-8000-000000000012','a1000000-0000-4000-8000-000000000001','Enforce product','SHADOW-ENFORCE',1000,500,'product',false,true,0,0,0,100);
insert into public.purchase_invoices(
 id,tenant_id,invoice_number,supplier_name,status,subtotal,net_amount,tax,total,balance,items
)values
 ('a1000000-0000-4000-8000-000000000020','a1000000-0000-4000-8000-000000000001','FC-SHADOW-DISABLED','Supplier','confirmed',1000,1000,0,1000,1000,'[{"line_id":"disabled","product_id":"a1000000-0000-4000-8000-000000000010","product_name":"Disabled product","quantity":2,"unit_cost":500,"purchase_treatment":"inventory"}]'),
 ('a1000000-0000-4000-8000-000000000021','a1000000-0000-4000-8000-000000000001','FC-SHADOW-OBSERVED','Supplier','confirmed',1000,1000,0,1000,1000,'[{"line_id":"shadow","product_id":"a1000000-0000-4000-8000-000000000011","product_name":"Shadow product","quantity":2,"unit_cost":500,"purchase_treatment":"inventory"}]'),
 ('a1000000-0000-4000-8000-000000000022','a1000000-0000-4000-8000-000000000001','FC-SHADOW-ENFORCE','Supplier','confirmed',1000,1000,0,1000,1000,'[{"line_id":"enforce","product_id":"a1000000-0000-4000-8000-000000000012","product_name":"Enforce product","quantity":2,"unit_cost":500,"purchase_treatment":"inventory"}]');

update public.purchase_invoices set status='received',received_date=now()
where id='a1000000-0000-4000-8000-000000000020';
select is((select count(*)::integer from public.purchase_receipt_compatibility_events),0,'disabled mode creates no observation event');
select is((select inventory_qty from public.products where id='a1000000-0000-4000-8000-000000000010'),2,'disabled legacy writer retains its stock behavior');

insert into public.purchase_receipt_control_settings(tenant_id,control_mode,activated_at,activated_by)
values('a1000000-0000-4000-8000-000000000001','shadow',now(),'a1000000-0000-4000-8000-000000000099');
update public.purchase_invoices set status='received',received_date=now()
where id='a1000000-0000-4000-8000-000000000021';

select is((select count(*)::integer from public.purchase_receipt_compatibility_events),1,'shadow mode records one legacy receipt event');
select is((select purchase_invoice_id from public.purchase_receipt_compatibility_events),'a1000000-0000-4000-8000-000000000021'::uuid,'event identifies the exact invoice');
select is((select actor_id from public.purchase_receipt_compatibility_events),'a1000000-0000-4000-8000-000000000099'::uuid,'event identifies the acting user');
select ok((select operation_id is not null from public.purchase_receipt_compatibility_events),'event links the invoice trace operation');
select is((select outcome from public.inventory_accounting_operations operation join public.purchase_receipt_compatibility_events event on event.operation_id=operation.id),'completed','linked invoice operation completed');
select is((select inventory_qty from public.products where id='a1000000-0000-4000-8000-000000000011'),2,'shadow observer does not alter legacy stock behavior');
select throws_ok($$update public.purchase_receipt_compatibility_events set old_status='tampered'$$,'23514','Purchase receipt compatibility events are append-only','event evidence cannot be edited');

update public.purchase_receipt_control_settings set control_mode='enforce' where tenant_id='a1000000-0000-4000-8000-000000000001';
select throws_ok(
 $$update public.purchase_invoices set status='received',received_date=now() where id='a1000000-0000-4000-8000-000000000022'$$,
 'P0001','Professional receiving is active; use the goods receipt command',
 'enforce mode still blocks legacy receipt before stock effects'
);
select is((select status from public.purchase_invoices where id='a1000000-0000-4000-8000-000000000022'),'confirmed','blocked invoice remains confirmed');
select is((select inventory_qty from public.products where id='a1000000-0000-4000-8000-000000000012'),0,'blocked legacy write leaves stock unchanged');
select is((select count(*)::integer from public.purchase_receipt_compatibility_events),1,'blocked transaction creates no false shadow event');

select * from finish();
rollback;
