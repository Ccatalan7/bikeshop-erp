begin;
select plan(14);

insert into public.tenants(id,shop_name)values('9d000000-0000-4000-8000-000000000001','Posted Evidence Test');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values(
 '9d000000-0000-4000-8000-000000000099','authenticated','authenticated','posted-evidence@example.invalid','',now(),'{}',
 jsonb_build_object('account_type','public_store_customer','customer_tenant_id','9d000000-0000-4000-8000-000000000001','tenant_id','9d000000-0000-4000-8000-000000000001'),now(),now()
);
insert into public.user_profiles(user_id,tenant_id,role)
values('9d000000-0000-4000-8000-000000000099','9d000000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claim.sub','9d000000-0000-4000-8000-000000000099',true);
select set_config('request.jwt.claims',jsonb_build_object('sub','9d000000-0000-4000-8000-000000000099','role','authenticated')::text,true);

select ok(to_regclass('public.journal_supersession_evidence')is not null,'immutable journal evidence table exists');

insert into public.sales_invoices(id,tenant_id,invoice_number,customer_name,status,subtotal,net_amount,iva_amount,total,items)
values('9d000000-0000-4000-8000-000000000002','9d000000-0000-4000-8000-000000000001','FV-EVIDENCE-001','Evidence Customer','confirmed',1000,1000,0,1000,'[]');
select is((select count(*)::integer from public.journal_entries where tenant_id='9d000000-0000-4000-8000-000000000001'and source_module='sales_invoices'and source_reference='FV-EVIDENCE-001'),1,'posted sales invoice owns one current journal');

update public.sales_invoices set status='cancelled'where id='9d000000-0000-4000-8000-000000000002';
select is((select count(*)::integer from public.journal_supersession_evidence where tenant_id='9d000000-0000-4000-8000-000000000001'and source_reference='FV-EVIDENCE-001'),1,'sales journal replacement preserves one immutable snapshot');
select ok((select jsonb_array_length(lines_snapshot)>=2 from public.journal_supersession_evidence where source_reference='FV-EVIDENCE-001'),'journal evidence preserves every debit and credit line');
select ok((select header_snapshot->>'source_module'='sales_invoices'from public.journal_supersession_evidence where source_reference='FV-EVIDENCE-001'),'journal evidence preserves source header identity');
select ok((select operation_id is not null from public.journal_supersession_evidence where source_reference='FV-EVIDENCE-001'),'journal evidence links to the source action operation');
select ok(exists(select 1 from public.inventory_accounting_checkpoints checkpoint join public.journal_supersession_evidence evidence on evidence.operation_id=checkpoint.operation_id where evidence.source_reference='FV-EVIDENCE-001'and checkpoint.phase='journal_reversed'and checkpoint.payload->>'evidence'='immutable_full_snapshot'),'operation checkpoint exposes the complete journal evidence');

select throws_ok($$delete from public.sales_invoices where id='9d000000-0000-4000-8000-000000000002'$$,'23514','Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow','non-draft sales invoice deletion is blocked');
insert into public.sales_invoices(id,tenant_id,invoice_number,customer_name,status,subtotal,net_amount,iva_amount,total,items)
values('9d000000-0000-4000-8000-000000000003','9d000000-0000-4000-8000-000000000001','FV-DRAFT-DELETE','Draft Customer','draft',0,0,0,0,'[]');
delete from public.sales_invoices where id='9d000000-0000-4000-8000-000000000003';
select is((select count(*)::integer from public.sales_invoices where id='9d000000-0000-4000-8000-000000000003'),0,'draft sales invoice remains deletable');

insert into public.purchase_invoices(id,tenant_id,invoice_number,supplier_name,status,subtotal,tax,total,paid_amount,balance,items)
values('9d000000-0000-4000-8000-000000000004','9d000000-0000-4000-8000-000000000001','FC-EVIDENCE-001','Evidence Supplier','confirmed',1000,0,1000,0,1000,'[]');
select throws_ok($$delete from public.purchase_invoices where id='9d000000-0000-4000-8000-000000000004'$$,'23514','Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow','posted purchase invoice deletion is blocked');
select is((select count(*)::integer from public.purchase_invoices where id='9d000000-0000-4000-8000-000000000004'),1,'blocked purchase delete leaves the invoice intact');
select is((select count(*)::integer from public.journal_entries where source_module='purchase_invoices'and source_reference='FC-EVIDENCE-001'),1,'blocked purchase delete leaves its journal intact');

insert into public.purchase_invoices(id,tenant_id,invoice_number,supplier_name,status,subtotal,tax,total,paid_amount,balance,items)
values('9d000000-0000-4000-8000-000000000005','9d000000-0000-4000-8000-000000000001','FC-DRAFT-DELETE','Draft Supplier','draft',0,0,0,0,0,'[]');
delete from public.purchase_invoices where id='9d000000-0000-4000-8000-000000000005';
select is((select count(*)::integer from public.purchase_invoices where id='9d000000-0000-4000-8000-000000000005'),0,'draft purchase invoice remains deletable');
select is((select count(*)::integer from(select entry.id from public.journal_entries entry join public.journal_lines line on line.entry_id=entry.id where entry.tenant_id='9d000000-0000-4000-8000-000000000001'group by entry.id having sum(line.debit_amount-line.credit_amount)<>0)unbalanced),0,'remaining current journals stay balanced');

select * from finish();
rollback;
