-- Read-back de 20260821230000_website_reads_the_registry.sql

select section_key, spec_label, display_value, unit
from public.get_public_product_technical_specs(
  '5443b130-cc28-45af-a420-cd500b288890'::uuid,
  'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid)
order by section_sort_order, field_sort_order;

select
  -- La tienda ya no lee la tabla vieja.
  1 / (case when (select count(*) from pg_proc
        where proname = 'get_public_product_technical_specs'
          and pg_get_functiondef(oid) not like '%product_spec_values%') = 1
      then 1 else 0 end) as afirma_no_lee_la_tabla_vieja,

  -- Lee el registro unificado.
  1 / (case when (select count(*) from pg_proc
        where proname = 'get_public_product_technical_specs'
          and pg_get_functiondef(oid) like '%spec_facts%'
          and pg_get_functiondef(oid) like '%spec_definition_values%') = 1
      then 1 else 0 end) as afirma_lee_el_registro,

  -- Y devuelve exactamente lo mismo que antes para el motor de referencia:
  -- cinco filas, con la caja y la construccion resueltas desde el registro.
  1 / (case when (select count(*) from public.get_public_product_technical_specs(
        '5443b130-cc28-45af-a420-cd500b288890'::uuid,
        'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid)) = 5
      then 1 else 0 end) as afirma_cinco_filas,

  1 / (case when exists (select 1 from public.get_public_product_technical_specs(
        '5443b130-cc28-45af-a420-cd500b288890'::uuid,
        'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid) e
        where e.spec_label = 'Caja de motor'
          and e.display_value = 'BSA / Caja inglesa 34,8 mm (1.37") x 24')
      then 1 else 0 end) as afirma_caja_resuelta_desde_el_registro,

  1 / (case when exists (select 1 from public.get_public_product_technical_specs(
        '5443b130-cc28-45af-a420-cd500b288890'::uuid,
        'd9f9f4b3-710d-4bc1-8284-96b206cf0615'::uuid) e
        where e.spec_label = 'Largo eje' and e.display_value = '118')
      then 1 else 0 end) as afirma_medidas_intactas;
