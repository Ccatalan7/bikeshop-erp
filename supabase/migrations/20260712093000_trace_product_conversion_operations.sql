-- Deployment status: DEPLOYED 2026-07-11. Adds common lineage to existing conversion commands.
begin;

create or replace function public.trace_product_conversion_activity()
returns trigger language plpgsql security definer set search_path=public as $$
declare
 v_operation uuid:=gen_random_uuid();v_product_id uuid;v_reference text;v_source_reference text;v_journal_id uuid;v_source_journal_id uuid;v_source_movement_id uuid;v_action text;v_movement_count integer;v_stock_before jsonb;v_stock_after jsonb;
begin
 if new.action not in('product_conversion','product_conversion_restore')then return new;end if;
 v_product_id:=nullif(new.details->>'product_id','')::uuid;
 if v_product_id is null then raise exception 'Product conversion trace requires product_id';end if;
 if new.action='product_conversion'then
  v_reference:=nullif(new.details->>'conversion_reference','');v_journal_id:=nullif(new.details->>'journal_entry_id','')::uuid;v_action:='convert';
  v_stock_before:=new.details->'original_state';v_stock_after:=new.details->'converted_state';
 else
  v_reference:=nullif(new.details->>'restore_reference','');v_source_reference:=nullif(new.details->>'source_conversion_reference','');v_journal_id:=nullif(new.details->>'journal_entry_id','')::uuid;v_action:='restore';
  v_stock_before:=null;v_stock_after:=new.details->'product_state_after_restore';
  select nullif(activity.details->>'journal_entry_id','')::uuid into v_source_journal_id from public.user_activity_log activity where activity.tenant_id=new.tenant_id and activity.action='product_conversion'and activity.details->>'conversion_reference'=v_source_reference order by activity.created_at desc limit 1;
  select movement.id into v_source_movement_id from public.stock_movements movement where movement.tenant_id=new.tenant_id and movement.product_id=v_product_id and movement.reference=v_source_reference order by movement.created_at desc limit 1;
 end if;
 if v_reference is null then raise exception 'Product conversion trace requires a durable reference';end if;
 insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,before_snapshot,after_snapshot,context)
 values(v_operation,new.tenant_id,'product_conversion:'||v_reference,'product_conversion',v_action,'product',v_product_id,new.user_id,'database_command',v_stock_before,v_stock_after,jsonb_build_object('activity_log_id',new.id,'reference',v_reference,'source_conversion_reference',new.details->>'source_conversion_reference'));
 perform public.append_inventory_accounting_checkpoint(v_operation,'accepted','completed','user_activity_log',new.id,jsonb_build_object('action',new.action,'reference',v_reference));
 update public.stock_adjustments set operation_id=v_operation where tenant_id=new.tenant_id and product_id=v_product_id and reference=v_reference and operation_id is null;
 update public.stock_movements set operation_id=v_operation,source_document_type='product',source_document_id=v_product_id,created_by=coalesce(created_by,new.user_id)
 where tenant_id=new.tenant_id and product_id=v_product_id and reference=v_reference and operation_id is null;
 get diagnostics v_movement_count=row_count;
 if v_action='restore'and v_source_movement_id is not null then update public.stock_movements set reversal_of_id=v_source_movement_id where operation_id=v_operation;end if;
 if v_journal_id is not null then
  update public.journal_entries set operation_id=v_operation,source_document_type='product',source_document_id=v_product_id,created_by=coalesce(created_by,new.user_id)
  where id=v_journal_id and tenant_id=new.tenant_id;
  if v_action='restore'and v_source_journal_id is not null then update public.journal_entries set reversal_of_id=v_source_journal_id where id=v_journal_id and tenant_id=new.tenant_id;end if;
 end if;
 perform public.append_inventory_accounting_checkpoint(v_operation,'inventory_applied','completed','product',v_product_id,jsonb_build_object('movement_count',v_movement_count,'reference',v_reference));
 if v_journal_id is not null then perform public.append_inventory_accounting_checkpoint(v_operation,'journal_posted','completed','journal_entry',v_journal_id,jsonb_build_object('balanced',true));
 else perform public.append_inventory_accounting_checkpoint(v_operation,'accounting_planned','completed','product',v_product_id,jsonb_build_object('journal_required',false));end if;
 perform public.complete_inventory_accounting_operation(v_operation,new.tenant_id,jsonb_build_object('action',v_action,'product_id',v_product_id,'reference',v_reference));
 return new;
end;$$;

drop trigger if exists trg_trace_product_conversion_activity on public.user_activity_log;
create trigger trg_trace_product_conversion_activity after insert on public.user_activity_log
for each row when(new.action in('product_conversion','product_conversion_restore'))
execute function public.trace_product_conversion_activity();
commit;
