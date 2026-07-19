begin;

select plan(13);

select has_function(
  'public',
  'website_setting_is_sensitive',
  array['text'],
  'website setting secret classifier exists'
);
select ok(
  public.website_setting_is_sensitive('mercadopago_access_token'),
  'access tokens are sensitive'
);
select ok(
  public.website_setting_is_sensitive('mercadopago_webhook_secret'),
  'webhook secrets are sensitive'
);
select ok(
  public.website_setting_is_sensitive('google_places_api_key'),
  'API keys are sensitive by default'
);
select ok(
  not public.website_setting_is_sensitive('mercadopago_public_key'),
  'explicit public provider keys remain readable'
);
select ok(
  not public.website_setting_is_sensitive('contact_email'),
  'ordinary storefront settings remain readable'
);

select ok(
  not has_table_privilege('anon', 'public.website_settings', 'TRUNCATE'),
  'anonymous users cannot truncate settings'
);
select ok(
  not has_table_privilege('anon', 'public.website_settings', 'UPDATE'),
  'anonymous users cannot update settings'
);
select ok(
  not has_table_privilege('authenticated', 'public.website_settings', 'TRUNCATE'),
  'authenticated users cannot bypass RLS with truncate'
);
select ok(
  has_table_privilege('anon', 'public.website_settings', 'SELECT'),
  'anonymous storefronts retain SELECT privilege'
);

insert into public.tenants (id, shop_name, currency, timezone)
values (
  '9e270000-0000-4000-8000-000000000001',
  'Website Settings Security Test',
  'CLP',
  'America/Santiago'
);

insert into public.website_settings (tenant_id, key, value)
values
  (
    '9e270000-0000-4000-8000-000000000001',
    'contact_email',
    'public@example.test'
  ),
  (
    '9e270000-0000-4000-8000-000000000001',
    'mercadopago_access_token',
    'must-never-be-visible'
  )
on conflict (tenant_id, key) do update
set value = excluded.value;

set local role anon;

select is(
  (
    select value
    from public.website_settings
    where tenant_id = '9e270000-0000-4000-8000-000000000001'
      and key = 'contact_email'
  ),
  'public@example.test',
  'anonymous storefront can read an ordinary tenant setting'
);
select is(
  (
    select count(*)::integer
    from public.website_settings
    where tenant_id = '9e270000-0000-4000-8000-000000000001'
      and key = 'mercadopago_access_token'
  ),
  0,
  'anonymous storefront cannot read the provider access token'
);

reset role;
set local role authenticated;

select is(
  (
    select count(*)::integer
    from public.website_settings
    where tenant_id = '9e270000-0000-4000-8000-000000000001'
      and key = 'mercadopago_access_token'
  ),
  0,
  'ordinary authenticated clients cannot read the provider access token'
);

reset role;

select * from finish();

rollback;
