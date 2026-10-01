-- Inventario de disparadores de INSERT que se ejecutarian durante el replay
-- de las 38 tablas del restore legado. Lectura de catalogo, sin filas de negocio.
-- La mención textual del contexto es sólo una pista: no demuestra que una
-- función suprima efectos ni que deba suprimirse una guardia de integridad.
with covered as (
  select scope.table_name,
         format('public.%I', scope.table_name)::regclass as relation_id
    from public.restore_backup_covered_scope() scope
), enabled_insert_triggers as (
  select covered.table_name,
         trigger_row.tgname as trigger_name,
         trigger_row.tgfoid as function_id,
         position(
           'app.restore_tenant' in lower(pg_get_functiondef(trigger_row.tgfoid))
         ) > 0 as mentions_restore_context
    from covered
    join pg_trigger trigger_row on trigger_row.tgrelid = covered.relation_id
   where not trigger_row.tgisinternal
     and trigger_row.tgenabled in ('O', 'A')
     and (trigger_row.tgtype::integer & 4) = 4
)
select function_id::regprocedure::text as trigger_function,
       count(*)::integer as enabled_insert_triggers,
       bool_or(mentions_restore_context) as mentions_restore_context,
       array_agg(table_name || '.' || trigger_name
                 order by table_name, trigger_name) as trigger_sites
  from enabled_insert_triggers
 group by function_id
 order by enabled_insert_triggers desc, trigger_function;
