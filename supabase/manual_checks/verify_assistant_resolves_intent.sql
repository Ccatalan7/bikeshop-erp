-- Read-back de 20260821140000_assistant_resolves_intent_before_filtering.sql

select pedido, public.assistant_resolve_select_value_internal_v1(
  (select allowed_values from public.spec_definitions
    where key = campo and tenant_id is null), pedido) as traducido
from (values
  ('caja inglesa', 'bb_shell_standard'), ('BSA', 'bb_shell_standard'),
  ('mid bmx', 'bb_shell_standard'), ('sellado', 'bb_construction'),
  ('integrado', 'bb_construction'), ('hollowtech', 'spindle_interface'),
  ('cuadrado', 'spindle_interface'), ('caja marciana', 'bb_shell_standard')
) as casos(pedido, campo);

select
  -- Como habla el mecánico llega al término real del vocabulario.
  1 / (case when public.assistant_resolve_select_value_internal_v1(
        (select allowed_values from public.spec_definitions
          where key = 'bb_shell_standard' and tenant_id is null),
        'caja inglesa') #>> '{}' = 'BSA / Caja inglesa 34,8 mm (1.37") x 24'
      then 1 else 0 end) as afirma_traduce_caja_inglesa,

  1 / (case when public.assistant_resolve_select_value_internal_v1(
        (select allowed_values from public.spec_definitions
          where key = 'bb_construction' and tenant_id is null),
        'sellado') #>> '{}' = 'Rodamiento sellado'
      then 1 else 0 end) as afirma_traduce_sellado,

  1 / (case when public.assistant_resolve_select_value_internal_v1(
        (select allowed_values from public.spec_definitions
          where key = 'spindle_interface' and tenant_id is null),
        'hollowtech') #>> '{}' = 'Hollowtech / 24mm'
      then 1 else 0 end) as afirma_traduce_hollowtech,

  -- Lo ambiguo no se adivina: «cuadrado» calza con JIS y con ISO, y elegir uno
  -- seria inventar un estandar que el operador no dijo.
  1 / (case when public.assistant_resolve_select_value_internal_v1(
        (select allowed_values from public.spec_definitions
          where key = 'spindle_interface' and tenant_id is null),
        'cuadrado') is null
      then 1 else 0 end) as afirma_no_adivina_lo_ambiguo,

  -- Lo que no existe tampoco se inventa.
  1 / (case when public.assistant_resolve_select_value_internal_v1(
        (select allowed_values from public.spec_definitions
          where key = 'bb_shell_standard' and tenant_id is null),
        'caja marciana') is null
      then 1 else 0 end) as afirma_no_inventa,

  -- El buscador descarta el predicado que no traduce en vez de abortar.
  1 / (case when (
        select count(*) from pg_proc
        where proname = 'assistant_search_inventory_v7'
          and pg_get_functiondef(oid) like '%v_dropped_predicates := v_dropped_predicates + 1%'
          and pg_get_functiondef(oid) like '%p_technical_predicates := v_applied_predicates%') = 1
      then 1 else 0 end) as afirma_descarta_sin_abortar,

  -- La firma no cambió: el gateway desplegado la sigue llamando igual.
  1 / (case when (
        select count(*) from pg_proc
        where proname = 'assistant_search_inventory_v7'
          and pg_get_function_identity_arguments(oid) =
            'p_query text, p_category text, p_availability text, '
            'p_technical_predicates jsonb, p_operational_predicates jsonb, '
            'p_sort_field text, p_sort_direction text, p_limit integer, '
            'p_selection_mode text') = 1
      then 1 else 0 end) as afirma_firma_intacta;
