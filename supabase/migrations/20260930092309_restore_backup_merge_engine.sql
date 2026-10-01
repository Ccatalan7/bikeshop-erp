-- C2 integrated recovery by difference, 2026-09-30.
-- Public entrypoints are new: existing legacy restore and all APPLIED files stay
-- immutable. The Flutter caller selects this merge contract only after rollout.
-- No DELETE of business data, trigger disabling, GUC authority or purge bypass.
-- Existing rows receive only present, changed columns; omitted columns and
-- live-only rows survive. INSERT uses explicit columns and their real defaults.
-- Unknown trigger effects, new Auth/global links and dependent rebindings are
-- refused before writing. This is an integrated conservative engine, not proof
-- of full C2 coverage: effectful recovery/dependent capture remain open.
-- DDL recovery: revoke new RPC EXECUTE in a reviewed forward; never re-enable
-- destructive legacy replay. Runtime constraint/timeout failure rolls back the
-- whole invocation. Locks serialize only the reviewed write scope and parents.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Snapshots contain PostgreSQL-generated values. They are observations, never
-- input columns: keep the snapshot immutable and strip them only from this
-- invocation's working JSON. The database recomputes them on an actual change.
create or replace function public.backup_merge_payload_internal(p_data jsonb)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_scope record;
  v_generated text[];
  v_rows jsonb;
begin
  if jsonb_typeof(p_data) is distinct from 'object' then
    raise exception 'Invalid recovery payload' using errcode = '22023';
  end if;
  for v_scope in select * from public.restore_backup_covered_scope() loop
    if not (p_data ? v_scope.table_name)
       or p_data -> v_scope.table_name = 'null'::jsonb then continue; end if;
    if jsonb_typeof(p_data -> v_scope.table_name) is distinct from 'array' then
      raise exception 'Invalid recovery table' using errcode = '22023';
    end if;
    select coalesce(array_agg(a.attname::text), '{}'::text[]) into v_generated
      from pg_attribute a
     where a.attrelid = to_regclass(format('public.%I', v_scope.table_name))
       and a.attnum > 0 and not a.attisdropped and a.attgenerated <> '';
    if exists (select 1 from jsonb_array_elements(p_data -> v_scope.table_name) x(value)
               where jsonb_typeof(x.value) is distinct from 'object') then
      raise exception 'Invalid recovery row' using errcode = '22023';
    end if;
    -- Portal identity is current authorization, not recoverable contact data.
    -- Existing customers keep their live link even if it was added after the
    -- snapshot. A missing customer's stored Auth link remains input and fails
    -- closed in the new-reference checker; this never rebinds an identity.
    select coalesce(jsonb_agg(case when v_scope.table_name = 'customers'
        and exists (select 1 from public.customers c
          where c.id = (x.value ->> 'id')::uuid
            and c.tenant_id = (x.value ->> 'tenant_id')::uuid)
        then x.value - v_generated - 'auth_user_id'
        else x.value - v_generated end order by x.ord), '[]'::jsonb)
      into v_rows from jsonb_array_elements(p_data -> v_scope.table_name) with ordinality x(value,ord);
    p_data := jsonb_set(p_data, array[v_scope.table_name], v_rows);
  end loop;
  return p_data;
end;
$function$;

-- Inspect the actual stored expression tree, including operator functions.
-- pg_depend alone misses pinned builtins such as random()/nextval(). Unknown
-- user functions and volatile expressions fail closed. INSERT defaults also
-- admit only the builtin clock and UUID generators, which do not write data.
create or replace function public.backup_merge_expression_safe_internal(
  p_expression pg_node_tree, p_default boolean default false
) returns boolean
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select p_expression is null or (
    p_expression::text !~ 'NEXTVALUEEXPR|SUBLINK|SUBPLAN|ROWCOMPAREEXPR|COERCETODOMAIN|COERCEVIAIO'
    and not exists (
      select 1 from (
        select (m[1])::oid as function_oid
          from regexp_matches(p_expression::text, ':(?:funcid|opfuncid) ([0-9]+)', 'g') m
         where (m[1])::oid <> 0
        union
        select o.oprcode::oid
          from regexp_matches(p_expression::text, ':opno ([0-9]+)', 'g') m
          join pg_operator o on o.oid = (m[1])::oid
      ) calls left join pg_proc p on p.oid = calls.function_oid
      where p.oid is null or p.pronamespace <> 'pg_catalog'::regnamespace
         or (p.provolatile <> 'i' and not (p_default and p.oid in (
           'pg_catalog.now()'::regprocedure, 'pg_catalog.gen_random_uuid()'::regprocedure)))
    )
  )
$function$;

create or replace function public.backup_merge_relation_plan_internal(
  p_relation regclass,
  p_rows jsonb,
  p_tenant_id uuid
) returns jsonb
language plpgsql stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set timezone to 'UTC'
as $function$
declare
  v_name text;
  v_namespace oid;
  v_relation text;
  v_scope text;
  v_pk text[];
  v_columns text[];
  v_required text[];
  v_insert_required text[];
  v_defaults text[];
  v_generated text[];
  v_identity text[];
  v_cte text;
  v_count bigint;
  v_counts jsonb;
