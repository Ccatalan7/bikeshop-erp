-- Deployment status: DEPLOYED 2026-07-11. Sales-return control remains disabled.
-- Turns returned-goods quarantine into an explicit, reversible custody workflow.
begin;

create table if not exists public.sales_return_quarantine_resolutions(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 quarantine_id uuid not null references public.sales_return_quarantine(id) on delete restrict,
 sales_return_id uuid not null references public.sales_returns(id) on delete restrict,
 disposition text not null check(disposition in('released','scrapped')),
 status text not null default 'posted' check(status in('posted','voided')),
 resolved_at timestamptz not null,
 reason text not null,
 notes text,
 idempotency_key text not null,
 operation_id uuid not null,
 journal_entry_id uuid references public.journal_entries(id),
 created_by uuid references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 void_operation_id uuid,
 void_journal_entry_id uuid references public.journal_entries(id),
 void_idempotency_key text,
 voided_at timestamptz,
 voided_by uuid references auth.users(id),
 void_reason text,
 unique(tenant_id,id),
 unique(tenant_id,idempotency_key),
 foreign key(tenant_id,operation_id) references public.inventory_accounting_operations(tenant_id,id) on delete restrict
);
create unique index if not exists uq_sales_return_quarantine_resolution_void_key
 on public.sales_return_quarantine_resolutions(tenant_id,void_idempotency_key)
 where void_idempotency_key is not null;

create table if not exists public.sales_return_quarantine_resolution_movements(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 resolution_id uuid not null references public.sales_return_quarantine_resolutions(id) on delete restrict,
 sales_return_line_movement_id uuid not null references public.sales_return_line_movements(id) on delete restrict,
 product_id uuid not null references public.products(id) on delete restrict,
 stock_movement_id uuid not null references public.stock_movements(id) on delete restrict,
 quantity integer not null check(quantity>0),
 created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,resolution_id,sales_return_line_movement_id)
);

alter table public.sales_return_quarantine
 add column if not exists resolution_id uuid references public.sales_return_quarantine_resolutions(id);

-- Earlier inactive drafts stored the last set component here. The quarantine row
-- represents the commercial return line; physical components remain in the mapping table.
update public.sales_return_quarantine quarantine
set product_id=line.product_id
from public.sales_return_lines line
where line.id=quarantine.sales_return_line_id
  and quarantine.product_id is distinct from line.product_id;

alter table public.sales_return_quarantine_resolutions enable row level security;
alter table public.sales_return_quarantine_resolution_movements enable row level security;
drop policy if exists sales_return_quarantine_resolutions_select on public.sales_return_quarantine_resolutions;
create policy sales_return_quarantine_resolutions_select on public.sales_return_quarantine_resolutions
 for select to authenticated using(tenant_id=public.user_tenant_id());
drop policy if exists sales_return_quarantine_resolution_movements_select on public.sales_return_quarantine_resolution_movements;
create policy sales_return_quarantine_resolution_movements_select on public.sales_return_quarantine_resolution_movements
 for select to authenticated using(tenant_id=public.user_tenant_id());
revoke insert,update,delete on public.sales_return_quarantine_resolutions,public.sales_return_quarantine_resolution_movements from public,anon,authenticated;
grant select on public.sales_return_quarantine_resolutions,public.sales_return_quarantine_resolution_movements to authenticated;

