-- LOCAL ONLY, no persistent definition or public/business DML.
begin;
set local statement_timeout = '30s';
-- Self-contained: the CLI pgTAP runner copies selected test files into
-- its container; sibling manual_checks files are not mounted there.
-- LOCAL ONLY: include inside a transaction and finish with ROLLBACK.
-- These session-local, SECURITY INVOKER helpers only SELECT candidate counts.
-- They never authorize restore, issue DML, evaluate defaults, or suppress
-- triggers. Global parent authorization, full dependent closure, business effects,
-- concurrency and volume remain
-- gates for a replacement engine. No public function or RPC is installed.

create function pg_temp.restore_relation_diff_plan(
  p_relation regclass,
  p_rows jsonb,
  p_tenant_id uuid
) returns jsonb
language plpgsql stable
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
  if v_namespace = pg_my_temp_schema() then
    v_scope := 'tenant_id = $1';
  elsif v_namespace = 'public'::regnamespace then
    select replace(s.predicate, 'p_tenant_id', '$1') into v_scope
      from public.restore_backup_covered_scope() s
     where s.table_name = v_name;
  end if;
  if v_scope is null then
    raise exception 'The relation is outside the closed backup scope'
      using errcode = '22023';
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
                  where b.typed -> field.name is distinct from l.typed -> field.name)
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
create function pg_temp.restore_effective_rows(
  p_relation regclass, p_rows jsonb, p_tenant_id uuid
) returns table(row_data jsonb, missing_defaults text[], backed boolean)
language plpgsql stable
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
     and (n.nspname in ('public', 'auth') or n.oid = pg_my_temp_schema());
  if v_relation is null or jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'Unsupported parent relation or row shape' using errcode = '22023';
  end if;
  if jsonb_array_length(p_rows) = 0 then
    return query execute format(
      'select to_jsonb(row), ''{}''::text[], false from %s row', v_relation);
    return;
  end if;

  -- Incoming rows may only target the closed backup scope or this session's
  -- temporary fixtures. This also rejects foreign live identity collisions.
  perform pg_temp.restore_relation_diff_plan(p_relation, p_rows, p_tenant_id);
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
         from jsonb_object_keys(b.raw) k(name)), '{}'::jsonb),
      case when l.identity is null then
        array(select k.name from unnest($3::text[]) k(name) where not (b.raw ? k.name))
        else '{}'::text[] end,
      b.identity is not null
    from backed b full join live l using (identity)
  $sql$, v_relation) using p_rows, v_pk, v_defaults;
end;
$function$;

