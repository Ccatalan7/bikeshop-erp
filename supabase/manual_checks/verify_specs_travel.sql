-- Read-back: la ficha viaja con el producto en el buscador.
select
  1 / (case when exists (
    select 1 from pg_proc where proname = 'assistant_search_inventory_v7'
      and prosrc like '%technicalSpecs%'
  ) then 1 else 0 end) as campo_presente,
  -- El producto de prueba tiene mano de rosca cargada, que es el dato que el
  -- nombre NO trae y que antes mandaba al asistente a internet.
  1 / (case when exists (
    select 1 from public.products p
    join public.spec_facts f on f.subject_id = p.id and f.subject_type = 'product'
    join public.spec_definitions d on d.id = f.spec_definition_id
      and d.key = 'bb_cup_thread_pair'
    where p.sku = '10561'
  ) then 1 else 0 end) as dato_solo_en_ficha;
