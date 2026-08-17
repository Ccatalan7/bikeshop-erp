begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select no_plan();

select is(
  (
    select template.technical_family
    from public.spec_templates template
    where template.tenant_id is null
      and template.key = 'tire'
  ),
  'tire',
  'the tire ficha has one active system technical family'
);

select is(
  (
    select count(*)::integer
    from public.spec_template_fields field
    join public.spec_templates template on template.id = field.template_id
    join public.spec_definitions definition
      on definition.id = field.spec_definition_id
    where template.tenant_id is null
      and template.key = 'tire'
      and definition.tenant_id is null
      and definition.key in (
        'wheel_size',
        'tire_width_in',
        'tire_width_mm',
        'tire_etrto',
        'tire_bead_type',
        'tire_tubeless_ready'
      )
      and definition.is_filterable is true
  ),
  6,
  'the tire ficha exposes the six canonical filterable facts'
);

select ok(
  not exists (
    select 1
    from public.product_categories category
    left join public.category_tech_mappings mapping
      on mapping.tenant_id = category.tenant_id
     and mapping.category_id = category.id
     and mapping.status = 'active'
    left join public.spec_templates template on template.id = mapping.template_id
    where category.is_active is true
      and category.full_path = 'Componentes / Ruedas / Neumáticos'
      and (
        mapping.technical_family is distinct from 'tire'
        or template.key is distinct from 'tire'
      )
  ),
  'every exact active tire category is bridged to the canonical tire template'
);

select ok(
  not exists (
    select 1
    from public.product_spec_values value
    join public.spec_definitions definition
      on definition.id = value.spec_definition_id
    where definition.tenant_id is null
      and definition.key in (
        'tire_width_in',
        'tire_width_mm',
        'tire_etrto',
        'tire_bead_type',
        'tire_tubeless_ready'
      )
      and value.created_at >= transaction_timestamp()
  ),
  'the schema migration does not invent product facts from commercial names'
);

select * from finish();
rollback;
