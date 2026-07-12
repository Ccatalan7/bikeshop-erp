begin;
select plan(42);

insert into public.tenants(id,shop_name)values
 ('a2000000-0000-4000-8000-000000000001','Credit Cash Settlement Test'),
 ('a2000000-0000-4000-8000-000000000002','Credit Cash Settlement Other');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)values
 ('a2000000-0000-4000-8000-000000000099','authenticated','authenticated','credit-refund@example.invalid','',now(),'{}',jsonb_build_object('tenant_id','a2000000-0000-4000-8000-000000000001'),now(),now()),
 ('a2000000-0000-4000-8000-000000000098','authenticated','authenticated','credit-refund-other@example.invalid','',now(),'{}',jsonb_build_object('tenant_id','a2000000-0000-4000-8000-000000000002'),now(),now());
update public.user_profiles set tenant_id='a2000000-0000-4000-8000-000000000001',role='admin'where user_id='a2000000-0000-4000-8000-000000000099';
update public.user_profiles set tenant_id='a2000000-0000-4000-8000-000000000002',role='admin'where user_id='a2000000-0000-4000-8000-000000000098';
update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','a2000000-0000-4000-8000-000000000001')where id='a2000000-0000-4000-8000-000000000099';
update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','a2000000-0000-4000-8000-000000000002')where id='a2000000-0000-4000-8000-000000000098';
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000099',true);
select set_config('request.jwt.claims',jsonb_build_object('sub','a2000000-0000-4000-8000-000000000099','role','authenticated')::text,true);
select is(coalesce((select control_mode from public.sales_customer_refund_control_settings where tenant_id='a2000000-0000-4000-8000-000000000001'),'disabled'),'disabled','customer refund workflow defaults inactive');
select is(coalesce((select control_mode from public.purchase_supplier_refund_control_settings where tenant_id='a2000000-0000-4000-8000-000000000001'),'disabled'),'disabled','supplier refund workflow defaults inactive');

insert into public.products(id,tenant_id,name,sku,price,cost,product_type,is_service,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level)
values('a2000000-0000-4000-8000-000000000010','a2000000-0000-4000-8000-000000000001','Credit settlement product','CREDIT-SETTLE',1190,1000,'product',false,true,10,10,0,100);
insert into public.sales_invoices(id,tenant_id,invoice_number,customer_name,status,subtotal,net_amount,iva_amount,total,balance,tax_treatment,items)
values('a2000000-0000-4000-8000-000000000020','a2000000-0000-4000-8000-000000000001','FV-REFUND-001','Refund Customer','confirmed',2000,2000,380,2380,2380,'tax_included','[{"line_id":"sales-refund-line","product_id":"a2000000-0000-4000-8000-000000000010","product_name":"Credit settlement product","quantity":2,"unit_price":1000,"price":1000,"cost":1000,"is_service":false}]');
insert into public.sales_payments(tenant_id,invoice_id,payment_method_id,idempotency_key,amount,reference)
select 'a2000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000020',id,'sales-refund-payment',2380,'Original payment'from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000001'and code='transfer';
insert into public.sales_credit_note_control_settings(tenant_id,control_mode,activated_at,activated_by)
values('a2000000-0000-4000-8000-000000000001','enforce',now(),'a2000000-0000-4000-8000-000000000099');
insert into public.sales_customer_refund_control_settings(tenant_id,control_mode,activated_at,activated_by)
values('a2000000-0000-4000-8000-000000000001','enforce',now(),'a2000000-0000-4000-8000-000000000099');
create temp table settlement_ids(name text primary key,id uuid not null)on commit drop;
insert into settlement_ids select 'sales_note',(public.create_sales_credit_note('a2000000-0000-4000-8000-000000000020','[{"line_index":0,"credited_quantity":1,"disposition":"financial_only"}]',now(),'price_adjustment','Sales refund credit','sales-refund-note')->>'sales_credit_note_id')::uuid;

