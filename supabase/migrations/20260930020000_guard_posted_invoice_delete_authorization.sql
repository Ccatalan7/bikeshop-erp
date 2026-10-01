-- La salida de purga del guard de facturas contabilizadas deja de ser una
-- variable de sesión (2026-09-30).
--
-- `guard_posted_invoice_delete()` (20260712113000) es SECURITY DEFINER: dentro
-- de ella `current_user` es su dueño, así que `current_user in ('postgres',
-- 'service_role')` siempre era verdadero y la purga dependía sólo de
-- `app.allow_posted_document_purge`, que cualquier rol fija con `set_config`.
-- Un authenticated de su propio taller borraba así una venta contabilizada y
-- su asiento (reproducido en local: supabase/tests/posted_invoice_purge_role_guard_local.sql).
--
-- Ahora la purga exige una autorización privada de esa fila, en esa
-- transacción y ese taller, que el guard consume una vez. La abre
-- `authorize_posted_document_purge`: el permiso EXECUTE lo comprueba
-- PostgreSQL contra el rol que llama (service_role, el backend, o el dueño);
-- authenticated y anon no pueden, tampoco con un claim inventado. Nada lee
-- variables, claims ni `current_user`. Nadie usaba la variable (ni la app, ni
-- funciones, ni scripts): la cancelación (UPDATE de estado) y el borrado de
-- borradores siguen iguales, y el restore legado sigue negándose.
--
-- Sin backfill ni cambios de datos de negocio. El reemplazo sólo toma locks
-- de catálogo; los timeouts acotan una espera por DDL concurrente.
-- Recuperación: una reparación posterior debe conservar el rechazo a purgas
-- no autorizadas; no reinstalar el bypass GUC vulnerable.
-- Idempotente hasta el stamp APPLIED: sólo acepta la definición original o
-- las tres funciones exactas de este forward, no una coincidencia de texto.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $precondition$
declare
  v_def text := pg_get_functiondef('public.guard_posted_invoice_delete()'::regprocedure);
  v_original boolean;
  v_installed boolean;
begin
  v_original := md5(v_def) = 'ddb0b13b7e4d511a3826c115efb79271';
  select count(*) = 3 and bool_and(
    p.prosecdef and p.proowner = g.proowner
    and md5(p.prosrc) = expected.source_md5
    and p.proconfig = expected.config
  ) into v_installed
  from (values
    ('public.guard_posted_invoice_delete()',
     '1370040447ca73d47d14661907410ede', array['search_path=public']),
    ('public.authorize_posted_document_purge(uuid,text,uuid[],text)',
     'cf0f508c91eac15b2c55b704ed268dbf', array['search_path=pg_catalog, public, pg_temp']),
    ('public.consume_posted_document_purge_internal(uuid,text,uuid)',
     'ebb27d958f5a0f9576d2c1fafdfc3204', array['search_path=pg_catalog, public, pg_temp'])
  ) as expected(signature, source_md5, config)
  join pg_proc p on p.oid = to_regprocedure(expected.signature)
  join pg_proc g on g.oid = 'public.guard_posted_invoice_delete()'::regprocedure;

  if not v_original and not coalesce(v_installed, false) then
    raise exception 'El guard o su autorización tienen una definición desconocida; revisar antes de reemplazarlos'
      using errcode = '55000';
  end if;
  if v_original and (
    to_regclass('public.posted_document_purge_authorizations') is not null
    or to_regprocedure('public.authorize_posted_document_purge(uuid,text,uuid[],text)') is not null
    or to_regprocedure('public.consume_posted_document_purge_internal(uuid,text,uuid)') is not null
  ) then
    raise exception 'Los nombres de autorización ya existen con el guard original; revisar la colisión'
      using errcode = '55000';
  end if;
  if not v_original and to_regclass('public.posted_document_purge_authorizations') is null then
    raise exception 'La autorización instalada carece de su tabla privada; revisar el estado parcial'
      using errcode = '55000';
  end if;
end;
$precondition$;

create table if not exists public.posted_document_purge_authorizations (
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
-- en su transacción. authenticated y anon no pueden ejecutarla.
create or replace function public.authorize_posted_document_purge(
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

comment on function public.authorize_posted_document_purge(uuid, text, uuid[], text) is
  'Backend-only (service_role or owner): authorizes the purge of specific posted invoices of one tenant in the current transaction; guard_posted_invoice_delete consumes each row once.';

create or replace function public.consume_posted_document_purge_internal(
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

-- El mismo guard de 20260712113000, con una sola línea cambiada: la salida de
-- purga es la autorización privada de esta fila.
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

commit;
