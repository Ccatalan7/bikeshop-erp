begin;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
select plan(45);

insert into public.tenants(id,shop_name) values('99400000-0000-4000-8000-000000000001','Purchase Credit Note Test');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99400000-0000-4000-8000-000000000099','authenticated','authenticated','purchase-credit@example.invalid','',now(),'{}'::jsonb,
jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99400000-0000-4000-8000-000000000001'),now(),now());
insert into public.user_profiles(user_id,tenant_id,role) values('99400000-0000-4000-8000-000000000099','99400000-0000-4000-8000-000000000001','admin');
update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','99400000-0000-4000-8000-000000000001') where id='99400000-0000-4000-8000-000000000099';
select set_config('request.jwt.claims',jsonb_build_object('sub','99400000-0000-4000-8000-000000000099','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99400000-0000-4000-8000-000000000099',true);

insert into public.products(id,tenant_id,name,sku,price,cost,product_type,is_service,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level)
values
('99400000-0000-4000-8000-000000000002','99400000-0000-4000-8000-000000000001','Credit Inventory Product','CN-INV',2000,1000,'product',false,true,0,0,0,100),
('99400000-0000-4000-8000-000000000003','99400000-0000-4000-8000-000000000001','Credit Consumable','CN-CONS',2000,1000,'product',false,false,0,0,0,100);
insert into public.purchase_invoices(id,tenant_id,invoice_number,supplier_name,status,subtotal,net_amount,tax,total,balance,tax_treatment,items)
values('99400000-0000-4000-8000-000000000004','99400000-0000-4000-8000-000000000001','FC-CREDIT-001','Credit Supplier','draft',10000,10000,1900,11900,11900,'tax_included',
jsonb_build_array(
 jsonb_build_object('line_id','credit-line-inventory','product_id','99400000-0000-4000-8000-000000000002','product_name','Credit Inventory Product','product_sku','CN-INV','quantity',6,'unit_cost',1000,'discount',0,'purchase_treatment','inventory','is_service',false),
 jsonb_build_object('line_id','credit-line-consumable','product_id','99400000-0000-4000-8000-000000000003','product_name','Credit Consumable','product_sku','CN-CONS','quantity',4,'unit_cost',1000,'discount',0,'purchase_treatment','workshop_consumable','is_service',false)
));
update public.purchase_invoices set status='confirmed',confirmed_date=now() where id='99400000-0000-4000-8000-000000000004';

select throws_ok($$select public.create_purchase_credit_note('99400000-0000-4000-8000-000000000004','[{"line_index":0,"credited_quantity":1}]'::jsonb,now(),'return','Disabled',null,'credit-disabled')$$,
'P0001','Purchase credit note workflow is not active for this tenant','credit note command is disabled by default');
select is((select count(*)::integer from public.purchase_credit_notes),0,'disabled command leaves no document');

insert into public.purchase_credit_note_control_settings(tenant_id,control_mode,activated_at,activated_by)
values('99400000-0000-4000-8000-000000000001','enforce',now(),'99400000-0000-4000-8000-000000000099');
insert into public.purchase_receipt_control_settings(tenant_id,control_mode,activated_at,activated_by)
values('99400000-0000-4000-8000-000000000001','enforce',now(),'99400000-0000-4000-8000-000000000099');

insert into public.purchase_payments(tenant_id,invoice_id,payment_method_id,idempotency_key,amount,date,reference)
select '99400000-0000-4000-8000-000000000001','99400000-0000-4000-8000-000000000004',id,'credit-payment-full',11900,now(),'Full payment'
from public.payment_methods where tenant_id='99400000-0000-4000-8000-000000000001' order by created_at limit 1;
select is((select status from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),'paid','fixture invoice is fully paid before credit');

create temp table first_credit on commit drop as
select public.create_purchase_credit_note(
'99400000-0000-4000-8000-000000000004',
'[{"line_index":0,"credited_quantity":2,"disposition":"financial_only"},{"line_index":1,"credited_quantity":1,"disposition":"financial_only"}]'::jsonb,
'2026-07-11 19:00:00+00','price_adjustment','Ajuste comercial parcial','NC-PROV-001','credit-first') payload;
select is((select phase_contract from public.professional_correction_trace_contract_view where operation_id=((select payload->>'operation_id' from first_credit)::uuid)),(select expected_phase_contract from public.professional_correction_trace_contract_view where operation_id=((select payload->>'operation_id' from first_credit)::uuid)),'purchase credit note has the full ordered trace contract');
select is((select total_amount from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)),3570::numeric,'mixed credit total uses original net and tax allocation');
select is((select net_amount from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)),3000::numeric,'mixed credit stores exact net');
select is((select tax_amount from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)),570::numeric,'mixed credit stores exact recoverable tax reversal');
select is((select official_dte_status from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)),'internal','internal document does not claim official DTE issuance');
select is((select count(*)::integer from public.purchase_credit_note_lines where purchase_credit_note_id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)),2,'credit preserves both original invoice line links');
select ok(exists(select 1 from public.journal_entries where id=(select journal_entry_id from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)) and total_debit=3570 and total_credit=3570),'credit journal is balanced');
select is((select debit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)) and account_code='2101'),3570::numeric,'credit debits supplier payable');
select is((select credit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)) and account_code='1105'),2000::numeric,'credit reverses inventory value for inventory line');
select is((select credit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)) and account_code='5101'),1000::numeric,'credit reverses workshop consumable expense');
select is((select credit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)) and account_code='2120'),570::numeric,'credit reverses recoverable tax');
select is((select count(*)::integer from public.stock_movements where operation_id=((select payload->>'operation_id' from first_credit)::uuid)),0,'financial credit creates zero stock movements');
select is((select inventory_qty from public.products where id='99400000-0000-4000-8000-000000000002'),0,'financial credit leaves physical stock unchanged');
select is((select credited_amount from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),3570::numeric,'invoice settlement stores posted credit total');
select is((select balance from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),0::numeric,'paid credited invoice has no payable balance');
select is((select supplier_credit_balance from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),3570::numeric,'paid invoice exposes supplier credit instead of phantom payment');
select is((select status from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),'paid','credit does not falsely undo the original payment');
select ok(exists(select 1 from public.inventory_accounting_operations where id=((select payload->>'operation_id' from first_credit)::uuid) and outcome='completed'),'credit completes connected trace operation');
select ok((public.create_purchase_credit_note('99400000-0000-4000-8000-000000000004','[{"line_index":0,"credited_quantity":2}]'::jsonb,now(),'retry','Retry',null,'credit-first')->>'replayed')::boolean,'credit command is idempotent');
select is((select count(*)::integer from public.purchase_credit_notes),1,'credit retry creates no second document');
select throws_ok($$select public.create_purchase_credit_note('99400000-0000-4000-8000-000000000004','[{"line_index":0,"credited_quantity":5}]'::jsonb,now(),'over','Over credit',null,'credit-over')$$,
'P0001','Purchase credit quantity exceeds original line balance','cumulative quantity over-credit is blocked');