begin
  if p_tenant_id is null or jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'A tenant and an array of backup rows are required'
      using errcode = '22023';
  end if;

  select c.relname, c.relnamespace, format('%I.%I', n.nspname, c.relname)
    into v_name, v_namespace, v_relation
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where c.oid = p_relation and c.relkind in ('r', 'p');
  if v_namespace = 'public'::regnamespace then
    select replace(s.predicate, 'p_tenant_id', '$1') into v_scope
      from public.restore_backup_covered_scope() s
     where s.table_name = v_name;
  end if;
  if v_scope is null then
    raise exception 'The relation is outside the closed backup scope'
      using errcode = '22023';
  end if;
  -- Validate type input before jsonb_populate_record can invoke it. Domain or
  -- custom input functions are outside this recovery contract, even when the
  -- later integrity check would refuse the write.
  if exists (select 1 from pg_attribute a join pg_type t on t.oid = a.atttypid
              where a.attrelid = p_relation and a.attnum > 0 and not a.attisdropped
                and not ((t.typnamespace = 'pg_catalog'::regnamespace and t.typtype = 'b')
                      or t.typtype = 'e')) then
    raise exception 'Unreviewed recovery input type' using errcode = '22023';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_attribute a
     where a.attrelid = p_relation and a.attname = 'tenant_id'
       and a.atttypid = 'uuid'::regtype and not a.attisdropped
  ) then
    raise exception 'The planner requires an explicit UUID tenant column'
      using errcode = '22023';
  end if;

  select array_agg(a.attname::text order by key.ord) into v_pk
    from pg_catalog.pg_constraint c
    cross join lateral unnest(c.conkey) with ordinality key(attnum, ord)
    join pg_catalog.pg_attribute a
      on a.attrelid = c.conrelid and a.attnum = key.attnum
   where c.conrelid = p_relation and c.contype = 'p';
  if v_pk is null then
    raise exception 'The relation has no primary key'
      using errcode = '22023';
  end if;

  select array_agg(a.attname::text order by a.attnum),
         coalesce(array_agg(a.attname::text) filter (
           where a.attnotnull and a.attgenerated = ''), '{}'::text[]),
         coalesce(array_agg(a.attname::text) filter (
           where a.attnotnull and not a.atthasdef
             and a.attidentity = '' and a.attgenerated = ''), '{}'::text[]),
         coalesce(array_agg(a.attname::text) filter (
           where a.atthasdef and a.attgenerated = ''), '{}'::text[]),
         coalesce(array_agg(a.attname::text) filter (
           where a.attgenerated <> ''), '{}'::text[]),
         coalesce(array_agg(a.attname::text) filter (
           where a.attidentity = 'a'), '{}'::text[])
    into v_columns, v_required, v_insert_required, v_defaults,
         v_generated, v_identity
    from pg_catalog.pg_attribute a
   where a.attrelid = p_relation and a.attnum > 0 and not a.attisdropped;

  if exists (select 1 from jsonb_array_elements(p_rows) row(value)
             where jsonb_typeof(row.value) is distinct from 'object') then
    raise exception 'A backup row is not an object' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_rows) row(value)
    cross join lateral jsonb_object_keys(row.value) field(name)
    where not (field.name = any(v_columns))
       or field.name = any(v_generated)
  ) then
    raise exception 'Unknown or generated columns cannot be replayed'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_rows) row(value)
    cross join unnest(v_pk || array['tenant_id']) field(name)
    where not (row.value ? field.name) or row.value -> field.name = 'null'::jsonb
  ) then
    raise exception 'A backup row is missing its identity or tenant'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_rows) row(value)
    cross join unnest(v_required) field(name)
    where row.value -> field.name = 'null'::jsonb
  ) then
    raise exception 'Explicit NULL violates a required column'
      using errcode = '22023';
  end if;

  -- Type conversion canonicalizes PKs and values (UUID case, numeric and
  -- timestamp spelling). It does not apply a column default. Presence is
  -- carried separately so an omitted value never becomes a NULL update.
  v_cte := format($sql$
    with incoming as materialized (
      select row.value as raw,
             to_jsonb(jsonb_populate_record(null::%1$s, row.value)) as typed
      from jsonb_array_elements($2) row(value)
    ), backed as materialized (
      select incoming.*,
        (select jsonb_object_agg(field.name, incoming.typed -> field.name)
         from unnest($3::text[]) field(name)) as identity
      from incoming
    ), live as materialized (
      select to_jsonb(row) as typed,
        (select jsonb_object_agg(field.name, to_jsonb(row) -> field.name)
         from unnest($3::text[]) field(name)) as identity
      from %1$s row where %2$s
    )
  $sql$, v_relation, v_scope);

  execute v_cte || 'select count(*) from backed
    where (typed ->> ''tenant_id'')::uuid is distinct from $1'
    into v_count using p_tenant_id, p_rows, v_pk;
  if v_count > 0 then
    raise exception 'A backup row belongs to another tenant'
      using errcode = '22023';
  end if;
  execute v_cte || 'select count(*) from (
    select identity from backed group by identity having count(*) > 1
  ) duplicates' into v_count using p_tenant_id, p_rows, v_pk;
  if v_count > 0 then
    raise exception 'Duplicate typed primary keys in the backup'
      using errcode = '22023';
  end if;

  -- A UUID already owned outside this tenant/parent scope is a conflict,
  -- never an INSERT candidate. Do not return the conflicting identity/data.
  execute v_cte || format($sql$
    select count(*) from backed b join %1$s row on b.identity =
      (select jsonb_object_agg(field.name, to_jsonb(row) -> field.name)
       from unnest($3::text[]) field(name))
    where not coalesce((%2$s), false)
  $sql$, v_relation, v_scope)
    into v_count using p_tenant_id, p_rows, v_pk;
  if v_count > 0 then
    raise exception 'A backed identity exists outside the selected scope'
      using errcode = '22023';
  end if;
  execute v_cte || 'select count(*) from live
    where (typed ->> ''tenant_id'')::uuid is distinct from $1'
    into v_count using p_tenant_id, p_rows, v_pk;
  if v_count > 0 then
    raise exception 'The live parent scope crosses tenant boundaries'
      using errcode = '22023';
  end if;
  execute v_cte || 'select count(*) from backed b
    left join live l using (identity)
    where l.identity is null and not (b.raw ?& $4::text[])'
    into v_count using p_tenant_id, p_rows, v_pk, v_insert_required;
  if v_count > 0 then
    raise exception 'A new row omits a required column without a default'
      using errcode = '22023';
  end if;

  execute v_cte || $sql$
    , compared as (
      select b.raw, b.identity as backed_identity, l.identity as live_identity,
        case when b.identity is not null and l.identity is not null then
          exists (select 1 from jsonb_object_keys(b.raw) field(name)
                  where field.name <> 'updated_at'
                    and b.typed -> field.name is distinct from l.typed -> field.name)
          else false end as changed
      from backed b full join live l using (identity)
    )
    select jsonb_build_object(
      'backup_rows', count(backed_identity),
      'live_rows', count(live_identity),
      'unchanged', count(*) filter (where backed_identity is not null
        and live_identity is not null and not changed),
      'update_candidates', count(*) filter (where changed),
      'insert_candidates', count(*) filter (where live_identity is null),
      'live_only', count(*) filter (where backed_identity is null),
      'insert_rows_using_defaults', count(*) filter (where live_identity is null
        and not (raw ?& $4::text[])),
      'matched_rows_with_omitted_columns', count(*) filter (
        where backed_identity is not null and live_identity is not null
          and not (raw ?& $5::text[])),
      'insert_rows_with_always_identity', count(*) filter (
        where live_identity is null and raw ?| $6::text[])
    ) from compared
  $sql$ into v_counts using p_tenant_id, p_rows, v_pk, v_defaults,
    array(select field.name from unnest(v_columns) field(name)
          where not (field.name = any(v_generated))), v_identity;

  return v_counts || jsonb_build_object(
    'table', v_name, 'primary_key', to_jsonb(v_pk),
    'can_restore', false, 'read_only', true,
    'live_only_policy', 'preserve_pending_review',
    'parent_scope_checked', false, 'effects_isolated', false
  );
end;
$function$;

-- Read the candidate final rows under the preserve-live policy. A backed row
-- overlays its present fields on its live identity; retaining the old and new
-- parent side by side would incorrectly validate a changed UNIQUE key.
create or replace function public.backup_merge_effective_rows_internal(
  p_relation regclass, p_rows jsonb, p_tenant_id uuid
) returns table(row_data jsonb, missing_defaults text[], backed boolean)
language plpgsql stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set timezone to 'UTC'
as $function$
declare
  v_relation text;
  v_pk text[];
  v_defaults text[];
