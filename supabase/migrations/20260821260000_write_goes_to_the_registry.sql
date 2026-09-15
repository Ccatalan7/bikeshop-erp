-- Fase 9: la escritura entra al registro y el espejo se da vuelta.
--
-- Hasta acá la app escribía `product_spec_values` y un trigger copiaba hacia
-- `spec_facts`. Eso servía para migrar sin romper, pero deja la tabla vieja
-- como dueña: mientras sea ella la que recibe, no se puede retirar.
--
-- Ahora la app escribe el registro con un solo RPC atómico, y el trigger va al
-- revés: `product_spec_values` se mantiene al día como COPIA, para el wizard y
-- la edición masiva que todavía la leen. Cuando ésos se muevan, se borra la
-- tabla y su trigger y no queda nada que limpiar.
--
-- El RPC recibe el conjunto completo de la plantilla, no un campo suelto: así
-- vaciar un campo es parte de la misma transacción que llenar otro, y no
-- existe el estado intermedio en que la ficha quedó a medias.
--
-- `display_value` desaparece del camino de escritura. Era una copia congelada
-- de la etiqueta y es justo lo que hacía que renombrar costara reescribir
-- productos; ahora la etiqueta se resuelve al leer.

begin;

drop trigger if exists mirror_product_spec_into_facts on public.product_spec_values;

create or replace function public.save_product_spec_facts_v1(
  p_product_id uuid,
  p_definition_ids uuid[],
  p_values jsonb
) returns integer
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $save$
declare
  v_tenant uuid := public.user_tenant_id();
  v_definicion uuid;
  v_tipo text;
  v_entrada jsonb;
  v_fact uuid;
  v_escritos integer := 0;
begin
  if v_tenant is null then
    raise exception 'sin tenant' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.products
    where id = p_product_id and tenant_id = v_tenant
  ) then
    raise exception 'el producto no pertenece a este tenant' using errcode = '42501';
  end if;

  -- Lo que la plantilla incluye y el payload no trae, se borra: vaciar un
  -- campo es parte de guardar, no una operación aparte.
  delete from public.spec_facts f
  where f.tenant_id = v_tenant and f.subject_type = 'product'
    and f.subject_id = p_product_id and f.subject_scope is null
    and f.spec_definition_id = any(p_definition_ids)
    and not (p_values ? f.spec_definition_id::text);

  for v_definicion in
    select unnest(p_definition_ids)
  loop
    v_entrada := p_values -> v_definicion::text;
    continue when v_entrada is null;

    select data_type into v_tipo from public.spec_definitions where id = v_definicion;
    continue when v_tipo is null;

    insert into public.spec_facts (
      tenant_id, subject_type, subject_id, spec_definition_id,
      value_number, value_boolean, value_text, source, confirmed
    ) values (
      v_tenant, 'product', p_product_id, v_definicion,
      case when v_tipo = 'number'
           then nullif(v_entrada ->> 'number', '')::numeric end,
      case when v_tipo = 'boolean'
           then (v_entrada ->> 'boolean')::boolean end,
      case when v_tipo not in ('number','boolean','single_select','multi_select')
           then nullif(v_entrada ->> 'text', '') end,
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

    delete from public.spec_fact_values where fact_id = v_fact;

    if v_tipo in ('single_select','multi_select')
       and jsonb_typeof(v_entrada -> 'labels') = 'array' then
      insert into public.spec_fact_values (fact_id, value_id, position)
      select v_fact, sv.id, (elem.ordinality - 1)::integer
      from jsonb_array_elements_text(v_entrada -> 'labels')
        with ordinality as elem(etiqueta, ordinality)
      join public.spec_definition_values sv
        on sv.spec_definition_id = v_definicion and sv.label = elem.etiqueta
      on conflict do nothing;
    end if;

    v_escritos := v_escritos + 1;
  end loop;

  return v_escritos;
end;
$save$;

comment on function public.save_product_spec_facts_v1(uuid, uuid[], jsonb) is
  'Guarda la ficha completa de un producto en el registro, en una sola '
  'transacción. Recibe el conjunto de la plantilla: lo que no venga en el '
  'payload se borra, así vaciar un campo y llenar otro son el mismo guardado.';

grant execute on function public.save_product_spec_facts_v1(uuid, uuid[], jsonb)
  to authenticated;

-- El espejo al revés: `product_spec_values` se mantiene como COPIA mientras el
-- wizard y la edición masiva la sigan leyendo.
create or replace function public.mirror_facts_into_product_specs_internal_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $mirror$
declare
  v_fact public.spec_facts%rowtype;
  v_tipo text;
  v_etiquetas text[];
begin
  if tg_op = 'DELETE' then
    if tg_table_name = 'spec_facts' then
      delete from public.product_spec_values
      where tenant_id = old.tenant_id and product_id = old.subject_id
        and spec_definition_id = old.spec_definition_id;
      return old;
    end if;
    select * into v_fact from public.spec_facts where id = old.fact_id;
  elsif tg_table_name = 'spec_fact_values' then
    select * into v_fact from public.spec_facts where id = new.fact_id;
  else
    v_fact := new;
  end if;

  if v_fact.id is null or v_fact.subject_type <> 'product'
     or v_fact.subject_scope is not null then
    return coalesce(new, old);
  end if;

  select data_type into v_tipo from public.spec_definitions
  where id = v_fact.spec_definition_id;

  select array_agg(sv.label order by fv.position) into v_etiquetas
  from public.spec_fact_values fv
  join public.spec_definition_values sv on sv.id = fv.value_id
  where fv.fact_id = v_fact.id;

  insert into public.product_spec_values (
    tenant_id, product_id, spec_definition_id,
    value_number, value_boolean, value_text, value_option, value_json,
    display_value
  ) values (
    v_fact.tenant_id, v_fact.subject_id, v_fact.spec_definition_id,
    v_fact.value_number, v_fact.value_boolean, v_fact.value_text,
    case when v_tipo = 'single_select' then v_etiquetas[1] end,
    case when v_tipo = 'multi_select' then to_jsonb(v_etiquetas) end,
    coalesce(
      array_to_string(v_etiquetas, ', '),
      v_fact.value_text,
      v_fact.value_number::text,
      case when v_fact.value_boolean then 'Sí'
           when v_fact.value_boolean is not null then 'No' end
    )
  )
  on conflict (tenant_id, product_id, spec_definition_id) do update set
    value_number = excluded.value_number,
    value_boolean = excluded.value_boolean,
    value_text = excluded.value_text,
    value_option = excluded.value_option,
    value_json = excluded.value_json,
    display_value = excluded.display_value,
    updated_at = now();

  return coalesce(new, old);
end;
$mirror$;

drop trigger if exists mirror_facts_into_product_specs on public.spec_facts;
create trigger mirror_facts_into_product_specs
  after insert or update or delete on public.spec_facts
  for each row execute function public.mirror_facts_into_product_specs_internal_v1();

drop trigger if exists mirror_fact_values_into_product_specs on public.spec_fact_values;
create trigger mirror_fact_values_into_product_specs
  after insert or delete on public.spec_fact_values
  for each row execute function public.mirror_facts_into_product_specs_internal_v1();

commit;
