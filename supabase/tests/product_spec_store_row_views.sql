-- The storefront reads a rows field through its store view (20261002140000):
-- only the columns a customer needs, numbers with a decimal comma, the rows
-- the source admits, in a stable order; never the source document or URL.
-- A view that leaves nothing removes the row from the sheet.
begin;
select no_plan();

create function pg_temp.shown(p_view jsonb, p_schema jsonb, p_rows jsonb) returns text language sql as $$
 select public.spec_rows_store_display_internal_v1(p_view, p_schema,
   jsonb_build_object('schema_version', 1, 'rows',
     (select coalesce(jsonb_agg(jsonb_build_object('id', 'r' || n, 'values', r, 'sources', '[]'::jsonb) order by n), '[]')
      from jsonb_array_elements(p_rows) with ordinality x(r, n)))) $$;

select is(pg_temp.shown('{"format":"{teeth}","sort_by":"position","join":"-","suffix":" dientes","distinct":false}',
  '{"columns":[{"key":"position","type":"integer"},{"key":"teeth","type":"integer"}]}',
  '[{"position":"3","teeth":"15"},{"position":"1","teeth":"11"},{"position":"2","teeth":"13"},{"position":"4","teeth":"15"}]'),
  '11-13-15-15 dientes', 'a cog sequence follows position and keeps repeated teeth');
select is(pg_temp.shown('{"format":"BSD: {bead_seat_diameter_mm} · máximo: {max_tire_width_mm}","join":" | "}',
  '{"columns":[{"key":"bead_seat_diameter_mm","type":"integer"},{"key":"max_tire_width_mm","type":"decimal"},{"key":"source_url","type":"url"}]}',
  '[{"bead_seat_diameter_mm":"622","max_tire_width_mm":"58.50","source_url":"https://example.test/fork.pdf"}]'),
  'BSD: 622 · máximo: 58,5', 'decimal comma, no trailing zeros, the source URL stays out');
select is(pg_temp.shown('{"format":"{target_system}","only":{"verdict":["Admitido por la fuente"]},"join":", ","replace":[["(\\d)-speed","\\1 velocidades"]]}',
  '{"columns":[{"key":"target_system","type":"text"},{"key":"verdict","type":"token"}]}',
  '[{"target_system":"KMC 11-speed","verdict":"Admitido por la fuente"},{"target_system":"Campagnolo 11-speed","verdict":"Excluido por la fuente"},{"target_system":"SRAM 11-speed","verdict":"Admitido por la fuente"}]'),
  'KMC 11 velocidades, SRAM 11 velocidades', 'only admitted rows, in customer words');
select is(pg_temp.shown('{"format":"{target_system}","only":{"verdict":["Admitido por la fuente"]}}',
  '{"columns":[{"key":"target_system","type":"text"},{"key":"verdict","type":"token"}]}',
  '[{"target_system":"Campagnolo","verdict":"Excluido por la fuente"},{"verdict":"Admitido por la fuente"}]'),
  null, 'nothing admitted and complete shows nothing');
select is(pg_temp.shown('{"format":["{direct_tube_diameter_mm} mm","{reduced_tube_diameter_mm} mm (con casquillo)"],"join":", "}',
  '{"columns":[{"key":"direct_tube_diameter_mm","type":"decimal"},{"key":"reduced_tube_diameter_mm","type":"decimal"}]}',
  '[{"direct_tube_diameter_mm":"34.9"},{"reduced_tube_diameter_mm":"31.8"},{"reduced_tube_diameter_mm":"31.8"}]'),
  '34,9 mm, 31,8 mm (con casquillo)', 'the first complete format wins and repeated readings collapse');
select is(pg_temp.shown('{"format":"{teeth}","sort_by":"teeth","sort_desc":true,"join":"-","suffix":" dientes","distinct":false}',
  '{"columns":[{"key":"teeth","type":"integer"}]}',
  '[{"teeth":"24"},{"teeth":"42"},{"teeth":"34"}]'),
  '42-34-24 dientes', 'chainrings read from the largest');
select is(pg_temp.shown('{"format":"{member_role} {identity_model}","join":", "}',
  '{"columns":[{"key":"member_role","type":"token"},{"key":"identity_model","type":"text"}]}',
  '[{"member_role":"manilla","identity_model":"BL-MT200"}]'),
  'Manilla BL-MT200', 'the text starts with a capital letter');
select is(public.spec_rows_store_display_internal_v1(null, '{}', '{"rows":[{"values":{"a":"1"}}]}'), null, 'no view, no text');
select is(public.spec_rows_store_display_internal_v1('{"format":"{a}"}', '{}', '{}'), null, 'no rows, no text');

select throws_ok($$update public.spec_definitions set store_view='{"format":"{a}"}'
  where id=(select id from public.spec_definitions where tenant_id is null and not (validation_rules ? 'rows_schema') limit 1)$$,
  '23514', null, 'only a rows field has a store view');

-- A view is judged whole when it is saved: one that failed while reading
-- would take down the sheet of every product that shows it.
create function pg_temp.problem(p_view jsonb) returns text language sql as $$
 select public.spec_store_view_problem_internal_v1(p_view,
   '{"columns":[{"key":"teeth","type":"integer"},{"key":"verdict","type":"token"}]}') $$;
select is(pg_temp.problem('{"format":"{teeth}","only":{"verdict":["Admitido"]},"sort_by":"teeth","sort_desc":true,"distinct":false,"join":"-","suffix":" dientes","replace":[["(\\d)-speed","\\1 velocidades"]]}'),
  null, 'a complete view passes');
