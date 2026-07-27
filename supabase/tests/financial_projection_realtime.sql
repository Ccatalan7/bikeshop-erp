begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(16);

select has_function(
  'public',
  'broadcast_financial_projection_change',
  array[]::text[],
  'financial projection invalidation has one canonical trigger function'
);

select ok(
  (
    select procedure.prosecdef
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'broadcast_financial_projection_change'
      and procedure.pronargs = 0
  ),
  'the trigger function owns the trusted realtime send'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.broadcast_financial_projection_change()',
    'EXECUTE'
  ),
  'authenticated clients cannot invoke the trigger function'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.broadcast_financial_projection_change()',
    'EXECUTE'
  ),
  'anonymous clients cannot invoke the trigger function'
);

select is(
  (
    select count(*)::integer
    from pg_trigger trigger_row
    where trigger_row.tgname =
      'trg_broadcast_financial_projection_change'
      and not trigger_row.tgisinternal
  ),
  14,
  'every direct financial projection source has the invalidation trigger'
);

select ok(
  not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgname =
      'trg_broadcast_financial_projection_change'
      and (
        not trigger_row.tgenabled = 'O'
        or pg_get_triggerdef(trigger_row.oid) not like
          '%AFTER INSERT OR DELETE OR UPDATE%'
      )
  ),
  'all financial invalidation triggers are enabled for insert/update/delete'
);

select ok(
  (
    select pg_get_functiondef(procedure.oid)
      like '%realtime.send(%'
      and pg_get_functiondef(procedure.oid)
        like '%' || quote_literal('event_id') || '%'
      and pg_get_functiondef(procedure.oid)
        like '%' || quote_literal('kind') || '%'
      and pg_get_functiondef(procedure.oid)
        like '%' || quote_literal('entity_id') || '%'
      and pg_get_functiondef(procedure.oid)
        like '%' || quote_literal('operation') || '%'
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'broadcast_financial_projection_change'
      and procedure.pronargs = 0
  ),
  'the broadcast payload contains only invalidation identity and operation'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'sales_invoices'
      and policyname = 'Employees can view all invoices'
  ),
  'the permissive cross-tenant sales invoice policy is absent'
);

select ok(
  not exists (
    select 1
    from public.sales_invoices
    where tenant_id is null
  ),
  'every sales invoice belongs to an explicit tenant'
);

select col_not_null(
  'public',
  'sales_invoices',
  'tenant_id',
  'sales invoices cannot regress to a tenantless state'
);

select ok(
  to_regclass('realtime.messages') is null
  or exists (
    select 1
    from pg_policies
    where schemaname = 'realtime'
      and tablename = 'messages'
      and policyname =
        'Tenant members receive financial projection broadcasts'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%extension = %broadcast%'
      and qual like '%financial-projections:%'
      and qual like '%user_tenant_id()%'
      and qual not like '%private IS TRUE%'
  ),
  'managed Realtime installs authorize the exact tenant Broadcast topic'
);

select ok(
  to_regclass('realtime.messages') is null
  or not exists (
    select 1
    from pg_policies
    where schemaname = 'realtime'
      and tablename = 'messages'
      and policyname =
        'Tenant members receive financial projection broadcasts'
      and cmd in ('INSERT', 'ALL')
  ),
  'clients receive financial broadcasts but cannot publish them'
);

select ok(
  (
    select procedure.proconfig @>
      array['search_path=pg_catalog, public, pg_temp']::text[]
    from pg_proc procedure
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'broadcast_financial_projection_change'
      and procedure.pronargs = 0
  ),
  'the security definer function has a fixed safe search path'
);

create temporary table financial_realtime_capture (
  topic text,
  event text,
  private boolean,
  payload jsonb
) on commit drop;

create temporary table financial_realtime_authorization_results (
  check_name text primary key,
  passed boolean not null
) on commit drop;

do $$
declare
  v_tenant_id constant uuid :=
    'fa170000-0000-4000-8000-000000000001';
  v_user_id constant uuid :=
    'fa170000-0000-4000-8000-000000000099';
  v_account_id constant uuid :=
    'fa170000-0000-4000-8000-000000000011';