begin
  select format('%I.%I', n.nspname, c.relname) into v_relation
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where c.oid = p_relation and c.relkind in ('r', 'p')
     and (n.nspname in ('public', 'auth'));
  if v_relation is null or jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Unsupported parent relation or row shape' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) = 0 then
    return query execute format(
      'select to_jsonb(row), ''{}''::text[], false from %s row', v_relation);
    return;
  end if;

  -- Incoming rows may only target the closed backup scope. This also rejects
  -- foreign live identity collisions.
  perform public.backup_merge_relation_plan_internal(p_relation, p_rows, p_tenant_id);
  select array_agg(a.attname::text order by k.ord) into v_pk
    from pg_catalog.pg_constraint c
    cross join lateral unnest(c.conkey) with ordinality k(attnum, ord)
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
   where c.conrelid = p_relation and c.contype = 'p';
  select coalesce(array_agg(a.attname::text) filter (
    where a.atthasdef or a.attidentity <> '' or a.attgenerated <> ''), '{}'::text[])
    into v_defaults from pg_catalog.pg_attribute a
   where a.attrelid = p_relation and a.attnum > 0 and not a.attisdropped;
  return query execute format($sql$
    with incoming as materialized (
      select raw, to_jsonb(jsonb_populate_record(null::%1$s, raw)) as typed
      from jsonb_array_elements($1) input(raw)
    ), backed as materialized (
      select incoming.*,
        (select jsonb_object_agg(k.name, typed -> k.name)
         from unnest($2::text[]) k(name)) as identity
      from incoming
    ), live as materialized (
      select to_jsonb(row) as typed,
        (select jsonb_object_agg(k.name, to_jsonb(row) -> k.name)
         from unnest($2::text[]) k(name)) as identity
      from %1$s row
    )
    select coalesce(l.typed, b.typed) || coalesce(
      (select jsonb_object_agg(k.name, b.typed -> k.name)
         from jsonb_object_keys(b.raw) k(name)
         where l.identity is null or k.name <> 'updated_at'), '{}'::jsonb),
      case when l.identity is null then
        array(select k.name from unnest($3::text[]) k(name) where not (b.raw ? k.name))
        else '{}'::text[] end,
      b.identity is not null
    from backed b full join live l using (identity)
  $sql$, v_relation) using p_rows, v_pk, v_defaults;
end;
$function$;

-- Incoming changed FK rows: Auth/global membership fails closed.
-- CHECK/UNIQUE remain active in the atomic write, with executable preflight
-- checks supplied by the merge plan below. No rows/IDs are
-- returned. Defaults with unknown final values fail closed without evaluation.
-- Native parent-to-child equality operators come from conpfeqop, rather than
-- comparing JSON spellings or assuming the FK references the parent's PK.
create or replace function public.backup_merge_fk_plan_internal(
  p_relation regclass, p_data jsonb, p_tenant_id uuid
) returns jsonb
language plpgsql stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set timezone to 'UTC'
as $function$
declare
  v_name text;
  v_relation text;
  v_rows jsonb;
  v_parent_rows jsonb;
  v_fk record;
  v_child_keys text[];
  v_parent_keys text[];
  v_join text;
  v_owned text;
  v_known_scope boolean;
  v_result jsonb := '[]'::jsonb;
  v_counts jsonb;
begin
  select c.relname, format('%I.%I', n.nspname, c.relname)
    into v_name, v_relation from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace where c.oid = p_relation;
  if p_tenant_id is null or jsonb_typeof(p_data) is distinct from 'object'
     or not (p_data ? v_name) then
    raise exception 'A tenant and an explicit backed table are required' using errcode = '22023';
  end if;
  v_rows := p_data -> v_name;
  if v_rows = 'null'::jsonb then v_rows := '[]'::jsonb; end if;
  perform public.backup_merge_relation_plan_internal(p_relation, v_rows, p_tenant_id);

  for v_fk in
    select c.*, p.relname as parent_name, n.nspname as parent_schema,
      format('%I.%I', n.nspname, p.relname) as parent_relation,
      exists (
        select 1 from public.restore_backup_covered_scope() s
        where p.relnamespace = 'public'::regnamespace and s.table_name = p.relname
      ) as parent_backed_allowed
    from pg_catalog.pg_constraint c join pg_catalog.pg_class p on p.oid = c.confrelid
    join pg_catalog.pg_namespace n on n.oid = p.relnamespace
    where c.conrelid = p_relation and c.contype = 'f' order by c.conname
  loop
    if v_fk.confmatchtype not in ('s', 'f') then
      raise exception 'Unsupported foreign key MATCH mode' using errcode = '22023';
    end if;
    select array_agg(child.attname::text order by k.ord),
      array_agg(parent.attname::text order by k.ord),
      string_agg(format('p.%I OPERATOR(%I.%s) c.%I', parent.attname,
        ops.nspname, op.oprname, child.attname), ' and ' order by k.ord)
      into v_child_keys, v_parent_keys, v_join
      from unnest(v_fk.conkey, v_fk.confkey, v_fk.conpfeqop)
        with ordinality k(child_num, parent_num, operator_oid, ord)
      join pg_catalog.pg_attribute child on child.attrelid = p_relation and child.attnum = k.child_num
      join pg_catalog.pg_attribute parent on parent.attrelid = v_fk.confrelid and parent.attnum = k.parent_num
      join pg_catalog.pg_operator op on op.oid = k.operator_oid
      join pg_catalog.pg_namespace ops on ops.oid = op.oprnamespace;
    v_parent_rows := case when v_fk.parent_backed_allowed and p_data ? v_fk.parent_name
      then p_data -> v_fk.parent_name else '[]'::jsonb end;
    if v_parent_rows = 'null'::jsonb then v_parent_rows := '[]'::jsonb; end if;
    v_known_scope := true;
    if exists (select 1 from pg_catalog.pg_attribute a
               where a.attrelid = v_fk.confrelid and a.attname = 'tenant_id'
                 and a.atttypid = 'uuid'::regtype and not a.attisdropped) then
      v_owned := 'p.tenant_id = $1';
    elsif v_fk.parent_schema = 'public' and v_fk.parent_name = 'tenants' then
      v_owned := 'p.id = $1';
    else
      v_owned := 'false';
      v_known_scope := false;
    end if;
    -- Only a new/changed FK needs new tenant authority. An unchanged
    -- historical Auth reference is preserved, never rebound by this engine.
    select coalesce(jsonb_agg(change.raw), '[]'::jsonb) into v_rows
      from public.backup_merge_changes_internal(p_relation,
        coalesce(nullif(p_data -> v_name, 'null'::jsonb), '[]'::jsonb), p_tenant_id) change
     where change.operation = 'INSERT' or change.changed_columns && v_child_keys;
    if jsonb_array_length(v_rows) = 0 then continue; end if;
    execute format($sql$
      with children as materialized (
        select * from public.backup_merge_effective_rows_internal(%1$L::regclass, $2, $1) where backed
      ), parents as materialized (
        select * from public.backup_merge_effective_rows_internal(%2$L::regclass, $3, $1)
      ), classified as (
        select case
          when child.missing_defaults && $4::text[] then 'unresolved_default'
          when nulls.n = cardinality($4::text[]) then 'null_exempt'
          when nulls.n > 0 and %3$L = 's' then 'null_exempt'
          when nulls.n > 0 then 'partial_null'
          when exists (select 1 from parents x where x.missing_defaults && $5::text[])
            then 'unresolved_default'
          when matches.n = 0 then 'missing_parent'
          when matches.n > 1 then 'ambiguous_parent'
          when not $6::boolean then 'scope_unchecked'
          when matches.owned = 0 then 'cross_tenant_parent'
          else 'resolved' end as status
        from children child
        cross join lateral jsonb_populate_record(null::%1$s, child.row_data) c
        cross join lateral (
          select count(*) as n from unnest($4::text[]) k(name)
          where child.row_data -> k.name is null or child.row_data -> k.name = 'null'::jsonb
        ) nulls
        cross join lateral (
          select count(*) as n, count(*) filter (where %4$s) as owned
          from parents parent
          cross join lateral jsonb_populate_record(null::%2$s, parent.row_data) p
          where %5$s
        ) matches
      )
      select jsonb_build_object(
        'checked_rows', count(*),
        'resolved', count(*) filter (where status = 'resolved'),
        'null_exempt', count(*) filter (where status = 'null_exempt'),
        'missing_parent', count(*) filter (where status = 'missing_parent'),
        'cross_tenant_parent', count(*) filter (where status = 'cross_tenant_parent'),
        'scope_unchecked', count(*) filter (where status = 'scope_unchecked'),
        'partial_null', count(*) filter (where status = 'partial_null'),
        'unresolved_default', count(*) filter (where status = 'unresolved_default'),
        'ambiguous_parent', count(*) filter (where status = 'ambiguous_parent'),
        'blocked_rows', count(*) filter (where status not in ('resolved', 'null_exempt'))
      ) from classified
    $sql$, v_relation, v_fk.parent_relation, v_fk.confmatchtype, v_owned, v_join)
      into v_counts using p_tenant_id, v_rows, v_parent_rows, v_child_keys, v_parent_keys, v_known_scope;
    v_result := v_result || jsonb_build_array(v_counts || jsonb_build_object(
      'constraint', v_fk.conname, 'parent_schema', v_fk.parent_schema,
      'parent_table', v_fk.parent_name, 'match', v_fk.confmatchtype));
  end loop;
  return jsonb_build_object('constraints', v_result,
    'blocked_rows', coalesce((select sum((x ->> 'blocked_rows')::bigint)
      from jsonb_array_elements(v_result) row(x)), 0),
    'incoming_only', true, 'live_dependents_checked', false, 'can_restore', false);
