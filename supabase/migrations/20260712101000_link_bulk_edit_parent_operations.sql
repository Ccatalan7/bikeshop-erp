-- Deployment status: DEPLOYED 2026-07-11. Makes per-row bulk changes one navigable batch trace.
begin;
alter table public.product_bulk_edit_history add column if not exists operation_id uuid references public.inventory_accounting_operations(id);

create or replace function public.link_product_bulk_edit_operations(p_history_id uuid,p_child_operation_ids uuid[]default'{}')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_tenant uuid:=public.user_tenant_id();v_actor uuid:=auth.uid();v_history public.product_bulk_edit_history%rowtype;v_operation uuid:=gen_random_uuid();v_valid_children uuid[];v_failed integer;
begin
 if v_actor is null or v_tenant is null then raise exception 'Authenticated employee tenant is required';end if;
 select * into v_history from public.product_bulk_edit_history where id=p_history_id and tenant_id=v_tenant for update;
 if not found then raise exception 'Bulk edit history not found for current tenant';end if;
 if v_history.operation_id is not null then return jsonb_build_object('operation_id',v_history.operation_id,'replayed',true);end if;
 select coalesce(array_agg(id order by id),'{}'::uuid[])into v_valid_children from public.inventory_accounting_operations where tenant_id=v_tenant and id=any(coalesce(p_child_operation_ids,'{}'::uuid[]));
 if cardinality(v_valid_children)<>cardinality(coalesce(p_child_operation_ids,'{}'::uuid[]))then raise exception 'Bulk edit contains an operation outside the current tenant';end if;
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,context)
 values(v_operation,v_tenant,'product_bulk_edit:'||p_history_id,'mass_edit_panel','batch_update','product_bulk_edit',p_history_id,v_actor,'database_command',jsonb_build_object('operation',v_history.operation,'scope_source',v_history.scope_source,'status',v_history.status,'child_operation_ids',to_jsonb(v_valid_children),'partial_success_policy',true));
 perform public.append_inventory_accounting_checkpoint(v_operation,'accepted','completed','product_bulk_edit_history',p_history_id,jsonb_build_object('enabled_products',v_history.enabled_product_count,'scope_products',v_history.scope_product_count));
 update public.inventory_accounting_operations child set context=child.context||jsonb_build_object('parent_operation_id',v_operation,'bulk_edit_history_id',p_history_id)where child.tenant_id=v_tenant and child.id=any(v_valid_children);
 select count(*)::integer into v_failed from public.inventory_accounting_operations where id=any(v_valid_children)and outcome<>'completed';
 perform public.append_inventory_accounting_checkpoint(v_operation,'inventory_applied',case when v_failed=0 then'completed'else'warning'end,'product_bulk_edit_history',p_history_id,jsonb_build_object('child_operation_count',cardinality(v_valid_children),'failed_child_operations',v_failed,'succeeded_products',v_history.succeeded_product_count,'failed_products',v_history.failed_product_count));
 perform public.append_inventory_accounting_checkpoint(v_operation,'invariants_verified','completed','product_bulk_edit_history',p_history_id,jsonb_build_object('all_posted_children_completed',v_failed=0,'partial_success_policy',true));
 update public.inventory_accounting_operations set outcome='completed',completed_at=clock_timestamp(),after_snapshot=jsonb_build_object('history_status',v_history.status,'succeeded',v_history.succeeded_product_count,'skipped',v_history.skipped_product_count,'failed',v_history.failed_product_count)where id=v_operation;
 update public.product_bulk_edit_history set operation_id=v_operation where id=p_history_id;
 perform public.append_inventory_accounting_checkpoint(v_operation,'completed','completed','product_bulk_edit_history',p_history_id,jsonb_build_object('child_operation_count',cardinality(v_valid_children)));
 return jsonb_build_object('operation_id',v_operation,'child_operation_count',cardinality(v_valid_children),'replayed',false);
end;$$;
revoke all on function public.link_product_bulk_edit_operations(uuid,uuid[])from public,anon;grant execute on function public.link_product_bulk_edit_operations(uuid,uuid[])to authenticated;
commit;
