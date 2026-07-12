-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-12;
-- Viñabike controls activated separately after rollback-only authenticated smoke.
-- Financial settlement of credit balances. These documents record money that
-- staff already verified as paid/received externally; they never move stock or
-- claim to execute a bank/provider transaction.
begin;

alter table public.sales_invoices
  add column if not exists refunded_amount numeric(12,2) not null default 0;
alter table public.purchase_invoices
  add column if not exists supplier_refunded_amount numeric(12,2) not null default 0;

create table if not exists public.sales_customer_refund_control_settings(
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  control_mode text not null default 'disabled'
    check(control_mode in('disabled','shadow','enforce')),
  activated_at timestamptz,
  activated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp()
);
create table if not exists public.purchase_supplier_refund_control_settings(
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  control_mode text not null default 'disabled'
    check(control_mode in('disabled','shadow','enforce')),
  activated_at timestamptz,
  activated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.sales_customer_refund_control_settings enable row level security;
alter table public.purchase_supplier_refund_control_settings enable row level security;
drop policy if exists sales_customer_refund_control_select on public.sales_customer_refund_control_settings;
create policy sales_customer_refund_control_select
  on public.sales_customer_refund_control_settings for select to authenticated
  using(tenant_id=public.user_tenant_id());
drop policy if exists purchase_supplier_refund_control_select on public.purchase_supplier_refund_control_settings;
create policy purchase_supplier_refund_control_select
  on public.purchase_supplier_refund_control_settings for select to authenticated
  using(tenant_id=public.user_tenant_id());
revoke insert,update,delete on public.sales_customer_refund_control_settings,
  public.purchase_supplier_refund_control_settings from public,anon,authenticated;
grant select on public.sales_customer_refund_control_settings,
  public.purchase_supplier_refund_control_settings to authenticated;

create table if not exists public.sales_customer_refunds(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
  sales_credit_note_id uuid not null references public.sales_credit_notes(id) on delete restrict,
  refund_number text not null,
  status text not null default 'posted' check(status in('posted','voided')),
  refunded_at timestamptz not null,
  payment_method_id uuid not null references public.payment_methods(id) on delete restrict,
  amount numeric(12,2) not null check(amount>0 and amount=trunc(amount)),
  reference text not null,
  reason text not null,
  idempotency_key text not null,
  operation_id uuid not null,
  journal_entry_id uuid not null references public.journal_entries(id) on delete restrict,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  void_operation_id uuid,
  void_journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  void_idempotency_key text,
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text,
  unique(tenant_id,refund_number),unique(tenant_id,idempotency_key),unique(tenant_id,id),
  foreign key(tenant_id,operation_id) references public.inventory_accounting_operations(tenant_id,id) on delete restrict
);
create unique index if not exists uq_sales_customer_refund_void_key
  on public.sales_customer_refunds(tenant_id,void_idempotency_key)
  where void_idempotency_key is not null;

create table if not exists public.purchase_supplier_refunds(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  purchase_credit_note_id uuid not null references public.purchase_credit_notes(id) on delete restrict,
  refund_number text not null,
  status text not null default 'posted' check(status in('posted','voided')),
  refunded_at timestamptz not null,
  payment_method_id uuid not null references public.payment_methods(id) on delete restrict,
  amount numeric(12,2) not null check(amount>0 and amount=trunc(amount)),
  reference text not null,
  reason text not null,
  idempotency_key text not null,
  operation_id uuid not null,
  journal_entry_id uuid not null references public.journal_entries(id) on delete restrict,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  void_operation_id uuid,
  void_journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  void_idempotency_key text,
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text,
  unique(tenant_id,refund_number),unique(tenant_id,idempotency_key),unique(tenant_id,id),
  foreign key(tenant_id,operation_id) references public.inventory_accounting_operations(tenant_id,id) on delete restrict
);
create unique index if not exists uq_purchase_supplier_refund_void_key
  on public.purchase_supplier_refunds(tenant_id,void_idempotency_key)
  where void_idempotency_key is not null;

create index if not exists idx_sales_customer_refunds_note
  on public.sales_customer_refunds(tenant_id,sales_credit_note_id,created_at desc);
create index if not exists idx_sales_customer_refunds_invoice
  on public.sales_customer_refunds(tenant_id,sales_invoice_id,created_at desc);
create index if not exists idx_purchase_supplier_refunds_note
  on public.purchase_supplier_refunds(tenant_id,purchase_credit_note_id,created_at desc);
create index if not exists idx_purchase_supplier_refunds_invoice
  on public.purchase_supplier_refunds(tenant_id,purchase_invoice_id,created_at desc);

alter table public.sales_customer_refunds enable row level security;
alter table public.purchase_supplier_refunds enable row level security;
drop policy if exists sales_customer_refunds_select on public.sales_customer_refunds;
create policy sales_customer_refunds_select on public.sales_customer_refunds
  for select to authenticated using(tenant_id=public.user_tenant_id());
drop policy if exists purchase_supplier_refunds_select on public.purchase_supplier_refunds;
create policy purchase_supplier_refunds_select on public.purchase_supplier_refunds
  for select to authenticated using(tenant_id=public.user_tenant_id());
revoke insert,update,delete on public.sales_customer_refunds,public.purchase_supplier_refunds
  from public,anon,authenticated;
grant select on public.sales_customer_refunds,public.purchase_supplier_refunds to authenticated;

create or replace view public.sales_credit_note_refund_balance_view
with(security_invoker=true)as
select note.id,note.tenant_id,note.sales_invoice_id,note.credit_note_number,note.status,
 note.official_dte_status,note.issue_date,note.reason,note.total_amount,note.void_reason,
 coalesce(sum(refund.amount)filter(where refund.status='posted'),0)::numeric(12,2) refunded_amount,
 greatest(note.total_amount-coalesce(sum(refund.amount)filter(where refund.status='posted'),0),0)::numeric(12,2) remaining_refundable,
 invoice.customer_credit_balance invoice_credit_balance
from public.sales_credit_notes note
join public.sales_invoices invoice on invoice.id=note.sales_invoice_id and invoice.tenant_id=note.tenant_id
left join public.sales_customer_refunds refund on refund.sales_credit_note_id=note.id and refund.tenant_id=note.tenant_id
group by note.id,note.tenant_id,note.sales_invoice_id,note.credit_note_number,note.status,
 note.official_dte_status,note.issue_date,note.reason,note.total_amount,note.void_reason,invoice.customer_credit_balance;
grant select on public.sales_credit_note_refund_balance_view to authenticated;

create or replace view public.purchase_credit_note_refund_balance_view
with(security_invoker=true)as
select note.id,note.tenant_id,note.purchase_invoice_id,note.credit_note_number,
 note.supplier_credit_note_number,note.status,note.official_dte_status,note.issue_date,
 note.reason,note.total_amount,note.void_reason,
 coalesce(sum(refund.amount)filter(where refund.status='posted'),0)::numeric(12,2) refunded_amount,
 greatest(note.total_amount-coalesce(sum(refund.amount)filter(where refund.status='posted'),0),0)::numeric(12,2) remaining_refundable,
 invoice.supplier_credit_balance invoice_credit_balance
from public.purchase_credit_notes note
join public.purchase_invoices invoice on invoice.id=note.purchase_invoice_id and invoice.tenant_id=note.tenant_id
left join public.purchase_supplier_refunds refund on refund.purchase_credit_note_id=note.id and refund.tenant_id=note.tenant_id
group by note.id,note.tenant_id,note.purchase_invoice_id,note.credit_note_number,
 note.supplier_credit_note_number,note.status,note.official_dte_status,note.issue_date,
 note.reason,note.total_amount,note.void_reason,invoice.supplier_credit_balance;
grant select on public.purchase_credit_note_refund_balance_view to authenticated;

create or replace function public.recalculate_sales_invoice_settlement(p_invoice_id uuid)
returns void language plpgsql set search_path=public as $$
declare v_invoice public.sales_invoices%rowtype;v_paid numeric;v_credit numeric;v_refunded numeric;v_net_paid numeric;v_effective numeric;v_balance numeric;v_customer_credit numeric;v_status text;
begin
 select * into v_invoice from public.sales_invoices where id=p_invoice_id for update;if not found then return;end if;
 select public.clp_round(coalesce(sum(amount),0))into v_paid from public.sales_payments where invoice_id=p_invoice_id and deleted_at is null;
 select public.clp_round(coalesce(sum(total_amount),0))into v_credit from public.sales_credit_notes where sales_invoice_id=p_invoice_id and status='posted';
 select public.clp_round(coalesce(sum(amount),0))into v_refunded from public.sales_customer_refunds where sales_invoice_id=p_invoice_id and status='posted';
 v_net_paid:=greatest(v_paid-v_refunded,0);v_effective:=greatest(public.clp_round(v_invoice.total)-v_credit,0);v_balance:=greatest(v_effective-v_net_paid,0);v_customer_credit:=greatest(v_net_paid-v_effective,0);
 if lower(v_invoice.status)in('cancelled','cancelado','cancelada','anulado','anulada')then v_status:=v_invoice.status;
 elsif lower(v_invoice.status)in('draft','borrador')then v_status:=v_invoice.status;
 elsif v_balance=0 and(v_paid>0 or v_credit>=public.clp_round(v_invoice.total))then v_status:='paid';elsif v_net_paid>0 then v_status:='confirmed';else v_status:=case when lower(v_invoice.status)in('paid','pagado','pagada')then'confirmed'else v_invoice.status end;end if;
 update public.sales_invoices set paid_amount=v_paid,refunded_amount=v_refunded,credited_amount=v_credit,balance=v_balance,customer_credit_balance=v_customer_credit,status=v_status,updated_at=now()where id=p_invoice_id;
 perform public.sync_invoice_status_to_job(p_invoice_id);
end;$$;

create or replace function public.recalculate_purchase_invoice_settlement(p_invoice_id uuid)
returns void language plpgsql set search_path=public as $$
declare v_invoice public.purchase_invoices%rowtype;v_paid numeric;v_credit numeric;v_refunded numeric;v_net_paid numeric;v_effective numeric;v_balance numeric;v_supplier_credit numeric;v_status text;
begin
 select * into v_invoice from public.purchase_invoices where id=p_invoice_id for update;if not found then return;end if;
 select public.clp_round(coalesce(sum(amount),0))into v_paid from public.purchase_payments where invoice_id=p_invoice_id and deleted_at is null;
 select public.clp_round(coalesce(sum(total_amount),0))into v_credit from public.purchase_credit_notes where purchase_invoice_id=p_invoice_id and status='posted';
 select public.clp_round(coalesce(sum(amount),0))into v_refunded from public.purchase_supplier_refunds where purchase_invoice_id=p_invoice_id and status='posted';
 v_net_paid:=greatest(v_paid-v_refunded,0);v_effective:=greatest(public.clp_round(v_invoice.total)-v_credit,0);v_balance:=greatest(v_effective-v_net_paid,0);v_supplier_credit:=greatest(v_net_paid-v_effective,0);
 if v_invoice.status='cancelled'then v_status:='cancelled';elsif v_invoice.status='received'or v_invoice.received_date is not null then v_status:='received';
 elsif v_invoice.status in('draft','sent')then v_status:=v_invoice.status;elsif v_balance=0 and(v_paid>0 or v_credit>=public.clp_round(v_invoice.total))then v_status:='paid';
 elsif v_net_paid>0 and v_balance>0 then v_status:='confirmed';else v_status:=case when v_invoice.status='paid'then'confirmed'else v_invoice.status end;end if;
 update public.purchase_invoices set paid_amount=v_paid,supplier_refunded_amount=v_refunded,credited_amount=v_credit,balance=v_balance,supplier_credit_balance=v_supplier_credit,status=v_status,updated_at=now()where id=p_invoice_id;
end;$$;

create or replace function public.create_sales_customer_refund(
 p_sales_credit_note_id uuid,p_refunded_at timestamptz,p_payment_method_id uuid,
 p_amount numeric,p_reference text,p_reason text,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_mode text:='disabled';v_note public.sales_credit_notes%rowtype;v_invoice public.sales_invoices%rowtype;v_existing public.sales_customer_refunds%rowtype;v_method record;v_used numeric;v_available numeric;v_refund uuid:=gen_random_uuid();v_op uuid:=gen_random_uuid();v_journal uuid:=gen_random_uuid();v_number text;v_desc text;v_ar uuid;
begin
 if v_actor is null or v_tenant is null then raise exception'Authenticated employee tenant is required';end if;
 if p_refunded_at is null or p_refunded_at>clock_timestamp()+interval'5 minutes'then raise exception'Valid refund date is required and cannot be in the future';end if;
 if p_amount is null or p_amount<=0 or p_amount<>trunc(p_amount)then raise exception'Refund amount must be positive whole CLP';end if;
 if nullif(btrim(p_reference),'')is null or nullif(btrim(p_reason),'')is null or nullif(btrim(p_idempotency_key),'')is null then raise exception'Refund reference, reason, and idempotency key are required';end if;
 select * into v_existing from public.sales_customer_refunds where tenant_id=v_tenant and idempotency_key=btrim(p_idempotency_key);if found then if v_existing.sales_credit_note_id<>p_sales_credit_note_id then raise exception'Idempotency key belongs to another sales credit note';end if;return jsonb_build_object('refund_id',v_existing.id,'operation_id',v_existing.operation_id,'refund_number',v_existing.refund_number,'replayed',true);end if;
 select coalesce(control_mode,'disabled')into v_mode from public.sales_customer_refund_control_settings where tenant_id=v_tenant;if not found then v_mode:='disabled';end if;if v_mode<>'enforce'then raise exception'Sales credit settlement is not active for this tenant';end if;
 select * into v_note from public.sales_credit_notes where id=p_sales_credit_note_id and tenant_id=v_tenant for update;if not found or v_note.status<>'posted'then raise exception'Posted sales credit note not found';end if;
 select * into v_invoice from public.sales_invoices where id=v_note.sales_invoice_id and tenant_id=v_tenant for update;if not found then raise exception'Sales invoice not found';end if;
 select method.*,account.code account_code,account.name account_name into v_method from public.payment_methods method join public.accounts account on account.id=method.account_id and account.tenant_id=method.tenant_id where method.id=p_payment_method_id and method.tenant_id=v_tenant and method.is_active;if not found then raise exception'Active refund payment method not found';end if;
 select public.clp_round(coalesce(sum(amount),0))into v_used from public.sales_customer_refunds where sales_credit_note_id=v_note.id and status='posted';v_available:=least(v_note.total_amount-v_used,v_invoice.customer_credit_balance);if p_amount>v_available then raise exception'Refund exceeds available customer credit balance: %',v_available;end if;
 v_number:=public.get_next_document_number(v_tenant,'sales_customer_refund','RC');v_desc:=format('Reembolso cliente %s - %s',v_number,v_note.credit_note_number);v_ar:=public.ensure_account(v_tenant,'1130','Cuentas por Cobrar Comerciales','asset','currentAsset','Cuentas por cobrar a clientes',null);
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,context)values(v_op,v_tenant,format('sales_customer_refund:%s:%s',v_note.id,btrim(p_idempotency_key)),'sales_customer_refund','create','sales_customer_refund',v_refund,v_actor,'database_command',jsonb_build_object('sales_invoice_id',v_invoice.id,'sales_credit_note_id',v_note.id,'amount',p_amount,'external_transfer_executed_by_erp',false));
 perform public.append_inventory_accounting_checkpoint(v_op,'accepted','started','sales_credit_note',v_note.id,jsonb_build_object('amount',p_amount,'reference',btrim(p_reference)));
 insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by)values(v_journal,v_tenant,public.get_next_document_number(v_tenant,'journal_entry'),p_refunded_at,v_desc,'refund','sales_customer_refunds',v_refund::text,'posted',p_amount,p_amount,v_op,'sales_customer_refund',v_refund,v_actor);
 insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount)values(gen_random_uuid(),v_tenant,v_journal,v_ar,'1130','Cuentas por Cobrar Comerciales',v_desc,p_amount,0),(gen_random_uuid(),v_tenant,v_journal,v_method.account_id,v_method.account_code,v_method.account_name,v_desc,0,p_amount);
 insert into public.sales_customer_refunds(id,tenant_id,sales_invoice_id,sales_credit_note_id,refund_number,refunded_at,payment_method_id,amount,reference,reason,idempotency_key,operation_id,journal_entry_id,created_by)values(v_refund,v_tenant,v_invoice.id,v_note.id,v_number,p_refunded_at,p_payment_method_id,p_amount,btrim(p_reference),btrim(p_reason),btrim(p_idempotency_key),v_op,v_journal,v_actor);
 perform public.recalculate_sales_invoice_settlement(v_invoice.id);perform public.append_inventory_accounting_checkpoint(v_op,'inventory_applied','completed','sales_customer_refund',v_refund,jsonb_build_object('movement_count',0));perform public.append_inventory_accounting_checkpoint(v_op,'journal_posted','completed','journal_entry',v_journal,jsonb_build_object('amount',p_amount,'balanced',true));
 update public.inventory_accounting_operations set after_snapshot=jsonb_build_object('refund_id',v_refund,'invoice_credit_balance',(select customer_credit_balance from public.sales_invoices where id=v_invoice.id))where id=v_op;
 perform public.complete_inventory_accounting_operation(v_op,v_tenant,jsonb_build_object('refund_id',v_refund,'refund_number',v_number));
 return jsonb_build_object('refund_id',v_refund,'operation_id',v_op,'refund_number',v_number,'replayed',false);
