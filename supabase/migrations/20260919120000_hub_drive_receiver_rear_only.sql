-- A hub's drivetrain receiver belongs only to a rear hub (2026-09-19).
-- The previous contract explained that rule in prose but exposed the fields for
-- front and universal hubs, and pair rows accepted a receiver on the front
-- piece. Tighten the scalar and row prerequisites without rewriting any facts.
-- No current production fact violates the stricter contract; guards fail
-- closed if that precondition changes before deployment.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $guard$
declare
  v_contract jsonb;
  v_columns jsonb;
begin
  if (select count(*) from public.spec_templates
      where tenant_id is null and key = 'hub' and is_active) <> 1 then
    raise exception 'Expected exactly one active global hub template';
  end if;
  if (select count(*) from public.spec_definitions
      where tenant_id is null and key = 'hub_package_pieces'
        and data_type = 'json') <> 1 then
    raise exception 'Expected the global structured hub_package_pieces definition';
  end if;

  select form_contract
    into v_contract
    from public.spec_templates
   where tenant_id is null and key = 'hub' and is_active;

  if v_contract->>'rules_version' <> '2'
     or v_contract #> '{allowed_when,hub_drive_receiver_present}' is null
     or v_contract #> '{row_conditions,fields,hub_package_pieces,allowed_when}' is null then
    raise exception 'Hub contract does not expose the reviewed scalar and row conditions';
  end if;

  select validation_rules #> '{rows_schema,columns}'
    into v_columns
    from public.spec_definitions
   where tenant_id is null and key = 'hub_package_pieces';

  if jsonb_typeof(v_columns) <> 'array'
     or (select count(*) from jsonb_array_elements(v_columns) c
          where c->>'key' = 'drive_interface_present') <> 1 then
    raise exception 'Hub package row schema has no unique drive_interface_present column';
  end if;

  if exists (
    with hub_values as (
      select p.id,
             max(coalesce(v.value_option, v.value_text))
               filter (where d.key = 'hub_package_position') as position,
             bool_or(v.value_boolean)
               filter (where d.key = 'hub_drive_receiver_present') as drive_present,
             max(coalesce(v.value_option, v.value_text))
               filter (where d.key = 'hub_drive_receiver_kind') as drive_kind,
             max(v.value_text)
               filter (where d.key = 'hub_drive_receiver_reference') as drive_reference
        from public.products p
        join public.product_spec_values v
          on v.tenant_id = p.tenant_id and v.product_id = p.id
        join public.spec_definitions d on d.id = v.spec_definition_id
       where p.spec_template_id = (
               select id from public.spec_templates
                where tenant_id is null and key = 'hub' and is_active)
         and d.key in (
               'hub_package_position',
               'hub_drive_receiver_present',
               'hub_drive_receiver_kind',
               'hub_drive_receiver_reference')
       group by p.id
    )
    select 1
      from hub_values
     where position is distinct from 'Trasera'
       and (drive_present is true
            or drive_kind is not null
            or drive_reference is not null)
  ) then
    raise exception 'A non-rear hub still carries a drivetrain receiver fact';
  end if;

  if exists (
    select 1
      from public.product_spec_values v
      join public.spec_definitions d on d.id = v.spec_definition_id
      cross join lateral jsonb_array_elements(v.value_json->'rows') r
     where d.tenant_id is null
       and d.key = 'hub_package_pieces'
       and r #>> '{values,piece_position}' = 'Delantera'
       and (
         r #> '{values,drive_interface_present}' = 'true'::jsonb
         or r #> '{values,drive_receiver_kind}' is not null
         or r #> '{values,drive_receiver_reference}' is not null
       )
  ) then
    raise exception 'A front hub package row still carries a drivetrain receiver';
  end if;
end
$guard$;

do $patch$
declare
  v_contract jsonb;
  v_rear jsonb := '{"kind":"when","rows":[[{"field":"hub_package_position","operator":"eq","value_type":"token","value":"Trasera"}]]}'::jsonb;
  v_receiver jsonb := '{"kind":"when","rows":[[{"field":"hub_package_position","operator":"eq","value_type":"token","value":"Trasera"},{"field":"hub_drive_receiver_present","operator":"eq","value_type":"boolean","value":true}]]}'::jsonb;
  v_row_rear jsonb := '{"kind":"when","rows":[[{"field":"piece_position","operator":"eq","value_type":"token","value":"Trasera"}]]}'::jsonb;
  v_row_receiver jsonb := '{"kind":"when","rows":[[{"field":"piece_position","operator":"eq","value_type":"token","value":"Trasera"},{"field":"drive_interface_present","operator":"eq","value_type":"boolean","value":true}]]}'::jsonb;
  v_helpers jsonb := '{
    "spoke_hole_count": "Cuántos rayos lleva la rueda. Cuenta todos los hoyos de las dos bridas: una maza de 32 hoyos suele tener 16 en cada brida.",
    "flange_pcd_left_mm": "Diámetro del círculo que forman los hoyos de los rayos en la brida izquierda. Se mide de centro de hoyo a centro del hoyo de enfrente.",
    "flange_pcd_right_mm": "Diámetro del círculo que forman los hoyos de los rayos en la brida derecha. Se mide de centro de hoyo a centro del hoyo de enfrente.",
    "hub_drive_receiver_present": "Sólo para mazas traseras. Sí si trae núcleo para cassette, rosca para rueda libre o la interfaz documentada para su piñón.",
    "hub_drive_receiver_kind": "Cómo se monta el piñón en esta maza trasera: núcleo estriado de cassette, rosca de rueda libre, rosca de piñón fijo, anillo o driver BMX.",
    "hub_drive_receiver_reference": "El nombre exacto del núcleo, rosca o driver según el fabricante (por ejemplo «HG 8-11v» o «Micro Spline»), si lo publica."
  }'::jsonb;