end;
$function$;

-- A changed referenced UNIQUE value can strand a live child even when every
-- incoming child passed its FK check. Inspect the effective child state,
-- including uncovered tables and other tenants, without simulating CASCADE.
-- A surviving key on a different parent is a rebound requiring review, not
-- permission to silently reassign the live dependent. This checks only changes
-- to referenced columns; it is not full closure or an executable replay order.
create or replace function public.backup_merge_live_fk_plan_internal(
  p_relation regclass, p_data jsonb, p_tenant_id uuid
) returns jsonb
language plpgsql stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set timezone to 'UTC'
as $function$
declare
  v_name text;
  v_relation text;
  v_rows jsonb;
  v_pk text[];
  v_fk record;
  v_child_rows jsonb;
  v_child_keys text[];
  v_parent_keys text[];
  v_join text;
  v_prior_join text;
  v_outside_tenant text;
  v_known_scope boolean;
  v_counts jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  select c.relname, format('%I.%I', n.nspname, c.relname)
    into v_name, v_relation from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace where c.oid = p_relation;
  if p_tenant_id is null or jsonb_typeof(p_data) is distinct from 'object'
     or not (p_data ? v_name) then
    raise exception 'A tenant and an explicit backed table are required' using errcode = '22023';
  end if;
  v_rows := p_data -> v_name;
  if v_rows = 'null'::jsonb then v_rows := '[]'::jsonb; end if;
  perform public.backup_merge_relation_plan_internal(p_relation, v_rows, p_tenant_id);
  select array_agg(a.attname::text order by key.ord) into v_pk
    from pg_catalog.pg_constraint c
    cross join lateral unnest(c.conkey) with ordinality key(attnum, ord)
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = key.attnum
   where c.conrelid = p_relation and c.contype = 'p';

  for v_fk in
    select c.*, child.relname as child_name, n.nspname as child_schema,
      format('%I.%I', n.nspname, child.relname) as child_relation,
      n.nspname in ('public', 'auth') as child_read_allowed,
      exists (
        select 1 from public.restore_backup_covered_scope() s
        where n.nspname = 'public' and s.table_name = child.relname
      ) as child_backed_allowed
    from pg_catalog.pg_constraint c join pg_catalog.pg_class child on child.oid = c.conrelid
    join pg_catalog.pg_namespace n on n.oid = child.relnamespace
    where c.confrelid = p_relation and c.contype = 'f'
    order by n.nspname, child.relname, c.conname
  loop
    if not v_fk.child_read_allowed then
      raise exception 'Unsupported dependent relation' using errcode = '22023';
    end if;
    select array_agg(child.attname::text order by k.ord),
      array_agg(parent.attname::text order by k.ord),
      string_agg(format('p.%I OPERATOR(%I.%s) c.%I', parent.attname,
        ops.nspname, op.oprname, child.attname), ' and ' order by k.ord),
      string_agg(format('prior.%I OPERATOR(%I.%s) c.%I', parent.attname,
        ops.nspname, op.oprname, child.attname), ' and ' order by k.ord)
      into v_child_keys, v_parent_keys, v_join, v_prior_join
      from unnest(v_fk.conkey, v_fk.confkey, v_fk.conpfeqop)
        with ordinality k(child_num, parent_num, operator_oid, ord)
      join pg_catalog.pg_attribute child on child.attrelid = v_fk.conrelid and child.attnum = k.child_num
      join pg_catalog.pg_attribute parent on parent.attrelid = p_relation and parent.attnum = k.parent_num
      join pg_catalog.pg_operator op on op.oid = k.operator_oid
      join pg_catalog.pg_namespace ops on ops.oid = op.oprnamespace;
    -- An unchanged referenced key cannot strand or rebind a child. Avoid
    -- reading every dependent table for contact/catalogue value changes.
    if not exists (select 1 from public.backup_merge_changes_internal(p_relation, v_rows, p_tenant_id) d
                    where d.operation = 'UPDATE' and d.changed_columns && v_parent_keys) then
      continue;
    end if;
    v_child_rows := case when v_fk.child_backed_allowed and p_data ? v_fk.child_name
      then p_data -> v_fk.child_name else '[]'::jsonb end;
    if v_child_rows = 'null'::jsonb then v_child_rows := '[]'::jsonb; end if;
    v_known_scope := exists (select 1 from pg_catalog.pg_attribute a
      where a.attrelid = v_fk.conrelid and a.attname = 'tenant_id'
        and a.atttypid = 'uuid'::regtype and not a.attisdropped);
    v_outside_tenant := case when v_known_scope
      then 'c.tenant_id is distinct from $1' else 'false' end;
    execute format($sql$
      with incoming as materialized (
        select raw, to_jsonb(jsonb_populate_record(null::%1$s, raw)) as typed
        from jsonb_array_elements($2) input(raw)
      ), targets as materialized (
        select to_jsonb(p) as row_data,
          (select jsonb_object_agg(k.name, to_jsonb(p) -> k.name)
           from unnest($6::text[]) k(name)) as identity
        from %1$s p where exists (
          select 1 from incoming i
          where (select jsonb_object_agg(k.name, i.typed -> k.name)
                 from unnest($6::text[]) k(name)) =
                (select jsonb_object_agg(k.name, to_jsonb(p) -> k.name)
                 from unnest($6::text[]) k(name))
            and exists (select 1 from unnest($5::text[]) k(name)
                        where i.raw ? k.name
                          and i.typed -> k.name is distinct from to_jsonb(p) -> k.name)
        )
      ), parents as materialized (
        select * from public.backup_merge_effective_rows_internal(%1$L::regclass, $2, $1)
      ), children as materialized (
        select * from public.backup_merge_effective_rows_internal(%2$L::regclass, $3, $1)
      ), classified as (
        select case
          when child.missing_defaults && $4::text[] then 'unresolved_defaults'
          when exists (select 1 from parents x where x.missing_defaults && $5::text[])
            then 'unresolved_defaults'
          when final_matches.n = 0 then 'orphaned'
          when final_matches.n > 1 then 'ambiguous'
          when final_matches.same_identity = 0 then 'rebound'
          else 'retained' end as status,
          %3$s as outside_tenant
        from children child
        cross join lateral jsonb_populate_record(null::%2$s, child.row_data) c
        cross join lateral (
          select count(*) as n from targets target
          cross join lateral jsonb_populate_record(null::%1$s, target.row_data) p
          where %4$s
        ) old_matches
        cross join lateral (
          select count(*) as n, count(*) filter (where exists (
            select 1 from targets target
            cross join lateral jsonb_populate_record(null::%1$s, target.row_data) prior
            where %5$s and target.identity =
              (select jsonb_object_agg(k.name, to_jsonb(p) -> k.name)
               from unnest($6::text[]) k(name))
          )) as same_identity
          from parents parent
          cross join lateral jsonb_populate_record(null::%1$s, parent.row_data) p
          where %4$s
        ) final_matches
        where exists (select 1 from targets)
          and (old_matches.n > 0 or child.missing_defaults && $4::text[])
      )
      select jsonb_build_object(
        'changed_parent_key_candidates', (select count(*) from targets),
        'candidate_dependents', count(*),
        'retained_reference', count(*) filter (where status = 'retained'),
        'orphaned_candidates', count(*) filter (where status = 'orphaned'),
        'rebound_candidates', count(*) filter (where status = 'rebound'),
        'ambiguous_candidates', count(*) filter (where status = 'ambiguous'),
        'unresolved_defaults', count(*) filter (where status = 'unresolved_defaults'),
        'outside_tenant_candidates', count(*) filter (where status <> 'retained' and outside_tenant),
        'unscoped_candidates', count(*) filter (where status <> 'retained' and not $7::boolean),
        'blocked_candidates', count(*) filter (where status <> 'retained')
      ) from classified
    $sql$, v_relation, v_fk.child_relation, v_outside_tenant, v_join, v_prior_join)
      into v_counts using p_tenant_id, v_rows, v_child_rows,
        v_child_keys, v_parent_keys, v_pk, v_known_scope;
    v_results := v_results || jsonb_build_array(v_counts || jsonb_build_object(
      'constraint', v_fk.conname, 'child_schema', v_fk.child_schema,
      'child_table', v_fk.child_name, 'update_action', v_fk.confupdtype));
  end loop;
  return jsonb_build_object('constraints', v_results,
    'blocked_candidates', coalesce((select sum((x ->> 'blocked_candidates')::bigint)
      from jsonb_array_elements(v_results) row(x)), 0),
    'checked_scope', 'referenced_key_changes',
    'all_dependents_checked', false, 'cascade_simulated', false, 'can_restore', false);
