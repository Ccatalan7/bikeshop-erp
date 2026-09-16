-- Revoking a research application (registrar review, 2026-09-16: «nadie puede
-- revocar una aplicación salvo por SQL privilegiado directo»). The actor who
-- applied it can now revoke it with a reason, through the same guarded path
-- the applier uses. Every fact the receipt lists as changed goes back to its
-- archived preimage (restored) or disappears when it did not exist (deleted),
-- but only while it is still exactly what the application wrote: a fact a
-- mechanic confirmed or edited afterwards is kept and reported. Identity
-- fields patched by the application go back the same way. A registered but
-- never applied application is simply closed so apply can never run. A second
-- call returns the revocation receipt (replayed).
-- Rerunnable: create or replace / if not exists only.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';

alter table public.product_spec_research_applications
  add column if not exists revoked_by uuid references auth.users(id),
  add column if not exists revoked_reason text;

create table if not exists public.product_spec_research_revocations (
 application_id uuid primary key references public.product_spec_research_applications(id),
 tenant_id uuid not null references public.tenants(id),
 actor_id uuid not null references auth.users(id),
 product_id uuid references public.products(id),
 reason text not null,
 before_snapshot jsonb,
 after_snapshot jsonb,
 restored_fact_ids uuid[] not null default '{}',
 deleted_fact_ids uuid[] not null default '{}',
 kept_fact_ids uuid[] not null default '{}',
 result jsonb not null,
 revoked_at timestamptz not null default clock_timestamp()
);
alter table public.product_spec_research_revocations enable row level security;
revoke all on public.product_spec_research_revocations from public,anon,authenticated,service_role;

