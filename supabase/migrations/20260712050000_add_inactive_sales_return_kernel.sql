-- Deployment status: DEPLOYED 2026-07-11. No tenant was activated.
-- Physical customer returns are separate from sales credit notes.
begin;

create table if not exists public.sales_return_control_settings(
 tenant_id uuid primary key references public.tenants(id) on delete cascade,
 control_mode text not null default 'disabled' check(control_mode in('disabled','shadow','enforce')),
 activated_at timestamptz,activated_by uuid references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.sales_returns(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,return_number text not null,
 status text not null default 'posted' check(status in('posted','voided')),returned_at timestamptz not null,
 reason text not null,notes text,idempotency_key text not null,operation_id uuid not null,created_by uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 void_operation_id uuid,void_idempotency_key text,voided_at timestamptz,voided_by uuid references auth.users(id),void_reason text,
 unique(tenant_id,return_number),unique(tenant_id,idempotency_key),unique(tenant_id,id),
 foreign key(tenant_id,operation_id) references public.inventory_accounting_operations(tenant_id,id) on delete restrict);
create unique index if not exists uq_sales_returns_void_key on public.sales_returns(tenant_id,void_idempotency_key) where void_idempotency_key is not null;
create table if not exists public.sales_return_lines(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 sales_return_id uuid not null,sales_invoice_id uuid not null references public.sales_invoices(id) on delete restrict,
 source_line_key text not null,source_line_index integer not null check(source_line_index>=0),product_id uuid references public.products(id) on delete restrict,
 product_name text not null,product_sku text,returned_quantity integer not null check(returned_quantity>0),previously_returned_quantity integer not null check(previously_returned_quantity>=0),
 sold_quantity integer not null check(sold_quantity>=0),disposition text not null check(disposition in('restock','quarantine','scrap')),
 line_snapshot jsonb not null,created_at timestamptz not null default clock_timestamp(),unique(tenant_id,sales_return_id,source_line_key),
 foreign key(tenant_id,sales_return_id) references public.sales_returns(tenant_id,id) on delete restrict,
 check(returned_quantity+previously_returned_quantity<=sold_quantity));
create table if not exists public.sales_return_line_movements(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 sales_return_id uuid not null,sales_return_line_id uuid not null references public.sales_return_lines(id) on delete restrict,
 product_id uuid not null references public.products(id) on delete restrict,original_sale_movement_id uuid not null references public.stock_movements(id) on delete restrict,
 return_stock_movement_id uuid references public.stock_movements(id) on delete restrict,movement_role text not null check(movement_role in('direct','set_component')),
 quantity integer not null check(quantity>0),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,sales_return_line_id,original_sale_movement_id),foreign key(tenant_id,sales_return_id) references public.sales_returns(tenant_id,id) on delete restrict);
create table if not exists public.sales_return_quarantine(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 sales_return_line_id uuid not null unique references public.sales_return_lines(id) on delete restrict,product_id uuid references public.products(id) on delete restrict,
 quantity integer not null check(quantity>0),status text not null default 'held' check(status in('held','released','scrapped','voided')),created_at timestamptz not null default clock_timestamp());
create index if not exists idx_sales_returns_invoice on public.sales_returns(tenant_id,sales_invoice_id,created_at desc);
create index if not exists idx_sales_return_lines_source on public.sales_return_lines(tenant_id,sales_invoice_id,source_line_key);

alter table public.sales_return_control_settings enable row level security;alter table public.sales_returns enable row level security;
alter table public.sales_return_lines enable row level security;alter table public.sales_return_line_movements enable row level security;alter table public.sales_return_quarantine enable row level security;
drop policy if exists sales_return_settings_select on public.sales_return_control_settings;create policy sales_return_settings_select on public.sales_return_control_settings for select to authenticated using(tenant_id=public.user_tenant_id());
drop policy if exists sales_returns_select on public.sales_returns;create policy sales_returns_select on public.sales_returns for select to authenticated using(tenant_id=public.user_tenant_id());
drop policy if exists sales_return_lines_select on public.sales_return_lines;create policy sales_return_lines_select on public.sales_return_lines for select to authenticated using(tenant_id=public.user_tenant_id());
drop policy if exists sales_return_movements_select on public.sales_return_line_movements;create policy sales_return_movements_select on public.sales_return_line_movements for select to authenticated using(tenant_id=public.user_tenant_id());
drop policy if exists sales_return_quarantine_select on public.sales_return_quarantine;create policy sales_return_quarantine_select on public.sales_return_quarantine for select to authenticated using(tenant_id=public.user_tenant_id());
revoke insert,update,delete on public.sales_return_control_settings,public.sales_returns,public.sales_return_lines,public.sales_return_line_movements,public.sales_return_quarantine from public,anon,authenticated;
grant select on public.sales_return_control_settings,public.sales_returns,public.sales_return_lines,public.sales_return_line_movements,public.sales_return_quarantine to authenticated;

