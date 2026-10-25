-- 20261024070000: the store keeps what visitors search and do not find, and
-- the ERP edits the search's vocabulary.
--
-- 2026-10-24, owner, after the vocabulary of 20261024030000: «has la 2
-- nomás» — the store keeps each search that finds nothing and the ERP shows
-- it beside the search's words, so a missing word is added with a click.
-- Until today the vocabulary (catalog_search_terms) was written only by
-- migrations: no screen showed it, and a store could not add a word.
--
--   1. catalog_search_misses: one row per way of saying a search (as
--      catalog_search_normalize_v1 compares it), with how many times, when,
--      and how many out-of-stock products it finds. Written only by
--      catalog_search_miss_record_v1, which the public store calls when a
--      search shows nothing; it searches again itself, so only a search that
--      lists nothing in the whole store stays, and nothing that looks like
--      someone's data (an e-mail, a phone, a RUT, a link) is kept.
--   2. The ERP reads both and writes the store's own words
--      (catalog_search_vocabulary_v1, catalog_search_misses_v1,
--      catalog_search_add_words_v1, catalog_search_remove_word_v1,
--      catalog_search_miss_close_v1), with the catalog's guards.
--   3. A store's own row of a shared concept may add only a phrase («bujes
--      delanteros»): its terms may be empty.

create table if not exists public.catalog_search_misses (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  -- What the search compares (catalog_search_normalize_v1).
  term text not null,
  -- The last text as a visitor wrote it (lower case, trimmed).
  typed text not null,
  searches integer not null default 1,
  -- Products the search finds among the out of stock, at the last search:
  -- 0 is a word the store does not understand (or does not sell).
  out_of_stock integer not null default 0,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  -- «Es una palabra de…» (`word`, with the concept) or «Ignorar».
  closed_at timestamptz,
  closed_as text,
  closed_concept text,
  closed_by uuid references auth.users(id) on delete set null,
  primary key (tenant_id, term),
  constraint catalog_search_misses_counts check (searches > 0 and out_of_stock >= 0),
  constraint catalog_search_misses_closed check (
    (closed_at is null and closed_as is null and closed_concept is null)
    or (closed_at is not null and closed_as = 'ignored' and closed_concept is null)
    or (closed_at is not null and closed_as = 'word' and closed_concept is not null)
  ),
  constraint catalog_search_misses_text check (
    char_length(term) between 1 and 200 and char_length(typed) between 1 and 200
  )
);

create index if not exists catalog_search_misses_recent_idx
  on public.catalog_search_misses (tenant_id, last_seen_at desc);

comment on table public.catalog_search_misses is
  'What visitors searched in the public store and did not find (20261024070000), one row per normalized search. Written only by catalog_search_miss_record_v1; read and closed in the ERP through catalog_search_misses_v1 and catalog_search_miss_close_v1.';

alter table public.catalog_search_misses enable row level security;
revoke all on table public.catalog_search_misses from public, anon, authenticated;

alter table public.catalog_search_terms
  drop constraint if exists catalog_search_terms_terms_present;
alter table public.catalog_search_terms
  add constraint catalog_search_terms_terms_present check (
    cardinality(terms) > 0
    or (tenant_id is not null and cardinality(phrases) > 0)
  );
alter table public.catalog_search_terms
  drop constraint if exists catalog_search_terms_normalized;
alter table public.catalog_search_terms
  add constraint catalog_search_terms_normalized check (
    (cardinality(terms || broader) = 0
      or array_to_string(terms || broader, ' ') ~ '^[a-z0-9]+( [a-z0-9]+)*$')
    and array_to_string(phrases, ',') ~ '^([a-z0-9]+( [a-z0-9]+)+(,[a-z0-9]+( [a-z0-9]+)+)*)?$'
  );

