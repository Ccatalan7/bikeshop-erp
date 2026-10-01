-- Guard the existing restore entrypoints before DELETE reaches the posted
-- invoice validator. No replay/purge/trigger behavior changes here.
-- Forward: preflight and restore_backup deny when current sales or purchase
-- invoices fail the exact DELETE predicate (non-draft or active payment).
-- Recovery: replace these two function bodies with the verified 030000 bodies;
-- the new helper is inert once neither entrypoint calls it. No data backfill.
-- Locks: CREATE OR REPLACE FUNCTION only; no table rewrite or business writes.
begin;

create or replace function public.restore_backup_invoice_delete_blocker(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
begin
  if exists (
    select 1 from public.sales_invoices invoice
     where invoice.tenant_id = p_tenant_id
       and (lower(coalesce(invoice.status, 'draft')) not in ('draft', 'borrador')
            or exists (
              select 1 from public.sales_payments payment
               where payment.invoice_id = invoice.id
                 and payment.deleted_at is null))
  ) or exists (
    select 1 from public.purchase_invoices invoice
     where invoice.tenant_id = p_tenant_id
       and (lower(coalesce(invoice.status, 'draft')) not in ('draft', 'borrador')
            or exists (
              select 1 from public.purchase_payments payment
               where payment.invoice_id = invoice.id
                 and payment.deleted_at is null))
  ) then
    return jsonb_build_object(
      'error_code', 'restore_invoice_delete_blocked',
      'message', 'No se restauró nada: hay facturas de venta o compra fuera de borrador o con pagos activos. Este restaurador no puede reemplazarlas de forma segura; puedes descargar el respaldo.'
    );
  end if;
  return null;
end;
$function$;

revoke all on function public.restore_backup_invoice_delete_blocker(uuid)
  from public, anon, authenticated, service_role;
comment on function public.restore_backup_invoice_delete_blocker(uuid) is
  'Niega antes del replay si el validador de DELETE de facturas no aceptaría las filas actuales del taller.';

create or replace function public.restore_backup_preflight(
  p_backup_id uuid,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_data jsonb;
  v_missing text[];
  v_dependents jsonb;
  v_blocker jsonb;
  v_invoice_blocker jsonb;
begin
  if auth.role() is distinct from 'service_role'
     and not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;

  select backup.backup_data
    into v_data
    from public.database_backups backup
   where backup.id = p_backup_id
     and backup.tenant_id = p_tenant_id
     and backup.status = 'completed';
  if v_data is null then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;

  v_missing := public.restore_backup_missing_tables(v_data);
  v_dependents := public.restore_backup_uncovered_dependents(p_tenant_id);
  v_blocker := public.restore_backup_foundation_blocker(v_data, p_tenant_id);
  v_invoice_blocker := public.restore_backup_invoice_delete_blocker(p_tenant_id);
  return jsonb_build_object(
    'can_restore', cardinality(v_missing) = 0
                   and jsonb_array_length(v_dependents) = 0
                   and v_blocker is null
                   and v_invoice_blocker is null,
    'message', case
      when cardinality(v_missing) > 0
        then public.restore_backup_incomplete_message(v_missing)
      when jsonb_array_length(v_dependents) > 0
        then public.restore_backup_refusal_message(v_dependents)
      when v_blocker is not null then v_blocker ->> 'message'
      else v_invoice_blocker ->> 'message' end,
    'missing_tables', coalesce((
      select jsonb_agg(jsonb_build_object(
               'table', t, 'label', public.restore_backup_table_label(t))
             order by o)
        from unnest(v_missing) with ordinality as missing(t, o)), '[]'::jsonb),
    'uncovered_dependents', v_dependents,
    'foundation_blocker', v_blocker,
    'posted_invoice_blocker', v_invoice_blocker,
    'omitted_attachments',
    (public.backup_rows_without_missing_images(
       v_data -> 'bikes', 'bikes', 'bike-images', p_tenant_id) -> 'omitted')
    || (public.backup_rows_without_missing_images(
       v_data -> 'mechanic_jobs', 'mechanic_jobs', 'job-images', p_tenant_id)
       -> 'omitted')
  );
end;
$function$;

create or replace function public.restore_backup(p_backup_id uuid, p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_data jsonb;
  v_missing text[];
  v_result jsonb;
  v_dependents jsonb;
  v_invoice_blocker jsonb;
begin
  if auth.role() is distinct from 'service_role'
     and not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied'
      using errcode = '42501';
  end if;

  select backup.backup_data
    into v_data
    from public.database_backups backup
   where backup.id = p_backup_id
     and backup.tenant_id = p_tenant_id
     and backup.status = 'completed';
  if v_data is null then
    raise exception 'Backup access denied'
      using errcode = '42501';
  end if;

  -- Restaurar nunca borra lo que no devuelve: ni una tabla que el respaldo no
  -- trae, ni filas que dependen de lo que borraría. No se toca nada y se dice
  -- qué. El motor lo vuelve a comprobar con las filas ya tomadas.
  v_missing := public.restore_backup_missing_tables(v_data);
  if cardinality(v_missing) > 0 then
    return jsonb_build_object(
      'success', false,
      'error_code', 'restore_backup_incomplete',
      'message', public.restore_backup_incomplete_message(v_missing),
      'missing_tables', to_jsonb(v_missing),
      'backup_id', p_backup_id
    );
  end if;

  v_dependents := public.restore_backup_uncovered_dependents(p_tenant_id);
  if jsonb_array_length(v_dependents) > 0 then
    return jsonb_build_object(
      'success', false,
      'error_code', 'restore_would_lose_uncovered_data',
      'message', public.restore_backup_refusal_message(v_dependents),
      'uncovered_dependents', v_dependents,
      'backup_id', p_backup_id
    );
  end if;

  -- The posted-document validator would reject these rows on DELETE. Do not
  -- offer a restore that can only fail after entering the replacement motor.
  v_invoice_blocker := public.restore_backup_invoice_delete_blocker(p_tenant_id);
  if v_invoice_blocker is not null then
    return jsonb_build_object(
      'success', false,
      'error_code', v_invoice_blocker ->> 'error_code',
      'message', v_invoice_blocker ->> 'message',
      'backup_id', p_backup_id
    );
  end if;

  v_result := public.restore_backup_internal(p_backup_id, p_tenant_id);

  -- El informe queda en el respaldo: qué adjuntos se omitieron (o ninguno).
  if coalesce((v_result ->> 'success')::boolean, false) then
    update public.database_backups backup
       set restore_report = jsonb_build_object(
             'restored_at', clock_timestamp(),
             'omitted_attachments',
             coalesce(v_result -> 'omitted_attachments', '[]'::jsonb))
     where backup.id = p_backup_id
       and backup.tenant_id = p_tenant_id;
  end if;

  return v_result;
end;
$function$;

comment on function public.restore_backup_preflight(uuid, uuid) is
  'Antes de ofrecer Restaurar: niega tablas ausentes, dependientes, cambios de base y facturas que el validador no deja reemplazar.';
comment on function public.restore_backup(uuid, uuid) is
  'Restaura sólo tras verificar tablas, dependientes y facturas reemplazables; el motor legado sigue protegido por sus validadores.';

commit;