end;
$function$;


-- Exact delta used by preflight and apply. No differences are inferred from
-- JSON spelling; omitted fields survive and updated_at remains live metadata.
create or replace function public.backup_merge_changes_internal(
  p_relation regclass, p_rows jsonb, p_tenant_id uuid
) returns table(raw jsonb, operation text, changed_columns text[], identity jsonb,
                effective_row jsonb, missing_defaults text[])
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set timezone to 'UTC'
as $function$
declare
  v_relation text;
  v_scope text;
  v_pk text[];
  v_defaults text[];
begin
  perform public.backup_merge_relation_plan_internal(p_relation, p_rows, p_tenant_id);
  select format('public.%I', c.relname), replace(s.predicate, 'p_tenant_id', '$1')
    into v_relation, v_scope
    from pg_class c join public.restore_backup_covered_scope() s on s.table_name = c.relname
   where c.oid = p_relation and c.relnamespace = 'public'::regnamespace;
  select array_agg(a.attname::text order by k.ord) into v_pk
    from pg_constraint c cross join lateral unnest(c.conkey) with ordinality k(n, ord)
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.n
   where c.conrelid = p_relation and c.contype = 'p';
  select coalesce(array_agg(a.attname::text) filter (
      where a.atthasdef or a.attidentity <> '' or a.attgenerated <> ''), '{}'::text[])
    into v_defaults from pg_attribute a
   where a.attrelid = p_relation and a.attnum > 0 and not a.attisdropped;
  return query execute format($sql$
    with incoming as materialized (
      select value as raw, to_jsonb(jsonb_populate_record(null::%1$s, value)) as typed
      from jsonb_array_elements($2)
    ), backed as materialized (
      select incoming.*, (select jsonb_object_agg(k, typed -> k) from unnest($3::text[]) k) as identity
      from incoming
    ), live as materialized (
      select to_jsonb(row) as typed,
        (select jsonb_object_agg(k, to_jsonb(row) -> k) from unnest($3::text[]) k) as identity
      from %1$s row where %2$s
    ), delta as (
      select b.raw, case when l.identity is null then 'INSERT' else 'UPDATE' end as operation,
        array(select k from jsonb_object_keys(b.raw) k
              where l.identity is null or (k <> 'updated_at' and b.typed -> k is distinct from l.typed -> k)
              order by k) as changed_columns,
        b.identity,
        coalesce(l.typed, b.typed) ||
          (select jsonb_object_agg(k, b.typed -> k) from jsonb_object_keys(b.raw) k) as effective_row,
        case when l.identity is null then array(select k from unnest($4::text[]) k where not (b.raw ? k))
             else '{}'::text[] end as missing_defaults
      from backed b left join live l using (identity)
    )
    select * from delta where operation = 'INSERT' or cardinality(changed_columns) > 0
    order by identity::text
  $sql$, v_relation, v_scope) using p_tenant_id, p_rows, v_pk, v_defaults;
end;
$function$;

-- Preflight evaluates current CHECKs and UNIQUE indexes without executing
-- defaults or effectful constraint functions. Actual constraints stay enabled
-- and make the write all-or-nothing if a concurrent/schema condition changes.
create or replace function public.backup_merge_integrity_internal(
  p_relation regclass, p_rows jsonb, p_tenant_id uuid
) returns boolean
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_relation text;
  v_constraint record;
  v_change record;
  v_keys text[];
  v_predicate text;
  v_columns text;
  v_count bigint;
