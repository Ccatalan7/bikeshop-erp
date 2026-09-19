-- Una conciliación queda registrada desde que se importan sus cartolas, no
-- recién al aplicar. Agrupa las cartolas que se revisaron juntas y guarda el
-- borrador de lo que el operador decidió sin aplicar —y lo que leyó la IA—,
-- para aplicar ahora lo seguro y retomar lo pendiente otro día sin volver a
-- subir los PDF (los movimientos ya viven en bank_statement_rows).
--
-- El borrador es del cliente: un objeto que el servidor sólo guarda con
-- revisión optimista. Lo que se aplica sigue pasando por el kernel, que
-- vuelve a validar todo.

create table if not exists public.bank_reconciliation_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  erp_account_id uuid not null,
  draft jsonb not null default '{}'::jsonb
    check (jsonb_typeof(draft) = 'object'),
  revision bigint not null default 1 check (revision > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint bank_reconciliation_sessions_account_fk
    foreign key (tenant_id, erp_account_id)
    references public.accounts(tenant_id, id) on delete restrict
);

create index if not exists idx_bank_reconciliation_sessions_account
  on public.bank_reconciliation_sessions(tenant_id, erp_account_id, updated_at desc);

alter table public.bank_statement_imports
  add column if not exists session_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'bank_statement_imports_session_fk'
  ) then
    alter table public.bank_statement_imports
      add constraint bank_statement_imports_session_fk
      foreign key (tenant_id, session_id)
      references public.bank_reconciliation_sessions(tenant_id, id)
      on delete restrict;
  end if;
end;
$$;

create index if not exists idx_bank_statement_imports_session
  on public.bank_statement_imports(tenant_id, session_id);

alter table public.bank_reconciliation_sessions enable row level security;

drop policy if exists bank_reconciliation_sessions_accounting_read
  on public.bank_reconciliation_sessions;
create policy bank_reconciliation_sessions_accounting_read
  on public.bank_reconciliation_sessions for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

revoke all on public.bank_reconciliation_sessions
  from public, anon, authenticated;
grant select on public.bank_reconciliation_sessions to authenticated;

-- Opens the conciliation its statements belong to: the one any of them
-- already joined (the most recent, when a file is shared), or a new one.
-- Statements that joined none join it. Returns the saved draft.
create or replace function public.open_bank_reconciliation_session_v1(
  p_erp_account_id uuid,
  p_import_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_user_id uuid := auth.uid();
  v_session public.bank_reconciliation_sessions%rowtype;
  v_created boolean := false;
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if p_erp_account_id is null
     or coalesce(cardinality(p_import_ids), 0) not between 1 and 24 then
    raise exception using errcode = '22023', message = 'bank_reconciliation_session_payload_invalid';
  end if;
  if (
    select count(*)
      from public.bank_statement_imports statement_import
     where statement_import.tenant_id = v_tenant_id
       and statement_import.erp_account_id = p_erp_account_id
       and statement_import.id = any(p_import_ids)
  ) <> cardinality(array(select distinct unnest(p_import_ids))) then
    raise exception using errcode = '42501', message = 'bank_statement_import_not_accessible';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':bank-reconciliation', 0
  ));

  select session.*
    into v_session
    from public.bank_reconciliation_sessions session
   where session.tenant_id = v_tenant_id
     and session.id in (
       select statement_import.session_id
         from public.bank_statement_imports statement_import
        where statement_import.tenant_id = v_tenant_id
          and statement_import.id = any(p_import_ids)
          and statement_import.session_id is not null
     )
   order by session.updated_at desc, session.id
   limit 1;

  if v_session.id is null then
    insert into public.bank_reconciliation_sessions (
      tenant_id, erp_account_id, created_by, updated_by
    ) values (
      v_tenant_id, p_erp_account_id, v_user_id, v_user_id
    )
    returning * into v_session;
    v_created := true;
  end if;

  update public.bank_statement_imports statement_import
     set session_id = v_session.id
   where statement_import.tenant_id = v_tenant_id
     and statement_import.id = any(p_import_ids)
     and statement_import.session_id is null;

  return jsonb_build_object(
    'session_id', v_session.id,
    'revision', v_session.revision,
    'draft', v_session.draft,
    'created', v_created,
    'import_ids', (
      select coalesce(jsonb_agg(statement_import.id order by statement_import.created_at), '[]'::jsonb)
        from public.bank_statement_imports statement_import
       where statement_import.tenant_id = v_tenant_id
         and statement_import.session_id = v_session.id
    )
  );
