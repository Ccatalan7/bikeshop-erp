-- Typed, versioned observations which retain each configuration's cells and
-- sources. This adds storage, not catalogue facts, assignments or OEM claims.
begin;
do $preimages$
declare g record; actual text;
begin
 for g in select * from (values
  ('get_product_spec_typed_configurations_v1(uuid[])', null::text, 'cdfe087a7aefbfcd4f9d7c1573f1041d'),
  ('get_public_product_technical_specs(uuid,uuid)', '6a4f8d71823c385d164096635af3dc00', '39a483344a232591c125a6704a542bc4'),
  ('mirror_facts_into_product_specs_internal_v1()', '0441072aa7fee0cf927b9e09815423e3', '317d1258c4d0b662cf2b78525238f2c4'),
  ('save_product_spec_facts_v1(uuid,uuid[],jsonb)', 'c7ae43770592d0ae1a9bcf1ca83a9735', 'b108fef679ba1ecb6768b07261dcde52'),
  ('spec_fact_value_shape_internal_v1()', 'dc69d3fed8417126f803619c5df5241c', '7d1f271a2e0bd0d27832a60ea679b0fc'),
  ('spec_payload_display_internal_v1(jsonb)', '6915ca93061a09dba339aa1e0e3ea602', '4b968349fa25437f1c931ec50378f452'),
  ('spec_product_payload_internal_v1(uuid)', 'd65a4cd1fff1414b8e1ae027ea8dbd10', 'a353807af49f812d0b349fbc6f112c4c'),
  ('spec_rows_definition_guard_internal_v1()', null::text, '80993f8ada4395792512f3f783f71abe'),
  ('spec_rows_display_internal_v1(jsonb,jsonb)', null::text, 'd9d008b84a3e9c69cc44f6a5d2fa2300'),
  ('spec_rows_fact_guard_internal_v1()', null::text, '4b5cd3700daeb26f34b18ecb0a5ad439'),
  ('spec_rows_reference_guard_internal_v1()', null::text, '69af5b011d214f3b0009a33e0685a1c9'),
  ('spec_rows_schema_validate_internal_v1(jsonb)', null::text, 'e4147389be641a0c61e0f625c676e39b'),
  ('spec_rows_validate_internal_v1(jsonb,jsonb)', null::text, '79623b3e97219d95b035aa0705be7757'),
  ('spec_source_url_valid_internal_v1(text)', null::text, '562a31f106b7286b3c8347499c56929d'),
  ('spec_unassigned_facts_internal_v1(uuid,uuid)', '09bb7db18ed3db2f0df093f82b20ed9c', '3bf820b8dc28859670c5d0fa5e11f89e'),
  ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)', '1b9760ba2076900cb68b9afb627c5173', '76a3e46dd75f5a3c444bbf3755ab0bc6'),
  ('spec_write_payload_internal_v2(uuid,uuid,jsonb,text)', '8d1cd17f62155def6cd528baf82a4817', '4000850abcb96fe223f1df53584eadfb')
 ) checks(signature,before_md5,after_md5) loop
   actual:=case when to_regprocedure('public.'||g.signature) is null then null
     else md5(pg_get_functiondef(to_regprocedure('public.'||g.signature))) end;
   if not (actual is not distinct from g.before_md5 or actual is not distinct from g.after_md5) then
     raise exception 'Structured rows preimage drift: %',g.signature using errcode='55000';
   end if;
 end loop;
end $preimages$;

alter table public.spec_facts add column if not exists value_json jsonb;
alter table public.spec_facts drop constraint if exists spec_facts_one_scalar;
alter table public.spec_facts add constraint spec_facts_one_scalar
 check(num_nonnulls(value_number,value_boolean,value_text,value_json)<=1);

