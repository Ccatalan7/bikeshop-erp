-- El comprobante de entrega lleva el membrete de la tienda (2026-11-04).
--
-- El PDF del comprobante se dibuja, como la oferta de una cotización, desde lo
-- que ve el cliente: el ERP con ensure_job_delivery_document_v1 y el portal con
-- list_my_job_delivery_documents_v1. Le faltaba el membrete —nombre, contacto—
-- y la dirección de la tienda, que es adonde apunta el QR para crear la
-- cuenta. Salen de la misma regla que la oferta (storefront_identity_internal
-- y `store_url` del editor del sitio), no de un texto escrito en el ERP.
--
-- Igual que la versión de 20261104200000 salvo `storefront`.

create or replace function public.job_delivery_document_projection_internal(p_document_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', document.id,
    'job_id', document.job_id,
    'job_number', document.job_number,
    'delivered_at', document.delivered_at,
    'service_warranty_days', document.service_warranty_days,
    'service_warranty_expires_at',
      coalesce(warranty.warranty_expires_at, document.service_warranty_expires_at),
    'service_warranty_days_remaining', greatest(
      ceil(extract(epoch from (
        coalesce(warranty.warranty_expires_at, document.service_warranty_expires_at)
        - clock_timestamp()
      )) / 86400.0),
      0
    )::integer,
    'parts_warranty_months', document.parts_warranty_months,
    'parts_warranty_expires_at', document.parts_warranty_expires_at,
    'parts_warranty_days_remaining', greatest(
      ceil(extract(epoch from (document.parts_warranty_expires_at - clock_timestamp())) / 86400.0),
      0
    )::integer,
    'invoice_id', job.invoice_id,
    'snapshot', document.snapshot,
    -- El membrete y la dirección de la tienda, de la misma regla que la
    -- oferta de una cotización: lo que la tienda ya publica.
    'storefront', public.storefront_identity_internal(document.tenant_id)
      || jsonb_strip_nulls(jsonb_build_object('storeUrl', (
           select nullif(btrim(setting.value), '')
             from public.website_settings setting
            where setting.tenant_id = document.tenant_id
              and setting.key = 'store_url'
         )))
  )
    from public.mechanic_job_delivery_documents document
    join public.mechanic_jobs job
      on job.id = document.job_id
     and job.tenant_id = document.tenant_id
    left join public.mechanic_job_service_warranty_view warranty
      on warranty.job_id = document.job_id
     and warranty.tenant_id = document.tenant_id
   where document.id = p_document_id;
$$;

revoke all on function public.job_delivery_document_projection_internal(uuid)
  from public, anon, authenticated, service_role;
