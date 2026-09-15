-- Member profiles are scoped observations of an inventory product. This file
-- never activates a family, creates inventory children or fills product facts.
create table if not exists public.product_spec_member_profiles (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id),
  product_id uuid not null references public.products(id) on delete restrict,
  collection_definition_id uuid not null references public.spec_definitions(id),
  member_row_id text not null check (member_row_id ~ '^[A-Za-z0-9_-]{1,80}$'),
  member_identity jsonb not null check (jsonb_typeof(member_identity)='object'),
  identity_sources jsonb not null default '[]' check (jsonb_typeof(identity_sources)='array'),
  manufacturer_sku text,
  template_id uuid not null references public.spec_templates(id),
  saved_contract_version integer not null check (saved_contract_version>0),
  reference_id text references public.product_spec_references(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  scope text generated always as ('member:'||id::text) stored,
  active_template_guard boolean generated always as
    (case when archived_at is null then true else null::boolean end) stored,
  foreign key (template_id,active_template_guard)
    references public.spec_templates(id,is_active) deferrable initially immediate
);
create unique index if not exists product_spec_member_profiles_active_row
  on public.product_spec_member_profiles(tenant_id,product_id,collection_definition_id,member_row_id)
  where archived_at is null;
create unique index if not exists product_spec_member_profiles_scope
  on public.product_spec_member_profiles(tenant_id,product_id,scope);
create index if not exists product_spec_member_profiles_product on public.product_spec_member_profiles(product_id);
create index if not exists product_spec_member_profiles_active_template
  on public.product_spec_member_profiles(template_id,product_id) where archived_at is null;
alter table public.product_spec_member_profiles enable row level security;
revoke all on public.product_spec_member_profiles from public,anon,authenticated;
-- Writes only through the aggregate command. Read access is tenant-scoped.
grant select on public.product_spec_member_profiles to authenticated;
drop policy if exists product_spec_member_profiles_tenant_read on public.product_spec_member_profiles;
create policy product_spec_member_profiles_tenant_read on public.product_spec_member_profiles
  for select to authenticated using (tenant_id=public.user_tenant_id());

-- Header changes retain the previous binding/reference and the actor. Facts
-- and readings continue in the existing normalized observation graph.
create table if not exists public.product_spec_member_profile_events (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.product_spec_member_profiles(id),
  tenant_id uuid not null references public.tenants(id),
  product_id uuid not null references public.products(id),
  actor_id uuid,
  occurred_at timestamptz not null default now(),
  before_state jsonb,
  after_state jsonb not null
);
alter table public.product_spec_member_profile_events enable row level security;
revoke all on public.product_spec_member_profile_events from public,anon,authenticated;
grant select on public.product_spec_member_profile_events to authenticated;
drop policy if exists product_spec_member_profile_events_tenant_read on public.product_spec_member_profile_events;
create policy product_spec_member_profile_events_tenant_read on public.product_spec_member_profile_events
 for select to authenticated using (tenant_id=public.user_tenant_id());
create index if not exists product_spec_member_profile_events_profile on public.product_spec_member_profile_events(profile_id,occurred_at,id);

create or replace function public.spec_member_event_immutable_internal_v1()
returns trigger language plpgsql set search_path=pg_catalog,public,pg_temp as $$
begin
 raise exception 'El historial del componente conserva su actor y sus estados originales' using errcode='23514';
end $$;
drop trigger if exists spec_member_event_immutable on public.product_spec_member_profile_events;
create trigger spec_member_event_immutable before update or delete on public.product_spec_member_profile_events
 for each row execute function public.spec_member_event_immutable_internal_v1();

-- A real write barrier (rather than a snapshot-only existence check) makes a
-- metadata transaction with an older repeatable-read snapshot abort when a
-- profile was committed meanwhile. It is internal coordination, not template
-- metadata, and never changes a family's contract_version on a product edit.
create table if not exists public.spec_member_graph_revisions (
  template_id uuid primary key references public.spec_templates(id) on delete cascade,
  revision bigint not null default 0,
  last_xid bigint not null
);
revoke all on public.spec_member_graph_revisions from public,anon,authenticated;
alter table public.spec_member_graph_revisions enable row level security;
-- New relations must not inherit extra readers from an environment's default
-- privileges. Only the owner/service role and the explicit tenant reader above
-- belong to this extension; the internal epoch has no authenticated grant.
do $member_table_acl$
declare relation record; reader record;
begin
 for relation in select c.oid,c.relname,c.relowner,c.relacl from pg_class c
   where c.oid in ('public.product_spec_member_profiles'::regclass,
     'public.product_spec_member_profile_events'::regclass,'public.spec_member_graph_revisions'::regclass) loop
   for reader in select distinct a.grantee from aclexplode(relation.relacl) a
     where a.grantee not in (relation.relowner,'service_role'::regrole::oid,'authenticated'::regrole::oid) loop
     execute format('revoke all on table public.%I from %s',relation.relname,
       case when reader.grantee=0 then 'public' else quote_ident(pg_get_userbyid(reader.grantee)) end);
   end loop;
 end loop;
