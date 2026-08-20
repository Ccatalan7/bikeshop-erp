-- Read-back de 20260820040000_fix_whatsapp_ingest_binding_arity.sql
--
-- SQL plano (los bloques plpgsql no pasan el camino de lectura alojada).

select
  (
    select position('p_context_id,
    null,
    null' in pg_get_functiondef(p.oid))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'ingest_whatsapp_inbound_message'
    limit 1
  ) as tiene_la_llamada_rota,
  (
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'ensure_whatsapp_conversation_binding'
  ) as firmas_del_binding;

select
  -- La llamada de diez argumentos es la que dejó sin mensajes entrantes al
  -- negocio. No puede volver a aparecer en el cuerpo de la función.
  1 / (case when (
              select position('p_context_id,
    null,
    null' in pg_get_functiondef(p.oid))
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and p.proname = 'ingest_whatsapp_inbound_message'
              limit 1) = 0
            then 1 else 0 end) as afirma_sin_llamada_rota,

  -- Y la rama de reacción tiene que seguir ahí.
  1 / (case when (
              select position('message_reactions' in pg_get_functiondef(p.oid))
              from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and p.proname = 'ingest_whatsapp_inbound_message'
              limit 1) > 0
            then 1 else 0 end) as afirma_reaccion_intacta;
