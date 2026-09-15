-- Read-back de 20260820310000_backfill_bottom_bracket_siblings.sql

select c.name as categoria, count(distinct p.id) as productos,
       count(v.id) as valores_de_ficha
from public.products p
join public.product_categories c on c.id = p.category_id
left join public.product_spec_values v on v.product_id = p.id
where c.name in ('Cubetas', 'Ejes de motor', 'Rodamientos Motor')
  and p.is_active is true
group by 1 order by 1;

select
  -- Los 14 quedan con construccion: es la raiz de sus tres plantillas.
  1 / (case when (
        select count(distinct v.product_id)
        from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        join public.products p on p.id = v.product_id
        join public.product_categories c on c.id = p.category_id
        where d.key = 'bb_construction' and p.is_active is true
          and c.name in ('Cubetas', 'Ejes de motor', 'Rodamientos Motor')) = 14
      then 1 else 0 end) as afirma_catorce_con_construccion,

  -- Las cinco cubetas de 34,8 mm quedan con su diametro.
  1 / (case when (
        select count(*) from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'bb_cup_outer_diameter_mm' and v.value_number = 34.8) = 5
      then 1 else 0 end) as afirma_cinco_cubetas_de_34_8,

  -- La mano de la rosca solo donde el nombre la declara: cinco de ocho.
  -- `DER/IZQ` x3, `DER/DER` de Nakasawa y el `R/R` de Bettabikes. Las tres que
  -- quedan fuera son `H-DE TOPE`, la americana de 9 piezas y la BMX sellada,
  -- que no dicen la mano por ninguna parte.
  1 / (case when (
        select count(*) from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'bb_cup_thread_pair') = 5
      then 1 else 0 end) as afirma_cuatro_manos_declaradas,

  -- El canastillo 1/4 x 9 queda con su bolita y su cantidad; el que solo dice
  -- «20unid» no, porque eso es cuantos vienen en la bolsa.
  1 / (case when (
        select count(*) from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'bb_ball_count_per_side' and v.value_number = 9) = 1
      then 1 else 0 end) as afirma_un_canastillo_de_nueve,

  -- Y el rodamiento sellado con su codigo.
  1 / (case when exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.key = 'bearing_size_code' and v.value_text = '163110')
      then 1 else 0 end) as afirma_codigo_163110,

  -- Ningun valor guardado queda fuera del vocabulario de su campo.
  1 / (case when not exists (
        select 1 from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.tenant_id is null
          and jsonb_array_length(d.allowed_values) > 0
          and coalesce(v.value_option, v.value_number::text, v.value_text) is not null
          and not exists (
            select 1 from jsonb_array_elements(d.allowed_values) vocab
            where vocab #>> '{}' = coalesce(
              v.value_option, v.value_number::text, v.value_text)))
      then 1 else 0 end) as afirma_valores_en_vocabulario;
