-- Read-back del objetivo comercial en la tarjeta de borrador (20260818200000).
-- Falla a nivel SQL si no quedó instalado o quedó roto.
--
-- Ejecuta el validador sobre una tabla de casos. Lo que se exige: que un
-- objetivo bien formado sea válido —eso es lo que habilita el corte—, que el
-- dominio sea **el mismo** de `supply_need_commercial_revisions` y no uno más
-- permisivo, que la moneda no sea representable, y que las tarjetas anteriores
-- sigan siendo válidas.

with cases(name, target, must_be_valid) as (values
  ('full', jsonb_build_object(
    'gama','alta',
    'preferredBrandId','f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4',
    'maxLandedUnitCostNet', 12000,
    'minGrossMarginRatio', 0.35), true),
  ('only_gama', jsonb_build_object('gama','economica'), true),
  ('only_margin_floor_zero', jsonb_build_object('minGrossMarginRatio', 0), true),
  ('margin_ceiling_one', jsonb_build_object('minGrossMarginRatio', 1), true),
  -- Ausente y explícitamente nulo son ambos aceptables; decir «no hay
  -- objetivo» no es lo mismo que no traer la clave, y el comando distingue.
  ('explicit_null', 'null'::jsonb, true),
  -- Dominio: exactamente el de la tabla.
  ('gama_outside_enum', jsonb_build_object('gama','premium'), false),
  ('brand_not_a_uuid', jsonb_build_object('preferredBrandId','shimano'), false),
  ('cost_zero', jsonb_build_object('maxLandedUnitCostNet', 0), false),
  ('cost_above_ceiling', jsonb_build_object('maxLandedUnitCostNet', 1000000000), false),
  ('cost_not_a_number', jsonb_build_object('maxLandedUnitCostNet', '12000'), false),
  ('margin_above_one', jsonb_build_object('minGrossMarginRatio', 1.5), false),
  ('margin_negative', jsonb_build_object('minGrossMarginRatio', -0.1), false),
  -- La moneda la fija el servidor: una tarjeta que la traiga se rechaza.
  ('currency_is_unrepresentable', jsonb_build_object(
    'gama','alta','currencyCode','USD'), false),
  ('unknown_key', jsonb_build_object('gama','alta','discount', 10), false),
  -- Un objetivo vacío es ruido, no un objetivo.
  ('empty_object', '{}'::jsonb, false)
), evaluated as (
  select cases.name, cases.must_be_valid,
    public.assistant_cards_valid_v1(jsonb_build_array(jsonb_build_object(
      'kind','supply_need_draft','eyebrow','Peticion estructurada',
      'title','1 necesidad para revisar','description','Revisa antes de guardar.',
      'destination','purchases','chips', jsonb_build_array('Equilibrio'),
      'supplyNeedDraft', jsonb_build_object(
        'profile','balanced',
        'lines', jsonb_build_array(jsonb_build_object(
          'lineRef','line-1','description','cadena 9 velocidades',
          'productId', null,'productName', null,'productSku', null,
          'identityState','unresolved','quantity', 2,'unit','unidad',
          'technicalPredicates','[]'::jsonb,'preference', null,
          'clarification', null,'clarificationRequired', false,
          'commercialTarget', cases.target
        ))
      )
    ))) as actually_valid
  from cases
)
select
  1 / (case when not exists (
    select 1 from evaluated where actually_valid is distinct from must_be_valid
  ) then 1 else 0 end) as every_case_matches,
  1 / (case when (select actually_valid from evaluated where name='full')
        then 1 else 0 end) as a_well_formed_target_is_valid,
  1 / (case when not (select actually_valid from evaluated
        where name='currency_is_unrepresentable')
        then 1 else 0 end) as currency_is_rejected_not_ignored,
  1 / (case when not (select actually_valid from evaluated where name='empty_object')
        then 1 else 0 end) as an_empty_target_is_not_a_target
from evaluated limit 1;

-- Sin la clave, la tarjeta anterior al corte sigue siendo válida.
select 1 / (case when public.assistant_cards_valid_v1(
  jsonb_build_array(jsonb_build_object(
    'kind','supply_need_draft','eyebrow','Peticion estructurada',
    'title','1 necesidad para revisar','description','Revisa antes de guardar.',
    'destination','purchases','chips', jsonb_build_array('Equilibrio'),
    'supplyNeedDraft', jsonb_build_object('profile','balanced',
      'lines', jsonb_build_array(jsonb_build_object(
        'lineRef','line-1','description','cadena 9 velocidades',
        'productId', null,'productName', null,'productSku', null,
        'identityState','unresolved','quantity', 2,'unit','unidad',
        'technicalPredicates','[]'::jsonb,'preference', null,
        'clarification', null,'clarificationRequired', false)))
  ))) then 1 else 0 end) as a_card_without_the_key_stays_valid;

-- Y ninguna tarjeta ya persistida queda fuera.
select 1 / (case when not exists (
  select 1 from public.assistant_messages message
  where not public.assistant_cards_valid_v1(message.cards)
) then 1 else 0 end) as every_persisted_card_stays_valid;
