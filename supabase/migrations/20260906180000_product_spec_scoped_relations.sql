-- Scoped manufacturer declarations: row alternatives, never Cartesian lists.
-- No product assignment, fact fill, or reference data is changed here.
begin;
-- Reviewed canonical definitions: fail closed on drift, accept exact replay.
do $guard$ declare r record; actual text; begin
 for r in select * from (values
('spec_condition_internal_v1(jsonb,jsonb)','a5ca43af3ac118c3c5c560d57ba0e7e6','d4a28048452544d76cd7153117e4dcc4'),
('spec_reference_relations_guard_internal_v1()',null::text,'46d959558160f469e0c0c9e95cdedffa'),
('spec_relation_condition_internal_v1(jsonb,jsonb)',null::text,'b63b594f1c1a92e8e268790eecebe9c6'),
('spec_relation_assess_internal_v1(jsonb,jsonb)',null::text,'30e08b04ea3bd6b3faa66ecc7ecf0402'),
('spec_relation_validate_internal_v1(jsonb)',null::text,'3f547847018daeaaa67aba26e125981b'),
('spec_rule_number_internal_v1(jsonb)',null::text,'402beae4c82ab3a7f38304e2a4f89415')
 ) reviewed(signature,before_md5,after_md5) loop
   select md5(pg_get_functiondef(to_regprocedure(r.signature))) into actual;
   if not (actual is not distinct from r.before_md5 or actual is not distinct from r.after_md5) then
     raise exception 'Affected function changed since review: %',r.signature using errcode='55000';
   end if;
 end loop;
end $guard$;


create or replace function public.spec_rule_number_internal_v1(p_value jsonb)
returns numeric language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $$
declare v_text text;
begin
 if jsonb_typeof(p_value) not in ('number','string') or p_value is null then return null; end if;
 v_text:=public.spec_rule_normalize_internal_v1(p_value);
 if v_text !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$' then return null; end if;
 return v_text::numeric;