select is(pg_temp.problem('{"join":"-"}'), 'falta format', 'a view needs a format');
select is(pg_temp.problem('{"format":"{teeth}","sort_desc":"invalid"}'), 'sort_desc y distinct son sí o no', 'a flag is a boolean');
select is(pg_temp.problem('{"format":"{tooth}"}'), 'format nombra una columna que la tabla no tiene: tooth', 'a format names real columns');
select is(pg_temp.problem('{"format":"{teeth}","only":{"verdict":"Admitido"}}'), 'only lleva una lista de textos por columna', 'only takes lists');
select is(pg_temp.problem('{"format":"{teeth}","replace":[["(unclosed","x"]]}'), 'patrón inválido en replace: (unclosed', 'a replace pattern compiles');
select is(pg_temp.problem('{"format":"{teeth}","order":"teeth"}'), 'clave desconocida: order', 'no unknown keys');

-- End to end: a published chain with a rows field read through its view.
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values ('99c50000-0000-4000-8000-000000000001','Store row views');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('99c50000-0000-4000-8000-000000000091','authenticated','authenticated','store-row-views@example.invalid','',now(),'{}',
 jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99c50000-0000-4000-8000-000000000001'),now(),now());
delete from public.user_profiles where user_id='99c50000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values ('99c50000-0000-4000-8000-000000000091','99c50000-0000-4000-8000-000000000001','admin');
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99c50000-0000-4000-8000-000000000010','99c50000-0000-4000-8000-000000000001','Cadenas','Cadenas');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status)
select '99c50000-0000-4000-8000-000000000001','99c50000-0000-4000-8000-000000000010','chain',id,'active'
from public.spec_templates where key='chain' and tenant_id is null;
insert into public.spec_definitions(id,key,label,data_type,validation_rules,is_customer_visible,store_label,store_view) values
 ('99c50000-0000-4000-8000-000000000055','store_view_probe_claims','Declaraciones de la fuente','json',
  '{"rows_schema":{"version":1,"columns":[{"key":"target_system","label":"Sistema declarado","type":"text"},{"key":"verdict","label":"Declaración","type":"token","allowed_values":["Admitido por la fuente","Excluido por la fuente"]},{"key":"source_url","label":"URL","type":"url"}]}}',
  true,'Para cadenas','{"format":"{target_system}","only":{"verdict":["Admitido por la fuente"]},"join":", "}');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select id,'99c50000-0000-4000-8000-000000000055','primary',99 from public.spec_templates where key='chain' and tenant_id is null;
select set_config('request.jwt.claims','{"sub":"99c50000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99c50000-0000-4000-8000-000000000091',true);

create function pg_temp.save(p_id uuid, p_sku text, p_rows jsonb) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
  jsonb_build_object('id',p_id,'name','Cadena KMC '||p_sku,'sku',p_sku,'brand','KMC','model',p_sku,'price',9990,'cost',4000,
   'category_id','99c50000-0000-4000-8000-000000000010','is_published',true,'show_on_website',true),
  true,(select id from public.spec_templates where key='chain' and tenant_id is null),
  (select contract_version from public.spec_templates where key='chain' and tenant_id is null),
  jsonb_build_object('99c50000-0000-4000-8000-000000000055',jsonb_build_object('rows',jsonb_build_object('schema_version',1,'rows',p_rows))),
  null,null,'store-row-views-'||p_sku,null,null) $$;

select lives_ok($$select pg_temp.save('99c50000-0000-4000-8000-000000000020','ROWS-A',
 '[{"id":"a","values":{"target_system":"Shimano 11 velocidades","verdict":"Admitido por la fuente","source_url":"https://example.test/a"},"sources":["https://example.test/a"]},
   {"id":"b","values":{"target_system":"Campagnolo 11","verdict":"Excluido por la fuente","source_url":"https://example.test/a"},"sources":["https://example.test/a"]}]')$$,
 'a published chain with source declarations');
select lives_ok($$select pg_temp.save('99c50000-0000-4000-8000-000000000021','ROWS-B',
 '[{"id":"b","values":{"target_system":"Campagnolo 11","verdict":"Excluido por la fuente","source_url":"https://example.test/b"},"sources":["https://example.test/b"]}]')$$,
 'a published chain whose only declaration is an exclusion');

select throws_ok($$update public.spec_definitions set store_view='{"format":"{target_system}","sort_desc":"invalid"}'
  where id='99c50000-0000-4000-8000-000000000055'$$, '23514', null, 'a broken view is not saved');

set local role anon;
select is((select display_value from public.get_public_product_technical_specs('99c50000-0000-4000-8000-000000000001','99c50000-0000-4000-8000-000000000020')
  where spec_key='store_view_probe_claims'), 'Shimano 11 velocidades', 'the visitor reads the admitted system, not the URL');
select is((select spec_label from public.get_public_product_technical_specs('99c50000-0000-4000-8000-000000000001','99c50000-0000-4000-8000-000000000020')
  where spec_key='store_view_probe_claims'), 'Para cadenas', 'under its store name');
select ok(not exists(select 1 from public.get_public_product_technical_specs('99c50000-0000-4000-8000-000000000001','99c50000-0000-4000-8000-000000000021')
  where spec_key='store_view_probe_claims'), 'a view that leaves nothing is not in the sheet');
select ok(not exists(select 1 from public.get_public_product_technical_specs('99c50000-0000-4000-8000-000000000001','99c50000-0000-4000-8000-000000000020')
  where display_value ilike '%example.test%'), 'no source URL reaches the storefront');
select throws_ok($$select public.spec_rows_store_display_internal_v1('{"format":"{a}"}','{}','{}')$$,'42501',null,'the formatter stays internal');
reset role;

select * from finish();
rollback;
