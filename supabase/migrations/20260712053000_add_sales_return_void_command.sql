-- Deployment status: DEPLOYED 2026-07-11. Sales-return control remains disabled.
begin;
create or replace function public.void_sales_return(p_sales_return_id uuid,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_return public.sales_returns%rowtype;
 v_operation uuid:=gen_random_uuid();v_map record;v_product public.products%rowtype;v_before integer;v_after integer;v_reversal uuid;
begin
 if v_actor is null or v_tenant is null then raise exception 'Authenticated employee tenant is required';end if;
 if nullif(btrim(p_reason),'') is null or nullif(btrim(p_idempotency_key),'') is null then raise exception 'Sales return void reason and idempotency key are required';end if;
 select * into v_return from public.sales_returns where id=p_sales_return_id and tenant_id=v_tenant for update;
 if not found then raise exception 'Sales return not found for current tenant';end if;
 if v_return.status='voided' then if v_return.void_idempotency_key=btrim(p_idempotency_key) then return jsonb_build_object('sales_return_id',v_return.id,'operation_id',v_return.void_operation_id,'replayed',true);end if;raise exception 'Sales return is already voided';end if;
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,old_status,new_status,context)
 values(v_operation,v_tenant,format('sales_return_void:%s:%s',p_sales_return_id,btrim(p_idempotency_key)),'sales_return','void','sales_return',p_sales_return_id,v_actor,'database_command','posted','voided',jsonb_build_object('reason',btrim(p_reason)));
 perform public.append_inventory_accounting_checkpoint(v_operation,'accepted','started','sales_return',p_sales_return_id,jsonb_build_object('reason',btrim(p_reason)));
 perform set_config('app.skip_stock_adjustment_trigger','true',true);
 for v_map in select mapping.*,line.disposition from public.sales_return_line_movements mapping join public.sales_return_lines line on line.id=mapping.sales_return_line_id where mapping.sales_return_id=p_sales_return_id and mapping.tenant_id=v_tenant order by mapping.product_id,mapping.id loop
  if v_map.return_stock_movement_id is not null then
   select * into v_product from public.products where id=v_map.product_id and tenant_id=v_tenant for update;
   if not found then raise exception 'Sales return product not found';end if;
   if coalesce(v_product.inventory_qty,0)<>coalesce(v_product.stock_quantity,0) then raise exception 'Product stock columns disagree; sales return void blocked';end if;
   v_before:=coalesce(v_product.inventory_qty,0);if v_before<v_map.quantity then raise exception 'Insufficient stock to void sales return';end if;v_after:=v_before-v_map.quantity;
   update public.products set inventory_qty=v_after,stock_quantity=v_after where id=v_product.id;
   v_reversal:=gen_random_uuid();insert into public.stock_movements(id,tenant_id,product_id,type,movement_type,quantity,reference,notes,date,created_at,updated_at,operation_id,source_document_type,source_document_id,created_by,stock_before,stock_after,reversal_of_id)
   values(v_reversal,v_tenant,v_product.id,'OUT','sales_return_reversal',-v_map.quantity,'sales_return:'||p_sales_return_id||':void',format('Anulación devolución %s',v_return.return_number),now(),now(),now(),v_operation,'sales_return',p_sales_return_id,v_actor,v_before,v_after,v_map.return_stock_movement_id);
  end if;
 end loop;
 update public.sales_return_quarantine set status='voided' where sales_return_line_id in(select id from public.sales_return_lines where sales_return_id=p_sales_return_id) and status='held';
 perform set_config('app.skip_stock_adjustment_trigger','',true);
 update public.sales_returns set status='voided',void_operation_id=v_operation,void_idempotency_key=btrim(p_idempotency_key),voided_at=clock_timestamp(),voided_by=v_actor,void_reason=btrim(p_reason) where id=p_sales_return_id;
 perform public.append_inventory_accounting_checkpoint(v_operation,'inventory_applied','completed','sales_return',p_sales_return_id,jsonb_build_object('reversal_count',(select count(*) from public.stock_movements where operation_id=v_operation)));
 perform public.append_inventory_accounting_checkpoint(v_operation,'accounting_planned','warning','sales_return',p_sales_return_id,jsonb_build_object('journal_posted',false,'reason','physical_return_void_only'));
 perform public.append_inventory_accounting_checkpoint(v_operation,'invariants_verified','completed','sales_return',p_sales_return_id,jsonb_build_object('dual_stock_columns_match',true));
 update public.inventory_accounting_operations set outcome='completed',completed_at=clock_timestamp(),after_snapshot=jsonb_build_object('status','voided') where id=v_operation;
 perform public.append_inventory_accounting_checkpoint(v_operation,'completed','completed','sales_return',p_sales_return_id,jsonb_build_object('status','voided'));
 return jsonb_build_object('sales_return_id',p_sales_return_id,'operation_id',v_operation,'replayed',false);
exception when others then perform set_config('app.skip_stock_adjustment_trigger','',true);raise;
end;$$;
revoke all on function public.void_sales_return(uuid,text,text) from public,anon;grant execute on function public.void_sales_return(uuid,text,text) to authenticated;
commit;