end $member_table_acl$;
create or replace function public.spec_member_graph_touch_internal_v1(p_template_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if p_template_id is null then return; end if;
 insert into public.spec_member_graph_revisions(template_id,revision,last_xid) values(p_template_id,1,txid_current())
 on conflict(template_id) do update set revision=public.spec_member_graph_revisions.revision+1,last_xid=txid_current()
 where public.spec_member_graph_revisions.last_xid<>txid_current();
end $$;

create or replace function public.spec_member_identity_enrichment_internal_v1(p_before jsonb,p_after jsonb)
returns boolean language sql immutable set search_path=pg_catalog,public,pg_temp as $$
 select jsonb_typeof(p_before)='object' and jsonb_typeof(p_after)='object' and not exists(
   select 1 from jsonb_each(p_before) e where public.spec_rule_known_internal_v1(e.value)
     and e.value is distinct from p_after->e.key)
$$;

-- The collection is enabled by template metadata. Field definitions, units and
-- rules remain owned by their existing family, including intrinsic row tables.
create or replace function public.spec_member_collection_contract_internal_v1(
  p_template_id uuid,p_definition_id uuid
) returns jsonb language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
declare cfg jsonb; entry jsonb; def public.spec_definitions%rowtype; k text; result jsonb;
begin
 select form_contract->'member_profiles' into cfg from public.spec_templates where id=p_template_id;
 if cfg is null then return null; end if;
 if jsonb_typeof(cfg) is distinct from 'object' or cfg->'version' is distinct from '1'::jsonb
   or jsonb_typeof(cfg->'collections') is distinct from 'array'
   or jsonb_array_length(cfg->'collections')=0
   or exists(select 1 from jsonb_object_keys(cfg) x where x not in ('version','collections')) then
   raise exception 'Contrato de perfiles de componentes inválido' using errcode='23514';
 end if;
 if exists(select 1 from jsonb_array_elements(cfg->'collections') x group by x->>'field' having count(*)>1) then
   raise exception 'La colección de componentes tiene dos dueños' using errcode='23514';
 end if;
 for entry in select value from jsonb_array_elements(cfg->'collections') loop
   if jsonb_typeof(entry) is distinct from 'object'
     or exists(select 1 from jsonb_object_keys(entry) x where x not in ('field','family_column','identity_columns'))
     or jsonb_typeof(entry->'field') is distinct from 'string'
     or jsonb_typeof(entry->'family_column') is distinct from 'string'
     or jsonb_typeof(entry->'identity_columns') is distinct from 'array' then
     raise exception 'Colección de perfiles inválida' using errcode='23514';
   end if;
   select d.* into def from public.spec_definitions d join public.spec_template_fields f on f.spec_definition_id=d.id
     join public.spec_templates t on t.id=f.template_id
     where f.template_id=p_template_id and d.key=entry->>'field'
       and t.form_contract->'roles'->>d.key='contents'
       and (d.tenant_id is null or d.tenant_id=t.tenant_id)
       and (f.tenant_id is null or f.tenant_id=t.tenant_id);
   if def.id is null or def.data_type<>'json' or not(def.validation_rules ? 'rows_schema') then
     raise exception 'El perfil necesita una colección activa de contenido' using errcode='23514';
   end if;
   if not exists(select 1 from jsonb_array_elements(def.validation_rules->'rows_schema'->'columns') c
     where c->>'key'=entry->>'family_column' and c->>'type'='token') then
     raise exception 'La familia del componente necesita una columna tipada' using errcode='23514';
   end if;
   if not (entry->'identity_columns' ?& array['identity_brand','identity_model']) or
     exists(select 1 from jsonb_array_elements(entry->'identity_columns') c
     where jsonb_typeof(c)<>'string') or
     jsonb_array_length(entry->'identity_columns')<>(select count(distinct x) from jsonb_array_elements(entry->'identity_columns') x) then
     raise exception 'Identidad de componente inválida' using errcode='23514';
   end if;
   for k in select jsonb_array_elements_text(entry->'identity_columns') loop
     if k=entry->>'family_column' or not exists(
       select 1 from jsonb_array_elements(def.validation_rules->'rows_schema'->'columns') c
       where c->>'key'=k and c->>'type' in ('token','text')) then
       raise exception 'Columna de identidad de componente inválida' using errcode='23514';
     end if;
   end loop;
   if def.id=p_definition_id then result:=entry; end if;
 end loop;
 return result;
end $$;

-- Resolves only a top-level row of this product, never a row in another scope.
create or replace function public.spec_member_binding_internal_v1(
  p_product_id uuid,p_definition_id uuid,p_row_id text,p_bound_template_id uuid default null
) returns jsonb language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
declare prod public.products%rowtype; parent_template uuid; cfg jsonb; row_value jsonb; row_sources jsonb;
  identity jsonb; family_key text; member_template uuid;
begin
 select * into prod from public.products where id=p_product_id;
 if not found then raise exception 'Producto no disponible' using errcode='42501'; end if;
 parent_template:=public.spec_template_resolution_internal_v1(prod.tenant_id,prod.category_id,prod.spec_template_id);
 cfg:=public.spec_member_collection_contract_internal_v1(parent_template,p_definition_id);
 if cfg is null then raise exception 'La ficha no admite perfiles en esta colección' using errcode='23514'; end if;
 select r->'values',r->'sources' into row_value,row_sources from public.spec_facts f
   cross join lateral jsonb_array_elements(f.value_json->'rows') r
   where f.tenant_id=prod.tenant_id and f.subject_type='product' and f.subject_id=prod.id
     and f.subject_scope is null and f.spec_definition_id=p_definition_id and r->>'id'=p_row_id;
 if row_value is null then raise exception 'Falta la fila del componente %: archiva o vuelve a vincular su ficha',p_row_id using errcode='23514'; end if;
 family_key:=row_value->>(cfg->>'family_column');
 select t.id into member_template from public.spec_templates t
   where t.key=family_key and t.is_active and (t.tenant_id is null or t.tenant_id=prod.tenant_id)
     and (p_bound_template_id is null or t.id=p_bound_template_id)
   order by (t.tenant_id=prod.tenant_id) desc nulls last,t.id limit 1;
 if member_template is null then raise exception 'Falta confirmar una familia con ficha disponible' using errcode='23514'; end if;
 select coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) into identity from jsonb_each(row_value) e
   where e.key=cfg->>'family_column' or cfg->'identity_columns' ? e.key;
 return jsonb_build_object('identity',identity,'sources',row_sources,'template_id',member_template,'family_key',family_key);
