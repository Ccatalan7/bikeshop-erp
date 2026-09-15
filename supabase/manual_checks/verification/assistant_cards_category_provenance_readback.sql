-- Read-back del validador de tarjetas con procedencia de categoría
-- (20260818190000). Falla a nivel SQL si no quedó instalado o quedó roto.
--
-- Ejecuta el validador de verdad sobre una tabla de casos: cada fila declara
-- qué se le agrega a una línea de borrador y si debe resultar válida. El caso
-- que estaba rojo en producción —la forma de la fase A— es la primera fila:
-- el allowlist cerrado la rechazaba y la corrida moría al persistir su
-- respuesta, con las seis herramientas en `succeeded` y sin decir por qué.
--
-- El camino guardado es de sólo lectura y no admite `create function`: los
-- casos viajan como `values`.

with cases(name, extra, must_be_valid) as (values
  -- La forma de la fase A. Ésta es la que estaba rota.
  ('phase_a_full', jsonb_build_object(
    'categoryId', 'f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4',
    'categoryPath', 'Componentes / Ruedas / Camaras',
    'technicalFamily', 'tube'), true),
  -- Identidad sin glosa: ruta y familia son opcionales.
  ('identity_without_gloss', jsonb_build_object(
    'categoryId', 'f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4',
    'categoryPath', null, 'technicalFamily', null), true),
  -- Una migración aditiva conserva todo el dominio vivo: las tarjetas
  -- anteriores a la fase A no traen las claves y siguen siendo válidas.
  ('pre_phase_a', '{}'::jsonb, true),
  -- El allowlist sigue cerrado.
  ('unknown_key', jsonb_build_object('inventedKey', 'x'), false),
  -- Las tres claves se comprueban de verdad.
  ('identity_must_be_uuid', jsonb_build_object('categoryId', 'no-es-uuid'), false),
  ('path_must_be_text', jsonb_build_object(
    'categoryId', 'f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4',
    'categoryPath', 42), false),
  ('family_must_be_text', jsonb_build_object(
    'categoryId', 'f8f5bf86-0ec9-47e7-9c8c-d05a28ba36a4',
    'technicalFamily', jsonb_build_array('tube')), false),
  -- **Sin identidad no hay ruta ni familia.** Una glosa sin nada detrás sería
  -- una afirmación que nada respalda; es la misma regla que el cliente aplica
  -- en `validateSupplyNeedDraft`.
  ('gloss_without_identity', jsonb_build_object(
    'categoryId', null, 'categoryPath', 'Componentes / Ruedas'), false),
  ('family_without_identity', jsonb_build_object(
    'technicalFamily', 'tube'), false)
), evaluated as (
  select cases.name, cases.must_be_valid,
    public.assistant_cards_valid_v1(jsonb_build_array(jsonb_build_object(
      'kind', 'supply_need_draft',
      'eyebrow', 'Peticion estructurada',
      'title', '1 necesidad para revisar',
      'description', 'Revisa antes de guardar.',
      'destination', 'purchases',
      'chips', jsonb_build_array('Equilibrio'),
      'supplyNeedDraft', jsonb_build_object(
        'profile', 'balanced',
        'lines', jsonb_build_array(
          jsonb_build_object(
            'lineRef', 'line-1',
            'description', 'camara 29 con valvula Schrader',
            'productId', null,
            'productName', null,
            'productSku', null,
            'identityState', 'unresolved',
            'quantity', 4,
            'unit', 'unidad',
            'technicalPredicates', '[]'::jsonb,
            'preference', null,
            'clarification', null,
            'clarificationRequired', false
          ) || cases.extra)
      )
    ))) as actually_valid
  from cases
)
select
  1 / (case when not exists (
    select 1 from evaluated where actually_valid is distinct from must_be_valid
  ) then 1 else 0 end) as every_case_matches,
  -- Nombrado aparte porque es el defecto que esta migración cierra.
  1 / (case when (select actually_valid from evaluated
        where name = 'phase_a_full') then 1 else 0 end) as phase_a_draft_is_valid,
  1 / (case when (select actually_valid from evaluated
        where name = 'pre_phase_a') then 1 else 0 end) as pre_phase_a_stays_valid,
  1 / (case when not (select actually_valid from evaluated
        where name = 'gloss_without_identity')
        then 1 else 0 end) as gloss_without_identity_is_rejected
from evaluated limit 1;

-- Ninguna tarjeta ya persistida queda fuera de la definición nueva.
select 1 / (case when not exists (
  select 1 from public.assistant_messages message
  where not public.assistant_cards_valid_v1(message.cards)
) then 1 else 0 end) as every_persisted_card_stays_valid;

-- Y el CHECK de la tabla sigue apoyado en este validador.
select 1 / (case when exists (
  select 1 from pg_constraint
  where conrelid = 'public.assistant_messages'::regclass
    and conname = 'assistant_messages_cards_check'
    and pg_get_constraintdef(oid) like '%assistant_cards_valid_v1%'
) then 1 else 0 end) as table_check_uses_the_validator;