create temp table source_receipt on commit drop as
select public.create_purchase_goods_receipt('99400000-0000-4000-8000-000000000004','[{"line_index":0,"accepted_quantity":4}]'::jsonb,now(),'GUIA-CREDIT', 'Bodega principal',null,'credit-source-receipt') payload;
select is((select inventory_qty from public.products where id='99400000-0000-4000-8000-000000000002'),4,'receipt adds physical stock before supplier return');
create temp table source_return on commit drop as
select public.create_purchase_supplier_return(
(select (payload->>'receipt_id')::uuid from source_receipt),
jsonb_build_array(jsonb_build_object('receipt_line_id',(select id from public.purchase_receipt_lines where receipt_id=(select (payload->>'receipt_id')::uuid from source_receipt)),'returned_quantity',2)),
now(),'Return for supplier credit','ENV-CREDIT',null,'credit-source-return') payload;
select is((select inventory_qty from public.products where id='99400000-0000-4000-8000-000000000002'),2,'supplier return owns the physical stock decrease');

create temp table linked_credit on commit drop as
select public.create_purchase_credit_note(
'99400000-0000-4000-8000-000000000004',
jsonb_build_array(jsonb_build_object('line_index',0,'credited_quantity',2,'disposition','supplier_return','supplier_return_line_id',(select id from public.purchase_supplier_return_lines where supplier_return_id=(select (payload->>'supplier_return_id')::uuid from source_return)))),
now(),'goods_return','Mercadería devuelta','NC-PROV-002','credit-linked-return') payload;
select ok(exists(select 1 from public.purchase_credit_note_lines where purchase_credit_note_id=((select payload->>'purchase_credit_note_id' from linked_credit)::uuid) and supplier_return_line_id is not null),'financial credit links to exact supplier return line');
select is((select credit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from linked_credit)::uuid)) and account_code='1145'),2000::numeric,'return-backed credit clears the supplier claim instead of crediting inventory twice');
select is((select inventory_qty from public.products where id='99400000-0000-4000-8000-000000000002'),2,'return-backed credit does not move stock a second time');
select is((select supplier_credit_balance from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),5950::numeric,'second credit increases explicit supplier credit balance');
select throws_ok(format('select public.void_purchase_supplier_return(%L::uuid,%L,%L)',(select payload->>'supplier_return_id' from source_return),'Blocked linked return','blocked-return-void'),
'P0001','Void linked purchase credit notes before voiding this supplier return','posted financial credit protects its physical return evidence');
select throws_ok($$update public.purchase_invoices set total=12000 where id='99400000-0000-4000-8000-000000000004'$$,
'P0001','Void posted purchase credit notes before editing invoice financial lines','posted credit freezes original invoice financial values');
select is((select total from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),11900::numeric,'blocked invoice edit leaves original total unchanged');