begin
  select format('public.%I', relname) into v_relation from pg_class where oid = p_relation;
  -- Type input and stored generated expressions are part of the write path,
  -- even if a backup omits that column. Only builtin/enum scalar inputs and
  -- pure expressions are supported by this first integrated contract.
  if exists (select 1 from pg_attribute a join pg_type t on t.oid = a.atttypid
              where a.attrelid = p_relation and a.attnum > 0 and not a.attisdropped
                and not ((t.typnamespace = 'pg_catalog'::regnamespace and t.typtype = 'b')
                      or t.typtype = 'e'))
     or exists (select 1 from pg_attrdef d join pg_attribute a
                 on a.attrelid = d.adrelid and a.attnum = d.adnum
                 where d.adrelid = p_relation and a.attgenerated <> ''
                   and not public.backup_merge_expression_safe_internal(d.adbin))
     or exists (select 1 from pg_constraint c where c.conrelid = p_relation and c.contype = 'x') then
    return false;
  end if;
  for v_change in select * from public.backup_merge_changes_internal(p_relation, p_rows, p_tenant_id) loop
    if v_change.operation <> 'INSERT' then continue; end if;
    if exists (select 1 from pg_attribute a
                where a.attrelid = p_relation and a.attidentity <> '')
       or exists (select 1 from pg_attrdef d join pg_attribute a
                   on a.attrelid = d.adrelid and a.attnum = d.adnum
                   where d.adrelid = p_relation and a.attgenerated = ''
                     and a.attname::text = any(v_change.missing_defaults)
                     and not public.backup_merge_expression_safe_internal(d.adbin, true)) then
      return false;
    end if;
  end loop;
  for v_constraint in select * from pg_constraint where conrelid = p_relation and contype = 'c' loop
    if not public.backup_merge_expression_safe_internal(v_constraint.conbin) then
      return false;
    end if;
    select array_agg(attname::text) into v_keys from pg_attribute
     where attrelid = p_relation and attnum = any(v_constraint.conkey);
    for v_change in select * from public.backup_merge_changes_internal(p_relation, p_rows, p_tenant_id) loop
      if v_change.missing_defaults && coalesce(v_keys, '{}'::text[]) then return false; end if;
      execute format('select count(*) from jsonb_populate_record(null::%s, $1) row where not (%s)',
        v_relation, pg_get_expr(v_constraint.conbin, p_relation)) into v_count using v_change.effective_row;
      if v_count > 0 then return false; end if;
    end loop;
  end loop;
  for v_constraint in select i.* from pg_index i where indrelid = p_relation and indisunique loop
    select coalesce(array_agg(distinct a.attname::text), '{}'::text[]) into v_keys
      from pg_attribute a where a.attrelid = p_relation and a.attnum > 0 and not a.attisdropped
       and (a.attnum = any(v_constraint.indkey::smallint[]) or exists (
         select 1 from pg_depend d where d.classid = 'pg_class'::regclass
          and d.objid = v_constraint.indexrelid and d.refclassid = 'pg_class'::regclass
          and d.refobjid = p_relation and d.refobjsubid = a.attnum));
    -- An unchanged auth/email index cannot conflict because only the phone or
    -- address is being recovered. Changed keys are checked using the actual
    -- index expression, predicate and NULL semantics.
    if not exists (select 1 from public.backup_merge_changes_internal(p_relation,p_rows,p_tenant_id) d
                    where d.operation = 'INSERT' or d.changed_columns && v_keys) then continue; end if;
    if not public.backup_merge_expression_safe_internal(v_constraint.indexprs)
       or not public.backup_merge_expression_safe_internal(v_constraint.indpred)
       or not v_constraint.indisvalid or not v_constraint.indisready
       or exists (select 1 from unnest(v_constraint.indclass::oid[]) x(oid)
                   join pg_opclass o on o.oid = x.oid where not o.opcdefault)
       or exists (select 1 from unnest(v_constraint.indoption::smallint[]) x(options) where x.options <> 0) then
      return false;
    end if;
    select string_agg(pg_get_indexdef(v_constraint.indexrelid, k, true), ', ' order by k),
      string_agg(format('(%s) is not null', pg_get_indexdef(v_constraint.indexrelid, k, true)), ' and ' order by k)
      into v_columns, v_predicate from generate_series(1, v_constraint.indnkeyatts::integer) k;
    if exists (select 1 from public.backup_merge_effective_rows_internal(p_relation, p_rows, p_tenant_id) e
                where e.missing_defaults && v_keys) then return false; end if;
    execute format($sql$
      select count(*) from (
        select %1$s from public.backup_merge_effective_rows_internal($1, $2, $3) e
        cross join lateral jsonb_populate_record(null::%2$s, e.row_data) row
        where %3$s group by %1$s having count(*) > 1
      ) conflicts
    $sql$, v_columns, v_relation,
      '(' || coalesce(pg_get_expr(v_constraint.indpred, p_relation), 'true') || ') and (' ||
      case when v_constraint.indnullsnotdistinct then 'true' else v_predicate end || ')')
      into v_count using p_relation, p_rows, p_tenant_id;
    if v_count > 0 then return false; end if;
  end loop;
  return true;
end;
$function$;

create or replace function public.backup_merge_effects_safe_internal(
  p_relation regclass, p_rows jsonb, p_tenant_id uuid
) returns boolean
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_change record;
  v_trigger record;
  v_watched text[];
begin
  -- An absent trigger is not proof that a stock, ledger or message row is
  -- independent. This first reviewed write scope is contact/bicycle catalogue
  -- data only. Other backed tables may be compared and retained unchanged;
  -- their actual recovery requires a later reviewed domain contract.
  if p_relation not in ('public.customers'::regclass, 'public.bike_brands'::regclass,
                        'public.bike_models'::regclass) then
    return false;
  end if;
  if exists(select 1 from pg_class where oid=p_relation
             and (relkind <> 'r' or relispartition)) then return false; end if;
  for v_change in select * from public.backup_merge_changes_internal(p_relation, p_rows, p_tenant_id) loop
    if p_relation = 'public.customers'::regclass and v_change.operation = 'UPDATE'
       and v_change.changed_columns && array['tenant_id', 'auth_user_id']::text[] then
      return false;
    end if;
    -- The reviewed write scope never changes a key referenced by a live
    -- child. This prevents cascades/rebindings without locking unrelated
    -- workshop, sales, ledger or message tables during a contact recovery.
    if v_change.operation = 'UPDATE' and exists (
      select 1 from pg_constraint fk
      join pg_attribute a on a.attrelid = fk.confrelid and a.attnum = any(fk.confkey)
      where fk.contype = 'f' and fk.confrelid = p_relation
        and a.attname::text = any(v_change.changed_columns)
    ) then return false; end if;
    if exists (select 1 from pg_rewrite r where r.ev_class=p_relation
                and r.ev_enabled in ('O','A')
                and r.ev_type=case when v_change.operation='INSERT' then '3' else '2' end) then
      return false;
    end if;
    for v_trigger in
      -- The installed production definition has CRLF and the historical local
      -- fixture has LF. Normalize only that line-ending difference; all other
      -- source and declaration changes still invalidate the reviewed digest.
      select t.*, p.oid as function_oid,
        md5(replace(pg_get_functiondef(p.oid), E'\r\n', E'\n')) as definition_md5
      from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = p_relation and not t.tgisinternal and t.tgenabled in ('O', 'A')
        and ((v_change.operation = 'INSERT' and (t.tgtype::integer & 4) <> 0)
          or (v_change.operation = 'UPDATE' and (t.tgtype::integer & 16) <> 0))
    loop
      select coalesce(array_agg(a.attname::text), '{}'::text[]) into v_watched
        from unnest(v_trigger.tgattr::smallint[]) k(n)
        join pg_attribute a on a.attrelid = p_relation and a.attnum = k.n;
      if v_change.operation = 'UPDATE' and cardinality(v_watched) > 0
         and not (v_watched && v_change.changed_columns) then continue; end if;
      -- WHEN executes before the reviewed trigger body. An effectful condition
      -- is still an unreviewed write path even with a known pure trigger body.
      if not public.backup_merge_expression_safe_internal(v_trigger.tgqual) then return false; end if;
      if not (
        (v_trigger.function_oid = to_regprocedure('public.set_updated_at()')
          and v_trigger.definition_md5 = '5d26afc0bd9e881933204e17151f1f50')
        or (v_trigger.function_oid = to_regprocedure('public.guard_customer_identity_update()')
          and v_trigger.definition_md5 = '29073d53212e18fedf797228025e5dde')
      ) then return false; end if;
    end loop;
  end loop;
  return true;
