-- Local-only: the job close as production runs it (C1/C4, 2026-09-30). Not a
-- production change.
--
-- The local base (supabase/sql/core_schema.sql) carries an older
-- `handle_mechanic_job_change` whose AFTER branch consumes stock and books a
-- journal entry when a job reaches EN_CURSO/FINALIZADO. Production's body
-- computes those flags and never executes them, and no migration in the repo
-- owns production's body. Two more bodies lag behind production:
-- `normalize_mechanic_job_lifecycle_timestamps` (the start timestamp from
-- 20260805210000) and `create_mechanic_job_erp_notification` with its trigger
-- (archive/restore from 20260817170000). A local journey that closes a job
-- would otherwise move stock and post entries production never does.
--
-- These are production's `pg_get_functiondef` bodies read on 2026-09-30,
-- verified identical by md5 after applying (bodies, grants and trigger).
-- The workshop journey preflight checks the close body by md5.
--   scripts/db/query.sh local --write --file supabase/tests/fixtures/job_lifecycle_production_local_seed.sql
\set ON_ERROR_STOP on
begin;
select 1 / (case when not exists (select 1 from vault.secrets) then 1 else 0 end) as solo_base_local;
CREATE OR REPLACE FUNCTION public.handle_mechanic_job_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_old_status text; v_new_status text; v_should_consume_inventory boolean := false; v_should_restore_inventory boolean := false; v_should_create_journal boolean := false; v_should_delete_journal boolean := false;
begin
  if pg_trigger_depth() > 1 then if TG_OP = 'DELETE' then return OLD; else return NEW; end if; end if;
  if TG_OP = 'INSERT' then
    if TG_WHEN = 'BEFORE' then if NEW.job_number is null or NEW.job_number = '' then NEW.job_number := public.generate_mechanic_job_number(); end if; if NEW.status = 'EN_CURSO' and NEW.started_at is null then NEW.started_at := now(); end if; if NEW.status = 'FINALIZADO' and NEW.completed_at is null then NEW.completed_at := now(); end if; if NEW.status = 'ENTREGADO' and NEW.delivered_at is null then NEW.delivered_at := now(); end if; return NEW; end if;
    if TG_WHEN = 'AFTER' then perform public.log_mechanic_job_timeline(NEW.id,'created',null,NEW.status,'Job created: ' || coalesce(NEW.client_request, 'Service request')); if NEW.status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') then v_should_consume_inventory := true; end if; if NEW.status in ('FINALIZADO', 'ENTREGADO') and not NEW.is_invoiced then v_should_create_journal := true; end if; end if; return NEW;
  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status; v_new_status := NEW.status;
    if v_old_status <> v_new_status then
      perform public.log_mechanic_job_timeline(NEW.id,'status_changed',v_old_status,v_new_status,'Status changed from ' || v_old_status || ' to ' || v_new_status);
      if v_new_status = 'EN_CURSO' and NEW.started_at is null then NEW.started_at := now(); end if; if v_new_status = 'FINALIZADO' and NEW.completed_at is null then NEW.completed_at := now(); end if; if v_new_status = 'ENTREGADO' and NEW.delivered_at is null then NEW.delivered_at := now(); end if;
      if NEW.invoice_id is not null then if v_new_status = 'ENTREGADO' then update public.sales_invoices set status = 'enviado', updated_at = now() where id = NEW.invoice_id and status = 'draft'; elsif v_new_status = 'CANCELADO' then update public.sales_invoices set status = 'cancelado', updated_at = now() where id = NEW.invoice_id and status != 'paid'; end if; end if;
      if v_old_status not in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') and v_new_status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') then v_should_consume_inventory := true; elsif v_old_status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') and v_new_status = 'CANCELADO' then v_should_restore_inventory := true; end if;
      if v_new_status in ('FINALIZADO', 'ENTREGADO') and v_old_status not in ('FINALIZADO', 'ENTREGADO') and not NEW.is_invoiced then v_should_create_journal := true; elsif v_new_status = 'CANCELADO' and v_old_status in ('FINALIZADO', 'ENTREGADO') then v_should_delete_journal := true; end if;
    end if;

    -- 🌟 Link Bridge Fix: If invoice_id is newly linked, force a Forward Sync!
    if NEW.invoice_id is not null and OLD.invoice_id is null then
      perform public.sync_invoice_items_to_job(NEW.invoice_id);
      perform public.sync_invoice_status_to_job(NEW.invoice_id);
    end if;

    if OLD.diagnosis is distinct from NEW.diagnosis and NEW.diagnosis is not null then perform public.log_mechanic_job_timeline(NEW.id,'diagnosis_added',null,null,'Diagnosis updated'); end if;
    if OLD.assigned_to is distinct from NEW.assigned_to then perform public.log_mechanic_job_timeline(NEW.id,'assigned',OLD.assigned_technician_name,NEW.assigned_technician_name,'Technician assigned'); end if;
    if OLD.approved_by_customer <> NEW.approved_by_customer and NEW.approved_by_customer then perform public.log_mechanic_job_timeline(NEW.id,'approved',null,null,'Customer approved the work'); end if;
    if OLD.is_invoiced <> NEW.is_invoiced and NEW.is_invoiced then perform public.log_mechanic_job_timeline(NEW.id,'invoiced',null,NEW.invoice_id::text,'Job invoiced'); v_should_delete_journal := true; end if;
    return NEW;
  elsif TG_OP = 'DELETE' then
    if OLD.status in ('EN_CURSO', 'FINALIZADO', 'ENTREGADO') then perform public.restore_mechanic_job_inventory(OLD.id); end if;
    perform public.delete_mechanic_job_journal_entry(OLD.id); return OLD;
  end if;
