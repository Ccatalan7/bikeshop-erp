-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on
-- 2026-07-17 UTC. The function body and migration-history row were read back;
-- a live BEGIN/ROLLBACK probe rejected an empty approval, accepted the same
-- pending proposal with its lines restored, and left the real row unchanged.
--
-- Purpose:
--   A proposal without products or services is not a customer-approvable
--   commercial document. Enforce the rule in the same atomic trigger that
--   captures the immutable approval snapshot, so every client and retry path
--   receives the same protection.
--
-- Recovery:
--   Reinstall the previous trigger function from migration
--   20260716030000_harden_quotation_approval_contract.sql. Existing approval
--   events and snapshots remain immutable; this migration performs no backfill.

begin;

create or replace function public.enrich_mechanic_job_mode_event_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_snapshot jsonb;
  v_approval_event public.mechanic_job_mode_events%rowtype;
  v_job_tenant_id uuid;
  v_job_subject_id uuid;
  v_job_subject_notes text;
  v_request_subject_id uuid;
begin
  select tenant_id, subject_id, subject_notes
  into v_job_tenant_id, v_job_subject_id, v_job_subject_notes
  from public.mechanic_jobs
  where id = new.job_id;

  if v_job_tenant_id is null
     or v_job_tenant_id is distinct from new.tenant_id then
    raise exception 'Quotation snapshot event does not match the job tenant.'
      using errcode = '23514';
  end if;

  if new.event_type = 'quotation_status_changed'
     and new.to_quotation_status in ('approved', 'rejected', 'expired') then
    v_snapshot := public.mechanic_job_quotation_content_snapshot(new.job_id);
    if v_snapshot is null then
      raise exception 'No se pudo capturar el contenido de la cotización aprobada.';
    end if;
    if new.to_quotation_status = 'approved'
       and jsonb_array_length(
         coalesce(v_snapshot->'items', '[]'::jsonb)
       ) = 0 then
      raise exception 'Agrega al menos un producto o servicio antes de aprobar el presupuesto.'
        using errcode = '23514';
    end if;
    if new.to_quotation_status = 'approved'
       and coalesce(
         (v_snapshot->'job'->>'discount_amount')::numeric,
         0
       ) > coalesce(
         (v_snapshot->'job'->>'parts_cost')::numeric,
         0
       ) + coalesce(
         (v_snapshot->'job'->>'labor_cost')::numeric,
         0
       ) then
      raise exception 'El descuento no puede superar el subtotal antes de aprobar el presupuesto.'
        using errcode = '23514';
    end if;
    new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
      'quotation_snapshot', v_snapshot,
      'quotation_snapshot_hash',
        encode(extensions.digest(v_snapshot::text, 'sha256'), 'hex'),
      'quotation_snapshot_hash_algorithm', 'sha256',
      'snapshot_contract', 'commercial-content-v1'
    );
  elsif new.event_type = 'converted_to_billable' then
    if new.to_intake_kind = 'component' then
      v_request_subject_id := nullif(
        btrim(coalesce(new.metadata->'request'->>'subject_id', '')),
        ''
      )::uuid;

      if v_request_subject_id is not null
         and not exists (
           select 1
           from public.job_subjects subject
           where subject.id = v_request_subject_id
             and subject.tenant_id = new.tenant_id
             and subject.is_active
         ) then
        raise exception 'El componente recibido debe estar activo y pertenecer al negocio del trabajo.'
          using errcode = '23514';
      end if;

      if v_job_subject_id is not null then
        if not exists (
          select 1
          from public.job_subjects subject
          where subject.id = v_job_subject_id
            and subject.tenant_id = new.tenant_id
            and subject.is_active
        ) then
          raise exception 'El componente recibido debe estar activo y pertenecer al negocio del trabajo.'
            using errcode = '23514';
        end if;
      elsif nullif(btrim(coalesce(v_job_subject_notes, '')), '') is null then
        raise exception 'Selecciona o describe el componente recibido antes de convertir la cotización.'
          using errcode = '23514';
      end if;
    end if;

    select * into v_approval_event
    from public.mechanic_job_mode_events event
    where event.tenant_id = new.tenant_id
      and event.job_id = new.job_id
      and event.event_type = 'quotation_status_changed'
      and event.to_quotation_status = 'approved'
      and event.metadata ? 'quotation_snapshot'
    order by event.occurred_at desc, event.id desc
    limit 1;

    if not found then
      raise exception 'La aprobación no contiene una ficha inmutable; reabre y vuelve a aprobar la cotización.'
        using errcode = '23514';
    end if;

    v_snapshot := public.mechanic_job_quotation_content_snapshot(new.job_id);
    if v_snapshot is distinct from v_approval_event.metadata->'quotation_snapshot' then
      raise exception 'La cotización cambió después de aprobarse; reábrela y solicita una nueva aprobación.'
        using errcode = '23514';
    end if;

    new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
      'quotation_snapshot', v_approval_event.metadata->'quotation_snapshot',
      'quotation_snapshot_hash',
        v_approval_event.metadata->>'quotation_snapshot_hash',
      'quotation_approval_event_id', v_approval_event.id,
      'snapshot_contract', 'commercial-content-v1',
      'snapshot_verified_at_conversion', true
    );
  end if;

  return new;
end;
$$;

revoke all on function public.enrich_mechanic_job_mode_event_snapshot()
  from public, anon, authenticated, service_role;

comment on function public.enrich_mechanic_job_mode_event_snapshot() is
  'Captures immutable proposal snapshots, rejects empty approvals, and verifies conversion against the approved content.';

commit;
