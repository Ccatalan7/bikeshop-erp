-- Read-back de 20260820020000_whatsapp_message_reactions.sql
--
--   scripts/db/query.sh production \
--     --file supabase/manual_checks/verify_whatsapp_message_reactions.sql
--
-- SQL PLANO A PROPÓSITO. El camino de lectura alojada rechaza cualquier bloque
-- `do $$ ... end; $$` porque el guard de transacciones ve el `end;` de plpgsql
-- y lo confunde con un END de transacción. Un read-back escrito con DO no se
-- puede correr contra producción, aunque funcione perfecto en local.
--
-- La primera consulta imprime el estado real, para que el operador lo vea en
-- el log. La segunda es la que muerde: divide por cero cuando el invariante no
-- está, de modo que query.sh sale distinto de cero y deploy_migration.sh
-- aborta antes de sellar la migración. Si ves «division by zero», mira la
-- columna que lo provocó y la fila de diagnóstico de arriba.

select
  (to_regclass('public.message_reactions') is not null) as tabla_existe,
  (
    select count(*) from pg_indexes
    where schemaname = 'public'
      and tablename = 'message_reactions'
      and indexname = 'message_reactions_one_per_reactor'
  ) as indice_una_por_persona,
  (
    select count(*) from pg_policies
    where schemaname = 'public' and tablename = 'message_reactions'
  ) as politicas_rls,
  (
    select coalesce(
      position('message_reactions' in pg_get_functiondef(p.oid)) > 0,
      false
    )
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'ingest_whatsapp_inbound_message'
    limit 1
  ) as ingreso_escribe_reacciones,
  (
    select count(*) from public.messages
    where external_provider = 'whatsapp'
      and message_direction = 'inbound'
      and metadata->>'message_type' = 'reaction'
  ) as mensajes_basura_restantes,
  (select count(*) from public.message_reactions) as reacciones_guardadas;

select
  -- La tabla tiene que existir.
  1 / (case when to_regclass('public.message_reactions') is not null
            then 1 else 0 end) as afirma_tabla,

  -- Sin el índice único, la misma persona podría acumular varias reacciones
  -- sobre un mensaje, que no es lo que hace WhatsApp.
  1 / (case when exists (
              select 1 from pg_indexes
              where schemaname = 'public'
                and tablename = 'message_reactions'
                and indexname = 'message_reactions_one_per_reactor')
            then 1 else 0 end) as afirma_una_reaccion_por_persona,

  -- Cuatro políticas: leer donde se lee el mensaje, y escribir sólo la propia.
  1 / (case when (
              select count(*) from pg_policies
              where schemaname = 'public'
                and tablename = 'message_reactions'
                and policyname in (
                  'message_reactions_select_scoped',
                  'message_reactions_insert_own',
                  'message_reactions_update_own',
                  'message_reactions_delete_own')) = 4
            then 1 else 0 end) as afirma_aislamiento,

  -- El ingreso tiene que reconocer la reacción; si no, vuelve a entrar como un
  -- mensaje de texto con la palabra «reaction».
  1 / (case when (
              select position('message_reactions' in pg_get_functiondef(p.oid))
              from pg_proc p
              join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and p.proname = 'ingest_whatsapp_inbound_message'
              limit 1) > 0
            then 1 else 0 end) as afirma_ingreso_reconoce_reaccion,

  -- Y no puede quedar ningún mensaje falso del defecto anterior.
  1 / (case when (
              select count(*) from public.messages
              where external_provider = 'whatsapp'
                and message_direction = 'inbound'
                and metadata->>'message_type' = 'reaction') = 0
            then 1 else 0 end) as afirma_sin_mensajes_basura;
