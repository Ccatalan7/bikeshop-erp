-- Read-back de 20260821150000_assistant_widens_instead_of_giving_up.sql

select pedido, public.assistant_resolve_select_value_internal_v1(
  (select allowed_values from public.spec_definitions
    where key = campo and tenant_id is null), pedido) as candidatas
from (values ('cuadrado','spindle_interface'), ('bmx','spindle_interface'),
  ('caja inglesa','bb_shell_standard'), ('sellado','bb_construction'),
  ('marciano','bb_shell_standard')) as casos(pedido, campo);

select
  -- «cuadrado» devuelve JIS e ISO: las dos son cuadrado. Rendirse ahi le
  -- esconderia al operador stock que si le sirve.
  1 / (case when jsonb_array_length(
        public.assistant_resolve_select_value_internal_v1(
          (select allowed_values from public.spec_definitions
            where key = 'spindle_interface' and tenant_id is null),
          'cuadrado')) = 2
      then 1 else 0 end) as afirma_cuadrado_devuelve_las_dos,

  -- Un termino sin ambiguedad sigue devolviendo una sola.
  1 / (case when jsonb_array_length(
        public.assistant_resolve_select_value_internal_v1(
          (select allowed_values from public.spec_definitions
            where key = 'bb_shell_standard' and tenant_id is null),
          'caja inglesa')) = 1
      then 1 else 0 end) as afirma_inglesa_es_una_sola,

  -- «bmx» sobre las puntas de eje devuelve las tres medidas BMX.
  1 / (case when jsonb_array_length(
        public.assistant_resolve_select_value_internal_v1(
          (select allowed_values from public.spec_definitions
            where key = 'spindle_interface' and tenant_id is null),
          'bmx')) = 3
      then 1 else 0 end) as afirma_bmx_devuelve_las_tres,

  -- Lo que no existe sigue sin inventarse.
  1 / (case when jsonb_array_length(
        public.assistant_resolve_select_value_internal_v1(
          (select allowed_values from public.spec_definitions
            where key = 'bb_shell_standard' and tenant_id is null),
          'marciano')) = 0
      then 1 else 0 end) as afirma_no_inventa,

  -- Con varias candidatas la comparacion pasa a ser de pertenencia.
  1 / (case when (
        select count(*) from pg_proc
        where proname = 'assistant_search_inventory_v7'
          and pg_get_functiondef(oid) like '%v_operator := ''in'';%') = 1
      then 1 else 0 end) as afirma_amplia_a_pertenencia,

  -- Y sólo se descarta el predicado cuando no se tradujo NADA.
  1 / (case when (
        select count(*) from pg_proc
        where proname = 'assistant_search_inventory_v7'
          and pg_get_functiondef(oid) like '%jsonb_array_length(v_translated_values) = 0%') = 1
      then 1 else 0 end) as afirma_descarta_solo_si_nada_traduce;
