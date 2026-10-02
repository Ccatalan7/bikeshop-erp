-- La lectura del editor dice de dónde salió cada dato (20261002110000).
begin;

select no_plan();

-- Una cadena con el ancho leído del nombre y los eslabones del texto del
-- proveedor; un tercer hecho de otro producto no se mezcla.
set local session_replication_role = replica;
insert into public.tenants(id, shop_name)
values ('99e20000-0000-4000-8000-000000000001', 'Value sources');
insert into public.products(id, tenant_id, name, sku)
values ('99e20000-0000-4000-8000-000000000002', '99e20000-0000-4000-8000-000000000001',
        'Cadena 3/32 116 eslabones', 'VS-1'),
       ('99e20000-0000-4000-8000-000000000003', '99e20000-0000-4000-8000-000000000001',
        'Otra cadena', 'VS-2');
insert into public.spec_facts(id, tenant_id, subject_type, subject_id, spec_definition_id,
                              source, confirmed, value_number)
select x.id::uuid, '99e20000-0000-4000-8000-000000000001', 'product', x.product::uuid, d.id,
       x.source, false, x.number
  from (values
    ('99e20000-0000-4000-8000-000000000011', '99e20000-0000-4000-8000-000000000002',
     'chain_width_family', 'name_reading', null::numeric),
    ('99e20000-0000-4000-8000-000000000012', '99e20000-0000-4000-8000-000000000002',
     'link_count', 'supplier_text', 116),
    ('99e20000-0000-4000-8000-000000000013', '99e20000-0000-4000-8000-000000000003',
     'link_count', 'research', 112)) x(id, product, key, source, number)
  join public.spec_definitions d on d.key = x.key and d.tenant_id is null;
insert into public.spec_fact_readings(fact_id, tenant_id, source_text, source_digest, quote, model,
                                      read_at, vocabulary_digest, definition_id)
select '99e20000-0000-4000-8000-000000000011', '99e20000-0000-4000-8000-000000000001',
       'Cadena 3/32 116 eslabones',
       encode(sha256(convert_to('Cadena 3/32 116 eslabones', 'UTF8')), 'hex'),
       '3/32', 'fixture', now(),
       public.spec_definition_vocabulary_digest_internal_v1(d.id), d.id
  from public.spec_definitions d where d.key = 'chain_width_family' and d.tenant_id is null;
set local session_replication_role = origin;

select is(
  public.spec_product_value_sources_internal_v1(
    '99e20000-0000-4000-8000-000000000002',
    (select id from public.spec_templates where key = 'chain' and tenant_id is null and is_active)),
  '{"link_count": {"source": "supplier_text", "reading_current": null},
    "chain_width_family": {"source": "name_reading", "reading_current": true}}'::jsonb,
  'cada valor del producto trae su procedencia, y la lectura del nombre dice si sigue en pie');

-- Si el nombre cambia, la lectura deja de estar en pie; la procedencia queda.
update public.products set name = 'Cadena renombrada'
 where id = '99e20000-0000-4000-8000-000000000002';
select is(
  public.spec_product_value_sources_internal_v1(
    '99e20000-0000-4000-8000-000000000002',
    (select id from public.spec_templates where key = 'chain' and tenant_id is null and is_active))
    ->'chain_width_family',
  '{"source": "name_reading", "reading_current": false}'::jsonb,
  'una lectura de un nombre anterior se dice como tal');

select is(
  has_function_privilege('authenticated',
    'public.spec_product_value_sources_internal_v1(uuid,uuid)', 'execute'),
  false,
  'la procedencia sólo sale por la lectura del editor, que comprueba el tenant');

select * from finish();
rollback;
