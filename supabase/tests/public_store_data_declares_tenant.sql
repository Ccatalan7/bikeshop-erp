begin;

select plan(4);

-- La tienda sólo acepta la proyección pública si declara el tenant pedido
-- (WebsiteService._validatedPublicStorePayload, la precarga de index.html y el
-- worker del borde). Sin él se descartaba en cada carga (20260924030000).

insert into public.tenants (id, shop_name, subdomain, is_active)
values
  ('9d0c0000-0000-4000-8000-000000000001', 'Tienda activa', 'tienda-activa-ptd', true),
  ('9d0c0000-0000-4000-8000-000000000002', 'Tienda inactiva', 'tienda-inactiva-ptd', false);

select is(
  (public.get_public_store_data('9d0c0000-0000-4000-8000-000000000001')::jsonb) ->> 'tenant_id',
  '9d0c0000-0000-4000-8000-000000000001',
  'un tenant activo declara su identidad'
);

select ok(
  (public.get_public_store_data('9d0c0000-0000-4000-8000-000000000001')::jsonb) ?& array['settings', 'blocks', 'home_page_id'],
  'la forma que consume la tienda sigue completa'
);

select ok(
  not ((public.get_public_store_data('9d0c0000-0000-4000-8000-000000000002')::jsonb) ? 'tenant_id'),
  'un tenant inactivo no declara identidad y la tienda lo rechaza'
);

select ok(
  has_function_privilege('anon', 'public.get_public_store_data(uuid)', 'EXECUTE'),
  'anónimo la sigue ejecutando'
);

select * from finish();
rollback;
