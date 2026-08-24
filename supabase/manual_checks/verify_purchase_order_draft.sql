-- El contrato del pedido, comprobado sin escribir.
--
-- La lectura de verificación corre en `BEGIN READ ONLY`: guardar un pedido de
-- prueba ahí es imposible por diseño, y está bien —no queremos folios de
-- prueba en producción—. Lo que sí se comprueba acá es todo lo que decide si
-- la función es correcta antes de que escriba: que exista con su firma, que
-- sea `security definer`, quién puede ejecutarla, y que sus compuertas
-- rechacen lo que tienen que rechazar (todas disparan antes del primer
-- INSERT). La escritura real se ejerce desde la app.
select
  proname funcion,
  provolatile = 'v' es_volatil,
  prosecdef es_security_definer,
  pg_get_function_identity_arguments(oid) firma,
  has_function_privilege('authenticated', oid, 'EXECUTE') puede_authenticated,
  has_function_privilege('anon', oid, 'EXECUTE') puede_anon
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in ('save_purchase_order_draft_v1', 'mark_purchase_order_sent_v1')
order by proname;

select set_config(
  'request.jwt.claim.sub',
  (select up.user_id::text
     from public.user_profiles up
    where up.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and up.user_id is not null
      and up.role in ('owner', 'admin', 'manager')
    order by case up.role when 'owner' then 1 when 'admin' then 2 else 3 end,
             up.created_at asc nulls last
    limit 1),
  true
) as actor_fijado;
select set_config('request.jwt.claim.role', 'authenticated', true) as rol_fijado;

-- Las compuertas rechazan antes de escribir. Se llaman dentro de una
-- subconsulta que atrapa el error por su código: si alguna dejara pasar el
-- caso, el INSERT fallaría por sólo-lectura y esta comprobación lo delataría
-- igual, con otro código.
select
  public.purchase_order_guard_probe_v1() as compuertas;