end $$;

create or replace function public.spec_member_profile_issues_internal_v1(p_profile_id uuid)
returns jsonb language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
declare profile public.product_spec_member_profiles%rowtype; payload jsonb; issues jsonb;
begin
 select * into profile from public.product_spec_member_profiles where id=p_profile_id;
 if not found or profile.archived_at is not null then return '[]'; end if;
 perform public.spec_validate_product_fact_shape_internal_v1(profile.product_id,profile.scope);
 payload:=public.spec_template_product_scope_payload_internal_v1(profile.product_id,profile.template_id,false,profile.scope);
 -- The shared draft validator cannot accept omitted mandatory OEM facts. Its
 -- caller supplies the same completeness check as the root-product validator.
 if profile.reference_id is not null and exists(
   select 1 from public.product_spec_references r cross join lateral jsonb_object_keys(r.fact_values) k
   where r.id=profile.reference_id and (not(payload ? k) or not public.spec_rule_known_internal_v1(
     public.spec_payload_display_exact_internal_v1(jsonb_build_object(k,payload->k))->
       (select d.key from public.spec_definitions d where d.id::text=k)))) then
   raise exception 'La referencia exige hechos en la ficha del componente' using errcode='23514';
 end if;
 issues:=public.spec_validate_draft_internal_v1(profile.template_id,
   public.spec_payload_display_exact_internal_v1(payload),profile.reference_id,
   coalesce(profile.member_identity->>'identity_brand',''),coalesce(profile.member_identity->>'identity_model',''),
   coalesce(profile.manufacturer_sku,''));
 return (select coalesce(jsonb_agg(i||jsonb_build_object('profile_id',profile.id,
   'collection_definition_id',profile.collection_definition_id,'member_row_id',profile.member_row_id)),'[]'::jsonb)
   from jsonb_array_elements(issues) i);
end $$;

create or replace function public.spec_validate_product_member_profiles_internal_v1(p_product_id uuid)
returns void language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
declare profile public.product_spec_member_profiles%rowtype; binding jsonb; issues jsonb;
begin
 if exists(select 1 from public.spec_facts f where f.subject_type='product' and f.subject_id=p_product_id
   and f.subject_scope is not null and not exists(select 1 from public.product_spec_member_profiles p
     where p.product_id=f.subject_id and p.tenant_id=f.tenant_id and p.scope=f.subject_scope)) then
   raise exception 'Hecho de componente sin perfil dueño' using errcode='23514';
 end if;
 for profile in select * from public.product_spec_member_profiles
   where product_id=p_product_id and archived_at is null loop
   binding:=public.spec_member_binding_internal_v1(p_product_id,profile.collection_definition_id,profile.member_row_id,profile.template_id);
   if binding->'identity' is distinct from profile.member_identity or
     (binding->>'template_id')::uuid is distinct from profile.template_id then
     raise exception 'El componente cambió: archiva explícitamente su ficha anterior' using errcode='23514';
   end if;
   if exists(select 1 from public.spec_facts f where f.subject_type='product' and f.subject_id=p_product_id
     and f.subject_scope=profile.scope and not exists(select 1 from public.spec_template_fields tf
       where tf.template_id=profile.template_id and tf.spec_definition_id=f.spec_definition_id)) then
     raise exception 'El hecho no pertenece a la ficha del componente' using errcode='23514';
   end if;
   issues:=public.spec_member_profile_issues_internal_v1(profile.id);
   if exists(select 1 from jsonb_array_elements(issues) i where coalesce((i->>'blocking')::boolean,true)) then
     raise exception 'Ficha de componente contradictoria: %',issues using errcode='23514';
   end if;
 end loop;