end;$$;

create or replace function public.create_purchase_supplier_refund(
 p_purchase_credit_note_id uuid,p_refunded_at timestamptz,p_payment_method_id uuid,
 p_amount numeric,p_reference text,p_reason text,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_mode text:='disabled';v_note public.purchase_credit_notes%rowtype;v_invoice public.purchase_invoices%rowtype;v_existing public.purchase_supplier_refunds%rowtype;v_method record;v_used numeric;v_available numeric;v_refund uuid:=gen_random_uuid();v_op uuid:=gen_random_uuid();v_journal uuid:=gen_random_uuid();v_number text;v_desc text;v_ap uuid;
begin
 if v_actor is null or v_tenant is null then raise exception'Authenticated employee tenant is required';end if;
 if p_refunded_at is null or p_refunded_at>clock_timestamp()+interval'5 minutes'then raise exception'Valid refund date is required and cannot be in the future';end if;
 if p_amount is null or p_amount<=0 or p_amount<>trunc(p_amount)then raise exception'Refund amount must be positive whole CLP';end if;
 if nullif(btrim(p_reference),'')is null or nullif(btrim(p_reason),'')is null or nullif(btrim(p_idempotency_key),'')is null then raise exception'Refund reference, reason, and idempotency key are required';end if;
 select * into v_existing from public.purchase_supplier_refunds where tenant_id=v_tenant and idempotency_key=btrim(p_idempotency_key);if found then if v_existing.purchase_credit_note_id<>p_purchase_credit_note_id then raise exception'Idempotency key belongs to another purchase credit note';end if;return jsonb_build_object('refund_id',v_existing.id,'operation_id',v_existing.operation_id,'refund_number',v_existing.refund_number,'replayed',true);end if;
 select coalesce(control_mode,'disabled')into v_mode from public.purchase_supplier_refund_control_settings where tenant_id=v_tenant;if not found then v_mode:='disabled';end if;if v_mode<>'enforce'then raise exception'Purchase credit settlement is not active for this tenant';end if;
 select * into v_note from public.purchase_credit_notes where id=p_purchase_credit_note_id and tenant_id=v_tenant for update;if not found or v_note.status<>'posted'then raise exception'Posted purchase credit note not found';end if;
 select * into v_invoice from public.purchase_invoices where id=v_note.purchase_invoice_id and tenant_id=v_tenant for update;if not found then raise exception'Purchase invoice not found';end if;
 select method.*,account.code account_code,account.name account_name into v_method from public.payment_methods method join public.accounts account on account.id=method.account_id and account.tenant_id=method.tenant_id where method.id=p_payment_method_id and method.tenant_id=v_tenant and method.is_active;if not found then raise exception'Active refund payment method not found';end if;
 select public.clp_round(coalesce(sum(amount),0))into v_used from public.purchase_supplier_refunds where purchase_credit_note_id=v_note.id and status='posted';v_available:=least(v_note.total_amount-v_used,v_invoice.supplier_credit_balance);if p_amount>v_available then raise exception'Refund exceeds available supplier credit balance: %',v_available;end if;
 v_number:=public.get_next_document_number(v_tenant,'purchase_supplier_refund','RP');v_desc:=format('Reembolso proveedor %s - %s',v_number,v_note.credit_note_number);v_ap:=public.ensure_account(v_tenant,'2101','Cuentas por Pagar Proveedores','liability','currentLiability','Cuentas por pagar a proveedores',null);
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,context)values(v_op,v_tenant,format('purchase_supplier_refund:%s:%s',v_note.id,btrim(p_idempotency_key)),'purchase_supplier_refund','create','purchase_supplier_refund',v_refund,v_actor,'database_command',jsonb_build_object('purchase_invoice_id',v_invoice.id,'purchase_credit_note_id',v_note.id,'amount',p_amount,'external_transfer_executed_by_erp',false));
 perform public.append_inventory_accounting_checkpoint(v_op,'accepted','started','purchase_credit_note',v_note.id,jsonb_build_object('amount',p_amount,'reference',btrim(p_reference)));
 insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by)values(v_journal,v_tenant,public.get_next_document_number(v_tenant,'journal_entry'),p_refunded_at,v_desc,'refund','purchase_supplier_refunds',v_refund::text,'posted',p_amount,p_amount,v_op,'purchase_supplier_refund',v_refund,v_actor);
 insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount)values(gen_random_uuid(),v_tenant,v_journal,v_method.account_id,v_method.account_code,v_method.account_name,v_desc,p_amount,0),(gen_random_uuid(),v_tenant,v_journal,v_ap,'2101','Cuentas por Pagar Proveedores',v_desc,0,p_amount);
 insert into public.purchase_supplier_refunds(id,tenant_id,purchase_invoice_id,purchase_credit_note_id,refund_number,refunded_at,payment_method_id,amount,reference,reason,idempotency_key,operation_id,journal_entry_id,created_by)values(v_refund,v_tenant,v_invoice.id,v_note.id,v_number,p_refunded_at,p_payment_method_id,p_amount,btrim(p_reference),btrim(p_reason),btrim(p_idempotency_key),v_op,v_journal,v_actor);
 perform public.recalculate_purchase_invoice_settlement(v_invoice.id);perform public.append_inventory_accounting_checkpoint(v_op,'inventory_applied','completed','purchase_supplier_refund',v_refund,jsonb_build_object('movement_count',0));perform public.append_inventory_accounting_checkpoint(v_op,'journal_posted','completed','journal_entry',v_journal,jsonb_build_object('amount',p_amount,'balanced',true));
 update public.inventory_accounting_operations set after_snapshot=jsonb_build_object('refund_id',v_refund,'invoice_credit_balance',(select supplier_credit_balance from public.purchase_invoices where id=v_invoice.id))where id=v_op;
 perform public.complete_inventory_accounting_operation(v_op,v_tenant,jsonb_build_object('refund_id',v_refund,'refund_number',v_number));
 return jsonb_build_object('refund_id',v_refund,'operation_id',v_op,'refund_number',v_number,'replayed',false);
