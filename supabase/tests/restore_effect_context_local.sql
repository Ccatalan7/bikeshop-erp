-- R1 del restore completo (Master Schema, cola ítem 3; 2026-09-30): un
-- contexto privado de reposición que un disparador real con efectos pueda
-- consumir, empezando por `handle_sales_invoice_change` y su contabilización.
--
-- Sólo local y transaccional (`bash scripts/db/test.sh restore_effect_context_local`):
-- el candidato (tabla, funciones y el disparador parcheado) se crea dentro de
-- esta transacción y desaparece con el ROLLBACK. No toca el motor legado ni
-- la purga: la negativa vigente del restore sigue igual. No se apagan
-- disparadores, RLS ni validadores, ni se usa `session_replication_role`. Sin
-- mensajes, productos ni pedidos (los disparadores que llaman `net.http_*`);
-- si la base tiene secretos en vault (producción), se detiene antes de escribir.
--
-- Contrato del candidato (v2):
-- * `restore_replay_authorizations`: privada, RLS sin políticas, sin grants a
--   anon/authenticated/service_role. Una fila autoriza UNA operación
--   (`insert`) de UNA fila de UNA tabla de UN taller, en la transacción
--   (`txid_current()`) y la sentencia de nivel superior
--   (`statement_timestamp()`) que la abrió.
-- * `restore_replay_authorize_internal` la abre (el motor, en su misma
--   llamada); `restore_replay_consume_internal` la consume una vez desde el
--   disparador; `restore_replay_close_internal` retira lo que no se usó.
--   Ninguna se puede ejecutar desde la API. Ninguna mira current_user, claims
--   ni variables de sesión: el disparador es SECURITY DEFINER y ahí
--   current_user es siempre su dueño.
-- * El disparador sólo omite los efectos de INSERT de una fila autorizada
--   (contabilizar, consumir inventario, recalcular pagos y sincronizar el
--   trabajo): la fila repuesta trae el estado del respaldo. BEFORE, UPDATE,
--   DELETE, constraints y validadores siguen iguales.
--
-- La prueba muestra por qué hace falta cada parte: v0 (marca por transacción)
-- se escapa a otro taller; v1 (por fila) deja que otra sentencia de la misma
-- transacción, aun como authenticated, use una autorización que no puede
-- abrir; v2 (atada a la sentencia) lo corrige.
--
-- Fuera de este corte: stock y pedidos (reserva/consumo en otros disparadores
-- de ventas y pedidos), push de mensajes, sincronización del catálogo de
-- WhatsApp, realtime/broadcast, trazas de inventario y contabilidad, garantía
-- de servicio, pagos (`handle_sales_payment_change`) y el cableado en el motor.
begin;

select no_plan();

-- Nunca en una base con secretos (producción): ahí un efecto externo sería real.
do $guard$
begin
  if exists (select 1 from vault.secrets) then
    raise exception 'restore_effect_context_local: sólo en la base local';
  end if;
end;
$guard$;

create temporary table net_queue_before as
  select count(*) as n from net.http_request_queue;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2894000-0000-4000-8000-0000000000' || p_n)::uuid $$;

-- A y B: talleres con sus cuentas sembradas. C: sin 1130/2150/4100, para que
-- se vea si una contabilización las crea.
insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Reposición A'),
  (pg_temp.id('02'), 'Reposición B'),
  (pg_temp.id('03'), 'Reposición C');