create or replace function public.revoke_product_spec_research_application_v1(p_application_id uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pg_temp'
as $function$
declare
 tenant uuid:=public.user_tenant_id(); actor uuid:=auth.uid();
 application public.product_spec_research_applications%rowtype;
 receipt public.product_spec_research_receipts%rowtype;
 revocation public.product_spec_research_revocations%rowtype;
 product_row public.products%rowtype; product_after public.products%rowtype;
 before_state jsonb; after_state jsonb; current_obs jsonb; applied_obs jsonb; archived_obs jsonb;
 fid uuid; restored uuid[]:='{}'; deleted uuid[]:='{}'; kept uuid[]:='{}'; missing uuid[]:='{}';
 identity_restored text[]:='{}'; command jsonb; before_product jsonb; after_product jsonb; k text;
 result jsonb;
begin
 if tenant is null or actor is null then
  raise exception 'Authenticated tenant required' using errcode='42501';
 end if;
 if length(btrim(coalesce(p_reason,'')))<8 then
  raise exception 'La revocación necesita un motivo' using errcode='22023';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(tenant::text||':spec_research:'||p_application_id::text,0));
 select * into application from public.product_spec_research_applications
  where id=p_application_id and tenant_id=tenant and actor_id=actor for update;
 if not found then raise exception 'Aplicación no disponible' using errcode='42501'; end if;
 select * into revocation from public.product_spec_research_revocations where application_id=application.id;
 if found then return revocation.result||jsonb_build_object('replayed',true); end if;
 if application.revoked_at is not null then
  raise exception 'Aplicación revocada sin recibo de revocación' using errcode='23514';
 end if;
 select * into receipt from public.product_spec_research_receipts where application_id=application.id;
 if not found then
  -- Registered, never applied: close it so the applier can never run it.
  update public.product_spec_research_applications
   set revoked_at=clock_timestamp(), revoked_by=actor, revoked_reason=btrim(p_reason) where id=application.id;
  result:=jsonb_build_object('application_id',application.id,'tenant_id',tenant,'actor_id',actor,'product_id',null,
   'applied',false,'restored_fact_ids','[]'::jsonb,'deleted_fact_ids','[]'::jsonb,'kept_fact_ids','[]'::jsonb,
   'missing_fact_ids','[]'::jsonb,'identity_restored','[]'::jsonb,'replayed',false);
  insert into public.product_spec_research_revocations(application_id,tenant_id,actor_id,product_id,reason,result)
   values(application.id,tenant,actor,null,btrim(p_reason),result);
  return result;
 end if;
 if receipt.tenant_id<>tenant or receipt.actor_id<>actor then
  raise exception 'Recibo de aplicación inconsistente' using errcode='23514';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(tenant::text||':spec_fact:'||receipt.product_id::text,0));
 select * into product_row from public.products where id=receipt.product_id and tenant_id=tenant for update;
 if not found then raise exception 'Producto no disponible para este tenant' using errcode='42501'; end if;
 lock table public.spec_templates,public.spec_template_fields,public.spec_definitions,
  public.spec_definition_values,public.category_tech_mappings,public.product_spec_references in share mode;
 perform 1 from public.spec_facts where tenant_id=tenant and subject_type='product' and subject_id=product_row.id for update;
 before_state:=public.get_product_spec_research_snapshot_v1(product_row.id);
 foreach fid in array receipt.changed_fact_ids loop
  select o into current_obs from jsonb_array_elements(before_state->'observations') o where (o#>>'{fact,id}')::uuid=fid;
  select o into applied_obs from jsonb_array_elements(receipt.after_snapshot->'observations') o where (o#>>'{fact,id}')::uuid=fid;
  select o into archived_obs from jsonb_array_elements(receipt.before_snapshot->'observations') o where (o#>>'{fact,id}')::uuid=fid;
  if current_obs is null then missing:=array_append(missing,fid); continue; end if;
  -- Only what the application wrote and nobody touched since goes back.
  if applied_obs is null or current_obs->>'fact_sha256' is distinct from applied_obs->>'fact_sha256' then
   kept:=array_append(kept,fid); continue;
  end if;
  delete from public.spec_fact_readings where fact_id=fid;
  delete from public.spec_fact_values where fact_id=fid;
  if archived_obs is null then
   delete from public.spec_facts where id=fid and tenant_id=tenant;
   deleted:=array_append(deleted,fid);
  else
   update public.spec_facts set
    value_number=(archived_obs#>>'{fact,value_number}')::numeric,
    value_boolean=(archived_obs#>>'{fact,value_boolean}')::boolean,
    value_text=archived_obs#>>'{fact,value_text}',
    value_json=(archived_obs#>>'{fact,value_json_text}')::jsonb,
    source=archived_obs#>>'{fact,source}',
    confirmed=coalesce((archived_obs#>>'{fact,confirmed}')::boolean,false),
    updated_at=clock_timestamp()
   where id=fid and tenant_id=tenant;
   insert into public.spec_fact_values(fact_id,value_id,position)
    select fid,(o->>'value_id')::uuid,(o->>'position')::integer
    from jsonb_array_elements(coalesce(archived_obs->'options','[]'::jsonb)) o;
   -- Readings were archived exactly by the applier; an archive of another
   -- shape is not guessed at.
   insert into public.spec_fact_readings
    select r.* from jsonb_array_elements(coalesce(archived_obs->'readings','[]'::jsonb)) o
    cross join lateral jsonb_populate_record(null::public.spec_fact_readings, o) r
    where o ? 'fact_id' and o ? 'quote' and o ? 'definition_id';
   restored:=array_append(restored,fid);
  end if;
 end loop;
 command:=application.command_text::jsonb;
 before_product:=receipt.before_product_text::jsonb; after_product:=receipt.after_product_text::jsonb;
 for k in select jsonb_object_keys(coalesce(command->'identity_patch','{}'::jsonb)) loop
  if k in ('model','manufacturer_sku','gtin')
   and to_jsonb(product_row)->k is not distinct from after_product->k
   and after_product->k is distinct from before_product->k then
   execute format('update public.products set %I=$1, updated_at=clock_timestamp() where id=$2 and tenant_id=$3', k)
    using (before_product->>k), product_row.id, tenant;
   identity_restored:=array_append(identity_restored,k);
  end if;
 end loop;
 if after_product->'spec_reference_id' is distinct from before_product->'spec_reference_id'
  and to_jsonb(product_row)->'spec_reference_id' is not distinct from after_product->'spec_reference_id' then
  update public.products set spec_reference_id=(before_product->>'spec_reference_id')::uuid, updated_at=clock_timestamp()
   where id=product_row.id and tenant_id=tenant;
  identity_restored:=array_append(identity_restored,'spec_reference_id');
 end if;
 perform public.spec_validate_product_internal_v1(product_row.id);
 after_state:=public.get_product_spec_research_snapshot_v1(product_row.id);
 select * into product_after from public.products where id=product_row.id and tenant_id=tenant;
 update public.product_spec_research_applications
  set revoked_at=clock_timestamp(), revoked_by=actor, revoked_reason=btrim(p_reason) where id=application.id;
 result:=jsonb_build_object('application_id',application.id,'tenant_id',tenant,'actor_id',actor,
  'product_id',product_row.id,'applied',true,
  'before_snapshot_sha256',before_state->'snapshot_sha256','after_snapshot_sha256',after_state->'snapshot_sha256',
  'restored_fact_ids',to_jsonb(restored),'deleted_fact_ids',to_jsonb(deleted),'kept_fact_ids',to_jsonb(kept),
  'missing_fact_ids',to_jsonb(missing),'identity_restored',to_jsonb(identity_restored),
  'revision',product_after.spec_revision,'replayed',false);
 insert into public.product_spec_research_revocations(application_id,tenant_id,actor_id,product_id,reason,
  before_snapshot,after_snapshot,restored_fact_ids,deleted_fact_ids,kept_fact_ids,result)
  values(application.id,tenant,actor,product_row.id,btrim(p_reason),before_state,after_state,restored,deleted,kept,result);
 return result;
end $function$;
revoke all on function public.revoke_product_spec_research_application_v1(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.revoke_product_spec_research_application_v1(uuid,text) to authenticated;

-- The actor reads back its own revocation receipt (without the snapshots).
create or replace function public.get_product_spec_research_revocation_v1(p_application_id uuid)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','public','pg_temp'
as $$
 select (to_jsonb(r)-'before_snapshot'-'after_snapshot')
 from public.product_spec_research_revocations r
 join public.product_spec_research_applications a on a.id=r.application_id
 where r.application_id=p_application_id and r.tenant_id=public.user_tenant_id() and a.actor_id=auth.uid()
$$;
revoke all on function public.get_product_spec_research_revocation_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_product_spec_research_revocation_v1(uuid) to authenticated;
commit;