end;
$function$;

create or replace function public.backup_merge_plan_internal(p_data jsonb, p_tenant_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_scope record;
  v_rows jsonb;
  v_plan jsonb;
  v_fk jsonb;
  v_impact jsonb;
  v_tables jsonb := '[]'::jsonb;
  v_blocked text[] := '{}';
  v_missing text[] := '{}';
  v_total_changed bigint := 0;
  v_effects boolean;
  v_integrity boolean;
begin
  if p_tenant_id is null or jsonb_typeof(p_data) is distinct from 'object' then
    raise exception 'Invalid recovery payload' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_data) k(name)
              where not exists (select 1 from public.restore_backup_covered_scope() s where s.table_name = k.name)) then
    return jsonb_build_object('can_restore', false, 'recovery_mode', 'merge_preserve_live',
      'message', 'El respaldo contiene datos cuyo recuperador todavía no está integrado. No se tocó nada.');
  end if;
  for v_scope in select * from public.restore_backup_covered_scope() order by ord loop
    if not (p_data ? v_scope.table_name) then
      v_missing := array_append(v_missing, v_scope.table_name); continue;
    end if;
    v_rows := coalesce(nullif(p_data -> v_scope.table_name, 'null'::jsonb), '[]'::jsonb);
    v_plan := public.backup_merge_relation_plan_internal(
      to_regclass(format('public.%I', v_scope.table_name)), v_rows, p_tenant_id);
    if (v_plan ->> 'update_candidates')::bigint + (v_plan ->> 'insert_candidates')::bigint > 0 then
      v_effects := public.backup_merge_effects_safe_internal(
        to_regclass(format('public.%I', v_scope.table_name)), v_rows, p_tenant_id);
      v_integrity := public.backup_merge_integrity_internal(
        to_regclass(format('public.%I', v_scope.table_name)), v_rows, p_tenant_id);
      v_fk := public.backup_merge_fk_plan_internal(
        to_regclass(format('public.%I', v_scope.table_name)), p_data, p_tenant_id);
      v_impact := public.backup_merge_live_fk_plan_internal(
        to_regclass(format('public.%I', v_scope.table_name)), p_data, p_tenant_id);
      if not v_effects or not v_integrity or (v_fk ->> 'blocked_rows')::bigint > 0
         or (v_impact ->> 'blocked_candidates')::bigint > 0 then
        v_blocked := array_append(v_blocked, public.restore_backup_table_label(v_scope.table_name));
      end if;
      v_total_changed := v_total_changed + (v_plan ->> 'update_candidates')::bigint
        + (v_plan ->> 'insert_candidates')::bigint;
      v_plan := v_plan || jsonb_build_object('effects_reviewed', v_effects,
        'integrity_checked', v_integrity, 'foreign_keys_checked', (v_fk ->> 'blocked_rows')::bigint = 0,
        'live_dependents_preserved', (v_impact ->> 'blocked_candidates')::bigint = 0,
        'can_restore', v_effects and v_integrity and (v_fk ->> 'blocked_rows')::bigint = 0
          and (v_impact ->> 'blocked_candidates')::bigint = 0);
    else
      v_plan := v_plan || jsonb_build_object('can_restore', true);
    end if;
    v_tables := v_tables || jsonb_build_array(v_plan);
  end loop;
  return jsonb_build_object('can_restore', cardinality(v_blocked) = 0,
    'recovery_mode', 'merge_preserve_live', 'tables', v_tables,
    'missing_tables_preserved', to_jsonb(v_missing), 'changed_rows', v_total_changed,
    'blocked_tables', to_jsonb(v_blocked), 'message', case when cardinality(v_blocked) > 0
      then 'Todavía no se puede recuperar con seguridad: ' || array_to_string(v_blocked, ', ') || '. No se tocó nada.'
      else 'Se recuperan los datos presentes en el respaldo y se conservan los registros nuevos.' end);
end;
$function$;

