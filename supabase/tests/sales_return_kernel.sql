begin;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
select plan(39);

insert into public.tenants(id,shop_name) values('99500000-0000-4000-8000-000000000001','Sales Return Test');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('99500000-0000-4000-8000-000000000099','authenticated','authenticated','sales-return@example.invalid','',now(),'{}'::jsonb,
jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99500000-0000-4000-8000-000000000001'),now(),now());
insert into public.user_profiles(user_id,tenant_id,role) values('99500000-0000-4000-8000-000000000099','99500000-0000-4000-8000-000000000001','admin');
update auth.users set raw_user_meta_data=raw_user_meta_data||jsonb_build_object('tenant_id','99500000-0000-4000-8000-000000000001') where id='99500000-0000-4000-8000-000000000099';
select set_config('request.jwt.claims',jsonb_build_object('sub','99500000-0000-4000-8000-000000000099','role','authenticated')::text,true);
select set_config('request.jwt.claim.sub','99500000-0000-4000-8000-000000000099',true);

insert into public.products(id,tenant_id,name,sku,price,cost,product_type,is_service,track_stock,inventory_qty,stock_quantity,min_stock_level,max_stock_level,is_set)
values
('99500000-0000-4000-8000-000000000002','99500000-0000-4000-8000-000000000001','Direct Sale Product','SALE-RETURN-DIRECT',2000,1000,'product',false,true,10,10,0,100,false),
('99500000-0000-4000-8000-000000000003','99500000-0000-4000-8000-000000000001','Return Set','SALE-RETURN-SET',5000,3000,'product',false,true,0,0,0,100,true),
('99500000-0000-4000-8000-000000000004','99500000-0000-4000-8000-000000000001','Return Component A','SALE-RETURN-A',2000,1000,'product',false,true,10,10,0,100,false),
('99500000-0000-4000-8000-000000000005','99500000-0000-4000-8000-000000000001','Return Component B','SALE-RETURN-B',3000,2000,'product',false,true,20,20,0,100,false),
('99500000-0000-4000-8000-000000000006','99500000-0000-4000-8000-000000000001','Scrap Sale Product','SALE-RETURN-SCRAP',1500,700,'product',false,true,5,5,0,100,false);
insert into public.product_set_components(tenant_id,set_product_id,component_product_id,component_label,component_position,quantity_in_set)
values
('99500000-0000-4000-8000-000000000001','99500000-0000-4000-8000-000000000003','99500000-0000-4000-8000-000000000004','A',1,1),
('99500000-0000-4000-8000-000000000001','99500000-0000-4000-8000-000000000003','99500000-0000-4000-8000-000000000005','B',2,2);

insert into public.sales_invoices(id,tenant_id,invoice_number,customer_name,status,subtotal,net_amount,iva_amount,total,balance,tax_treatment,items)
values('99500000-0000-4000-8000-000000000010','99500000-0000-4000-8000-000000000001','FV-RETURN-001','Return Customer','draft',20500,20500,0,20500,20500,'no_tax',
jsonb_build_array(
jsonb_build_object('line_id','sale-line-direct','product_id','99500000-0000-4000-8000-000000000002','product_name','Direct Sale Product','product_sku','SALE-RETURN-DIRECT','quantity',4,'unit_price',2000,'price',2000,'cost',1000,'purchase_treatment','inventory','is_service',false),
jsonb_build_object('line_id','sale-line-set','product_id','99500000-0000-4000-8000-000000000003','product_name','Return Set','product_sku','SALE-RETURN-SET','quantity',2,'unit_price',5000,'price',5000,'cost',3000,'purchase_treatment','inventory','is_service',false),
jsonb_build_object('line_id','sale-line-scrap','product_id','99500000-0000-4000-8000-000000000006','product_name','Scrap Sale Product','product_sku','SALE-RETURN-SCRAP','quantity',1,'unit_price',1500,'price',1500,'cost',700,'purchase_treatment','inventory','is_service',false)
));
update public.sales_invoices set status='confirmed' where id='99500000-0000-4000-8000-000000000010';
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000002'),6,'posted sale consumes direct quantity');
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000004'),8,'posted set sale consumes first component');
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000005'),16,'posted set sale consumes multiplied component');

select throws_ok($$select public.create_sales_return('99500000-0000-4000-8000-000000000010','[{"line_index":0,"returned_quantity":1,"disposition":"restock"}]'::jsonb,now(),'Disabled',null,'return-disabled')$$,
'P0001','Sales return workflow is not active for this tenant','sales return is disabled by default');
select is((select count(*)::integer from public.sales_returns),0,'disabled attempt leaves no return');
insert into public.sales_return_control_settings(tenant_id,control_mode,activated_at,activated_by)
values('99500000-0000-4000-8000-000000000001','enforce',now(),'99500000-0000-4000-8000-000000000099');

create temp table direct_return on commit drop as select public.create_sales_return(
'99500000-0000-4000-8000-000000000010','[{"line_index":0,"returned_quantity":2,"disposition":"restock"}]'::jsonb,
now(),'Cliente devolvió producto',null,'return-direct-1') payload;
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000002'),8,'restock return increases available stock');
select is((select returned_quantity from public.sales_return_lines where sales_return_id=((select payload->>'sales_return_id' from direct_return)::uuid)),2,'return stores commercial quantity');
select is((select previously_returned_quantity from public.sales_return_lines where sales_return_id=((select payload->>'sales_return_id' from direct_return)::uuid)),0,'first return stores zero prior quantity');
select ok(exists(select 1 from public.sales_return_line_movements mapping join public.stock_movements returned on returned.id=mapping.return_stock_movement_id where mapping.sales_return_id=((select payload->>'sales_return_id' from direct_return)::uuid) and returned.quantity=2 and returned.stock_before=6 and returned.stock_after=8 and returned.reversal_of_id=mapping.original_sale_movement_id),'restock movement stores exact balances and original sale link');
select ok(exists(
  select 1
  from public.journal_entries entry
  where entry.operation_id=((select payload->>'operation_id' from direct_return)::uuid)
    and entry.total_debit=2000 and entry.total_credit=2000
    and exists(select 1 from public.journal_lines line where line.entry_id=entry.id and line.account_code='1105' and line.debit_amount=2000)
    and exists(select 1 from public.journal_lines line where line.entry_id=entry.id and line.account_code='5100' and line.credit_amount=2000)
),'restocked sales return restores inventory value and reverses COGS exactly once');
select is((select status from public.sales_invoices where id='99500000-0000-4000-8000-000000000010'),'confirmed','physical return leaves invoice status unchanged');
select is((select balance from public.sales_invoices where id='99500000-0000-4000-8000-000000000010'),20500::numeric,'physical return leaves receivable unchanged');
select ok(exists(select 1 from public.inventory_accounting_checkpoints where operation_id=((select payload->>'operation_id' from direct_return)::uuid) and phase='accounting_planned' and outcome='completed' and (payload->>'financial_credit_separate')::boolean),'return trace records separate pending financial credit and completed physical-value accounting');
select ok((select contract_complete from public.professional_correction_trace_contract_view where operation_id=((select payload->>'operation_id' from direct_return)::uuid)),'sales return create has the full ordered trace contract');
select ok((public.create_sales_return('99500000-0000-4000-8000-000000000010','[{"line_index":0,"returned_quantity":2}]'::jsonb,now(),'Retry',null,'return-direct-1')->>'replayed')::boolean,'return retry is idempotent');
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000002'),8,'return replay does not restock twice');

select public.create_sales_return('99500000-0000-4000-8000-000000000010','[{"line_index":0,"returned_quantity":2,"disposition":"restock"}]'::jsonb,now(),'Return remainder',null,'return-direct-2');
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000002'),10,'second partial return restores sold direct balance');
select throws_ok($$select public.create_sales_return('99500000-0000-4000-8000-000000000010','[{"line_index":0,"returned_quantity":1,"disposition":"restock"}]'::jsonb,now(),'Over',null,'return-direct-over')$$,
'P0001','Sales return exceeds remaining sold quantity','over-return is blocked');
select is((select count(*)::integer from public.sales_returns),2,'failed over-return leaves no header');

create temp table set_restock on commit drop as select public.create_sales_return(
'99500000-0000-4000-8000-000000000010','[{"line_index":1,"returned_quantity":1,"disposition":"restock"}]'::jsonb,now(),'Set accepted',null,'return-set-restock') payload;
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000004'),9,'set restock restores first component');
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000005'),18,'set restock restores multiplied component');
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000003'),0,'set header never receives stock');
select is((select count(*)::integer from public.sales_return_line_movements where sales_return_id=((select payload->>'sales_return_id' from set_restock)::uuid)),2,'set return maps both component sale movements');

create temp table set_quarantine on commit drop as select public.create_sales_return(
'99500000-0000-4000-8000-000000000010','[{"line_index":1,"returned_quantity":1,"disposition":"quarantine"}]'::jsonb,now(),'Set requires inspection',null,'return-set-quarantine') payload;
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000004'),9,'quarantine does not increase available component stock');
select is((select quantity from public.sales_return_quarantine where sales_return_line_id=(select id from public.sales_return_lines where sales_return_id=((select payload->>'sales_return_id' from set_quarantine)::uuid))),1,'quarantine records held commercial quantity');
select is((select count(*)::integer from public.sales_return_line_movements where sales_return_id=((select payload->>'sales_return_id' from set_quarantine)::uuid)),2,'quarantine still traces both original component movements');
select ok(exists(select 1 from public.journal_lines where entry_id=(select inventory_journal_entry_id from public.sales_returns where id=((select payload->>'sales_return_id' from set_quarantine)::uuid)) and account_code='1106' and debit_amount=3000),'quarantine return recognizes returned-goods custody value');

create temp table scrap_return on commit drop as select public.create_sales_return(
'99500000-0000-4000-8000-000000000010','[{"line_index":2,"returned_quantity":1,"disposition":"scrap"}]'::jsonb,now(),'Irreparable',null,'return-scrap') payload;
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000006'),4,'scrap disposition does not restore available stock');
select ok(exists(select 1 from public.sales_return_line_movements where sales_return_id=((select payload->>'sales_return_id' from scrap_return)::uuid) and return_stock_movement_id is null),'scrap remains linked to original sale without fake stock movement');
select ok(exists(select 1 from public.journal_lines where entry_id=(select inventory_journal_entry_id from public.sales_returns where id=((select payload->>'sales_return_id' from scrap_return)::uuid)) and account_code='5205' and debit_amount=700),'irreparable return classifies expected value as inventory loss');

create temp table set_void on commit drop as select public.void_sales_return((select (payload->>'sales_return_id')::uuid from set_restock),'Return entered by mistake','void-set-restock') payload;
select ok((select contract_complete from public.professional_correction_trace_contract_view where operation_id=((select payload->>'operation_id' from set_void)::uuid)),'sales return void has the full ordered trace contract');
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000004'),8,'void removes restocked first component');
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000005'),16,'void removes restocked multiplied component');
select ok(exists(select 1 from public.stock_movements where operation_id=((select payload->>'operation_id' from set_void)::uuid) and movement_type='sales_return_reversal' and reversal_of_id is not null),'void appends linked stock reversals');
select ok((public.void_sales_return((select (payload->>'sales_return_id')::uuid from set_restock),'Return entered by mistake','void-set-restock')->>'replayed')::boolean,'sales return void is idempotent');

select public.void_sales_return((select (payload->>'sales_return_id')::uuid from set_quarantine),'Inspection record mistake','void-set-quarantine');
select is((select status from public.sales_return_quarantine where sales_return_line_id=(select id from public.sales_return_lines where sales_return_id=((select payload->>'sales_return_id' from set_quarantine)::uuid))),'voided','quarantine void preserves held record as voided');
select is((select inventory_qty from public.products where id='99500000-0000-4000-8000-000000000004'),8,'quarantine void has no stock effect');

select set_config('app.skip_stock_adjustment_trigger','true',true);
update public.products set inventory_qty=0,stock_quantity=0 where id='99500000-0000-4000-8000-000000000002';
select set_config('app.skip_stock_adjustment_trigger','',true);
select throws_ok(format('select public.void_sales_return(%L::uuid,%L,%L)',(select payload->>'sales_return_id' from direct_return),'Insufficient','void-direct-insufficient'),
'P0001','Insufficient stock to void sales return','insufficient stock blocks return void atomically');
select is((select status from public.sales_returns where id=((select payload->>'sales_return_id' from direct_return)::uuid)),'posted','failed void leaves return posted');
select * from finish();
rollback;
