-- 20260930020000: la purga de facturas contabilizadas exige una autorización
-- privada de la fila; authenticated ya no la abre con una variable de sesión
-- ni con un claim inventado (defecto reproducido en
-- posted_invoice_purge_role_guard_local.sql).
--
-- Prueba el SQL forward instalado, no una copia: aplicar antes en local
--   scripts/db/query.sh local --write --file supabase/migrations/20260930020000_guard_posted_invoice_delete_authorization.sql
-- y correr
--   bash scripts/db/test.sh posted_invoice_purge_authorization
-- Sólo local y transaccional: talleres y ventas sintéticos, ROLLBACK al final;
-- se detiene si la base tiene secretos en vault (producción) y compara la
-- cola de pg_net. Compras usan el mismo guard (se comprueba en el catálogo).
begin;

select no_plan();

do $guard$
begin
  if exists (select 1 from vault.secrets) then
    raise exception 'posted_invoice_purge_authorization: sólo en la base local';
  end if;
end;
$guard$;

create temporary table net_queue_before as
  select count(*) as n from net.http_request_queue;

select ok(
  to_regprocedure('public.authorize_posted_document_purge(uuid,text,uuid[],text)') is not null
  and to_regprocedure('public.consume_posted_document_purge_internal(uuid,text,uuid)') is not null
  and position('consume_posted_document_purge_internal'
               in pg_get_functiondef('public.guard_posted_invoice_delete()'::regprocedure)) > 0,
  'el SQL forward de 20260930020000 está aplicado en esta base');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2897000-0000-4000-8000-0000000000' || p_n)::uuid $$;

insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Purga autorizada propio'),
  (pg_temp.id('02'), 'Purga autorizada otro');
