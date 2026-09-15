-- El recuento de la fila cuenta lo de ESA necesidad; el barrido va aparte.
--
-- Se compara el mismo proveedor con y sin alcance: sin alcance sale el barrido
-- entero, con alcance sale sólo el producto por el que se preguntó. Si los dos
-- dieran igual, la corrección no estaría haciendo nada.
select set_config(
  'request.jwt.claim.sub',
  (select up.user_id::text from public.user_profiles up
    where up.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and up.user_id is not null and up.role in ('owner','admin','manager')
    order by case up.role when 'owner' then 1 when 'admin' then 2 else 3 end,
             up.created_at asc nulls last limit 1),
  true) as actor;
select set_config('request.jwt.claim.role', 'authenticated', true) as rol;

with proveedor as (
  select s.id from public.suppliers s
  where s.tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and s.name = 'RBX'
  limit 1
), uno as (
  select c.product_id from public.supplier_availability_checks c
  join proveedor on proveedor.id = c.supplier_id
  where c.product_id is not null
  limit 1
)
select
  (public.supplier_last_availability_v1((select id from proveedor))
    -> 'summary' ->> 'checked')::int barrido_completo,
  (public.supplier_last_availability_v1((select id from proveedor))
    -> 'summary' ->> 'scoped')::boolean barrido_sin_alcance,
  (public.supplier_last_availability_v1(
      (select id from proveedor), 12,
      array[(select product_id from uno)])
    -> 'summary' ->> 'checked')::int con_alcance_de_uno,
  (public.supplier_last_availability_v1(
      (select id from proveedor), 12,
      array[(select product_id from uno)])
    -> 'summary' ->> 'sweptProducts')::int barrido_sigue_visible;
