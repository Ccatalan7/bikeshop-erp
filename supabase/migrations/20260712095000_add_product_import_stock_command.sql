-- Deployment status: DEPLOYED 2026-07-11. Adds durable import identity and retry safety.
begin;
create table if not exists public.product_import_stock_commands(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id)on delete cascade,
 idempotency_key text not null,product_id uuid not null references public.products(id)on delete restrict,target_quantity integer not null check(target_quantity>=0),
 import_reference text not null,status text not null check(status in('completed','no_change')),operation_id uuid references public.inventory_accounting_operations(id),
 stock_adjustment_id uuid references public.stock_adjustments(id),created_by uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,idempotency_key)
);
alter table public.product_import_stock_commands enable row level security;
drop policy if exists product_import_stock_commands_select on public.product_import_stock_commands;
create policy product_import_stock_commands_select on public.product_import_stock_commands for select to authenticated using(tenant_id=public.user_tenant_id());
revoke insert,update,delete on public.product_import_stock_commands from public,anon,authenticated;grant select on public.product_import_stock_commands to authenticated;

create or replace function public.apply_product_import_stock(
 p_product_id uuid,p_target_quantity integer,p_import_reference text,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare
 v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_product public.products%rowtype;v_existing public.product_import_stock_commands%rowtype;
 v_delta integer;v_result jsonb;v_operation uuid;v_adjustment uuid;v_command uuid:=gen_random_uuid();v_status text;
begin
 if v_actor is null or v_tenant is null then raise exception 'Authenticated employee tenant is required';end if;
 if p_target_quantity is null or p_target_quantity<0 then raise exception 'Import target stock must be zero or positive';end if;
 if nullif(btrim(p_import_reference),'')is null or nullif(btrim(p_idempotency_key),'')is null then raise exception 'Import reference and idempotency key are required';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_tenant::text||':product_import:'||btrim(p_idempotency_key),0));
 select * into v_existing from public.product_import_stock_commands where tenant_id=v_tenant and idempotency_key=btrim(p_idempotency_key);
 if found then
  if v_existing.product_id<>p_product_id or v_existing.target_quantity<>p_target_quantity then raise exception 'Import key was already used with different stock content' using errcode='integrity_constraint_violation';end if;
  return jsonb_build_object('command_id',v_existing.id,'operation_id',v_existing.operation_id,'adjustment_id',v_existing.stock_adjustment_id,'status',v_existing.status,'replayed',true);
 end if;
 select * into v_product from public.products where id=p_product_id and tenant_id=v_tenant for update;
 if not found then raise exception 'Import product not found for current tenant';end if;
 if coalesce(v_product.product_type,'product')='service'or not coalesce(v_product.track_stock,true)or coalesce(v_product.purchase_treatment,'inventory')='workshop_consumable'then
  if p_target_quantity<>0 then raise exception 'Imported non-stock product cannot receive stock';end if;
 end if;
 if coalesce(v_product.inventory_qty,0)<>coalesce(v_product.stock_quantity,0)then raise exception 'Product stock columns disagree; import blocked';end if;
 v_delta:=p_target_quantity-coalesce(v_product.inventory_qty,0);
 if v_delta=0 then
  insert into public.product_import_stock_commands(id,tenant_id,idempotency_key,product_id,target_quantity,import_reference,status,created_by)
  values(v_command,v_tenant,btrim(p_idempotency_key),p_product_id,p_target_quantity,btrim(p_import_reference),'no_change',v_actor);
  return jsonb_build_object('command_id',v_command,'status','no_change','replayed',false);
 end if;
 perform set_config('app.inventory_idempotency_key','product_import:'||btrim(p_idempotency_key),true);
 v_result:=public.apply_inventory_stock_adjustment(p_product_id,abs(v_delta),case when v_delta>0 then'IN'else'OUT'end,'count',format('Importación %s',btrim(p_import_reference)),now(),'manual_service');
 v_operation:=(v_result->>'operation_id')::uuid;v_adjustment:=(v_result->>'adjustment_id')::uuid;v_status:='completed';
 update public.inventory_accounting_operations set source_channel='product_import',context=context||jsonb_build_object('adjustment_origin','product_import','import_reference',btrim(p_import_reference),'import_command_id',v_command)where id=v_operation and tenant_id=v_tenant;
 update public.stock_adjustments set adjustment_origin='product_import',reason=format('Importación: %s',btrim(p_import_reference))where id=v_adjustment and tenant_id=v_tenant;
 update public.stock_movements set notes=format('Importación: %s',btrim(p_import_reference))where operation_id=v_operation and tenant_id=v_tenant;
 perform public.append_inventory_accounting_checkpoint(v_operation,'completed','completed','stock_adjustment',v_adjustment,jsonb_build_object('source_reclassified','product_import','import_reference',btrim(p_import_reference),'import_command_id',v_command));
 insert into public.product_import_stock_commands(id,tenant_id,idempotency_key,product_id,target_quantity,import_reference,status,operation_id,stock_adjustment_id,created_by)
 values(v_command,v_tenant,btrim(p_idempotency_key),p_product_id,p_target_quantity,btrim(p_import_reference),v_status,v_operation,v_adjustment,v_actor);
 return v_result||jsonb_build_object('command_id',v_command,'status',v_status,'adjustment_origin','product_import','replayed',false);
end;$$;
revoke all on function public.apply_product_import_stock(uuid,integer,text,text)from public,anon;grant execute on function public.apply_product_import_stock(uuid,integer,text,text)to authenticated;
commit;