-- El alta del taller deja su id como `sub` (SUPABASE_WORKFLOW.md).
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated', 'purga-autorizada-1@example.invalid',
   '', now(), '{}', '{}', now(), now()),
  (pg_temp.id('92'), 'authenticated', 'authenticated', 'purga-autorizada-2@example.invalid',
   '', now(), '{}', '{}', now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin'),
  (pg_temp.id('92'), pg_temp.id('02'), 'admin');

-- Claims de un miembro de su taller; el rol efectivo lo fija `set local role`.
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
    pg_temp.id(p_id), pg_temp.id(p_tenant), 'PA-' || p_tenant || '-' || p_id,
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

select pg_temp.add(n, '01') from unnest(array['20', '21', '22', '23', '24', '25',
                                             '26', '27']) as n;
select pg_temp.add('29', '01', 'draft');
select pg_temp.add('40', '02');
select is(pg_temp.entries('20', '01'), 1, 'las ventas contabilizadas del taller tienen su asiento');

-- ============================================================================
-- authenticated: ni la variable ni un claim service_role abren la purga
-- ============================================================================
select pg_temp.claims('01', 'authenticated');
set local role authenticated;
select is(current_user::text, 'authenticated', 'la sentencia corre como authenticated');
select set_config('app.allow_posted_document_purge', 'true', true);
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2897000-0000-4000-8000-000000000020'
       and tenant_id = 'e2897000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'authenticated con app.allow_posted_document_purge no borra su venta contabilizada');
reset role;
select set_config('app.allow_posted_document_purge', '', true);

select pg_temp.claims('01', 'service_role');
set local role authenticated;
select is(auth.role(), 'service_role', 'el claim inventado engaña a quien lea auth.role()');
select set_config('app.allow_posted_document_purge', 'true', true);
select throws_ok(
  $$select public.authorize_posted_document_purge(
      'e2897000-0000-4000-8000-000000000001', 'sales_invoices',
      array['e2897000-0000-4000-8000-000000000021'::uuid], 'claim inventado')$$,
  '42501', null, 'authenticated con claim service_role no autoriza la purga');
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2897000-0000-4000-8000-000000000021'
       and tenant_id = 'e2897000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'ni borra con claim service_role y la variable');
select throws_ok(
  $$insert into public.posted_document_purge_authorizations
      values (txid_current(), 'e2897000-0000-4000-8000-000000000001', 'sales_invoices',
              'e2897000-0000-4000-8000-000000000021', 'directo')$$,
  '42501', null, 'authenticated no escribe la tabla de autorizaciones');
select throws_ok(
  $$select public.consume_posted_document_purge_internal(
      'e2897000-0000-4000-8000-000000000001', 'sales_invoices',
      'e2897000-0000-4000-8000-000000000021')$$,
  '42501', null, 'authenticated no consume autorizaciones');
reset role;
select set_config('app.allow_posted_document_purge', '', true);
select ok(pg_temp.exists_invoice('20', '01') and pg_temp.exists_invoice('21', '01')
          and pg_temp.entries('20', '01') = 1,
  'las ventas de authenticated y su asiento siguen ahí');

-- ============================================================================
-- El backend: service_role autoriza una fila de su taller y la purga, una vez
-- ============================================================================
select pg_temp.claims('01', 'service_role');
set local role service_role;
select is(current_user::text, 'service_role', 'la sentencia corre como service_role');
select set_config('app.allow_posted_document_purge', 'true', true);
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2897000-0000-4000-8000-000000000022'
       and tenant_id = 'e2897000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'service_role sin autorización no purga, aunque fije la variable');
select set_config('app.allow_posted_document_purge', '', true);
select is(public.authorize_posted_document_purge(
  pg_temp.id('01'), 'sales_invoices', array[pg_temp.id('23')], 'purga del backend'),
  1, 'service_role autoriza una venta de su taller');
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2897000-0000-4000-8000-000000000024'
       and tenant_id = 'e2897000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'la autorización es de una fila: otra venta no se purga');
select lives_ok(
  $$delete from public.sales_invoices
     where id = 'e2897000-0000-4000-8000-000000000023'
       and tenant_id = 'e2897000-0000-4000-8000-000000000001'$$,
  'service_role purga la venta que autorizó');
select throws_ok(
  $$select public.authorize_posted_document_purge(
      'e2897000-0000-4000-8000-000000000001', 'sales_invoices',
      array['e2897000-0000-4000-8000-000000000040'::uuid], 'otro taller')$$,
  '22023', null, 'no se autoriza una venta de otro taller');
select throws_ok(
  $$select public.authorize_posted_document_purge(
      'e2897000-0000-4000-8000-000000000001', 'journal_entries',
      array['e2897000-0000-4000-8000-000000000025'::uuid], 'otra tabla')$$,
  '22023', null, 'no se autoriza otra tabla');
select throws_ok(
  $$select public.authorize_posted_document_purge(
      'e2897000-0000-4000-8000-000000000001', 'sales_invoices',
      array['e2897000-0000-4000-8000-000000000025'::uuid], '  ')$$,
  '22023', null, 'la purga exige un motivo');
reset role;

select ok(not pg_temp.exists_invoice('23', '01')
          and pg_temp.exists_invoice('22', '01') and pg_temp.exists_invoice('24', '01')
          and pg_temp.exists_invoice('40', '02'),
  'se purgó exactamente la fila autorizada');
select ok(exists (select 1 from public.journal_supersession_evidence evidence
                   where evidence.tenant_id = pg_temp.id('01')
                     and evidence.source_reference = 'PA-01-23'),
  'la purga autorizada conserva la evidencia del asiento');

-- Una vez: la fila 23 vuelve (misma id) y ya no hay autorización.
select pg_temp.add('23', '01');
select pg_temp.claims('01', 'service_role');
set local role service_role;
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2897000-0000-4000-8000-000000000023'
       and tenant_id = 'e2897000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'la autorización se usa una sola vez');
reset role;

-- El dueño (mantención) también autoriza y purga.
select is(public.authorize_posted_document_purge(
  pg_temp.id('01'), 'sales_invoices', array[pg_temp.id('26')], 'mantención'),
  1, 'el dueño autoriza');
delete from public.sales_invoices
 where id = pg_temp.id('26') and tenant_id = pg_temp.id('01');
select ok(not pg_temp.exists_invoice('26', '01'), 'y purga la fila autorizada');

-- ============================================================================
-- Los flujos normales: cancelar una contabilizada y borrar un borrador
-- ============================================================================
select pg_temp.claims('01', 'authenticated');
set local role authenticated;
select lives_ok(
  $$update public.sales_invoices set status = 'cancelled'
     where id = 'e2897000-0000-4000-8000-000000000027'
       and tenant_id = 'e2897000-0000-4000-8000-000000000001'$$,
  'authenticated cancela su venta contabilizada');
select throws_ok(
  $$delete from public.sales_invoices
     where id = 'e2897000-0000-4000-8000-000000000027'
       and tenant_id = 'e2897000-0000-4000-8000-000000000001'$$,
  '23514',
  'Posted invoices cannot be deleted; use the documented cancellation, return, credit-note, or void workflow',
  'una venta cancelada sigue sin borrarse');
select lives_ok(
  $$delete from public.sales_invoices
     where id = 'e2897000-0000-4000-8000-000000000029'
       and tenant_id = 'e2897000-0000-4000-8000-000000000001'$$,
  'authenticated borra su borrador (como la app)');
reset role;
select ok(
  (select status = 'cancelled' from public.sales_invoices
    where id = pg_temp.id('27') and tenant_id = pg_temp.id('01'))
  and pg_temp.entries('27', '01') = 0
  and not pg_temp.exists_invoice('29', '01'),
  'la cancelación revierte el asiento y el borrador ya no está');

-- ============================================================================
-- Catálogo
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
  'la tabla de autorizaciones es privada (RLS sin políticas, sin privilegios de la API)');
