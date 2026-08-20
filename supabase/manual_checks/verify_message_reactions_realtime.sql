-- Read-back de 20260820030000_message_reactions_realtime.sql
--
-- SQL plano: el camino de lectura alojada rechaza los bloques `do $$ … end; $$`
-- (ver AGENT_DATABASE_CONTRACT.md).

select
  (
    select count(*) from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) as en_publicacion_realtime,
  (
    select relreplident from pg_class
    where oid = 'public.message_reactions'::regclass
  ) as identidad_de_replica;

select
  -- Sin esto, una reacción que llega con el chat abierto no se pinta nunca.
  1 / (case when exists (
              select 1 from pg_publication_tables
              where pubname = 'supabase_realtime'
                and schemaname = 'public'
                and tablename = 'message_reactions')
            then 1 else 0 end) as afirma_realtime_publicado,

  -- 'f' = full. Sin la fila completa, el filtro por conversación no se puede
  -- evaluar en un DELETE y quitar una reacción no desaparecería en vivo.
  1 / (case when (
              select relreplident from pg_class
              where oid = 'public.message_reactions'::regclass) = 'f'
            then 1 else 0 end) as afirma_identidad_full;
