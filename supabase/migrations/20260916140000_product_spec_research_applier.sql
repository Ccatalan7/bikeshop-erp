-- Research applier: readiness gate, registered commands, receipts and the
-- authenticated apply RPC, reviewed on 2026-09-07 and rehearsed locally.
-- Publishing it enables nothing: no readiness row exists, `enabled` defaults
-- to false, registration is a privileged reviewed DB write, and the RPC
-- refuses every command until a closed readiness receipt is registered.
-- No product, fact, reference, template or assignment changes.
-- Rerunnable: when the exact reviewed objects are already installed it only
-- re-applies the idempotent grants, so an interrupted verification can be
-- completed by rerunning this same file.
-- Candidate scripts/inventory/sql/product_spec_application_candidate.sql
-- sha256 71db507e742e04c5450acdeb592fb4b236cf44fa07545f3071237223db6457b7.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
create temp table research_applier_state on commit drop as
 select to_regprocedure('public.apply_product_spec_research_v1(uuid)') is not null as installed;
do $guard$ begin
 if (select installed from research_applier_state) then
  if md5(pg_get_functiondef('public.apply_product_spec_research_v1(uuid)'::regprocedure))<>'dd356e99326b9d1727b5dcba3b695c43' or md5(pg_get_functiondef('public.get_product_spec_research_application_status_v1(uuid)'::regprocedure))<>'c9f31a17aad9cdc3e290d301e8372548' or md5(pg_get_functiondef('public.get_product_spec_research_receipt_v1(uuid)'::regprocedure))<>'eb079dec2f23aa54d7223b13124d1c3a' or (select pg_get_constraintdef(oid) from pg_constraint
  where conrelid='public.spec_facts'::regclass and conname='spec_facts_source_known') is distinct from 'CHECK ((source = ANY (ARRAY[''mechanic''::text, ''catalog''::text, ''supplier_text''::text, ''inferred''::text, ''import''::text, ''name_reading''::text, ''research''::text])))' then
   raise exception 'Installed research applier differs from the reviewed candidate';
  end if;
  return;
 end if;
 if to_regclass('public.product_spec_research_readiness') is not null
  or to_regclass('public.product_spec_research_applications') is not null
  or to_regclass('public.product_spec_research_receipts') is not null
  or to_regprocedure('public.apply_product_spec_research_v1(uuid)') is not null
  or to_regprocedure('public.get_product_spec_research_receipt_v1(uuid)') is not null
  or to_regprocedure('public.get_product_spec_research_application_status_v1(uuid)') is not null then
  raise exception 'Research applier objects already exist';
 end if;
 if (select pg_get_constraintdef(oid) from pg_constraint
  where conrelid='public.spec_facts'::regclass and conname='spec_facts_source_known') is distinct from 'CHECK ((source = ANY (ARRAY[''mechanic''::text, ''catalog''::text, ''supplier_text''::text, ''inferred''::text, ''import''::text, ''name_reading''::text])))' then
  raise exception 'spec_facts_source_known differs from the reviewed production state';
 end if;
 if exists(select 1 from public.spec_facts where source='research') then
  raise exception 'Unexpected research-sourced facts before the applier exists';
 end if;
 if (select extnamespace::regnamespace::text from pg_extension where extname='pgcrypto') is distinct from 'extensions' then
  raise exception 'pgcrypto must live in the extensions schema';
 end if;
 if md5(pg_get_functiondef('public.get_product_spec_research_snapshot_v1(uuid)'::regprocedure))<>'981026d3283612b825ff3231d0d9ab41' or md5(pg_get_functiondef('public.preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text)'::regprocedure))<>'a48f8882900af7d7e945ad4cbc561df2' or md5(pg_get_functiondef('public.spec_validate_product_internal_v1(uuid)'::regprocedure))<>'ebe417e4a4d802d7dfc60f40768125e7' or md5(pg_get_functiondef('public.user_tenant_id()'::regprocedure))<>'fac7093d7805560ddb01e2699a287169' then
  raise exception 'A reviewed predecessor function differs from the pinned production state';
 end if;
end $guard$;

