-- A tube declares its wheel size inside «Aro y ancho de neumático»
-- (`tube_fit_rows`: one row per ISO diameter with the tyre width range), so
-- the first cut of the spec facets (20260916210000) offered tubes no «Aro»
-- filter while tyres had one. The facet kernel now projects a numeric cell of
-- a rows field onto the global filterable number field of the same key:
-- `bead_seat_diameter_mm` in a tube's rows filters exactly like the tyre's
-- scalar, under the same label, with the same wheel-size wording. The
-- projection is generic (any rows column named after a filterable global
-- number field) and keeps every exclusion of the scalar path: resolved active
-- template, field not retired, unconfirmed inferences never shown.
-- Rerunnable: create or replace only.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';

create or replace function public.spec_public_facet_values_internal_v1(p_tenant_id uuid)
returns table(product_id uuid, spec_key text, spec_label text, data_type text, unit text, value_text text)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  with bound as (
    -- Facts of the product's resolved active template, field not retired,
    -- customer-visible, never an unconfirmed inference.
    select f.id as fact_id, f.subject_id, f.value_number, f.value_boolean, f.value_json,
      d.key, d.label, d.data_type, d.unit, d.is_filterable, d.validation_rules,
      t.form_contract
    from public.spec_facts f
    join public.product_spec_bindings_internal_v1 b on b.product_id = f.subject_id and b.tenant_id = f.tenant_id
    join public.spec_templates t on t.id = b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id = p_tenant_id)
    join public.spec_template_fields tf on tf.template_id = t.id and tf.spec_definition_id = f.spec_definition_id
    join public.spec_definitions d on d.id = f.spec_definition_id and d.is_customer_visible
    where f.tenant_id = p_tenant_id and f.subject_type = 'product' and f.subject_scope is null
      and coalesce(t.form_contract->'roles'->>d.key, 'primary') <> 'legacy'
      and not (f.source = 'inferred' and not coalesce(f.confirmed, false))
  ), scalar as (
    -- Options by label, numbers without trailing zeros, booleans as «Sí»/«No».
    select b.subject_id, b.key, coalesce(b.form_contract->'labels'->>b.key, b.label) as spec_label,
      b.data_type, b.unit,
      case b.data_type
        when 'number' then trim_scale(b.value_number)::text
        when 'boolean' then case when b.value_boolean then 'Sí' else 'No' end
        else v.label end as value_text
    from bound b
    left join public.spec_fact_values fv on fv.fact_id = b.fact_id
    left join public.spec_definition_values v on v.id = fv.value_id and v.is_active
    where b.is_filterable and b.data_type in ('single_select','number','boolean')
      and (b.data_type <> 'single_select' or v.label is not null)
      and (b.data_type <> 'number' or b.value_number is not null)
      and (b.data_type <> 'boolean' or b.value_boolean is not null)
  ), projected as (
    -- A numeric cell of a rows field named after a global filterable number
    -- field is that field for the visitor (a tube's ISO diameter is «Aro»).
    select b.subject_id, target.key,
      coalesce(b.form_contract->'labels'->>target.key, target.label) as spec_label,
      target.data_type, target.unit,
      case when (fit.r->'values'->>(cols.col->>'key')) ~ '^[0-9]+(\.[0-9]+)?$'
        then trim_scale((fit.r->'values'->>(cols.col->>'key'))::numeric)::text end as value_text
    from bound b
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.validation_rules->'rows_schema'->'columns') = 'array'
        then b.validation_rules->'rows_schema'->'columns' else '[]'::jsonb end
    ) as cols(col)
    join public.spec_definitions target
      on target.tenant_id is null and target.key = cols.col->>'key'
     and target.data_type = 'number' and target.is_filterable and target.is_customer_visible
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.value_json->'rows') = 'array' then b.value_json->'rows' else '[]'::jsonb end
    ) as fit(r)
    where b.data_type = 'json' and cols.col->>'type' in ('integer','decimal','number')
  )
  select subject_id, key, spec_label, data_type, unit, value_text from scalar
  union
  select subject_id, key, spec_label, data_type, unit, value_text from projected where value_text is not null
$$;
revoke all on function public.spec_public_facet_values_internal_v1(uuid) from public, anon, authenticated, service_role;
commit;