end;
$$;

-- Saves the draft only over the revision the client last saw: two screens
-- never overwrite each other in silence.
create or replace function public.save_bank_reconciliation_session_draft_v1(
  p_session_id uuid,
  p_expected_revision bigint,
  p_draft jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_user_id uuid := auth.uid();
  v_revision bigint;
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if p_session_id is null or p_expected_revision is null
     or coalesce(jsonb_typeof(p_draft), 'null') <> 'object' then
    raise exception using errcode = '22023', message = 'bank_reconciliation_session_payload_invalid';
  end if;
  if octet_length(p_draft::text) > 4000000 then
    raise exception using errcode = '22023', message = 'bank_reconciliation_draft_too_large';
  end if;

  update public.bank_reconciliation_sessions session
     set draft = p_draft,
         revision = session.revision + 1,
         updated_by = v_user_id,
         updated_at = now()
   where session.tenant_id = v_tenant_id
     and session.id = p_session_id
     and session.revision = p_expected_revision
  returning session.revision into v_revision;

  if v_revision is null then
    if exists (
      select 1 from public.bank_reconciliation_sessions session
       where session.tenant_id = v_tenant_id and session.id = p_session_id
    ) then
      raise exception using errcode = '40001', message = 'bank_reconciliation_draft_conflict';
    end if;
    raise exception using errcode = '42501', message = 'bank_reconciliation_session_not_accessible';
  end if;

  return jsonb_build_object('session_id', p_session_id, 'revision', v_revision);
end;
$$;

-- The account's conciliations, newest first, with what is still open: a
-- movement is done once its decision is final (anything but pending).
create or replace function public.list_bank_reconciliation_sessions_v1(
  p_erp_account_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;

  return coalesce((
    select jsonb_agg(item order by (item->>'updated_at')::timestamptz desc)
      from (
        select jsonb_build_object(
          'session_id', session.id,
          'revision', session.revision,
          'created_at', session.created_at,
          'updated_at', session.updated_at,
          'statement_count', (
            select count(*) from public.bank_statement_imports statement_import
             where statement_import.tenant_id = v_tenant_id
               and statement_import.session_id = session.id
          ),
          'movement_count', count(statement_row.id),
          'decided_count', count(statement_row.id) filter (
            where decision.disposition is not null
              and decision.disposition <> 'pending'
          ),
          'first_date', min(statement_row.booking_date),
          'last_date', max(statement_row.booking_date),
          'last_applied_at', max(decision.decided_at) filter (
            where decision.disposition is not null
              and decision.disposition <> 'pending'
          ),
          'draft_rows', (
            select count(*)
              from jsonb_object_keys(
                case when jsonb_typeof(session.draft->'rows') = 'object'
                     then session.draft->'rows' else '{}'::jsonb end
              )
          )
        ) as item
          from public.bank_reconciliation_sessions session
          left join public.bank_statement_imports statement_import
            on statement_import.tenant_id = v_tenant_id
           and statement_import.session_id = session.id
          left join public.bank_statement_rows statement_row
            on statement_row.tenant_id = v_tenant_id
           and statement_row.import_id = statement_import.id
          left join public.bank_reconciliation_row_decisions decision
            on decision.tenant_id = v_tenant_id
           and decision.row_id = statement_row.id
         where session.tenant_id = v_tenant_id
           and session.erp_account_id = p_erp_account_id
         group by session.id
         order by session.updated_at desc
         limit 50
      ) listed
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.open_bank_reconciliation_session_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;
revoke all on function public.save_bank_reconciliation_session_draft_v1(uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.list_bank_reconciliation_sessions_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.open_bank_reconciliation_session_v1(uuid, uuid[])
  to authenticated;
grant execute on function public.save_bank_reconciliation_session_draft_v1(uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.list_bank_reconciliation_sessions_v1(uuid)
  to authenticated;
