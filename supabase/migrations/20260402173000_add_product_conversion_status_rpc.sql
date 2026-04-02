create or replace function public.get_product_conversion_status(
  p_product_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_product public.products;
  v_conversion public.user_activity_log;
  v_restore public.user_activity_log;
  v_conversion_reference text;
  v_restored boolean := false;
  v_restored_inventory boolean := false;
begin
  if p_product_id is null then
    raise exception 'Product ID is required';
  end if;

  select *
    into v_product
    from public.products
   where id = p_product_id
     and tenant_id = public.user_tenant_id()
   limit 1;

  if not found then
    raise exception 'Product not found or not accessible';
  end if;

  select *
    into v_conversion
    from public.user_activity_log
   where tenant_id = v_product.tenant_id
     and action = 'product_conversion'
     and details->>'product_id' = v_product.id::text
   order by created_at desc
   limit 1;

  if not found then
    return jsonb_build_object(
      'product_id', v_product.id,
      'product_name', v_product.name,
      'has_conversion_history', false,
      'can_restore', false,
      'restored', false
    );
  end if;

  v_conversion_reference := v_conversion.details->>'conversion_reference';
  v_restored := coalesce((v_conversion.details->>'restored')::boolean, false);
  v_restored_inventory := coalesce((v_conversion.details->>'restored_inventory')::boolean, false);

  if v_conversion_reference is not null then
    select *
      into v_restore
      from public.user_activity_log
     where tenant_id = v_product.tenant_id
       and action = 'product_conversion_restore'
       and details->>'product_id' = v_product.id::text
       and details->>'source_conversion_reference' = v_conversion_reference
     order by created_at desc
     limit 1;
  end if;

  return jsonb_build_object(
    'product_id', v_product.id,
    'product_name', v_product.name,
    'has_conversion_history', true,
    'can_restore', not v_restored,
    'conversion_reference', v_conversion_reference,
    'conversion_reason', v_conversion.details->>'conversion_reason',
    'conversion_created_at', v_conversion.created_at,
    'converted_quantity', coalesce((v_conversion.details->>'converted_quantity')::integer, 0),
    'inventory_value', coalesce((v_conversion.details->>'inventory_value')::numeric, 0),
    'target_purchase_treatment', v_conversion.details->>'target_purchase_treatment',
    'target_product_type', v_conversion.details->>'target_product_type',
    'journal_entry_id', v_conversion.details->>'journal_entry_id',
    'original_state', coalesce(v_conversion.details->'original_state', '{}'::jsonb),
    'converted_state', coalesce(v_conversion.details->'converted_state', '{}'::jsonb),
    'restored', v_restored,
    'restored_at', coalesce(v_conversion.details->>'restored_at', to_char(v_restore.created_at, 'YYYY-MM-DD"T"HH24:MI:SSOF')),
    'restored_inventory', coalesce(
      nullif(v_conversion.details->>'restored_inventory', '')::boolean,
      nullif(v_restore.details->>'restored_inventory', '')::boolean,
      v_restored_inventory,
      false
    ),
    'restore_reference', coalesce(v_conversion.details->>'restore_reference', v_restore.details->>'restore_reference'),
    'restore_reason', coalesce(v_conversion.details->>'restore_reason', v_restore.details->>'restore_reason'),
    'restore_journal_entry_id', coalesce(v_conversion.details->>'restore_journal_entry_id', v_restore.details->>'journal_entry_id')
  );
end;
$$;

grant execute on function public.get_product_conversion_status(uuid) to authenticated;