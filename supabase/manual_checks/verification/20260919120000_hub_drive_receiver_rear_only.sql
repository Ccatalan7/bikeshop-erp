-- Fails until the hub drive receiver is rear-only at scalar and pair-row scope.
with expected as (
  select
    '{"kind":"when","rows":[[{"field":"hub_package_position","operator":"eq","value_type":"token","value":"Trasera"}]]}'::jsonb as rear,
    '{"kind":"when","rows":[[{"field":"hub_package_position","operator":"eq","value_type":"token","value":"Trasera"},{"field":"hub_drive_receiver_present","operator":"eq","value_type":"boolean","value":true}]]}'::jsonb as receiver,
    '{"kind":"when","rows":[[{"field":"piece_position","operator":"eq","value_type":"token","value":"Trasera"}]]}'::jsonb as row_rear,
    '{"kind":"when","rows":[[{"field":"piece_position","operator":"eq","value_type":"token","value":"Trasera"},{"field":"drive_interface_present","operator":"eq","value_type":"boolean","value":true}]]}'::jsonb as row_receiver
),
contract_ok as (
  select count(*) = 1 as ok
    from public.spec_templates t
    cross join expected e
   where t.tenant_id is null
     and t.key = 'hub'
     and t.is_active
     and t.form_contract #> '{allowed_when,hub_drive_receiver_present}' = e.rear
     and t.form_contract #> '{required_when,hub_drive_receiver_present}' = e.rear
     and t.form_contract #> '{allowed_when,hub_drive_receiver_kind}' = e.receiver
     and t.form_contract #> '{required_when,hub_drive_receiver_kind}' = e.receiver
     and t.form_contract #> '{allowed_when,hub_drive_receiver_reference}' = e.receiver
     and t.form_contract #> '{required_when,hub_drive_receiver_reference}' = e.receiver
     and t.form_contract #> '{row_conditions,fields,hub_package_pieces,allowed_when,drive_interface_present}' = e.row_rear
     and t.form_contract #> '{row_conditions,fields,hub_package_pieces,required_when,drive_interface_present}' = e.row_rear
     and t.form_contract #> '{row_conditions,fields,hub_package_pieces,allowed_when,drive_receiver_kind}' = e.row_receiver
     and t.form_contract #> '{row_conditions,fields,hub_package_pieces,required_when,drive_receiver_kind}' = e.row_receiver
     and t.form_contract #> '{row_conditions,fields,hub_package_pieces,allowed_when,drive_receiver_reference}' = e.row_receiver
     and t.form_contract #> '{row_conditions,fields,hub_package_pieces,required_when,drive_receiver_reference}' = e.row_receiver
     and t.form_contract #>> '{helpers,spoke_hole_count}' =
       'Cuántos rayos lleva la rueda. Cuenta todos los hoyos de las dos bridas: una maza de 32 hoyos suele tener 16 en cada brida.'
),
schema_ok as (
  select count(*) = 1 as ok
    from public.spec_definitions d
    cross join lateral jsonb_array_elements(
      d.validation_rules #> '{rows_schema,columns}') c
   where d.tenant_id is null
     and d.key = 'hub_package_pieces'
     and c->>'key' = 'drive_interface_present'
     and c->>'required' = 'false'
),
labels_ok as (
  select count(*) = 4 as ok
    from public.spec_definitions
   where tenant_id is null
     and (key, label) in (
       ('spoke_hole_count', 'Cantidad total de hoyos (rayos)'),
       ('hub_spoke_head_interface', 'Entrada del rayo (con codo o recta)'),
       ('hub_drive_receiver_kind', 'Cómo se monta el piñón'),
       ('hub_drive_receiver_reference', 'Modelo del núcleo, rosca o driver')
     )
),
hub_values as (
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
),
data_ok as (
  select
    not exists (
      select 1
        from hub_values
       where position is distinct from 'Trasera'
         and (drive_present is true
              or drive_kind is not null
              or drive_reference is not null)
    )
    and not exists (
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
    ) as ok
)
select 1 / case when contract_ok.ok and schema_ok.ok and labels_ok.ok and data_ok.ok
                then 1 else 0 end
  from contract_ok, schema_ok, labels_ok, data_ok;
