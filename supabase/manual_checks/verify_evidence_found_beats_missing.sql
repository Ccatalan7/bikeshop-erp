-- Read-back: la escalera reconoce lo establecido antes que lo desconocido.
select
  -- Nada establecido: sigue siendo «no se sabe».
  1 / (case when public.supply_need_match_state_internal_v1(
    '[{"field":"wheel_size","source":"unresolved"},
      {"field":"valve_type","source":"unresolved"}]'::jsonb, 2
  ) = 'unverified' then 1 else 0 end) as nada_establecido_es_desconocido,
  -- El nombre dice 29 y la válvula no se sabe: coincide por nombre, y ya no se
  -- confunde con una cámara de 26.
  1 / (case when public.supply_need_match_state_internal_v1(
    '[{"field":"wheel_size","source":"identity_fallback"},
      {"field":"valve_type","source":"unresolved"}]'::jsonb, 2
  ) = 'weak' then 1 else 0 end) as el_nombre_cuenta,
  -- Todo por ficha sigue siendo fuerte.
  1 / (case when public.supply_need_match_state_internal_v1(
    '[{"field":"wheel_size","source":"product_spec"},
      {"field":"valve_type","source":"product_spec"}]'::jsonb, 2
  ) = 'strong' then 1 else 0 end) as ficha_completa_es_fuerte,
  -- La contradicción sigue mandando sobre todo lo demás.
  1 / (case when public.supply_need_match_state_internal_v1(
    '[{"field":"wheel_size","source":"conflict"},
      {"field":"valve_type","source":"product_spec"}]'::jsonb, 2
  ) = 'conflict' then 1 else 0 end) as la_contradiccion_manda,
  1 / (case when public.supply_need_match_state_internal_v1(
    '[]'::jsonb, 0
  ) = 'no_criteria' then 1 else 0 end) as sin_criterios;
