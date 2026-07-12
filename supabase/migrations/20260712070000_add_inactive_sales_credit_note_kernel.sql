-- Deployment status: DEPLOYED 2026-07-11. No tenant was activated.
begin;
alter table public.sales_invoices add column if not exists credited_amount numeric(12,2) not null default 0,
 add column if not exists customer_credit_balance numeric(12,2) not null default 0;
create table if not exists public.sales_credit_note_control_settings(
 tenant_id uuid primary key references public.tenants(id) on delete cascade,control_mode text not null default'disabled' check(control_mode in('disabled','shadow','enforce')),
 activated_at timestamptz,activated_by uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.sales_credit_notes(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
 credit_note_number text not null,status text not null default'posted' check(status in('posted','voided')),official_dte_status text not null default'internal' check(official_dte_status in('internal','pending','issued','rejected','cancelled')),
 issue_date timestamptz not null,reason_code text not null,reason text not null,net_amount numeric(12,2) not null check(net_amount>=0),tax_amount numeric(12,2) not null check(tax_amount>=0),
 cost_amount numeric(12,2) not null default 0 check(cost_amount>=0),total_amount numeric(12,2) not null check(total_amount>0),idempotency_key text not null,operation_id uuid not null,
 journal_entry_id uuid not null references public.journal_entries(id) on delete restrict,created_by uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 void_operation_id uuid,void_journal_entry_id uuid references public.journal_entries(id),void_idempotency_key text,voided_at timestamptz,voided_by uuid references auth.users(id),void_reason text,
 unique(tenant_id,credit_note_number),unique(tenant_id,idempotency_key),unique(tenant_id,id),foreign key(tenant_id,operation_id) references public.inventory_accounting_operations(tenant_id,id) on delete restrict,
 check(total_amount=net_amount+tax_amount));
create unique index if not exists uq_sales_credit_void_key on public.sales_credit_notes(tenant_id,void_idempotency_key) where void_idempotency_key is not null;
create table if not exists public.sales_credit_note_lines(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,sales_credit_note_id uuid not null,sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
 source_line_key text not null,source_line_index integer not null,product_id uuid references public.products(id),product_name text not null,product_sku text,
 disposition text not null check(disposition in('financial_only','sales_return')),sales_return_line_id uuid references public.sales_return_lines(id) on delete restrict,
 credited_quantity integer not null default 0 check(credited_quantity>=0),original_quantity integer not null,original_allocated_net numeric(12,2) not null,original_allocated_tax numeric(12,2) not null,
 net_amount numeric(12,2) not null,tax_amount numeric(12,2) not null,cost_amount numeric(12,2) not null default 0,total_amount numeric(12,2) not null,line_snapshot jsonb not null,created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,sales_credit_note_id,source_line_key),foreign key(tenant_id,sales_credit_note_id) references public.sales_credit_notes(tenant_id,id) on delete restrict,
 check(total_amount=net_amount+tax_amount),check((disposition='sales_return' and sales_return_line_id is not null and credited_quantity>0)or(disposition='financial_only' and sales_return_line_id is null)));
create index if not exists idx_sales_credit_invoice on public.sales_credit_notes(tenant_id,sales_invoice_id,created_at desc);
alter table public.sales_credit_note_control_settings enable row level security;alter table public.sales_credit_notes enable row level security;alter table public.sales_credit_note_lines enable row level security;
drop policy if exists sales_credit_settings_select on public.sales_credit_note_control_settings;create policy sales_credit_settings_select on public.sales_credit_note_control_settings for select to authenticated using(tenant_id=public.user_tenant_id());
drop policy if exists sales_credit_notes_select on public.sales_credit_notes;create policy sales_credit_notes_select on public.sales_credit_notes for select to authenticated using(tenant_id=public.user_tenant_id());
drop policy if exists sales_credit_lines_select on public.sales_credit_note_lines;create policy sales_credit_lines_select on public.sales_credit_note_lines for select to authenticated using(tenant_id=public.user_tenant_id());
revoke insert,update,delete on public.sales_credit_note_control_settings,public.sales_credit_notes,public.sales_credit_note_lines from public,anon,authenticated;
grant select on public.sales_credit_note_control_settings,public.sales_credit_notes,public.sales_credit_note_lines to authenticated;

