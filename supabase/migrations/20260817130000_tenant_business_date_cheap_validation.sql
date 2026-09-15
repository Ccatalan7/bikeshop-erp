-- `tenant_business_date` deja de escanear el catálogo de zonas horarias.
--
-- La función valida la zona del tenant preguntándole a
-- `pg_catalog.pg_timezone_names` si existe. Esa vista tiene 1.194 filas, no
-- tiene índice y se recorre entera en **cada llamada**.
--
-- Medición sobre producción (2026-08-17), 100 llamadas con argumento variable
-- —que es como la llaman las vistas, con una columna—:
--
--   · función actual ................................ ~67 ms por llamada
--   · el mismo cálculo sin el chequeo del catálogo ... ~6 ms por llamada
--
-- El escaneo del catálogo es el 90% del costo. Con argumento **constante** no
-- se nota, porque al ser STABLE el planificador la evalúa una vez: por eso el
-- problema sólo aparece donde importa, en una vista que la llama por fila.
--
-- El caso que lo destapó: `purchase_candidate_metrics_v1` la invoca tres veces
-- por fila —dos en el EXISTS de `is_confirmed_local`, una en
-- `evidence_age_days`— para los 267 candidatos del taller real. 267 × 3 × 67 ms
-- ≈ 54 s, contra el `statement_timeout` de 4,5 s del ranking. Esta función la
-- usan además lecturas del asistente, gastos y proveedores: el ahorro no es de
-- un módulo.
--
-- El chequeo es innecesario, no sólo caro: `at time zone` **ya valida** la zona
-- y lanza `invalid_parameter_value` si no la reconoce. Se captura y se vuelve a
-- lanzar con el mismo mensaje y el mismo SQLSTATE que antes, así que ningún
-- llamador nota la diferencia salvo en el tiempo.
--
-- Semántica preservada, punto por punto: mismo resultado para una zona válida;
-- mismo error 22023 «Tenant timezone is invalid» para una inválida; mismos
-- errores de tenant nulo, membresía y tenant inexistente, y en el mismo orden.

begin;

create or replace function public.tenant_business_date(
  p_tenant_id uuid,
  p_at timestamptz default statement_timestamp()
)
returns date
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_timezone text;
begin
  if p_tenant_id is null then
    raise exception 'Tenant id is required for business date'
      using errcode = '22023';
  end if;

  if v_role <> 'service_role'
     and not (
       v_role = ''
       and session_user in ('postgres', 'supabase_admin')
     )
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;

  select coalesce(
    nullif(btrim(tenant.timezone), ''),
    'America/Santiago'
  )
  into v_timezone
  from public.tenants tenant
  where tenant.id = p_tenant_id;

  if not found then
    raise exception 'Tenant not found for business date'
      using errcode = 'P0002';
  end if;

  -- La validación la hace el propio cast. Preguntarle antes al catálogo costaba
  -- un escaneo de 1.194 filas por llamada para no enterarse de nada nuevo.
  begin
    return (coalesce(p_at, statement_timestamp()) at time zone v_timezone)::date;
  exception
    when invalid_parameter_value or invalid_datetime_format then
      raise exception 'Tenant timezone is invalid'
        using errcode = '22023';
  end;
end;
$$;

comment on function public.tenant_business_date(uuid, timestamptz) is
  'Single server-owned effective-date boundary for tenant business rules. It resolves statement time in the tenant IANA timezone, defaults null/blank legacy values to America/Santiago, and fails closed for invalid configured zones. Zone validity comes from the conversion itself: probing pg_timezone_names cost a 1194-row scan per call.';

revoke all on function public.tenant_business_date(uuid, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.tenant_business_date(uuid, timestamptz)
  to authenticated, service_role;

commit;