end;$$;

create or replace function public.void_sales_customer_refund(p_refund_id uuid,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_refund public.sales_customer_refunds%rowtype;v_op uuid:=gen_random_uuid();v_journal uuid:=gen_random_uuid();v_original public.journal_entries%rowtype;
begin if v_actor is null or v_tenant is null or nullif(btrim(p_reason),'')is null or nullif(btrim(p_idempotency_key),'')is null then raise exception'Authenticated tenant, void reason, and idempotency key are required';end if;
 select * into v_refund from public.sales_customer_refunds where id=p_refund_id and tenant_id=v_tenant for update;if not found then raise exception'Customer refund not found';end if;if v_refund.status='voided'then if v_refund.void_idempotency_key=btrim(p_idempotency_key)then return jsonb_build_object('refund_id',v_refund.id,'operation_id',v_refund.void_operation_id,'replayed',true);end if;raise exception'Customer refund already voided';end if;
 select * into v_original from public.journal_entries where id=v_refund.journal_entry_id;
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,context)values(v_op,v_tenant,format('sales_customer_refund_void:%s:%s',v_refund.id,btrim(p_idempotency_key)),'sales_customer_refund','void','sales_customer_refund',v_refund.id,v_actor,'database_command',jsonb_build_object('reversal_of_operation_id',v_refund.operation_id));
 insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by,reversal_of_id)values(v_journal,v_tenant,public.get_next_document_number(v_tenant,'journal_entry'),now(),'Anulación '||v_original.description,'refund_void','sales_customer_refunds',v_refund.id::text||':void','posted',v_refund.amount,v_refund.amount,v_op,'sales_customer_refund',v_refund.id,v_actor,v_original.id);
 insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount)select gen_random_uuid(),tenant_id,v_journal,account_id,account_code,account_name,'Anulación '||description,credit_amount,debit_amount from public.journal_lines where entry_id=v_original.id;
 update public.sales_customer_refunds set status='voided',void_operation_id=v_op,void_journal_entry_id=v_journal,void_idempotency_key=btrim(p_idempotency_key),voided_at=now(),voided_by=v_actor,void_reason=btrim(p_reason)where id=v_refund.id;perform public.recalculate_sales_invoice_settlement(v_refund.sales_invoice_id);perform public.append_inventory_accounting_checkpoint(v_op,'inventory_applied','completed','sales_customer_refund',v_refund.id,jsonb_build_object('movement_count',0));perform public.append_inventory_accounting_checkpoint(v_op,'journal_reversed','completed','journal_entry',v_journal,jsonb_build_object('reversal_of_id',v_original.id));perform public.complete_inventory_accounting_operation(v_op,v_tenant,jsonb_build_object('refund_id',v_refund.id,'voided',true));return jsonb_build_object('refund_id',v_refund.id,'operation_id',v_op,'replayed',false);end;$$;

