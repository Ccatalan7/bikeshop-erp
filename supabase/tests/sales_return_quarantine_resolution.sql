begin;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
select plan(26);

insert into public.tenants(id,shop_name) values('99700000-0000-4000-8000-000000000001','Quarantine Resolution Test');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99700000-0000-4000-8000-000000000099','authenticated','authenticated','quarantine@example.invalid','',now(),'{}'::jsonb,
jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99700000-0000-4000-8000-000000000001'),now(),now());
insert into public.user_profiles(user_id,tenant_id,role) values('99700000-0000-4000-8000-000000000099','99700000-0000-4000-8000-000000000001','admin');
update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','99700000-0000-4000-8000-000000000001') where id='99700000-0000-4000-8000-000000000099';
select set_config('request.jwt.claims',jsonb_build_object('sub','99700000-0000-4000-8000-000000000099','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99700000-0000-4000-8000-000000000099',true);

insert into public.products(id,tenant_id,name,sku,price,cost,product_type,is_service,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level,is_set) values
('99700000-0000-4000-8000-000000000002','99700000-0000-4000-8000-000000000001','Inspection Set','Q-SET',5000,3000,'product',false,true,0,0,0,100,true),
('99700000-0000-4000-8000-000000000003','99700000-0000-4000-8000-000000000001','Inspection A','Q-A',2000,1000,'product',false,true,10,10,0,100,false),
('99700000-0000-4000-8000-000000000004','99700000-0000-4000-8000-000000000001','Inspection B','Q-B',3000,2000,'product',false,true,20,20,0,100,false);
insert into public.product_set_components(tenant_id,set_product_id,component_product_id,component_label,component_position,quantity_in_set) values
('99700000-0000-4000-8000-000000000001','99700000-0000-4000-8000-000000000002','99700000-0000-4000-8000-000000000003','A',1,1),
('99700000-0000-4000-8000-000000000001','99700000-0000-4000-8000-000000000002','99700000-0000-4000-8000-000000000004','B',2,2);
insert into public.sales_invoices(id,tenant_id,invoice_number,customer_name,status,subtotal,net_amount,iva_amount,total,balance,tax_treatment,items)
values('99700000-0000-4000-8000-000000000010','99700000-0000-4000-8000-000000000001','FV-Q-001','Inspection Customer','draft',10000,10000,0,10000,10000,'no_tax',
jsonb_build_array(jsonb_build_object('line_id','q-line','product_id','99700000-0000-4000-8000-000000000002','product_name','Inspection Set','product_sku','Q-SET','quantity',2,'unit_price',5000,'price',5000,'cost',3000,'purchase_treatment','inventory','is_service',false)));
update public.sales_invoices set status='confirmed' where id='99700000-0000-4000-8000-000000000010';
insert into public.sales_payments(
  tenant_id,
  invoice_id,
  payment_method_id,
  idempotency_key,
  amount,
  tax_treatment,
  net_amount,
  iva_amount,
  date
)
select
  '99700000-0000-4000-8000-000000000001',
  '99700000-0000-4000-8000-000000000010',
  id,
  'quarantine-return-payment',
  10000,
  'no_tax',
  10000,
  0,
  now()
from public.payment_methods
where tenant_id = '99700000-0000-4000-8000-000000000001'
order by created_at
limit 1;
insert into public.sales_return_control_settings(tenant_id,control_mode,activated_at,activated_by)
values('99700000-0000-4000-8000-000000000001','enforce',now(),'99700000-0000-4000-8000-000000000099');

create temp table quarantine_return on commit drop as select public.create_sales_return(
'99700000-0000-4000-8000-000000000010','[{"line_index":0,"returned_quantity":1,"disposition":"quarantine"}]',now(),'Requires inspection',null,'q-return') payload;
create temp view q_record as select quarantine.* from public.sales_return_quarantine quarantine join public.sales_return_lines line on line.id=quarantine.sales_return_line_id where line.sales_return_id=((select payload->>'sales_return_id' from quarantine_return)::uuid);
select is((select product_id from q_record),'99700000-0000-4000-8000-000000000002'::uuid,'quarantine identifies the commercial set, not an arbitrary component');
select is((select inventory_qty from public.products where id='99700000-0000-4000-8000-000000000003'),8,'held quarantine does not expose component A as available');
select ok(exists(select 1 from public.journal_lines where entry_id=(select inventory_journal_entry_id from public.sales_returns where id=((select payload->>'sales_return_id' from quarantine_return)::uuid)) and account_code='1106' and debit_amount=3000),'held quarantine recognizes custody value');

create temp table release_resolution on commit drop as select public.resolve_sales_return_quarantine((select id from q_record),'release',now(),'Inspection passed',null,'q-release') payload;
select ok((select contract_complete from public.professional_correction_trace_contract_view where operation_id=((select payload->>'operation_id' from release_resolution)::uuid)),'quarantine resolution has the full ordered trace contract');
select is((select status from q_record),'released','release records the inspection decision');
select is((select inventory_qty from public.products where id='99700000-0000-4000-8000-000000000003'),9,'release restores component A');
select is((select inventory_qty from public.products where id='99700000-0000-4000-8000-000000000004'),18,'release restores multiplied component B');
select is((select count(*)::integer from public.sales_return_quarantine_resolution_movements where resolution_id=((select payload->>'resolution_id' from release_resolution)::uuid)),2,'release maps both physical component movements');
select ok(exists(select 1 from public.journal_entries entry where entry.id=(select journal_entry_id from public.sales_return_quarantine_resolutions where id=((select payload->>'resolution_id' from release_resolution)::uuid)) and entry.total_debit=3000 and entry.total_credit=3000),'release value journal is balanced');
select is((select debit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.sales_return_quarantine_resolutions where id=((select payload->>'resolution_id' from release_resolution)::uuid)) and account_code='1105'),3000::numeric,'release transfers value into available inventory');
select is((select credit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.sales_return_quarantine_resolutions where id=((select payload->>'resolution_id' from release_resolution)::uuid)) and account_code='1106'),3000::numeric,'release clears quarantine value');
select ok((public.resolve_sales_return_quarantine((select id from q_record),'release',now(),'Retry',null,'q-release')->>'replayed')::boolean,'release command is idempotent');
select is((select count(*)::integer from public.sales_return_quarantine_resolutions),1,'release replay creates no second resolution');
select throws_ok(format('select public.void_sales_return(%L::uuid,%L,%L)',(select payload->>'sales_return_id' from quarantine_return),'Blocked','q-return-blocked'),'P0001','Void quarantine resolutions before voiding this sales return','resolved quarantine protects the parent return');