end;
$function$;
CREATE OR REPLACE FUNCTION public.normalize_mechanic_job_lifecycle_timestamps()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_now timestamptz := clock_timestamp();
  v_is_delivered boolean;
  v_is_complete boolean;
  v_is_started boolean;
begin
  v_is_delivered := public.mechanic_job_resolves_delivery(
    new.status,
    new.status_id
  );
  v_is_complete := public.mechanic_job_resolves_completion(
    new.status,
    new.status_id
  );
  v_is_started := public.mechanic_job_resolves_start(
    new.status,
    new.status_id
  );

  -- El inicio es primer-gana y nunca se limpia: pasar a En Pausa o a
  -- REPUESTOS no des-inicia un trabajo. Un término o entrega implica que el
  -- trabajo también comenzó, aunque nadie haya pasado por «En Curso».
  if v_is_started or v_is_complete or v_is_delivered then
    new.started_at := coalesce(new.started_at, v_now);
  end if;

  if v_is_delivered then
    new.delivered_at := coalesce(new.delivered_at, v_now);
  else
    new.delivered_at := null;
  end if;

  if v_is_complete then
    new.completed_at := coalesce(
      new.completed_at,
      new.delivered_at,
      v_now
    );
  end if;

  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION public.create_mechanic_job_erp_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_bike_label text;
  v_body text;
  v_client_request text;
  v_customer_name text;
  v_is_archive boolean := false;
  v_is_restore boolean := false;
  v_job public.mechanic_jobs%rowtype;
  v_recorded_by_name text;
  v_removed_at timestamp with time zone;
  v_removed_by_name text;
