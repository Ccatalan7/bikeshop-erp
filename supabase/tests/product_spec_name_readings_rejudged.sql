-- Una lectura del nombre muda por un cambio de vocabulario vuelve a contar si
-- el juez actual acepta su cita, y sigue muda si no (20261002120000).
begin;

select no_plan();

-- Fixture mínima, sin disparadores: un producto con dos lecturas de «Ancho»
-- cuya huella de vocabulario quedó vieja.
set local session_replication_role = replica;
insert into public.tenants(id, shop_name)
values ('99e10000-0000-4000-8000-000000000001', 'Readings rejudged');
insert into public.products(id, tenant_id, name, sku)
values ('99e10000-0000-4000-8000-000000000002', '99e10000-0000-4000-8000-000000000001',
        'Cadena 3/32 116 eslabones', 'RJ-1'),
       ('99e10000-0000-4000-8000-000000000003', '99e10000-0000-4000-8000-000000000001',
        'Cadena 3/32 116 eslabones', 'RJ-2');
with fixture(fact_id, product_id, quote) as (values
  ('99e10000-0000-4000-8000-000000000011'::uuid, '99e10000-0000-4000-8000-000000000002'::uuid, '3/32'),
  ('99e10000-0000-4000-8000-000000000012'::uuid, '99e10000-0000-4000-8000-000000000003'::uuid, '116 eslabones')
), definition as (
  select d.id from public.spec_definitions d
   where d.key = 'chain_width_family' and d.tenant_id is null
), facts as (
  insert into public.spec_facts(id, tenant_id, subject_type, subject_id, spec_definition_id, source, confirmed)
  select x.fact_id, '99e10000-0000-4000-8000-000000000001', 'product', x.product_id, d.id,
         'name_reading', false
    from fixture x cross join definition d
  returning id
), chosen as (
  insert into public.spec_fact_values(fact_id, value_id, position)
  select x.fact_id, v.id, 0
    from fixture x cross join definition d
    join public.spec_definition_values v on v.spec_definition_id = d.id and v.label = '3/32'
  returning fact_id
)
insert into public.spec_fact_readings(fact_id, tenant_id, source_text, source_digest, quote, model,
                                      read_at, vocabulary_digest, definition_id)
select x.fact_id, '99e10000-0000-4000-8000-000000000001', 'Cadena 3/32 116 eslabones',
       encode(sha256(convert_to('Cadena 3/32 116 eslabones', 'UTF8')), 'hex'),
       x.quote, 'fixture', now(), 'vocabulario-anterior', d.id
  from fixture x cross join definition d;
set local session_replication_role = origin;

select is(public.spec_rejudge_name_readings_internal_v1(), 1,
  'sólo vuelve a contar la lectura cuya cita dice el valor');

select is(
  (select r.vocabulary_digest = public.spec_definition_vocabulary_digest_internal_v1(r.definition_id)
     from public.spec_fact_readings r
    where r.fact_id = '99e10000-0000-4000-8000-000000000011'),
  true,
  '«3/32» dice 3/32: recibe la huella del vocabulario actual');

select is(
  (select r.vocabulary_digest from public.spec_fact_readings r
    where r.fact_id = '99e10000-0000-4000-8000-000000000012'),
  'vocabulario-anterior',
  '«116 eslabones» no dice el ancho: sigue muda');

select * from finish();
rollback;
