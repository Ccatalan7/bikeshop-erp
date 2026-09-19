-- The list counted as «decisiones sin aplicar» what was already applied.
--
-- The draft keeps the decisions of a sitting until the screen saves it
-- again; applying them does not rewrite it. Right after the owner's four
-- statements were applied (222 of 229 movements, 2026-09-19) the list said
-- «92 decisiones sin aplicar · 49 con análisis IA» for a conciliation with 7
-- movements left. The draft counts now leave out the movements a statement
-- already decided; resuming drops them from the draft on its next save.

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
              from jsonb_each(
                case when jsonb_typeof(session.draft->'rows') = 'object'
                     then session.draft->'rows' else '{}'::jsonb end
              ) saved
             where true
               and not exists (
                 select 1
                   from public.bank_statement_imports decided_import
                   join public.bank_statement_rows decided_row
                     on decided_row.tenant_id = v_tenant_id
                    and decided_row.import_id = decided_import.id
                   join public.bank_reconciliation_row_decisions decided
                     on decided.tenant_id = v_tenant_id
                    and decided.row_id = decided_row.id
                    and decided.disposition <> 'pending'
                  where decided_import.tenant_id = v_tenant_id
                    and decided_import.session_id = session.id
                    and decided_import.file_sha256 || ':'
                          || decided_row.source_row_id = saved.key
               )
          ),
          'draft_decisions', (
            select count(*)
              from jsonb_each(
                case when jsonb_typeof(session.draft->'rows') = 'object'
                     then session.draft->'rows' else '{}'::jsonb end
              ) saved
             where coalesce(saved.value->'resolution'->>'action', 'pending')
                   <> 'pending'
               and not exists (
                 select 1
                   from public.bank_statement_imports decided_import
                   join public.bank_statement_rows decided_row
                     on decided_row.tenant_id = v_tenant_id
                    and decided_row.import_id = decided_import.id
                   join public.bank_reconciliation_row_decisions decided
                     on decided.tenant_id = v_tenant_id
                    and decided.row_id = decided_row.id
                    and decided.disposition <> 'pending'
                  where decided_import.tenant_id = v_tenant_id
                    and decided_import.session_id = session.id
                    and decided_import.file_sha256 || ':'
                          || decided_row.source_row_id = saved.key
               )
          ),
          'draft_analyses', (
            select count(*)
              from jsonb_each(
                case when jsonb_typeof(session.draft->'rows') = 'object'
                     then session.draft->'rows' else '{}'::jsonb end
              ) saved
             where saved.value ? 'ai'
               and not exists (
                 select 1
                   from public.bank_statement_imports decided_import
                   join public.bank_statement_rows decided_row
                     on decided_row.tenant_id = v_tenant_id
                    and decided_row.import_id = decided_import.id
                   join public.bank_reconciliation_row_decisions decided
                     on decided.tenant_id = v_tenant_id
                    and decided.row_id = decided_row.id
                    and decided.disposition <> 'pending'
                  where decided_import.tenant_id = v_tenant_id
                    and decided_import.session_id = session.id
                    and decided_import.file_sha256 || ':'
                          || decided_row.source_row_id = saved.key
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

revoke all on function public.list_bank_reconciliation_sessions_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.list_bank_reconciliation_sessions_v1(uuid)
  to authenticated;
