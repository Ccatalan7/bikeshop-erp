-- Devuelve los stubs fail-closed que la app instalada necesita.
--
-- **Mi error.** `20260830060000` retiró las firmas de 7 y 8 argumentos creyendo
-- que eran overloads muertos del contrato viejo. No lo eran: `20260829160000`
-- las había recreado **a propósito** como stubs `immutable` que responden
-- `client_upgrade_required` sin insertar nada, porque desplegar este backend
-- con la app anterior en los equipos «es el caso normal, no el excepcional».
--
-- Sin ellos, esa app instalada deja de recibir una respuesta ordenada y pasa a
-- un error de función inexistente: se rompe un flujo que estaba diseñado para
-- degradar en silencio y dejar el portal «sin consultar».
--
-- Lo que sí había que arreglar —y se mantiene— es la firma de 12 argumentos:
-- ésa competía de verdad con la de 13 por el `default` de `p_operation_key`, y
-- es la que producía `42725 is not unique`. Los stubs de 7 y 8 no compiten con
-- nadie: ninguna llamada de 13 argumentos puede resolverse contra ellos.

begin;

create or replace function public.record_supplier_need_portal_search_v1(
  p_supplier_id uuid,
  p_supply_need_id uuid,
  p_search_query text,
  p_status text,
  p_source_url text,
  p_results jsonb,
  p_evidence jsonb
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'status', 'client_upgrade_required',
    'recorded', false,
    'reason', 'La app instalada no puede declarar qué ficha estaba '
      || 'respondiendo esta lectura.'
  );
$$;

create or replace function public.record_supplier_need_portal_search_v1(
  p_supplier_id uuid,
  p_supply_need_id uuid,
  p_search_query text,
  p_status text,
  p_source_url text,
  p_results jsonb,
  p_evidence jsonb,
  p_coverage jsonb
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'status', 'client_upgrade_required',
    'recorded', false,
    'reason', 'La app instalada no puede declarar qué ficha estaba '
      || 'respondiendo esta lectura.'
  );
$$;

revoke all on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
) to authenticated;

revoke all on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
) to authenticated;

comment on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
) is
  'Stub fail-closed para la app instalada: responde client_upgrade_required y no inserta nada, para que un portal quede «sin consultar» en vez de guardar una lectura que nadie puede fechar contra una ficha.';

comment on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
) is
  'Stub fail-closed para la app instalada: responde client_upgrade_required y no inserta nada, para que un portal quede «sin consultar» en vez de guardar una lectura que nadie puede fechar contra una ficha.';

commit;
