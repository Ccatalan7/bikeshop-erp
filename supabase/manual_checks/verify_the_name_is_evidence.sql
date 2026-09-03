-- Read-back de `20260831260000_the_name_is_evidence_the_server_checks`.

-- 1. La procedencia nueva existe y el hecho puede llevarla.
select 1 / (
  case when pg_get_constraintdef(oid) like '%name_reading%' then 1 else 0 end
) as la_procedencia_existe
from pg_constraint where conname = 'spec_facts_source_known';

-- 2. El recibo de la lectura vive, con RLS y sin política de escritura: sólo
--    la RPC comprobadora puede crearlo.
select 1 / (case when count(*) = 1 then 1 else 0 end) as el_recibo_vive
from pg_class where relname = 'spec_fact_readings' and relrowsecurity;
select 1 / (case when count(*) = 0 then 1 else 0 end) as nadie_lo_escribe_a_mano
from pg_policy where polrelid = 'public.spec_fact_readings'::regclass
  and polcmd <> 'r';

-- 2.b La compuerta se prueba contra vocabulario que EXISTE: si el campo no
--     estuviera, las afirmaciones de abajo pasarían en vacío.
select 1 / (case when count(*) >= 2 then 1 else 0 end) as el_vocabulario_existe
from public.spec_definitions d
where d.key in ('compound_type', 'pad_finned')
  and (d.tenant_id is null
    or d.tenant_id = '5443b130-cc28-45af-a420-cd500b288890');

-- 3. **El caso adversarial, comprobado contra el vocabulario real del taller.**
--    Citar «METALICA» y normalizarlo como «Orgánico» tiene que morir acá.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'compound_type'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"Orgánico"'::jsonb, 'METALICA') is not null
  then 1 else 0 end
) as la_cita_no_autoriza_el_valor_contrario;

--    Y la lectura correcta de la misma cita sí pasa: no es que rechace todo.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'compound_type'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    '"Metálico"'::jsonb, 'METALICA') is null
  then 1 else 0 end
) as la_lectura_correcta_pasa;

--    Un booleano no se afirma con una palabra que el campo no nombra.
select 1 / (
  case when public.spec_reading_rejection_internal_v1(
    (select id from public.spec_definitions where key = 'pad_finned'
      and (tenant_id is null
        or tenant_id = '5443b130-cc28-45af-a420-cd500b288890') limit 1),
    'true'::jsonb, 'CON DISIPADOR') is not null
  then 1 else 0 end
) as el_servidor_no_inventa_que_un_disipador_es_una_aleta;

-- 4. La lectura caduca con el texto: el juez de procedencia compara el digest.
select 1 / (
  case when prosrc like '%source_digest%'
        and prosrc like '%sha256(convert_to(v_texto%'
       then 1 else 0 end
) as la_evidencia_caduca_si_cambia_el_texto
from pg_proc where proname
  = 'assistant_inventory_technical_predicate_source_internal_v1';

-- 5. La procedencia cuenta SÓLO donde se habilitó. En el carril de compras sí.
select 1 / (
  case when public.supply_need_evidence_is_complete_internal_v1(
    '[{"field":"x","source":"name_reading"}]'::jsonb) then 1 else 0 end
) as compras_acepta_la_lectura_verificada;

--    En la búsqueda del asistente NO: un token nuevo no entra por descuido.
select 1 / (
  case when pg_get_functiondef(oid) not like '%name_reading%'
       then 1 else 0 end
) as el_asistente_sigue_ignorandola
from pg_proc where proname = 'assistant_search_inventory_v7';

-- 6. Nada de esto escribió un solo hecho todavía: el despliegue instala la
--    puerta, no la evidencia. Si esto falla, algo escribió sin pasar por la app.
select 1 / (case when count(*) = 0 then 1 else 0 end) as ninguna_lectura_aun
from public.spec_facts where source = 'name_reading';
