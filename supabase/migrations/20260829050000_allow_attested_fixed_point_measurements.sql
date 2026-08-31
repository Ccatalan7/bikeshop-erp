begin;

-- Runtime cards legitimately carry decimal technical measurements (for
-- example a 29 x 2.25 tyre). The original attestation subset accepted only
-- integers, so the provider and inventory tools could finish successfully but
-- the terminal supply-need card failed before it reached the durable ledger.
--
-- Keep the subset deterministic across JSON.stringify and PostgreSQL jsonb:
-- fixed-point only, within JavaScript's safe range, and never a non-zero value
-- whose JavaScript representation would switch to exponent notation.
create or replace function assistant_runtime.assistant_canonical_json_internal_v1(
  p_value jsonb
)
returns text
language plpgsql
immutable
set search_path = pg_catalog, assistant_runtime, pg_temp
as $$
declare
  v_type text := jsonb_typeof(p_value);
  v_scalar text;
  v_numeric numeric;
  v_result text;
begin
  if v_type = 'null' then return 'null'; end if;
  if v_type = 'boolean' then return p_value::text; end if;
  if v_type = 'string' then return p_value::text; end if;
  if v_type = 'number' then
    v_scalar := p_value #>> '{}';
    if v_scalar !~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$' then
      raise exception 'Attested JSON number is invalid' using errcode = '22023';
    end if;
    v_numeric := v_scalar::numeric;
    if v_numeric not between -9007199254740991 and 9007199254740991
       or (v_numeric <> 0 and abs(v_numeric) < 0.000001) then
      raise exception 'Attested JSON number is invalid' using errcode = '22023';
    end if;
    return v_scalar;
  end if;
  if v_type = 'array' then
    select '[' || coalesce(string_agg(
      assistant_runtime.assistant_canonical_json_internal_v1(element.value),
      ',' order by element.ordinality
    ), '') || ']'
    into v_result
    from jsonb_array_elements(p_value) with ordinality element(value, ordinality);
    return v_result;
  end if;
  if v_type = 'object' then
    if exists (
      select 1 from jsonb_object_keys(p_value) object_key(key)
      where key !~ '^[A-Za-z0-9_]+$'
    ) then
      raise exception 'Attested JSON key is invalid' using errcode = '22023';
    end if;
    select '{' || coalesce(string_agg(
      to_jsonb(member.key)::text || ':' ||
        assistant_runtime.assistant_canonical_json_internal_v1(member.value),
      ',' order by member.key collate "C"
    ), '') || '}'
    into v_result
    from jsonb_each(p_value) member(key, value);
    return v_result;
  end if;
  raise exception 'Attested JSON value is invalid' using errcode = '22023';
end;
$$;

commit;