create or replace view public.sales_credit_note_line_balance_view with(security_invoker=true) as
with raw as(
 select invoice.id sales_invoice_id,invoice.tenant_id,invoice.net_amount invoice_net,invoice.iva_amount invoice_tax,source.ordinality::integer-1 source_line_index,source.item line_snapshot,
 coalesce(nullif(source.item->>'line_id',''),nullif(source.item->>'id',''),md5(invoice.id::text||':'||(source.ordinality::integer-1)::text||':'||coalesce(source.item->>'product_id','')))source_line_key,
 coalesce(nullif(source.item->>'quantity','')::numeric,0)::integer original_quantity,
 greatest(coalesce(nullif(source.item->>'quantity','')::numeric,0)*coalesce(nullif(source.item->>'unit_price','')::numeric,nullif(source.item->>'price','')::numeric,0)-coalesce(nullif(source.item->>'discount','')::numeric,0),0)raw_net,
 case when coalesce((source.item->>'is_service')::boolean,false) then 0 else coalesce(nullif(source.item->>'quantity','')::numeric,0)*coalesce(nullif(source.item->>'cost','')::numeric,0) end original_cost
 from public.sales_invoices invoice cross join lateral jsonb_array_elements(invoice.items)with ordinality source(item,ordinality)
),base as(select raw.*,case when sum(raw_net)over(partition by sales_invoice_id)>0 then public.clp_round(raw_net/sum(raw_net)over(partition by sales_invoice_id)*invoice_net)else 0 end net_base from raw),
net_alloc as(select base.*,net_base+case when row_number()over(partition by sales_invoice_id order by raw_net desc,source_line_index)=1 then public.clp_round(invoice_net-sum(net_base)over(partition by sales_invoice_id))else 0 end original_allocated_net from base),
tax_base as(select net_alloc.*,case when invoice_net>0 then public.clp_round(original_allocated_net/invoice_net*invoice_tax)else 0 end tax_pre from net_alloc),
alloc as(select tax_base.*,tax_pre+case when row_number()over(partition by sales_invoice_id order by original_allocated_net desc,source_line_index)=1 then public.clp_round(invoice_tax-sum(tax_pre)over(partition by sales_invoice_id))else 0 end original_allocated_tax from tax_base),
credits as(select line.tenant_id,line.sales_invoice_id,line.source_line_key,sum(line.credited_quantity)credited_quantity,sum(line.net_amount)credited_net,sum(line.tax_amount)credited_tax,sum(line.cost_amount)credited_cost from public.sales_credit_note_lines line join public.sales_credit_notes note on note.id=line.sales_credit_note_id where note.status='posted' group by 1,2,3)
select alloc.tenant_id,alloc.sales_invoice_id,alloc.source_line_index,alloc.source_line_key,nullif(alloc.line_snapshot->>'product_id','')::uuid product_id,coalesce(alloc.line_snapshot->>'product_name','Producto')product_name,alloc.line_snapshot->>'product_sku'product_sku,
 alloc.original_quantity,alloc.original_allocated_net,alloc.original_allocated_tax,public.clp_round(alloc.original_cost)original_cost,coalesce(credits.credited_quantity,0)::integer credited_quantity,coalesce(credits.credited_net,0)credited_net,coalesce(credits.credited_tax,0)credited_tax,coalesce(credits.credited_cost,0)credited_cost,
 greatest(alloc.original_quantity-coalesce(credits.credited_quantity,0),0)remaining_quantity,greatest(alloc.original_allocated_net-coalesce(credits.credited_net,0),0)remaining_net,greatest(alloc.original_allocated_tax-coalesce(credits.credited_tax,0),0)remaining_tax,greatest(public.clp_round(alloc.original_cost)-coalesce(credits.credited_cost,0),0)remaining_cost,alloc.line_snapshot