create or replace function public.void_purchase_supplier_refund(p_refund_id uuid,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_refund public.purchase_supplier_refunds%rowtype;v_op uuid:=gen_random_uuid();v_journal uuid:=gen_random_uuid();v_original public.journal_entries%rowtype;
begin if v_actor is null or v_tenant is null or nullif(btrim(p_reason),'')is null or nullif(btrim(p_idempotency_key),'')is null then raise exception'Authenticated tenant, void reason, and idempotency key are required';end if;
 select * into v_refund from public.purchase_supplier_refunds where id=p_refund_id and tenant_id=v_tenant for update;if not found then raise exception'Supplier refund not found';end if;if v_refund.status='voided'then if v_refund.void_idempotency_key=btrim(p_idempotency_key)then return jsonb_build_object('refund_id',v_refund.id,'operation_id',v_refund.void_operation_id,'replayed',true);end if;raise exception'Supplier refund already voided';end if;
 select * into v_original from public.journal_entries where id=v_refund.journal_entry_id;
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,context)values(v_op,v_tenant,format('purchase_supplier_refund_void:%s:%s',v_refund.id,btrim(p_idempotency_key)),'purchase_supplier_refund','void','purchase_supplier_refund',v_refund.id,v_actor,'database_command',jsonb_build_object('reversal_of_operation_id',v_refund.operation_id));
 insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by,reversal_of_id)values(v_journal,v_tenant,public.get_next_document_number(v_tenant,'journal_entry'),now(),'Anulación '||v_original.description,'refund_void','purchase_supplier_refunds',v_refund.id::text||':void','posted',v_refund.amount,v_refund.amount,v_op,'purchase_supplier_refund',v_refund.id,v_actor,v_original.id);
 insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount)select gen_random_uuid(),tenant_id,v_journal,account_id,account_code,account_name,'Anulación '||description,credit_amount,debit_amount from public.journal_lines where entry_id=v_original.id;
 update public.purchase_supplier_refunds set status='voided',void_operation_id=v_op,void_journal_entry_id=v_journal,void_idempotency_key=btrim(p_idempotency_key),voided_at=now(),voided_by=v_actor,void_reason=btrim(p_reason)where id=v_refund.id;perform public.recalculate_purchase_invoice_settlement(v_refund.purchase_invoice_id);perform public.append_inventory_accounting_checkpoint(v_op,'inventory_applied','completed','purchase_supplier_refund',v_refund.id,jsonb_build_object('movement_count',0));perform public.append_inventory_accounting_checkpoint(v_op,'journal_reversed','completed','journal_entry',v_journal,jsonb_build_object('reversal_of_id',v_original.id));perform public.complete_inventory_accounting_operation(v_op,v_tenant,jsonb_build_object('refund_id',v_refund.id,'voided',true));return jsonb_build_object('refund_id',v_refund.id,'operation_id',v_op,'replayed',false);end;$$;

