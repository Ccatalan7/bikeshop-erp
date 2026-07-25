-- Deployment status: APPLIED in production; migration history confirms
-- 20260718250000. The tenant-existence guard keeps canonical empty-local
-- bootstrap idempotent without changing production behavior.
--
-- Keep public contact and sales operations on the verified Viñabike domain.
-- General/privacy correspondence stays on contacto@; order, payment and return
-- operations use ventas@. The update is tenant-scoped and idempotent.

insert into public.website_settings (
  tenant_id, key, value, description, updated_at
)
select
  seed.tenant_id,
  seed.key,
  seed.value,
  seed.description,
  now()
from (
  values
    (
      '5443b130-cc28-45af-a420-cd500b288890'::uuid,
      'contact_email',
      'contacto@vinabike.cl',
      'Email público general y de privacidad'
    ),
    (
      '5443b130-cc28-45af-a420-cd500b288890'::uuid,
      'seo_email',
      'contacto@vinabike.cl',
      'Email público general para metadatos y datos estructurados'
    ),
    (
      '5443b130-cc28-45af-a420-cd500b288890'::uuid,
      'payment_transfer_contact_email',
      'ventas@vinabike.cl',
      'Email de pedidos y validación de transferencias'
    )
) as seed(tenant_id, key, value, description)
where exists (
  select 1
  from public.tenants tenant
  where tenant.id = seed.tenant_id
)
on conflict (tenant_id, key) do update
set
  value = excluded.value,
  description = excluded.description,
  updated_at = case
    when public.website_settings.value is distinct from excluded.value
      or public.website_settings.description is distinct from excluded.description
    then now()
    else public.website_settings.updated_at
  end;

update public.website_blocks block
set
  block_data = replace(
    block.block_data::text,
    'contacto@vinabike.cl',
    'ventas@vinabike.cl'
  )::jsonb,
  updated_at = now()
from public.website_pages page
where page.id = block.page_id
  and page.tenant_id = block.tenant_id
  and page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
  and page.slug = 'devoluciones'
  and block.block_data::text like '%contacto@vinabike.cl%';
