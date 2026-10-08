-- Read-back of 20261008010000: the unique index exists over (conversation,
-- sender, client key), only for rows that carry the key, and no keyed message
-- of Viñabike repeats. Read-only; division by zero fails it.
select count(*) as mensajes_con_llave
  from public.messages
 where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and metadata ? 'client_message_id';

select 1/(case when
 (select i.indisunique
     and i.indisvalid
     and pg_get_indexdef(i.indexrelid) like '%(conversation_id, sender_id, ((metadata ->> ''client_message_id''::text)))%'
     and pg_get_expr(i.indpred, i.indrelid) = '(metadata ? ''client_message_id''::text)'
    from pg_index i
   where i.indexrelid = to_regclass('public.messages_one_per_client_key'))
 and (select count(*) = 0 from (
   select 1
     from public.messages
    where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
      and metadata ? 'client_message_id'
    group by conversation_id, sender_id, metadata ->> 'client_message_id'
   having count(*) > 1) repetidos)
then 1 else 0 end) as una_fila_por_llave_ok;