create or replace function public.prevent_credit_note_void_with_posted_refund()
returns trigger language plpgsql set search_path=public as $$
begin
 if old.status='posted'and new.status='voided'then
  if tg_table_name='sales_credit_notes'and exists(select 1 from public.sales_customer_refunds where sales_credit_note_id=old.id and status='posted')then raise exception'Void posted customer refunds before voiding this sales credit note';end if;
  if tg_table_name='purchase_credit_notes'and exists(select 1 from public.purchase_supplier_refunds where purchase_credit_note_id=old.id and status='posted')then raise exception'Void posted supplier refunds before voiding this purchase credit note';end if;
 end if;return new;
end;$$;
drop trigger if exists trg_prevent_sales_credit_void_with_refund on public.sales_credit_notes;
create trigger trg_prevent_sales_credit_void_with_refund before update of status on public.sales_credit_notes for each row execute function public.prevent_credit_note_void_with_posted_refund();
drop trigger if exists trg_prevent_purchase_credit_void_with_refund on public.purchase_credit_notes;
create trigger trg_prevent_purchase_credit_void_with_refund before update of status on public.purchase_credit_notes for each row execute function public.prevent_credit_note_void_with_posted_refund();

revoke all on function public.create_sales_customer_refund(uuid,timestamptz,uuid,numeric,text,text,text) from public,anon;
revoke all on function public.create_purchase_supplier_refund(uuid,timestamptz,uuid,numeric,text,text,text) from public,anon;
revoke all on function public.void_sales_customer_refund(uuid,text,text) from public,anon;
revoke all on function public.void_purchase_supplier_refund(uuid,text,text) from public,anon;
grant execute on function public.create_sales_customer_refund(uuid,timestamptz,uuid,numeric,text,text,text) to authenticated;
grant execute on function public.create_purchase_supplier_refund(uuid,timestamptz,uuid,numeric,text,text,text) to authenticated;
grant execute on function public.void_sales_customer_refund(uuid,text,text) to authenticated;
grant execute on function public.void_purchase_supplier_refund(uuid,text,text) to authenticated;

comment on table public.sales_customer_refunds is 'Verified external money returned to a customer against a posted sales credit note; no stock effect.';
comment on table public.purchase_supplier_refunds is 'Verified external money received from a supplier against a posted purchase credit note; no stock effect.';

commit;
