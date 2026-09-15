-- Reviewed extension: two private functions; no metadata/data rewrite or new grants.
begin isolation level repeatable read;
set local lock_timeout='5s';
set local statement_timeout='30s';
lock table public.spec_definitions in share mode;
do $before$
declare wanted jsonb; actual record; old_count integer:=0; new_count integer:=0;
begin
 for wanted in select value from jsonb_array_elements('[{"acl": "{postgres=X/postgres,service_role=X/postgres}", "md5": "c21cb764086b89a50c5580ad72c0c970", "settings": ["search_path=pg_catalog, public, pg_temp"], "signature": "spec_rows_schema_validate_internal_v1(jsonb)", "owner_name": "postgres", "volatility": "i", "security_definer": false, "before_md5": "e4147389be641a0c61e0f625c676e39b"}, {"acl": "{postgres=X/postgres,service_role=X/postgres}", "md5": "a7e629a22356148871253ad48ef25b3f", "settings": ["search_path=pg_catalog, public, pg_temp"], "signature": "spec_rows_validate_internal_v1(jsonb,jsonb)", "owner_name": "postgres", "volatility": "i", "security_definer": false, "before_md5": "79623b3e97219d95b035aa0705be7757"}]'::jsonb) loop
  select md5(pg_get_functiondef(p.oid)) body_md5,pg_get_userbyid(p.proowner) owner_name,
   p.proacl::text acl,p.prosecdef security_definer,p.provolatile::text volatility,
   to_jsonb(p.proconfig) settings into actual from pg_proc p
   where p.oid=to_regprocedure('public.'||(wanted->>'signature'));
  if not found or actual.owner_name is distinct from wanted->>'owner_name'
   or actual.acl is distinct from wanted->>'acl'
   or actual.security_definer is distinct from (wanted->>'security_definer')::boolean
   or actual.volatility is distinct from wanted->>'volatility'
   or actual.settings is distinct from wanted->'settings' then
   raise exception 'Unreviewed strict-row function permissions or mode';
  end if;
  old_count:=old_count+case when actual.body_md5=wanted->>'before_md5' then 1 else 0 end;
  new_count:=new_count+case when actual.body_md5=wanted->>'md5' then 1 else 0 end;
 end loop;
 if old_count<>2 and new_count<>2 then
  raise exception 'Unreviewed or mixed strict-row function bodies';
 end if;
end $before$;
create temporary table strict_row_before on commit drop as select jsonb_build_object(
 'definitions',(select md5(coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]')::text) from public.spec_definitions d),
 'templates',(select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')::text) from public.spec_templates t),
 'fields',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_template_fields f),
 'facts',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f),
 'references',(select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]')::text) from public.product_spec_references r),
 'products',(select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p)) as fingerprint