-- No business trigger is disabled. Every row is an INSERT or an UPDATE with
-- explicit, present columns. The entrypoint holds the reviewed write locks and
-- recomputes the plan before entering this private writer.
create or replace function public.backup_merge_apply_internal(p_data jsonb, p_tenant_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_scope record;
  v_change record;
  v_relation regclass;
  v_columns text;
  v_values text;
  v_pk_join text;
  v_written bigint;
  v_inserted bigint := 0;
  v_updated bigint := 0;
begin
  for v_scope in select * from public.restore_backup_covered_scope() order by ord desc loop
    if not (p_data ? v_scope.table_name) then continue; end if;
    v_relation := to_regclass(format('public.%I', v_scope.table_name));
    for v_change in select * from public.backup_merge_changes_internal(v_relation,
      coalesce(nullif(p_data -> v_scope.table_name, 'null'::jsonb), '[]'::jsonb), p_tenant_id) loop
      select string_agg(format('%I', k), ', ' order by k),
        string_agg(format('incoming.%I', k), ', ' order by k)
        into v_columns, v_values from unnest(v_change.changed_columns) k;
      if v_change.operation = 'INSERT' then
        execute format('insert into public.%I (%s) select %s from jsonb_populate_record(null::public.%I, $1) incoming',
          v_scope.table_name, v_columns, v_values, v_scope.table_name) using v_change.raw;
        get diagnostics v_written = row_count;
        v_inserted := v_inserted + v_written;
      else
        select string_agg(format('target.%I = incoming.%I', a.attname, a.attname), ' and ' order by k.ord)
          into v_pk_join from pg_constraint c
          cross join lateral unnest(c.conkey) with ordinality k(n, ord)
          join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.n
         where c.conrelid = v_relation and c.contype = 'p';
        execute format('update public.%I target set (%s) = (select %s) from jsonb_populate_record(null::public.%I, $1) incoming where %s',
          v_scope.table_name, v_columns, v_values, v_scope.table_name, v_pk_join) using v_change.raw;
        get diagnostics v_written = row_count;
        v_updated := v_updated + v_written;
      end if;
      if v_written <> 1 then raise exception 'Recovery identity changed' using errcode = '23514'; end if;
    end loop;
  end loop;
  return jsonb_build_object('inserted', v_inserted, 'updated', v_updated);
end;
$function$;

create or replace function public.restore_backup_merge_preflight(p_backup_id uuid, p_tenant_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare v_data jsonb;
begin
  if not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;
  select b.backup_data into v_data from public.database_backups b
   where b.id = p_backup_id and b.tenant_id = p_tenant_id and b.status = 'completed';
  if v_data is null then raise exception 'Backup access denied' using errcode = '42501'; end if;
  return public.backup_merge_plan_internal(public.backup_merge_payload_internal(v_data), p_tenant_id);
exception when data_exception or not_null_violation then
  return jsonb_build_object('can_restore', false, 'recovery_mode', 'merge_preserve_live',
    'message', 'El respaldo contiene datos que no son compatibles con el esquema actual. No se tocó nada.');
end;
$function$;

create or replace function public.restore_backup_merge(p_backup_id uuid, p_tenant_id uuid)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
set lock_timeout to '3s'
as $function$
declare
  v_data jsonb;
  v_plan jsonb;
  v_result jsonb;
  v_lock_tables text;
  v_after jsonb;
  v_target_data jsonb;
  v_snapshot_data jsonb;
begin
  if not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;
  select b.backup_data into v_data from public.database_backups b
   where b.id = p_backup_id and b.tenant_id = p_tenant_id and b.status = 'completed' for update;
  if v_data is null then raise exception 'Backup access denied' using errcode = '42501'; end if;
  v_snapshot_data := v_data;
  v_data := public.backup_merge_payload_internal(v_data);
  v_plan := public.backup_merge_plan_internal(v_data, p_tenant_id);
  if not (v_plan ->> 'can_restore')::boolean then
    return jsonb_build_object('success', false, 'backup_id', p_backup_id,
      'error_code', 'restore_merge_not_safe', 'message', v_plan ->> 'message',
      'recovery_mode', 'merge_preserve_live');
  end if;
  -- Only three reviewed tables can change, and their referenced keys never
  -- change. Lock that write scope and its direct public FK parents, not the
  -- entire store. Actual FKs stay enabled; new Auth links were already denied.
  -- OID order and the function-level timeout also cover the backup-row lock.
  with write_scope(relation) as (
    values ('public.customers'::regclass), ('public.bike_brands'::regclass),
      ('public.bike_models'::regclass)
  ), locked(relation) as (
    select relation from write_scope
    union
    select fk.confrelid from pg_constraint fk join write_scope w on w.relation = fk.conrelid
     join pg_class parent on parent.oid = fk.confrelid
     where fk.contype = 'f' and parent.relnamespace = 'public'::regnamespace
  ) select string_agg(relation::regclass::text, ', ' order by relation::oid) into v_lock_tables from locked;
  execute 'lock table ' || v_lock_tables || ' in share row exclusive mode';
  -- Recheck under writer exclusion: a preflight is advisory, never authority.
  v_data := public.backup_merge_payload_internal(v_snapshot_data);
  v_plan := public.backup_merge_plan_internal(v_data, p_tenant_id);
  if not (v_plan ->> 'can_restore')::boolean then
    return jsonb_build_object('success', false, 'backup_id', p_backup_id,
      'error_code', 'restore_merge_not_safe', 'message', v_plan ->> 'message',
      'recovery_mode', 'merge_preserve_live');
  end if;
  select coalesce(jsonb_object_agg(t ->> 'table', v_data -> (t ->> 'table')), '{}'::jsonb)
    into v_target_data from jsonb_array_elements(v_plan -> 'tables') t
   where (t ->> 'update_candidates')::bigint + (t ->> 'insert_candidates')::bigint > 0;
  v_result := public.backup_merge_apply_internal(v_target_data, p_tenant_id);
  -- The accepted present fields must match after the real INSERT/UPDATE, not
  -- merely after simulating JSON. A reviewed trigger cannot silently skip or
  -- transform the recovery while the response claims success.
  v_after := public.backup_merge_plan_internal(v_target_data, p_tenant_id);
  if coalesce((v_after ->> 'changed_rows')::bigint, -1) <> 0 then
    raise exception 'Recovery result does not match the accepted fields' using errcode = '23514';
  end if;
  update public.database_backups set restored_at = clock_timestamp(), restored_by = auth.uid(),
    restore_report = jsonb_build_object('restored_at', clock_timestamp(), 'recovery_mode', 'merge_preserve_live',
      'changed_rows', v_result, 'missing_tables_preserved', v_plan -> 'missing_tables_preserved',
      'omitted_attachments', '[]'::jsonb)
   where id = p_backup_id and tenant_id = p_tenant_id;
  return jsonb_build_object('success', true, 'backup_id', p_backup_id,
    'recovery_mode', 'merge_preserve_live', 'changed_rows', v_result,
    'message', case when (v_result ->> 'inserted')::bigint + (v_result ->> 'updated')::bigint = 0
      then 'Los datos del respaldo ya coinciden. No se modificó ningún registro.'
      else 'Datos recuperados. Los registros nuevos y sus vínculos se conservaron.' end,
    'omitted_attachments', '[]'::jsonb);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
               or data_exception then
  return jsonb_build_object('success', false, 'backup_id', p_backup_id,
    'error_code', 'restore_merge_constraint_conflict', 'recovery_mode', 'merge_preserve_live',
    'message', 'La recuperación se revirtió completa porque hay datos incompatibles. No se cambió ningún registro.');
when lock_not_available or deadlock_detected or query_canceled then
  return jsonb_build_object('success', false, 'backup_id', p_backup_id,
    'error_code', 'restore_merge_busy', 'recovery_mode', 'merge_preserve_live',
    'message', 'Hay registros en uso. No se cambió nada; vuelve a intentar cuando termine la operación en curso.');
end;
$function$;

-- All planning/writer helpers are private, including defaults automatically
-- granted to service_role by the hosted project. Only authorized admin RPCs
-- are callable by authenticated; the actual tenant membership is rechecked.
revoke all on function public.backup_merge_payload_internal(jsonb),
  public.backup_merge_expression_safe_internal(pg_node_tree,boolean),
  public.backup_merge_relation_plan_internal(regclass,jsonb,uuid),
  public.backup_merge_effective_rows_internal(regclass,jsonb,uuid),
  public.backup_merge_fk_plan_internal(regclass,jsonb,uuid),
  public.backup_merge_live_fk_plan_internal(regclass,jsonb,uuid),
  public.backup_merge_changes_internal(regclass,jsonb,uuid),
  public.backup_merge_integrity_internal(regclass,jsonb,uuid),
  public.backup_merge_effects_safe_internal(regclass,jsonb,uuid),
  public.backup_merge_plan_internal(jsonb,uuid),
  public.backup_merge_apply_internal(jsonb,uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_merge_preflight(uuid,uuid), public.restore_backup_merge(uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.restore_backup_merge_preflight(uuid,uuid), public.restore_backup_merge(uuid,uuid)
  to authenticated;

commit;
