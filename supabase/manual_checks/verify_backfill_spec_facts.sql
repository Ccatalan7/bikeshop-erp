-- Read-back de 20260821190000_backfill_spec_facts.sql

select subject_type, count(*) as hechos,
  count(*) filter (where confirmed) as confirmados
from public.spec_facts group by 1 order by 1;

select
  -- Los 282 valores de producto tienen su espejo.
  1 / (case when (select count(*) from public.spec_facts where subject_type = 'product')
        = (select count(*) from public.product_spec_values)
      then 1 else 0 end) as afirma_productos_completos,

  -- Ningun valor de lista quedo sin resolver contra el vocabulario: si uno
  -- fallara, ese producto perderia su dato al mover los lectores.
  1 / (case when (
        select count(*) from public.product_spec_values v
        join public.spec_definitions d on d.id = v.spec_definition_id
        where d.data_type = 'single_select' and v.value_option is not null
          and not exists (
            select 1 from public.spec_definition_values sv
            where sv.spec_definition_id = d.id and sv.label = v.value_option)) = 0
      then 1 else 0 end) as afirma_todas_las_listas_resueltas,

  -- Las bicis entraron con su procedencia y su confirmacion, no en blanco.
  1 / (case when (select count(*) from public.spec_facts
        where subject_type = 'bike' and confirmed) > 0
      then 1 else 0 end) as afirma_bicis_con_confirmacion,

  -- Un «other» o «unknown» NO entra como valor: en la tabla nueva la ausencia
  -- es como se dice «no se», y asi `confirmed` recupera su significado.
  1 / (case when not exists (
        select 1 from public.spec_facts f
        join public.spec_fact_values fv on fv.fact_id = f.id
        join public.spec_definition_values sv on sv.id = fv.value_id
        where f.subject_type = 'bike'
          and sv.code in ('other', 'unknown')) = true
      then 1 else 0 end) as afirma_sin_no_se_como_valor,

  -- Un motor y una bici comparten ahora el mismo campo: eso es lo que hace
  -- que cruzarlos sea un join y no un traductor en Dart.
  1 / (case when exists (
        select 1 from public.spec_facts producto
        join public.spec_facts bici
          on bici.spec_definition_id = producto.spec_definition_id
         and bici.subject_type = 'bike'
        where producto.subject_type = 'product')
      then 1 else 0 end) as afirma_producto_y_bici_comparten_campo,

  -- Y ningun hecho de lista quedo con un escalar encima.
  1 / (case when not exists (
        select 1 from public.spec_facts f
        join public.spec_fact_values fv on fv.fact_id = f.id
        where num_nonnulls(f.value_number, f.value_boolean, f.value_text) > 0)
      then 1 else 0 end) as afirma_formas_limpias;
