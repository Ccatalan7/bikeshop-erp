-- Read-back de `20260830180000_legacy_transport_for_origin`.

-- 1. La frontera existe, es de sólo lectura y `anon` no la alcanza.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as frontera_de_solo_lectura
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'supplier_legacy_transport_for_origin_v1'
  and p.provolatile = 's'
  and p.prosecdef;

select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as anon_no_puede_leer_el_transporte
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'supplier_legacy_transport_for_origin_v1'
  and grantee in ('anon', 'PUBLIC');

-- 2. **No entrega nada del secreto.** Se afirma sobre el cuerpo real: sólo
--    puede nombrar las dos claves del transporte, y ninguna de identidad.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as no_expone_identidad_ni_secreto
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'supplier_legacy_transport_for_origin_v1'
  and pg_get_functiondef(p.oid) like '%sessionLoginUrl%'
  and pg_get_functiondef(p.oid) not like '%vault_secret_id%'
  and pg_get_functiondef(p.oid) not like '%credential_key%'
  and pg_get_functiondef(p.oid) not like '%username%';

-- 3. La ruta real se resuelve. Sin contexto de negocio muere en 42501, que es
--    la guarda de tenant; si muriera en 42725 o 42883 no existiría.
explain (costs off)
select public.supplier_legacy_transport_for_origin_v1(
  'https://portal.rburgos.cl'
);

-- 4. Y la declaración que tiene que encontrar sigue en su lugar, unida por
--    tenant y proveedor —que es como la función la busca—.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as la_union_encuentra_a_rbx
from public.supplier_credentials credential
join public.supplier_portal_probes probe
  on probe.tenant_id = credential.tenant_id
 and probe.supplier_id = credential.supplier_id
where credential.origin_url = 'https://portal.rburgos.cl'
  and probe.is_enabled
  and probe.session_login_legacy -> 'page_urls'
      @> '["https://portal.rburgos.cl/login/"]'::jsonb
  and probe.session_login_legacy ->> 'action_url'
      = 'http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp';