create temp table linked_void on commit drop as
select public.void_purchase_credit_note((select (payload->>'purchase_credit_note_id')::uuid from linked_credit),'Supplier rejected credit','credit-linked-void') payload;
select is((select phase_contract from public.professional_correction_trace_contract_view where operation_id=((select payload->>'operation_id' from linked_void)::uuid)),(select expected_phase_contract from public.professional_correction_trace_contract_view where operation_id=((select payload->>'operation_id' from linked_void)::uuid)),'purchase credit-note void has the full ordered trace contract');
select is((select status from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from linked_credit)::uuid)),'voided','credit void preserves document as voided');
select is((select credited_amount from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),3570::numeric,'credit void recalculates invoice credit total');
select ok(exists(select 1 from public.journal_entries where id=(select void_journal_entry_id from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from linked_credit)::uuid)) and reversal_of_id=(select journal_entry_id from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from linked_credit)::uuid)) and total_debit=total_credit),'credit void appends balanced linked journal reversal');
select ok((public.void_purchase_credit_note((select (payload->>'purchase_credit_note_id')::uuid from linked_credit),'Supplier rejected credit','credit-linked-void')->>'replayed')::boolean,'credit void is idempotent');
select lives_ok(format('select public.void_purchase_supplier_return(%L::uuid,%L,%L)',(select payload->>'supplier_return_id' from source_return),'Credit voided','return-void-after-credit'),'supplier return can be voided after linked credit is voided');
select is((select inventory_qty from public.products where id='99400000-0000-4000-8000-000000000002'),4,'supplier return void restores physical stock exactly once');

update public.purchase_credit_notes set official_dte_status='issued' where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid);
select throws_ok(format('select public.void_purchase_credit_note(%L::uuid,%L,%L)',(select payload->>'purchase_credit_note_id' from first_credit),'Invalid internal void','issued-credit-void'),
'P0001','Issued tax credit notes require an official reversal document','issued DTE cannot be internally voided');
select is((select status from public.purchase_credit_notes where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid)),'posted','failed issued-DTE void leaves credit posted');
update public.purchase_credit_notes set official_dte_status='internal' where id=((select payload->>'purchase_credit_note_id' from first_credit)::uuid);
select public.void_purchase_credit_note((select (payload->>'purchase_credit_note_id')::uuid from first_credit),'Internal correction','credit-first-void');
select is((select credited_amount from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),0::numeric,'voiding all credits restores zero credited amount');
select is((select supplier_credit_balance from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),0::numeric,'voiding all credits clears supplier credit balance');
select is((select paid_amount from public.purchase_invoices where id='99400000-0000-4000-8000-000000000004'),11900::numeric,'credit lifecycle never mutates payment amount');

select * from finish();
rollback;
