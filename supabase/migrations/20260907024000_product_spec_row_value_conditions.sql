-- Same-row conditional values. No catalogue, product, schema version or
-- published metadata changes. Old clients reject the new bucket as unknown.
begin;

-- The unchanged callers own row scope, version locks and populated-data
-- publication guards. Do not widen syntax on an unreviewed predecessor.
do $dependencies$
declare expected record; actual record; fn regprocedure;
begin
 for expected in select * from (values
  ('save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb)','007ed3a67a009527c24ed54ee3380b99',true,'v','{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}'),
  ('spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','48f01ef6f5343dfe3a45285ad227fb60',false,'i','{postgres=X/postgres,service_role=X/postgres}'),
  ('spec_coherence_metadata_internal_v1(jsonb,jsonb)','863ba9ce738f2c6d497e1a3786c02eb5',false,'i','{postgres=X/postgres,service_role=X/postgres}'),
  ('spec_coherence_publication_guard_internal_v1()','1d9f691d7e044034255f7500c21feb7c',true,'v','{postgres=X/postgres,service_role=X/postgres}'),
  ('spec_template_rules_validate_internal_v1(uuid)','273b46c7568552a6e2641eec4f69f59c',true,'v','{postgres=X/postgres,service_role=X/postgres}')
 ) e(signature,digest,definer,volatility,acl) loop
  fn:=to_regprocedure('public.'||expected.signature);
  if fn is null then raise exception 'Missing row value dependency: %',expected.signature; end if;
  select p.*,pg_get_userbyid(p.proowner) owner_name,md5(pg_get_functiondef(p.oid)) body_md5
   into actual from pg_proc p where p.oid=fn;
  if actual.body_md5<>expected.digest or actual.owner_name<>'postgres'
   or actual.prosecdef<>expected.definer or actual.provolatile::text<>expected.volatility
   or actual.proacl::text is distinct from expected.acl
   or actual.proconfig is distinct from array['search_path=pg_catalog, public, pg_temp']::text[] then
   raise exception 'Unreviewed row value dependency: %',expected.signature;
  end if;
 end loop;
end $dependencies$;

do $preimage$
declare expected record; actual record; fn regprocedure;
begin
 for expected in select * from (values
  ('spec_row_conditions_metadata_internal_v1(jsonb,jsonb)','bdc9903e785f45355d16840963128554','f3a61c7ddb5ae221d977207eb692588b'),
  ('spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb)','ff9dfdc494187854222afcf70cb036dc','74312e56c452d640b3ced5633f729b7c')
 ) e(signature,old_md5,new_md5) loop
  fn:=to_regprocedure('public.'||expected.signature);
  if fn is null then raise exception 'Missing required row condition function: %',expected.signature; end if;
  select p.*,pg_get_userbyid(p.proowner) owner_name,md5(pg_get_functiondef(p.oid)) body_md5
   into actual from pg_proc p where p.oid=fn;
  if actual.body_md5 not in (expected.old_md5,expected.new_md5) then
   raise exception 'Unreviewed row condition preimage: %',expected.signature;
  end if;
  if actual.owner_name<>'postgres' or actual.prosecdef or actual.provolatile::text<>'i'
   or actual.proconfig is distinct from array['search_path=pg_catalog, public, pg_temp']::text[]
   or has_function_privilege('anon',fn,'execute') or has_function_privilege('authenticated',fn,'execute')
   or not has_function_privilege('service_role',fn,'execute')
   or exists(select 1 from aclexplode(coalesce(actual.proacl,acldefault('f',actual.proowner))) a
     where a.grantee not in ('postgres'::regrole::oid,'service_role'::regrole::oid)
       or a.grantor<>actual.proowner or a.is_grantable or a.privilege_type<>'EXECUTE') then
   raise exception 'Unreviewed row condition security: %',expected.signature;
  end if;
 end loop;
end $preimage$;

