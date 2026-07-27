begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- Remove the legacy cross-tenant SELECT escape hatch. The canonical
-- sales_invoices_select policy already grants ERP users tenant-scoped access.
drop policy if exists "Employees can view all invoices"
  on public.sales_invoices;

-- Emit only a minimal invalidation message. Financial rows never leave the
-- database through this channel, and the tenant topic is derived from the
-- committed row rather than supplied by a client.
create or replace function public.broadcast_financial_projection_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_record jsonb;
  v_tenant_id uuid;
  v_entity_id text;
  v_kind text;
begin
  v_record := case
    when tg_op = 'DELETE' then to_jsonb(old)
    else to_jsonb(new)
  end;
  v_tenant_id := nullif(v_record ->> 'tenant_id', '')::uuid;
  v_entity_id := nullif(v_record ->> 'id', '');
  v_kind := case tg_table_name
    when 'sales_invoices' then 'salesInvoice'
    when 'sales_payments' then 'salesPayment'
    when 'purchase_invoices' then 'purchaseInvoice'
    when 'purchase_payments' then 'purchasePayment'
    when 'expenses' then 'expense'
    when 'expense_lines' then 'expense'
    when 'expense_payments' then 'expensePayment'
    when 'payroll_vouchers' then 'payroll'
    when 'payroll_voucher_lines' then 'payroll'
    when 'employee_advances' then 'payroll'
    when 'employee_advance_allocations' then 'payroll'
    when 'journal_entries' then 'journalEntry'
    when 'journal_lines' then 'journalEntry'
    when 'accounts' then 'account'
    else null
  end;

  if v_tenant_id is null or v_kind is null then
    raise warning
      'Skipping financial projection broadcast for %.% without a tenant/kind',
      tg_table_schema,
      tg_table_name;
  elsif to_regprocedure(
    'realtime.send(jsonb,text,text,boolean)'
  ) is null then
    -- Public-only production validation clones omit Supabase-managed schemas.
    null;
  else
    perform realtime.send(
      jsonb_build_object(
        'event_id', gen_random_uuid()::text,
        'kind', v_kind,
        'entity_id', v_entity_id,
        'operation', lower(tg_op)
      ),
      'changed',
      'financial-projections:' || v_tenant_id::text,
      true
    );
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.broadcast_financial_projection_change()
  from public, anon, authenticated, service_role;

comment on function public.broadcast_financial_projection_change() is
  'Broadcasts tenant-private, payload-minimal financial projection invalidations after durable source-row changes.';

do $$
begin
  -- Production and a normal Supabase stack own this managed schema. The
  -- production-derived validation clone intentionally captures public only.
  if to_regclass('realtime.messages') is not null then
    execute
      'drop policy if exists "Tenant members receive financial projection broadcasts" '
      'on realtime.messages';
    execute $policy$
      create policy "Tenant members receive financial projection broadcasts"
        on realtime.messages
        for select
        to authenticated
        using (
          extension = 'broadcast'
          and private is true
          and (select realtime.topic()) =
            'financial-projections:' ||
            (select public.user_tenant_id())::text
        )
    $policy$;
  end if;
end
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'accounts',
    'employee_advance_allocations',
    'employee_advances',
    'expense_lines',
    'expense_payments',
    'expenses',
    'journal_entries',
    'journal_lines',
    'payroll_voucher_lines',
    'payroll_vouchers',
    'purchase_invoices',
    'purchase_payments',
    'sales_invoices',
    'sales_payments'
  ]
  loop
    if to_regclass('public.' || v_table) is null then
      raise exception 'Missing financial projection source table public.%', v_table;
    end if;

    execute format(
      'drop trigger if exists trg_broadcast_financial_projection_change on public.%I',
      v_table
    );
    execute format(
      'create trigger trg_broadcast_financial_projection_change '
      'after insert or update or delete on public.%I '
      'for each row execute function public.broadcast_financial_projection_change()',
      v_table
    );
  end loop;
end
$$;

commit;
