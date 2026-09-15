-- Read-back de 20260821250000_predicate_matcher_reads_registry.sql

select
  public.assistant_inventory_technical_predicate_source_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid,
    'bb_construction', 'eq', '["Rodamiento sellado"]'::jsonb, '', ''
  ) as calza_construccion,
  public.assistant_inventory_technical_predicate_source_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid,
    'spindle_length_mm', 'eq', '[118]'::jsonb, '', ''
  ) as calza_largo,
  public.assistant_inventory_technical_predicate_source_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890'::uuid,
    'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid,
    'bb_construction', 'eq', '["Cubetas y canastillo"]'::jsonb, '', ''
  ) as no_calza_otra_construccion;

select
  -- El matcher lee el registro y ya no la tabla vieja.
  1 / (case when (select count(*) from pg_proc
        where proname = 'assistant_inventory_technical_predicate_source_internal_v1'
          and pg_get_functiondef(oid) like '%public.spec_facts%'
          and pg_get_functiondef(oid) not like '%from public.product_spec_values%') = 1
      then 1 else 0 end) as afirma_lee_el_registro,

  -- Y sigue resolviendo igual: el motor de referencia calza por construccion.
  1 / (case when public.assistant_inventory_technical_predicate_source_internal_v1(
        '5443b130-cc28-45af-a420-cd500b288890'::uuid,
        'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid,
        'bb_construction', 'eq', '["Rodamiento sellado"]'::jsonb, '', ''
      ) = 'product_spec' then 1 else 0 end) as afirma_calza_por_construccion,

  -- Por su largo de eje.
  1 / (case when public.assistant_inventory_technical_predicate_source_internal_v1(
        '5443b130-cc28-45af-a420-cd500b288890'::uuid,
        'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid,
        'spindle_length_mm', 'eq', '[118]'::jsonb, '', ''
      ) = 'product_spec' then 1 else 0 end) as afirma_calza_por_largo,

  -- Y sigue RECHAZANDO lo que no corresponde: sin esto el filtro diria que si
  -- a todo, que es peor que no filtrar.
  1 / (case when public.assistant_inventory_technical_predicate_source_internal_v1(
        '5443b130-cc28-45af-a420-cd500b288890'::uuid,
        'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid,
        'bb_construction', 'eq', '["Cubetas y canastillo"]'::jsonb, '', ''
      ) = 'conflict' then 1 else 0 end) as afirma_rechaza_lo_que_no_calza;