create or replace function public.resolve_sales_return_quarantine(
 p_quarantine_id uuid,p_disposition text,p_resolved_at timestamptz,p_reason text,p_notes text default null,p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_mode text:='disabled';
 v_quarantine public.sales_return_quarantine%rowtype;v_line public.sales_return_lines%rowtype;v_return public.sales_returns%rowtype;
 v_existing public.sales_return_quarantine_resolutions%rowtype;v_resolution uuid:=gen_random_uuid();v_operation uuid:=gen_random_uuid();
 v_disposition text;v_mapping record;v_product public.products%rowtype;v_before integer;v_after integer;v_stock_movement uuid;
 v_cost numeric;v_entry uuid;v_debit_account uuid;v_quarantine_account uuid;v_description text;
begin
 if v_actor is null or v_tenant is null then raise exception 'Authenticated employee tenant is required';end if;
 if p_resolved_at is null or nullif(btrim(p_reason),'') is null or nullif(btrim(p_idempotency_key),'') is null then raise exception 'Quarantine resolution date, reason, and idempotency key are required';end if;
 v_disposition:=case lower(coalesce(p_disposition,'')) when 'release' then 'released' when 'released' then 'released' when 'scrap' then 'scrapped' when 'scrapped' then 'scrapped' else null end;
 if v_disposition is null then raise exception 'Quarantine resolution must be release or scrap';end if;
 select * into v_existing from public.sales_return_quarantine_resolutions where tenant_id=v_tenant and idempotency_key=btrim(p_idempotency_key);
 if found then
  if v_existing.quarantine_id<>p_quarantine_id then raise exception 'Idempotency key belongs to a different quarantine record';end if;
  return jsonb_build_object('resolution_id',v_existing.id,'operation_id',v_existing.operation_id,'disposition',v_existing.disposition,'replayed',true);
 end if;
 select coalesce(setting.control_mode,'disabled') into v_mode from(select 1)seed left join public.sales_return_control_settings setting on setting.tenant_id=v_tenant;
 if v_mode<>'enforce' then raise exception 'Sales return workflow is not active for this tenant';end if;
 select * into v_quarantine from public.sales_return_quarantine where id=p_quarantine_id and tenant_id=v_tenant for update;
 if not found then raise exception 'Sales return quarantine record not found for current tenant';end if;
 if v_quarantine.status<>'held' then raise exception 'Sales return quarantine record is not awaiting resolution';end if;
 select * into v_line from public.sales_return_lines where id=v_quarantine.sales_return_line_id and tenant_id=v_tenant;
 select * into v_return from public.sales_returns where id=v_line.sales_return_id and tenant_id=v_tenant for update;
 if v_return.status<>'posted' then raise exception 'Sales return must remain posted while quarantine is resolved';end if;

 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,old_status,new_status,context)
 values(v_operation,v_tenant,format('sales_return_quarantine:%s:%s',p_quarantine_id,btrim(p_idempotency_key)),'sales_return','resolve','sales_return_quarantine_resolution',v_resolution,v_actor,'database_command','held',v_disposition,jsonb_build_object('quarantine_id',p_quarantine_id,'sales_return_id',v_return.id));
 perform public.append_inventory_accounting_checkpoint(v_operation,'accepted','started','sales_return_quarantine',p_quarantine_id,jsonb_build_object('disposition',v_disposition));
 insert into public.sales_return_quarantine_resolutions(id,tenant_id,quarantine_id,sales_return_id,disposition,resolved_at,reason,notes,idempotency_key,operation_id,created_by)
 values(v_resolution,v_tenant,p_quarantine_id,v_return.id,v_disposition,p_resolved_at,btrim(p_reason),nullif(btrim(p_notes),''),btrim(p_idempotency_key),v_operation,v_actor);

 perform set_config('app.skip_stock_adjustment_trigger','true',true);
 if v_disposition='released' then
  for v_mapping in
   select mapping.* from public.sales_return_line_movements mapping
   where mapping.sales_return_line_id=v_line.id and mapping.tenant_id=v_tenant order by mapping.product_id,mapping.id
  loop
   select * into v_product from public.products where id=v_mapping.product_id and tenant_id=v_tenant for update;
   if coalesce(v_product.inventory_qty,0)<>coalesce(v_product.stock_quantity,0) then raise exception 'Product stock columns disagree; quarantine release blocked';end if;
   v_before:=coalesce(v_product.inventory_qty,0);v_after:=v_before+v_mapping.quantity;
   update public.products set inventory_qty=v_after,stock_quantity=v_after where id=v_product.id;
   v_stock_movement:=gen_random_uuid();
   insert into public.stock_movements(id,tenant_id,product_id,type,movement_type,quantity,reference,notes,date,created_at,updated_at,operation_id,source_document_type,source_document_id,created_by,stock_before,stock_after,reversal_of_id)
   values(v_stock_movement,v_tenant,v_product.id,'IN','sales_return_quarantine_release',v_mapping.quantity,'sales_return_quarantine_resolution:'||v_resolution,format('Liberación de cuarentena devolución %s',v_return.return_number),p_resolved_at,now(),now(),v_operation,'sales_return_quarantine_resolution',v_resolution,v_actor,v_before,v_after,v_mapping.original_sale_movement_id);
   insert into public.sales_return_quarantine_resolution_movements(tenant_id,resolution_id,sales_return_line_movement_id,product_id,stock_movement_id,quantity)
   values(v_tenant,v_resolution,v_mapping.id,v_product.id,v_stock_movement,v_mapping.quantity);
  end loop;
 end if;
 perform set_config('app.skip_stock_adjustment_trigger','',true);

 v_cost:=public.clp_round(v_line.returned_quantity*coalesce(nullif(v_line.line_snapshot->>'cost','')::numeric,0));
 if v_cost>0 then
  v_entry:=gen_random_uuid();
  v_quarantine_account:=public.ensure_account(v_tenant,'1106','Inventario en Cuarentena','asset','currentAsset','Devoluciones recibidas pendientes de inspección',null);
  if v_disposition='released' then
   v_debit_account:=public.ensure_account(v_tenant,'1105','Inventarios','asset','currentAsset','Valor del inventario',null);v_description:='Liberación de inventario en cuarentena';
  else
   v_debit_account:=public.ensure_account(v_tenant,'5205','Pérdidas de Inventario','expense','operatingExpense','Mercadería dañada o no recuperable',null);v_description:='Baja de inventario en cuarentena';
  end if;
  insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by,created_at,updated_at)
  values(v_entry,v_tenant,public.get_next_document_number(v_tenant,'journal_entry'),p_resolved_at,v_description,'quarantine_resolution','sales_return_quarantine',v_resolution::text,'posted',v_cost,v_cost,v_operation,'sales_return_quarantine_resolution',v_resolution,v_actor,now(),now());
  insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)
  values
   (gen_random_uuid(),v_tenant,v_entry,v_debit_account,case when v_disposition='released'then'1105'else'5205'end,case when v_disposition='released'then'Inventarios'else'Pérdidas de Inventario'end,v_description,v_cost,0,now(),now()),
   (gen_random_uuid(),v_tenant,v_entry,v_quarantine_account,'1106','Inventario en Cuarentena',v_description,0,v_cost,now(),now());
  update public.sales_return_quarantine_resolutions set journal_entry_id=v_entry where id=v_resolution;
 end if;
 update public.sales_return_quarantine set status=v_disposition,resolution_id=v_resolution where id=p_quarantine_id;
 perform public.append_inventory_accounting_checkpoint(v_operation,'inventory_applied','completed','sales_return_quarantine_resolution',v_resolution,jsonb_build_object('stock_movement_count',(select count(*) from public.sales_return_quarantine_resolution_movements where resolution_id=v_resolution),'disposition',v_disposition));
 perform public.append_inventory_accounting_checkpoint(v_operation,'journal_posted','completed','journal_entry',v_entry,jsonb_build_object('inventory_value',v_cost,'from_account','1106'));
 perform public.append_inventory_accounting_checkpoint(v_operation,'invariants_verified','completed','sales_return_quarantine_resolution',v_resolution,jsonb_build_object('quarantine_status',v_disposition));
 update public.inventory_accounting_operations set outcome='completed',completed_at=clock_timestamp(),after_snapshot=jsonb_build_object('resolution_id',v_resolution,'status',v_disposition) where id=v_operation;
 perform public.append_inventory_accounting_checkpoint(v_operation,'completed','completed','sales_return_quarantine_resolution',v_resolution,jsonb_build_object('status',v_disposition));
 return jsonb_build_object('resolution_id',v_resolution,'operation_id',v_operation,'disposition',v_disposition,'replayed',false);
