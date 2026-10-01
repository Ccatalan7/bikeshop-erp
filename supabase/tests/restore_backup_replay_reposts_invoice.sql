-- R0 del restore completo (Master Schema, cola ítem 3; 2026-09-29): lo que
-- hace hoy el motor legado al reponer una factura contabilizada.
--
-- Sólo local y transaccional (`just db-test restore_backup_replay_reposts_invoice`);
-- todo termina en ROLLBACK. No se siembran mensajes, productos ni pedidos:
-- son las tablas cuyos disparadores llaman a `net.http_*` (push, catálogo de
-- WhatsApp, MercadoPago, correo). La cola de `pg_net` se compara al final, y
-- si la base tiene el secreto de push (producción), el archivo se detiene
-- antes de escribir nada.
--
-- Con los validadores encendidos, sobre el motor desplegado:
-- A. La consulta previa dice `can_restore: true` (no ve dependientes fuera del
--    respaldo), pero `restore_backup` falla al borrar: la factura contabilizada
--    no se puede borrar (`aaa_guard_posted_sales_invoice_delete`). No cambia
--    nada.
-- B. Si el motor usa la salida del propio validador
--    (`app.allow_posted_document_purge`, sólo postgres/service_role), llega a
--    reponer la factura: su disparador la vuelve a contabilizar y crea las
--    cuentas 1130/4100/2150 antes de que el motor reponga las del respaldo,
--    que chocan en `accounts_tenant_id_code_key`. Tampoco cambia nada.
--    Control: un taller igual con la factura en borrador sí se restaura.
-- C. El asiento, aislado con las mismas sentencias del motor desplegado
--    (`restore_backup_legacy_rows_internal`; líneas de su `pg_get_functiondef`
--    en producción el 2026-09-29: borrados 20, 34, 35 y 44, inserts 126 y
--    171; igual en local salvo comentarios): la factura repuesta nace
--    con un asiento nuevo, y el del respaldo choca en
--    `idx_journal_entries_sales_source_document_unique`.
begin;

select no_plan();

-- Nunca en una base con el secreto de push: ahí sí saldría un envío real.
do $guard$
begin
  if exists (select 1 from vault.secrets
              where name = 'push_notification_webhook_secret') then
    raise exception 'restore_backup_replay_reposts_invoice: sólo en la base local';
  end if;
end;
$guard$;

create temporary table net_queue_before as
  select count(*) as n from net.http_request_queue;

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2891000-0000-4000-8000-0000000000' || p_n)::uuid $$;

-- Un taller con su administrador, sin lo que la siembra deja fuera del
-- respaldo: terminales de pago (y los medios con tarjeta que las apuntan) y
-- la categoría de gastos. Se borran con los disparadores encendidos.
create or replace function pg_temp.seed_tenant(p_tenant text, p_user text)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  insert into public.tenants(id, shop_name)
  values (pg_temp.id(p_tenant), 'Taller replay ' || p_tenant);
  -- El alta del taller deja su id como `sub` (SUPABASE_WORKFLOW.md).
  perform set_config('request.jwt.claims', '{}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  insert into auth.users(
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    pg_temp.id(p_user), 'authenticated', 'authenticated',
    'replay-' || p_user || '@example.invalid', '', now(), '{}', '{}', now(), now()
  );
  insert into public.user_profiles(user_id, tenant_id, role)
  values (pg_temp.id(p_user), pg_temp.id(p_tenant), 'admin');

  delete from public.payment_terminal_terms
   where payment_method_id in (select id from public.payment_methods
                                where tenant_id = pg_temp.id(p_tenant));
  delete from public.payment_methods
   where tenant_id = pg_temp.id(p_tenant) and terminal_profile_id is not null;
  delete from public.payment_terminal_profiles where tenant_id = pg_temp.id(p_tenant);
  delete from public.expense_categories where tenant_id = pg_temp.id(p_tenant);
end;
$$;