create or replace function public.spec_source_url_valid_internal_v1(p_source text)
returns boolean language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $urlfn$
declare v_match text[];
begin
 if p_source is null or p_source ~ '[[:space:]]' then return false; end if;
 v_match:=regexp_match(p_source,$url$^https?://([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*)(?::([0-9]{1,5}))?([/?#][A-Za-z0-9._~!$&'()*+,;=:@/?%#-]*)?$$url$);
 return v_match is not null
   and (v_match[2] is null or v_match[2]::integer between 1 and 65535)
   and regexp_replace(p_source,'%[0-9A-Fa-f]{2}','','g') not like '%\%%' escape '\';
end $urlfn$;

create or replace function public.spec_rows_schema_validate_internal_v1(p_schema jsonb)
returns void language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $schema$
#variable_conflict use_column
declare c jsonb; g jsonb; k text; names text[]:='{}'; v_min numeric; v_max numeric;
begin
 if jsonb_typeof(p_schema) is distinct from 'object' or p_schema->'version' is distinct from '1'::jsonb
   or jsonb_typeof(p_schema->'columns') is distinct from 'array' then
   raise exception 'Esquema de filas no disponible' using errcode='22023';
 end if;
 if jsonb_array_length(p_schema->'columns')=0 or exists(select 1 from jsonb_object_keys(p_schema) k
   where k not in ('version','columns','ordered_pairs','unique_by')) then
   raise exception 'Esquema de filas inválido' using errcode='22023';
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
 foreach k in array array['ordered_pairs','unique_by'] loop
   if not (p_schema ? k) then continue; end if;
   if jsonb_typeof(p_schema->k)<>'array' then raise exception 'Relación de columnas inválida' using errcode='22023'; end if;
   for g in select value from jsonb_array_elements(p_schema->k) loop
     if jsonb_typeof(g)<>'array' then raise exception 'Grupo de columnas inválido' using errcode='22023'; end if;
     if jsonb_array_length(g)=0 or (k='ordered_pairs' and jsonb_array_length(g)<>2)
       or exists(select 1 from jsonb_array_elements(g) x where jsonb_typeof(x)<>'string' or not(x#>>'{}'=any(names)))
       or jsonb_array_length(g)<>(select count(distinct x) from jsonb_array_elements(g) x)
       or (k='ordered_pairs' and exists(select 1 from jsonb_array_elements(p_schema->'columns') col
         where g ? (col->>'key') and col->>'type' not in ('decimal','integer'))) then
       raise exception 'Relación de columnas inválida' using errcode='22023';
     end if;
   end loop;
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

create or replace function public.spec_rows_display_internal_v1(p_schema jsonb,p_value jsonb)
returns text language sql immutable set search_path=pg_catalog,public,pg_temp as $display$
 select string_agg(line,'; ' order by rn) from (
   select rn,string_agg((c->>'label')||': '||case when c->>'type'='boolean'
       then case r->'values'->(c->>'key') when 'true'::jsonb then 'Sí' else 'No' end
       else r->'values'->>(c->>'key') end||coalesce(' '||(c->>'unit'),''),' · ' order by cn) line
   from jsonb_array_elements(p_value->'rows') with ordinality rr(r,rn)
   cross join jsonb_array_elements(p_schema->'columns') with ordinality cc(c,cn)
   where r->'values' ? (c->>'key') group by rn
 ) lines
$display$;

create or replace function public.spec_rows_definition_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $definition$
begin
 if tg_op='DELETE' then
   if old.validation_rules ? 'rows_schema' and
     (exists(select 1 from public.spec_facts where spec_definition_id=old.id)
      or exists(select 1 from public.product_spec_references where fact_values ? old.id::text)) then
     raise exception 'Conserva el esquema de las configuraciones documentadas' using errcode='23514';
   end if;
   return old;
 end if;
 if new.validation_rules ? 'rows_schema' then
   if new.data_type<>'json' then raise exception 'Filas requieren tipo estructurado' using errcode='23514'; end if;
   perform public.spec_rows_schema_validate_internal_v1(new.validation_rules->'rows_schema');
 end if;
 if tg_op='UPDATE' and (old.validation_rules ? 'rows_schema' or new.validation_rules ? 'rows_schema')
   and (old.validation_rules->'rows_schema' is distinct from new.validation_rules->'rows_schema' or old.data_type<>new.data_type)
   and (exists(select 1 from public.spec_facts where spec_definition_id=old.id)
     or exists(select 1 from public.product_spec_references where fact_values ? old.id::text)) then
   raise exception 'Una definición con filas guardadas requiere migración explícita; conserva su esquema anterior' using errcode='23514';
 end if;
 return new;
end $definition$;
drop trigger if exists spec_rows_definition_guard on public.spec_definitions;
create trigger spec_rows_definition_guard before insert or update or delete on public.spec_definitions
 for each row execute function public.spec_rows_definition_guard_internal_v1();

create or replace function public.spec_rows_fact_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $fact$
declare d public.spec_definitions%rowtype;
begin
 select * into strict d from public.spec_definitions where id=new.spec_definition_id for share;
 if d.data_type='json' and d.validation_rules ? 'rows_schema' then
   if num_nonnulls(new.value_number,new.value_boolean,new.value_text)<>0 then
     raise exception 'Una configuración no puede serializarse como texto o escalar' using errcode='23514';
   end if;
   new.value_json:=public.spec_rows_validate_internal_v1(d.validation_rules->'rows_schema',new.value_json);
 elsif new.value_json is not null then
   raise exception 'El campo no tiene esquema de filas' using errcode='23514';
 end if;
 return new;
end $fact$;
drop trigger if exists spec_rows_fact_guard on public.spec_facts;
create trigger spec_rows_fact_guard before insert or update on public.spec_facts
 for each row execute function public.spec_rows_fact_guard_internal_v1();

-- Command and reader replacements follow. Exact preimage guards are generated
-- from the reviewed, currently deployed definitions before this is applied.

create or replace function public.spec_rows_reference_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $reference$
declare e record; d public.spec_definitions%rowtype;
begin
 for e in select * from jsonb_each(new.fact_values) loop
   select * into d from public.spec_definitions where id::text=e.key for share;
   if d.data_type='json' and d.validation_rules ? 'rows_schema' then
     if jsonb_typeof(e.value) is distinct from 'object'
       or exists(select 1 from jsonb_object_keys(e.value) k where k<>'rows') then
       raise exception 'Una referencia de filas no puede incluir otro escalar' using errcode='23514';
     end if;
     new.fact_values:=jsonb_set(new.fact_values,array[e.key],jsonb_build_object('rows',
       public.spec_rows_validate_internal_v1(d.validation_rules->'rows_schema',e.value->'rows')));
     if exists(select 1 from jsonb_array_elements(new.fact_values->e.key->'rows'->'rows') r
       cross join jsonb_array_elements(r->'sources') s where not(new.sources @> jsonb_build_array(s))) then
       raise exception 'La fuente de una configuración debe pertenecer a la referencia' using errcode='23514';
     end if;
   elsif e.value ? 'rows' then
     raise exception 'La referencia declara filas sin esquema' using errcode='23514';
   end if;
 end loop;
 return new;
end $reference$;
drop trigger if exists spec_rows_reference_guard on public.product_spec_references;
create trigger spec_rows_reference_guard before insert or update on public.product_spec_references
 for each row execute function public.spec_rows_reference_guard_internal_v1();

-- Explicitly typed transport for relation evaluators. Existing display APIs
-- retain their scalar JSON contract; this one reads numeric::text at the
-- database boundary and preserves sets/rows as such, never choosing a member.
create or replace function public.get_product_spec_typed_configurations_v1(p_product_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $typed$
declare v_tenant uuid:=public.user_tenant_id(); v_result jsonb;
begin
 if v_tenant is null or auth.uid() is null then raise exception 'No autenticado' using errcode='42501'; end if;
 if p_product_ids is null or cardinality(p_product_ids)>200 then
   raise exception 'Lee configuraciones en bloques de hasta 200 productos' using errcode='22023';
 end if;
 with scoped as materialized (
   select p.id,p.tenant_id,p.spec_revision,b.template_id,b.binding_source,t.contract_version
   from public.products p join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
   left join public.spec_templates t on t.id=b.template_id
   where p.id=any(p_product_ids) and p.tenant_id=v_tenant
 ), payloads as materialized (
   select p.*,public.spec_template_product_payload_internal_v1(p.id,p.template_id,false) vals from scoped p
 ), configurations as (
   select p.*,coalesce((select jsonb_object_agg(d.key,jsonb_build_object(
     'definition_id',d.id,'value_type',case d.data_type
       when 'number' then 'decimal' when 'boolean' then 'boolean'
       when 'multi_select' then 'token_set' when 'json' then 'rows' else 'token' end,
     'value',case d.data_type when 'number' then to_jsonb((e.value->>'number')::numeric::text)
       else public.spec_payload_display_internal_v1(jsonb_build_object(e.key,e.value))->d.key end))
     from jsonb_each(p.vals) e join public.spec_definitions d on d.id::text=e.key
     where d.data_type<>'json' or d.validation_rules ? 'rows_schema'),'{}'::jsonb) fields
   from payloads p
 ) select coalesce(jsonb_object_agg(id,jsonb_build_object('schema_version',2,
     'product_id',id,'template_id',template_id,'binding_source',binding_source,
     'revision',spec_revision,'contract_version',contract_version,'fields',fields)),'{}'::jsonb)
   into v_result from configurations;
 return v_result;
end $typed$;
revoke all on function public.get_product_spec_typed_configurations_v1(uuid[]) from public,anon;
grant execute on function public.get_product_spec_typed_configurations_v1(uuid[]) to authenticated;

CREATE OR REPLACE FUNCTION public.spec_unassigned_facts_internal_v1(p_product_id uuid, p_template_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
 with payload as materialized (
   select public.spec_product_payload_internal_v1(p_product_id) values
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'fact_id',f.id,'definition_id',d.id,'key',d.key,'label',d.label,
   'value',public.spec_payload_display_internal_v1(jsonb_build_object(d.id::text,payload.values->d.id::text))->d.key,
   'rows_schema',d.validation_rules->'rows_schema',
   'source',f.source,'confirmed',f.confirmed,'updated_at',f.updated_at,
   'readings',(select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) from public.spec_fact_readings r where r.fact_id=f.id and r.tenant_id=f.tenant_id)
 ) order by d.key),'[]'::jsonb)
 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id cross join payload
 where f.subject_type='product' and f.subject_id=p_product_id and f.subject_scope is null
   and f.tenant_id=(select tenant_id from public.products where id=p_product_id)
   and not exists(select 1 from public.spec_template_fields tf
     where tf.template_id=p_template_id and tf.spec_definition_id=f.spec_definition_id)
$function$
;

-- ROW_COMMANDS_BEGIN
CREATE OR REPLACE FUNCTION public.spec_payload_display_internal_v1(p_values jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_object_agg(d.key,
    case d.data_type when 'number' then e.value->'number'
      when 'boolean' then e.value->'boolean'
      when 'single_select' then to_jsonb((select v.label from public.spec_definition_values v
        where v.spec_definition_id = d.id and v.id::text = e.value->'value_ids'->>0))
      when 'multi_select' then coalesce((select jsonb_agg(v.label order by a.ordinality)
        from jsonb_array_elements_text(e.value->'value_ids') with ordinality a(id, ordinality)
        join public.spec_definition_values v on v.id::text = a.id and v.spec_definition_id = d.id), '[]'::jsonb)
      when 'json' then case when d.validation_rules ? 'rows_schema' then e.value->'rows' else e.value->'text' end
      else e.value->'text' end), '{}'::jsonb)
  from jsonb_each(p_values) e join public.spec_definitions d on d.id::text = e.key
$function$;

CREATE OR REPLACE FUNCTION public.spec_product_payload_internal_v1(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_object_agg(f.spec_definition_id::text,
    case d.data_type when 'number' then jsonb_build_object('number',f.value_number)
      when 'boolean' then jsonb_build_object('boolean',f.value_boolean)
      when 'single_select' then jsonb_build_object('value_ids',coalesce(v.ids,'[]'::jsonb))
      when 'multi_select' then jsonb_build_object('value_ids',coalesce(v.ids,'[]'::jsonb))
      when 'json' then case when d.validation_rules ? 'rows_schema' then jsonb_build_object('rows',f.value_json) else jsonb_build_object('text',f.value_text) end
      else jsonb_build_object('text',f.value_text) end), '{}'::jsonb)
  from public.spec_facts f join public.spec_definitions d on d.id = f.spec_definition_id
  left join lateral (select jsonb_agg(fv.value_id order by fv.position) ids
    from public.spec_fact_values fv where fv.fact_id = f.id) v on true
  where f.subject_type = 'product' and f.subject_id = p_product_id
    and f.subject_scope is null
    and f.tenant_id=(select tenant_id from public.products where id=p_product_id)
$function$;

CREATE OR REPLACE FUNCTION public.spec_write_payload_internal_v2(p_product_id uuid, p_template_id uuid, p_values jsonb, p_reference_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_tenant uuid := public.user_tenant_id(); v_entry record; v_def public.spec_definitions%rowtype;
  v_fact uuid; v_ids uuid[]; v_count integer := 0; v_reference jsonb := '{}'; v_payload jsonb; v_old jsonb; v_contract jsonb;
begin
  if v_tenant is null or auth.uid() is null or not exists (
    select 1 from public.products where id = p_product_id and tenant_id = v_tenant) then
    raise exception 'Producto no disponible para este tenant' using errcode = '42501';
  end if;
  select fact_values into v_reference from public.product_spec_references where id = p_reference_id;
  -- Explicitly submitted facts are independent observations. The client omits
  -- automatic values; reference validation still rejects conflicting facts.
  -- Reattribution to catalog would erase the observation on reload/detach.
  v_reference := coalesce(v_reference,'{}'::jsonb) - array(select jsonb_object_keys(p_values));
  v_payload := v_reference || p_values;
  if jsonb_typeof(v_payload) <> 'object' then raise exception 'Invalid fact payload' using errcode = '22023'; end if;
  -- No arbitrary definition list from the client, and no silently dropped IDs.
  if exists (select 1 from jsonb_object_keys(v_payload) k where not exists (
    select 1 from public.spec_template_fields f where f.template_id = p_template_id and f.spec_definition_id::text = k)) then
    raise exception 'La respuesta no pertenece a esta plantilla' using errcode = '23514';
  end if;
  select form_contract into v_contract from public.spec_templates where id=p_template_id;
  v_old:=public.spec_product_payload_internal_v1(p_product_id);
  -- Old clients may round-trip identical retired answers; omission preserves
  -- them too. Changed/new retired values need a separate reviewed repair.
  for v_entry in select e.* from jsonb_each(v_payload) e
    join public.spec_definitions d on d.id::text=e.key
    where v_contract->'roles'->>d.key='legacy' loop
    if v_old->v_entry.key is distinct from v_entry.value then
      raise exception 'El campo retirado se conserva como legacy y no admite cambios: %',v_entry.key using errcode='23514';
    end if;
    v_payload:=v_payload-v_entry.key;
  end loop;
  delete from public.spec_facts f using public.spec_template_fields tf
    where tf.template_id = p_template_id and tf.spec_definition_id = f.spec_definition_id
    and f.tenant_id = v_tenant and f.subject_type = 'product' and f.subject_id = p_product_id
    and f.subject_scope is null and not (v_payload ? f.spec_definition_id::text)
    and coalesce(v_contract->'roles'->>(select key from public.spec_definitions where id=f.spec_definition_id),'primary')<>'legacy';
  for v_entry in select * from jsonb_each(v_payload) loop
    select * into strict v_def from public.spec_definitions where id::text = v_entry.key;
    v_ids := null;
    if v_def.data_type='json' and v_def.validation_rules ? 'rows_schema' then
      if jsonb_typeof(v_entry.value) is distinct from 'object' or exists(
        select 1 from jsonb_object_keys(v_entry.value) k where k<>'rows') then
        raise exception 'La configuración requiere un payload de filas' using errcode='23514';
      end if;
      v_entry.value:=jsonb_build_object('rows',public.spec_rows_validate_internal_v1(
        v_def.validation_rules->'rows_schema',v_entry.value->'rows'));
    end if;
    if v_def.data_type in ('single_select','multi_select') then
      if jsonb_typeof(v_entry.value->'value_ids') is distinct from 'array'
        or jsonb_array_length(v_entry.value->'value_ids') = 0
        or (v_def.data_type = 'single_select' and jsonb_array_length(v_entry.value->'value_ids') <> 1) then
        raise exception 'Invalid option cardinality for %', v_def.key using errcode = '23514';
      end if;
      v_ids := array(select jsonb_array_elements_text(v_entry.value->'value_ids')::uuid);
      if cardinality(v_ids) <> (select count(distinct v.id) from public.spec_definition_values v
        where v.spec_definition_id = v_def.id and v.id = any(v_ids)) then
        raise exception 'Unknown, duplicate or foreign option for %', v_def.key using errcode = '23514';
      end if;
    elsif v_def.data_type = 'number' and (jsonb_typeof(v_entry.value->'number') not in ('number','string') or public.spec_rule_number_internal_v1(v_entry.value->'number') is null) then
      raise exception 'Expected numeric fact for %', v_def.key using errcode = '23514';
    elsif v_def.data_type = 'boolean' and jsonb_typeof(v_entry.value->'boolean') is distinct from 'boolean' then
      raise exception 'Expected boolean fact for %', v_def.key using errcode = '23514';
    elsif not (v_def.data_type='json' and v_def.validation_rules ? 'rows_schema')
      and v_def.data_type not in ('number','boolean','single_select','multi_select')
      and jsonb_typeof(v_entry.value->'text') is distinct from 'string' then
      raise exception 'Expected text fact for %', v_def.key using errcode = '23514';
    end if;
    if exists(select 1 from public.spec_facts f where f.subject_type='product' and f.subject_id=p_product_id
      and f.tenant_id=v_tenant and f.subject_scope is null and f.spec_definition_id=v_def.id
      and public.spec_rule_set_internal_v1(public.spec_payload_display_internal_v1(jsonb_build_object(v_entry.key,v_old->v_entry.key))->v_def.key)
        = public.spec_rule_set_internal_v1(public.spec_payload_display_internal_v1(jsonb_build_object(v_entry.key,v_entry.value))->v_def.key)
      and (not (coalesce(v_reference,'{}'::jsonb) ? v_entry.key) or f.source='catalog')
      and (f.source<>'catalog' or coalesce(v_reference,'{}'::jsonb) ? v_entry.key)) then
      v_count := v_count+1;
      continue;
    end if;
    insert into public.spec_facts (tenant_id,subject_type,subject_id,spec_definition_id,
      value_number,value_boolean,value_text,value_json,source,confirmed)
    values (v_tenant,'product',p_product_id,v_def.id,
      case when v_def.data_type = 'number' then (v_entry.value->>'number')::numeric end,
      case when v_def.data_type = 'boolean' then (v_entry.value->>'boolean')::boolean end,
      case when v_def.data_type not in ('number','boolean','single_select','multi_select') and not(v_def.validation_rules ? 'rows_schema') then v_entry.value->>'text' end,
      case when v_def.data_type='json' and v_def.validation_rules ? 'rows_schema' then v_entry.value->'rows' end,
      case when coalesce(v_reference,'{}'::jsonb) ? v_entry.key then 'catalog' else 'mechanic' end, false)
    on conflict (tenant_id,subject_type,subject_id,spec_definition_id,coalesce(subject_scope,''))
    do update set value_number = excluded.value_number, value_boolean = excluded.value_boolean,
      value_text = excluded.value_text, value_json=excluded.value_json, source = excluded.source, confirmed = excluded.confirmed, updated_at = now()
    returning id into v_fact;
    delete from public.spec_fact_readings where fact_id = v_fact;
    delete from public.spec_fact_values where fact_id = v_fact;
    if v_ids is not null then
      insert into public.spec_fact_values(fact_id,value_id,position)
        select v_fact,id,(ordinality-1)::integer from unnest(v_ids) with ordinality a(id,ordinality);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $function$;

CREATE OR REPLACE FUNCTION public.save_product_spec_facts_v1(p_product_id uuid, p_definition_ids uuid[], p_values jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_tenant uuid := public.user_tenant_id();
  v_definicion uuid;
  v_tipo text;
  v_entrada jsonb;
  v_fact uuid;
  v_escritos integer := 0;
  v_retired uuid[]; v_old jsonb; v_key text;
begin
  if v_tenant is null or auth.uid() is null then
    raise exception 'sin tenant' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.products
    where id = p_product_id and tenant_id = v_tenant
  ) then
    raise exception 'el producto no pertenece a este tenant' using errcode = '42501';
  end if;

  -- **La misma llave que toma la lectura, y antes de tocar nada.** Vaciar un
  -- criterio es lo primero que hace esta función; sin el candado acá, una
  -- lectura en vuelo podía reinsertar justo el campo que la persona acababa de
  -- vaciar, y el resultado quedaba escrito por el lector aunque la persona
  -- hubiera llegado después.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant::text || ':spec_fact:' || p_product_id::text, 0));

  if jsonb_typeof(p_values) is distinct from 'object' or p_definition_ids is null then
    raise exception 'Invalid specification payload' using errcode = '22023';
  end if;
  if exists(select 1 from unnest(p_definition_ids) d where not exists(
    select 1 from public.spec_definitions sd where sd.id=d and (sd.tenant_id is null or sd.tenant_id=v_tenant)))
    or exists(select 1 from jsonb_object_keys(p_values) k where not k = any(array(select d::text from unnest(p_definition_ids) d))) then
    raise exception 'Unknown or foreign specification definition' using errcode = '23514';
  end if;
  if exists(select 1 from unnest(p_definition_ids) d where not exists(
      select 1 from public.product_spec_bindings_internal_v1 b
      join public.spec_template_fields tf on tf.template_id=b.template_id
      where b.product_id=p_product_id and tf.spec_definition_id=d)) then
    raise exception 'La respuesta no pertenece a esta plantilla' using errcode = '23514';
  end if;
  select coalesce(array_agg(d.id),'{}'::uuid[]) into v_retired
  from public.product_spec_bindings_internal_v1 b join public.spec_templates t on t.id=b.template_id
  join public.spec_template_fields f on f.template_id=t.id join public.spec_definitions d on d.id=f.spec_definition_id
  where b.product_id=p_product_id and d.id=any(p_definition_ids) and t.form_contract->'roles'->>d.key='legacy';
  v_old:=public.spec_product_payload_internal_v1(p_product_id);
  foreach v_definicion in array v_retired loop
    if not (p_values ? v_definicion::text) then continue; end if;
    select key,data_type into v_key,v_tipo from public.spec_definitions where id=v_definicion;
    v_entrada:=p_values->v_definicion::text;
    if v_tipo in ('single_select','multi_select') then
      v_entrada:=case when v_tipo='single_select' then v_entrada->'labels'->0 else v_entrada->'labels' end;
    else
      v_entrada:=v_entrada->case v_tipo when 'number' then 'number' when 'boolean' then 'boolean' else 'text' end;
    end if;
    if not(v_old ? v_definicion::text) or public.spec_payload_display_internal_v1(jsonb_build_object(v_definicion::text,v_old->v_definicion::text))->v_key is distinct from v_entrada then
      raise exception 'El campo retirado se conserva como legacy y no admite cambios: %',v_key using errcode='23514';
    end if;
    p_values:=p_values-v_definicion::text;
  end loop;
  p_definition_ids:=array(select d from unnest(p_definition_ids) d where not d=any(v_retired));
  if exists(select 1 from public.spec_definitions where id=any(p_definition_ids)
    and data_type='json' and validation_rules ? 'rows_schema') then
    raise exception 'Esta ficha requiere el editor de configuraciones; el guardado antiguo no puede modificar sus filas' using errcode='23514';
  end if;
  for v_definicion in select unnest(p_definition_ids) loop
    v_entrada := p_values->v_definicion::text;
    continue when v_entrada is null;
    select data_type into strict v_tipo from public.spec_definitions where id=v_definicion;
    if v_tipo in ('single_select','multi_select') then
      if jsonb_typeof(v_entrada->'labels') is distinct from 'array'
        or jsonb_array_length(v_entrada->'labels')=0
        or (v_tipo='single_select' and jsonb_array_length(v_entrada->'labels')<>1) then
        raise exception 'Invalid option cardinality' using errcode = '23514';
      end if;
      if (select count(distinct v.id) from jsonb_array_elements_text(v_entrada->'labels') a(label)
        join public.spec_definition_values v on v.spec_definition_id=v_definicion and v.label=a.label)
        <> jsonb_array_length(v_entrada->'labels') then
        raise exception 'Unknown or duplicate specification option' using errcode = '23514';
      end if;
    elsif v_tipo='number' and jsonb_typeof(v_entrada->'number') is distinct from 'number' then
      raise exception 'Expected numeric specification value' using errcode = '23514';
    elsif v_tipo='boolean' and jsonb_typeof(v_entrada->'boolean') is distinct from 'boolean' then
      raise exception 'Expected boolean specification value' using errcode = '23514';
    end if;
  end loop;

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
      -- **La persona gana de verdad.** Sin esto, guardar encima de una lectura
      -- del nombre dejaba el valor del mecanico con `source = 'name_reading'`
      -- y con el recibo de una cita que ya no lo sostiene: procedencia y
      -- respaldo falsos, y ademas el hecho caducaba solo al cambiar el nombre
      -- del producto, borrando en silencio lo que una persona escribio.
      source = excluded.source,
      confirmed = excluded.confirmed,
      updated_at = now()
    returning id into v_fact;

    -- El recibo se retira: ya no hay ninguna lectura que respaldar.
    delete from public.spec_fact_readings where fact_id = v_fact;
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

  perform public.spec_validate_product_internal_v1(p_product_id);
  return v_escritos;
end;
$function$;

CREATE OR REPLACE FUNCTION public.spec_validate_draft_internal_v1(p_template_id uuid, p_values jsonb, p_reference_id text DEFAULT NULL::text, p_brand text DEFAULT ''::text, p_model text DEFAULT ''::text, p_manufacturer_sku text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_issues jsonb := '[]'::jsonb; v_field record; v_value jsonb;
  v_rule jsonb; v_allowed text[]; v_next text[]; v_condition boolean;
  v_message text; v_number numeric; v_key text; v_contract jsonb;
  v_reference public.product_spec_references%rowtype; v_entry record; v_pair text[];
begin
  select form_contract into v_contract from public.spec_templates where id = p_template_id;
  if v_contract is null then raise exception 'Unknown specification template' using errcode = '22023'; end if;
  -- Retired/out-of-template values remain history; neither predicates nor
  -- measurement pair checks may use them to judge the current draft.
  select coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) into p_values
  from jsonb_each(p_values) e where exists(
    select 1 from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
    where f.template_id=p_template_id and d.key=e.key
      and coalesce(v_contract->'roles'->>d.key,'primary')<>'legacy');
  if p_reference_id is not null then
    select * into v_reference from public.product_spec_references where id = p_reference_id;
    if not found or lower(btrim(v_reference.brand)) <> lower(btrim(coalesce(p_brand,'')))
      or lower(btrim(v_reference.model)) <> lower(btrim(coalesce(p_model,'')))
      or (v_reference.manufacturer_sku is not null and lower(btrim(v_reference.manufacturer_sku)) <> lower(btrim(coalesce(p_manufacturer_sku,''))))
      or v_reference.technical_family <> (select technical_family from public.spec_templates where id = p_template_id) then
      v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','reference_identity','field','',
        'message','La referencia no corresponde a esta marca, modelo o familia.'));
    end if;
    for v_entry in select * from jsonb_each(public.spec_payload_display_internal_v1(coalesce(v_reference.fact_values,'{}'))) loop
      -- Operator evidence supplements the immutable manufacturer's sources.
      continue when v_entry.key = 'spec_evidence_source';
      if public.spec_rule_known_internal_v1(p_values->v_entry.key)
        and public.spec_rule_set_internal_v1(p_values->v_entry.key) <> public.spec_rule_set_internal_v1(v_entry.value) then
        v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','reference_conflict','field',v_entry.key,
          'message','El valor difiere de la referencia del fabricante.'));
      end if;
    end loop;
  end if;
  for v_field in select d.*, f.visibility_rules, f.constraint_rules from public.spec_template_fields f
    join public.spec_definitions d on d.id = f.spec_definition_id where f.template_id = p_template_id loop
    v_value := p_values->v_field.key;
    continue when not public.spec_rule_known_internal_v1(v_value);
    v_message := null;
    if p_reference_id is not null and v_contract->'roles'->>v_field.key='declaration'
      and v_field.key <> 'spec_evidence_source' and not (coalesce(v_reference.fact_values,'{}'::jsonb) ? v_field.id::text) then
      v_message := 'La referencia elegida no documenta esta declaración manual. Usa sus declaraciones o retira la referencia.';
    end if;
    for v_rule in select value from jsonb_array_elements(coalesce(v_field.visibility_rules,'[]')) loop
      v_condition := public.spec_condition_internal_v1(v_rule,p_values);
      if v_condition is false then
        v_message := 'Revisa los requisitos de este campo o retira el valor.';
      elsif v_condition is null then
        v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','prerequisite_missing','field',v_field.key,
          'message','Falta confirmar los requisitos del campo.','blocking',false));
      end if;
    end loop;
    for v_key in select jsonb_array_elements_text(coalesce(v_contract->'prerequisites'->v_field.key,'[]')) loop
      if not public.spec_rule_known_internal_v1(p_values->v_key) then
        v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','prerequisite_missing','field',v_field.key,
          'message','Falta confirmar ' || v_key || '.','blocking',false));
      end if;
    end loop;
    if v_field.data_type = 'boolean' and jsonb_typeof(v_value) <> 'boolean' then
      v_message := 'El campo requiere Sí, No o Sin confirmar.';
    elsif v_field.data_type = 'number' then
      if public.spec_rule_normalize_internal_v1(v_value) !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$' then
        v_message := 'El campo requiere un número válido.';
      else
        v_number := public.spec_rule_normalize_internal_v1(v_value)::numeric;
        if v_field.validation_rules->>'positive' = 'true' and v_number <= 0 then
          v_message := 'Ingresa un valor mayor que cero.';
        end if;
        if v_field.validation_rules->>'integer' = 'true' and v_number <> trunc(v_number) then
          v_message := 'Ingresa una cantidad entera.';
        end if;
        if v_number < (v_field.validation_rules->>'min')::numeric or
          v_number > (v_field.validation_rules->>'max')::numeric then
          v_message := 'El valor está fuera del rango declarado para este campo.';
        end if;
      end if;
    elsif v_field.data_type='json' and v_field.validation_rules ? 'rows_schema' then
      begin
        perform public.spec_rows_validate_internal_v1(v_field.validation_rules->'rows_schema',v_value);
        if exists(select 1 from jsonb_array_elements(v_value->'rows') r
          cross join jsonb_array_elements(v_field.validation_rules->'rows_schema'->'columns') c
          where c->>'required'='true' and not(r->'values' ? (c->>'key'))) then
          v_issues:=v_issues||jsonb_build_array(jsonb_build_object('code','row_incomplete','field',v_field.key,
            'message',v_field.label||': faltan datos dentro de una configuración.','blocking',false));
        end if;
      exception when check_violation then
        v_message:=sqlerrm;
      end;
    elsif v_field.data_type in ('single_select','multi_select') then
      if (v_field.data_type = 'single_select' and jsonb_typeof(v_value) <> 'string') or
         (v_field.data_type = 'multi_select' and jsonb_typeof(v_value) <> 'array') then
        v_message := 'La cantidad de respuestas no corresponde al campo.';
      elsif not (public.spec_rule_set_internal_v1(v_value) <@
          public.spec_rule_set_internal_v1(v_field.allowed_values)) then
        v_message := 'La respuesta no pertenece a las opciones del campo.';
      end if;
    end if;
    v_allowed := null;
    for v_rule in select value from jsonb_array_elements(coalesce(v_field.constraint_rules,'[]')) loop
      if public.spec_condition_internal_v1(v_rule,p_values) is true then
        if jsonb_typeof(v_rule->'allow') <> 'array' then raise exception 'Invalid option rule' using errcode = '22023'; end if;
        v_next := public.spec_rule_set_internal_v1(v_rule->'allow');
        if v_allowed is null then v_allowed := v_next;
        else v_allowed := array(select unnest(v_allowed) intersect select unnest(v_next)); end if;
      end if;
    end loop;
    if v_allowed is not null and not (public.spec_rule_set_internal_v1(v_value) <@ v_allowed) then
      v_message := 'El valor no corresponde a los requisitos elegidos.';
    end if;
    if v_message is not null then
      v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','field_constraint','field',v_field.key,
        'message',v_field.label || ': ' || v_message));
    end if;
  end loop;
  foreach v_pair slice 1 in array array[
    ['smallest_cog_teeth','largest_cog_teeth'],['tube_width_min_mm','tube_width_max_mm'],
    ['tube_width_min_in','tube_width_max_in'],['bearing_inner_diameter_mm','bearing_outer_diameter_mm']]
  loop
    if jsonb_typeof(p_values->v_pair[1]) = 'number' and jsonb_typeof(p_values->v_pair[2]) = 'number'
      and (p_values->>v_pair[1])::numeric > (p_values->>v_pair[2])::numeric then
      v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','range_order','field',v_pair[2],
        'message','El límite inferior no puede superar el superior.'));
    end if;
  end loop;
  return v_issues;
