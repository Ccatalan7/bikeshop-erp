-- Guard the legacy full-recordset replay against columns missing from an
-- older backup. The current motor writes NULL for omitted keys, even when a
-- column has a DEFAULT; it also ignores unknown keys. No row is restored here.
-- Recovery: restore the verified 120000 entrypoint bodies. The helper becomes
-- inert when those functions no longer call it. No table rewrite/backfill.
begin;

create or replace function public.restore_backup_legacy_column_blocker(
  p_data jsonb
)
returns jsonb
language plpgsql
stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_table text;
  v_column text;
  v_reason text;
begin
  -- INSERT INTO table SELECT * also supplies an explicit value for an
  -- identity GENERATED ALWAYS column. The old motor has no OVERRIDING clause.
  select scope.table_name, a.attname, 'identity_replay'
    into v_table, v_column, v_reason
    from public.restore_backup_covered_scope() scope
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(p_data -> scope.table_name) = 'array'
           then p_data -> scope.table_name else '[]'::jsonb end
    ) with ordinality as item(value, row_number)
    join pg_catalog.pg_class c
      on c.relnamespace = 'public'::regnamespace
     and c.relname = scope.table_name
     and c.relkind in ('r', 'p')
    join pg_catalog.pg_attribute a
      on a.attrelid = c.oid
     and a.attnum > 0
     and not a.attisdropped
     and a.attidentity = 'a'
   order by scope.ord, item.row_number, a.attnum
   limit 1;

  if v_table is null then
  select scope.table_name, a.attname,
         case
           when jsonb_typeof(item.value) <> 'object' then 'malformed_row'
           when not (item.value ? a.attname) and a.atthasdef
             then 'missing_default'
           when not (item.value ? a.attname) then 'missing_required'
           else 'explicit_null'
         end
    into v_table, v_column, v_reason
    from public.restore_backup_covered_scope() scope
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(p_data -> scope.table_name) = 'array'
           then p_data -> scope.table_name else '[]'::jsonb end
    ) with ordinality as item(value, row_number)
    join pg_catalog.pg_class c
      on c.relnamespace = 'public'::regnamespace
     and c.relname = scope.table_name
     and c.relkind in ('r', 'p')
    join pg_catalog.pg_attribute a
      on a.attrelid = c.oid
     and a.attnum > 0
     and not a.attisdropped
     and a.attgenerated = ''
     and (a.attnotnull or a.atthasdef)
   where jsonb_typeof(item.value) <> 'object'
      or not (item.value ? a.attname)
      or (a.attnotnull and item.value -> a.attname = 'null'::jsonb)
   order by scope.ord, item.row_number, a.attnum
   limit 1;
  end if;

  if v_table is null then
    select scope.table_name, key.name, 'unknown_column'
      into v_table, v_column, v_reason
      from public.restore_backup_covered_scope() scope
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(p_data -> scope.table_name) = 'array'
             then p_data -> scope.table_name else '[]'::jsonb end
      ) with ordinality as item(value, row_number)
      cross join lateral jsonb_object_keys(
        case when jsonb_typeof(item.value) = 'object'
             then item.value else '{}'::jsonb end
      ) as key(name)
      join pg_catalog.pg_class c
        on c.relnamespace = 'public'::regnamespace
       and c.relname = scope.table_name
       and c.relkind in ('r', 'p')
     where not exists (
       select 1 from pg_catalog.pg_attribute a
        where a.attrelid = c.oid
          and a.attnum > 0
          and not a.attisdropped
          and a.attname = key.name
     )
     order by scope.ord, item.row_number, key.name
     limit 1;
  end if;

  if v_table is null then
    return null;
  end if;

  return jsonb_build_object(
    'error_code', 'restore_backup_legacy_column_blocked',
    'table', v_table,
    'column', v_column,
    'reason', v_reason,
    'message', 'No se restauró nada: este respaldo no es compatible con los campos actuales de '
      || public.restore_backup_table_label(v_table)
      || '. Este restaurador aún no puede reponerlo sin alterar datos; puedes descargar el respaldo.'
  );
end;
$function$;

revoke all on function public.restore_backup_legacy_column_blocker(jsonb)
  from public, anon, authenticated, service_role;
comment on function public.restore_backup_legacy_column_blocker(jsonb) is
  'Niega el replay legado ante identidad ALWAYS, columnas NOT NULL o con DEFAULT omitidas, NULL explícito en NOT NULL o claves desconocidas. Sólo lee el catálogo y el JSON del respaldo.';

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
  v_schema_blocker jsonb;
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
  if cardinality(v_missing) = 0
     and jsonb_array_length(v_dependents) = 0
     and v_blocker is null
     and v_invoice_blocker is null then
    v_schema_blocker := public.restore_backup_legacy_column_blocker(v_data);
  end if;
  return jsonb_build_object(
    'can_restore', cardinality(v_missing) = 0
                   and jsonb_array_length(v_dependents) = 0
                   and v_blocker is null
                   and v_invoice_blocker is null
                   and v_schema_blocker is null,
    'message', case
      when cardinality(v_missing) > 0
        then public.restore_backup_incomplete_message(v_missing)
      when jsonb_array_length(v_dependents) > 0
        then public.restore_backup_refusal_message(v_dependents)
      when v_blocker is not null then v_blocker ->> 'message'
      when v_invoice_blocker is not null then v_invoice_blocker ->> 'message'
      else v_schema_blocker ->> 'message' end,
    'missing_tables', coalesce((
      select jsonb_agg(jsonb_build_object(
               'table', t, 'label', public.restore_backup_table_label(t))
             order by o)
        from unnest(v_missing) with ordinality as missing(t, o)), '[]'::jsonb),
    'uncovered_dependents', v_dependents,
    'foundation_blocker', v_blocker,
    'posted_invoice_blocker', v_invoice_blocker,
    'legacy_column_blocker', v_schema_blocker,
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
  v_schema_blocker jsonb;
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

  -- A full-recordset INSERT would replace omitted DEFAULTs with NULL (or
  -- fail on NOT NULL). Refuse before the replacement motor deletes any row.
  v_schema_blocker := public.restore_backup_legacy_column_blocker(v_data);
  if v_schema_blocker is not null then
    return jsonb_build_object(
      'success', false,
      'error_code', v_schema_blocker ->> 'error_code',
      'message', v_schema_blocker ->> 'message',
      'legacy_column_blocker', v_schema_blocker,
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
  'Antes de ofrecer Restaurar: niega tablas ausentes, dependientes, cambios de base, facturas no reemplazables y columnas que el replay legado convertiría en NULL.';
comment on function public.restore_backup(uuid, uuid) is
  'Restaura sólo tras verificar tablas, dependientes, facturas reemplazables y columnas compatibles con el motor legado.';

commit;
