-- Prevent old clients or ad-hoc table updates from bypassing the append-only
-- workshop archive event and the shared inventory/accounting checkpoints.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

alter function public.set_mechanic_job_archived(
  uuid, boolean, text, text
) rename to set_mechanic_job_archived_internal;

revoke all on function public.set_mechanic_job_archived_internal(
  uuid, boolean, text, text
) from public, anon, authenticated, service_role;

create or replace function public.guard_mechanic_job_archive_projection()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_expected_context text;
begin
  if new.deleted_at is not distinct from old.deleted_at
     and new.deleted_by is not distinct from old.deleted_by
     and new.archive_reason is not distinct from old.archive_reason
     and new.archive_operation_id is not distinct from old.archive_operation_id then
    return new;
  end if;

  if old.deleted_at is null and new.deleted_at is not null then
    v_expected_context := old.id::text || ':archive';
    if new.deleted_by is distinct from auth.uid()
       or nullif(btrim(coalesce(new.archive_reason, '')), '') is null
       or new.archive_operation_id is null then
      raise exception 'La eliminación del trabajo no contiene una huella completa.'
        using errcode = '23514';
    end if;
  elsif old.deleted_at is not null and new.deleted_at is null then
    v_expected_context := old.id::text || ':restore';
    if new.deleted_by is not null
       or new.archive_reason is not null
       or new.archive_operation_id is not null then
      raise exception 'La restauración del trabajo no limpió su estado archivado.'
        using errcode = '23514';
    end if;
  else
    raise exception 'El estado de eliminación solo cambia mediante Eliminar o Restaurar.'
      using errcode = '42501';
  end if;

  if current_setting('app.mechanic_job_archive_command', true)
       is distinct from v_expected_context then
    raise exception 'Esta versión del ERP no puede eliminar trabajos de forma auditada. Actualiza la aplicación e inténtalo nuevamente.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_mechanic_job_archive_projection()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_mechanic_job_archive_projection
  on public.mechanic_jobs;
create trigger trg_guard_mechanic_job_archive_projection
  before update of deleted_at, deleted_by, archive_reason, archive_operation_id
  on public.mechanic_jobs
  for each row execute function public.guard_mechanic_job_archive_projection();

create or replace function public.set_mechanic_job_archived(
  p_job_id uuid,
  p_archived boolean,
  p_reason text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
  v_context text := p_job_id::text || case
    when p_archived then ':archive'
    else ':restore'
  end;
begin
  perform set_config('app.mechanic_job_archive_command', v_context, true);
  begin
    v_result := public.set_mechanic_job_archived_internal(
      p_job_id,
      p_archived,
      p_reason,
      p_idempotency_key
    );
  exception when others then
    perform set_config('app.mechanic_job_archive_command', '', true);
    raise;
  end;
  perform set_config('app.mechanic_job_archive_command', '', true);
  return v_result;
end;
$$;

revoke all on function public.set_mechanic_job_archived(
  uuid, boolean, text, text
) from public, anon, service_role;
grant execute on function public.set_mechanic_job_archived(
  uuid, boolean, text, text
) to authenticated;

comment on function public.set_mechanic_job_archived(uuid, boolean, text, text)
is 'Only public entry point for replay-safe workshop job archive/restore; direct archive-column updates are rejected.';

notify pgrst, 'reload schema';

commit;
