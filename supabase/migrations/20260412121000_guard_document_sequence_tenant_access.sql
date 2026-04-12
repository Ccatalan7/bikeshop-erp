create or replace function public.get_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_tenant_id uuid;
  v_next_number integer;
  v_max_existing integer := 0;
  v_prefix text;
  v_table_name text;
  v_column_name text;
  v_formatted_number text;
begin
  v_actor_tenant_id := public.user_tenant_id();

  if auth.uid() is not null then
    if v_actor_tenant_id is null then
      raise exception 'Could not resolve tenant for authenticated user';
    end if;

    if p_tenant_id is null or p_tenant_id <> v_actor_tenant_id then
      raise exception 'Cross-tenant document sequence access is not allowed';
    end if;
  end if;

  v_prefix := coalesce(p_prefix, case p_document_type
    when 'sales_invoice' then 'FV'
    when 'purchase_invoice' then 'FC'
    when 'sales_payment' then 'PV'
    when 'purchase_payment' then 'PC'
    when 'journal_entry' then 'AC'
    when 'mechanic_job' then 'PG'
    when 'stock_adjustment' then 'AJ'
    when 'expense' then 'GTO'
    else 'DOC'
  end);

  case p_document_type
    when 'sales_invoice' then
      v_table_name := 'sales_invoices';
      v_column_name := 'invoice_number';
    when 'purchase_invoice' then
      v_table_name := 'purchase_invoices';
      v_column_name := 'invoice_number';
    when 'sales_payment' then
      v_table_name := 'sales_payments';
      v_column_name := 'payment_number';
    when 'purchase_payment' then
      v_table_name := 'purchase_payments';
      v_column_name := 'payment_number';
    when 'journal_entry' then
      v_table_name := 'journal_entries';
      v_column_name := 'entry_number';
    when 'mechanic_job' then
      v_table_name := 'mechanic_jobs';
      v_column_name := 'job_number';
    when 'stock_adjustment' then
      v_table_name := 'stock_adjustments';
      v_column_name := 'adjustment_number';
    when 'expense' then
      v_table_name := 'expenses';
      v_column_name := 'expense_number';
    else
      v_table_name := null;
      v_column_name := null;
  end case;

  if v_table_name is not null and v_column_name is not null then
    execute format(
      'select coalesce(max((substring(%1$I from ''([0-9]+)$''))::integer), 0)
         from public.%2$I
        where tenant_id = $1
          and %1$I ~ $2',
      v_column_name,
      v_table_name
    )
    into v_max_existing
    using p_tenant_id, '^' || v_prefix || '-[0-9]+$';
  end if;

  insert into public.document_sequences (tenant_id, document_type, last_number)
  values (p_tenant_id, p_document_type, greatest(v_max_existing, 0) + 1)
  on conflict (tenant_id, document_type)
  do update set
    last_number = greatest(public.document_sequences.last_number, v_max_existing) + 1,
    updated_at = now()
  returning last_number into v_next_number;

  v_formatted_number := v_prefix || '-' || lpad(v_next_number::text, 5, '0');
  return v_formatted_number;
end;
$$;

grant execute on function public.get_next_document_number(uuid, text, text) to authenticated;

create or replace function public.preview_next_document_number(
  p_tenant_id uuid,
  p_document_type text,
  p_prefix text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_tenant_id uuid;
  v_current_number integer;
  v_max_existing integer := 0;
  v_next_number integer;
  v_prefix text;
  v_table_name text;
  v_column_name text;
  v_formatted_number text;
begin
  v_actor_tenant_id := public.user_tenant_id();

  if auth.uid() is not null then
    if v_actor_tenant_id is null then
      raise exception 'Could not resolve tenant for authenticated user';
    end if;

    if p_tenant_id is null or p_tenant_id <> v_actor_tenant_id then
      raise exception 'Cross-tenant document sequence access is not allowed';
    end if;
  end if;

  v_prefix := coalesce(p_prefix, case p_document_type
    when 'sales_invoice' then 'FV'
    when 'purchase_invoice' then 'FC'
    when 'sales_payment' then 'PV'
    when 'purchase_payment' then 'PC'
    when 'journal_entry' then 'AC'
    when 'mechanic_job' then 'PG'
    when 'stock_adjustment' then 'AJ'
    when 'expense' then 'GTO'
    else 'DOC'
  end);

  case p_document_type
    when 'sales_invoice' then
      v_table_name := 'sales_invoices';
      v_column_name := 'invoice_number';
    when 'purchase_invoice' then
      v_table_name := 'purchase_invoices';
      v_column_name := 'invoice_number';
    when 'sales_payment' then
      v_table_name := 'sales_payments';
      v_column_name := 'payment_number';
    when 'purchase_payment' then
      v_table_name := 'purchase_payments';
      v_column_name := 'payment_number';
    when 'journal_entry' then
      v_table_name := 'journal_entries';
      v_column_name := 'entry_number';
    when 'mechanic_job' then
      v_table_name := 'mechanic_jobs';
      v_column_name := 'job_number';
    when 'stock_adjustment' then
      v_table_name := 'stock_adjustments';
      v_column_name := 'adjustment_number';
    when 'expense' then
      v_table_name := 'expenses';
      v_column_name := 'expense_number';
    else
      v_table_name := null;
      v_column_name := null;
  end case;

  if v_table_name is not null and v_column_name is not null then
    execute format(
      'select coalesce(max((substring(%1$I from ''([0-9]+)$''))::integer), 0)
         from public.%2$I
        where tenant_id = $1
          and %1$I ~ $2',
      v_column_name,
      v_table_name
    )
    into v_max_existing
    using p_tenant_id, '^' || v_prefix || '-[0-9]+$';
  end if;

  select coalesce(last_number, 0)
    into v_current_number
    from public.document_sequences
   where tenant_id = p_tenant_id
     and document_type = p_document_type;

  v_next_number := greatest(coalesce(v_current_number, 0), coalesce(v_max_existing, 0)) + 1;
  v_formatted_number := v_prefix || '-' || lpad(v_next_number::text, 5, '0');
  return v_formatted_number;
end;
$$;

grant execute on function public.preview_next_document_number(uuid, text, text) to authenticated;