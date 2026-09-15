-- Focused dependency fixture, always inside the calling test's rollback.
-- Production read-back 2026-09-14 confirms the receipt contract from
-- 20260831290000_the_label_and_the_button_agree.sql. The historical local
-- fixture lacks its NOT NULL, composite owner FK and source constraint.
-- This does not claim schema parity or replace the live deployment gate.
alter table public.spec_fact_readings alter column definition_id set not null;
alter table public.spec_fact_readings alter column vocabulary_digest set not null;
alter table public.spec_fact_readings drop constraint if exists spec_fact_readings_belongs_to_its_fact;
alter table public.spec_facts drop constraint if exists spec_facts_id_tenant_definition_unique;
alter table public.spec_facts add constraint spec_facts_id_tenant_definition_unique
 unique (id,tenant_id,spec_definition_id);
alter table public.spec_fact_readings add constraint spec_fact_readings_belongs_to_its_fact
 foreign key (fact_id,tenant_id,definition_id) references public.spec_facts(id,tenant_id,spec_definition_id)
 on delete cascade;
create or replace function public.spec_fact_reading_requires_reading_internal_v1()
returns trigger language plpgsql as $function$
declare v_source text;
begin
 select f.source into v_source from public.spec_facts f where f.id=new.fact_id;
 if v_source is distinct from 'name_reading' then
   raise exception 'Un recibo de lectura sólo puede colgar de una lectura.' using errcode='23514';
 end if;
 return new;
end;
$function$;
drop trigger if exists spec_fact_readings_only_on_readings on public.spec_fact_readings;
create constraint trigger spec_fact_readings_only_on_readings after insert or update on public.spec_fact_readings
 deferrable initially immediate for each row execute function public.spec_fact_reading_requires_reading_internal_v1();
