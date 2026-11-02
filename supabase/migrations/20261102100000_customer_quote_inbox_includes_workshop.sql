-- La bandeja de cotizaciones también trae las del taller (redefine
-- customer_quote_inbox_v1 de 20261102041700).
--
-- Una cotización que se registra en el local es un trabajo del taller con
-- flujo `quotation` y sin bicicleta recibida («Cotización · Sin objeto
-- recibido»). Sigue siendo del taller: sus líneas, su PDF, la decisión del
-- cliente y la conversión en servicio o venta son los comandos auditados de
-- Trabajos. La bandeja la lista junto a las del sitio, con su estado leído
-- como el de la bandeja:
--
--   pendiente sin líneas          → por confirmar (falta cotizarla)
--   pendiente con líneas          → oferta enviada (espera al cliente)
--   pendiente con la vigencia ida → vencida (igual que mechanic_job_mode_view)
--   aprobada, o ya convertida     → aceptada
--   rechazada                     → rechazada
--
-- Un presupuesto (flujo `quotation` con bicicleta recibida) no entra: es la
-- aprobación de la reparación de una bici que está en el taller, el paso
-- normal de casi todo servicio (138 convertidos al 2026-11-02), y vive en
-- Trabajos. Un trabajo eliminado o archivado tampoco entra.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function public.customer_quote_inbox_v1(
  p_tenant_id uuid,
  p_status text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  return (
    with web as (
      select q.id, q.quote_number as number, q.status, q.source,
             q.customer_name as "customerName", q.preferred_channel as "preferredChannel",
             q.requested_at as "requestedAt", q.updated_at as "updatedAt",
             q.expires_at as "expiresAt",
             (select count(*) from public.customer_quote_lines l where l.quote_id = q.id) as lines,
             (select o.total from public.customer_quote_offers o where o.id = q.current_offer_id) as total,
             (select count(*) from public.customer_quote_supplier_tasks t
               where t.quote_id = q.id and t.status = 'open') as "openTasks",
             (select min(t.due_at) from public.customer_quote_supplier_tasks t
               where t.quote_id = q.id and t.status = 'open') as "nextDueAt",
             false as converted
        from public.customer_quotes q
       where q.tenant_id = p_tenant_id
    ),
    workshop_jobs as (
      select j.id, j.tenant_id, j.customer_id, j.job_number, j.workflow_kind,
             j.quotation_status, j.quotation_valid_until, j.total_cost,
             j.created_at, j.updated_at,
             (select count(*) from public.mechanic_job_items i
               where i.job_id = j.id and i.tenant_id = j.tenant_id) as item_count
        from public.mechanic_jobs j
       where j.tenant_id = p_tenant_id
         and j.deleted_at is null
         and j.archive_reason is null
         and (
           (j.workflow_kind = 'quotation' and j.intake_kind is distinct from 'bike')
           or exists (
             select 1 from public.mechanic_job_mode_events e
              where e.tenant_id = j.tenant_id and e.job_id = j.id
                and e.event_type = 'converted_to_billable'
                and e.from_workflow_kind = 'quotation'
                and e.from_intake_kind is distinct from 'bike'
           )
         )
    ),
    workshop as (
      select w.id, w.job_number as number,
             case
               when w.workflow_kind is distinct from 'quotation' then 'accepted'
               when w.quotation_status = 'approved' then 'accepted'
               when w.quotation_status = 'rejected' then 'rejected'
               when w.quotation_status = 'expired' then 'expired'
               when w.quotation_valid_until < now() then 'expired'
               when w.item_count = 0 then 'confirming'
               else 'offered'
             end as status,
             'workshop'::text as source,
             coalesce(nullif(btrim(c.name), ''), 'Sin cliente') as "customerName",
             null::text as "preferredChannel",
             w.created_at as "requestedAt", w.updated_at as "updatedAt",
             case when w.workflow_kind = 'quotation' and w.quotation_status = 'pending'
                  then w.quotation_valid_until end as "expiresAt",
             w.item_count as lines,
             w.total_cost as total,
             0::bigint as "openTasks",
             null::timestamptz as "nextDueAt",
             (w.workflow_kind is distinct from 'quotation') as converted
        from workshop_jobs w
        left join public.customers c on c.id = w.customer_id and c.tenant_id = w.tenant_id
    ),
    all_quotes as (
      select * from web
      union all
      select * from workshop
    )
    select jsonb_build_object(
      'counts', (
        select coalesce(jsonb_object_agg(s.status, s.n), '{}'::jsonb)
          from (select a.status, count(*) as n from all_quotes a group by a.status) s
      ),
      'quotes', coalesce((
        select jsonb_agg(to_jsonb(r) order by r."updatedAt" desc)
          from (
            select a.* from all_quotes a
             where p_status is null or a.status = p_status
             order by a."updatedAt" desc
             limit greatest(1, least(coalesce(p_limit, 50), 200))
            offset greatest(0, coalesce(p_offset, 0))
          ) r
      ), '[]'::jsonb)
    )
  );
end;
$$;

revoke all on function public.customer_quote_inbox_v1(uuid, text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_inbox_v1(uuid, text, integer, integer) to authenticated;

commit;