select is((select customer_credit_balance from public.sales_invoices where id='a2000000-0000-4000-8000-000000000020'),1190::numeric,'paid sales credit creates explicit customer credit');
select throws_ok(format($$select public.create_sales_customer_refund(%L::uuid,now(),(select id from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000001'and code='transfer'),1000,'','Reason','missing-ref')$$,(select id from settlement_ids where name='sales_note')),'P0001','Refund reference, reason, and idempotency key are required','sales refund requires external reference');
insert into settlement_ids select 'sales_refund',(public.create_sales_customer_refund((select id from settlement_ids where name='sales_note'),now(),(select id from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000001'and code='transfer'),1000,'BANK-OUT-001','Verified customer transfer','sales-refund-create')->>'refund_id')::uuid;
select is((select status from public.sales_customer_refunds where id=(select id from settlement_ids where name='sales_refund')),'posted','customer refund document is posted');
select is((select amount from public.sales_customer_refunds where id=(select id from settlement_ids where name='sales_refund')),1000::numeric,'customer refund stores exact whole CLP');
select is((select reference from public.sales_customer_refunds where id=(select id from settlement_ids where name='sales_refund')),'BANK-OUT-001','customer refund stores external transfer evidence');
select is((select refunded_amount from public.sales_invoices where id='a2000000-0000-4000-8000-000000000020'),1000::numeric,'invoice exposes money actually refunded');
select is((select paid_amount from public.sales_invoices where id='a2000000-0000-4000-8000-000000000020'),2380::numeric,'refund preserves original collected payment evidence');
select is((select customer_credit_balance from public.sales_invoices where id='a2000000-0000-4000-8000-000000000020'),190::numeric,'refund reduces customer credit without phantom balance');
select is((select debit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.sales_customer_refunds where id=(select id from settlement_ids where name='sales_refund'))and account_code='1130'),1000::numeric,'customer refund debits receivable credit balance');
select is((select credit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.sales_customer_refunds where id=(select id from settlement_ids where name='sales_refund'))and account_code=(select account.code from public.payment_methods method join public.accounts account on account.id=method.account_id where method.id=(select payment_method_id from public.sales_customer_refunds where id=(select id from settlement_ids where name='sales_refund')))),1000::numeric,'customer refund credits the selected cash or bank account');
select is((select count(*)::integer from public.stock_movements where operation_id=(select operation_id from public.sales_customer_refunds where id=(select id from settlement_ids where name='sales_refund'))),0,'customer refund has zero stock movements');
select ok(exists(select 1 from public.inventory_accounting_operations where id=(select operation_id from public.sales_customer_refunds where id=(select id from settlement_ids where name='sales_refund'))and outcome='completed'),'customer refund operation completes');
select ok((public.create_sales_customer_refund((select id from settlement_ids where name='sales_note'),now(),(select id from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000001'and code='transfer'),1000,'RETRY','Retry','sales-refund-create')->>'replayed')::boolean,'customer refund create is idempotent');
select is((select count(*)::integer from public.sales_customer_refunds),1,'customer refund replay creates no duplicate');
select throws_ok(format($$select public.create_sales_customer_refund(%L::uuid,now(),(select id from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000001'and code='transfer'),191,'BANK-OVER','Over','sales-refund-over')$$,(select id from settlement_ids where name='sales_note')),'P0001','Refund exceeds available customer credit balance: 190.00','customer refund cannot exceed remaining credit');
select throws_ok(format($$select public.void_sales_credit_note(%L::uuid,'Blocked','sales-note-blocked')$$,(select id from settlement_ids where name='sales_note')),'P0001','Void posted customer refunds before voiding this sales credit note','posted refund protects its credit note');

insert into public.purchase_invoices(id,tenant_id,invoice_number,supplier_name,status,subtotal,net_amount,tax,total,balance,tax_treatment,items)
values('a2000000-0000-4000-8000-000000000030','a2000000-0000-4000-8000-000000000001','FC-REFUND-001','Refund Supplier','confirmed',2000,2000,380,2380,2380,'tax_included','[{"line_id":"purchase-refund-line","product_id":"a2000000-0000-4000-8000-000000000010","product_name":"Credit settlement product","quantity":2,"unit_cost":1000,"purchase_treatment":"inventory","is_service":false}]');
insert into public.purchase_payments(tenant_id,invoice_id,payment_method_id,idempotency_key,amount,reference)
select 'a2000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000030',id,'purchase-refund-payment',2380,'Original supplier payment'from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000001'and code='transfer';
insert into public.purchase_credit_note_control_settings(tenant_id,control_mode,activated_at,activated_by)
values('a2000000-0000-4000-8000-000000000001','enforce',now(),'a2000000-0000-4000-8000-000000000099');
insert into public.purchase_supplier_refund_control_settings(tenant_id,control_mode,activated_at,activated_by)
values('a2000000-0000-4000-8000-000000000001','enforce',now(),'a2000000-0000-4000-8000-000000000099');
insert into settlement_ids select 'purchase_note',(public.create_purchase_credit_note('a2000000-0000-4000-8000-000000000030','[{"line_index":0,"credited_quantity":1,"disposition":"financial_only"}]',now(),'price_adjustment','Supplier refund credit','NC-SUP-REFUND','purchase-refund-note')->>'purchase_credit_note_id')::uuid;
select is((select supplier_credit_balance from public.purchase_invoices where id='a2000000-0000-4000-8000-000000000030'),1190::numeric,'paid purchase credit creates explicit supplier credit');
insert into settlement_ids select 'purchase_refund',(public.create_purchase_supplier_refund((select id from settlement_ids where name='purchase_note'),now(),(select id from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000001'and code='transfer'),1000,'BANK-IN-001','Verified supplier transfer','purchase-refund-create')->>'refund_id')::uuid;
select is((select status from public.purchase_supplier_refunds where id=(select id from settlement_ids where name='purchase_refund')),'posted','supplier refund document is posted');
select is((select supplier_refunded_amount from public.purchase_invoices where id='a2000000-0000-4000-8000-000000000030'),1000::numeric,'purchase invoice exposes money returned by supplier');
select is((select supplier_credit_balance from public.purchase_invoices where id='a2000000-0000-4000-8000-000000000030'),190::numeric,'supplier refund reduces supplier credit');
select is((select debit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.purchase_supplier_refunds where id=(select id from settlement_ids where name='purchase_refund'))and account_code=(select account.code from public.payment_methods method join public.accounts account on account.id=method.account_id where method.id=(select payment_method_id from public.purchase_supplier_refunds where id=(select id from settlement_ids where name='purchase_refund')))),1000::numeric,'supplier refund debits selected cash or bank');
select is((select credit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.purchase_supplier_refunds where id=(select id from settlement_ids where name='purchase_refund'))and account_code='2101'),1000::numeric,'supplier refund credits payable balance');
select is((select count(*)::integer from public.stock_movements where operation_id=(select operation_id from public.purchase_supplier_refunds where id=(select id from settlement_ids where name='purchase_refund'))),0,'supplier refund has zero stock movements');
select ok((public.create_purchase_supplier_refund((select id from settlement_ids where name='purchase_note'),now(),(select id from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000001'and code='transfer'),1000,'RETRY','Retry','purchase-refund-create')->>'replayed')::boolean,'supplier refund create is idempotent');
select throws_ok(format($$select public.create_purchase_supplier_refund(%L::uuid,now(),(select id from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000001'and code='transfer'),191,'BANK-OVER','Over','purchase-refund-over')$$,(select id from settlement_ids where name='purchase_note')),'P0001','Refund exceeds available supplier credit balance: 190.00','supplier refund cannot exceed remaining credit');
select throws_ok(format($$select public.void_purchase_credit_note(%L::uuid,'Blocked','purchase-note-blocked')$$,(select id from settlement_ids where name='purchase_note')),'P0001','Void posted supplier refunds before voiding this purchase credit note','posted supplier refund protects credit note');

select ok((public.void_sales_customer_refund((select id from settlement_ids where name='sales_refund'),'Incorrect transfer','sales-refund-void')->>'replayed')::boolean=false,'customer refund void posts reversal');
select is((select status from public.sales_customer_refunds where id=(select id from settlement_ids where name='sales_refund')),'voided','customer refund is preserved as voided');
select is((select refunded_amount from public.sales_invoices where id='a2000000-0000-4000-8000-000000000020'),0::numeric,'customer refund void clears refunded total');
select is((select customer_credit_balance from public.sales_invoices where id='a2000000-0000-4000-8000-000000000020'),1190::numeric,'customer refund void restores credit balance');
select ok(exists(select 1 from public.journal_entries entry join public.sales_customer_refunds refund on refund.void_journal_entry_id=entry.id where refund.id=(select id from settlement_ids where name='sales_refund')and entry.reversal_of_id=refund.journal_entry_id and entry.total_debit=entry.total_credit),'customer refund void owns linked balanced reversal');
select ok((public.void_sales_customer_refund((select id from settlement_ids where name='sales_refund'),'Incorrect transfer','sales-refund-void')->>'replayed')::boolean,'customer refund void is idempotent');
select lives_ok(format($$select public.void_sales_credit_note(%L::uuid,'Refund voided','sales-note-after-refund')$$,(select id from settlement_ids where name='sales_note')),'sales credit note can void after refund void');

select public.void_purchase_supplier_refund((select id from settlement_ids where name='purchase_refund'),'Incorrect receipt','purchase-refund-void');
select is((select status from public.purchase_supplier_refunds where id=(select id from settlement_ids where name='purchase_refund')),'voided','supplier refund is preserved as voided');
select is((select supplier_refunded_amount from public.purchase_invoices where id='a2000000-0000-4000-8000-000000000030'),0::numeric,'supplier refund void clears refunded total');
select is((select supplier_credit_balance from public.purchase_invoices where id='a2000000-0000-4000-8000-000000000030'),1190::numeric,'supplier refund void restores supplier credit');
select ok(exists(select 1 from public.journal_entries entry join public.purchase_supplier_refunds refund on refund.void_journal_entry_id=entry.id where refund.id=(select id from settlement_ids where name='purchase_refund')and entry.reversal_of_id=refund.journal_entry_id and entry.total_debit=entry.total_credit),'supplier refund void owns linked balanced reversal');
select lives_ok(format($$select public.void_purchase_credit_note(%L::uuid,'Refund voided','purchase-note-after-refund')$$,(select id from settlement_ids where name='purchase_note')),'purchase credit note can void after refund void');

select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000098',true);select set_config('request.jwt.claims',jsonb_build_object('sub','a2000000-0000-4000-8000-000000000098','role','authenticated')::text,true);
select throws_ok(format($$select public.create_sales_customer_refund(%L::uuid,now(),(select id from public.payment_methods where tenant_id='a2000000-0000-4000-8000-000000000002'limit 1),1,'CROSS','Cross','cross-refund')$$,(select id from settlement_ids where name='sales_note')),'P0001','Sales credit settlement is not active for this tenant','credit refund cannot cross tenant boundaries');
select is((select count(*)::integer from(select entry.id from public.journal_entries entry join public.journal_lines line on line.entry_id=entry.id where entry.tenant_id='a2000000-0000-4000-8000-000000000001'group by entry.id having sum(line.debit_amount)<>sum(line.credit_amount))broken),0,'all credit settlement journals remain balanced');

select * from finish();
rollback;
