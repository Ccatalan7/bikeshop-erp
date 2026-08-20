-- Purpose: `message_reactions` quedó fuera de la publicación de realtime, así
-- que una reacción nueva no llegaba a los clientes conectados.
--
-- El síntoma engañaba: las reacciones YA guardadas sí aparecían, porque
-- `.stream()` de Supabase hace una consulta inicial antes de escuchar. Sólo las
-- que llegaban con el chat abierto se perdían — exactamente el caso que uno
-- prueba y el que más importa.
--
-- `replica identity full` es necesario además del alta en la publicación: el
-- cliente filtra el stream por `conversation_id`, y en un DELETE con la
-- identidad por defecto sólo viaja la llave primaria. Sin la fila completa el
-- filtro no se puede evaluar y quitar una reacción no desaparecería en vivo,
-- que es la mitad de la función.

alter table public.message_reactions replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end;
$$;
