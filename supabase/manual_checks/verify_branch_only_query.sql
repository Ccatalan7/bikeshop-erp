-- Read-back: nombrar una rama basta para soltar el texto libre.
select
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_inventory_v7'
      and prosrc like '%v_inferred_categories is not null%'
  ) then 1 else 0 end) as regla_presente,
  -- La inferencia devuelve la rama aunque no haya ningún filtro técnico.
  1 / (case when jsonb_array_length((
    select public.assistant_infer_technical_predicates_internal_v1(
      '5443b130-cc28-45af-a420-cd500b288890'::uuid, 'los 5 motores mas caros'
    ) -> 'categories'
  )) > 0 then 1 else 0 end) as rama_sin_filtro_tecnico,
  -- Y una identidad suelta sigue sin rama, así que su texto no se toca.
  1 / (case when jsonb_array_length((
    select public.assistant_infer_technical_predicates_internal_v1(
      '5443b130-cc28-45af-a420-cd500b288890'::uuid, 'VP-BC73'
    ) -> 'categories'
  )) = 0 then 1 else 0 end) as identidad_intacta;
