-- C2/C3: the private copy receipt is a member of the recovered job.
-- PREPARED. Requires 170000/171000/172000 and 180000; no bytes are copied
-- or deleted. The prior reviewed scope/validators remain callable privately,
-- preserving their exact bodies; these four names are superseded here.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

alter function public.workshop_backup_scope_internal()
  rename to workshop_backup_scope_without_private_copies_internal;
create function public.workshop_backup_scope_internal()
returns table(ord integer, table_name text, predicate text)
language sql immutable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select * from public.workshop_backup_scope_without_private_copies_internal()
  union all select 200, 'workshop_legacy_asset_copies', 'tenant_id = p_tenant_id'
$function$;

alter function public.workshop_restore_tables_internal()
  rename to workshop_restore_tables_without_private_copies_internal;
create function public.workshop_restore_tables_internal()
returns table(ord integer, table_name text, policy text, root_table text, root_column text)
language sql immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select * from public.workshop_restore_tables_without_private_copies_internal()
  union all select 41, 'workshop_legacy_asset_copies', 'member', 'mechanic_jobs', 'job_id'
$function$;

alter function public.workshop_restore_trigger_review_internal()
  rename to workshop_restore_trigger_review_without_private_copies_internal;
create function public.workshop_restore_trigger_review_internal()
returns table(table_name text, trigger_name name, review text, function_md5 text)
language sql immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select * from public.workshop_restore_trigger_review_without_private_copies_internal()
  union all select 'workshop_legacy_asset_copies', 'workshop_legacy_asset_copy_guard'::name,
    'keep', 'c9cf3791c21e9f75f9acc399a647a178'
$function$;

alter function public.workshop_restore_table_label(text)
  rename to workshop_restore_table_label_without_private_copies_internal;
create function public.workshop_restore_table_label(p_table text)
returns text
language sql stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select case when p_table = 'workshop_legacy_asset_copies'
    then 'copias privadas de fotos del trabajo'
    else public.workshop_restore_table_label_without_private_copies_internal(p_table) end
$function$;

revoke all on function public.workshop_backup_scope_internal(),
  public.workshop_backup_scope_without_private_copies_internal(),
  public.workshop_restore_tables_internal(),
  public.workshop_restore_tables_without_private_copies_internal(),
  public.workshop_restore_trigger_review_internal(),
  public.workshop_restore_trigger_review_without_private_copies_internal(),
  public.workshop_restore_table_label(text),
  public.workshop_restore_table_label_without_private_copies_internal(text)
  from public, anon, authenticated, service_role;

-- Every new captured member retains a reviewed parent and its live guard.
do $contract$
begin
  if not exists (select 1 from public.workshop_restore_tables_internal()
    where table_name = 'workshop_legacy_asset_copies' and policy = 'member'
      and root_table = 'mechanic_jobs' and root_column = 'job_id')
    or public.workshop_restore_effects_review_internal(
      'public.workshop_legacy_asset_copies'::regclass) is not null then
    raise exception 'The private photo receipt recovery contract is not reviewed';
  end if;
end;
$contract$;
commit;
