create or replace function public.get_stock_adjustment_details(
  p_adjustment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_adjustment record;
  v_entry record;
  v_counterpart_account_code text;
  v_counterpart_account_name text;
  v_counterpart_debit numeric;
  v_counterpart_credit numeric;
begin
  select
    sa.id,
    sa.tenant_id,
    sa.product_id,
    sa.adjustment_type,
    sa.quantity,
    sa.stock_before,
    sa.stock_after,
    sa.reason,
    sa.reference,
    sa.adjustment_date,
    sa.created_at,
    sa.created_by,
    p.name as product_name,
    p.sku as product_sku,
    p.cost as unit_cost,
    au.email as created_by_email,
    abs(sa.quantity) * greatest(coalesce(p.cost, 0), 0) as inventory_value
  into v_adjustment
  from public.stock_adjustments sa
  join public.products p
    on p.id = sa.product_id
   and p.tenant_id = sa.tenant_id
  left join auth.users au
    on au.id = sa.created_by
  where sa.id = p_adjustment_id
    and sa.tenant_id = public.user_tenant_id();

  if not found then
    raise exception 'Stock adjustment % not found for current tenant', p_adjustment_id
      using errcode = 'foreign_key_violation';
  end if;

  select
    je.id,
    je.entry_number,
    je.entry_date,
    je.description,
    je.total_debit,
    je.total_credit
  into v_entry
  from public.journal_entries je
  where je.tenant_id = v_adjustment.tenant_id
    and je.source_module = 'stock_adjustment'
    and je.source_reference = v_adjustment.id::text
  order by je.created_at desc
  limit 1;

  if v_entry.id is not null then
    select
      jl.account_code,
      jl.account_name,
      jl.debit_amount,
      jl.credit_amount
    into v_counterpart_account_code,
         v_counterpart_account_name,
         v_counterpart_debit,
         v_counterpart_credit
    from public.journal_lines jl
    where jl.entry_id = v_entry.id
      and jl.account_code <> '1105'
    order by greatest(jl.debit_amount, jl.credit_amount) desc, jl.created_at asc
    limit 1;
  end if;

  return jsonb_build_object(
    'id', v_adjustment.id,
    'product_id', v_adjustment.product_id,
    'product_name', v_adjustment.product_name,
    'product_sku', v_adjustment.product_sku,
    'adjustment_type', v_adjustment.adjustment_type,
    'reference_number', v_adjustment.reference,
    'quantity', v_adjustment.quantity,
    'stock_before', v_adjustment.stock_before,
    'stock_after', v_adjustment.stock_after,
    'reason', v_adjustment.reason,
    'adjustment_date', v_adjustment.adjustment_date,
    'created_at', v_adjustment.created_at,
    'created_by', v_adjustment.created_by,
    'created_by_email', v_adjustment.created_by_email,
    'unit_cost', v_adjustment.unit_cost,
    'inventory_value', v_adjustment.inventory_value,
    'journal_entry_id', v_entry.id,
    'journal_entry_number', v_entry.entry_number,
    'journal_entry_date', v_entry.entry_date,
    'journal_entry_description', v_entry.description,
    'counterpart_account_code', v_counterpart_account_code,
    'counterpart_account_name', v_counterpart_account_name,
    'counterpart_debit', v_counterpart_debit,
    'counterpart_credit', v_counterpart_credit
  );
end;
$$;

grant execute on function public.get_stock_adjustment_details(uuid) to authenticated;