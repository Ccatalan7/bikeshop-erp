begin;

select plan(6);

select is(
  (select value from public.website_settings
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and key = 'contact_email'),
  'contacto@vinabike.cl',
  'general public contact uses the domain mailbox'
);

select is(
  (select value from public.website_settings
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and key = 'seo_email'),
  'contacto@vinabike.cl',
  'structured public contact uses the domain mailbox'
);

select is(
  (select value from public.website_settings
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and key = 'payment_transfer_contact_email'),
  'ventas@vinabike.cl',
  'bank transfer instructions use the sales mailbox'
);

select ok(
  exists (
    select 1
    from public.website_pages page
    join public.website_blocks block on block.page_id = page.id
    where page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and page.slug = 'devoluciones'
      and block.block_data::text like '%ventas@vinabike.cl%'
  ),
  'returns policy directs customers to the sales mailbox'
);

select ok(
  not exists (
    select 1
    from public.website_pages page
    join public.website_blocks block on block.page_id = page.id
    where page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and page.slug = 'devoluciones'
      and block.block_data::text like '%contacto@vinabike.cl%'
  ),
  'returns policy has no stale general-contact address'
);

select ok(
  not exists (
    select 1
    from public.website_settings
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
      and key in ('contact_email', 'seo_email', 'payment_transfer_contact_email')
      and lower(coalesce(value, '')) = 'vinabikechile@gmail.com'
  ),
  'public commerce settings no longer expose the legacy Gmail address'
);

select * from finish();

rollback;