exception when numeric_value_out_of_range or invalid_text_representation then return null;
end $$;
revoke all on function public.spec_rule_number_internal_v1(jsonb) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.spec_condition_internal_v1(p_rule jsonb, p_values jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_child jsonb; v_result boolean; v_unknown boolean := false;
  v_group text; v_operator text := coalesce(p_rule->>'operator', 'eq');
  v_actual jsonb; v_set text[]; v_expected text[]; v_number numeric; v_limit numeric;
begin
  foreach v_group in array array['all','any'] loop
    if p_rule ? v_group then
      if jsonb_typeof(p_rule->v_group) <> 'array' or jsonb_array_length(p_rule->v_group) = 0 then
        raise exception 'Invalid specification condition group' using errcode = '22023';
      end if;
      for v_child in select value from jsonb_array_elements(p_rule->v_group) loop
        v_result := public.spec_condition_internal_v1(v_child, p_values);
        if v_group = 'all' and v_result = false then return false; end if;
        if v_group = 'any' and v_result = true then return true; end if;
        v_unknown := v_unknown or v_result is null;
      end loop;
      return case when v_unknown then null else v_group = 'all' end;
    end if;
  end loop;
  if nullif(p_rule->>'field', '') is null then
    raise exception 'Specification condition requires a field' using errcode = '22023';
  end if;
  v_actual := p_values->(p_rule->>'field');
  if v_operator = 'is_set' then return public.spec_rule_known_internal_v1(v_actual); end if;
  if v_operator = 'not_set' then return not public.spec_rule_known_internal_v1(v_actual); end if;
  if v_operator in ('lt','lte','gt','gte') then
    v_limit:=public.spec_rule_number_internal_v1(p_rule->'value');
    if v_limit is null then raise exception 'Condition limit must be finite and numeric' using errcode='22023'; end if;
    v_number:=public.spec_rule_number_internal_v1(v_actual);
    if v_number is null then return null; end if;
    return case v_operator when 'lt' then v_number<v_limit when 'lte' then v_number<=v_limit
      when 'gt' then v_number>v_limit else v_number>=v_limit end;
  end if;
  if v_operator not in ('eq','neq','in','not_in','contains_any','contains_all') then
    raise exception 'Unsupported specification operator: %', v_operator using errcode = '22023';
  end if;
  if not public.spec_rule_known_internal_v1(v_actual) then return null; end if;
  v_set := public.spec_rule_set_internal_v1(v_actual);
  v_expected := public.spec_rule_set_internal_v1(p_rule->'value');
  return case v_operator
    when 'eq' then v_set = v_expected when 'neq' then v_set <> v_expected
    when 'in' then v_set <@ v_expected when 'not_in' then not (v_set && v_expected)
    when 'contains_any' then v_set && v_expected when 'contains_all' then v_set @> v_expected end;
end $function$
;


-- V2 type is explicit: decimal text must not be confused with a model token.
-- Decimal observations are serialized as text by their SQL projection. JSON
-- numbers are unknown because a web client may already have rounded them.
create or replace function public.spec_relation_condition_internal_v1(p_rule jsonb,p_values jsonb)
returns boolean language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $$
declare v_actual jsonb:=p_values->(p_rule->>'field'); v_type text:=p_rule->>'value_type';
 v_operator text:=p_rule->>'operator'; v_choice jsonb; v_number numeric; v_limit numeric;
begin
 if not public.spec_rule_known_internal_v1(v_actual) then return null; end if;
 if jsonb_typeof(v_actual) is distinct from (case when v_type='boolean' then 'boolean' else 'string' end) then return null; end if;
 if v_type='decimal' then
  v_number:=public.spec_rule_number_internal_v1(v_actual);
  if v_number is null then return null; end if;
 end if;
 for v_choice in select value from jsonb_array_elements(case when v_operator='in' then p_rule->'value' else jsonb_build_array(p_rule->'value') end) loop
  if v_type='decimal' then
   v_limit:=public.spec_rule_number_internal_v1(v_choice);
   if v_limit is null then raise exception 'Invalid decimal relation operand' using errcode='22023'; end if;
   if (case v_operator when 'lt' then v_number<v_limit when 'lte' then v_number<=v_limit
      when 'gt' then v_number>v_limit when 'gte' then v_number>=v_limit else v_number=v_limit end) then return true; end if;
  elsif v_actual=v_choice then return true;
  end if;
 end loop;
 return false;
end $$;
revoke all on function public.spec_relation_condition_internal_v1(jsonb,jsonb) from public,anon,authenticated;

create or replace function public.spec_relation_validate_internal_v1(p_claim jsonb)
returns void language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $validate$
declare v_group text; v_row jsonb; v_condition jsonb; v_source jsonb;
 v_ids text[]:='{}'; v_operator text; v_value jsonb; v_type text; v_choice jsonb; v_url text[];
begin
 if jsonb_typeof(p_claim)<>'object' or p_claim is null
 or p_claim->'schema_version' is distinct from '2'::jsonb
 or jsonb_typeof(p_claim->'interface') is distinct from 'string'
 or nullif(btrim(p_claim->>'interface'),'') is null
 or jsonb_typeof(p_claim->'label') is distinct from 'string'
 or nullif(btrim(p_claim->>'label'),'') is null
 or exists(select 1 from jsonb_object_keys(p_claim) k where k not in ('schema_version','interface','label','alternatives','exclusions')) then
  raise exception 'Relation requires version, interface and label' using errcode='22023'; end if;
 foreach v_group in array array['alternatives','exclusions'] loop
  if jsonb_typeof(p_claim->v_group) is distinct from 'array' then
   raise exception 'Relation requires row arrays' using errcode='22023'; end if;
  if v_group='alternatives' and jsonb_array_length(p_claim->v_group)=0 then
   raise exception 'Relation requires positive alternatives' using errcode='22023'; end if;
  for v_row in select value from jsonb_array_elements(p_claim->v_group) loop
   if jsonb_typeof(v_row)<>'object' then raise exception 'Invalid relation row' using errcode='22023'; end if;
   if jsonb_typeof(v_row->'id') is distinct from 'string' or nullif(btrim(v_row->>'id'),'') is null
    or jsonb_typeof(v_row->'label') is distinct from 'string' or nullif(btrim(v_row->>'label'),'') is null
    or jsonb_typeof(v_row->'conditions') is distinct from 'array'
    or jsonb_typeof(v_row->'sources') is distinct from 'array'
    or exists(select 1 from jsonb_object_keys(v_row) k where k not in ('id','label','conditions','sources')) then
     raise exception 'Relation row requires identity, conditions and sources' using errcode='22023'; end if;
   if jsonb_array_length(v_row->'conditions')=0 or jsonb_array_length(v_row->'sources')=0
     or v_row->>'id'=any(v_ids) then raise exception 'Empty or duplicate relation row' using errcode='22023'; end if;
   v_ids:=array_append(v_ids,v_row->>'id');
   for v_source in select value from jsonb_array_elements(v_row->'sources') loop
    v_url:=regexp_match(v_source#>>'{}',$url$^https?://([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*)(?::([0-9]{1,5}))?([/?#][A-Za-z0-9._~!$&'()*+,;=:@/?%#-]*)?$$url$);
    if jsonb_typeof(v_source) is distinct from 'string' or v_url is null
      or v_source#>>'{}' ~ '[[:space:]]'
      or (v_url[2] is not null and v_url[2]::integer not between 1 and 65535)
      or position('%' in regexp_replace(v_source#>>'{}','%[0-9A-Fa-f]{2}','','g'))>0 then
     raise exception 'Relation source requires an absolute web URL' using errcode='22023'; end if;
   end loop;
   for v_condition in select value from jsonb_array_elements(v_row->'conditions') loop
    if jsonb_typeof(v_condition)<>'object' then raise exception 'Invalid relation condition' using errcode='22023'; end if;
    v_operator:=v_condition->>'operator'; v_value:=v_condition->'value'; v_type:=v_condition->>'value_type';
    if jsonb_typeof(v_condition->'field') is distinct from 'string'
     or nullif(btrim(v_condition->>'field'),'') is null
     or v_operator is null or v_operator not in ('eq','in','lt','lte','gt','gte')
     or v_type is null or v_type not in ('decimal','token','boolean')
     or (v_operator not in ('eq','in') and v_type<>'decimal')
     or not public.spec_rule_known_internal_v1(v_value)
     or exists(select 1 from jsonb_object_keys(v_condition) k where k not in ('field','operator','value_type','value')) then
      raise exception 'Relation condition requires a known scalar configuration' using errcode='22023'; end if;
    if v_operator='in' and jsonb_typeof(v_value) is distinct from 'array' then
     raise exception 'In condition requires a list' using errcode='22023'; end if;
    for v_choice in select value from jsonb_array_elements(case when v_operator='in' then v_value else jsonb_build_array(v_value) end) loop
     if jsonb_typeof(v_choice) is distinct from (case when v_type='boolean' then 'boolean' else 'string' end)
      or (v_type='decimal' and public.spec_rule_number_internal_v1(v_choice) is null) then
      raise exception 'Comparison value must preserve its declared type and decimal precision' using errcode='22023'; end if;
    end loop;
   end loop;
  end loop;
 end loop;
end $validate$;
revoke all on function public.spec_relation_validate_internal_v1(jsonb) from public,anon,authenticated;

create or replace function public.spec_relation_assess_internal_v1(p_claim jsonb,p_configuration jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $$
declare v_row jsonb; v_condition jsonb; v_values jsonb; v_field text; v_state boolean;
 v_group text; v_matched jsonb:='[]'; v_excluded boolean:=false; v_unknown boolean:=false; v_exclusion_unknown boolean:=false;
 v_unresolved text[]:='{}'; v_row_unknown text[]; v_verdict text; v_child_state boolean; v_row_false boolean;
begin
 perform public.spec_relation_validate_internal_v1(p_claim);
 if jsonb_typeof(p_configuration) is distinct from 'object' then
  raise exception 'Relation evaluation requires one configuration' using errcode='22023'; end if;
 foreach v_group in array array['alternatives','exclusions'] loop
  for v_row in select value from jsonb_array_elements(p_claim->v_group) loop
   v_values:=p_configuration; v_row_unknown:='{}'; v_row_false:=false;
   for v_condition in select value from jsonb_array_elements(v_row->'conditions') loop
    v_field:=v_condition->>'field';
    if jsonb_typeof(v_values->v_field) in ('array','object','number') then v_values:=v_values-v_field; end if;
    v_child_state:=public.spec_relation_condition_internal_v1(v_condition,v_values);
    if v_child_state is null then v_row_unknown:=array_append(v_row_unknown,v_field);
    elsif not v_child_state then v_row_false:=true; end if;
   end loop;
   v_state:=case when v_row_false then false when cardinality(v_row_unknown)>0 then null else true end;
   if v_state is null then
    v_unknown:=true; v_unresolved:=v_unresolved||v_row_unknown;
    if v_group='exclusions' then v_exclusion_unknown:=true; end if;
   elsif v_state then
    if v_group='alternatives' then v_matched:=v_matched||jsonb_build_array(v_row->>'id');
    else v_excluded:=true; end if;
   end if;
  end loop;
 end loop;
 -- Exclusions narrow coverage; outside a non-exhaustive positive declaration
 -- does not prove physical incompatibility. A supported row concerns only
 -- this interface, never the bicycle as a whole.
 if v_excluded then v_verdict:='excluded';
 elsif v_exclusion_unknown then v_verdict:='unknown';
 elsif jsonb_array_length(v_matched)>0 then v_verdict:='supported';
 elsif v_unknown then v_verdict:='unknown';
 else v_verdict:='outside_declared_scope'; end if;
 return jsonb_build_object('verdict',v_verdict,'matching_alternatives',v_matched,
  'unresolved_fields',case when v_verdict='unknown' then
   (select coalesce(jsonb_agg(distinct f order by f),'[]') from unnest(v_unresolved) f) else '[]'::jsonb end);
end $$;
revoke all on function public.spec_relation_assess_internal_v1(jsonb,jsonb) from public,anon,authenticated;

create or replace function public.spec_reference_relations_guard_internal_v1()
returns trigger language plpgsql set search_path=pg_catalog,public,pg_temp as $$
declare v_claim jsonb; v_row jsonb; v_source jsonb;
begin
 for v_claim in select value from jsonb_array_elements(new.claims) loop
  if v_claim->'schema_version'='2'::jsonb then
   perform public.spec_relation_validate_internal_v1(v_claim);
   for v_row in select value from jsonb_array_elements((v_claim->'alternatives')||(v_claim->'exclusions')) loop
    for v_source in select value from jsonb_array_elements(v_row->'sources') loop
     if not (new.sources @> jsonb_build_array(v_source)) then
      raise exception 'Relation row source must belong to its manufacturer reference' using errcode='23514'; end if;
    end loop;
   end loop;
  elsif v_claim ? 'schema_version' then
   raise exception 'Unsupported relation schema version' using errcode='22023';
  end if;
 end loop;
 return new;
end $$;
revoke all on function public.spec_reference_relations_guard_internal_v1() from public,anon,authenticated;
drop trigger if exists spec_reference_relations_guard on public.product_spec_references;
create trigger spec_reference_relations_guard before insert or update of claims,sources on public.product_spec_references
 for each row execute function public.spec_reference_relations_guard_internal_v1();

notify pgrst,'reload schema';
commit;