create table if not exists public.product_spec_research_readiness (
 id uuid primary key,
 tenant_id uuid not null references public.tenants(id),
 audit_sha256 text not null check(audit_sha256 ~ '^[a-f0-9]{64}$'),
 review_sha256 text not null check(review_sha256 ~ '^[a-f0-9]{64}$'),
 closed_at timestamptz not null,
 enabled boolean not null default false,
 unique(id,tenant_id)
);
create table if not exists public.product_spec_research_applications (
 id uuid primary key,
 tenant_id uuid not null references public.tenants(id),
 actor_id uuid not null references auth.users(id),
 readiness_id uuid not null,
 command_text text not null check(octet_length(command_text) between 2 and 4194304),
 command_sha256 text not null check(command_sha256 ~ '^[a-f0-9]{64}$'),
 proposal jsonb not null check(jsonb_typeof(proposal)='object'),
 bundle_sha256 text not null check(bundle_sha256 ~ '^[a-f0-9]{64}$'),
 registered_at timestamptz not null default clock_timestamp(),
 revoked_at timestamptz,
 foreign key(readiness_id,tenant_id) references public.product_spec_research_readiness(id,tenant_id),
 check(encode(extensions.digest(command_text,'sha256'),'hex')=command_sha256),
 unique(tenant_id,command_sha256)
);
create table if not exists public.product_spec_research_receipts (
 application_id uuid primary key references public.product_spec_research_applications(id),
 tenant_id uuid not null references public.tenants(id),
 actor_id uuid not null references auth.users(id),
 product_id uuid not null references public.products(id),
 command_sha256 text not null,
 before_product_text text not null,
 after_product_text text not null,
 before_snapshot jsonb not null,
 after_snapshot jsonb not null,
 changed_fact_ids uuid[] not null,
 result jsonb not null,
 applied_at timestamptz not null default clock_timestamp()
);
alter table public.product_spec_research_readiness enable row level security;
alter table public.product_spec_research_applications enable row level security;
alter table public.product_spec_research_receipts enable row level security;
revoke all on public.product_spec_research_readiness,public.product_spec_research_applications,
 public.product_spec_research_receipts from public,anon,authenticated;
-- Registration and readiness are privileged, reviewed DB operations. Neither
-- the client nor the apply RPC can manufacture or enable its own permission.
revoke all on public.product_spec_research_readiness,public.product_spec_research_applications,
 public.product_spec_research_receipts from service_role;

do $source$ begin
 if (select pg_get_constraintdef(oid) from pg_constraint
  where conrelid='public.spec_facts'::regclass and conname='spec_facts_source_known')='CHECK ((source = ANY (ARRAY[''mechanic''::text, ''catalog''::text, ''supplier_text''::text, ''inferred''::text, ''import''::text, ''name_reading''::text, ''research''::text])))' then return; end if;
 alter table public.spec_facts drop constraint spec_facts_source_known;
alter table public.spec_facts add constraint spec_facts_source_known check(source=any(array[
 'mechanic','catalog','supplier_text','inferred','import','name_reading','research']));
end $source$;

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
  or application.proposal#>>'{review,by}' is null or application.proposal#>>'{review,by}' not in ('codex','claude')
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

comment on function public.apply_product_spec_research_v1(uuid) is
 'Apply one privileged registered research command as its real authenticated actor. Requires closed global readiness, locked exact preimage, canonical preview, complete preservation check and atomic before/after receipt. No product creation, assignment, stock, price or arbitrary patch.';

create or replace function public.get_product_spec_research_receipt_v1(p_application_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $receipt$
declare result jsonb;
begin
 if auth.uid() is null or public.user_tenant_id() is null then
  raise exception 'Authenticated tenant required' using errcode='42501';
 end if;
 select to_jsonb(r) into result from public.product_spec_research_receipts r
 where r.application_id=p_application_id and r.tenant_id=public.user_tenant_id() and r.actor_id=auth.uid();
 if not found then raise exception 'Recibo no disponible' using errcode='42501'; end if;
 return result;
end $receipt$;
revoke all on function public.get_product_spec_research_receipt_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_product_spec_research_receipt_v1(uuid) to authenticated;

create or replace function public.get_product_spec_research_application_status_v1(p_application_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $status$
declare result jsonb;
begin
 if auth.uid() is null or public.user_tenant_id() is null then
  raise exception 'Authenticated tenant required' using errcode='42501';
 end if;
 select jsonb_build_object('application_id',a.id,'tenant_id',a.tenant_id,'actor_id',a.actor_id,
  'command_sha256',a.command_sha256,'bundle_sha256',a.bundle_sha256,
  'readiness_id',a.readiness_id,'readiness_enabled',g.enabled,
  'revoked',a.revoked_at is not null,'applied',r.application_id is not null)
 into result from public.product_spec_research_applications a
 join public.product_spec_research_readiness g on g.id=a.readiness_id and g.tenant_id=a.tenant_id
 left join public.product_spec_research_receipts r on r.application_id=a.id
 where a.id=p_application_id and a.tenant_id=public.user_tenant_id() and a.actor_id=auth.uid();
 if not found then raise exception 'Aplicación no disponible' using errcode='42501'; end if;
 return result;
end $status$;
revoke all on function public.get_product_spec_research_application_status_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_product_spec_research_application_status_v1(uuid) to authenticated;
-- Production default privileges grant SELECT on new public tables to the
-- read-only codex_test_runner role; the reviewed ACL keeps these tables
-- owner-only, readable solely through the definer RPCs.
do $runner$ begin
 if exists(select 1 from pg_roles where rolname='codex_test_runner') then
  execute 'revoke all on public.product_spec_research_readiness,public.product_spec_research_applications,'
   'public.product_spec_research_receipts from codex_test_runner';
 end if;
end $runner$;

commit;
