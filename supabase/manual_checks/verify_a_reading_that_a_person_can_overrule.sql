-- Read-back de `20260831270000_a_reading_that_a_person_can_overrule`.
-- Los seis bordes, cada uno afirmado contra el comportamiento y no contra el
-- texto de la función, salvo donde lo único observable es la definición.

-- (1) Una negación explícita prueba la ausencia; el silencio sigue sin probar
--     nada; y la misma cita no puede sostener lo contrario de lo que dice.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
         (select id from public.spec_definitions where key = 'pad_finned'
           and (tenant_id is null
             or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
         'false'::jsonb, 'SIN ALETAS DE CALOR') is null
  then 1 else 0 end
) as la_negacion_explicita_prueba;

select 1 / (
  case when public.spec_reading_rejection_internal_v1(
         (select id from public.spec_definitions where key = 'pad_finned'
           and (tenant_id is null
             or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
         'true'::jsonb, 'SIN ALETAS DE CALOR') is not null
  then 1 else 0 end
) as la_misma_cita_no_sostiene_lo_contrario;

select 1 / (
  case when public.spec_reading_rejection_internal_v1(
         (select id from public.spec_definitions where key = 'pad_finned'
           and (tenant_id is null
             or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
         'false'::jsonb, 'Pastilla Freno Organica') is not null
  then 1 else 0 end
) as el_silencio_sigue_sin_negar;

-- (2) Estado y evidencia dicen lo mismo. Si esto falla, el rótulo de la fila
--     contradice a su propio botón.
select 1 / (
  case when public.supply_need_match_state_internal_v1(
         '[{"field":"a","source":"name_reading"}]'::jsonb, 1) = 'strong'
        and public.supply_need_evidence_is_complete_internal_v1(
         '[{"field":"a","source":"name_reading"}]'::jsonb)
  then 1 else 0 end
) as el_rotulo_y_el_boton_coinciden;

select 1 / (
  case when public.supply_need_match_state_internal_v1(
         '[{"field":"a","source":"name_reading"},
           {"field":"b","source":"unresolved"}]'::jsonb, 2) = 'weak'
  then 1 else 0 end
) as un_campo_en_silencio_sigue_siendo_parcial;

-- (3) La vigencia mira el vocabulario además del texto.
select 1 / (
  case when prosrc like '%spec_definition_vocabulary_digest_internal_v1%'
       then 1 else 0 end
) as la_vigencia_mira_el_vocabulario
from pg_proc where proname
  = 'assistant_inventory_technical_predicate_source_internal_v1';

select 1 / (case when count(*) = 2 then 1 else 0 end) as el_recibo_guarda_ambas
from information_schema.columns
where table_schema = 'public' and table_name = 'spec_fact_readings'
  and column_name in ('vocabulary_digest', 'definition_id');

-- (4) La persona recupera la procedencia y retira el recibo.
select 1 / (
  case when prosrc like '%source = excluded.source%'
        and prosrc like '%delete from public.spec_fact_readings%'
       then 1 else 0 end
) as la_persona_gana_de_verdad
from pg_proc where proname = 'save_product_spec_facts_v1';

-- (5) Lo que no se sabe resolver se rechaza; una cita tiene tope.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
         (select d.id from public.spec_definitions d
          where d.data_type = 'multi_select' and d.is_filterable
            and (d.tenant_id is null
              or d.tenant_id = '5443b130-cc28-45af-a420-cd500b288890')
          limit 1),
         '"cualquiera"'::jsonb, 'cualquiera') is not null
  then 1 else 0 end
) as una_lista_no_se_resuelve_a_medias;

select 1 / (
  case when public.spec_reading_rejection_internal_v1(
         (select id from public.spec_definitions where key = 'compound_type'
           and (tenant_id is null
             or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
         '"Metálico"'::jsonb, 'METALICA ' || repeat('x ', 120)) is not null
  then 1 else 0 end
) as la_cita_tiene_tope;

-- (6) El recibo pertenece al mismo taller que su hecho, y lo impone la base.
select 1 / (case when count(*) = 1 then 1 else 0 end) as la_base_impone_el_taller
from pg_constraint
where conrelid = 'public.spec_fact_readings'::regclass
  and contype = 'f'
  and pg_get_constraintdef(oid) like '%(fact_id, tenant_id)%';

-- Y el caso adversarial de siempre sigue muerto.
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
) as la_cita_no_autoriza_el_valor_contrario;