create or replace function public.create_sales_return(p_sales_invoice_id uuid,p_lines jsonb,p_returned_at timestamptz,p_reason text,p_notes text default null,p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_mode text:='disabled';v_invoice public.sales_invoices%rowtype;v_existing public.sales_returns%rowtype;
 v_return uuid:=gen_random_uuid();v_operation uuid:=gen_random_uuid();v_number text;v_request jsonb;v_item jsonb;v_idx integer;v_key text;v_qty integer;v_sold integer;v_previous integer;v_disposition text;
 v_product public.products%rowtype;v_line uuid;v_target record;v_target_qty integer;v_needed integer;v_source record;v_capacity integer;v_alloc integer;v_before integer;v_after integer;v_movement uuid;
begin
 if v_actor is null or v_tenant is null then raise exception 'Authenticated employee tenant is required';end if;
 if p_returned_at is null or nullif(btrim(p_reason),'') is null or nullif(btrim(p_idempotency_key),'') is null then raise exception 'Sales return date, reason, and idempotency key are required';end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'Sales return requires at least one line';end if;
 select * into v_existing from public.sales_returns where tenant_id=v_tenant and idempotency_key=btrim(p_idempotency_key);
 if found then if v_existing.sales_invoice_id<>p_sales_invoice_id then raise exception 'Idempotency key belongs to a different sales invoice';end if;return jsonb_build_object('sales_return_id',v_existing.id,'operation_id',v_existing.operation_id,'return_number',v_existing.return_number,'replayed',true);end if;
 select coalesce(setting.control_mode,'disabled') into v_mode from(select 1)seed left join public.sales_return_control_settings setting on setting.tenant_id=v_tenant;
 if v_mode<>'enforce' then raise exception 'Sales return workflow is not active for this tenant';end if;
 select * into v_invoice from public.sales_invoices where id=p_sales_invoice_id and tenant_id=v_tenant for update;
 if not found then raise exception 'Sales invoice not found for current tenant';end if;if lower(v_invoice.status) not in('confirmed','paid','overdue','sent','enviado','enviada','emitido','emitida','issued') then raise exception 'Sales invoice must be posted before return';end if;
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,old_status,new_status,context)
 values(v_operation,v_tenant,format('sales_return:%s:%s',p_sales_invoice_id,btrim(p_idempotency_key)),'sales_return','create','sales_return',v_return,v_actor,'database_command',v_invoice.status,v_invoice.status,jsonb_build_object('sales_invoice_id',v_invoice.id,'financial_effect','none_pending_sales_credit_note'));
 perform public.append_inventory_accounting_checkpoint(v_operation,'accepted','started','sales_invoice',v_invoice.id,jsonb_build_object('line_count',jsonb_array_length(p_lines)));
 v_number:=public.get_next_document_number(v_tenant,'sales_return','DVC');
 insert into public.sales_returns(id,tenant_id,sales_invoice_id,return_number,returned_at,reason,notes,idempotency_key,operation_id,created_by)
 values(v_return,v_tenant,v_invoice.id,v_number,p_returned_at,btrim(p_reason),nullif(btrim(p_notes),''),btrim(p_idempotency_key),v_operation,v_actor);
 perform set_config('app.skip_stock_adjustment_trigger','true',true);
 for v_request in select value from jsonb_array_elements(p_lines) loop
  v_idx:=nullif(v_request->>'line_index','')::integer;if v_idx is null or v_idx<0 or v_idx>=jsonb_array_length(v_invoice.items) then raise exception 'Invalid sales invoice line index';end if;
  v_item:=v_invoice.items->v_idx;v_key:=coalesce(nullif(v_item->>'line_id',''),nullif(v_item->>'id',''),md5(v_invoice.id::text||':'||v_idx::text||':'||coalesce(v_item->>'product_id','')));
  if exists(select 1 from public.sales_return_lines where sales_return_id=v_return and source_line_key=v_key) then raise exception 'Duplicate sales return line';end if;
  v_sold:=coalesce(nullif(v_item->>'quantity','')::numeric,0)::integer;if v_sold<=0 or v_sold::numeric<>coalesce(nullif(v_item->>'quantity','')::numeric,0) then raise exception 'Sales return source quantity must be positive whole units';end if;
  v_qty:=coalesce(nullif(v_request->>'returned_quantity','')::integer,0);if v_qty<=0 then raise exception 'Sales return quantity must be positive';end if;
  select coalesce(sum(line.returned_quantity),0) into v_previous from public.sales_return_lines line join public.sales_returns header on header.id=line.sales_return_id where line.sales_invoice_id=v_invoice.id and line.source_line_key=v_key and header.status='posted';
  if v_previous+v_qty>v_sold then raise exception 'Sales return exceeds remaining sold quantity';end if;
  v_disposition:=coalesce(nullif(v_request->>'disposition',''),'restock');if v_disposition not in('restock','quarantine','scrap') then raise exception 'Invalid sales return disposition';end if;
  select * into v_product from public.products where id=nullif(v_item->>'product_id','')::uuid and tenant_id=v_tenant;if not found then raise exception 'Sales return product not found';end if;
  insert into public.sales_return_lines(tenant_id,sales_return_id,sales_invoice_id,source_line_key,source_line_index,product_id,product_name,product_sku,returned_quantity,previously_returned_quantity,sold_quantity,disposition,line_snapshot)
  values(v_tenant,v_return,v_invoice.id,v_key,v_idx,v_product.id,coalesce(v_item->>'product_name',v_product.name),v_item->>'product_sku',v_qty,v_previous,v_sold,v_disposition,v_item) returning id into v_line;
  for v_target in
   select v_product.id product_id,v_qty quantity,'direct' role where not coalesce(v_product.is_set,false)
   union all select component.component_product_id,v_qty*component.quantity_in_set,'set_component' from public.product_set_components component where component.set_product_id=v_product.id and component.tenant_id=v_tenant and coalesce(v_product.is_set,false)
  loop
   v_needed:=v_target.quantity;
   for v_source in
    select movement.id,abs(movement.quantity)::integer sold_qty,
      abs(movement.quantity)::integer-coalesce((select sum(mapping.quantity) from public.sales_return_line_movements mapping join public.sales_returns sr on sr.id=mapping.sales_return_id where mapping.original_sale_movement_id=movement.id and sr.status='posted'),0)::integer capacity
    from public.stock_movements movement
    where movement.tenant_id=v_tenant and movement.product_id=v_target.product_id and movement.quantity<0
      and (movement.source_document_id=v_invoice.id or movement.reference='sales_invoice:'||v_invoice.id::text)
      and not exists(select 1 from public.stock_movements reversal where reversal.reversal_of_id=movement.id and reversal.movement_type='sales_invoice_reversal')
    order by movement.date,movement.id for update
   loop
    v_capacity:=greatest(v_source.capacity,0);if v_capacity=0 then continue;end if;v_alloc:=least(v_needed,v_capacity);
    v_movement:=null;
    if v_disposition='restock' then
     select * into v_product from public.products where id=v_target.product_id and tenant_id=v_tenant for update;
     if coalesce(v_product.inventory_qty,0)<>coalesce(v_product.stock_quantity,0) then raise exception 'Product stock columns disagree; sales return blocked';end if;
     v_before:=coalesce(v_product.inventory_qty,0);v_after:=v_before+v_alloc;update public.products set inventory_qty=v_after,stock_quantity=v_after where id=v_product.id;
     v_movement:=gen_random_uuid();insert into public.stock_movements(id,tenant_id,product_id,type,movement_type,quantity,reference,notes,date,created_at,updated_at,operation_id,source_document_type,source_document_id,created_by,stock_before,stock_after,reversal_of_id)
     values(v_movement,v_tenant,v_product.id,'IN','sales_return_restock',v_alloc,'sales_return:'||v_return,format('Reposición devolución %s',v_number),p_returned_at,now(),now(),v_operation,'sales_return',v_return,v_actor,v_before,v_after,v_source.id);
    end if;
    insert into public.sales_return_line_movements(tenant_id,sales_return_id,sales_return_line_id,product_id,original_sale_movement_id,return_stock_movement_id,movement_role,quantity)
    values(v_tenant,v_return,v_line,v_target.product_id,v_source.id,v_movement,v_target.role,v_alloc);
    v_needed:=v_needed-v_alloc;exit when v_needed=0;
   end loop;
   if v_needed>0 then raise exception 'Sales return cannot be matched to active invoice stock movements';end if;
  end loop;
  if v_disposition='quarantine' then
   insert into public.sales_return_quarantine(tenant_id,sales_return_line_id,product_id,quantity)
   select v_tenant,v_line,line.product_id,v_qty from public.sales_return_lines line where line.id=v_line;
  end if;
 end loop;
 perform set_config('app.skip_stock_adjustment_trigger','',true);
 perform public.append_inventory_accounting_checkpoint(v_operation,'inventory_applied','completed','sales_return',v_return,jsonb_build_object('movement_count',(select count(*) from public.sales_return_line_movements where sales_return_id=v_return and return_stock_movement_id is not null)));
 perform public.append_inventory_accounting_checkpoint(v_operation,'accounting_planned','warning','sales_return',v_return,jsonb_build_object('journal_posted',false,'reason','awaiting_explicit_sales_credit_note'));
 perform public.append_inventory_accounting_checkpoint(v_operation,'invariants_verified','completed','sales_return',v_return,jsonb_build_object('invoice_and_payments_unchanged',true));
 update public.inventory_accounting_operations set outcome='completed',completed_at=clock_timestamp(),after_snapshot=jsonb_build_object('sales_return_id',v_return,'return_number',v_number) where id=v_operation;
 perform public.append_inventory_accounting_checkpoint(v_operation,'completed','completed','sales_return',v_return,jsonb_build_object('return_number',v_number));
 return jsonb_build_object('sales_return_id',v_return,'operation_id',v_operation,'return_number',v_number,'replayed',false);
exception when others then perform set_config('app.skip_stock_adjustment_trigger','',true);raise;
end;$$;

revoke all on function public.create_sales_return(uuid,jsonb,timestamptz,text,text,text) from public,anon;
grant execute on function public.create_sales_return(uuid,jsonb,timestamptz,text,text,text) to authenticated;
commit;
