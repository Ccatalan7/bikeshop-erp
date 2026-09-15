-- Una sola firma para el recibo de búsqueda de portal.
--
-- **El defecto que introduje.** `20260830040000` agregó `p_operation_key` con
-- `DEFAULT NULL` sobre `record_supplier_need_portal_search_v1` **sin retirar la
-- firma anterior**. Postgres identifica una función por su lista de argumentos,
-- así que no reemplazó nada: quedaron CUATRO overloads (7, 8, 12 y 13
-- argumentos). Es exactamente el fallo que `AGENT_DATABASE_CONTRACT` documenta
-- desde el 2026-08-22 —«agregar un parámetro con default NO reemplaza la
-- función: la duplica»— y que ya había costado 38 herramientas del asistente
-- muriendo calladas.
--
-- No aparece al aplicar: aparece cuando alguien llama. Una llamada de 12
-- argumentos ya no puede resolverse entre la firma de 12 y la de 13 con
-- default, y muere con `42725 is not unique`.
--
-- **Lo que hace.** Deja **una sola** firma, la de 13. Como el último parámetro
-- tiene default, una llamada de 12 argumentos sigue resolviendo contra ella;
-- las de 7 y 8 eran el contrato viejo de una base sin migrar y en producción no
-- las llama nadie.
--
-- El read-back que la acompaña no se conforma con contar: **ejecuta las rutas
-- reales** y exige que fallen por falta de contexto de negocio (`42501`) y no
-- por ambigüedad (`42725`), que es la única forma de probar que la resolución
-- funciona sin escribir una fila.

begin;

drop function if exists public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
);

drop function if exists public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
);

drop function if exists public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb, bigint, bigint, uuid, text
);

commit;
