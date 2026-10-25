-- 20261024080000: the search's groups have a name as the shop writes it, and
-- a word joins a shared group whatever its key looks like.
--
-- 2026-10-24, the ERP's «Búsquedas» on real data (20261024070000): the groups
-- showed their keys, «Camara», «Cuentakilometros», «Liquido_freno», because
-- the vocabulary keeps the words as the search compares them (no accents).
-- And catalog_search_add_words_v1 normalized the group it was given, so a
-- word for «cinta_llanta» or «pata_de_cambio» would have made a new group
-- «cinta llanta» beside the shared one.
--
--   1. catalog_search_terms.label: the group's name, with its accents. The
--      shared groups get theirs here; a store's own group keeps the name it
--      was created with.
--   2. catalog_search_vocabulary_v1 answers it, and
--      catalog_search_add_words_v1 / catalog_search_remove_word_v1 find a
--      group by its exact key before reading the text as a new name.

alter table public.catalog_search_terms
  add column if not exists label text;
alter table public.catalog_search_terms
  drop constraint if exists catalog_search_terms_label;
alter table public.catalog_search_terms
  add constraint catalog_search_terms_label check (
    label is null or char_length(btrim(label)) between 1 and 40
  );

update public.catalog_search_terms v
   set label = names.label
  from (values
    ('abrazadera', 'Abrazadera'), ('adaptador', 'Adaptador'),
    ('amortiguador', 'Amortiguador'), ('asiento', 'Asiento'),
    ('bolso', 'Bolso'), ('cacho', 'Cacho'), ('cadena', 'Cadena'),
    ('cala', 'Calas'), ('calza', 'Calza'), ('camara', 'Cámara'),
    ('cambio', 'Cambio (desviador)'), ('canasto', 'Canasto'),
    ('candado', 'Candado'), ('caramayola', 'Caramayola'), ('casco', 'Casco'),
    ('cassette', 'Piñón (cassette)'), ('cinta_llanta', 'Cinta de llanta'),
    ('cinta_manubrio', 'Cinta de manubrio'), ('cono', 'Cono'),
    ('cuadro', 'Cuadro'), ('cubrecadena', 'Cubrecadena'),
    ('cuentakilometros', 'Cuentakilómetros'),
    ('desengrasante', 'Desengrasante'), ('desmontador', 'Desmontador'),
    ('direccion', 'Dirección'), ('disco', 'Disco de freno'), ('eje', 'Eje'),
    ('electrica', 'Eléctrica'), ('eslabon', 'Eslabón'),
    ('espaciador', 'Espaciador'), ('espejo', 'Espejo'),
    ('fixie', 'Fixie (piñón fijo)'), ('freno', 'Freno'), ('funda', 'Funda'),
    ('grasa', 'Grasa'), ('guante', 'Guantes'), ('herramienta', 'Herramienta'),
    ('hidraulico', 'Hidráulico'), ('horquilla', 'Horquilla'),
    ('infantil', 'Infantil'), ('inflador', 'Inflador'), ('lentes', 'Lentes'),
    ('liquido_freno', 'Líquido de frenos'), ('llanta', 'Llanta'),
    ('llave', 'Llave'), ('lubricante', 'Lubricante'), ('luz', 'Luz'),
    ('manilla', 'Manilla'), ('manubrio', 'Manubrio'), ('maza', 'Maza'),
    ('mecanico', 'Mecánico'), ('mochila', 'Mochila'),
    ('motor', 'Motor (pedalier)'), ('mtb', 'MTB (montaña)'),
    ('neumatico', 'Neumático'), ('niple', 'Niple'), ('parche', 'Parche'),
    ('parrilla', 'Parrilla'), ('pasante', 'Eje pasante'),
    ('pastilla', 'Pastillas de freno'), ('pata', 'Pata (atril)'),
    ('pata_de_cambio', 'Pata de cambio'), ('patin', 'Patines (zapatas)'),
    ('pedal', 'Pedal'), ('piola', 'Piola'), ('plato', 'Plato'),
    ('plegable', 'Plegable'), ('polera', 'Polera'),
    ('portacaramayola', 'Portacaramayola'), ('puno', 'Puño'),
    ('rayo', 'Rayo'), ('recargable', 'Recargable'),
    ('reflectante', 'Reflectante'), ('rodamiento', 'Rodamiento'),
    ('rodillo', 'Rodillo'), ('rueda', 'Rueda'),
    ('rueditas', 'Rueditas de apoyo'), ('ruta', 'Ruta'),
    ('scooter', 'Scooter'), ('sellante', 'Sellante'),
    ('shifter', 'Mando de cambio'), ('silla_nino', 'Silla para niño'),
    ('tapabarro', 'Tapabarro'), ('tee', 'Tee (potencia)'),
    ('telescopica', 'Tija telescópica'), ('tija', 'Tija'),
    ('timbre', 'Timbre'), ('tubeless', 'Tubeless'), ('urbana', 'Urbana'),
    ('valvula_dunlop', 'Válvula Dunlop'),
    ('valvula_presta', 'Válvula francesa (Presta)'),
    ('valvula_schrader', 'Válvula americana (auto)'),
    ('vbrake', 'V-brake'), ('volante', 'Volante (biela)')
  ) as names(concept, label)
 where v.tenant_id is null
   and v.concept = names.concept
   and v.label is distinct from names.label;

