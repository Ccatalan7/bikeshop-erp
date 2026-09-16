-- Research applier: the reviewer of a proposal may be codex, claude,
-- claude-peer (a separate Claude session with fresh context) or owner, and
-- must still differ from the researcher. Only apply_product_spec_research_v1
-- changes; tables, grants, readiness, applications, receipts and facts stay.
-- Rerunnable: with the new body already installed it exits.
-- Candidate sha256 f80610525ba56c2c4b4ad3e96c7986dd15b3a362ada28c5083192d191d418653.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
do $guard$ begin
 if to_regprocedure('public.apply_product_spec_research_v1(uuid)') is null then
  raise exception 'The research applier is not installed';
 end if;
 if md5(pg_get_functiondef('public.apply_product_spec_research_v1(uuid)'::regprocedure))<>'dd356e99326b9d1727b5dcba3b695c43' and md5(pg_get_functiondef('public.apply_product_spec_research_v1(uuid)'::regprocedure))<>'431920eb97996e87c4e44d8e28a10e03' then
  raise exception 'apply_product_spec_research_v1 differs from the reviewed publication';
 end if;
end $guard$;

create or replace function public.apply_product_spec_research_v1(p_application_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $apply$
declare
 tenant uuid:=public.user_tenant_id(); actor uuid:=auth.uid();
 application public.product_spec_research_applications%rowtype;
 receipt public.product_spec_research_receipts%rowtype;
 command jsonb; before_state jsonb; after_state jsonb; preview jsonb;
 product_before public.products%rowtype; product_after public.products%rowtype;
 delta jsonb; definition public.spec_definitions%rowtype; old_fact public.spec_facts%rowtype;
 v_fact_id uuid; changed_ids uuid[]:='{}'; options uuid[]; value jsonb; source_kind text;
 changed_keys text[]:='{}'; product_exceptions text[]:=array['updated_at','spec_revision'];
 result jsonb; untouched_before jsonb; untouched_after jsonb;
begin
 if tenant is null or actor is null then
  raise exception 'Authenticated tenant required' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(tenant::text||':spec_research:'||p_application_id::text,0));
 select * into application from public.product_spec_research_applications
  where id=p_application_id and tenant_id=tenant and actor_id=actor for update;
 if not found then raise exception 'Aplicación no disponible' using errcode='42501'; end if;
 -- An uncertain response can retrieve an existing receipt without replaying a
 -- write, even if readiness was disabled afterwards. Revocation cannot erase it.
 select * into receipt from public.product_spec_research_receipts where application_id=application.id;
 if found then
  if receipt.command_sha256<>application.command_sha256 or receipt.actor_id<>actor or receipt.tenant_id<>tenant then
   raise exception 'Recibo de aplicación inconsistente' using errcode='23514';
  end if;
  return receipt.result||jsonb_build_object('replayed',true);
 end if;
 if application.revoked_at is not null or not exists(
  select 1 from public.product_spec_research_readiness where id=application.readiness_id
   and tenant_id=tenant and enabled for share) then
  raise exception 'El saneamiento global todavía no habilita el llenado' using errcode='42501';
 end if;
 command:=application.command_text::jsonb;
 if jsonb_typeof(command) is distinct from 'object' or command->'schema_version' is distinct from '1'::jsonb
  or command->>'tenant_id' is distinct from tenant::text or command->>'actor_id' is distinct from actor::text
  or exists(select 1 from jsonb_object_keys(command) k where k not in (
   'schema_version','product_id','tenant_id','actor_id','based_on','proposal_sha256',
   'identity_patch','values_patch','reference_id','expected_values','expected_identity','changes'))
  or jsonb_typeof(command->'changes') is distinct from 'array'
  or jsonb_typeof(command->'identity_patch') is distinct from 'object'
  or jsonb_typeof(command->'values_patch') is distinct from 'object'
  or exists(select 1 from jsonb_object_keys(command->'identity_patch') k where k not in ('model','manufacturer_sku','gtin')) then
  raise exception 'Comando de ficha inválido' using errcode='22023';
 end if;
 if jsonb_array_length(command->'changes')<>(select count(distinct c->>'key') from jsonb_array_elements(command->'changes') c)
  or exists(select 1 from jsonb_array_elements(command->'changes') c
   where c->>'origin' not in ('reference','research') or c->>'origin' is null
    or jsonb_typeof(c->'evidence') is distinct from 'array' or c->'evidence'='[]'::jsonb) then
  raise exception 'Los efectos deben ser únicos y tener procedencia revisada' using errcode='23514';
 end if;
 -- The privileged registrar validates the full proposal schema/evidence and
 -- independent review. The RPC additionally refuses a mismatched approval.
 if application.proposal->>'product_id' is distinct from command->>'product_id'
  or application.proposal->>'status' is distinct from 'reviewed'
  or application.proposal#>>'{review,verdict}' is distinct from 'accepted'
  or application.proposal#>>'{review,reviewed_proposal_sha256}' is distinct from command->>'proposal_sha256'
  or application.proposal#>>'{review,by}' is null or application.proposal#>>'{review,by}' not in ('codex','claude','claude-peer','owner')
  or application.proposal#>>'{review,by}' is not distinct from application.proposal->>'researcher'
  or application.proposal->'based_on' is distinct from command->'based_on' then
  raise exception 'La revisión no corresponde a este comando' using errcode='23514';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(tenant::text||':spec_fact:'||(command->>'product_id')::uuid::text,0));
 select * into product_before from public.products where id=(command->>'product_id')::uuid and tenant_id=tenant for update;
 if not found then raise exception 'Producto no disponible para este tenant' using errcode='42501'; end if;
 -- Stabilize metadata insertions as well as updates; locks also protect a
 -- category default and global options that a template row lock cannot cover.
 lock table public.spec_templates,public.spec_template_fields,public.spec_definitions,
  public.spec_definition_values,public.category_tech_mappings,public.product_spec_references in share mode;
 perform 1 from public.spec_facts where tenant_id=tenant and subject_type='product' and subject_id=product_before.id for update;
 perform 1 from public.spec_fact_values v join public.spec_facts f on f.id=v.fact_id
  where f.tenant_id=tenant and f.subject_type='product' and f.subject_id=product_before.id for update of v;
 perform 1 from public.spec_fact_readings r join public.spec_facts f on f.id=r.fact_id
  where f.tenant_id=tenant and f.subject_type='product' and f.subject_id=product_before.id for update of r;
 before_state:=public.get_product_spec_research_snapshot_v1(product_before.id);
 if before_state->>'snapshot_sha256' is distinct from command#>>'{based_on,snapshot_sha256}'
  or before_state->'fingerprints' is distinct from command#>'{based_on,fingerprints}'
  or before_state#>'{product,spec_revision}' is distinct from command#>'{based_on,spec_revision}'
  or before_state#>'{product,updated_at}' is distinct from command#>'{based_on,updated_at}'
  or before_state#>'{editor,template_id}' is distinct from command#>'{based_on,template_id}'
  or before_state#>'{editor,contract_version}' is distinct from command#>'{based_on,contract_version}' then
  raise exception 'La preimagen cambió; hay que investigar y revisar de nuevo' using errcode='40001';
 end if;
 preview:=public.preview_product_spec_research_v1(product_before.id,before_state->>'snapshot_sha256',
  command->'identity_patch',command->'values_patch',command->>'reference_id');
 if preview->'valid_draft' is distinct from 'true'::jsonb or preview->'values' is distinct from command->'expected_values'
  or preview->'identity' is distinct from command->'expected_identity'
  or preview->'reference_id' is distinct from command->'reference_id' then
  raise exception 'El efecto actual no corresponde a la propuesta revisada' using errcode='23514';
 end if;
 -- Every changed or automatically derived value must have an approved effect.
 if exists(select 1 from jsonb_each(preview->'values') e where
    e.value is distinct from before_state#>array['editor','values',e.key]
    and not exists(select 1 from jsonb_array_elements(command->'changes') c where c->>'key'=e.key))
  or exists(select 1 from jsonb_object_keys(command->'values_patch') k
    where not exists(select 1 from jsonb_array_elements(command->'changes') c where c->>'key'=k)) then
  raise exception 'Hay hechos sin revisión individual' using errcode='23514';
 end if;
 for delta in select c from jsonb_array_elements(command->'changes') c loop
  select d.* into definition from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
   where f.template_id=(before_state#>>'{editor,template_id}')::uuid
    and d.id=(delta->>'definition_id')::uuid and d.key=delta->>'key';
  if not found or before_state#>>array['editor','template','form_contract','roles',definition.key]='legacy'
   or delta->'final_value' is distinct from preview#>array['values',definition.key] then
   raise exception 'Efecto ajeno a la plantilla activa' using errcode='23514';
  end if;
  if definition.data_type not in ('number','boolean','text','single_select','multi_select','json') then
   raise exception 'Tipo técnico no implementado por este aplicador' using errcode='23514';
  end if;
  value:=delta->'final_value';
  select * into old_fact from public.spec_facts where tenant_id=tenant and subject_type='product'
   and subject_id=product_before.id and subject_scope is null and spec_definition_id=definition.id;
  -- An equal value never steals confirmation, readings or independent source.
  if old_fact.id is not null and value is not distinct from before_state#>array['editor','values',definition.key] then
   continue;
  end if;
  if old_fact.confirmed and not exists(select 1 from jsonb_array_elements(
    coalesce(application.proposal->'conflicts','[]'::jsonb)) conflict
    where conflict->>'field'=definition.key and jsonb_typeof(conflict->'resolution')='string'
     and nullif(btrim(conflict->>'resolution'),'') is not null) then
   raise exception 'Una observación confirmada requiere un conflicto resuelto explícitamente' using errcode='23514';
  end if;
  source_kind:=case when delta->>'origin'='reference' then 'catalog' else 'research' end;
  options:=null;
  if definition.data_type in ('single_select','multi_select') then
   select array_agg(o.id order by a.n) into options
   from jsonb_array_elements(case when definition.data_type='single_select' then jsonb_build_array(value) else value end)
    with ordinality a(label,n)
   join public.spec_definition_values o on o.spec_definition_id=definition.id and o.is_active
    and to_jsonb(o.label)=a.label and (o.tenant_id is null or o.tenant_id=tenant);
   if coalesce(cardinality(options),0)<>(case when definition.data_type='single_select' then 1 else jsonb_array_length(value) end)
    or cardinality(options)<>(select count(distinct v) from unnest(options) v) then
    raise exception 'Las opciones no resuelven IDs únicos' using errcode='23514';
   end if;
  end if;
  insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,
   value_number,value_boolean,value_text,value_json,source,confirmed)
  values(tenant,'product',product_before.id,definition.id,
   case when definition.data_type='number' then (value#>>'{}')::numeric end,
   case when definition.data_type='boolean' then (value#>>'{}')::boolean end,
   case when definition.data_type='text' then value#>>'{}' end,
   case when definition.data_type='json' then value end,source_kind,false)
  on conflict(tenant_id,subject_type,subject_id,spec_definition_id,coalesce(subject_scope,'')) do update
   set value_number=excluded.value_number,value_boolean=excluded.value_boolean,value_text=excluded.value_text,
    value_json=excluded.value_json,source=excluded.source,confirmed=false,updated_at=clock_timestamp()
  returning id into v_fact_id;
  -- Replaced readings/options are archived exactly in before_snapshot. Keeping
  -- an old name-reading attached to the new value would misattribute evidence.
  delete from public.spec_fact_readings where fact_id=v_fact_id;
  delete from public.spec_fact_values where fact_id=v_fact_id;
  if options is not null then
   insert into public.spec_fact_values(fact_id,value_id,position)
    select v_fact_id,id,(n-1)::integer from unnest(options) with ordinality a(id,n);
  end if;
  changed_ids:=array_append(changed_ids,v_fact_id);
  changed_keys:=array_append(changed_keys,definition.key);
 end loop;
 if command->'identity_patch'<>'{}'::jsonb or product_before.spec_reference_id is distinct from command->>'reference_id' then
  update public.products set
   model=case when command->'identity_patch' ? 'model' then command#>>'{identity_patch,model}' else model end,
   manufacturer_sku=case when command->'identity_patch' ? 'manufacturer_sku' then command#>>'{identity_patch,manufacturer_sku}' else manufacturer_sku end,
   gtin=case when command->'identity_patch' ? 'gtin' then command#>>'{identity_patch,gtin}' else gtin end,
   spec_reference_id=command->>'reference_id',updated_at=clock_timestamp()
   where id=product_before.id and tenant_id=tenant;
 end if;
 perform public.spec_validate_product_internal_v1(product_before.id);
 after_state:=public.get_product_spec_research_snapshot_v1(product_before.id);
 select * into product_after from public.products where id=product_before.id and tenant_id=tenant;
 product_exceptions:=product_exceptions||array(select jsonb_object_keys(command->'identity_patch'));
 if product_before.spec_reference_id is distinct from command->>'reference_id' then
  product_exceptions:=array_append(product_exceptions,'spec_reference_id');
 end if;
 if (to_jsonb(product_before)-product_exceptions) is distinct from (to_jsonb(product_after)-product_exceptions)
  or after_state#>'{editor,values}' is distinct from command->'expected_values'
  or product_after.spec_reference_id is distinct from command->>'reference_id'
  or exists(select 1 from jsonb_each(command->'identity_patch') i where to_jsonb(product_after)->i.key is distinct from i.value) then
  raise exception 'El guardado cambió datos fuera del efecto aprobado' using errcode='23514';
 end if;
 select coalesce(jsonb_agg(o order by o#>>'{fact,id}'),'[]') into untouched_before
  from jsonb_array_elements(before_state->'observations') o where not (o#>>'{fact,id}')::uuid=any(changed_ids);
 select coalesce(jsonb_agg(o order by o#>>'{fact,id}'),'[]') into untouched_after
  from jsonb_array_elements(after_state->'observations') o where not (o#>>'{fact,id}')::uuid=any(changed_ids);
 if untouched_before is distinct from untouched_after then
  raise exception 'El guardado alteró observaciones no incluidas' using errcode='23514';
 end if;
 result:=jsonb_build_object('application_id',application.id,'tenant_id',tenant,'actor_id',actor,
  'product_id',product_before.id,'command_sha256',application.command_sha256,
  'before_snapshot_sha256',before_state->'snapshot_sha256','after_snapshot_sha256',after_state->'snapshot_sha256',
  'changed_fact_ids',to_jsonb(changed_ids),'changed_keys',to_jsonb(changed_keys),
  'revision',product_after.spec_revision,'replayed',false);
 insert into public.product_spec_research_receipts(application_id,tenant_id,actor_id,product_id,command_sha256,
  before_product_text,after_product_text,before_snapshot,after_snapshot,changed_fact_ids,result)
 values(application.id,tenant,actor,product_before.id,application.command_sha256,
  to_jsonb(product_before)::text,to_jsonb(product_after)::text,before_state,after_state,changed_ids,result);
 return result;
end $apply$;
revoke all on function public.apply_product_spec_research_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.apply_product_spec_research_v1(uuid) to authenticated;

commit;