begin
  select form_contract
    into v_contract
    from public.spec_templates
   where tenant_id is null and key = 'hub' and is_active
   for update;

  v_contract := jsonb_set(v_contract, '{allowed_when,hub_drive_receiver_present}', v_rear, true);
  v_contract := jsonb_set(v_contract, '{required_when,hub_drive_receiver_present}', v_rear, true);
  v_contract := jsonb_set(v_contract, '{allowed_when,hub_drive_receiver_kind}', v_receiver, true);
  v_contract := jsonb_set(v_contract, '{required_when,hub_drive_receiver_kind}', v_receiver, true);
  v_contract := jsonb_set(v_contract, '{allowed_when,hub_drive_receiver_reference}', v_receiver, true);
  v_contract := jsonb_set(v_contract, '{required_when,hub_drive_receiver_reference}', v_receiver, true);
  v_contract := jsonb_set(v_contract, '{row_conditions,fields,hub_package_pieces,allowed_when,drive_interface_present}', v_row_rear, true);
  v_contract := jsonb_set(v_contract, '{row_conditions,fields,hub_package_pieces,required_when,drive_interface_present}', v_row_rear, true);
  v_contract := jsonb_set(v_contract, '{row_conditions,fields,hub_package_pieces,allowed_when,drive_receiver_kind}', v_row_receiver, true);
  v_contract := jsonb_set(v_contract, '{row_conditions,fields,hub_package_pieces,required_when,drive_receiver_kind}', v_row_receiver, true);
  v_contract := jsonb_set(v_contract, '{row_conditions,fields,hub_package_pieces,allowed_when,drive_receiver_reference}', v_row_receiver, true);
  v_contract := jsonb_set(v_contract, '{row_conditions,fields,hub_package_pieces,required_when,drive_receiver_reference}', v_row_receiver, true);
  v_contract := jsonb_set(v_contract, '{helpers}', coalesce(v_contract->'helpers', '{}'::jsonb) || v_helpers, true);

  update public.spec_templates
     set form_contract = v_contract,
         updated_at = now()
   where tenant_id is null
     and key = 'hub'
     and is_active
     and form_contract is distinct from v_contract;
end
$patch$;

update public.spec_definitions d
   set validation_rules = jsonb_set(
         d.validation_rules,
         '{rows_schema,columns}',
         (
           select jsonb_agg(
                    case when c.value->>'key' = 'drive_interface_present'
                         then jsonb_set(c.value, '{required}', 'false'::jsonb, true)
                         else c.value end
                    order by c.ordinality)
             from jsonb_array_elements(
                    d.validation_rules #> '{rows_schema,columns}')
                  with ordinality c(value, ordinality)
         ),
         true),
       updated_at = now()
 where d.tenant_id is null
   and d.key = 'hub_package_pieces'
   and exists (
     select 1
       from jsonb_array_elements(
              d.validation_rules #> '{rows_schema,columns}') c
      where c->>'key' = 'drive_interface_present'
        and c->>'required' is distinct from 'false'
   );

update public.spec_definitions
   set label = case key
         when 'spoke_hole_count' then 'Cantidad total de hoyos (rayos)'
         when 'hub_spoke_head_interface' then 'Entrada del rayo (con codo o recta)'
         when 'hub_drive_receiver_kind' then 'Cómo se monta el piñón'
         when 'hub_drive_receiver_reference' then 'Modelo del núcleo, rosca o driver'
         else label
       end,
       updated_at = now()
 where tenant_id is null
   and key in (
     'spoke_hole_count',
     'hub_spoke_head_interface',
     'hub_drive_receiver_kind',
     'hub_drive_receiver_reference')
   and label is distinct from case key
         when 'spoke_hole_count' then 'Cantidad total de hoyos (rayos)'
         when 'hub_spoke_head_interface' then 'Entrada del rayo (con codo o recta)'
         when 'hub_drive_receiver_kind' then 'Cómo se monta el piñón'
         when 'hub_drive_receiver_reference' then 'Modelo del núcleo, rosca o driver'
         else label
       end;

commit;