-- Como la función del servidor que llama la app con la llave de servicio.
create or replace function pg_temp.act_as(p_user text)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', pg_temp.id(p_user), 'role', 'service_role')::text, true);
  perform set_config('request.jwt.claim.sub', pg_temp.id(p_user)::text, true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
end;
$$;

select pg_temp.seed_tenant('01', '91');
select pg_temp.seed_tenant('02', '92');

-- Taller 01: una venta contabilizada. Taller 02 (control): la misma, en borrador.
select pg_temp.act_as('91');
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment
) values (
  pg_temp.id('20'), pg_temp.id('01'), 'FV-REPLAY-1', 'Cliente replay',
  'confirmed', 'manual_sale', 10000, 10000, 0, 10000, 0, 10000, 'no_tax'
);
select pg_temp.act_as('92');
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance, tax_treatment
) values (
  pg_temp.id('21'), pg_temp.id('02'), 'FV-REPLAY-2', 'Cliente replay',
  'draft', 'manual_sale', 10000, 10000, 0, 10000, 0, 10000, 'no_tax'
);

select is(
  (select count(*)::integer from public.journal_entries
    where tenant_id = pg_temp.id('01')
      and source_module = 'sales_invoices'
      and source_document_id = pg_temp.id('20')),
  1, 'la venta contabilizada tiene su asiento');

create temporary table results (label text primary key, result jsonb);
select pg_temp.act_as('91');
insert into results
select 'respaldo-01', public.create_backup(pg_temp.id('01'), 'Replay contabilizada', 'manual', null);
select pg_temp.act_as('92');
insert into results
select 'respaldo-02', public.create_backup(pg_temp.id('02'), 'Replay borrador', 'manual', null);

create or replace function pg_temp.backup_id(p_label text)
returns uuid
language sql
as $$ select (result ->> 'backup_id')::uuid from results where label = p_label $$;

create temporary table backup_01 as
  select backup.backup_data as d
    from public.database_backups backup
   where backup.id = pg_temp.backup_id('respaldo-01')
     and backup.tenant_id = pg_temp.id('01');

select ok(
  (select (result ->> 'success')::boolean from results where label = 'respaldo-01')
  and (select jsonb_array_length(d -> 'sales_invoices') = 1
              and jsonb_array_length(d -> 'journal_entries') = 1 from backup_01),
  'el respaldo guarda la venta y su asiento');

-- Lo que hay antes de restaurar, para ver que un fallo no cambia nada.
create temporary table state_01 as
  select (select array_agg(id order by id) from public.journal_entries
           where tenant_id = pg_temp.id('01')) as entry_ids,
         (select array_agg(id order by id) from public.accounts
           where tenant_id = pg_temp.id('01')) as account_ids,
         (select status from public.sales_invoices
           where id = pg_temp.id('20') and tenant_id = pg_temp.id('01')) as invoice_status;

create or replace function pg_temp.unchanged_01()
returns boolean
language sql
as $$
  select (select array_agg(id order by id) from public.journal_entries
           where tenant_id = pg_temp.id('01')) = state.entry_ids
     and (select array_agg(id order by id) from public.accounts
           where tenant_id = pg_temp.id('01')) = state.account_ids
     and (select status from public.sales_invoices
           where id = pg_temp.id('20') and tenant_id = pg_temp.id('01')) = state.invoice_status
     and (select backup.status = 'completed' and backup.restore_report is null
            from public.database_backups backup
           where backup.id = pg_temp.backup_id('respaldo-01')
             and backup.tenant_id = pg_temp.id('01'))
    from state_01 state
$$;

-- ============================================================================
-- A. La nueva guardia de la app niega antes de llegar al motor
-- ============================================================================
select pg_temp.act_as('91');
insert into results
select 'previa-01', public.restore_backup_preflight(pg_temp.backup_id('respaldo-01'), pg_temp.id('01'));
select ok(
  (select not (result ->> 'can_restore')::boolean
          and result -> 'posted_invoice_blocker' ->> 'error_code'
                = 'restore_invoice_delete_blocked'
          and jsonb_array_length(result -> 'uncovered_dependents') = 0
     from results where label = 'previa-01'),
  'A: la consulta previa rechaza la venta contabilizada antes de ofrecer Restaurar');

insert into results
select 'restaurar-01', public.restore_backup(pg_temp.backup_id('respaldo-01'), pg_temp.id('01'));
select is(
  (select result ->> 'error_code' from results where label = 'restaurar-01'),
  'restore_invoice_delete_blocked',
  'A: la entrada real rechaza la venta antes del DELETE');
