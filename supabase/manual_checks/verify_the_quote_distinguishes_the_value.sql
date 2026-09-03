-- Read-back de `20260831280000_the_quote_distinguishes_the_value`.
-- Contra el vocabulario REAL del taller, con las citas reales de sus nombres.

-- Las dos lecturas honestas que la regla anterior rechazaba.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions
      where key = 'drivetrain_primary_ecosystem'
        and (tenant_id is null
          or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"Ecosistema Shimano"'::jsonb, 'SHIMANO') is null
  then 1 else 0 end
) as la_marca_sola_distingue_el_ecosistema;

select 1 / (
  case when public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'derailleur_cage_length'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"SGS / larga"'::jsonb, 'SGS') is null
   and public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'derailleur_cage_length'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"SGS / larga"'::jsonb, 'PATA LARGA') is null
  then 1 else 0 end
) as la_sigla_y_el_castellano_dicen_lo_mismo;

-- Y las tres adversariales que tienen que seguir muertas.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions
      where key = 'drivetrain_primary_ecosystem'
        and (tenant_id is null
          or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"Ecosistema SRAM"'::jsonb, 'SHIMANO') is not null
   and public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions
      where key = 'drivetrain_primary_ecosystem'
        and (tenant_id is null
          or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"Ecosistema Shimano"'::jsonb, 'Sun Race') is not null
   and public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'derailleur_cage_length'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"SS / corta"'::jsonb, 'SGS') is not null
  then 1 else 0 end
) as las_adversariales_siguen_muertas;

-- El caso original de las pastillas no se movió.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'compound_type'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"Orgánico"'::jsonb, 'METALICA') is not null
   and public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'compound_type'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"Metálico"'::jsonb, 'METALICA') is null
  then 1 else 0 end
) as el_caso_de_las_pastillas_no_se_movio;

-- Una lista sigue rechazándose entera: leída de un nombre es parcial, y una
-- ficha parcial fabrica contradicciones donde sólo hay silencio.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'drivetrain_speeds'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"9"'::jsonb, '9-SPEED') is not null
  then 1 else 0 end
) as una_lista_sigue_sin_leerse;