create temp table release_void on commit drop as select public.void_sales_return_quarantine_resolution((select (payload->>'resolution_id')::uuid from release_resolution),'Inspection correction','q-release-void') payload;
select ok((select contract_complete from public.professional_correction_trace_contract_view where operation_id=((select payload->>'operation_id' from release_void)::uuid)),'quarantine resolution void has the full ordered trace contract');
select is((select status from q_record),'held','voiding release returns the item to held quarantine');
select is((select inventory_qty from public.products where id='99700000-0000-4000-8000-000000000003'),8,'release void removes component A from available stock');
select is((select inventory_qty from public.products where id='99700000-0000-4000-8000-000000000004'),16,'release void removes component B from available stock');
select ok(exists(select 1 from public.journal_entries where id=(select void_journal_entry_id from public.sales_return_quarantine_resolutions where id=((select payload->>'resolution_id' from release_resolution)::uuid)) and reversal_of_id=(select journal_entry_id from public.sales_return_quarantine_resolutions where id=((select payload->>'resolution_id' from release_resolution)::uuid))),'release void appends an exact journal reversal');
select ok((public.void_sales_return_quarantine_resolution((select (payload->>'resolution_id')::uuid from release_resolution),'Inspection correction','q-release-void')->>'replayed')::boolean,'release void is idempotent');

create temp table scrap_resolution on commit drop as select public.resolve_sales_return_quarantine((select id from q_record),'scrap',now(),'Inspection failed',null,'q-scrap') payload;
select is((select status from q_record),'scrapped','scrap records the inspection decision');
select is((select count(*)::integer from public.sales_return_quarantine_resolution_movements where resolution_id=((select payload->>'resolution_id' from scrap_resolution)::uuid)),0,'scrap creates no available-stock movement');
select is((select debit_amount from public.journal_lines where entry_id=(select journal_entry_id from public.sales_return_quarantine_resolutions where id=((select payload->>'resolution_id' from scrap_resolution)::uuid)) and account_code='5205'),3000::numeric,'scrap transfers quarantine value to inventory loss');
select throws_ok(format('select public.void_sales_return(%L::uuid,%L,%L)',(select payload->>'sales_return_id' from quarantine_return),'Blocked','q-return-blocked-2'),'P0001','Void quarantine resolutions before voiding this sales return','scrapped quarantine also protects the parent return');
select public.void_sales_return_quarantine_resolution((select (payload->>'resolution_id')::uuid from scrap_resolution),'Reopen inspection','q-scrap-void');
select lives_ok(format('select public.void_sales_return(%L::uuid,%L,%L)',(select payload->>'sales_return_id' from quarantine_return),'Return cancelled','q-return-void'),'parent return can void after its resolution is voided');
select is((select status from q_record),'voided','parent return void preserves quarantine evidence as voided');

select * from finish();
rollback;
