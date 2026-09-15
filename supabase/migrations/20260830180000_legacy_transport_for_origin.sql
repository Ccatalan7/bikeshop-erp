-- Leer el transporte declarado de un portal sin acercarse a su secreto.
--
-- **Por qué hace falta.** El cliente necesita saber si el origen canónico de
-- una página tiene transporte legacy declarado. Consultar `supplier_credentials`
-- desde la app no funciona ni debe: esa tabla tiene `revoke all` para
-- `authenticated` —guarda identidad y `vault_secret_id`— y la relación hacia
-- `supplier_portal_probes` es entre hermanas, no directa, así que ni siquiera
-- se puede embeber. Un intento así cae al catch y devuelve `null` en silencio,
-- que es exactamente por qué el autofill seguía sin dispararse.
--
-- **Lo que esta frontera entrega.** Sólo lo que describe el transporte del
-- portal: `session_login_url` y `session_login_legacy`. Ni username, ni
-- `vault_secret_id`, ni `credential_key`. La credencial se sigue resolviendo
-- por el camino protegido de siempre, contra el mismo origen canónico.
--
-- Y el alcance es del tenant: la función parte de `user_tenant_id()`, así que
-- un origen de otro negocio no devuelve nada.

begin;

create or replace function public.supplier_legacy_transport_for_origin_v1(
  p_canonical_origin text
)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to 'pg_catalog', 'public', 'pg_temp'
 set statement_timeout to '5000ms'
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_origin text := nullif(btrim(coalesce(p_canonical_origin, '')), '');
  v_row record;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  -- Sólo un origen HTTPS puede preguntar: la excepción degrada el esquema de un
  -- portal registrado, nunca habilita uno nuevo.
  if v_origin is null
     or octet_length(v_origin) > 200
     or v_origin !~ '^https://[A-Za-z0-9.-]+$' then
    return jsonb_build_object('status', 'not_declared');
  end if;

  select probe.session_login_url as login_url,
         probe.session_login_legacy as legacy
  into v_row
  from public.supplier_credentials credential
  join public.supplier_portal_probes probe
    on probe.tenant_id = credential.tenant_id
   and probe.supplier_id = credential.supplier_id
  where credential.tenant_id = v_tenant_id
    and credential.origin_url = v_origin
    and probe.is_enabled
    and probe.session_login_legacy is not null
  limit 1;

  if not found then
    return jsonb_build_object('status', 'not_declared');
  end if;

  return jsonb_build_object(
    'status', 'declared',
    'sessionLoginUrl', v_row.login_url,
    'legacy', v_row.legacy
  );
end;
$function$
;

revoke all on function
  public.supplier_legacy_transport_for_origin_v1(text) from public, anon;
grant execute on function
  public.supplier_legacy_transport_for_origin_v1(text) to authenticated;

comment on function public.supplier_legacy_transport_for_origin_v1(text) is
  'Devuelve el transporte legacy declarado de un portal para un origen HTTPS canónico del tenant. Entrega sólo session_login_url y session_login_legacy: nunca username, credential_key ni vault_secret_id.';

commit;