begin
  if to_regclass('realtime.messages') is not null then
    -- Supabase manages daily partitions in hosted environments. A stopped
    -- local Realtime container can lag one day behind, so create only the
    -- current transactional test partition and roll it back with the fixture.
    begin
      execute format(
        'create table realtime.%I partition of realtime.messages '
        'for values from (%L) to (%L)',
        'messages_financial_realtime_' || pg_backend_pid()::text,
        date_trunc('day', current_timestamp),
        date_trunc('day', current_timestamp) + interval '1 day'
      );
    exception
      when duplicate_table or invalid_object_definition then
        null;
    end;

    insert into public.tenants (id, shop_name)
    values (v_tenant_id, 'Financial Realtime pgTAP');

    insert into auth.users (
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    )
    values (
      v_user_id,
      'authenticated',
      'authenticated',
      'financial-realtime@example.invalid',
      '',
      now(),
      '{}'::jsonb,
      jsonb_build_object(
        'account_type',
        'public_store_customer',
        'customer_tenant_id',
        v_tenant_id
      ),
      now(),
      now()
    );

    insert into public.user_profiles (user_id, tenant_id, role)
    values (v_user_id, v_tenant_id, 'admin');

    insert into public.accounts (
      id,
      tenant_id,
      code,
      name,
      type,
      category
    )
    values (
      v_account_id,
      v_tenant_id,
      'RT-AUDIT',
      'Realtime audit account',
      'expense',
      'operatingExpense'
    );

    -- Match the rolled-back row shape used by Realtime Authorization. Its
    -- private flag is false/default even when the requested channel itself is
    -- private, so topic authorization must not depend on that durable-row
    -- column.
    perform realtime.send(
      jsonb_build_object('probe', true),
      'authorization-probe',
      'financial-projections:' || v_tenant_id::text,
      false
    );

    insert into financial_realtime_capture (
      topic,
      event,
      private,
      payload
    )
    select
      message.topic,
      message.event,
      message.private,
      message.payload
    from realtime.messages message
    where message.topic =
      'financial-projections:' || v_tenant_id::text
      and message.event = 'changed'
    order by message.inserted_at desc
    limit 1;
  end if;
end
$$;

select ok(
  to_regclass('realtime.messages') is null
  or exists (
    select 1
    from financial_realtime_capture capture
    where capture.event = 'changed'
      and capture.private is true
      and capture.payload ->> 'kind' = 'account'
      and capture.payload ->> 'operation' = 'insert'
      and capture.payload ? 'event_id'
      and capture.payload ? 'entity_id'
  ),
  'a real source insert emits one private minimal tenant invalidation'
);

do $$
declare
  v_tenant_id constant uuid :=
    'fa170000-0000-4000-8000-000000000001';
  v_user_id constant uuid :=
    'fa170000-0000-4000-8000-000000000099';
  v_visible boolean;
begin
  if to_regclass('realtime.messages') is not null then
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub',
        v_user_id,
        'role',
        'authenticated'
      )::text,
      true
    );
    perform set_config(
      'request.jwt.claim.sub',
      v_user_id::text,
      true
    );
    perform set_config(
      'realtime.topic',
      'financial-projections:' || v_tenant_id::text,
      true
    );

    execute 'set local role authenticated';
    execute $query$
      select exists (
        select 1
        from realtime.messages
        where event = 'authorization-probe'
      )
    $query$
    into v_visible;
    execute 'reset role';

    insert into financial_realtime_authorization_results (
      check_name,
      passed
    )
    values ('own_topic', v_visible);

    perform set_config(
      'realtime.topic',
      'financial-projections:fa170000-0000-4000-8000-000000000002',
      true
    );
    execute 'set local role authenticated';
    execute $query$
      select not exists (
        select 1
        from realtime.messages
        where event = 'authorization-probe'
      )
    $query$
    into v_visible;
    execute 'reset role';

    insert into financial_realtime_authorization_results (
      check_name,
      passed
    )
    values ('foreign_topic', v_visible);
  end if;
exception
  when others then
    execute 'reset role';
    raise;
end
$$;

select ok(
  to_regclass('realtime.messages') is null
  or coalesce(
    (
      select result.passed
      from financial_realtime_authorization_results result
      where result.check_name = 'own_topic'
    ),
    false
  ),
  'the authenticated tenant can read the synthetic Broadcast authorization probe'
);

select ok(
  to_regclass('realtime.messages') is null
  or coalesce(
    (
      select result.passed
      from financial_realtime_authorization_results result
      where result.check_name = 'foreign_topic'
    ),
    false
  ),
  'the same authenticated user cannot read a foreign tenant topic'
);

select * from finish();

rollback;
