-- Fase 7: el espejo se mantiene solo.
--
-- `spec_facts` quedó lleno pero congelado: cualquier ficha que un mecánico
-- guarde desde hoy entra a `product_spec_values` y no al registro. En días el
-- espejo estaría mintiendo, y mover los lectores encima de un espejo viejo es
-- peor que no moverlos.
--
-- Un trigger lo resuelve para TODO el que escriba —el formulario, una
-- migración, la edición masiva, un import— sin que ninguno tenga que
-- acordarse. Cuando los lectores terminen de moverse, la dirección se invierte
-- y `product_spec_values` pasa a ser el espejo hasta que se retire.

begin;

create or replace function public.mirror_product_spec_into_facts_internal_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $mirror$
declare
  v_tipo text;
  v_definicion uuid;
  v_fact uuid;
begin
  if tg_op = 'DELETE' then
    delete from public.spec_facts
    where tenant_id = old.tenant_id and subject_type = 'product'
      and subject_id = old.product_id
      and spec_definition_id = old.spec_definition_id
      and subject_scope is null;
    return old;
  end if;

  select d.data_type, d.id into v_tipo, v_definicion
  from public.spec_definitions d where d.id = new.spec_definition_id;
  if v_definicion is null then
    return new;
  end if;

  insert into public.spec_facts (
    tenant_id, subject_type, subject_id, spec_definition_id,
    value_number, value_boolean, value_text, source, confirmed
  ) values (
    new.tenant_id, 'product', new.product_id, new.spec_definition_id,
    new.value_number, new.value_boolean,
    case when v_tipo = 'text' then new.value_text end,
    'mechanic', false
  )
  on conflict (tenant_id, subject_type, subject_id, spec_definition_id,
               coalesce(subject_scope, ''))
  do update set
    value_number = excluded.value_number,
    value_boolean = excluded.value_boolean,
    value_text = excluded.value_text,
    updated_at = now()
  returning id into v_fact;

  -- Los valores de lista se rehacen: es la forma simple de que quitar uno de
  -- un multi-valor no deje huérfanos.
  delete from public.spec_fact_values where fact_id = v_fact;

  if v_tipo = 'single_select' and new.value_option is not null then
    insert into public.spec_fact_values (fact_id, value_id, position)
    select v_fact, sv.id, 0
    from public.spec_definition_values sv
    where sv.spec_definition_id = new.spec_definition_id
      and sv.label = new.value_option
    limit 1;
  elsif v_tipo = 'multi_select' and jsonb_typeof(new.value_json) = 'array' then
    insert into public.spec_fact_values (fact_id, value_id, position)
    select v_fact, sv.id, (elem.ordinality - 1)::integer
    from jsonb_array_elements_text(new.value_json)
      with ordinality as elem(texto, ordinality)
    join public.spec_definition_values sv
      on sv.spec_definition_id = new.spec_definition_id and sv.label = elem.texto
    on conflict do nothing;
  end if;

  return new;
end;
$mirror$;

comment on function public.mirror_product_spec_into_facts_internal_v1() is
  'Mantiene `spec_facts` al día con cada escritura de ficha de producto, sin '
  'que el que escribe tenga que saberlo. Provisional: cuando los lectores '
  'terminen de moverse, la dirección se invierte.';

drop trigger if exists mirror_product_spec_into_facts on public.product_spec_values;
create trigger mirror_product_spec_into_facts
  after insert or update or delete on public.product_spec_values
  for each row execute function public.mirror_product_spec_into_facts_internal_v1();

commit;