-- A search the store showed nothing for. The public store calls it; it
-- decides alone what stays.
create or replace function public.catalog_search_miss_record_v1(
  p_tenant_id uuid,
  p_term text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_typed text := lower(btrim(regexp_replace(left(coalesce(p_term, ''), 400), '\s+', ' ', 'g')));
  v_key text;
  v_listed bigint;
  v_found bigint;
begin
  if p_tenant_id is null or char_length(v_typed) < 2 or char_length(v_typed) > 80 then
    return;
  end if;
  -- What could be someone's data never stays: an e-mail, a link, a phone or
  -- a RUT (seven digits or more, however they are separated), or a sentence.
  if v_typed ~ '@'
     or v_typed ~ '(https?:|www\.)'
     or regexp_replace(v_typed, '[^0-9]', '', 'g') ~ '[0-9]{7,}'
     or cardinality(string_to_array(v_typed, ' ')) > 8 then
    return;
  end if;
  if not exists (
    select 1 from public.tenants t where t.id = p_tenant_id and t.is_active is true
  ) then
    return;
  end if;
  v_key := public.catalog_search_normalize_v1(v_typed);
  if char_length(v_key) < 2 then
    return;
  end if;
  -- The store's own search says it: what it lists with its stock rule
  -- (p_only_in_stock reads the store's rule; false would widen a search to
  -- the out of stock, 20261024050000)...
  select coalesce(max(r.total_count), 0) into v_listed
    from public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_search_term := v_typed,
      p_only_in_stock := true,
      p_limit := 1
    ) r;
  if v_listed > 0 then
    return;
  end if;
  -- ...and what it would find among the out of stock.
  select coalesce(max(r.total_count), 0) into v_found
    from public.get_public_products_without_inventory_reservations(
      p_tenant_id := p_tenant_id,
      p_search_term := v_typed,
      p_only_in_stock := false,
      p_limit := 1
    ) r;

  -- A day holds at most 300 new searches per store; the ones it has keep
  -- counting.
  if not exists (
       select 1 from public.catalog_search_misses m
        where m.tenant_id = p_tenant_id and m.term = v_key
     )
     and (
       select count(*) from public.catalog_search_misses m
        where m.tenant_id = p_tenant_id
          and m.first_seen_at > now() - interval '1 day'
     ) >= 300 then
    return;
  end if;

  insert into public.catalog_search_misses as m (
    tenant_id, term, typed, out_of_stock
  ) values (
    p_tenant_id, v_key, v_typed, least(v_found, 2147483647)::integer
  )
  on conflict (tenant_id, term) do update
    set searches = least(m.searches, 2147483646) + 1,
        typed = excluded.typed,
        out_of_stock = excluded.out_of_stock,
        last_seen_at = now();

  -- Half a year is enough to tell what people look for.
  delete from public.catalog_search_misses m
   where m.tenant_id = p_tenant_id
     and m.last_seen_at < now() - interval '180 days';
end;
$function$;

