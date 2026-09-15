-- Read-back de 20260820240000_valve_length_real_vocabulary.sql

select key, allowed_values from public.spec_definitions
where key = 'valve_length_mm' and tenant_id is null;

select
  -- Los dos largos Presta mas vendidos entran al vocabulario.
  1 / (case when (
        select count(*) from public.spec_definitions d
        cross join lateral jsonb_array_elements(d.allowed_values) v
        where d.key = 'valve_length_mm' and d.tenant_id is null
          and v #>> '{}' in ('40', '48')) = 2
      then 1 else 0 end) as afirma_cuarenta_y_cuarentaiocho,

  -- Ningun valor de valvula queda fuera de su propia lista: sin esto el
  -- asistente no puede filtrar por un largo que si tienes en bodega.
  1 / (case when not exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'valve_length_mm' and d.tenant_id is null
          and coalesce(v.value_option, v.value_number::text) is not null
          and not exists (
            select 1 from jsonb_array_elements(d.allowed_values) vocab
            where vocab #>> '{}' = coalesce(v.value_option, v.value_number::text)))
      then 1 else 0 end) as afirma_sin_valores_huerfanos;