CREATE OR REPLACE FUNCTION public.spec_row_conditions_metadata_internal_v1(p_contract jsonb, p_fields jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare block jsonb:=p_contract->'row_conditions'; field record; bucket record; cell record;
 schema jsonb; columns jsonb; col jsonb; predicate jsonb; input jsonb; choices jsonb; edges jsonb; expressions jsonb; expression jsonb; rule jsonb; expected jsonb;
begin
 if not(p_contract ? 'row_conditions') then return; end if;
 if p_contract->'rules_version' is distinct from '2'::jsonb or jsonb_typeof(block) is distinct from 'object' then
   raise exception 'Condiciones de configuración inválidas' using errcode='23514';
 end if;
 if block->'version' is distinct from '1'::jsonb or jsonb_typeof(block->'fields') is distinct from 'object'
   or exists(select 1 from jsonb_object_keys(block) k where k not in ('version','fields')) then
   raise exception 'Condiciones de configuración inválidas' using errcode='23514';
 end if;
 for field in select * from jsonb_each(block->'fields') loop
   schema:=p_fields->field.key->'schema';
   if p_fields->field.key->>'data_type' is distinct from 'json' or jsonb_typeof(schema) is distinct from 'object'
     or jsonb_typeof(field.value) is distinct from 'object' or field.value='{}'::jsonb then
     raise exception 'Las condiciones usan un campo de filas no disponible' using errcode='23514';
   end if;
   perform public.spec_rows_schema_validate_internal_v1(schema);
   select jsonb_object_agg(c->>'key',c) into columns from jsonb_array_elements(schema->'columns') c;
   edges:='[]';
   for bucket in select * from jsonb_each(field.value) loop
     if bucket.key not in ('allowed_when','required_when','allowed_options','value_when') or jsonb_typeof(bucket.value) is distinct from 'object' then
       raise exception 'Falta un mapa de condiciones de columnas' using errcode='23514';
     end if;
     for cell in select * from jsonb_each(bucket.value) loop
       col:=columns->cell.key;
       if col is null then raise exception 'Una condición apunta a otra configuración' using errcode='23514'; end if;
       if bucket.key='allowed_options' then
         if col->>'type'<>'token' or jsonb_typeof(cell.value) is distinct from 'array' then
           raise exception 'Las opciones exceden el dominio de la columna' using errcode='23514';
         end if;
         if jsonb_array_length(cell.value)<>(select count(distinct v) from jsonb_array_elements(cell.value) v)
           or exists(select 1 from jsonb_array_elements(cell.value) v where jsonb_typeof(v)<>'string' or v#>>'{}'=''
             or (jsonb_array_length(coalesce(col->'allowed_values','[]'))>0 and not(col->'allowed_values' @> jsonb_build_array(v)))) then
           raise exception 'Las opciones exceden el dominio de la columna' using errcode='23514';
         end if;
         continue;
       end if;
       if bucket.key='value_when' then
         if jsonb_typeof(cell.value) is distinct from 'array' then
           raise exception 'Una columna necesita reglas de valor condicionado' using errcode='23514';
         end if;
         if jsonb_array_length(cell.value)=0 then
           raise exception 'Una columna necesita reglas de valor condicionado' using errcode='23514';
         end if;
         expressions:='[]';
         for rule in select value from jsonb_array_elements(cell.value) loop
           if jsonb_typeof(rule) is distinct from 'object' then
             raise exception 'Regla de valor condicionado inválida' using errcode='23514';
           end if;
           if not(rule ?& array['when','expected'])
             or exists(select 1 from jsonb_object_keys(rule) k where k not in ('when','expected'))
             or jsonb_typeof(rule->'expected') is distinct from 'object'
             or jsonb_typeof(rule->'when') is distinct from 'object' then
             raise exception 'Regla de valor condicionado inválida' using errcode='23514';
           end if;
           expected:=rule->'expected';
           if not(expected ?& array['value_type','value'])
             or exists(select 1 from jsonb_object_keys(expected) k where k not in ('value_type','value'))
             or coalesce(expected->>'value_type','') not in ('boolean','token','decimal')
             or (expected->>'value_type'='boolean' and col->>'type'<>'boolean')
             or (expected->>'value_type'='token' and col->>'type'<>'token')
             or (expected->>'value_type'='decimal' and col->>'type' not in ('decimal','integer'))
             or not public.spec_rule_known_internal_v1(expected->'value') then
             raise exception 'El valor condicionado necesita el tipo y dominio de su columna' using errcode='23514';
           end if;
           -- The row parser owns literal types, exact PG decimals and numeric
           -- domains. A single target observation cannot satisfy another cell.
           perform public.spec_rows_validate_internal_v1(schema,jsonb_build_object('schema_version',1,'rows',
             jsonb_build_array(jsonb_build_object('id','expected','values',jsonb_build_object(cell.key,expected->'value'),'sources','[]'::jsonb))));
           if field.value->'allowed_options' ? cell.key and
             not(field.value->'allowed_options'->cell.key @> jsonb_build_array(expected->'value')) then
             raise exception 'El valor condicionado excede las opciones de esta ficha' using errcode='23514';
           end if;
           expressions:=expressions||jsonb_build_array(rule->'when');
         end loop;
       else
         expressions:=jsonb_build_array(cell.value);
       end if;
       for expression in select value from jsonb_array_elements(expressions) loop
       if bucket.key='value_when' then
         begin
           perform public.spec_template_condition_internal_v1(expression,'{}');
         exception when invalid_parameter_value then
           raise exception 'Condición de valor de configuración inválida' using errcode='23514';
         end;
       else
         perform public.spec_template_condition_internal_v1(expression,'{}');
       end if;
       if bucket.key='allowed_when' and col->'required'='true'::jsonb and expression->>'kind'<>'always' then
         raise exception 'Una columna obligatoria del esquema no puede hacerse condicional' using errcode='23514';
       end if;
       for predicate in select p from jsonb_array_elements(coalesce(expression->'rows','[]')) r
         cross join lateral jsonb_array_elements(r) pp(p) loop
         input:=columns->(predicate->>'field');
         if input is null or (predicate->>'value_type'='boolean' and input->>'type'<>'boolean')
           or (predicate->>'value_type'='decimal' and input->>'type' not in ('decimal','integer'))
           or (predicate->>'value_type'='token' and input->>'type' not in ('text','token')) then
           raise exception 'Un requisito usa una columna o un tipo ajeno' using errcode='23514';
         end if;
         choices:=case when predicate->>'operator'='in' then predicate->'value' else jsonb_build_array(predicate->'value') end;
         if jsonb_array_length(coalesce(input->'allowed_values','[]'))>0 and not(input->'allowed_values' @> choices) then
           raise exception 'Un requisito usa una opción ajena a la columna' using errcode='23514';
         end if;
         edges:=edges||jsonb_build_array(jsonb_build_array(cell.key,predicate->>'field'));
       end loop;
       end loop;
     end loop;
   end loop;
   if exists(with recursive e(a,b) as (select p->>0,p->>1 from jsonb_array_elements(edges) p),
     paths(tip,visited,cycle) as (
       select b,array[a,b],a=b from e
       union all select e.b,p.visited||e.b,e.b=any(p.visited)
         from paths p join e on e.a=p.tip where not p.cycle
     ) select 1 from paths where cycle) then
     raise exception 'Los requisitos de una configuración forman un ciclo' using errcode='23514';
   end if;
 end loop;
end $function$
;
revoke all on function public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.spec_row_conditions_issues_internal_v1(p_contract jsonb, p_fields jsonb, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare result jsonb:='[]'; field record; schema jsonb; document jsonb; r jsonb; col jsonb;
 cells jsonb; allowed boolean; required boolean; known boolean; options jsonb; code text; message text; blocking boolean;
 rule jsonb; expected jsonb; active_expected jsonb; antecedent boolean; pending boolean; conflict boolean; equal_value boolean;
 expectations_conflict boolean; expected_label text;
begin
 perform public.spec_row_conditions_metadata_internal_v1(p_contract,p_fields);
 for field in select * from jsonb_each(coalesce(p_contract->'row_conditions'->'fields','{}')) loop
   if not public.spec_rule_known_internal_v1(p_values->field.key) then continue; end if;
   schema:=p_fields->field.key->'schema';
   begin
     document:=public.spec_rows_validate_internal_v1(schema,p_values->field.key);
   exception when check_violation then
     result:=result||jsonb_build_array(jsonb_build_object('code','row_shape','field',field.key,
       'message','La configuración tiene un formato inválido. Sus datos se conservan.','blocking',true));
     continue;
   end;
   for r in select value from jsonb_array_elements(document->'rows') loop
     cells:=r->'values';
     for col in select value from jsonb_array_elements(schema->'columns') loop
       known:=public.spec_rule_known_internal_v1(cells->(col->>'key'));
       allowed:=public.spec_template_condition_internal_v1(coalesce(field.value->'allowed_when'->(col->>'key'),'{"kind":"always"}'),cells);
       required:=case when col->'required'='true'::jsonb then true else
         public.spec_template_condition_internal_v1(coalesce(field.value->'required_when'->(col->>'key'),'{"kind":"never"}'),cells) end;
       code:=null; message:=null; blocking:=false;
       if allowed is false then
         if known then code:='row_field_applicability';blocking:=true;message:='El dato no corresponde a los requisitos de esta configuración.'; end if;
       elsif allowed is null then code:='row_prerequisite';message:='Confirma primero los requisitos de esta configuración.';
       elsif not known and required is null then code:='row_prerequisite';message:='Falta determinar si este dato es necesario.';
       elsif not known and required and col->'required' is distinct from 'true'::jsonb then
         code:='row_required_missing';message:='Falta confirmar este dato de la configuración.';
       end if;
       if code is not null then result:=result||jsonb_build_array(jsonb_build_object('code',code,'field',field.key,'row_id',r->>'id',
         'column',col->>'key','message',(col->>'label')||': '||message,'blocking',blocking)); end if;
       if allowed is false then continue; end if;
       options:=field.value->'allowed_options'->(col->>'key');
       if known and options is not null and not(options @> jsonb_build_array(cells->(col->>'key'))) then
         result:=result||jsonb_build_array(jsonb_build_object('code','row_option','field',field.key,'row_id',r->>'id',
           'column',col->>'key','message',(col->>'label')||': La opción no pertenece a esta ficha.','blocking',true));
       end if;
       if allowed is not true then continue; end if;
       pending:=false; conflict:=false; expectations_conflict:=false; active_expected:=null;
       for rule in select value from jsonb_array_elements(coalesce(field.value->'value_when'->(col->>'key'),'[]')) loop
         antecedent:=public.spec_template_condition_internal_v1(rule->'when',cells);
         if antecedent is false then continue; end if;
         if antecedent is null then pending:=true; continue; end if;
         expected:=rule->'expected';
         -- Simultaneously active implications have no precedence. Contradictory
         -- expected values block even when their observed cell is absent.
         if active_expected is not null then
           equal_value:=case when expected->>'value_type'='decimal' then
             public.spec_rule_number_internal_v1(active_expected->'value')=public.spec_rule_number_internal_v1(expected->'value')
             else active_expected->'value'=expected->'value' end;
           expectations_conflict:=expectations_conflict or equal_value is false;
         end if;
         active_expected:=coalesce(active_expected,expected);
         if not known then pending:=true; continue; end if;
         equal_value:=case when expected->>'value_type'='decimal' then
           public.spec_rule_number_internal_v1(cells->(col->>'key'))=public.spec_rule_number_internal_v1(expected->'value')
           else cells->(col->>'key')=expected->'value' end;
         conflict:=conflict or equal_value is false;
         pending:=pending or equal_value is null;
       end loop;
       expected_label:=case when active_expected is null then null
         when active_expected->>'value_type'='boolean' then case active_expected->'value' when 'true'::jsonb then 'Sí' else 'No' end
         when active_expected->>'value_type'='decimal' then trim_scale(public.spec_rule_number_internal_v1(active_expected->'value'))::text
           ||case when col->>'unit' is null then '' else ' '||(col->>'unit') end
         else active_expected->>'value' end;
       if conflict or expectations_conflict or pending then
         result:=result||jsonb_build_array(jsonb_build_object(
           'code',case when conflict or expectations_conflict then 'row_value_conflict' else 'row_value_pending' end,
           'field',field.key,'row_id',r->>'id','column',col->>'key',
           'message',(col->>'label')||': '||case when expectations_conflict then
             'hay condiciones confirmadas que exigen valores incompatibles para esta configuración.'
             when conflict then 'se espera «'||expected_label||'» para las condiciones confirmadas de esta configuración.'
             else coalesce('se espera «'||expected_label||'»; ','')||
             'falta confirmar el valor o los requisitos de esta configuración.' end,'blocking',conflict or expectations_conflict));
       end if;
     end loop;
   end loop;
 end loop;
 return result;
end $function$
;
revoke all on function public.spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb) to service_role;

do $postimage$
declare expected record; fn regprocedure;
begin
 for expected in select * from (values
  ('spec_row_conditions_metadata_internal_v1(jsonb,jsonb)','f3a61c7ddb5ae221d977207eb692588b'),
  ('spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb)','74312e56c452d640b3ced5633f729b7c')
 ) e(signature,digest) loop
  fn:=to_regprocedure('public.'||expected.signature);
  if fn is null or md5(pg_get_functiondef(fn)) is distinct from expected.digest then
   raise exception 'Unexpected row value postimage: %',expected.signature;
  end if;
 end loop;
end $postimage$;
commit;