revoke all on function public.catalog_search_miss_record_v1(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.catalog_search_miss_record_v1(uuid, text)
  to anon, authenticated;

-- The searches without results, the open ones first.
create or replace function public.catalog_search_misses_v1(p_tenant_id uuid)
returns table (
  term text,
  typed text,
  searches integer,
  out_of_stock integer,
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  state text,
  concept text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
#variable_conflict use_column
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);
  return query
  select
    m.term,
    m.typed,
    m.searches,
    m.out_of_stock,
    m.first_seen_at,
    m.last_seen_at,
    -- A word added that still finds nothing comes back.
    case
      when m.closed_at is null then 'open'
      when m.closed_as = 'word' and m.last_seen_at > m.closed_at then 'open'
      else m.closed_as
    end as state,
    m.closed_concept as concept
  from public.catalog_search_misses m
  where m.tenant_id = p_tenant_id
  order by
    (m.closed_at is null or (m.closed_as = 'word' and m.last_seen_at > m.closed_at)) desc,
    m.searches desc,
    m.last_seen_at desc
  limit 500;
end;
$function$;

-- The search's words: the shared ones and the store's own, by concept.
create or replace function public.catalog_search_vocabulary_v1(p_tenant_id uuid)
returns table (
  concept text,
  kind text,
  terms text[],
  own_terms text[],
  broader text[],
  phrases text[],
  own_phrases text[],
  shared boolean
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
#variable_conflict use_column
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);
  return query
  select
    coalesce(s.concept, o.concept),
    coalesce(s.kind, o.kind),
    coalesce(s.terms, '{}'::text[]),
    coalesce(o.terms, '{}'::text[]),
    coalesce(s.broader, '{}'::text[]) || coalesce(o.broader, '{}'::text[]),
    coalesce(s.phrases, '{}'::text[]),
    coalesce(o.phrases, '{}'::text[]),
    s.concept is not null
  from (
    select v.concept, v.kind, v.terms, v.broader, v.phrases
      from public.catalog_search_terms v
     where v.tenant_id is null
  ) s
  full join (
    select v.concept, v.kind, v.terms, v.broader, v.phrases
      from public.catalog_search_terms v
     where v.tenant_id = p_tenant_id
  ) o on o.concept = s.concept
  order by 1;
end;
$function$;

-- How many products a text finds now: all of them, and those the store
-- lists.
create or replace function public.catalog_search_counts_internal_v1(
  p_tenant_id uuid,
  p_text text
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
  select jsonb_build_object(
    'finds', (
      select coalesce(max(r.total_count), 0)
        from public.get_public_products_without_inventory_reservations(
          p_tenant_id := p_tenant_id,
          p_search_term := p_text,
          p_only_in_stock := false,
          p_limit := 1
        ) r
    ),
    'listed', (
      select coalesce(max(r.total_count), 0)
        from public.get_public_products(
          p_tenant_id := p_tenant_id,
          p_search_term := p_text,
          p_only_in_stock := true,
          p_limit := 1
        ) r
    )
  )
$function$;

revoke all on function public.catalog_search_counts_internal_v1(uuid, text)
  from public, anon, authenticated, service_role;

-- «Es una palabra de…»: the store's words added to a concept (a shared one,
-- or the store's own, which this creates). One word is a term, several a
-- phrase. With [p_miss_term] the search it answers is closed, and the
-- answer says how many products that search finds now.
create or replace function public.catalog_search_add_words_v1(
  p_tenant_id uuid,
  p_concept text,
  p_words text[],
  p_kind text default 'part',
  p_miss_term text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_concept text := public.catalog_search_normalize_v1(p_concept);
  v_shared public.catalog_search_terms%rowtype;
  v_own public.catalog_search_terms%rowtype;
  v_have_shared boolean;
  v_have_own boolean;
  v_known text[];
  v_terms text[] := '{}';
  v_phrases text[] := '{}';
  v_already text[] := '{}';
  v_word text;
  v_raw text;
  v_kind text;
  v_miss public.catalog_search_misses%rowtype;
  v_counts jsonb := null;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  if v_concept = '' or char_length(v_concept) > 40 then
    raise exception 'catalog_search_concept_invalid' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_words), 0) = 0 or cardinality(p_words) > 20 then
    raise exception 'catalog_search_words_invalid' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_tenant_id::text || ':catalog_search_terms:' || v_concept, 0
  ));

  select * into v_shared from public.catalog_search_terms v
   where v.tenant_id is null and v.concept = v_concept;
  v_have_shared := found;
  select * into v_own from public.catalog_search_terms v
   where v.tenant_id = p_tenant_id and v.concept = v_concept;
  v_have_own := found;

  v_known := coalesce(v_shared.terms, '{}') || coalesce(v_shared.phrases, '{}')
    || coalesce(v_shared.broader, '{}') || coalesce(v_own.terms, '{}')
    || coalesce(v_own.phrases, '{}');

  foreach v_raw in array p_words loop
    v_word := public.catalog_search_normalize_v1(v_raw);
    continue when v_word = '';
    if char_length(v_word) > 60 then
      raise exception 'catalog_search_words_invalid' using errcode = '22023';
    end if;
    if v_word = any (v_known || v_terms || v_phrases) then
      v_already := v_already || v_word;
    elsif position(' ' in v_word) > 0 then
      v_phrases := v_phrases || v_word;
    else
      v_terms := v_terms || v_word;
    end if;
  end loop;

  -- A concept of the store's own: its name is one of its words.
  if not v_have_shared and not v_have_own then
    if not (v_concept = any (v_terms || v_phrases || v_already)) then
      if position(' ' in v_concept) > 0 then
        v_phrases := v_concept || v_phrases;
      else
        v_terms := v_concept || v_terms;
      end if;
    end if;
  end if;

  if cardinality(v_terms) + cardinality(v_phrases) > 0 then
    -- The store's row speaks of the shared concept as it does.
    v_kind := coalesce(
      v_shared.kind,
      v_own.kind,
      case when p_kind = 'attribute' then 'attribute' else 'part' end
    );
    if v_have_own then
      update public.catalog_search_terms v
         set terms = v.terms || v_terms,
             phrases = v.phrases || v_phrases,
             updated_at = now()
       where v.id = v_own.id;
    else
      insert into public.catalog_search_terms (tenant_id, concept, kind, terms, phrases)
      values (p_tenant_id, v_concept, v_kind, v_terms, v_phrases);
    end if;
  end if;

  if p_miss_term is not null then
    select * into v_miss from public.catalog_search_misses m
     where m.tenant_id = p_tenant_id
       and m.term = public.catalog_search_normalize_v1(p_miss_term);
    if found then
      update public.catalog_search_misses m
         set closed_at = now(),
             closed_as = 'word',
             closed_concept = v_concept,
             closed_by = auth.uid()
       where m.tenant_id = p_tenant_id and m.term = v_miss.term;
      v_counts := public.catalog_search_counts_internal_v1(p_tenant_id, v_miss.typed);
    end if;
  end if;

  return jsonb_build_object(
    'concept', v_concept,
    'added_terms', to_jsonb(v_terms),
    'added_phrases', to_jsonb(v_phrases),
    'already', to_jsonb(v_already),
    'created', not v_have_shared and not v_have_own
  ) || coalesce(v_counts, '{}'::jsonb);