begin
  if TG_OP = 'DELETE' then
    v_job := OLD;
    v_is_archive := true;
  else
    v_job := NEW;
  end if;

  if TG_OP = 'UPDATE' then
    v_is_archive := OLD.deleted_at is null and NEW.deleted_at is not null;
    v_is_restore := OLD.deleted_at is not null and NEW.deleted_at is null;
    if not v_is_archive and not v_is_restore then
      return NEW;
    end if;
  end if;

  if v_is_archive then
    v_removed_at := coalesce(v_job.deleted_at, clock_timestamp());
    v_removed_by_name := public.erp_actor_display_name(
      coalesce(v_job.deleted_by, auth.uid()),
      v_job.tenant_id
    );

    update public.erp_notifications as notification
       set type = 'mechanic_job_archived',
           title = 'Trabajo eliminado',
           route = '/taller/pegas',
           severity = 'warning',
           data = notification.data || jsonb_strip_nulls(jsonb_build_object(
             'is_inactive', true,
             'inactive_reason', 'archived',
             'removed_at', v_removed_at,
             'removed_by_name', v_removed_by_name,
             'archive_reason', nullif(btrim(v_job.archive_reason), '')
           ))
     where notification.tenant_id = v_job.tenant_id
       and notification.entity_type = 'mechanic_job'
       and notification.entity_id = v_job.id
       and notification.type in (
         'mechanic_job_created',
         'mechanic_job_archived'
       );

    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    return NEW;
  end if;

  -- An insert already carrying deleted_at is an inactive import, not a new
  -- workshop arrival. A normal restore is handled below.
  if TG_OP = 'INSERT' and NEW.deleted_at is not null then
    return NEW;
  end if;

  select customer.name
    into v_customer_name
  from public.customers customer
  where customer.id = v_job.customer_id
    and customer.tenant_id = v_job.tenant_id;

  select nullif(trim(
           coalesce(bike.brand, '') || ' ' || coalesce(bike.model, '')
           || case
                when nullif(trim(coalesce(bike.color, '')), '') is not null
                  then ' · ' || bike.color
                else ''
              end
         ), '')
    into v_bike_label
  from public.bikes bike
  where bike.id = v_job.bike_id
    and bike.tenant_id = v_job.tenant_id;

  v_client_request := nullif(
    left(coalesce(v_job.client_request, ''), 300),
    ''
  );
  v_recorded_by_name := public.erp_actor_display_name(
    coalesce(v_job.created_by, auth.uid()),
    v_job.tenant_id
  );
  v_body := coalesce(nullif(v_job.job_number, ''), 'Trabajo')
    || ' · '
    || coalesce(nullif(v_customer_name, ''), 'Cliente');

  if v_is_restore then
    update public.erp_notifications as notification
       set type = 'mechanic_job_created',
           title = 'Nuevo trabajo',
           body = v_body,
           route = '/taller/pegas?job=' || v_job.id::text,
           severity = 'info',
           data = (
             notification.data
               - 'is_inactive'
               - 'inactive_reason'
               - 'removed_at'
               - 'removed_by_name'
               - 'archive_reason'
           ) || jsonb_strip_nulls(jsonb_build_object(
             'job_id', v_job.id,
             'job_number', v_job.job_number,
             'customer_id', v_job.customer_id,
             'customer_name', v_customer_name,
             'bike_id', v_job.bike_id,
             'bike_label', v_bike_label,
             'client_request', v_client_request,
             'recorded_by_name', v_recorded_by_name,
             'priority', v_job.priority,
             'status', v_job.status
           ))
     where notification.tenant_id = v_job.tenant_id
       and notification.entity_type = 'mechanic_job'
       and notification.entity_id = v_job.id
       and notification.type = 'mechanic_job_archived';

    if found then
      return NEW;
    end if;
  end if;

  insert into public.erp_notifications (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data
  ) values (
    v_job.tenant_id,
    'mechanic_job_created',
    'Nuevo trabajo',
    v_body,
    '/taller/pegas?job=' || v_job.id::text,
    'mechanic_job',
    v_job.id,
    'info',
    jsonb_strip_nulls(jsonb_build_object(
      'job_id', v_job.id,
      'job_number', v_job.job_number,
      'customer_id', v_job.customer_id,
      'customer_name', v_customer_name,
      'bike_id', v_job.bike_id,
      'bike_label', v_bike_label,
      'client_request', v_client_request,
      'recorded_by_name', v_recorded_by_name,
      'priority', v_job.priority,
      'status', v_job.status
    ))
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;

  return v_job;
end;
$function$;
drop trigger if exists trg_mechanic_job_erp_notification on public.mechanic_jobs;
CREATE TRIGGER trg_mechanic_job_erp_notification AFTER INSERT OR DELETE OR UPDATE OF deleted_at ON public.mechanic_jobs FOR EACH ROW EXECUTE FUNCTION create_mechanic_job_erp_notification();
commit;
