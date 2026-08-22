-- Read-back de 20260821130000_assistant_search_contains_on_selects.sql

select proname,
  (pg_get_functiondef(oid) like '%''eq'',''neq'',''in'',''contains''%') as admite_contains,
  (pg_get_functiondef(oid) like '%v_operator <> ''contains''%') as salta_pertenencia
from pg_proc where proname = 'assistant_search_inventory_v7';

select
  -- `contains` entra como operador valido para campos de lista.
  1 / (case when (
        select count(*) from pg_proc
        where proname = 'assistant_search_inventory_v7'
          and pg_get_functiondef(oid) like '%''eq'',''neq'',''in'',''contains''%') = 1
      then 1 else 0 end) as afirma_contains_permitido,

  -- Y con `contains` no se exige pertenencia a allowed_values: un fragmento
  -- nunca va a ser una entrada completa del vocabulario.
  1 / (case when (
        select count(*) from pg_proc
        where proname = 'assistant_search_inventory_v7'
          and pg_get_functiondef(oid) like '%v_operator <> ''contains''%') = 1
      then 1 else 0 end) as afirma_pertenencia_saltada_en_contains,

  -- `eq` conserva la comprobación exacta: un filtro que afirma un valor
  -- concreto sigue teniendo que nombrar uno que existe.
  1 / (case when (
        select count(*) from pg_proc
        where proname = 'assistant_search_inventory_v7'
          and pg_get_functiondef(oid) like '%jsonb_array_length(v_definition.allowed_values) > 0%') = 1
      then 1 else 0 end) as afirma_exactitud_conservada,

  -- La firma no cambió, así que el gateway desplegado la sigue llamando igual.
  1 / (case when (
        select count(*) from pg_proc
        where proname = 'assistant_search_inventory_v7'
          and pg_get_function_identity_arguments(oid) =
            'p_query text, p_category text, p_availability text, '
            'p_technical_predicates jsonb, p_operational_predicates jsonb, '
            'p_sort_field text, p_sort_direction text, p_limit integer, '
            'p_selection_mode text') = 1
      then 1 else 0 end) as afirma_firma_intacta;
