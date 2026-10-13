-- A sales credit note could not be issued when the invoice line's product had
-- been deleted from the catalogue: the credit line copied the product id and
-- its foreign key to products failed (2026-10-13, annulling the store's test
-- sales INV-25-00001 and INV-25-00002, whose «test» product no longer exists).
--
-- A credit note is financial only — it never moves stock — so the line keeps
-- the product name, SKU and snapshot from the invoice and links to the
-- catalogue only while that product exists. A physical sales return still
-- requires the product, because it restocks it.
--
-- Same body as production (20260712070000), changing only the line insert.

CREATE OR REPLACE FUNCTION public.create_sales_credit_note(p_sales_invoice_id uuid, p_lines jsonb, p_issue_date timestamp with time zone, p_reason_code text, p_reason text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_mode text:='disabled';v_invoice public.sales_invoices%rowtype;v_existing public.sales_credit_notes%rowtype;
 v_note uuid:=gen_random_uuid();v_operation uuid:=gen_random_uuid();v_journal uuid:=gen_random_uuid();v_number text;v_req jsonb;v_idx integer;v_bal record;v_qty integer;v_net numeric;v_tax numeric;v_cost numeric;v_prevq integer;v_prevnet numeric;v_prevtax numeric;v_disposition text;v_return_line uuid;v_return record;v_used integer;
 v_totalnet numeric:=0;v_totaltax numeric:=0;v_totalcost numeric:=0;v_ar uuid;v_revenue uuid;v_taxacct uuid;v_inventory uuid;v_cogs uuid;v_description text;
begin
 if v_actor is null or v_tenant is null then raise exception'Authenticated employee tenant is required';end if;if p_issue_date is null or nullif(btrim(p_reason_code),'')is null or nullif(btrim(p_reason),'')is null or nullif(btrim(p_idempotency_key),'')is null then raise exception'Sales credit note date, reason, and idempotency key are required';end if;
 if jsonb_typeof(p_lines)<>'array'or jsonb_array_length(p_lines)=0 then raise exception'Sales credit note requires at least one line';end if;
 select * into v_existing from public.sales_credit_notes where tenant_id=v_tenant and idempotency_key=btrim(p_idempotency_key);if found then if v_existing.sales_invoice_id<>p_sales_invoice_id then raise exception'Idempotency key belongs to another sales invoice';end if;return jsonb_build_object('sales_credit_note_id',v_existing.id,'operation_id',v_existing.operation_id,'credit_note_number',v_existing.credit_note_number,'replayed',true);end if;
 select coalesce(control_mode,'disabled')into v_mode from public.sales_credit_note_control_settings where tenant_id=v_tenant;if not found then v_mode:='disabled';end if;if v_mode<>'enforce'then raise exception'Sales credit note workflow is not active for this tenant';end if;
 select * into v_invoice from public.sales_invoices where id=p_sales_invoice_id and tenant_id=v_tenant for update;if not found then raise exception'Sales invoice not found';end if;if lower(v_invoice.status)in('draft','borrador','cancelled','cancelado','cancelada','anulado','anulada')then raise exception'Sales invoice must be posted before crediting';end if;
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,old_status,new_status,context)values(v_operation,v_tenant,format('sales_credit_note:%s:%s',p_sales_invoice_id,btrim(p_idempotency_key)),'sales_credit_note','create','sales_credit_note',v_note,v_actor,'database_command',v_invoice.status,v_invoice.status,jsonb_build_object('stock_effect','none','official_dte_status','internal'));
 v_number:=public.get_next_document_number(v_tenant,'sales_credit_note','NCV');
 create temporary table if not exists pg_temp.sales_credit_work(source_line_key text,source_line_index integer,product_id uuid,product_name text,product_sku text,disposition text,sales_return_line_id uuid,credited_quantity integer,original_quantity integer,original_allocated_net numeric,original_allocated_tax numeric,net_amount numeric,tax_amount numeric,cost_amount numeric,line_snapshot jsonb)on commit drop;truncate pg_temp.sales_credit_work;
 for v_req in select value from jsonb_array_elements(p_lines)loop
  v_idx:=nullif(v_req->>'line_index','')::integer;select * into v_bal from public.sales_credit_note_line_balance_view where tenant_id=v_tenant and sales_invoice_id=v_invoice.id and source_line_index=v_idx;if not found then raise exception'Invalid sales credit line';end if;
  if exists(select 1 from pg_temp.sales_credit_work where source_line_key=v_bal.source_line_key)then raise exception'Duplicate sales credit line';end if;
  v_qty:=coalesce(nullif(v_req->>'credited_quantity','')::integer,0);if v_qty<0 or v_qty>v_bal.remaining_quantity then raise exception'Sales credit quantity exceeds original line balance';end if;
  v_net:=coalesce(nullif(v_req->>'net_amount','')::numeric,case when v_bal.original_quantity>0 then public.clp_round(v_bal.original_allocated_net*v_qty/v_bal.original_quantity)else 0 end);
  v_tax:=coalesce(nullif(v_req->>'tax_amount','')::numeric,case when v_bal.original_allocated_net>0 then public.clp_round(v_bal.original_allocated_tax*v_net/v_bal.original_allocated_net)else 0 end);
  if v_net<>public.clp_round(v_net)or v_tax<>public.clp_round(v_tax)or v_net<0 or v_tax<0 or v_net+v_tax<=0 or v_net>v_bal.remaining_net or v_tax>v_bal.remaining_tax then raise exception'Sales credit amount exceeds original line balance or is not whole CLP';end if;
  v_disposition:=coalesce(nullif(v_req->>'disposition',''),'financial_only');v_return_line:=nullif(v_req->>'sales_return_line_id','')::uuid;v_cost:=0;
  if v_disposition='sales_return'then
   select line.*,header.status return_status into v_return from public.sales_return_lines line join public.sales_returns header on header.id=line.sales_return_id where line.id=v_return_line and line.tenant_id=v_tenant and header.sales_invoice_id=v_invoice.id and line.source_line_key=v_bal.source_line_key;
   if not found or v_return.return_status<>'posted'then raise exception'Posted sales return line not found for credited invoice line';end if;
   select coalesce(sum(line.credited_quantity),0)into v_used from public.sales_credit_note_lines line join public.sales_credit_notes note on note.id=line.sales_credit_note_id where line.sales_return_line_id=v_return_line and note.status='posted';if v_used+v_qty>v_return.returned_quantity then raise exception'Credit quantity exceeds linked sales return';end if;
   -- Physical restock owns the Inventory/COGS reversal. The financial credit
   -- must not post that value a second time.
   v_cost:=0;
  elsif v_disposition<>'financial_only'or v_return_line is not null then raise exception'Invalid sales credit disposition';end if;
  insert into pg_temp.sales_credit_work values(v_bal.source_line_key,v_idx,v_bal.product_id,v_bal.product_name,v_bal.product_sku,v_disposition,v_return_line,v_qty,v_bal.original_quantity,v_bal.original_allocated_net,v_bal.original_allocated_tax,v_net,v_tax,v_cost,v_bal.line_snapshot);
  v_totalnet:=v_totalnet+v_net;v_totaltax:=v_totaltax+v_tax;v_totalcost:=v_totalcost+v_cost;
 end loop;
 if v_totalnet+v_totaltax>public.clp_round(v_invoice.total-coalesce(v_invoice.credited_amount,0))then raise exception'Sales credit exceeds remaining invoice amount';end if;
 v_ar:=public.ensure_account(v_tenant,'1130','Cuentas por Cobrar Comerciales','asset','currentAsset','Cuentas por cobrar a clientes',null);v_revenue:=public.ensure_account(v_tenant,'4100','Ingresos Operacionales','income','operatingIncome','Ingresos operacionales',null);v_taxacct:=public.ensure_account(v_tenant,'2150','IVA Débito Fiscal','liability','currentLiability','IVA generado en ventas',null);v_inventory:=public.ensure_account(v_tenant,'1105','Inventarios','asset','currentAsset','Inventario disponible',null);v_cogs:=public.ensure_account(v_tenant,'5100','Costo de Ventas','expense','costOfGoodsSold','Costo de ventas',null);v_description:=format('Nota crédito venta %s - factura %s',v_number,v_invoice.invoice_number);
 insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by,created_at,updated_at)values(v_journal,v_tenant,public.get_next_document_number(v_tenant,'journal_entry'),p_issue_date,v_description,'credit_note','sales_credit_notes',v_note::text,'posted',v_totalnet+v_totaltax+v_totalcost,v_totalnet+v_totaltax+v_totalcost,v_operation,'sales_credit_note',v_note,v_actor,now(),now());
 if v_totalnet>0 then insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)values(gen_random_uuid(),v_tenant,v_journal,v_revenue,'4100','Ingresos Operacionales',v_description,v_totalnet,0,now(),now());end if;
 if v_totaltax>0 then insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)values(gen_random_uuid(),v_tenant,v_journal,v_taxacct,'2150','IVA Débito Fiscal',v_description,v_totaltax,0,now(),now());end if;
 insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)values(gen_random_uuid(),v_tenant,v_journal,v_ar,'1130','Cuentas por Cobrar Comerciales',v_description,0,v_totalnet+v_totaltax,now(),now());
 if v_totalcost>0 then insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)values(gen_random_uuid(),v_tenant,v_journal,v_inventory,'1105','Inventarios',v_description,v_totalcost,0,now(),now()),(gen_random_uuid(),v_tenant,v_journal,v_cogs,'5100','Costo de Ventas',v_description,0,v_totalcost,now(),now());end if;
 insert into public.sales_credit_notes(id,tenant_id,sales_invoice_id,credit_note_number,issue_date,reason_code,reason,net_amount,tax_amount,cost_amount,total_amount,idempotency_key,operation_id,journal_entry_id,created_by)values(v_note,v_tenant,v_invoice.id,v_number,p_issue_date,btrim(p_reason_code),btrim(p_reason),v_totalnet,v_totaltax,v_totalcost,v_totalnet+v_totaltax,btrim(p_idempotency_key),v_operation,v_journal,v_actor);
 insert into public.sales_credit_note_lines(tenant_id,sales_credit_note_id,sales_invoice_id,source_line_key,source_line_index,product_id,product_name,product_sku,disposition,sales_return_line_id,credited_quantity,original_quantity,original_allocated_net,original_allocated_tax,net_amount,tax_amount,cost_amount,total_amount,line_snapshot)
 -- A financial credit has no physical effect: a line whose product was later
 -- deleted from the catalogue keeps its name, SKU and snapshot and is credited
 -- without the catalogue link (2026-10-13, INV-25-00001/00002).
 select v_tenant,v_note,v_invoice.id,work.source_line_key,work.source_line_index,(select product.id from public.products product where product.id=work.product_id and product.tenant_id=v_tenant),work.product_name,work.product_sku,work.disposition,work.sales_return_line_id,work.credited_quantity,work.original_quantity,work.original_allocated_net,work.original_allocated_tax,work.net_amount,work.tax_amount,work.cost_amount,work.net_amount+work.tax_amount,work.line_snapshot from pg_temp.sales_credit_work work;
 perform public.recalculate_sales_invoice_settlement(v_invoice.id);perform public.append_inventory_accounting_checkpoint(v_operation,'inventory_applied','completed','sales_credit_note',v_note,jsonb_build_object('movement_count',0));perform public.append_inventory_accounting_checkpoint(v_operation,'journal_posted','completed','journal_entry',v_journal,jsonb_build_object('balanced',true));perform public.append_inventory_accounting_checkpoint(v_operation,'invariants_verified','completed','sales_credit_note',v_note,jsonb_build_object('official_dte_status','internal'));
 update public.inventory_accounting_operations set outcome='completed',completed_at=clock_timestamp(),after_snapshot=jsonb_build_object('sales_credit_note_id',v_note,'total',v_totalnet+v_totaltax)where id=v_operation;perform public.append_inventory_accounting_checkpoint(v_operation,'completed','completed','sales_credit_note',v_note,jsonb_build_object('credit_note_number',v_number));
 return jsonb_build_object('sales_credit_note_id',v_note,'operation_id',v_operation,'credit_note_number',v_number,'replayed',false);
end;$function$;

revoke all on function public.create_sales_credit_note(uuid,jsonb,timestamptz,text,text,text) from public, anon;
grant execute on function public.create_sales_credit_note(uuid,jsonb,timestamptz,text,text,text) to authenticated;