end;
$function$;

-- A word of the store's own taken out (the shared ones stay).
create or replace function public.catalog_search_remove_word_v1(
  p_tenant_id uuid,
  p_concept text,
  p_word text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_concept text := public.catalog_search_normalize_v1(p_concept);
  v_word text := public.catalog_search_normalize_v1(p_word);
  v_own public.catalog_search_terms%rowtype;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  perform pg_advisory_xact_lock(hashtextextended(
    p_tenant_id::text || ':catalog_search_terms:' || v_concept, 0
  ));
  select * into v_own from public.catalog_search_terms v
   where v.tenant_id = p_tenant_id and v.concept = v_concept;
  if not found or not (v_word = any (v_own.terms || v_own.phrases)) then
    return jsonb_build_object('removed', false);
  end if;
  v_own.terms := array_remove(v_own.terms, v_word);
  v_own.phrases := array_remove(v_own.phrases, v_word);
  -- The last word takes the store's row with it.
  if cardinality(v_own.terms) + cardinality(v_own.phrases) = 0 then
    delete from public.catalog_search_terms v where v.id = v_own.id;
  else
    update public.catalog_search_terms v
       set terms = v_own.terms, phrases = v_own.phrases, updated_at = now()
     where v.id = v_own.id;
  end if;
  return jsonb_build_object('removed', true);
end;
$function$;

-- «Ignorar» (not sold here, or written wrong) and its undo.
create or replace function public.catalog_search_miss_close_v1(
  p_tenant_id uuid,
  p_term text,
  p_ignored boolean default true
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  update public.catalog_search_misses m
     set closed_at = case when coalesce(p_ignored, true) then now() end,
         closed_as = case when coalesce(p_ignored, true) then 'ignored' end,
         closed_concept = null,
         closed_by = case when coalesce(p_ignored, true) then auth.uid() end
   where m.tenant_id = p_tenant_id
     and m.term = public.catalog_search_normalize_v1(p_term);
  return jsonb_build_object('changed', found, 'ignored', coalesce(p_ignored, true));
end;
$function$;

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.catalog_search_misses_v1(uuid)',
    'public.catalog_search_vocabulary_v1(uuid)',
    'public.catalog_search_add_words_v1(uuid, text, text[], text, text)',
    'public.catalog_search_remove_word_v1(uuid, text, text)',
    'public.catalog_search_miss_close_v1(uuid, text, boolean)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_signature);
    execute format('grant execute on function %s to authenticated', v_signature);
  end loop;
end;
$grants$;