;
create or replace function public.spec_rows_schema_validate_internal_v1(p_schema jsonb)
returns void language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $schema$
#variable_conflict use_column
declare c jsonb; g jsonb; k text; names text[]:='{}'; v_min numeric; v_max numeric;
begin
 if jsonb_typeof(p_schema) is distinct from 'object' or coalesce(p_schema->'version' not in ('1'::jsonb,'2'::jsonb),true)
   or jsonb_typeof(p_schema->'columns') is distinct from 'array' then
   raise exception 'Esquema de filas no disponible' using errcode='22023';
 end if;
 if jsonb_array_length(p_schema->'columns')=0 or exists(select 1 from jsonb_object_keys(p_schema) k
   where k not in ('version','columns','ordered_pairs','strict_ordered_pairs','unique_by')) then
   raise exception 'Esquema de filas inválido' using errcode='22023';
 end if;
 if p_schema ? 'strict_ordered_pairs' and p_schema->'version' is distinct from '2'::jsonb then
   raise exception 'El orden estricto requiere esquema de filas v2' using errcode='22023';
 end if;
 for c in select value from jsonb_array_elements(p_schema->'columns') loop
   if jsonb_typeof(c) is distinct from 'object' then raise exception 'Columna inválida' using errcode='22023'; end if;
   if jsonb_typeof(c->'key') is distinct from 'string' or (c->>'key') !~ '^[a-z][a-z0-9_]*$'
     or (c->>'key') ~ '[[:space:]]' or c->>'key'=any(names)
     or jsonb_typeof(c->'label') is distinct from 'string' or btrim(c->>'label')=''
     or coalesce(c->>'type','') not in ('text','token','decimal','integer','boolean','url')
     or (c ? 'unit' and jsonb_typeof(c->'unit') not in ('string','null'))
     or (c ? 'required' and jsonb_typeof(c->'required')<>'boolean')
     or exists(select 1 from jsonb_object_keys(c) k where k not in
       ('key','label','type','unit','required','allowed_values','validation')) then
     raise exception 'Definición de columna inválida' using errcode='22023';
   end if;
   names:=array_append(names,c->>'key');
   if c ? 'allowed_values' then
     if jsonb_typeof(c->'allowed_values')<>'array' then raise exception 'Vocabulario inválido' using errcode='22023'; end if;
     if (jsonb_array_length(c->'allowed_values')>0 and c->>'type'<>'token')
       or exists(select 1 from jsonb_array_elements(c->'allowed_values') x where jsonb_typeof(x)<>'string' or x#>>'{}'='')
       or jsonb_array_length(c->'allowed_values')<>(select count(distinct x) from jsonb_array_elements(c->'allowed_values') x) then
       raise exception 'Vocabulario de columna inválido' using errcode='22023';
     end if;
   end if;
   if c ? 'validation' then
     if jsonb_typeof(c->'validation')<>'object' then raise exception 'Dominio inválido' using errcode='22023'; end if;
     if exists(select 1 from jsonb_object_keys(c->'validation') k where k not in ('positive','min','max'))
       or (c->'validation'<>'{}'::jsonb and c->>'type' not in ('decimal','integer'))
       or (c->'validation' ? 'positive' and jsonb_typeof(c->'validation'->'positive')<>'boolean') then
       raise exception 'Dominio de columna inválido' using errcode='22023';
     end if;
     foreach k in array array['min','max'] loop
       if c->'validation' ? k and (jsonb_typeof(c->'validation'->k)<>'string'
         or public.spec_rule_number_internal_v1(c->'validation'->k) is null) then
         raise exception 'Límite decimal inválido' using errcode='22023';
       end if;
     end loop;
     v_min:=public.spec_rule_number_internal_v1(c->'validation'->'min');
     v_max:=public.spec_rule_number_internal_v1(c->'validation'->'max');
     if v_min>v_max then raise exception 'Dominio invertido' using errcode='22023'; end if;
   end if;
 end loop;
 foreach k in array array['ordered_pairs','strict_ordered_pairs','unique_by'] loop
   if not (p_schema ? k) then continue; end if;
   if jsonb_typeof(p_schema->k)<>'array' then raise exception 'Relación de columnas inválida' using errcode='22023'; end if;
   for g in select value from jsonb_array_elements(p_schema->k) loop
     if jsonb_typeof(g)<>'array' then raise exception 'Grupo de columnas inválido' using errcode='22023'; end if;
     if jsonb_array_length(g)=0 or (k in ('ordered_pairs','strict_ordered_pairs') and jsonb_array_length(g)<>2)
       or exists(select 1 from jsonb_array_elements(g) x where jsonb_typeof(x)<>'string' or not(x#>>'{}'=any(names)))
       or jsonb_array_length(g)<>(select count(distinct x) from jsonb_array_elements(g) x)
       or (k in ('ordered_pairs','strict_ordered_pairs') and exists(select 1 from jsonb_array_elements(p_schema->'columns') col
         where g ? (col->>'key') and col->>'type' not in ('decimal','integer'))) then
       raise exception 'Relación de columnas inválida' using errcode='22023';
     end if;
     if k in ('ordered_pairs','strict_ordered_pairs') and
       (select col->>'unit' from jsonb_array_elements(p_schema->'columns') col where col->>'key'=g->>0)
       is distinct from
       (select col->>'unit' from jsonb_array_elements(p_schema->'columns') col where col->>'key'=g->>1) then
       raise exception 'El orden necesita columnas con la misma unidad' using errcode='22023';
     end if;
   end loop;
 end loop;
 for g in select value from jsonb_array_elements(coalesce(p_schema->'strict_ordered_pairs','[]')) loop
   if exists(with recursive edges as (
       select x->>0 as a,x->>1 as b from jsonb_array_elements(
         coalesce(p_schema->'ordered_pairs','[]')||coalesce(p_schema->'strict_ordered_pairs','[]')) x
     ), reachable(node) as (
       select g->>1
       union
       select e.b from reachable r join edges e on e.a=r.node
     ) select 1 from reachable where node=g->>0) then
     raise exception 'El esquema de filas contiene órdenes contradictorios' using errcode='22023';
   end if;
 end loop;
end $schema$;

create or replace function public.spec_rows_validate_internal_v1(p_schema jsonb,p_value jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $rows$
#variable_conflict use_column
declare r jsonb; c jsonb; v jsonb; cells jsonb; result_rows jsonb:='[]'; ids text[]:='{}';
  keys text[]; k text; n numeric; lo numeric; hi numeric; g jsonb; old_row jsonb;
begin
 perform public.spec_rows_schema_validate_internal_v1(p_schema);
 if jsonb_typeof(p_value) is distinct from 'object' or p_value->'schema_version' is distinct from p_schema->'version'
   or jsonb_typeof(p_value->'rows') is distinct from 'array' then
   raise exception 'Configuraciones inválidas' using errcode='23514';
 end if;
 if jsonb_array_length(p_value->'rows')=0 or exists(select 1 from jsonb_object_keys(p_value) k where k not in ('schema_version','rows')) then
   raise exception 'Configuraciones sin filas válidas' using errcode='23514';
 end if;
 select array_agg(x->>'key') into keys from jsonb_array_elements(p_schema->'columns') x;
 for r in select value from jsonb_array_elements(p_value->'rows') loop
   if jsonb_typeof(r) is distinct from 'object' then raise exception 'Fila inválida' using errcode='23514'; end if;
   if jsonb_typeof(r->'id') is distinct from 'string' or (r->>'id') !~ '^[A-Za-z0-9_-]{1,80}$'
     or (r->>'id') ~ '[[:space:]]' or r->>'id'=any(ids)
     or jsonb_typeof(r->'values') is distinct from 'object' or r->'values'='{}'::jsonb
     or jsonb_typeof(r->'sources') is distinct from 'array'
     or exists(select 1 from jsonb_object_keys(r) k where k not in ('id','values','sources')) then
     raise exception 'Cada fila necesita identidad y datos propios' using errcode='23514';
   end if;
   ids:=array_append(ids,r->>'id');
   if exists(select 1 from jsonb_object_keys(r->'values') k where not(k=any(keys))) then
     raise exception 'La fila contiene un campo ajeno' using errcode='23514';
   end if;
   if exists(select 1 from jsonb_array_elements(r->'sources') s
       where jsonb_typeof(s)<>'string' or not public.spec_source_url_valid_internal_v1(s#>>'{}'))
     or jsonb_array_length(r->'sources')<>(select count(distinct s) from jsonb_array_elements(r->'sources') s) then
     raise exception 'Fuente de fila inválida o duplicada' using errcode='23514';
   end if;
   cells:=r->'values';
   for c in select value from jsonb_array_elements(p_schema->'columns') loop
     k:=c->>'key';
     if not(cells ? k) then continue; end if;
     v:=cells->k;
     if c->>'type'='boolean' then
       if jsonb_typeof(v)<>'boolean' then raise exception 'Booleano de fila inválido: %',k using errcode='23514'; end if;
       continue;
     end if;
     if jsonb_typeof(v)<>'string' or btrim(v#>>'{}')='' then
       raise exception 'Celda de fila inválida: %',k using errcode='23514';
     end if;
     if c->>'type' in ('decimal','integer') then
       -- Numeric JSON is rejected: a browser may already have rounded it.
       if (v#>>'{}') !~ '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
         or (v#>>'{}') ~ '[[:space:]]' then
         raise exception 'Formato decimal de fila inválido: %',k using errcode='23514';
       end if;
       n:=public.spec_rule_number_internal_v1(v);
       if n is null or (c->>'type'='integer' and trunc(n)<>n) then
         raise exception 'Número exacto de fila inválido: %',k using errcode='23514';
       end if;
       lo:=public.spec_rule_number_internal_v1(c->'validation'->'min');
       hi:=public.spec_rule_number_internal_v1(c->'validation'->'max');
       if (c->'validation'->'positive'='true'::jsonb and n<=0) or n<lo or n>hi then
         raise exception 'Celda fuera de dominio: %',k using errcode='23514';
       end if;
       cells:=jsonb_set(cells,array[k],to_jsonb(trim_scale(n)::text));
     elsif c->>'type'='url' and not public.spec_source_url_valid_internal_v1(v#>>'{}') then
       raise exception 'URL de fila inválida: %',k using errcode='23514';
     elsif c->>'type'='token' and jsonb_array_length(coalesce(c->'allowed_values','[]'))>0
       and not(c->'allowed_values' @> jsonb_build_array(v)) then
       raise exception 'Opción de fila desconocida: %',k using errcode='23514';
     end if;
   end loop;
   for g in select value from jsonb_array_elements(coalesce(p_schema->'ordered_pairs','[]')) loop
     lo:=public.spec_rule_number_internal_v1(cells->(g->>0));
     hi:=public.spec_rule_number_internal_v1(cells->(g->>1));
     if lo>hi then raise exception 'Límite inferior de fila supera el superior' using errcode='23514'; end if;
   end loop;
   for g in select value from jsonb_array_elements(coalesce(p_schema->'strict_ordered_pairs','[]')) loop
     lo:=public.spec_rule_number_internal_v1(cells->(g->>0));
     hi:=public.spec_rule_number_internal_v1(cells->(g->>1));
     if lo>=hi then raise exception 'La primera cota de fila debe ser menor que la segunda' using errcode='23514'; end if;
   end loop;
   for g in select value from jsonb_array_elements(coalesce(p_schema->'unique_by','[]')) loop
     if exists(select 1 from jsonb_array_elements_text(g) k where not(cells ? k)) then continue; end if;
     for old_row in select value from jsonb_array_elements(result_rows) loop
       if not exists(select 1 from jsonb_array_elements_text(g) k where old_row->'values'->k is distinct from cells->k) then
         raise exception 'Dos filas repiten posición o identidad' using errcode='23514';
       end if;
     end loop;
   end loop;
   result_rows:=result_rows||jsonb_build_array(jsonb_set(r,'{values}',cells));
 end loop;
 return jsonb_build_object('schema_version',p_schema->'version','rows',result_rows);
end $rows$;

-- Pure SELECT read-back: body, owner, ACL, mode and exact return behavior.
with expected as (select value w from jsonb_array_elements('[{"acl": "{postgres=X/postgres,service_role=X/postgres}", "md5": "c21cb764086b89a50c5580ad72c0c970", "settings": ["search_path=pg_catalog, public, pg_temp"], "signature": "spec_rows_schema_validate_internal_v1(jsonb)", "owner_name": "postgres", "volatility": "i", "security_definer": false, "before_md5": "e4147389be641a0c61e0f625c676e39b"}, {"acl": "{postgres=X/postgres,service_role=X/postgres}", "md5": "a7e629a22356148871253ad48ef25b3f", "settings": ["search_path=pg_catalog, public, pg_temp"], "signature": "spec_rows_validate_internal_v1(jsonb,jsonb)", "owner_name": "postgres", "volatility": "i", "security_definer": false, "before_md5": "79623b3e97219d95b035aa0705be7757"}]'::jsonb)), checked as (
 select w,p.oid,md5(pg_get_functiondef(p.oid)) body_md5,pg_get_userbyid(p.proowner) owner_name,
 p.proacl::text acl,p.prosecdef security_definer,p.provolatile::text volatility,
 to_jsonb(p.proconfig) settings from expected left join pg_proc p
 on p.oid=to_regprocedure('public.'||(w->>'signature')))
select 1/(case when count(*)=2 and bool_and(oid is not null and body_md5=w->>'md5'
 and owner_name=w->>'owner_name' and acl=w->>'acl'
 and security_definer=(w->>'security_definer')::boolean and volatility=w->>'volatility'
 and settings=w->'settings') then 1 else 0 end) as exact_strict_row_functions from checked;
with checked as materialized (select public.spec_rows_schema_validate_internal_v1(
 validation_rules->'rows_schema') as result from public.spec_definitions
 where validation_rules ? 'rows_schema')
select count(*) as existing_row_schemas_validated,
 count(result) as nonnull_void_results from checked;
select 1/(case when public.spec_rows_validate_internal_v1('{"version": 2, "columns": [{"key": "inner", "label": "Diámetro interior", "type": "decimal", "unit": "mm", "required": true, "validation": {"positive": true}}, {"key": "outer", "label": "Diámetro exterior", "type": "decimal", "unit": "mm", "required": true, "validation": {"positive": true}}, {"key": "minimum", "label": "Mínimo", "type": "decimal", "unit": "bar"}, {"key": "maximum", "label": "Máximo", "type": "decimal", "unit": "bar"}, {"key": "name", "label": "Modelo", "type": "text"}, {"key": "middle", "label": "Cota intermedia", "type": "decimal", "unit": "mm"}], "strict_ordered_pairs": [["inner", "outer"]], "ordered_pairs": [["minimum", "maximum"]]}'::jsonb,
 '{"schema_version": 2, "rows": [{"id": "readback-body", "values": {"inner": "30", "outer": "41.8"}, "sources": []}]}'::jsonb)='{"schema_version": 2, "rows": [{"id": "readback-body", "values": {"inner": "30", "outer": "41.8"}, "sources": []}]}'::jsonb then 1 else 0 end) as strict_body_roundtrip;
select 1/(case when b.fingerprint=a.fingerprint then 1 else 0 end) as unchanged_catalog_and_products
from strict_row_before b cross join (select jsonb_build_object(
 'definitions',(select md5(coalesce(jsonb_agg(to_jsonb(d) order by d.id),'[]')::text) from public.spec_definitions d),
 'templates',(select md5(coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]')::text) from public.spec_templates t),
 'fields',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_template_fields f),
 'facts',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f),
 'references',(select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]')::text) from public.product_spec_references r),
 'products',(select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p)) as fingerprint
) a;
commit;