select ok(
  not (select (result ->> 'success')::boolean from results where label = 'restaurar-01')
  and pg_temp.unchanged_01(),
  'A: el fallo no cambia nada (asiento, cuentas, factura, respaldo)');

-- ============================================================================
-- B. El motor interno demuestra por qué habilitar sólo purga no basta.
-- ============================================================================
select set_config('app.allow_posted_document_purge', 'true', true);

insert into results
select 'restaurar-01-purga', public.restore_backup_internal(pg_temp.backup_id('respaldo-01'), pg_temp.id('01'));
select is(
  (select result ->> 'error' from results where label = 'restaurar-01-purga'),
  'duplicate key value violates unique constraint "accounts_tenant_id_code_key"',
  'B: al reponer la venta, su contabilización crea cuentas que chocan con las del respaldo');
select ok(
  not (select (result ->> 'success')::boolean from results where label = 'restaurar-01-purga')
  and pg_temp.unchanged_01(),
  'B: el fallo no cambia nada');

-- Control: el mismo motor y la misma salida, con la venta en borrador.
select pg_temp.act_as('92');
insert into results
select 'restaurar-02-purga', public.restore_backup(pg_temp.backup_id('respaldo-02'), pg_temp.id('02'));
select ok(
  (select (result ->> 'success')::boolean from results where label = 'restaurar-02-purga')
  and (select count(*) = 0 from public.journal_entries where tenant_id = pg_temp.id('02')),
  'B (control): con la venta en borrador, sin contabilizar, la restauración resulta');

-- ============================================================================
-- C. El asiento, con las sentencias del motor desplegado
-- ============================================================================
-- Sigue la salida de purga de B (borrar la venta contabilizada) y, como
-- `restore_backup_internal`, sin ajuste de stock.
select pg_temp.act_as('91');
select set_config('app.skip_stock_adjustment_trigger', 'true', true);

-- Borrados del motor (líneas 20, 34, 35 y 44), sólo del taller 01.
delete from public.journal_lines
 where entry_id in (select id from public.journal_entries where tenant_id = pg_temp.id('01'));
delete from public.journal_entries where tenant_id = pg_temp.id('01');
delete from public.sales_payments where tenant_id = pg_temp.id('01');
delete from public.sales_invoices where tenant_id = pg_temp.id('01');

-- Línea 126: reponer las facturas del respaldo.
insert into public.sales_invoices
select * from jsonb_populate_recordset(null::public.sales_invoices,
                                       (select d -> 'sales_invoices' from backup_01));

select results_eq(
  $$select count(*)::integer,
           bool_and(entry.id::text <> (select backup_01.d -> 'journal_entries' -> 0 ->> 'id' from backup_01))
      from public.journal_entries entry
     where entry.tenant_id = pg_temp.id('01')
       and entry.source_module = 'sales_invoices'
       and entry.source_document_id = pg_temp.id('20')$$,
  $$values (1, true)$$,
  'C: la venta repuesta nace con un asiento nuevo, antes de reponer el del respaldo');

-- Línea 171: reponer los asientos del respaldo.
select throws_ok(
  $$insert into public.journal_entries
    select * from jsonb_populate_recordset(null::public.journal_entries,
                                           (select d -> 'journal_entries' from backup_01))$$,
  '23505',
  'duplicate key value violates unique constraint "idx_journal_entries_sales_source_document_unique"',
  'C: el asiento del respaldo choca con el de la reposición');

-- Rama de compra del mismo validador: una factura no borrador también impide
-- prometer un restore aunque no haya una venta contabilizada en el taller.
select pg_temp.act_as('92');
insert into public.purchase_invoices (
  id, tenant_id, invoice_number, status
) values (pg_temp.id('30'), pg_temp.id('02'), 'FC-REPLAY-1', 'cancelled');
select is(
  public.restore_backup_invoice_delete_blocker(pg_temp.id('02')) ->> 'error_code',
  'restore_invoice_delete_blocked',
  'D: una factura de compra no borrador también bloquea el replay');

select is(
  (select count(*) from net.http_request_queue),
  (select n from net_queue_before),
  'nada quedó en la cola de pg_net');

select * from finish();
rollback;
