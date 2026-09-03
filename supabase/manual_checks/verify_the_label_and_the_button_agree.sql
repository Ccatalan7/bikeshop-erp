-- Read-back de `20260831290000_the_label_and_the_button_agree`.

-- (a) El rótulo y el botón usan la misma lista. Si esto falla, una fila sale
--     comprobada para el botón y parcial para el texto, que es lo que pasaba.
select 1 / (
  case when public.supply_need_match_state_internal_v1(
         '[{"field":"a","source":"name_reading"},
           {"field":"b","source":"identity_fallback"}]'::jsonb, 2) = 'strong'
        and public.supply_need_evidence_is_complete_internal_v1(
         '[{"field":"a","source":"name_reading"},
           {"field":"b","source":"identity_fallback"}]'::jsonb)
  then 1 else 0 end
) as el_rotulo_y_el_boton_coinciden;

select 1 / (
  case when public.supply_need_match_state_internal_v1(
         '[{"field":"a","source":"name_reading"},
           {"field":"b","source":"unresolved"}]'::jsonb, 2) = 'weak'
  then 1 else 0 end
) as un_campo_en_silencio_sigue_siendo_parcial;

-- (b) Una sigla de dos letras es una palabra, y sigue exigiendo exactitud.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'derailleur_cage_length'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"SS / corta"'::jsonb, 'SS') is null
   and public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'derailleur_cage_length'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"SS / corta"'::jsonb, 'SGS') is not null
  then 1 else 0 end
) as la_sigla_corta_cuenta_y_no_contagia;

-- (c) La huella del vocabulario incluye la descripción del campo.
select 1 / (
  case when prosrc like '%d.description%' then 1 else 0 end
) as la_huella_incluye_la_descripcion
from pg_proc
where proname = 'spec_definition_vocabulary_digest_internal_v1';

-- (d) Los dos que escriben la ficha de un producto toman la MISMA llave, y el
--     guardado manual la toma antes de vaciar nada.
select 1 / (
  case when prosrc like '%:spec_fact:'' || p_product_id::text, 0%'
       then 1 else 0 end
) as la_lectura_se_serializa_por_producto
from pg_proc where proname = 'record_product_spec_reading_v1';

select 1 / (
  case when prosrc like '%:spec_fact:'' || p_product_id::text, 0%'
        and position('pg_advisory_xact_lock' in prosrc)
            < position('delete from public.spec_facts' in prosrc)
       then 1 else 0 end
) as el_guardado_manual_traba_antes_de_vaciar
from pg_proc where proname = 'save_product_spec_facts_v1';

-- (d) Y el invariante que hace inofensiva la carrera, gane quien gane.
select 1 / (case when count(*) = 1 then 1 else 0 end)
  as un_recibo_solo_cuelga_de_una_lectura
from pg_trigger where tgname = 'spec_fact_readings_only_on_readings';

select 1 / (case when count(*) = 1 then 1 else 0 end)
  as cambiar_la_procedencia_retira_el_recibo
from pg_trigger where tgname = 'spec_facts_drop_reading_on_source_change';

-- (e) El recibo, amarrado y sin huecos.
select 1 / (case when count(*) = 2 then 1 else 0 end) as las_huellas_no_faltan
from information_schema.columns
where table_schema = 'public' and table_name = 'spec_fact_readings'
  and column_name in ('definition_id', 'vocabulary_digest')
  and is_nullable = 'NO';

select 1 / (case when count(*) = 1 then 1 else 0 end)
  as el_recibo_va_al_mismo_hecho_taller_y_campo
from pg_constraint
where conrelid = 'public.spec_fact_readings'::regclass and contype = 'f'
  and pg_get_constraintdef(oid) like '%(fact_id, tenant_id, definition_id)%';

-- Y producción sigue sin una sola lectura guardada: este bloque instala la
-- puerta, no la evidencia.
select 1 / (case when count(*) = 0 then 1 else 0 end) as ninguna_lectura_aun
from public.spec_facts where source = 'name_reading';