-- Incoming FK rows only: CHECK/UNIQUE integrity, unchanged live dependents,
-- user membership and business effects are separate gates. No rows/IDs are
-- returned. Defaults with unknown final values fail closed without evaluation.
-- Native parent-to-child equality operators come from conpfeqop, rather than
-- comparing JSON spellings or assuming the FK references the parent's PK.
create function pg_temp.restore_relation_fk_plan(
  p_relation regclass, p_data jsonb, p_tenant_id uuid
) returns jsonb
language plpgsql stable
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
  perform pg_temp.restore_relation_diff_plan(p_relation, v_rows, p_tenant_id);

  for v_fk in
    select c.*, p.relname as parent_name, n.nspname as parent_schema,
      format('%I.%I', n.nspname, p.relname) as parent_relation,
      p.relnamespace = pg_my_temp_schema() or exists (
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
    execute format($sql$
      with children as materialized (
        select * from pg_temp.restore_effective_rows(%1$L::regclass, $2, $1) where backed
      ), parents as materialized (
        select * from pg_temp.restore_effective_rows(%2$L::regclass, $3, $1)
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
create function pg_temp.restore_live_fk_impact_plan(
  p_relation regclass, p_data jsonb, p_tenant_id uuid
) returns jsonb
language plpgsql stable
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
  perform pg_temp.restore_relation_diff_plan(p_relation, v_rows, p_tenant_id);
  select array_agg(a.attname::text order by key.ord) into v_pk
    from pg_catalog.pg_constraint c
    cross join lateral unnest(c.conkey) with ordinality key(attnum, ord)
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = key.attnum
   where c.conrelid = p_relation and c.contype = 'p';

  for v_fk in
    select c.*, child.relname as child_name, n.nspname as child_schema,
      format('%I.%I', n.nspname, child.relname) as child_relation,
      n.nspname in ('public', 'auth') or n.oid = pg_my_temp_schema() as child_read_allowed,
      n.oid = pg_my_temp_schema() or exists (
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
        select * from pg_temp.restore_effective_rows(%1$L::regclass, $2, $1)
      ), children as materialized (
        select * from pg_temp.restore_effective_rows(%2$L::regclass, $3, $1)
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

create function pg_temp.restore_backup_diff_plan(p_data jsonb, p_tenant_id uuid)
returns jsonb
language plpgsql stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_table text;
  v_rows jsonb;
  v_plans jsonb := '[]'::jsonb;
  v_missing jsonb := '[]'::jsonb;
  v_checked_plans jsonb := '[]'::jsonb;
  v_plan jsonb;
begin
  if p_tenant_id is null or jsonb_typeof(p_data) is distinct from 'object' then
    raise exception 'A tenant and a backup object are required'
      using errcode = '22023';
  end if;
  for v_table in select s.table_name from public.restore_backup_covered_scope() s
                 order by s.ord loop
    if not (p_data ? v_table) then
      v_missing := v_missing || jsonb_build_array(v_table);
      continue;
    end if;
    v_rows := p_data -> v_table;
    if v_rows = 'null'::jsonb then v_rows := '[]'::jsonb; end if;
    v_plans := v_plans || jsonb_build_array(
      pg_temp.restore_relation_diff_plan(
        to_regclass(format('public.%I', v_table)), v_rows, p_tenant_id));
  end loop;
  -- Validate all backed identities before any parent payload is interpreted.
  for v_plan in select x from jsonb_array_elements(v_plans) row(x) loop
    v_checked_plans := v_checked_plans || jsonb_build_array(v_plan ||
      jsonb_build_object('foreign_keys', pg_temp.restore_relation_fk_plan(
        to_regclass(format('public.%I', v_plan ->> 'table')), p_data, p_tenant_id),
        'live_fk_impact', pg_temp.restore_live_fk_impact_plan(
        to_regclass(format('public.%I', v_plan ->> 'table')), p_data, p_tenant_id)));
  end loop;
  return jsonb_build_object('tables', v_checked_plans, 'missing_tables', v_missing,
    'can_restore', false, 'read_only', true,
    'concurrency_checked', false, 'effects_isolated', false);
end;
$function$;

select plan(42);

create temporary table restore_plan_fixture (
  tenant_id uuid not null,
  id uuid primary key,
  content text not null,
  defaulted_value text not null default 'default-del-servidor',
  nullable_value text,
  amount numeric,
  happened_at timestamptz,
  payload jsonb
) on commit drop;
insert into restore_plan_fixture (tenant_id, id, content, amount, happened_at, payload) values
  ('00000000-0000-0000-0000-000000000010', 'aaaaaaaa-0000-0000-0000-000000000001', 'igual', 2, '2026-09-30T00:00Z', '{"nested":{"a":1,"b":2}}'),
  ('00000000-0000-0000-0000-000000000010', 'aaaaaaaa-0000-0000-0000-000000000002', 'cambiar', null, null, null),
  ('00000000-0000-0000-0000-000000000010', 'aaaaaaaa-0000-0000-0000-000000000003', 'vivo-no-respaldado', null, null, null),
  ('00000000-0000-0000-0000-000000000020', 'aaaaaaaa-0000-0000-0000-000000000020', 'otro-taller', null, null, null);

create function pg_temp.reject_restore_plan_dml() returns trigger
language plpgsql as $function$
begin
  raise exception 'The planner attempted DML' using errcode = 'P0001';
end;
$function$;
create trigger reject_restore_plan_dml before insert or update or delete
on restore_plan_fixture for each statement execute function pg_temp.reject_restore_plan_dml();

create temporary table restore_plan_result on commit drop as
select pg_temp.restore_relation_diff_plan('restore_plan_fixture'::regclass,
  '[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"AAAAAAAA-0000-0000-0000-000000000001","content":"igual","amount":"2.00","happened_at":"2026-09-29T17:00:00-07:00"},
    {"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000002","content":"del-respaldo"},
    {"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000004","content":"nuevo"}]'::jsonb,
  '00000000-0000-0000-0000-000000000010') as result;

select is(result ->> 'unchanged', '1', 'UUID/número/hora equivalentes no generan UPDATE') from restore_plan_result;
select is(result ->> 'update_candidates', '1', 'sólo el valor diferente es candidato a UPDATE') from restore_plan_result;
select is(result ->> 'insert_candidates', '1', 'sólo la identidad ausente es candidata a INSERT') from restore_plan_result;
select is(result ->> 'live_only', '1', 'la fila viva ausente se informa sin retirarla') from restore_plan_result;
select is(result ->> 'live_rows', '3', 'el otro taller queda fuera del informe') from restore_plan_result;
select is(result ->> 'insert_rows_using_defaults', '1', 'default omitido se informa sin evaluarlo') from restore_plan_result;
select is(result ->> 'matched_rows_with_omitted_columns', '2', 'columnas omitidas de filas existentes se preservan') from restore_plan_result;
select is(result ->> 'can_restore', 'false', 'el plan no autoriza restore') from restore_plan_result;
select is((select content from restore_plan_fixture where id='aaaaaaaa-0000-0000-0000-000000000002'), 'cambiar', 'el planner no ejecutó DML ni disparadores') ;

select throws_ok($test$
  select pg_temp.restore_relation_diff_plan('restore_plan_fixture',
    '[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"AAAAAAAA-0000-0000-0000-000000000001"},
      {"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000001"}]',
    '00000000-0000-0000-0000-000000000010')
$test$, '22023', 'Duplicate typed primary keys in the backup', 'duplicados tras conversión de tipos se rechazan');
select throws_ok($test$
  select pg_temp.restore_relation_diff_plan('restore_plan_fixture',
    '[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000020"}]',
    '00000000-0000-0000-0000-000000000010')
$test$, '22023', 'A backed identity exists outside the selected scope', 'identidad viva ajena no se confunde con alta');
select throws_ok($test$
  select pg_temp.restore_relation_diff_plan('restore_plan_fixture',
    '[{"tenant_id":"00000000-0000-0000-0000-000000000020","id":"aaaaaaaa-0000-0000-0000-000000000030"}]',
    '00000000-0000-0000-0000-000000000010')
$test$, '22023', 'A backup row belongs to another tenant', 'fila del respaldo de otro taller se rechaza');
select throws_ok($test$
  select pg_temp.restore_relation_diff_plan('restore_plan_fixture',
    '[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000001","unknown":1}]',
    '00000000-0000-0000-0000-000000000010')
$test$, '22023', 'Unknown or generated columns cannot be replayed', 'una clave desconocida no desaparece');
select throws_ok($test$
  select pg_temp.restore_relation_diff_plan('restore_plan_fixture',
    '[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000001","content":null}]',
    '00000000-0000-0000-0000-000000000010')
$test$, '22023', 'Explicit NULL violates a required column', 'NULL explícito inválido no se trata como omisión');
select throws_ok($test$
  select pg_temp.restore_relation_diff_plan('restore_plan_fixture',
    '[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000040"}]',
    '00000000-0000-0000-0000-000000000010')
$test$, '22023', 'A new row omits a required column without a default', 'fila nueva incompleta se rechaza');

create temporary table restore_composite_fixture (
  tenant_id uuid not null,
  conversation_id uuid not null,
  user_id uuid not null,
  primary key (conversation_id, user_id)
) on commit drop;
insert into restore_composite_fixture values
  ('00000000-0000-0000-0000-000000000010', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000002');
select is(pg_temp.restore_relation_diff_plan('restore_composite_fixture',
  '[{"tenant_id":"00000000-0000-0000-0000-000000000010","conversation_id":"aaaaaaaa-0000-0000-0000-000000000001","user_id":"aaaaaaaa-0000-0000-0000-000000000003"}]',
  '00000000-0000-0000-0000-000000000010') ->> 'insert_candidates', '1', 'PK compuesta distingue ambos participantes');

select is(pg_temp.restore_relation_diff_plan('restore_plan_fixture',
  '[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000001","payload":{"nested":{"a":1}}}]',
  '00000000-0000-0000-0000-000000000010') ->> 'update_candidates', '1', 'un objeto JSON parcialmente igual sigue siendo un cambio');

select is(jsonb_array_length(pg_temp.restore_backup_diff_plan(
  (select jsonb_object_agg(s.table_name, 'null'::jsonb) from public.restore_backup_covered_scope() s),
  '00000000-0000-0000-0000-000000000099') -> 'tables'), 38,
  'las 38 tablas y PK reales del catálogo local se planifican con sólo SELECT');
select is(jsonb_array_length(pg_temp.restore_backup_diff_plan('{}',
  '00000000-0000-0000-0000-000000000099') -> 'missing_tables'), 38,
  'tabla omitida no se interpreta como tabla vacía');
select throws_ok($test$
  select pg_temp.restore_relation_diff_plan('public.database_backups', '[]',
    '00000000-0000-0000-0000-000000000010')
$test$, '22023', 'The relation is outside the closed backup scope', 'tabla ajena al alcance no se consulta');

-- Incoming FK fixtures: only temporary tables are written; after seeding,
-- statement triggers reject any planner INSERT/UPDATE/DELETE on them.
create temporary table restore_fk_parent (
  tenant_id uuid not null,
  id uuid primary key,
  code text not null unique,
  unique (tenant_id, id)
) on commit drop;
insert into restore_fk_parent values
  ('00000000-0000-0000-0000-000000000010', 'aaaaaaaa-0000-0000-0000-000000000001', 'old-key'),
  ('00000000-0000-0000-0000-000000000020', 'aaaaaaaa-0000-0000-0000-000000000020', 'foreign-key');
create temporary table restore_fk_child (
  tenant_id uuid not null,
  id uuid primary key,
  parent_id uuid default 'aaaaaaaa-0000-0000-0000-000000000001'
    references restore_fk_parent(id)
) on commit drop;
insert into restore_fk_child values
  ('00000000-0000-0000-0000-000000000010', 'bbbbbbbb-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-000000000001');
create temporary table restore_fk_full_child (
  tenant_id uuid not null,
  id uuid primary key,
  ref_tenant uuid,
  ref_parent uuid,
  foreign key (ref_tenant, ref_parent) references restore_fk_parent(tenant_id, id) match full
) on commit drop;
create temporary table restore_fk_code_child (
  tenant_id uuid not null,
  id uuid primary key,
  parent_code text default 'old-key' references restore_fk_parent(code)
) on commit drop;
insert into restore_fk_code_child values
  ('00000000-0000-0000-0000-000000000010', 'cccccccc-0000-0000-0000-000000000001', 'old-key'),
  ('00000000-0000-0000-0000-000000000010', 'cccccccc-0000-0000-0000-000000000002', null),
  ('00000000-0000-0000-0000-000000000020', 'cccccccc-0000-0000-0000-000000000020', 'old-key');
create temporary table restore_fk_unscoped_child (
  id uuid primary key,
  parent_code text references restore_fk_parent(code)
) on commit drop;
insert into restore_fk_unscoped_child values ('dddddddd-0000-0000-0000-000000000001', 'old-key');
create temporary table restore_fk_cascade_child (
  tenant_id uuid not null,
  id uuid primary key,
  parent_code text references restore_fk_parent(code) on update cascade
) on commit drop;
insert into restore_fk_cascade_child values
  ('00000000-0000-0000-0000-000000000010', 'eeeeeeee-0000-0000-0000-000000000001', 'old-key');
create temporary table restore_fk_global_parent (id uuid primary key) on commit drop;
insert into restore_fk_global_parent values ('aaaaaaaa-0000-0000-0000-000000000001');
create temporary table restore_fk_global_child (
  tenant_id uuid not null,
  id uuid primary key,
  parent_id uuid references restore_fk_global_parent(id)
) on commit drop;

create trigger reject_restore_fk_parent_dml before insert or update or delete
on restore_fk_parent for each statement execute function pg_temp.reject_restore_plan_dml();
create trigger reject_restore_fk_child_dml before insert or update or delete
on restore_fk_child for each statement execute function pg_temp.reject_restore_plan_dml();
create trigger reject_restore_fk_full_dml before insert or update or delete
on restore_fk_full_child for each statement execute function pg_temp.reject_restore_plan_dml();
create trigger reject_restore_fk_code_dml before insert or update or delete
on restore_fk_code_child for each statement execute function pg_temp.reject_restore_plan_dml();
create trigger reject_restore_fk_unscoped_dml before insert or update or delete
on restore_fk_unscoped_child for each statement execute function pg_temp.reject_restore_plan_dml();
create trigger reject_restore_fk_cascade_dml before insert or update or delete
on restore_fk_cascade_child for each statement execute function pg_temp.reject_restore_plan_dml();
create trigger reject_restore_fk_global_parent_dml before insert or update or delete
on restore_fk_global_parent for each statement execute function pg_temp.reject_restore_plan_dml();
create trigger reject_restore_fk_global_child_dml before insert or update or delete
on restore_fk_global_child for each statement execute function pg_temp.reject_restore_plan_dml();

create function pg_temp.restore_fk_fixture_plan(
  p_child regclass, p_row jsonb, p_parents jsonb default '{}'
) returns jsonb
language sql stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select pg_temp.restore_relation_fk_plan(p_child,
    jsonb_build_object((select relname from pg_class where oid = p_child),
      jsonb_build_array(p_row)) || p_parents,
    '00000000-0000-0000-0000-000000000010')
$function$;

select is(pg_temp.restore_fk_fixture_plan('restore_fk_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","parent_id":"AAAAAAAA-0000-0000-0000-000000000001"}')
  #>> '{constraints,0,resolved}', '1', 'el padre vivo del taller resuelve la FK con tipos reales');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","parent_id":"aaaaaaaa-0000-0000-0000-000000000099"}')
  #>> '{constraints,0,missing_parent}', '1', 'padre ausente en respaldo y base se bloquea');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","parent_id":"aaaaaaaa-0000-0000-0000-000000000020"}')
  #>> '{constraints,0,cross_tenant_parent}', '1', 'la FK válida hacia otro taller se bloquea');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","parent_id":"aaaaaaaa-0000-0000-0000-000000000004"}',
  '{"restore_fk_parent":[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000004","code":"new-key"}]}')
  #>> '{constraints,0,resolved}', '1', 'el padre que sólo está en el respaldo también resuelve la FK');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000001"}')
  #>> '{constraints,0,resolved}', '1', 'FK omitida de una fila existente conserva su padre vivo');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_full_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","ref_tenant":"00000000-0000-0000-0000-000000000010","ref_parent":"aaaaaaaa-0000-0000-0000-000000000001"}')
  #>> '{constraints,0,resolved}', '1', 'FK compuesta verifica todas sus columnas');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_full_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","ref_tenant":"00000000-0000-0000-0000-000000000010","ref_parent":null}')
  #>> '{constraints,0,partial_null}', '1', 'MATCH FULL rechaza NULL parcial');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_full_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","ref_tenant":null,"ref_parent":null}')
  #>> '{constraints,0,null_exempt}', '1', 'MATCH FULL permite todas las columnas NULL');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","parent_id":null}')
  #>> '{constraints,0,null_exempt}', '1', 'MATCH SIMPLE con NULL explícito no busca un padre');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_code_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","parent_code":"old-key"}',
  '{"restore_fk_parent":[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000001","code":"changed-key"}]}')
  #>> '{constraints,0,missing_parent}', '1', 'la clave UNIQUE anterior desaparece del padre efectivo');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002"}')
  #>> '{constraints,0,unresolved_default}', '1', 'FK omitida con default de alta queda sin resolver, sin ejecutarlo');
select is(pg_temp.restore_fk_fixture_plan('restore_fk_global_child',
  '{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"bbbbbbbb-0000-0000-0000-000000000002","parent_id":"aaaaaaaa-0000-0000-0000-000000000001"}')
  #>> '{constraints,0,scope_unchecked}', '1', 'un padre global existente no demuestra autorización del taller');

create function pg_temp.restore_impact_fixture_plan(
  p_more_data jsonb default '{}', p_child text default 'restore_fk_code_child'
) returns jsonb
language sql stable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select item from jsonb_array_elements(pg_temp.restore_live_fk_impact_plan(
    'restore_fk_parent',
    '{"restore_fk_parent":[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000001","code":"changed-key"}]}'::jsonb
      || p_more_data, '00000000-0000-0000-0000-000000000010') -> 'constraints') row(item)
  where item ->> 'child_table' = p_child
$function$;

select is(pg_temp.restore_impact_fixture_plan() ->> 'orphaned_candidates', '2',
  'cambiar la clave del padre detecta dos dependientes vivos ausentes del respaldo');
select is(pg_temp.restore_impact_fixture_plan() ->> 'outside_tenant_candidates', '1',
  'el impacto no oculta el dependiente vivo de otro taller');
select is(pg_temp.restore_impact_fixture_plan('{}', 'restore_fk_unscoped_child')
  ->> 'unscoped_candidates', '1', 'dependiente sin tenant queda pendiente de revisión');
select is(pg_temp.restore_impact_fixture_plan(
  '{"restore_fk_code_child":[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"cccccccc-0000-0000-0000-000000000001","parent_code":"changed-key"}]}')
  ->> 'orphaned_candidates', '1', 'actualizar el hijo respaldado conserva sólo el bloqueo del hijo ajeno');
select is(pg_temp.restore_impact_fixture_plan(
  '{"restore_fk_code_child":[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"cccccccc-0000-0000-0000-000000000001"}]}')
  ->> 'orphaned_candidates', '2', 'FK omitida del hijo existente sigue usando su referencia viva');
select is(pg_temp.restore_impact_fixture_plan(
  '{"restore_fk_parent":[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000001"}]}')
  ->> 'changed_parent_key_candidates', '0', 'clave omitida del padre no inventa un cambio ni huérfanos');
select is(pg_temp.restore_impact_fixture_plan('{"restore_fk_code_child":[]}')
  ->> 'orphaned_candidates', '2', 'tabla hija vacía en el respaldo conserva dependientes vivos');
select is(pg_temp.restore_impact_fixture_plan(
  '{"restore_fk_parent":[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000001","code":"changed-key"},{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"aaaaaaaa-0000-0000-0000-000000000004","code":"old-key"}]}')
  ->> 'rebound_candidates', '2', 'conservar la clave en otro padre no permite reasignar hijos silenciosamente');
select is((select jsonb_build_object('action', item ->> 'update_action',
  'blocked', item ->> 'orphaned_candidates') from (
    select pg_temp.restore_impact_fixture_plan('{}', 'restore_fk_cascade_child') as item) result),
  '{"action":"c","blocked":"1"}'::jsonb,
  'ON UPDATE CASCADE se informa y no se simula como autorización para mutar hijos');
select is(pg_temp.restore_impact_fixture_plan(
  '{"restore_fk_code_child":[{"tenant_id":"00000000-0000-0000-0000-000000000010","id":"cccccccc-0000-0000-0000-000000000004"}]}')
  ->> 'unresolved_defaults', '1', 'default nuevo de FK queda irresuelto sin ejecutarlo');

select * from finish();
rollback;
