-- Production recorded migration 20260719215000 while provisional expense RPC
-- definitions were still present. Reconcile the complete boundary under a new
-- immutable version so migration runners cannot skip the final state. This is
-- intentionally a full, idempotent convergence migration rather than an
-- out-of-band rewrite of already-recorded history.
--
-- Keep the legacy expense journal entry points compatible with current and
-- older clients while removing their cross-tenant SECURITY DEFINER surface.
-- The original implementations are retained owner-only. Only the application
-- rebuild and total-recalculation commands remain authenticated and prove the
-- caller's tenant before delegating; create/delete compatibility names are
-- service/trigger-only.
-- Trigger-driven delete cleanup remains possible after the source row has
-- already disappeared.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $$
declare
  v_pair record;
begin
  for v_pair in
    select *
    from (values
      (
        'public.create_expense_journal_entry(uuid)',
        'public.create_expense_journal_entry_owner_only(uuid)',
        'create_expense_journal_entry_owner_only'
      ),
      (
        'public.delete_expense_journal_entry(uuid)',
        'public.delete_expense_journal_entry_owner_only(uuid)',
        'delete_expense_journal_entry_owner_only'
      ),
      (
        'public.create_expense_payment_journal_entry(uuid)',
        'public.create_expense_payment_journal_entry_owner_only(uuid)',
        'create_expense_payment_journal_entry_owner_only'
      ),
      (
        'public.delete_expense_payment_journal_entry(uuid)',
        'public.delete_expense_payment_journal_entry_owner_only(uuid)',
        'delete_expense_payment_journal_entry_owner_only'
      ),
      (
        'public.rebuild_expense_journal_entry(uuid)',
        'public.rebuild_expense_journal_entry_owner_only(uuid)',
        'rebuild_expense_journal_entry_owner_only'
      ),
      (
        'public.recalculate_expense_totals(uuid)',
        'public.recalculate_expense_totals_owner_only(uuid)',
        'recalculate_expense_totals_owner_only'
      )
    ) as signatures(public_signature, owner_signature, owner_name)
  loop
    if to_regprocedure(v_pair.owner_signature) is null then
      if to_regprocedure(v_pair.public_signature) is null then
        raise exception 'Required expense journal RPC is missing: %',
          v_pair.public_signature
          using errcode = '42883';
      end if;

      execute format(
        'alter function %s rename to %I',
        v_pair.public_signature,
        v_pair.owner_name
      );
    end if;
  end loop;
end;
$$;

