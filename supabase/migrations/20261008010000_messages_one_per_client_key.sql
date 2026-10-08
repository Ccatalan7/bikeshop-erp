-- Un mensaje por llave del cliente.
--
-- Quien escribe marca cada envío con `metadata.client_message_id` y lo repite
-- cuando se perdió la respuesta: el chat del portal en HTML reintenta con la
-- misma llave, la bandeja de WhatsApp y los envíos de Meta la heredan de su
-- intento. La tienda buscaba la llave antes de insertar, pero dos pedidos a la
-- vez podían no verla los dos y dejar el mensaje repetido. La regla vive aquí:
-- la misma persona no puede dejar dos filas con la misma llave en la misma
-- conversación, y el segundo insert recibe 23505 en vez de duplicar.
--
-- Producción no repite ninguna llave (2026-10-08: 196 de 495 mensajes la
-- llevan), así que el índice nace sin limpiar nada. Las filas sin llave, o con
-- la llave en null, quedan fuera.
create unique index if not exists messages_one_per_client_key
  on public.messages (
    conversation_id,
    sender_id,
    (metadata ->> 'client_message_id')
  )
  where metadata ? 'client_message_id';

comment on index public.messages_one_per_client_key is
  'Un envío reintentado con la misma metadata.client_message_id no deja dos '
  'mensajes de la misma persona en la misma conversación (2026-10-08).';