select results_eq(
  $$select has_function_privilege('anon', 'public.authorize_posted_document_purge(uuid,text,uuid[],text)', 'EXECUTE'),
           has_function_privilege('authenticated', 'public.authorize_posted_document_purge(uuid,text,uuid[],text)', 'EXECUTE'),
           has_function_privilege('service_role', 'public.authorize_posted_document_purge(uuid,text,uuid[],text)', 'EXECUTE'),
           has_function_privilege('anon', 'public.consume_posted_document_purge_internal(uuid,text,uuid)', 'EXECUTE'),
           has_function_privilege('authenticated', 'public.consume_posted_document_purge_internal(uuid,text,uuid)', 'EXECUTE'),
           has_function_privilege('service_role', 'public.consume_posted_document_purge_internal(uuid,text,uuid)', 'EXECUTE')$$,
  $$values (false, false, true, false, false, false)$$,
  'autoriza sólo service_role (y el dueño); nadie de la API consume');
select ok(
  (select bool_and(pg_get_functiondef(p.oid) !~* '(allow_posted_document_purge|current_user|session_user|current_setting|request\.jwt|auth\.)')
     from pg_proc p
    where p.oid in ('public.guard_posted_invoice_delete()'::regprocedure,
                    'public.authorize_posted_document_purge(uuid,text,uuid[],text)'::regprocedure,
                    'public.consume_posted_document_purge_internal(uuid,text,uuid)'::regprocedure)),
  'el guard y la autorización no leen rol, variables ni claims');
select is(
  (select count(*)::integer from pg_trigger
    where tgfoid = 'public.guard_posted_invoice_delete()'::regprocedure
      and tgrelid in ('public.sales_invoices'::regclass, 'public.purchase_invoices'::regclass)
      and tgenabled = 'O'),
  2, 'el guard sigue en ventas y compras');

select is(
  (select count(*) from net.http_request_queue),
  (select n from net_queue_before),
  'nada quedó en la cola de pg_net');

select * from finish();
rollback;