-- The legacy helper matched source_reference = expense_number without a
-- tenant predicate. Two tenants may legitimately use the same document
-- number, so mutable references are only valid together with source tenant.
-- If an AFTER DELETE path has already removed the expense, cleanup falls back
-- exclusively to the immutable expense UUID lineage.
create or replace function public.delete_expense_journal_entry_untraced(
  p_expense_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_expense_number text;
begin
  if p_expense_id is null then
    return;
  end if;

  select expense.tenant_id, expense.expense_number
    into v_tenant_id, v_expense_number
    from public.expenses expense
   where expense.id = p_expense_id
   for key share;

  if found then
    delete from public.journal_entries entry
     where entry.tenant_id = v_tenant_id
       and entry.source_module = 'expenses'
       and (
         entry.source_reference in (v_expense_number, p_expense_id::text)
         or entry.source_document_id = p_expense_id
       );
  else
    delete from public.journal_entries entry
     where entry.source_module = 'expenses'
       and (
         entry.source_reference = p_expense_id::text
         or entry.source_document_id = p_expense_id
       );
  end if;
end;
$$;

-- Retain the established posting shape while making every parent/account
-- lookup tenant-explicit. In particular, the historical fallback selected the
-- first account code 1101 in the whole database.
create or replace function public.create_expense_payment_journal_entry_untraced(
  p_payment_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_payment public.expense_payments%rowtype;
  v_expense public.expenses%rowtype;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_liability_account_id uuid;
  v_liability_code text;
  v_liability_name text;
  v_cash_account record;
  v_description text;
  v_is_payroll boolean := false;
begin
  select payment.*
    into v_payment
    from public.expense_payments payment
   where payment.id = p_payment_id;

  if not found then
    return;
  end if;

  select expense.*
    into v_expense
    from public.expenses expense
   where expense.id = v_payment.expense_id
     and expense.tenant_id = v_payment.tenant_id;

  if not found then
    raise exception 'Expense payment parent is missing'
      using errcode = '23503';
  end if;

  if lower(coalesce(v_expense.posting_status, 'draft')) <> 'posted'
     or coalesce(v_payment.amount, 0) = 0 then
    return;
  end if;

  v_is_payroll := (
    v_expense.notes like 'Pago de salario%'
    or v_expense.notes like 'Salario:%'
    or v_expense.reference like 'Semana %'
  );

  select exists (
    select 1
    from public.journal_entries entry
    where entry.tenant_id = v_payment.tenant_id
      and entry.source_module = 'expense_payments'
      and (
        entry.source_reference = v_payment.id::text
        or entry.source_document_id = v_payment.id
      )
  ) into v_exists;

  if v_exists then
    perform public.delete_expense_payment_journal_entry_untraced(v_payment.id);
  end if;

  if v_is_payroll then
    v_liability_code := '2106';
    v_liability_name := 'Sueldos por Pagar';
  else
    v_liability_code := '2105';
    v_liability_name := 'Cuentas por Pagar - Gastos';
  end if;

  if v_expense.liability_account_id is not null then
    select account.id, account.code, account.name
      into v_liability_account_id, v_liability_code, v_liability_name
      from public.accounts account
     where account.id = v_expense.liability_account_id
       and account.tenant_id = v_expense.tenant_id;
  end if;

  if v_liability_account_id is null then
    v_liability_account_id := public.ensure_account(
      v_expense.tenant_id,
      v_liability_code,
      v_liability_name,
      'liability',
      'currentLiability',
      'Obligaciones por gastos pendientes de pago',
      null
    );
  end if;

  select null::uuid as id, null::text as code, null::text as name
    into v_cash_account;

  if v_payment.payment_account_id is not null then
    select account.id, account.code, account.name
      into v_cash_account
      from public.accounts account
     where account.id = v_payment.payment_account_id
       and account.tenant_id = v_payment.tenant_id;
  elsif v_payment.payment_method_id is not null then
    select account.id, account.code, account.name
      into v_cash_account
      from public.payment_methods method
      join public.accounts account
        on account.id = method.account_id
       and account.tenant_id = method.tenant_id
     where method.id = v_payment.payment_method_id
       and method.tenant_id = v_payment.tenant_id;
  end if;

  if v_cash_account.id is null then
    select account.id, account.code, account.name
      into v_cash_account
      from public.accounts account
     where account.tenant_id = v_payment.tenant_id
       and account.code = '1101'
     order by account.created_at, account.id
     limit 1;
  end if;

  if v_cash_account.id is null then
    raise exception 'Expense payment account is missing for tenant'
      using errcode = '23503';
  end if;

  v_description := format(
    'Pago gasto %s',
    coalesce(v_expense.expense_number, v_expense.id::text)
  );

  insert into public.journal_entries (
    id, tenant_id, entry_number, entry_date, description, type,
    source_module, source_reference, status, total_debit, total_credit,
    created_at, updated_at
  ) values (
    v_entry_id,
    v_expense.tenant_id,
    public.get_next_document_number(v_expense.tenant_id, 'journal_entry'),
    coalesce(v_payment.payment_date, now()),
    v_description,
    'payment',
    'expense_payments',
    v_payment.id::text,
    'posted',
    v_payment.amount,
    v_payment.amount,
    now(),
    now()
  );

  insert into public.journal_lines (
    id, tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) values (
    gen_random_uuid(),
    v_expense.tenant_id,
    v_entry_id,
    v_liability_account_id,
    v_liability_code,
    v_liability_name,
    v_description,
    v_payment.amount,
    0,
    now(),
    now()
  );

  insert into public.journal_lines (
    id, tenant_id, entry_id, account_id, account_code, account_name,
    description, debit_amount, credit_amount, created_at, updated_at
  ) values (
    gen_random_uuid(),
    v_expense.tenant_id,
    v_entry_id,
    v_cash_account.id,
    v_cash_account.code,
    v_cash_account.name,
    v_description,
    0,
    v_payment.amount,
    now(),
    now()
  );
end;
$$;

create or replace function public.delete_expense_payment_journal_entry_untraced(
  p_payment_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  if p_payment_id is null then
    return;
  end if;

  select payment.tenant_id
    into v_tenant_id
    from public.expense_payments payment
   where payment.id = p_payment_id
   for key share;

  delete from public.journal_entries entry
   where entry.source_module = 'expense_payments'
     and (v_tenant_id is null or entry.tenant_id = v_tenant_id)
     and (
       entry.source_reference = p_payment_id::text
       or entry.source_document_id = p_payment_id
     );
end;
$$;

create or replace function public.assert_expense_rpc_tenant(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_database_role text := nullif(current_setting('role', true), 'none');
  v_auth_role text;
  v_auth_user uuid := auth.uid();
begin
  -- Prefer the database role selected by PostgREST. The JWT claim is only a
  -- fallback for owner-controlled SQL that deliberately supplies request
  -- claims; an authenticated caller cannot turn itself into service_role by
  -- changing an untrusted claim value.
  v_auth_role := coalesce(v_database_role, nullif(auth.role(), ''), '');

  if v_auth_role = 'authenticated' and (
    v_auth_user is null
    or p_tenant_id is null
    or public.user_tenant_id() is distinct from p_tenant_id
  ) then
    raise exception 'Expense not found or access denied'
      using errcode = '42501';
  end if;

  if v_auth_role = 'anon' then
    raise exception 'Expense not found or access denied'
      using errcode = '42501';
  end if;

  -- service_role and owner-controlled SQL remain compatible with internal
  -- maintenance and trigger paths. Neither role is reachable through these
  -- wrappers unless its exact EXECUTE privilege is present below.
end;
$$;

create or replace function public.assert_expense_deleted_source_operation(
  p_document_type text,
  p_document_id uuid,
  p_owner_table text,
  p_source_channel text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_operation_text text := nullif(
    current_setting('app.inventory_operation_id', true),
    ''
  );
  v_operation_id uuid;
  v_tenant_id uuid;
begin
  if v_operation_text is null
     or nullif(current_setting('app.inventory_source_document_type', true), '')
        is distinct from p_document_type
     or nullif(current_setting('app.inventory_source_document_id', true), '')
        is distinct from p_document_id::text
     or nullif(current_setting('app.inventory_source_channel', true), '')
        is distinct from p_source_channel then
    raise exception 'Expense not found or access denied'
      using errcode = '42501';
  end if;

  begin
    v_operation_id := v_operation_text::uuid;
  exception when invalid_text_representation then
    raise exception 'Expense not found or access denied'
      using errcode = '42501';
  end;

  select operation.tenant_id
    into v_tenant_id
    from public.inventory_accounting_operations operation
   where operation.id = v_operation_id
     and operation.document_type = p_document_type
     and operation.document_id = p_document_id
     and operation.source_channel = p_source_channel
     and operation.action = 'delete'
     and operation.outcome = 'started'
     and operation.executor = 'database_trigger'
     and operation.context->>'trace_owner' = 'row_trigger'
     and operation.context->>'owner_table' = p_owner_table
     and operation.context->>'owner_entity_id' = p_document_id::text;

  if not found then
    raise exception 'Expense not found or access denied'
      using errcode = '42501';
  end if;

  perform public.assert_expense_rpc_tenant(v_tenant_id);
  return v_tenant_id;
end;
$$;

create or replace function public.create_expense_journal_entry(
  p_expense_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select expense.tenant_id
    into v_tenant_id
    from public.expenses expense
   where expense.id = p_expense_id;

  perform public.assert_expense_rpc_tenant(v_tenant_id);

  perform public.create_expense_journal_entry_owner_only(p_expense_id);
end;
$$;

create or replace function public.delete_expense_journal_entry(
  p_expense_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select expense.tenant_id
    into v_tenant_id
    from public.expenses expense
   where expense.id = p_expense_id;

  if found then
    perform public.assert_expense_rpc_tenant(v_tenant_id);
  else
    perform public.assert_expense_deleted_source_operation(
      'expense',
      p_expense_id,
      'expenses',
      'expense'
    );
  end if;

  perform public.delete_expense_journal_entry_owner_only(p_expense_id);
end;
$$;

create or replace function public.create_expense_payment_journal_entry(
  p_payment_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select expense.tenant_id
    into v_tenant_id
    from public.expense_payments payment
    join public.expenses expense
      on expense.id = payment.expense_id
     and expense.tenant_id = payment.tenant_id
   where payment.id = p_payment_id;

  perform public.assert_expense_rpc_tenant(v_tenant_id);

  perform public.create_expense_payment_journal_entry_owner_only(p_payment_id);
end;
$$;

create or replace function public.delete_expense_payment_journal_entry(
  p_payment_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select expense.tenant_id
    into v_tenant_id
    from public.expense_payments payment
    join public.expenses expense
      on expense.id = payment.expense_id
     and expense.tenant_id = payment.tenant_id
   where payment.id = p_payment_id;

  if found then
    perform public.assert_expense_rpc_tenant(v_tenant_id);
  else
    perform public.assert_expense_deleted_source_operation(
      'expense_payment',
      p_payment_id,
      'expense_payments',
      'expense_payment'
    );
  end if;

  perform public.delete_expense_payment_journal_entry_owner_only(p_payment_id);
end;
$$;

create or replace function public.rebuild_expense_journal_entry(
  p_expense_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select expense.tenant_id
    into v_tenant_id
    from public.expenses expense
   where expense.id = p_expense_id;

  perform public.assert_expense_rpc_tenant(v_tenant_id);

  perform public.rebuild_expense_journal_entry_owner_only(p_expense_id);
end;
$$;

create or replace function public.recalculate_expense_totals(
  p_expense_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  select expense.tenant_id
    into v_tenant_id
    from public.expenses expense
   where expense.id = p_expense_id
   for key share;

  perform public.assert_expense_rpc_tenant(v_tenant_id);

  perform public.recalculate_expense_totals_owner_only(p_expense_id);
end;
$$;

-- During an expense DELETE, PostgreSQL may run cascading expense_lines
-- triggers after the parent trace has completed and cleared its transaction
-- context. There is nothing left to recalculate in that case, so return before
-- invoking any missing-source SECURITY DEFINER command. Existing parents keep
-- the established recalculate-then-rebuild behavior.
create or replace function public.handle_expense_line_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_expense_id uuid;
  v_posting_status text;
begin
  v_expense_id := case
    when TG_OP = 'DELETE' then OLD.expense_id
    else NEW.expense_id
  end;

  select expense.posting_status
    into v_posting_status
    from public.expenses expense
   where expense.id = v_expense_id;

  if not found then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  perform public.recalculate_expense_totals(v_expense_id);

  if lower(coalesce(v_posting_status, 'draft')) = 'posted' then
    perform public.create_expense_journal_entry(v_expense_id);
  end if;

  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

-- A payment DELETE can be explicit (the parent expense still exists) or can
-- be the FK cascade of an expense DELETE (the parent is already invisible).
-- OLD is trustworthy row-trigger evidence in both cases. Authorize its
-- immutable tenant directly, avoid recalculating a missing parent, and invoke
-- the retained delete implementation without relying on an unrelated root
-- operation trace.
create or replace function public.handle_expense_payment_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_parent_exists boolean;
begin
  if TG_OP = 'INSERT' then
    perform public.recalculate_expense_totals(NEW.expense_id);
    perform public.create_expense_payment_journal_entry(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    perform public.recalculate_expense_totals(NEW.expense_id);
    perform public.delete_expense_payment_journal_entry(OLD.id);
    perform public.create_expense_payment_journal_entry(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    perform public.assert_expense_rpc_tenant(OLD.tenant_id);

    select exists (
      select 1
        from public.expenses expense
       where expense.id = OLD.expense_id
         and expense.tenant_id = OLD.tenant_id
    ) into v_parent_exists;

    if v_parent_exists then
      perform public.recalculate_expense_totals(OLD.expense_id);
    end if;

    perform public.delete_expense_payment_journal_entry_owner_only(OLD.id);
    return OLD;
  end if;

  return null;
end;
$$;

comment on function public.assert_expense_rpc_tenant(uuid) is
  'Owner-only tenant assertion used before any SECURITY DEFINER expense journal mutation.';
comment on function public.assert_expense_deleted_source_operation(text, uuid, text, text) is
  'Owner-only proof that a missing delete source belongs to the exact active row-trigger operation.';
comment on function public.rebuild_expense_journal_entry(uuid) is
  'Tenant-scoped authenticated wrapper around the retained owner-only atomic expense journal rebuild.';
comment on function public.recalculate_expense_totals(uuid) is
  'Tenant-scoped authenticated wrapper around the retained owner-only expense total recalculation.';

do $$
declare
  v_function record;
  v_acl record;
  v_authenticated_oid oid;
  v_service_oid oid;
begin
  select oid into strict v_authenticated_oid
  from pg_roles where rolname = 'authenticated';
  select oid into strict v_service_oid
  from pg_roles where rolname = 'service_role';

  for v_function in
    select *
    from (values
      ('public.assert_expense_rpc_tenant(uuid)', false, false),
      ('public.assert_expense_deleted_source_operation(text,uuid,text,text)', false, false),
      ('public.create_expense_journal_entry_owner_only(uuid)', false, false),
      ('public.delete_expense_journal_entry_owner_only(uuid)', false, false),
      ('public.create_expense_payment_journal_entry_owner_only(uuid)', false, false),
      ('public.delete_expense_payment_journal_entry_owner_only(uuid)', false, false),
      ('public.rebuild_expense_journal_entry_owner_only(uuid)', false, false),
      ('public.recalculate_expense_totals_owner_only(uuid)', false, false),
      ('public.create_expense_journal_entry_untraced(uuid)', false, false),
      ('public.delete_expense_journal_entry_untraced(uuid)', false, false),
      ('public.create_expense_payment_journal_entry_untraced(uuid)', false, false),
      ('public.delete_expense_payment_journal_entry_untraced(uuid)', false, false),
      ('public.handle_expense_line_change()', false, false),
      ('public.handle_expense_payment_change()', false, false),
      ('public.create_expense_journal_entry(uuid)', true, false),
      ('public.delete_expense_journal_entry(uuid)', true, false),
      ('public.create_expense_payment_journal_entry(uuid)', true, false),
      ('public.delete_expense_payment_journal_entry(uuid)', true, false),
      ('public.rebuild_expense_journal_entry(uuid)', true, true),
      ('public.recalculate_expense_totals(uuid)', true, true)
    ) as functions(signature, service_api, authenticated_api)
  loop
    if to_regprocedure(v_function.signature) is null then
      raise exception 'Expense journal hardening function is missing: %',
        v_function.signature
        using errcode = '42883';
    end if;

    execute format(
      'revoke all privileges on function %s from public, anon, authenticated, service_role cascade',
      v_function.signature
    );

    for v_acl in
      select distinct pg_get_userbyid(acl.grantee) as role_name
      from pg_proc function_row
      cross join lateral aclexplode(
        coalesce(
          function_row.proacl,
          acldefault('f', function_row.proowner)
        )
      ) acl
      where function_row.oid = to_regprocedure(v_function.signature)
        and acl.privilege_type = 'EXECUTE'
        and acl.grantee <> 0
        and acl.grantee <> function_row.proowner
    loop
      execute format(
        'revoke all privileges on function %s from %I cascade',
        v_function.signature,
        v_acl.role_name
      );
    end loop;

    if v_function.service_api then
      execute format(
        'grant execute on function %s to service_role',
        v_function.signature
      );
    end if;

    if v_function.authenticated_api then
      execute format(
        'grant execute on function %s to authenticated',
        v_function.signature
      );
    end if;
  end loop;

  if exists (
    select 1
    from pg_proc function_row
    cross join lateral aclexplode(
      coalesce(function_row.proacl, acldefault('f', function_row.proowner))
    ) acl
    where function_row.oid in (
      'public.assert_expense_rpc_tenant(uuid)'::regprocedure,
      'public.assert_expense_deleted_source_operation(text,uuid,text,text)'::regprocedure,
      'public.create_expense_journal_entry_owner_only(uuid)'::regprocedure,
      'public.delete_expense_journal_entry_owner_only(uuid)'::regprocedure,
      'public.create_expense_payment_journal_entry_owner_only(uuid)'::regprocedure,
      'public.delete_expense_payment_journal_entry_owner_only(uuid)'::regprocedure,
      'public.rebuild_expense_journal_entry_owner_only(uuid)'::regprocedure,
      'public.recalculate_expense_totals_owner_only(uuid)'::regprocedure,
      'public.create_expense_journal_entry_untraced(uuid)'::regprocedure,
      'public.delete_expense_journal_entry_untraced(uuid)'::regprocedure,
      'public.create_expense_payment_journal_entry_untraced(uuid)'::regprocedure,
      'public.delete_expense_payment_journal_entry_untraced(uuid)'::regprocedure,
      'public.handle_expense_line_change()'::regprocedure,
      'public.handle_expense_payment_change()'::regprocedure
    )
      and acl.privilege_type = 'EXECUTE'
      and (acl.grantee = 0 or acl.grantee <> function_row.proowner)
  ) then
    raise exception 'Owner-only expense journal helper has an unsafe EXECUTE grant'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from pg_proc function_row
    cross join lateral aclexplode(
      coalesce(function_row.proacl, acldefault('f', function_row.proowner))
    ) acl
    where function_row.oid in (
      'public.create_expense_journal_entry(uuid)'::regprocedure,
      'public.delete_expense_journal_entry(uuid)'::regprocedure,
      'public.create_expense_payment_journal_entry(uuid)'::regprocedure,
      'public.delete_expense_payment_journal_entry(uuid)'::regprocedure,
      'public.rebuild_expense_journal_entry(uuid)'::regprocedure,
      'public.recalculate_expense_totals(uuid)'::regprocedure
    )
      and acl.privilege_type = 'EXECUTE'
      and (
        acl.grantee = 0
        or acl.grantee not in (
          function_row.proowner,
          v_authenticated_oid,
          v_service_oid
        )
      )
  ) then
    raise exception 'Expense journal API wrapper has an unsafe EXECUTE grant'
      using errcode = '23514';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.rebuild_expense_journal_entry(uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.recalculate_expense_totals(uuid)',
       'EXECUTE'
     )
     or exists (
       select 1
       from unnest(array[
         'public.create_expense_journal_entry(uuid)',
         'public.delete_expense_journal_entry(uuid)',
         'public.create_expense_payment_journal_entry(uuid)',
         'public.delete_expense_payment_journal_entry(uuid)'
       ]) signature
       where has_function_privilege('authenticated', signature, 'EXECUTE')
     )
     or exists (
       select 1
       from unnest(array[
         'public.create_expense_journal_entry(uuid)',
         'public.delete_expense_journal_entry(uuid)',
         'public.create_expense_payment_journal_entry(uuid)',
         'public.delete_expense_payment_journal_entry(uuid)',
         'public.rebuild_expense_journal_entry(uuid)',
         'public.recalculate_expense_totals(uuid)'
       ]) signature
       where not has_function_privilege('service_role', signature, 'EXECUTE')
          or has_function_privilege('anon', signature, 'EXECUTE')
     ) then
    raise exception 'Expense journal API wrapper ACL reconciliation failed'
      using errcode = '23514';
  end if;
end;
$$;

commit;
