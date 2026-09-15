begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
-- Preserve the component issue identity in structured error details.
do $guard$ begin if not exists(select 1 from pg_proc where oid='public.spec_validate_product_member_profiles_internal_v1(uuid)'::regprocedure and md5(pg_get_functiondef(oid)) in ('e20342ed1ea076059d9325382b58798d','51736f7297cc9dfe673e2f8df15d5bcb') and pg_get_userbyid(proowner)='postgres' and not prosecdef and provolatile='s' and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[] and proacl=array['postgres=X/postgres','service_role=X/postgres']::aclitem[]) then raise exception 'Unexpected component validation function'; end if; end $guard$;
CREATE OR REPLACE FUNCTION public.spec_validate_product_member_profiles_internal_v1(p_product_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
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
     raise exception 'Revisa la ficha de la pieza incluida' using errcode='23514', detail=issues::text;
   end if;
 end loop;
end $function$;
do $guard$ begin if not exists(select 1 from pg_proc where oid='public.spec_validate_product_member_profiles_internal_v1(uuid)'::regprocedure and md5(pg_get_functiondef(oid)) in ('51736f7297cc9dfe673e2f8df15d5bcb') and pg_get_userbyid(proowner)='postgres' and not prosecdef and provolatile='s' and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[] and proacl=array['postgres=X/postgres','service_role=X/postgres']::aclitem[]) then raise exception 'Unexpected component validation function'; end if; end $guard$;
commit;