end $function$;

CREATE OR REPLACE FUNCTION public.mirror_facts_into_product_specs_internal_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fact public.spec_facts%rowtype;
  v_tipo text; v_rules jsonb;
  v_etiquetas text[];
begin
  if tg_op = 'DELETE' then
    if tg_table_name = 'spec_facts' then
      if old.subject_type <> 'product' or old.subject_scope is not null then
        return old;
      end if;
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

  select data_type,validation_rules into v_tipo,v_rules from public.spec_definitions
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
    case when v_tipo = 'multi_select' then to_jsonb(v_etiquetas) when v_tipo='json' then v_fact.value_json end,
    coalesce(
      case when v_tipo='json' and v_rules ? 'rows_schema' then public.spec_rows_display_internal_v1(v_rules->'rows_schema',v_fact.value_json) end,
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
$function$;

CREATE OR REPLACE FUNCTION public.spec_fact_value_shape_internal_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_tipo text;
  v_escalares integer;
begin
  select d.data_type, num_nonnulls(f.value_number, f.value_boolean, f.value_text, f.value_json)
    into v_tipo, v_escalares
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id
  where f.id = new.fact_id;

  if v_tipo not in ('single_select', 'multi_select') then
    raise exception 'spec_fact_values sólo aplica a campos de lista (% es %)',
      new.fact_id, v_tipo using errcode = '22023';
  end if;
  if v_escalares > 0 then
    raise exception 'un hecho de lista no puede llevar además un valor escalar'
      using errcode = '22023';
  end if;
  if v_tipo = 'single_select'
     and (select count(*) from public.spec_fact_values where fact_id = new.fact_id) > 0 then
    raise exception 'un campo de selección única admite un solo valor'
      using errcode = '22023';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_product_technical_specs(p_tenant_id uuid, p_product_id uuid)
 RETURNS TABLE(section_key text, section_sort_order integer, field_sort_order integer, spec_key text, spec_label text, display_value text, unit text, data_type text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  with visible as (
    select p.id,p.brand,p.model,p.manufacturer_sku,p.spec_reference_id,t.id template_id,t.form_contract
    from public.products p
    join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
    join public.spec_templates t on t.id=b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
    where p.id=p_product_id and p.tenant_id=p_tenant_id and coalesce(p.is_active,true)
      and coalesce(p.is_published,false) and coalesce(p.show_on_website,false)
  ), facts as (
    select p.*,public.spec_active_product_values_internal_v1(p.id,p.template_id) vals from visible p
  ), assessed as (select p.*,public.spec_validate_draft_internal_v1(p.template_id,p.vals,p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) issues from facts p
  ), fields as (
    select f.section_key,f.sort_order,d.key,coalesce(p.form_contract->'labels'->>d.key,d.label) label,
      d.unit,d.data_type,d.validation_rules,p.vals->d.key val,min(f.sort_order) over(partition by f.section_key) section_order
    from assessed p join public.spec_template_fields f on f.template_id=p.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
    where coalesce(p.form_contract->'roles'->>d.key,'primary') <> 'legacy'
      and public.spec_rule_known_internal_v1(p.vals->d.key)
      and not exists(select 1 from jsonb_array_elements(p.issues) i where coalesce((i->>'blocking')::boolean,true) and i->>'field' in ('',d.key))
  )
  select f.section_key,dense_rank() over(order by f.section_order,f.section_key)::integer,
    f.sort_order,f.key,f.label,case
      when f.data_type='json' and f.validation_rules ? 'rows_schema' then public.spec_rows_display_internal_v1(f.validation_rules->'rows_schema',f.val)
      when jsonb_typeof(f.val)='array' then (select string_agg(e,', ' order by n) from jsonb_array_elements_text(f.val) with ordinality a(e,n))
      when jsonb_typeof(f.val)='boolean' then case when f.val='true'::jsonb then 'Sí' else 'No' end
      else f.val#>>'{}' end,f.unit,f.data_type
  from fields f order by f.section_order,f.sort_order,f.label
$function$;
-- ROW_COMMANDS_END


revoke all on function public.spec_source_url_valid_internal_v1(text),
 public.spec_rows_schema_validate_internal_v1(jsonb),public.spec_rows_validate_internal_v1(jsonb,jsonb),
 public.spec_rows_display_internal_v1(jsonb,jsonb),public.spec_rows_definition_guard_internal_v1(),
 public.spec_rows_fact_guard_internal_v1(),public.spec_rows_reference_guard_internal_v1()
 from public,anon,authenticated;

comment on column public.spec_facts.value_json is
 'Typed rows with schema_version, stable row identities, paired scalar cells and row sources. Never free-form text or a Cartesian product.';

do $postimages$
declare g record;
begin
 for g in select * from (values
  ('get_product_spec_typed_configurations_v1(uuid[])', null::text, 'cdfe087a7aefbfcd4f9d7c1573f1041d'),  ('get_public_product_technical_specs(uuid,uuid)', '6a4f8d71823c385d164096635af3dc00', '39a483344a232591c125a6704a542bc4'),  ('mirror_facts_into_product_specs_internal_v1()', '0441072aa7fee0cf927b9e09815423e3', '317d1258c4d0b662cf2b78525238f2c4'),  ('save_product_spec_facts_v1(uuid,uuid[],jsonb)', 'c7ae43770592d0ae1a9bcf1ca83a9735', 'b108fef679ba1ecb6768b07261dcde52'),  ('spec_fact_value_shape_internal_v1()', 'dc69d3fed8417126f803619c5df5241c', '7d1f271a2e0bd0d27832a60ea679b0fc'),  ('spec_payload_display_internal_v1(jsonb)', '6915ca93061a09dba339aa1e0e3ea602', '4b968349fa25437f1c931ec50378f452'),  ('spec_product_payload_internal_v1(uuid)', 'd65a4cd1fff1414b8e1ae027ea8dbd10', 'a353807af49f812d0b349fbc6f112c4c'),  ('spec_rows_definition_guard_internal_v1()', null::text, '80993f8ada4395792512f3f783f71abe'),  ('spec_rows_display_internal_v1(jsonb,jsonb)', null::text, 'd9d008b84a3e9c69cc44f6a5d2fa2300'),  ('spec_rows_fact_guard_internal_v1()', null::text, '4b5cd3700daeb26f34b18ecb0a5ad439'),  ('spec_rows_reference_guard_internal_v1()', null::text, '69af5b011d214f3b0009a33e0685a1c9'),  ('spec_rows_schema_validate_internal_v1(jsonb)', null::text, 'e4147389be641a0c61e0f625c676e39b'),  ('spec_rows_validate_internal_v1(jsonb,jsonb)', null::text, '79623b3e97219d95b035aa0705be7757'),  ('spec_source_url_valid_internal_v1(text)', null::text, '562a31f106b7286b3c8347499c56929d'),  ('spec_unassigned_facts_internal_v1(uuid,uuid)', '09bb7db18ed3db2f0df093f82b20ed9c', '3bf820b8dc28859670c5d0fa5e11f89e'),  ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)', '1b9760ba2076900cb68b9afb627c5173', '76a3e46dd75f5a3c444bbf3755ab0bc6'),  ('spec_write_payload_internal_v2(uuid,uuid,jsonb,text)', '8d1cd17f62155def6cd528baf82a4817', '4000850abcb96fe223f1df53584eadfb')
 ) checks(signature,before_md5,after_md5) loop
  if md5(pg_get_functiondef(to_regprocedure('public.'||g.signature))) is distinct from g.after_md5 then
   raise exception 'Structured rows postimage drift: %',g.signature using errcode='55000';
  end if;
 end loop;
end $postimages$;

commit;
