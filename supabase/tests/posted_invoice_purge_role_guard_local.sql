-- Purga de facturas contabilizadas: quién puede saltarse el guard
-- (Master Schema, restore ítem 3; hallazgo de R1, 2026-09-30).
--
-- Sólo local y transaccional (`bash scripts/db/test.sh posted_invoice_purge_role_guard_local`):
-- talleres y ventas sintéticos, candidato creado dentro de la transacción y
-- ROLLBACK al final. No toca migraciones aplicadas. Se detiene si la base
-- tiene secretos en vault (producción) y compara la cola de pg_net.
--
-- Defecto (parte A, con el guard desplegado, mismo md5 en producción):
-- `guard_posted_invoice_delete()` es SECURITY DEFINER, así que su
-- `current_user in ('postgres','service_role')` siempre es verdadero: dentro
-- de la función el usuario es su dueño. La salida de purga queda en manos de
-- `app.allow_posted_document_purge`, que cualquier rol fija con `set_config`.
-- Un authenticated de su propio taller borra así una venta contabilizada, y
-- el borrado se lleva su asiento (queda sólo la evidencia). Con un claim
-- `service_role` inventado, igual.
--
-- Quién usa hoy esa salida (revisado 2026-09-30): nadie. Ninguna función,
-- migración, script ni código de la app fija la variable. La app borra sólo
-- borradores (`SalesService.deleteInvoice`, `PurchaseService.deletePurchaseInvoice`,
-- como authenticated); `cascade_delete_pega_invoice` (borrar un trabajo borra
-- su factura en borrador) y el reinicio de fábrica pasan por el camino de
-- borradores; el motor legado de restore choca con el guard (negativa
-- vigente). La cancelación normal es un UPDATE de estado, que el guard no mira.
--
-- Candidato (bloque FORWARD, el SQL exacto que propongo para cross-review):
-- una autorización privada por transacción, taller, tabla y fila, que el
-- guard consume una vez. La abre `authorize_posted_document_purge`, con
-- EXECUTE sólo para service_role (el backend) y el dueño; la API authenticated
-- y anon no. El guard ya no lee variables, claims ni `current_user`. Queda
-- para el revisor: si service_role debe conservar esta salida (el diseño
-- original la nombraba) o sólo el dueño.
--
-- Fuera de este archivo: la misma prueba con compras en tiempo de ejecución
-- (el guard y el candidato son los mismos: se comprueba en el catálogo) y el
-- guard de pagos activos (sin cambios).
begin;

select no_plan();

do $guard$
begin
  if exists (select 1 from vault.secrets) then
    raise exception 'posted_invoice_purge_role_guard_local: sólo en la base local';
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
as $$ select ('e2895000-0000-4000-8000-0000000000' || p_n)::uuid $$;

insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Purga propio'),
  (pg_temp.id('02'), 'Purga otro');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated', 'purga-1@example.invalid',
   '', now(), '{}', '{}', now(), now()),
  (pg_temp.id('92'), 'authenticated', 'authenticated', 'purga-2@example.invalid',
   '', now(), '{}', '{}', now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin'),
  (pg_temp.id('92'), pg_temp.id('02'), 'admin');

-- Claims de un miembro de su taller (el rol efectivo lo fija `set local role`).
create function pg_temp.claims(p_tenant text, p_role text)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', pg_temp.id('9' || right(p_tenant, 1)), 'role', p_role)::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.id('9' || right(p_tenant, 1))::text, true);
  perform set_config('request.jwt.claim.role', p_role, true);
end;
$$;

create function pg_temp.add(p_id text, p_tenant text, p_status text default 'confirmed')
returns void
language plpgsql
as $$
begin
  perform pg_temp.claims(p_tenant, 'authenticated');
  insert into public.sales_invoices (
    id, tenant_id, invoice_number, customer_name, status, source,
    subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment
  ) values (
    pg_temp.id(p_id), pg_temp.id(p_tenant), 'PG-' || p_tenant || '-' || p_id,
    'Cliente purga', p_status, 'manual_sale',
    10000, 10000, 0, 10000, 0, 10000, 'no_tax'
  );
end;
$$;

create function pg_temp.exists_invoice(p_id text, p_tenant text)
returns boolean
language sql
as $$
  select exists (select 1 from public.sales_invoices
                  where id = pg_temp.id(p_id) and tenant_id = pg_temp.id(p_tenant))
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

select pg_temp.add(n, '01') from unnest(array['20', '21', '22', '30', '31', '32', '33',
                                             '34', '35', '36', '37', '38']) as n;
select pg_temp.add('39', '01', 'draft');
select pg_temp.add('40', '02');

select is(pg_temp.entries('20', '01'), 1, 'las ventas contabilizadas del taller tienen su asiento');
select is(md5(pg_get_functiondef('public.guard_posted_invoice_delete()'::regprocedure)),
  'ddb0b13b7e4d511a3826c115efb79271',
  'el guard es el desplegado (mismo md5 que producción el 2026-09-29)');

-- ============================================================================
-- A. El guard desplegado: authenticated purga con una variable de sesión
-- ============================================================================
-- Sonda del rol efectivo dentro de un disparador: definer frente a invoker.
create function public.purge_probe_definer_role()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $$
begin
  perform set_config('purge_probe.definer_role', current_user::text, true);
  return old;
end;
$$;
create function public.purge_probe_invoker_role()
returns trigger
language plpgsql
set search_path to 'pg_catalog'
as $$
begin
  perform set_config('purge_probe.invoker_role', current_user::text, true);
  return old;
end;
$$;
grant execute on function public.purge_probe_definer_role() to authenticated;
grant execute on function public.purge_probe_invoker_role() to authenticated;
create trigger zzz_purge_probe_definer before delete on public.sales_invoices
  for each row execute function public.purge_probe_definer_role();
create trigger zzz_purge_probe_invoker before delete on public.sales_invoices
  for each row execute function public.purge_probe_invoker_role();

select pg_temp.claims('01', 'authenticated');
set local role authenticated;
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000021'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'A: sin la variable, authenticated no borra su venta contabilizada');
select set_config('app.allow_posted_document_purge', 'true', true);
select lives_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000020'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  'A (defecto): con la variable, authenticated borra su venta contabilizada');
select is(current_user::text, 'authenticated', 'A: la sentencia corrió como authenticated');
reset role;
select set_config('app.allow_posted_document_purge', '', true);

select results_eq(
  $$values (current_setting('purge_probe.definer_role', true),
            current_setting('purge_probe.invoker_role', true))$$,
  $$values ('postgres'::text, 'authenticated'::text)$$,
  'A: dentro de un disparador definer current_user es el dueño, no quien borra');
select ok(not pg_temp.exists_invoice('20', '01') and pg_temp.entries('20', '01') = 0,
  'A (defecto): la venta y su asiento ya no están');

-- Con un claim service_role inventado, lo mismo.
select pg_temp.claims('01', 'service_role');
set local role authenticated;
select set_config('app.allow_posted_document_purge', 'true', true);
select lives_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000022'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  'A (defecto): con un claim service_role inventado, también');
reset role;
select set_config('app.allow_posted_document_purge', '', true);

drop trigger zzz_purge_probe_definer on public.sales_invoices;
drop trigger zzz_purge_probe_invoker on public.sales_invoices;

-- ============================================================================
-- B. Candidato. FORWARD-BEGIN: SQL exacto propuesto (en su migración, entre
-- begin/commit; el md5 de arriba es la precondición del reemplazo).
-- ============================================================================
create table public.posted_document_purge_authorizations (
  txid bigint not null,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  table_name text not null check (table_name in ('sales_invoices', 'purchase_invoices')),
  row_id uuid not null,
  reason text not null check (length(btrim(reason)) > 0),
  primary key (txid, table_name, row_id)
);
alter table public.posted_document_purge_authorizations enable row level security;
revoke all on table public.posted_document_purge_authorizations
  from public, anon, authenticated, service_role;
comment on table public.posted_document_purge_authorizations is
  'Private, transaction-scoped: posted invoices the backend may purge in this transaction, one row each, consumed once by guard_posted_invoice_delete. Never readable or writable by API roles.';

-- El backend (service_role) o el dueño autoriza filas concretas de un taller,
-- en su transacción. authenticated y anon no pueden.
create function public.authorize_posted_document_purge(
  p_tenant_id uuid,
  p_table text,
  p_row_ids uuid[],
  p_reason text
)
returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_requested integer;
  v_found integer;
begin
  if p_tenant_id is null or p_row_ids is null or cardinality(p_row_ids) = 0
     or array_position(p_row_ids, null) is not null
     or length(btrim(coalesce(p_reason, ''))) = 0 then
    raise exception 'purge authorization: taller, filas y motivo son obligatorios'
      using errcode = '22023';
  end if;
  select count(distinct row_id) into v_requested from unnest(p_row_ids) as row_id;
  if p_table = 'sales_invoices' then
    select count(*) into v_found from public.sales_invoices invoice
     where invoice.tenant_id = p_tenant_id and invoice.id = any (p_row_ids);
  elsif p_table = 'purchase_invoices' then
    select count(*) into v_found from public.purchase_invoices invoice
     where invoice.tenant_id = p_tenant_id and invoice.id = any (p_row_ids);
  else
    raise exception 'purge authorization: tabla no admitida' using errcode = '22023';
  end if;
  if v_found <> v_requested or v_requested <> cardinality(p_row_ids) then
    raise exception 'purge authorization: cada fila debe existir, una vez, en ese taller'
      using errcode = '22023';
  end if;
  insert into public.posted_document_purge_authorizations(
    txid, tenant_id, table_name, row_id, reason)
  select txid_current(), p_tenant_id, p_table, row_id, btrim(p_reason)
    from unnest(p_row_ids) as row_id;
  return v_requested;
end;
$$;

create function public.consume_posted_document_purge_internal(
  p_tenant_id uuid,
  p_table text,
  p_row_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
begin
  delete from public.posted_document_purge_authorizations a
   where a.txid = txid_current()
     and a.tenant_id = p_tenant_id
     and a.table_name = p_table
     and a.row_id = p_row_id;
  return found;
end;
$$;

revoke all on function public.authorize_posted_document_purge(uuid, text, uuid[], text)
  from public, anon, authenticated, service_role;
grant execute on function public.authorize_posted_document_purge(uuid, text, uuid[], text)
  to service_role;
revoke all on function public.consume_posted_document_purge_internal(uuid, text, uuid)
  from public, anon, authenticated, service_role;

-- El mismo guard, con una sola línea cambiada: la salida de purga es la
-- autorización privada de esta fila, no una variable ni el rol del definer.
create or replace function public.guard_posted_invoice_delete()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_status text:=lower(coalesce(old.status,'draft'));
begin
 if public.consume_posted_document_purge_internal(old.tenant_id,tg_table_name,old.id)then return old;end if;
 if v_status not in('draft','borrador')then
  raise exception 'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow'
   using errcode='check_violation';
 end if;
 if tg_table_name='sales_invoices'and exists(
  select 1 from public.sales_payments payment where payment.invoice_id=old.id and payment.deleted_at is null
 )then raise exception 'Invoice with active payments cannot be deleted'using errcode='check_violation';end if;
 if tg_table_name='purchase_invoices'and exists(
  select 1 from public.purchase_payments payment where payment.invoice_id=old.id and payment.deleted_at is null
 )then raise exception 'Invoice with active payments cannot be deleted'using errcode='check_violation';end if;
 return old;
end;$$;
-- FORWARD-END

-- ============================================================================
-- C. El candidato: authenticated ya no purga; el backend autorizado sí
-- ============================================================================
select pg_temp.claims('01', 'authenticated');
set local role authenticated;
select set_config('app.allow_posted_document_purge', 'true', true);
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000030'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'C: authenticated con la variable ya no borra su venta contabilizada');
reset role;
select set_config('app.allow_posted_document_purge', '', true);

select pg_temp.claims('01', 'service_role');
set local role authenticated;
select is(auth.role(), 'service_role', 'C: el claim inventado engaña a quien lea auth.role()');
select set_config('app.allow_posted_document_purge', 'true', true);
select throws_ok(
  $$select public.authorize_posted_document_purge(
      'e2895000-0000-4000-8000-000000000001', 'sales_invoices',
      array['e2895000-0000-4000-8000-000000000031'::uuid], 'claim inventado')$$,
  '42501', null, 'C: authenticated con claim service_role no autoriza la purga');
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000031'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'C: ni borra con claim service_role y la variable');
select throws_ok(
  $$insert into public.posted_document_purge_authorizations
      values (txid_current(), 'e2895000-0000-4000-8000-000000000001', 'sales_invoices',
              'e2895000-0000-4000-8000-000000000031', 'directo')$$,
  '42501', null, 'C: authenticated no escribe la tabla de autorizaciones');
select throws_ok(
  $$select public.consume_posted_document_purge_internal(
      'e2895000-0000-4000-8000-000000000001', 'sales_invoices',
      'e2895000-0000-4000-8000-000000000031')$$,
  '42501', null, 'C: authenticated no consume autorizaciones');
reset role;
select set_config('app.allow_posted_document_purge', '', true);

-- El backend real: service_role autoriza la fila y la purga.
select pg_temp.claims('01', 'service_role');
set local role service_role;
select is(current_user::text, 'service_role', 'C: la sentencia corre como service_role');
select is(public.authorize_posted_document_purge(
  pg_temp.id('01'), 'sales_invoices', array[pg_temp.id('32')], 'purga del backend'),
  1, 'C: service_role autoriza una venta de ese taller');
select lives_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000032'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  'C: service_role purga la venta que autorizó');
select set_config('app.allow_posted_document_purge', 'true', true);
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000033'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'C: service_role sin autorización no purga, aunque fije la variable');
select set_config('app.allow_posted_document_purge', '', true);
select is(public.authorize_posted_document_purge(
  pg_temp.id('01'), 'sales_invoices', array[pg_temp.id('36')], 'sólo esta'),
  1, 'C: service_role autoriza otra fila');
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000037'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'C: la autorización es de una fila: otra venta no se purga');
select lives_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000036'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  'C: la fila autorizada sí');
select throws_ok(
  $$select public.authorize_posted_document_purge(
      'e2895000-0000-4000-8000-000000000001', 'sales_invoices',
      array['e2895000-0000-4000-8000-000000000040'::uuid], 'otro taller')$$,
  '22023', null, 'C: no se autoriza una venta de otro taller');
select throws_ok(
  $$select public.authorize_posted_document_purge(
      'e2895000-0000-4000-8000-000000000001', 'journal_entries',
      array['e2895000-0000-4000-8000-000000000035'::uuid], 'otra tabla')$$,
  '22023', null, 'C: no se autoriza otra tabla');
select throws_ok(
  $$select public.authorize_posted_document_purge(
      'e2895000-0000-4000-8000-000000000001', 'sales_invoices',
      array['e2895000-0000-4000-8000-000000000035'::uuid], '  ')$$,
  '22023', null, 'C: la purga exige un motivo');
reset role;

select ok(not pg_temp.exists_invoice('32', '01') and not pg_temp.exists_invoice('36', '01')
          and pg_temp.exists_invoice('33', '01') and pg_temp.exists_invoice('37', '01'),
  'C: se purgaron exactamente las dos filas autorizadas');
select ok(exists (select 1 from public.journal_supersession_evidence evidence
                   where evidence.tenant_id = pg_temp.id('01')
                     and evidence.source_reference = 'PG-01-32'),
  'C: la purga autorizada conserva la evidencia del asiento');

-- Una vez: la fila 36 vuelve (misma id) y ya no hay autorización.
select pg_temp.add('36', '01');
select pg_temp.claims('01', 'service_role');
set local role service_role;
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000036'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'C: la autorización se usa una sola vez');
reset role;

-- El dueño (mantención) también autoriza y purga.
select is(public.authorize_posted_document_purge(
  pg_temp.id('01'), 'sales_invoices', array[pg_temp.id('34')], 'mantención'),
  1, 'C: el dueño autoriza');
delete from public.sales_invoices
 where id = pg_temp.id('34') and tenant_id = pg_temp.id('01');
select ok(not pg_temp.exists_invoice('34', '01'), 'C: y purga la fila autorizada');

-- Los flujos normales siguen: cancelar una contabilizada y borrar un borrador.
select pg_temp.claims('01', 'authenticated');
set local role authenticated;
select lives_ok(
  $$update public.sales_invoices set status = 'cancelled'
     where id = 'e2895000-0000-4000-8000-000000000038'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  'normal: authenticated cancela su venta contabilizada');
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000038'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'normal: una venta cancelada sigue sin borrarse');
select lives_ok(
  $$delete from public.sales_invoices
     where id = 'e2895000-0000-4000-8000-000000000039'
       and tenant_id = 'e2895000-0000-4000-8000-000000000001'$$,
  'normal: authenticated borra su borrador (como la app)');
reset role;
select ok(
  (select status = 'cancelled' from public.sales_invoices
    where id = pg_temp.id('38') and tenant_id = pg_temp.id('01'))
  and pg_temp.entries('38', '01') = 0
  and not pg_temp.exists_invoice('39', '01'),
  'normal: la cancelación revierte el asiento y el borrador ya no está');

-- ============================================================================
-- D. Catálogo del candidato
-- ============================================================================
select ok(
  (select c.relrowsecurity from pg_class c
    where c.oid = 'public.posted_document_purge_authorizations'::regclass)
  and not exists (select 1 from pg_policy
                   where polrelid = 'public.posted_document_purge_authorizations'::regclass)
  and not exists (
    select 1 from unnest(array['anon', 'authenticated', 'service_role']) as r(role),
                  unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE']) as p(priv)
     where has_table_privilege(r.role, 'public.posted_document_purge_authorizations', p.priv)),
  'D: la tabla de autorizaciones es privada (RLS sin políticas, sin privilegios de la API)');
select results_eq(
  $$select has_function_privilege('anon', 'public.authorize_posted_document_purge(uuid,text,uuid[],text)', 'EXECUTE'),
           has_function_privilege('authenticated', 'public.authorize_posted_document_purge(uuid,text,uuid[],text)', 'EXECUTE'),
           has_function_privilege('service_role', 'public.authorize_posted_document_purge(uuid,text,uuid[],text)', 'EXECUTE'),
           has_function_privilege('anon', 'public.consume_posted_document_purge_internal(uuid,text,uuid)', 'EXECUTE'),
           has_function_privilege('authenticated', 'public.consume_posted_document_purge_internal(uuid,text,uuid)', 'EXECUTE'),
           has_function_privilege('service_role', 'public.consume_posted_document_purge_internal(uuid,text,uuid)', 'EXECUTE')$$,
  $$values (false, false, true, false, false, false)$$,
  'D: autoriza sólo service_role (y el dueño); nadie de la API consume');
select ok(
  (select bool_and(pg_get_functiondef(p.oid) !~* '(current_user|session_user|current_setting|request\.jwt|auth\.)')
     from pg_proc p
    where p.oid in ('public.guard_posted_invoice_delete()'::regprocedure,
                    'public.authorize_posted_document_purge(uuid,text,uuid[],text)'::regprocedure,
                    'public.consume_posted_document_purge_internal(uuid,text,uuid)'::regprocedure)),
  'D: el guard y el candidato no leen rol, variables ni claims');
select is(
  (select count(*)::integer from pg_trigger
    where tgfoid = 'public.guard_posted_invoice_delete()'::regprocedure
      and tgrelid in ('public.sales_invoices'::regclass, 'public.purchase_invoices'::regclass)
      and tgenabled = 'O'),
  2, 'D: el guard sigue en ventas y compras');

select is(
  (select count(*) from net.http_request_queue),
  (select n from net_queue_before),
  'nada quedó en la cola de pg_net');

select * from finish();
rollback;