end $$;

create or replace function public.spec_member_profile_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare prod public.products%rowtype; binding jsonb; v_template_id uuid;
begin
 if tg_op='DELETE' then
   raise exception 'Archiva la ficha del componente para conservar su evidencia' using errcode='23514';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(new.tenant_id::text||':spec_fact:'||new.product_id::text,0));
 select * into prod from public.products where id=new.product_id and tenant_id=new.tenant_id for update;
 if not found or not exists(select 1 from public.spec_templates t where t.id=new.template_id
   and (t.tenant_id is null or t.tenant_id=new.tenant_id)) or not exists(
     select 1 from public.spec_definitions d where d.id=new.collection_definition_id
       and (d.tenant_id is null or d.tenant_id=new.tenant_id)) then
   raise exception 'Perfil de componente ajeno al tenant' using errcode='42501';
 end if;
 for v_template_id in select distinct x from unnest(array[new.template_id,
   public.spec_template_resolution_internal_v1(prod.tenant_id,prod.category_id,prod.spec_template_id)]) x order by x loop
   perform public.spec_member_graph_touch_internal_v1(v_template_id);
 end loop;
 if jsonb_typeof(new.identity_sources) is distinct from 'array' or exists(
   select 1 from jsonb_array_elements(new.identity_sources) s
   where jsonb_typeof(s)<>'string' or not public.spec_source_url_valid_internal_v1(s#>>'{}')) then
   raise exception 'La identidad del componente necesita fuentes válidas' using errcode='23514';
 end if;
 if tg_op='UPDATE' then
   if old.archived_at is not null then
     raise exception 'La ficha archivada conserva su evidencia sin cambios' using errcode='23514';
   end if;
   if (new.id,new.tenant_id,new.product_id,new.collection_definition_id,new.template_id,new.created_at)
     is distinct from (old.id,old.tenant_id,old.product_id,old.collection_definition_id,old.template_id,old.created_at) then
     raise exception 'La identidad de la ficha del componente es inmutable' using errcode='23514';
   end if;
   if new.member_row_id is distinct from old.member_row_id and
     (new.member_identity,new.manufacturer_sku) is distinct from (old.member_identity,old.manufacturer_sku) then
     raise exception 'Vincular otra fila exige la misma identidad confirmada' using errcode='23514';
   end if;
   if (new.member_identity,new.manufacturer_sku) is distinct from (old.member_identity,old.manufacturer_sku) and (
     not public.spec_member_identity_enrichment_internal_v1(old.member_identity,new.member_identity)
     or (old.manufacturer_sku is not null and new.manufacturer_sku is distinct from old.manufacturer_sku)
     or jsonb_array_length(new.identity_sources)=0) then
     raise exception 'Cambiar identidad confirmada exige archivar; identificar un vacío exige su fuente' using errcode='23514';
   end if;
 end if;
 if new.archived_at is null then
   binding:=public.spec_member_binding_internal_v1(new.product_id,new.collection_definition_id,new.member_row_id,new.template_id);
   if binding->'identity' is distinct from new.member_identity then
     raise exception 'La fila elegida no corresponde a la identidad del componente' using errcode='23514';
   end if;
 end if;
 new.updated_at:=now();
 return new;
end $$;
drop trigger if exists spec_member_profile_guard on public.product_spec_member_profiles;
create trigger spec_member_profile_guard before insert or update or delete on public.product_spec_member_profiles
  for each row execute function public.spec_member_profile_guard_internal_v1();

create or replace function public.spec_member_profile_revision_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 insert into public.product_spec_member_profile_events(profile_id,tenant_id,product_id,actor_id,before_state,after_state)
 values(new.id,new.tenant_id,new.product_id,auth.uid(),case when tg_op='UPDATE' then to_jsonb(old) end,to_jsonb(new));
 update public.products set spec_revision=spec_revision+1 where id=new.product_id;
 return null;
end $$;
drop trigger if exists spec_member_profile_revision on public.product_spec_member_profiles;
create trigger spec_member_profile_revision after insert or update on public.product_spec_member_profiles
  for each row execute function public.spec_member_profile_revision_internal_v1();

create or replace function public.spec_member_profile_constraint_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.spec_validate_product_internal_v1(new.product_id);
 return null;
end $$;
drop trigger if exists spec_member_profile_constraint on public.product_spec_member_profiles;
create constraint trigger spec_member_profile_constraint after insert or update on public.product_spec_member_profiles
  deferrable initially deferred for each row execute function public.spec_member_profile_constraint_internal_v1();

create or replace function public.spec_member_metadata_constraint_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_template_id uuid; v_product_id uuid; target_ids uuid[];
begin
 if tg_table_name='spec_templates' then target_ids:=array[new.id];
 elsif tg_table_name='spec_template_fields' then
   target_ids:=array[case when tg_op='DELETE' then old.template_id else new.template_id end];
   if tg_op='UPDATE' then target_ids:=array_append(target_ids,old.template_id); end if;
 else
   select array_agg(f.template_id) into target_ids from public.spec_template_fields f where f.spec_definition_id=new.id;
 end if;
 for v_template_id in select distinct t.id from public.spec_templates t where t.id=any(target_ids) loop
   perform public.spec_member_graph_touch_internal_v1(v_template_id);
   perform public.spec_member_collection_contract_internal_v1(v_template_id,null);
   for v_product_id in select distinct p.id from public.product_spec_member_profiles m
     join public.products p on p.id=m.product_id where m.archived_at is null
       and (m.template_id=v_template_id or public.spec_template_resolution_internal_v1(p.tenant_id,p.category_id,p.spec_template_id)=v_template_id) loop
     perform public.spec_validate_product_member_profiles_internal_v1(v_product_id);
   end loop;
 end loop;
 return null;
end $$;
drop trigger if exists spec_member_template_metadata_constraint on public.spec_templates;
create constraint trigger spec_member_template_metadata_constraint after insert or update on public.spec_templates
 deferrable initially deferred for each row execute function public.spec_member_metadata_constraint_internal_v1();
drop trigger if exists spec_member_field_metadata_constraint on public.spec_template_fields;
create constraint trigger spec_member_field_metadata_constraint after insert or update or delete on public.spec_template_fields
 deferrable initially deferred for each row execute function public.spec_member_metadata_constraint_internal_v1();
drop trigger if exists spec_member_definition_metadata_constraint on public.spec_definitions;
create constraint trigger spec_member_definition_metadata_constraint after update on public.spec_definitions
 deferrable initially deferred for each row execute function public.spec_member_metadata_constraint_internal_v1();

-- A category binding is another metadata route to the parent template. Touch
-- both template epochs even when the current snapshot has no profiles: an RR
-- transaction must conflict with a profile committed after that snapshot.
create or replace function public.spec_member_category_constraint_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_template_id uuid; v_product_id uuid; target_ids uuid[];
begin
 if tg_op='UPDATE' and (old.tenant_id,old.category_id,old.template_id,old.status)
   is not distinct from (new.tenant_id,new.category_id,new.template_id,new.status) then return null; end if;
 target_ids:=array[case when tg_op<>'INSERT' then old.template_id end,
   case when tg_op<>'DELETE' then new.template_id end];
 for v_template_id in select distinct t.id from public.spec_templates t
   where t.id=any(target_ids) order by t.id loop
   perform public.spec_member_graph_touch_internal_v1(v_template_id);
 end loop;
 for v_product_id in select p.id from public.products p
   where p.spec_template_id is null and (
     (tg_op<>'INSERT' and p.tenant_id=old.tenant_id and p.category_id=old.category_id) or
     (tg_op<>'DELETE' and p.tenant_id=new.tenant_id and p.category_id=new.category_id))
   and exists(select 1 from public.product_spec_member_profiles m where m.product_id=p.id and m.archived_at is null)
   order by p.id loop
   perform public.spec_validate_product_member_profiles_internal_v1(v_product_id);
   -- Even a compatible parent reassignment invalidates an already-open editor.
   update public.products set spec_revision=spec_revision+1 where id=v_product_id;
 end loop;
 return null;
end $$;
drop trigger if exists spec_member_category_constraint on public.category_tech_mappings;
create constraint trigger spec_member_category_constraint after insert or update or delete on public.category_tech_mappings
 deferrable initially deferred for each row execute function public.spec_member_category_constraint_internal_v1();

-- Direct fact/option/reading writes must not mutate history or create an
-- unowned product scope. Bike/job_bike scopes retain their existing contract.
create or replace function public.spec_member_fact_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare fact public.spec_facts%rowtype; profile public.product_spec_member_profiles%rowtype; fid uuid; v_template_id uuid;
begin
 if tg_table_name='spec_facts' then
   if tg_op='DELETE' then fact:=old; else fact:=new; end if;
 else
   fid:=case when tg_op='DELETE' then old.fact_id else new.fact_id end;
   select * into fact from public.spec_facts where id=fid;
   if tg_op='UPDATE' and new.fact_id is distinct from old.fact_id and exists(
     select 1 from public.spec_facts where id in (old.fact_id,new.fact_id) and subject_type='product' and subject_scope is not null) then
     raise exception 'La evidencia no puede mudarse de componente' using errcode='23514';
   end if;
 end if;
 if fact.subject_type='product' and fact.subject_scope is not null then
   perform pg_advisory_xact_lock(hashtextextended(fact.tenant_id::text||':spec_fact:'||fact.subject_id::text,0));
   select * into profile from public.product_spec_member_profiles where tenant_id=fact.tenant_id
     and product_id=fact.subject_id and scope=fact.subject_scope for share;
   if not found then raise exception 'Hecho de componente sin perfil dueño' using errcode='23514'; end if;
   if profile.archived_at is not null then
     raise exception 'La ficha archivada conserva su evidencia sin cambios' using errcode='23514';
   end if;
   for v_template_id in select distinct x from public.products p cross join lateral unnest(array[profile.template_id,
     public.spec_template_resolution_internal_v1(p.tenant_id,p.category_id,p.spec_template_id)]) x
     where p.id=profile.product_id order by x loop
     perform public.spec_member_graph_touch_internal_v1(v_template_id);
   end loop;
 end if;
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
drop trigger if exists spec_member_fact_guard on public.spec_facts;
create trigger spec_member_fact_guard before insert or update or delete on public.spec_facts
  for each row execute function public.spec_member_fact_guard_internal_v1();
drop trigger if exists spec_member_fact_values_guard on public.spec_fact_values;
create trigger spec_member_fact_values_guard before insert or update or delete on public.spec_fact_values
  for each row execute function public.spec_member_fact_guard_internal_v1();
drop trigger if exists spec_member_fact_readings_guard on public.spec_fact_readings;
create trigger spec_member_fact_readings_guard before insert or update or delete on public.spec_fact_readings
  for each row execute function public.spec_member_fact_guard_internal_v1();

create or replace function public.spec_member_reading_revision_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 update public.products p set spec_revision=p.spec_revision+1 from public.spec_facts f
   where f.id=case when tg_op='DELETE' then old.fact_id else new.fact_id end
     and f.subject_type='product' and f.subject_scope is not null and f.subject_id=p.id and f.tenant_id=p.tenant_id;
 return null;
end $$;
drop trigger if exists spec_member_reading_revision on public.spec_fact_readings;
create trigger spec_member_reading_revision after insert or update or delete on public.spec_fact_readings
 for each row execute function public.spec_member_reading_revision_internal_v1();

create or replace function public.spec_apply_member_profiles_internal_v1(p_product_id uuid,p_command jsonb)
returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare entry jsonb; profile public.product_spec_member_profiles%rowtype; binding jsonb; t public.spec_templates%rowtype;
  tenant uuid:=public.user_tenant_id(); profile_id uuid;
begin
 if jsonb_typeof(p_command) is distinct from 'object' or p_command->'schema_version' is distinct from '1'::jsonb
   or jsonb_typeof(p_command->'upserts') is distinct from 'array'
   or jsonb_typeof(p_command->'archive_ids') is distinct from 'array'
   or exists(select 1 from jsonb_object_keys(p_command) k where k not in ('schema_version','upserts','archive_ids'))
   or jsonb_array_length(p_command->'upserts')>200 or jsonb_array_length(p_command->'archive_ids')>200 then
   raise exception 'Comando de perfiles de componentes inválido' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_array_elements(p_command->'upserts') e group by (e->>'id')::uuid having count(*)>1)
   or exists(select 1 from jsonb_array_elements(p_command->'archive_ids') e group by (e#>>'{}')::uuid having count(*)>1) then
   raise exception 'El comando repite una ficha de componente' using errcode='22023';
 end if;
 for entry in select value from jsonb_array_elements(p_command->'archive_ids') loop
   if jsonb_typeof(entry)<>'string' then raise exception 'Identificador de archivo inválido' using errcode='22023'; end if;
   profile_id:=(entry#>>'{}')::uuid;
   select * into profile from public.product_spec_member_profiles where id=profile_id and tenant_id=tenant
     and product_id=p_product_id for update;
   if not found then raise exception 'Ficha de componente no disponible' using errcode='42501'; end if;
   if profile.archived_at is null then
     update public.product_spec_member_profiles set archived_at=now() where id=profile.id;
   end if;
 end loop;
 for entry in select value from jsonb_array_elements(p_command->'upserts') loop
   if jsonb_typeof(entry) is distinct from 'object' or jsonb_typeof(entry->'values') is distinct from 'object'
     or not(entry ?& array['id','collection_definition_id','member_row_id','template_id','contract_version','values'])
     or exists(select 1 from jsonb_object_keys(entry) k where k not in ('id','collection_definition_id',
       'member_row_id','template_id','contract_version','reference_id','manufacturer_sku','values','binding_action'))
     or (entry ? 'binding_action' and coalesce(entry->>'binding_action','') not in ('identify','rebind')) then
     raise exception 'Ficha de componente inválida' using errcode='22023';
   end if;
   profile_id:=(entry->>'id')::uuid;
   binding:=public.spec_member_binding_internal_v1(p_product_id,(entry->>'collection_definition_id')::uuid,
     entry->>'member_row_id',(entry->>'template_id')::uuid);
   select * into t from public.spec_templates where id=(binding->>'template_id')::uuid for share;
   if t.id is distinct from (entry->>'template_id')::uuid
     or t.contract_version is distinct from (entry->>'contract_version')::integer then
     raise exception 'La ficha del componente cambió. Recarga antes de guardar.' using errcode='40001';
   end if;
   select * into profile from public.product_spec_member_profiles where id=profile_id for update;
   if found then
     if (profile.tenant_id,profile.product_id) is distinct from (tenant,p_product_id) then
       raise exception 'Ficha de componente no disponible' using errcode='42501';
     end if;
     if profile.archived_at is not null or (profile.collection_definition_id,profile.template_id) is distinct from
       ((entry->>'collection_definition_id')::uuid,t.id) then
       raise exception 'Archiva la ficha anterior y crea una para esta pieza' using errcode='23514';
     end if;
     if (profile.member_identity,profile.manufacturer_sku) is distinct from
       (binding->'identity',nullif(btrim(entry->>'manufacturer_sku'),'')) then
       if entry->>'binding_action' is distinct from 'identify' or profile.member_row_id<>entry->>'member_row_id' then
         raise exception 'Confirma la identificación con su fuente o archiva la ficha anterior' using errcode='23514';
       end if;
       update public.product_spec_member_profiles set member_identity=binding->'identity',identity_sources=binding->'sources',
         manufacturer_sku=nullif(btrim(entry->>'manufacturer_sku'),'') where id=profile.id;
     elsif profile.member_row_id<>entry->>'member_row_id' then
       if entry->>'binding_action' is distinct from 'rebind' then
         raise exception 'Elige explícitamente la fila para volver a vincular esta ficha' using errcode='23514';
       end if;
       update public.product_spec_member_profiles set member_row_id=entry->>'member_row_id' where id=profile.id;
     end if;
     if (profile.reference_id,profile.saved_contract_version) is distinct from (entry->>'reference_id',t.contract_version) then
       update public.product_spec_member_profiles set reference_id=entry->>'reference_id',saved_contract_version=t.contract_version
         where id=profile.id;
     end if;
   else
     insert into public.product_spec_member_profiles(id,tenant_id,product_id,collection_definition_id,member_row_id,
       member_identity,identity_sources,manufacturer_sku,template_id,saved_contract_version,reference_id)
     values(profile_id,tenant,p_product_id,(entry->>'collection_definition_id')::uuid,entry->>'member_row_id',
       binding->'identity',binding->'sources',nullif(btrim(entry->>'manufacturer_sku'),''),t.id,t.contract_version,entry->>'reference_id');
   end if;
   perform public.spec_write_scope_payload_internal_v1(p_product_id,t.id,entry->'values',entry->>'reference_id','member:'||profile_id::text);
 end loop;
end $$;

-- Research backups include the binding history as well as scoped facts. The
-- v1 snapshot already covers all fact scopes; v2 adds their profile owners and
-- pins them in the fingerprint instead of leaving the observations orphaned.
create or replace function public.get_product_spec_research_snapshot_v2(p_product_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare root_snapshot jsonb; members jsonb; events jsonb; fingerprints jsonb;
begin
 root_snapshot:=public.get_product_spec_research_snapshot_v1(p_product_id);
 members:=public.get_product_spec_member_profiles_v1(p_product_id);
 select coalesce(jsonb_agg(to_jsonb(e) order by e.occurred_at,e.id),'[]'::jsonb) into events
   from public.product_spec_member_profile_events e where e.product_id=p_product_id and e.tenant_id=public.user_tenant_id();
 fingerprints:=root_snapshot->'fingerprints'||jsonb_build_object(
   'member_profiles_sha256',encode(extensions.digest(members::text,'sha256'),'hex'),
   'member_events_sha256',encode(extensions.digest(events::text,'sha256'),'hex'));
 return root_snapshot||jsonb_build_object('read_schema_version',2,'member_profiles',members,'member_profile_events',events,
   'fingerprints',fingerprints,'snapshot_sha256',encode(extensions.digest(jsonb_build_object(
     'root_snapshot_sha256',root_snapshot->>'snapshot_sha256','fingerprints',fingerprints)::text,'sha256'),'hex'));
end $$;

create or replace function public.get_product_spec_member_profiles_v1(p_product_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare prod public.products%rowtype; profile public.product_spec_member_profiles%rowtype;
  result jsonb:='[]'; archived jsonb:='[]'; profile_context jsonb; ref jsonb;
begin
 if auth.uid() is null then raise exception 'Authenticated tenant required' using errcode='42501'; end if;
 select * into prod from public.products where id=p_product_id and tenant_id=public.user_tenant_id();
 if not found then raise exception 'Producto no disponible para este tenant' using errcode='42501'; end if;
 for profile in select * from public.product_spec_member_profiles where product_id=p_product_id and tenant_id=prod.tenant_id
   order by created_at,id loop
   select (to_jsonb(r)-'fact_values')||jsonb_build_object('read_schema_version',2,
     'facts',public.spec_payload_display_exact_internal_v1(r.fact_values)) into ref
     from public.product_spec_references r where id=profile.reference_id;
   profile_context:=to_jsonb(profile)||jsonb_build_object(
     'fact_payload',(select coalesce(jsonb_object_agg(e.key,case when d.data_type='number' then
       jsonb_build_object('number',e.value->>'number') else e.value end),'{}'::jsonb)
       from jsonb_each(public.spec_product_scope_payload_internal_v1(prod.id,profile.scope)) e
       join public.spec_definitions d on d.id::text=e.key),
     'catalog_keys',(select coalesce(jsonb_agg(d.key order by d.key),'[]'::jsonb) from public.spec_facts f
       join public.spec_definitions d on d.id=f.spec_definition_id
       where f.tenant_id=prod.tenant_id and f.subject_type='product' and f.subject_id=prod.id
         and f.subject_scope=profile.scope and f.source='catalog'),
     'values',public.spec_payload_display_exact_internal_v1(public.spec_product_scope_payload_internal_v1(prod.id,profile.scope)),
     'reference',ref,'issues',public.spec_member_profile_issues_internal_v1(profile.id));
   if profile.archived_at is null then
     profile_context:=profile_context||jsonb_build_object('template',public.spec_template_editor_internal_v1(profile.template_id,prod.tenant_id));
     result:=result||jsonb_build_array(profile_context);
   else
     archived:=archived||jsonb_build_array(profile_context);
   end if;
 end loop;
 return jsonb_build_object('read_schema_version',1,'product_id',prod.id,'revision',prod.spec_revision,
   'product_updated_at',prod.updated_at,'profiles',result,'archived_profiles',archived);
end $$;

-- One statement supplies the root and scoped contexts in the same MVCC view.
create or replace function public.get_product_spec_editor_context_v3(p_product_id uuid,p_category_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare root_context jsonb; persisted_context jsonb; prod public.products%rowtype; persisted_template uuid;
begin
 root_context:=public.get_product_spec_editor_context_v2(p_product_id,p_category_id);
 if p_product_id is not null then
   select * into prod from public.products where id=p_product_id and tenant_id=public.user_tenant_id();
   if not found then raise exception 'Producto no disponible para este tenant' using errcode='42501'; end if;
   persisted_template:=public.spec_template_resolution_internal_v1(prod.tenant_id,prod.category_id,prod.spec_template_id);
   if persisted_template is distinct from (root_context->>'template_id')::uuid then
     persisted_context:=public.get_product_spec_editor_context_v2(p_product_id,prod.category_id)
       ||jsonb_build_object('product_updated_at',prod.updated_at);
   end if;
 end if;
 -- A category preview changes only the draft root. Keep the persisted owner
 -- available so its components can still be edited or explicitly archived.
 return root_context||jsonb_build_object('product_updated_at',prod.updated_at,'member_parent_context',persisted_context,
   'member_profiles',case when p_product_id is null then
   jsonb_build_object('read_schema_version',1,'product_id',null,'revision',0,
     'product_updated_at',null,'profiles','[]'::jsonb,'archived_profiles','[]'::jsonb)
   else public.get_product_spec_member_profiles_v1(p_product_id) end);
end $$;

-- Draft rows have not yet been persisted. Load the existing family's contract
-- after checking the parent's declared collection; saving still resolves the
-- actual persisted row and rechecks every template version atomically.
create or replace function public.get_product_spec_member_template_v1(
 p_parent_template_id uuid,p_collection_definition_id uuid,p_family_key text
) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare tenant uuid:=public.user_tenant_id(); cfg jsonb; result jsonb; target uuid;
begin
 if auth.uid() is null or tenant is null or not exists(select 1 from public.spec_templates
   where id=p_parent_template_id and is_active and (tenant_id is null or tenant_id=tenant)) then
   raise exception 'Ficha no disponible para este tenant' using errcode='42501';
 end if;
 cfg:=public.spec_member_collection_contract_internal_v1(p_parent_template_id,p_collection_definition_id);
 if cfg is null or not exists(select 1 from public.spec_definitions d,
   lateral jsonb_array_elements(d.validation_rules->'rows_schema'->'columns') c
   where d.id=p_collection_definition_id and c->>'key'=cfg->>'family_column' and c->'allowed_values' ? p_family_key) then
   raise exception 'La familia no corresponde a esta colección' using errcode='23514';
 end if;
 select t.id into target from public.spec_templates t where t.key=p_family_key and t.is_active
   and (t.tenant_id is null or t.tenant_id=tenant)
   order by (t.tenant_id=tenant) desc nulls last,t.id limit 1;
 if target is null then raise exception 'La familia aún no tiene una ficha disponible' using errcode='23514'; end if;
 result:=public.spec_template_editor_internal_v1(target,tenant);
 return jsonb_build_object('read_schema_version',2,'revision',0,'values','{}'::jsonb,
   'parent_template_id',p_parent_template_id,'collection_definition_id',p_collection_definition_id,
   'template_id',target,'template_key',result->>'key','technical_family',result->>'technical_family',
   'contract_version',result->'contract_version','template',result);
end $$;
