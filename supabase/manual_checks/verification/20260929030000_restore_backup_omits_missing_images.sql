-- Read-back de 20260929030000_restore_backup_omits_missing_images. Antes de
-- desplegar tiene que fallar contra producción (no hay columna ni función).

select 1 / (case when
  exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'database_backups'
       and column_name = 'restore_report'
       and data_type = 'jsonb')
then 1 else 0 end) as informe_de_restauracion;

select 1 / (case when
  to_regprocedure('public.backup_rows_without_missing_images(jsonb,text,text,uuid)') is not null
  and to_regprocedure('public.restore_backup_legacy_rows_internal(uuid,uuid)') is not null
  and pg_get_functiondef('public.restore_backup_legacy_unsafe_internal(uuid,uuid)'::regprocedure)
    like '%omitted_attachments%'
  and pg_get_functiondef('public.restore_backup_legacy_unsafe_internal(uuid,uuid)'::regprocedure)
    like '%restore_backup_legacy_rows_internal(v_copy_id, p_tenant_id)%'
  and pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure)
    like '%restore_report%'
  and pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure)
    like '%can_manage_tenant_backups(p_tenant_id)%'
then 1 else 0 end) as restauracion_omite_lo_ausente;

-- La negativa vive en la entrada y en el motor: el motor toma las filas del
-- taller antes de volver a contar.
select 1 / (case when
  pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure)
    like '%restore_backup_missing_tables(v_data)%'
  and pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure)
    like '%restore_backup_uncovered_dependents(p_tenant_id)%'
  and pg_get_functiondef('public.restore_backup_legacy_unsafe_internal(uuid,uuid)'::regprocedure)
    like '%restore_backup_missing_tables(v_data)%'
  and pg_get_functiondef('public.restore_backup_legacy_unsafe_internal(uuid,uuid)'::regprocedure)
    like '%in share row exclusive mode%'
  and pg_get_functiondef('public.restore_backup_legacy_unsafe_internal(uuid,uuid)'::regprocedure)
    like '%for update%'
  and pg_get_functiondef('public.restore_backup_legacy_unsafe_internal(uuid,uuid)'::regprocedure)
    like '%restore_backup_uncovered_dependents(p_tenant_id)%'
  and pg_get_functiondef('public.restore_backup_preflight(uuid,uuid)'::regprocedure)
    like '%restore_backup_foundation_blocker(v_data, p_tenant_id)%'
then 1 else 0 end) as niega_en_la_entrada_y_en_el_motor;

-- El alcance que usan la guardia y el bloqueo es, tabla por tabla, el borrado
-- de la restauración: mismas tablas y misma condición. Si se separan, la
-- guardia dejaría de ver lo que se pierde.
select 1 / (case when
  (select array_agg(distinct m[1] order by m[1])
     from regexp_matches(
       pg_get_functiondef('public.restore_backup_legacy_rows_internal(uuid,uuid)'::regprocedure),
       'delete from ([a-z_]+)', 'g') as m)
  = (select array_agg(t order by t)
       from unnest(public.restore_backup_covered_tables()) as t)
  and not exists (
    select 1
      from public.restore_backup_covered_scope() scope
     where position(
             regexp_replace('delete from ' || scope.table_name || ' where '
                            || scope.predicate || ';', '\s+', ' ', 'g')
             in regexp_replace(
               pg_get_functiondef('public.restore_backup_legacy_rows_internal(uuid,uuid)'::regprocedure),
               '\s+', ' ', 'g')) = 0)
then 1 else 0 end) as alcance_igual_al_borrado;

select 1 / (case when
  has_function_privilege('authenticated', 'public.restore_backup(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.restore_backup(uuid,uuid)', 'EXECUTE')
  and not exists (
    select 1
      from unnest(array['anon', 'authenticated', 'service_role']) as role_name,
           unnest(array[
             'public.backup_rows_without_missing_images(jsonb,text,text,uuid)',
             'public.restore_backup_legacy_unsafe_internal(uuid,uuid)',
             'public.restore_backup_legacy_rows_internal(uuid,uuid)',
             'public.restore_backup_uncovered_dependents(uuid)',
             'public.restore_backup_covered_scope()',
             'public.restore_backup_covered_tables()',
             'public.restore_backup_table_label(text)',
             'public.restore_backup_missing_tables(jsonb)',
             'public.restore_backup_incomplete_message(text[])',
             'public.restore_backup_refusal_message(jsonb)',
             'public.restore_backup_foundation_blocker(jsonb,uuid)']) as fn
     where has_function_privilege(role_name, fn, 'EXECUTE'))
  and has_function_privilege('authenticated', 'public.restore_backup_preflight(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.restore_backup_preflight(uuid,uuid)', 'EXECUTE')
then 1 else 0 end) as permisos_de_restauracion;
