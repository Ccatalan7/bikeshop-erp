-- El comprobante de entrega lleva lo que pidió el cliente y el diagnóstico
-- (2026-11-04).
--
-- 20261104200000 armaba la foto del trabajo con «trabajo realizado», y en
-- producción ese campo casi no se llena: de los últimos 200 trabajos entregados
-- de Viñabike, 2 lo tienen, 127 tienen la solicitud del cliente y 19 el
-- diagnóstico. El portal ya le muestra al cliente las dos cosas en su trabajo
-- («Lo que pediste», «Diagnóstico»), así que el comprobante las guarda igual.
-- Todavía no hay comprobantes armados: nada que rehacer.
--
-- Igual que la versión de 20261104200000 salvo las dos claves nuevas.

create or replace function public.job_delivery_document_snapshot_internal(
  p_tenant_id uuid,
  p_job_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'job_number', job.job_number,
    'customer', jsonb_build_object('name', nullif(trim(customer.name), '')),
    'client_request', nullif(trim(job.client_request), ''),
    'diagnosis', nullif(trim(job.diagnosis), ''),
    'work_performed', nullif(trim(job.work_performed), ''),
    'subject_notes', nullif(trim(job.subject_notes), ''),
    'bikes', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'job_bike_id', job_bike.id,
            'brand', nullif(trim(bike.brand), ''),
            'model', nullif(trim(bike.model), ''),
            'year', bike.year,
            'color', nullif(trim(bike.color), ''),
            'serial_number', nullif(trim(bike.serial_number), ''),
            'work_requested', nullif(trim(job_bike.work_requested), ''),
            'work_performed', nullif(trim(job_bike.work_performed), '')
          )
          order by job_bike.order_index, job_bike.created_at
        )
          from public.mechanic_job_bikes job_bike
          left join public.bikes bike
            on bike.id = job_bike.bike_id
           and bike.tenant_id = job_bike.tenant_id
         where job_bike.tenant_id = job.tenant_id
           and job_bike.job_id = job.id
      ),
      (
        select jsonb_build_array(
          jsonb_build_object(
            'job_bike_id', null,
            'brand', nullif(trim(bike.brand), ''),
            'model', nullif(trim(bike.model), ''),
            'year', bike.year,
            'color', nullif(trim(bike.color), ''),
            'serial_number', nullif(trim(bike.serial_number), ''),
            'work_requested', nullif(trim(job.client_request), ''),
            'work_performed', nullif(trim(job.work_performed), '')
          )
        )
          from public.bikes bike
         where bike.id = job.bike_id
           and bike.tenant_id = job.tenant_id
      ),
      '[]'::jsonb
    ),
    'lines', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'kind', case item.item_type
              when 'service' then 'service'
              when 'product' then 'part'
              else 'other'
            end,
            'name', coalesce(
              nullif(trim(item.product_name), ''),
              nullif(trim(item.description), '')
            ),
            'quantity', item.quantity,
            'job_bike_id', item.job_bike_id
          )
          order by item.created_at, item.id
        )
          from public.mechanic_job_items item
         where item.tenant_id = job.tenant_id
           and item.job_id = job.id
      ),
      '[]'::jsonb
    )
  )
    from public.mechanic_jobs job
    left join public.customers customer
      on customer.id = job.customer_id
     and customer.tenant_id = job.tenant_id
   where job.tenant_id = p_tenant_id
     and job.id = p_job_id;
$$;

revoke all on function public.job_delivery_document_snapshot_internal(uuid, uuid)
  from public, anon, authenticated, service_role;