-- El alta del taller deja su id como `sub` (SUPABASE_WORKFLOW.md).
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated', 'replay-a@example.invalid',
   '', now(), '{}', '{}', now(), now()),
  (pg_temp.id('92'), 'authenticated', 'authenticated', 'replay-b@example.invalid',
   '', now(), '{}', '{}', now(), now()),
  (pg_temp.id('93'), 'authenticated', 'authenticated', 'replay-c@example.invalid',
   '', now(), '{}', '{}', now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin'),
  (pg_temp.id('92'), pg_temp.id('02'), 'admin'),
  (pg_temp.id('93'), pg_temp.id('03'), 'admin');
delete from public.accounts
 where tenant_id = pg_temp.id('03') and code in ('1130', '2150', '4100');

-- ============================================================================
-- El candidato, sólo dentro de esta transacción
-- ============================================================================
create table public.restore_replay_authorizations (
  txid bigint not null,
  statement_started_at timestamptz not null,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  table_name text not null check (table_name in ('sales_invoices')),
  row_id uuid not null,
  operation text not null check (operation in ('insert')),
  primary key (txid, table_name, row_id, operation)
);
alter table public.restore_replay_authorizations enable row level security;
revoke all on table public.restore_replay_authorizations
  from public, anon, authenticated, service_role;

create function public.restore_replay_authorize_internal(
  p_tenant_id uuid,
  p_table text,
  p_row_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_count integer;
begin
  if p_tenant_id is null or p_table is null or p_row_ids is null
     or cardinality(p_row_ids) = 0 or array_position(p_row_ids, null) is not null then
    raise exception 'restore replay: taller, tabla y filas son obligatorios'
      using errcode = '22023';
  end if;
  insert into public.restore_replay_authorizations(
    txid, statement_started_at, tenant_id, table_name, row_id, operation)
  select txid_current(), statement_timestamp(), p_tenant_id, p_table, row_id, 'insert'
    from unnest(p_row_ids) as row_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create function public.restore_replay_close_internal(p_tenant_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_count integer;
begin
  delete from public.restore_replay_authorizations a
   where a.txid = txid_current()
     and a.tenant_id = p_tenant_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- v0: la marca por transacción sola (lo que NO basta).
create function public.restore_replay_consume_internal(
  p_tenant_id uuid,
  p_table text,
  p_row_id uuid,
  p_operation text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  return exists (select 1 from public.restore_replay_authorizations a
                  where a.txid = txid_current());
end;
$$;

revoke all on function public.restore_replay_authorize_internal(uuid, text, uuid[])
  from public, anon, authenticated, service_role;
revoke all on function public.restore_replay_close_internal(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_replay_consume_internal(uuid, text, uuid, text)
  from public, anon, authenticated, service_role;

-- El disparador real, con el mismo cuerpo y una sola adición anclada al
-- comienzo de su rama INSERT (como el patrón de 20260928140000).
do $do$
declare
  v_def text := pg_get_functiondef('public.handle_sales_invoice_change()'::regprocedure);
  v_anchor constant text := $a$  if TG_OP = 'INSERT' then
$a$;
  v_block constant text := $b$    -- Reposición autorizada de un respaldo: la fila trae su propio
    -- efecto (asiento, inventario, pagos y trabajo ya están en el respaldo).
    if public.restore_replay_consume_internal(NEW.tenant_id, 'sales_invoices', NEW.id, 'insert') then
      return NEW;
    end if;
$b$;
begin
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'handle_sales_invoice_change: el ancla debe aparecer una vez';
  end if;
  execute replace(v_def, v_anchor, v_anchor || v_block);
end;
$do$;

select is(
  (select (length(def) - length(replace(def, 'restore_replay_consume_internal', '')))
          / length('restore_replay_consume_internal')
     from (select pg_get_functiondef('public.handle_sales_invoice_change()'::regprocedure) as def) f),
  1, 'el disparador real consulta el contexto una sola vez, en su rama INSERT');

-- ============================================================================
-- Ayudas: como el motor (autoriza e inserta en UNA sentencia) y como un
-- escritor normal
-- ============================================================================
create function pg_temp.act_as(p_tenant text)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', pg_temp.id('9' || right(p_tenant, 1)), 'role', 'service_role')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.id('9' || right(p_tenant, 1))::text, true);
end;
$$;

create function pg_temp.add_invoice(p_id text, p_tenant text, p_status text default 'confirmed')
returns void
language plpgsql
as $$
begin
  perform pg_temp.act_as(p_tenant);
  insert into public.sales_invoices (
    id, tenant_id, invoice_number, customer_name, status, source,
    subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment
  ) values (
    pg_temp.id(p_id), pg_temp.id(p_tenant), 'R1-' || p_tenant || '-' || p_id,
    'Cliente reposición', p_status, 'manual_sale',
    10000, 10000, 0, 10000, 0, 10000, 'no_tax'
  );
end;
$$;

create function pg_temp.authorize(p_tenant text, p_ids text[])
returns integer
language sql
as $$
  select public.restore_replay_authorize_internal(
    pg_temp.id(p_tenant), 'sales_invoices',
    array(select pg_temp.id(n) from unnest(p_ids) as n))
$$;

-- Como el motor: autoriza la fila y la repone en la misma sentencia.
create function pg_temp.replay(p_id text, p_tenant text, p_status text default 'confirmed')
returns void
language plpgsql
as $$
begin
  perform pg_temp.authorize(p_tenant, array[p_id]);
  perform pg_temp.add_invoice(p_id, p_tenant, p_status);
end;
$$;

create function pg_temp.entries(p_id text, p_tenant text)
returns integer
language sql
as $$
  select count(*)::integer from public.journal_entries entry
   where entry.tenant_id = pg_temp.id(p_tenant)
     and entry.source_module = 'sales_invoices'
     and entry.source_document_id = pg_temp.id(p_id)
$$;

-- ============================================================================
-- v0: una marca por transacción se escapa a otro taller
-- ============================================================================
select pg_temp.replay('20', '01');
select is(pg_temp.entries('20', '01'), 0, 'v0: la reposición autorizada no contabiliza');

select pg_temp.authorize('01', array['29']);
select pg_temp.add_invoice('21', '02');
select is(pg_temp.entries('21', '02'), 0,
  'v0 (defecto): con una marca abierta en A, una venta normal de B queda sin asiento');
select public.restore_replay_close_internal(pg_temp.id('01'));

-- ============================================================================
-- v1: por taller, tabla, fila y operación, consumida una vez
-- ============================================================================
create or replace function public.restore_replay_consume_internal(
  p_tenant_id uuid,
  p_table text,
  p_row_id uuid,
  p_operation text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  delete from public.restore_replay_authorizations a
   where a.txid = txid_current()
     and a.tenant_id = p_tenant_id
     and a.table_name = p_table
     and a.row_id = p_row_id
     and a.operation = p_operation;
  return found;
end;
$$;

select pg_temp.authorize('01', array['29']);
select pg_temp.add_invoice('22', '02');
select is(pg_temp.entries('22', '02'), 1, 'v1: la venta normal de B vuelve a contabilizar');
select public.restore_replay_close_internal(pg_temp.id('01'));

-- La autorización de una sentencia del motor, usada por la siguiente sentencia
-- de la misma transacción, que corre como authenticated.
select pg_temp.authorize('01', array['23']);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
set local role authenticated;
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment
) values (
  pg_temp.id('23'), pg_temp.id('01'), 'R1-01-23', 'Cliente reposición', 'confirmed',
  'manual_sale', 10000, 10000, 0, 10000, 0, 10000, 'no_tax'
);
reset role;
select is(pg_temp.entries('23', '01'), 0,
  'v1 (defecto): una sentencia posterior de authenticated usa la autorización del motor y queda sin asiento');
select public.restore_replay_close_internal(pg_temp.id('01'));

-- ============================================================================
-- v2: además atada a la sentencia que la abrió (el contrato candidato)
-- ============================================================================
create or replace function public.restore_replay_consume_internal(
  p_tenant_id uuid,
  p_table text,
  p_row_id uuid,
  p_operation text
)
returns boolean
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  delete from public.restore_replay_authorizations a
   where a.txid = txid_current()
     and a.statement_started_at = statement_timestamp()
     and a.tenant_id = p_tenant_id
     and a.table_name = p_table
     and a.row_id = p_row_id
     and a.operation = p_operation;
  return found;
end;
$$;

-- La fuga de v1, ahora cerrada.
select pg_temp.authorize('01', array['24']);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
set local role authenticated;
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment
) values (
  pg_temp.id('24'), pg_temp.id('01'), 'R1-01-24', 'Cliente reposición', 'confirmed',
  'manual_sale', 10000, 10000, 0, 10000, 0, 10000, 'no_tax'
);
reset role;
select is(pg_temp.entries('24', '01'), 1,
  'v2: la autorización de otra sentencia no sirve; la venta de authenticated contabiliza');
select is(public.restore_replay_close_internal(pg_temp.id('01')), 1,
  'v2: el cierre retira la autorización que nadie usó');

-- La reposición autorizada, en el taller sin cuentas de venta.
select pg_temp.replay('30', '03');
select is(pg_temp.entries('30', '03'), 0, 'v2: la reposición autorizada no crea asiento');
select is((select count(*)::integer from public.accounts
            where tenant_id = pg_temp.id('03') and code in ('1130', '2150', '4100')),
  0, 'v2: la reposición autorizada no crea cuentas');
select is((select count(*)::integer from public.restore_replay_authorizations
            where tenant_id = pg_temp.id('03')),
  0, 'v2: la autorización se consume al usarla');
select is((select status from public.sales_invoices
            where id = pg_temp.id('30') and tenant_id = pg_temp.id('03')),
  'confirmed', 'v2: la fila repuesta queda como la trae el respaldo');

-- La operación normal, en el mismo taller: contabiliza exactamente una vez.
select pg_temp.add_invoice('31', '03');
select is(pg_temp.entries('31', '03'), 1, 'normal: una venta contabiliza exactamente una vez');
select is((select count(*)::integer from public.accounts
            where tenant_id = pg_temp.id('03') and code in ('1130', '2150', '4100')),
  3, 'normal: y crea sus cuentas (la comparación de arriba discrimina)');

-- Alcance, dentro de UNA sentencia con el contexto abierto (como el motor).
create function pg_temp.mixed_statement()
returns void
language plpgsql
as $$
begin
  perform pg_temp.authorize('01', array['40', '43']);
  perform pg_temp.add_invoice('40', '01');   -- autorizada
  perform pg_temp.add_invoice('41', '01');   -- mismo taller, no autorizada
  perform pg_temp.add_invoice('42', '02');   -- otro taller
  perform pg_temp.add_invoice('43', '02');   -- id autorizado para A, fila de B
  perform public.restore_replay_close_internal(pg_temp.id('01'));
end;
$$;
select pg_temp.mixed_statement();
select results_eq(
  $$values (pg_temp.entries('40', '01'), pg_temp.entries('41', '01'),
            pg_temp.entries('42', '02'), pg_temp.entries('43', '02'))$$,
  $$values (0, 1, 1, 1)$$,
  'v2: en la misma sentencia sólo la fila autorizada de su taller omite el efecto');

-- Sólo INSERT: la misma fila, repuesta como borrador y luego confirmada.
create function pg_temp.insert_then_update()
returns void
language plpgsql
as $$
begin
  perform pg_temp.replay('44', '01', 'draft');
  perform pg_temp.act_as('01');
  update public.sales_invoices set status = 'confirmed'
   where id = pg_temp.id('44') and tenant_id = pg_temp.id('01');
end;
$$;
select pg_temp.insert_then_update();
select is(pg_temp.entries('44', '01'), 1,
  'v2: la autorización es sólo del INSERT; el UPDATE de la misma fila contabiliza');

-- Una vez: la fila autorizada, borrada (borrador) y vuelta a insertar.
create function pg_temp.consume_once()
returns void
language plpgsql
as $$
begin
  perform pg_temp.replay('45', '01', 'draft');
  delete from public.sales_invoices
   where id = pg_temp.id('45') and tenant_id = pg_temp.id('01');
  perform pg_temp.add_invoice('45', '01');
end;
$$;
select pg_temp.consume_once();
select is(pg_temp.entries('45', '01'), 1,
  'v2: la autorización se usa una sola vez; el segundo INSERT contabiliza');

-- Retiro: autorizada y cerrada antes de insertar.
create function pg_temp.withdrawn()
returns void
language plpgsql
as $$
begin
  perform pg_temp.authorize('01', array['46']);
  perform public.restore_replay_close_internal(pg_temp.id('01'));
  perform pg_temp.add_invoice('46', '01');
end;
$$;
select pg_temp.withdrawn();
select is(pg_temp.entries('46', '01'), 1, 'v2: retirado el contexto, el efecto vuelve');

-- Subtransacción fallida: la autorización se deshace con ella.
create function pg_temp.failed_subtransaction()
returns void
language plpgsql
as $$
begin
  begin
    perform pg_temp.authorize('01', array['47']);
    perform 1 / 0;
  exception when division_by_zero then
    null;
  end;
  perform pg_temp.add_invoice('47', '01');
end;
$$;
select pg_temp.failed_subtransaction();
select is(pg_temp.entries('47', '01'), 1,
  'v2: la autorización abierta en una subtransacción fallida no queda');

-- ============================================================================
-- Constraints y validadores siguen rechazando, con el contexto abierto
-- ============================================================================
create function pg_temp.replay_duplicate()
returns void
language plpgsql
as $$
begin
  perform pg_temp.replay('30', '03');
end;
$$;
select throws_ok('select pg_temp.replay_duplicate()', '23505',
  'duplicate key value violates unique constraint "sales_invoices_pkey"',
  'con el contexto abierto, la llave rechaza la fila repuesta dos veces');

create function pg_temp.delete_replayed()
returns void
language plpgsql
as $$
begin
  perform pg_temp.authorize('03', array['30']);
  delete from public.sales_invoices
   where id = pg_temp.id('30') and tenant_id = pg_temp.id('03');
end;
$$;
select throws_ok('select pg_temp.delete_replayed()', '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'el contexto no abre la purga: la venta repuesta contabilizada no se borra');

select throws_ok(
  $$select public.restore_replay_authorize_internal('e2894000-0000-4000-8000-0000000000ff', 'sales_invoices', array['e2894000-0000-4000-8000-000000000050'::uuid])$$,
  '23503', null, 'no se autoriza para un taller que no existe');
select throws_ok(
  $$select public.restore_replay_authorize_internal('e2894000-0000-4000-8000-000000000001', 'purchase_invoices', array['e2894000-0000-4000-8000-000000000050'::uuid])$$,
  '23514', null, 'no se autoriza otra tabla que la cubierta por el disparador');
select throws_ok(
  $$select public.restore_replay_authorize_internal('e2894000-0000-4000-8000-000000000001', 'sales_invoices', array[null::uuid])$$,
  '22023', null, 'no se autoriza sin filas explícitas');

-- ============================================================================
-- La API no lo abre ni lo imita
-- ============================================================================
select ok(
  (select c.relrowsecurity from pg_class c
    where c.oid = 'public.restore_replay_authorizations'::regclass)
  and not exists (select 1 from pg_policy
                   where polrelid = 'public.restore_replay_authorizations'::regclass)
  and not exists (
    select 1 from unnest(array['anon', 'authenticated', 'service_role']) as r(role),
                  unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as p(priv)
     where has_table_privilege(r.role, 'public.restore_replay_authorizations', p.priv)),
  'la tabla de autorizaciones: RLS sin políticas y sin privilegios para la API');

select ok(
  not exists (
    select 1
      from unnest(array[
             'public.restore_replay_authorize_internal(uuid,text,uuid[])',
             'public.restore_replay_consume_internal(uuid,text,uuid,text)',
             'public.restore_replay_close_internal(uuid)']) as f(sig),
           unnest(array['anon', 'authenticated', 'service_role']) as r(role)
     where has_function_privilege(r.role, f.sig::regprocedure, 'EXECUTE')),
  'ninguna función del contexto se ejecuta desde la API');

select ok(
  (select bool_and(p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
                   and p.proconfig @> array['search_path=pg_catalog, public, pg_temp']
                   and pg_get_functiondef(p.oid) !~* '(current_user|session_user|current_setting|request\.jwt|auth\.)')
     from pg_proc p
    where p.oid in ('public.restore_replay_authorize_internal(uuid,text,uuid[])'::regprocedure,
                    'public.restore_replay_consume_internal(uuid,text,uuid,text)'::regprocedure,
                    'public.restore_replay_close_internal(uuid)'::regprocedure)),
  'las funciones del contexto son del dueño, con search_path fijo, y no leen rol, claims ni variables');

select ok(
  (select p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres'
     from pg_proc p where p.oid = 'public.handle_sales_invoice_change()'::regprocedure),
  'el disparador corre como su dueño: current_user ahí no dice quién escribe');

select ok(
  not exists (
    select 1 from unnest(array['anon', 'authenticated', 'service_role']) as r(role),
                  unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as p(priv)
     where has_table_privilege(r.role, 'public.mechanic_job_line_gate_deferrals', p.priv)),
  'el antecedente (mechanic_job_line_gate_deferrals) también es privado');

-- authenticated, con claims de service_role y variables inventadas.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'service_role')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
select set_config('request.jwt.claim.role', 'service_role', true);
set local role authenticated;
select is(current_user::text, 'authenticated', 'el rol efectivo de la sesión es authenticated');
select throws_ok(
  $$select public.restore_replay_authorize_internal('e2894000-0000-4000-8000-000000000001', 'sales_invoices', array['e2894000-0000-4000-8000-000000000050'::uuid])$$,
  '42501', null, 'authenticated (aun con claim service_role) no abre el contexto');
select throws_ok(
  $$select public.restore_replay_consume_internal('e2894000-0000-4000-8000-000000000001', 'sales_invoices', 'e2894000-0000-4000-8000-000000000050', 'insert')$$,
  '42501', null, 'authenticated no consume el contexto');
select throws_ok(
  $$select public.restore_replay_close_internal('e2894000-0000-4000-8000-000000000001')$$,
  '42501', null, 'authenticated no cierra el contexto');
select throws_ok(
  $$insert into public.restore_replay_authorizations
      values (txid_current(), statement_timestamp(), 'e2894000-0000-4000-8000-000000000001',
              'sales_invoices', 'e2894000-0000-4000-8000-000000000050', 'insert')$$,
  '42501', null, 'authenticated no escribe la tabla de autorizaciones');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select set_config('app.restore_replay', 'on', true);
select set_config('app.restore_tenant', pg_temp.id('01')::text, true);
select set_config('app.allow_posted_document_purge', 'true', true);
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment
) values (
  pg_temp.id('48'), pg_temp.id('01'), 'R1-01-48', 'Cliente reposición', 'confirmed',
  'manual_sale', 10000, 10000, 0, 10000, 0, 10000, 'no_tax'
);
select set_config('app.restore_replay', '', true);
select set_config('app.restore_tenant', '', true);
select set_config('app.allow_posted_document_purge', '', true);

-- Control con el mismo método: la variable que el disparador real sí lee hoy.
select set_config('app.syncing_job_to_invoice', 'true', true);
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment
) values (
  pg_temp.id('49'), pg_temp.id('01'), 'R1-01-49', 'Cliente reposición', 'confirmed',
  'manual_sale', 10000, 10000, 0, 10000, 0, 10000, 'no_tax'
);
select set_config('app.syncing_job_to_invoice', '', true);
reset role;

select is(pg_temp.entries('48', '01'), 1,
  'authenticated no imita el contexto con variables de sesión: su venta contabiliza');
select is(pg_temp.entries('49', '01'), 0,
  'control (defecto vigente): con app.syncing_job_to_invoice, authenticated deja su venta sin asiento');

select is(
  (select count(*) from net.http_request_queue),
  (select n from net_queue_before),
  'nada quedó en la cola de pg_net');

select * from finish();
rollback;