-- The group a text names: a key the store reads (shared or its own) as it
-- is, else the text as a new group's key.
create or replace function public.catalog_search_group_key_internal_v1(
  p_tenant_id uuid,
  p_concept text
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
  select coalesce(
    (select v.concept
       from public.catalog_search_terms v
      where v.concept = btrim(coalesce(p_concept, ''))
        and (v.tenant_id is null or v.tenant_id = p_tenant_id)
      limit 1),
    public.catalog_search_normalize_v1(p_concept)
  )
$function$;

revoke all on function public.catalog_search_group_key_internal_v1(uuid, text)
  from public, anon, authenticated, service_role;

drop function if exists public.catalog_search_vocabulary_v1(uuid);
create function public.catalog_search_vocabulary_v1(p_tenant_id uuid)
returns table (
  concept text,
  label text,
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
    coalesce(s.label, o.label),
    coalesce(s.kind, o.kind),
    coalesce(s.terms, '{}'::text[]),
    coalesce(o.terms, '{}'::text[]),
    coalesce(s.broader, '{}'::text[]) || coalesce(o.broader, '{}'::text[]),
    coalesce(s.phrases, '{}'::text[]),
    coalesce(o.phrases, '{}'::text[]),
    s.concept is not null
  from (
    select v.concept, v.label, v.kind, v.terms, v.broader, v.phrases
      from public.catalog_search_terms v
     where v.tenant_id is null
  ) s
  full join (
    select v.concept, v.label, v.kind, v.terms, v.broader, v.phrases
      from public.catalog_search_terms v
     where v.tenant_id = p_tenant_id
  ) o on o.concept = s.concept
  order by coalesce(s.label, o.label, s.concept, o.concept);
end;
$function$;

drop function if exists public.catalog_search_add_words_v1(uuid, text, text[], text, text);
create function public.catalog_search_add_words_v1(
  p_tenant_id uuid,
  p_concept text,
  p_words text[],
  p_kind text default 'part',
  p_miss_term text default null,
  p_label text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
declare
  v_concept text;
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
  v_label text := nullif(btrim(coalesce(p_label, '')), '');
  v_miss public.catalog_search_misses%rowtype;
  v_counts jsonb := null;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  v_concept := public.catalog_search_group_key_internal_v1(p_tenant_id, p_concept);
  if v_concept = '' or char_length(v_concept) > 40 then
    raise exception 'catalog_search_concept_invalid' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_words), 0) = 0 or cardinality(p_words) > 20 then
    raise exception 'catalog_search_words_invalid' using errcode = '22023';
  end if;
  if v_label is not null and char_length(v_label) > 40 then
    raise exception 'catalog_search_concept_invalid' using errcode = '22023';
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

  -- A group of the store's own: its name is one of its words.
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
    -- The store's row speaks of the shared group as it does.
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
      insert into public.catalog_search_terms (
        tenant_id, concept, label, kind, terms, phrases
      ) values (
        p_tenant_id, v_concept,
        -- A shared group keeps its name; a new one takes the one it was
        -- given.
        case when v_have_shared then null else v_label end,
        v_kind, v_terms, v_phrases
      );
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
  v_concept text;
  v_word text := public.catalog_search_normalize_v1(p_word);
  v_own public.catalog_search_terms%rowtype;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  v_concept := public.catalog_search_group_key_internal_v1(p_tenant_id, p_concept);
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

do $grants$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.catalog_search_vocabulary_v1(uuid)',
    'public.catalog_search_add_words_v1(uuid, text, text[], text, text, text)',
    'public.catalog_search_remove_word_v1(uuid, text, text)'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_signature);
    execute format('grant execute on function %s to authenticated', v_signature);
  end loop;
end;
$grants$;