exception when others then perform set_config('app.skip_stock_adjustment_trigger','',true);raise;
end;$$;

create or replace function public.void_sales_return_quarantine_resolution(p_resolution_id uuid,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_resolution public.sales_return_quarantine_resolutions%rowtype;v_quarantine public.sales_return_quarantine%rowtype;
 v_operation uuid:=gen_random_uuid();v_mapping record;v_product public.products%rowtype;v_before integer;v_after integer;v_reversal uuid;
 v_entry uuid;v_line record;v_amount numeric:=0;v_description text:='Anulación de resolución de cuarentena';
begin
 if v_actor is null or v_tenant is null then raise exception 'Authenticated employee tenant is required';end if;
 if nullif(btrim(p_reason),'') is null or nullif(btrim(p_idempotency_key),'') is null then raise exception 'Quarantine resolution void reason and idempotency key are required';end if;
 select * into v_resolution from public.sales_return_quarantine_resolutions where id=p_resolution_id and tenant_id=v_tenant for update;
 if not found then raise exception 'Quarantine resolution not found for current tenant';end if;
 if v_resolution.status='voided' then
  if v_resolution.void_idempotency_key=btrim(p_idempotency_key) then return jsonb_build_object('resolution_id',v_resolution.id,'operation_id',v_resolution.void_operation_id,'replayed',true);end if;
  raise exception 'Quarantine resolution is already voided';
 end if;
 select * into v_quarantine from public.sales_return_quarantine where id=v_resolution.quarantine_id and tenant_id=v_tenant for update;
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,old_status,new_status,context)
 values(v_operation,v_tenant,format('sales_return_quarantine_void:%s:%s',p_resolution_id,btrim(p_idempotency_key)),'sales_return','void','sales_return_quarantine_resolution',p_resolution_id,v_actor,'database_command',v_resolution.disposition,'held',jsonb_build_object('reason',btrim(p_reason)));
 perform public.append_inventory_accounting_checkpoint(v_operation,'accepted','started','sales_return_quarantine_resolution',p_resolution_id,jsonb_build_object('reason',btrim(p_reason)));
 perform set_config('app.skip_stock_adjustment_trigger','true',true);
 if v_resolution.disposition='released' then
  for v_mapping in select * from public.sales_return_quarantine_resolution_movements where resolution_id=p_resolution_id and tenant_id=v_tenant order by product_id,id loop
   select * into v_product from public.products where id=v_mapping.product_id and tenant_id=v_tenant for update;
   if coalesce(v_product.inventory_qty,0)<>coalesce(v_product.stock_quantity,0) then raise exception 'Product stock columns disagree; quarantine resolution void blocked';end if;
   v_before:=coalesce(v_product.inventory_qty,0);if v_before<v_mapping.quantity then raise exception 'Insufficient stock to void quarantine release';end if;v_after:=v_before-v_mapping.quantity;
   update public.products set inventory_qty=v_after,stock_quantity=v_after where id=v_product.id;
   v_reversal:=gen_random_uuid();
   insert into public.stock_movements(id,tenant_id,product_id,type,movement_type,quantity,reference,notes,date,created_at,updated_at,operation_id,source_document_type,source_document_id,created_by,stock_before,stock_after,reversal_of_id)
   values(v_reversal,v_tenant,v_product.id,'OUT','sales_return_quarantine_release_reversal',-v_mapping.quantity,'sales_return_quarantine_resolution:'||p_resolution_id||':void',v_description,now(),now(),now(),v_operation,'sales_return_quarantine_resolution',p_resolution_id,v_actor,v_before,v_after,v_mapping.stock_movement_id);
  end loop;
 end if;
 perform set_config('app.skip_stock_adjustment_trigger','',true);
 if v_resolution.journal_entry_id is not null then
  select total_debit into v_amount from public.journal_entries where id=v_resolution.journal_entry_id;
  v_entry:=gen_random_uuid();
  insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by,reversal_of_id,created_at,updated_at)
  values(v_entry,v_tenant,public.get_next_document_number(v_tenant,'journal_entry'),now(),v_description,'quarantine_resolution_void','sales_return_quarantine',p_resolution_id::text,'posted',v_amount,v_amount,v_operation,'sales_return_quarantine_resolution',p_resolution_id,v_actor,v_resolution.journal_entry_id,now(),now());
  for v_line in select * from public.journal_lines where entry_id=v_resolution.journal_entry_id loop
   insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)
   values(gen_random_uuid(),v_tenant,v_entry,v_line.account_id,v_line.account_code,v_line.account_name,v_description,v_line.credit_amount,v_line.debit_amount,now(),now());
  end loop;
 end if;
 update public.sales_return_quarantine_resolutions set status='voided',void_operation_id=v_operation,void_journal_entry_id=v_entry,void_idempotency_key=btrim(p_idempotency_key),voided_at=clock_timestamp(),voided_by=v_actor,void_reason=btrim(p_reason) where id=p_resolution_id;
 update public.sales_return_quarantine set status='held',resolution_id=null where id=v_resolution.quarantine_id;
 perform public.append_inventory_accounting_checkpoint(v_operation,'inventory_applied','completed','sales_return_quarantine_resolution',p_resolution_id,jsonb_build_object('reversal_count',(select count(*) from public.stock_movements where operation_id=v_operation)));
 perform public.append_inventory_accounting_checkpoint(v_operation,'journal_reversed','completed','journal_entry',v_entry,jsonb_build_object('reversal_of',v_resolution.journal_entry_id));
 perform public.append_inventory_accounting_checkpoint(v_operation,'invariants_verified','completed','sales_return_quarantine_resolution',p_resolution_id,jsonb_build_object('quarantine_status','held'));
 update public.inventory_accounting_operations set outcome='completed',completed_at=clock_timestamp(),after_snapshot=jsonb_build_object('resolution_id',p_resolution_id,'status','voided') where id=v_operation;
 perform public.append_inventory_accounting_checkpoint(v_operation,'completed','completed','sales_return_quarantine_resolution',p_resolution_id,jsonb_build_object('status','voided'));
 return jsonb_build_object('resolution_id',p_resolution_id,'operation_id',v_operation,'replayed',false);
exception when others then perform set_config('app.skip_stock_adjustment_trigger','',true);raise;
end;$$;

create or replace function public.guard_sales_return_void_with_resolved_quarantine()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if old.status='posted' and new.status='voided' and exists(
  select 1 from public.sales_return_quarantine quarantine
  join public.sales_return_lines line on line.id=quarantine.sales_return_line_id
  where line.sales_return_id=old.id and quarantine.status in('released','scrapped')
 ) then raise exception 'Void quarantine resolutions before voiding this sales return';end if;
 return new;
end;$$;
drop trigger if exists trg_guard_sales_return_resolved_quarantine_void on public.sales_returns;
create trigger trg_guard_sales_return_resolved_quarantine_void before update of status on public.sales_returns
for each row execute function public.guard_sales_return_void_with_resolved_quarantine();

revoke all on function public.resolve_sales_return_quarantine(uuid,text,timestamptz,text,text,text) from public,anon;
revoke all on function public.void_sales_return_quarantine_resolution(uuid,text,text) from public,anon;
grant execute on function public.resolve_sales_return_quarantine(uuid,text,timestamptz,text,text,text) to authenticated;
grant execute on function public.void_sales_return_quarantine_resolution(uuid,text,text) to authenticated;
commit;