from alloc left join credits on credits.tenant_id=alloc.tenant_id and credits.sales_invoice_id=alloc.sales_invoice_id and credits.source_line_key=alloc.source_line_key;
grant select on public.sales_credit_note_line_balance_view to authenticated;

create or replace function public.recalculate_sales_invoice_settlement(p_invoice_id uuid)returns void language plpgsql set search_path=public as $$
declare v_invoice public.sales_invoices%rowtype;v_paid numeric;v_credit numeric;v_effective numeric;v_balance numeric;v_customer_credit numeric;v_status text;
begin select * into v_invoice from public.sales_invoices where id=p_invoice_id for update;if not found then return;end if;
 select public.clp_round(coalesce(sum(amount),0))into v_paid from public.sales_payments where invoice_id=p_invoice_id and deleted_at is null;
 select public.clp_round(coalesce(sum(total_amount),0))into v_credit from public.sales_credit_notes where sales_invoice_id=p_invoice_id and status='posted';
 v_effective:=greatest(public.clp_round(v_invoice.total)-v_credit,0);v_balance:=greatest(v_effective-v_paid,0);v_customer_credit:=greatest(v_paid-v_effective,0);
 if lower(v_invoice.status)in('cancelled','cancelado','cancelada','anulado','anulada')then v_status:=v_invoice.status;
 elsif lower(v_invoice.status)in('draft','borrador')then v_status:=v_invoice.status;
 elsif v_balance=0 and v_paid>0 then v_status:='paid';elsif v_paid>0 then v_status:='confirmed';else v_status:=case when lower(v_invoice.status)in('paid','pagado','pagada')then'confirmed'else v_invoice.status end;end if;
 update public.sales_invoices set paid_amount=v_paid,credited_amount=v_credit,balance=v_balance,customer_credit_balance=v_customer_credit,status=v_status,updated_at=now()where id=p_invoice_id;
 perform public.sync_invoice_status_to_job(p_invoice_id);
end;$$;
create or replace function public.recalculate_sales_invoice_payments(p_invoice_id uuid)returns void language plpgsql set search_path=public as $$begin perform public.recalculate_sales_invoice_settlement(p_invoice_id);end;$$;

create or replace function public.create_sales_credit_note(p_sales_invoice_id uuid,p_lines jsonb,p_issue_date timestamptz,p_reason_code text,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
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
 select v_tenant,v_note,v_invoice.id,source_line_key,source_line_index,product_id,product_name,product_sku,disposition,sales_return_line_id,credited_quantity,original_quantity,original_allocated_net,original_allocated_tax,net_amount,tax_amount,cost_amount,net_amount+tax_amount,line_snapshot from pg_temp.sales_credit_work;
 perform public.recalculate_sales_invoice_settlement(v_invoice.id);perform public.append_inventory_accounting_checkpoint(v_operation,'inventory_applied','completed','sales_credit_note',v_note,jsonb_build_object('movement_count',0));perform public.append_inventory_accounting_checkpoint(v_operation,'journal_posted','completed','journal_entry',v_journal,jsonb_build_object('balanced',true));perform public.append_inventory_accounting_checkpoint(v_operation,'invariants_verified','completed','sales_credit_note',v_note,jsonb_build_object('official_dte_status','internal'));
 update public.inventory_accounting_operations set outcome='completed',completed_at=clock_timestamp(),after_snapshot=jsonb_build_object('sales_credit_note_id',v_note,'total',v_totalnet+v_totaltax)where id=v_operation;perform public.append_inventory_accounting_checkpoint(v_operation,'completed','completed','sales_credit_note',v_note,jsonb_build_object('credit_note_number',v_number));
 return jsonb_build_object('sales_credit_note_id',v_note,'operation_id',v_operation,'credit_note_number',v_number,'replayed',false);
end;$$;

revoke all on function public.create_sales_credit_note(uuid,jsonb,timestamptz,text,text,text)from public,anon;grant execute on function public.create_sales_credit_note(uuid,jsonb,timestamptz,text,text,text)to authenticated;
commit;
