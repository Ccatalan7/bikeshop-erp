-- Revisión de Codex a «La marca está en el nombre» y a los destacados
-- (2026-10-11). Sin P0; lo que corrige:
--
-- P1 Deshacer confiaba en el recibo que manda la pantalla: con uno armado a
--    mano, un editor podía enlazar una marca de otro tenant. Ahora la marca
--    anterior tiene que ser global o del tenant.
-- P1 Deshacer comparaba sólo el enlace y devolvía también el texto: pisaba
--    una corrección del texto hecha después. Compara los dos.
-- P2 El comando aceptaba lo que la lista no ofrece (servicios, consumibles,
--    ocultos). Ahora pide lo mismo: un producto que hoy se vende.
-- P2 «compatible con: Shimano» pasaba el «para …» porque la expresión pedía
--    un espacio justo después. Ahora se mira sobre el texto ya partido en
--    palabras, sin puntuación.
-- P2 Una marca que es una palabra («One», «Race») se sugería sola. Además de
--    la lista medida (Doble, PRO, Velo), sólo se sugiere una marca que ya
--    usa algún producto de la tienda: las 41 de hoy la cumplían.
-- P3 «Ohlins» no calzaba con «Öhlins»: el texto pierde los acentos.
-- P2 Destacados: entre comprobar que el nuevo se vende y guardarlo, otro
--    podía apagarlo. Ahora los nuevos quedan tomados (FOR SHARE) mientras se
--    comprueban y se guardan.

create or replace function public.catalog_brand_text_v1(p_text text)
returns text
language sql
immutable
as $$
  select ' ' || btrim(regexp_replace(lower(translate(coalesce(p_text, ''),
           'ÁÀÄÂáàäâÉÈËÊéèëêÍÌÏÎíìïîÓÒÖÔóòöôÚÙÜÛúùüûÑñ',
           'AAAAaaaaEEEEeeeeIIIIiiiiOOOOooooUUUUuuuuNn')),
         '[^[:alnum:]]+', ' ', 'g')) || ' ';
$$;

create or replace function public.catalog_brand_words_v1(p_tenant_id uuid)
returns table (id uuid, name_key text)
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select b.id, btrim(public.catalog_brand_text_v1(b.name))
    from public.product_brands b
   where b.is_active
     and (b.tenant_id is null or b.tenant_id = p_tenant_id)
     and length(btrim(b.name)) >= 3
     and public.catalog_is_public_brand_v1(b.name)
     and btrim(public.catalog_brand_text_v1(b.name)) not in ('doble', 'pro', 'velo')
     and exists (
           select 1
             from public.products used
            where used.tenant_id = p_tenant_id
              and used.brand_id = b.id)
   order by (b.tenant_id is null), b.id;
$$;

create or replace function public.catalog_brand_from_words_v1(
  p_text text,
  p_ids uuid[],
  p_keys text[]
)
returns uuid
language sql
immutable
as $$
  with text_words as (
    select public.catalog_brand_text_v1(p_text) as padded
  ), named as (
    select distinct on (word.name_key) word.id
      from unnest(coalesce(p_ids, '{}'::uuid[]), coalesce(p_keys, '{}'::text[]))
             with ordinality as word(id, name_key, position),
           text_words
     where case
             when position(' ' || word.name_key || ' ' in text_words.padded) > 0
               then text_words.padded !~ (
                 ' (para|compatible con|p|tipo|estilo|replica|igual a) ([[:alnum:]]+ ){0,2}'
                 || word.name_key || ' ')
             else false
           end
     order by word.name_key, word.position
  )
  select case when count(*) = 1 then (array_agg(named.id))[1] end
    from named;
$$;

create or replace function public.catalog_apply_brand_from_name_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_changed jsonb;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);

  with target as (
    select p.id,
           p.brand_id as previous_brand_id,
           p.brand as previous_brand,
           public.catalog_brand_from_name_v1(
             p_tenant_id,
             coalesce(nullif(btrim(p.website_name), ''), p.name)) as suggestion,
           p.brand as written_brand,
           p.website_merchant_brand as merchant_brand
      from public.products p
      left join public.product_brands linked_brand
        on linked_brand.id = p.brand_id
       and linked_brand.is_active
       and (linked_brand.tenant_id is null or linked_brand.tenant_id = p.tenant_id)
     where p.tenant_id = p_tenant_id
       and p.id = any (coalesce(p_product_ids, '{}'::uuid[]))
       and coalesce(p.product_type, 'product') <> 'service'
       and public.catalog_product_web_block_v1(p, public.catalog_web_policy_v1(p_tenant_id)) is null
       and not public.catalog_is_public_brand_v1(linked_brand.name)
     for update of p
  ), changed as (
    update public.products p
       set brand_id = target.suggestion,
           brand = suggested.name
      from target
      join public.product_brands suggested on suggested.id = target.suggestion
     where p.id = target.id
       and p.tenant_id = p_tenant_id
       and public.catalog_brand_agrees_v1(target.written_brand, target.suggestion)
       and public.catalog_brand_agrees_v1(target.merchant_brand, target.suggestion)
    returning p.id, target.previous_brand_id, target.previous_brand, p.brand_id, p.brand
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', changed.id,
           'previous_brand_id', changed.previous_brand_id,
           'previous_brand', changed.previous_brand,
           'brand_id', changed.brand_id,
           'brand', changed.brand)), '[]'::jsonb)
    into v_changed
    from changed;

  return jsonb_build_object('changed', v_changed);
end;
$$;

create or replace function public.catalog_restore_brands_v1(
  p_tenant_id uuid,
  p_changed jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_restored integer;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  if jsonb_typeof(coalesce(p_changed, '[]'::jsonb)) <> 'array' then
    raise exception 'catalog_restore_invalid' using errcode = '22023';
  end if;

  update public.products p
     set brand_id = nullif(entry ->> 'previous_brand_id', '')::uuid,
         brand = left(entry ->> 'previous_brand', 200)
    from jsonb_array_elements(coalesce(p_changed, '[]'::jsonb)) entry
   where p.tenant_id = p_tenant_id
     and p.id = (entry ->> 'id')::uuid
     and p.brand_id is not distinct from nullif(entry ->> 'brand_id', '')::uuid
     and p.brand is not distinct from (entry ->> 'brand')
     and (
       nullif(entry ->> 'previous_brand_id', '') is null
       or exists (
            select 1
              from public.product_brands previous
             where previous.id = nullif(entry ->> 'previous_brand_id', '')::uuid
               and (previous.tenant_id is null or previous.tenant_id = p_tenant_id))
     );
  get diagnostics v_restored = row_count;

  return jsonb_build_object('restored', v_restored);
end;
$$;

create or replace function public.catalog_replace_featured_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_count integer;
  v_previous uuid[];
  v_name text;
  v_block text;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  perform pg_advisory_xact_lock(hashtextextended('catalog_featured:' || p_tenant_id::text, 0));

  select coalesce(array_agg(f.product_id), '{}'::uuid[])
    into v_previous
    from public.featured_products f
   where f.tenant_id = p_tenant_id;

  -- Los nuevos quedan tomados hasta guardar: nadie los cambia entre la
  -- comprobación y el insert.
  perform 1
     from public.products p
    where p.tenant_id = p_tenant_id
      and p.id = any (coalesce(p_product_ids, '{}'::uuid[]))
      and p.id <> all (v_previous)
      for share of p;

  select coalesce(nullif(btrim(p.website_name), ''), p.name),
         public.catalog_product_web_block_v1(p, public.catalog_web_policy_v1(p_tenant_id))
    into v_name, v_block
    from unnest(coalesce(p_product_ids, '{}'::uuid[])) with ordinality as requested(id, position)
    join public.products p on p.id = requested.id and p.tenant_id = p_tenant_id
   where requested.id <> all (v_previous)
     and public.catalog_product_web_block_v1(p, public.catalog_web_policy_v1(p_tenant_id)) is not null
   order by requested.position
   limit 1;

  if v_block is not null then
    raise exception 'Ya no se vende en la web: «%» (%). No se agregó a destacados.',
      v_name,
      case v_block
        when 'workshop_consumable' then 'es consumible del taller'
        when 'inactive' then 'está archivado'
        when 'web_off' then 'su venta web está apagada'
        when 'missing_tax' then 'no tiene IVA clasificado'
        when 'missing_price' then 'no tiene precio'
        when 'below_cost' then 'el precio quedó bajo el costo'
        when 'missing_image' then 'no tiene foto'
        when 'missing_web_name' then 'no tiene nombre web'
        when 'missing_description' then 'no tiene descripción'
        when 'missing_brand' then 'no tiene marca'
        when 'category_hidden' then 'su categoría no se muestra en la tienda'
        else 'no cumple la regla de venta'
      end
      using errcode = 'P0001', hint = 'catalog_featured_not_on_sale';
  end if;

  delete from public.featured_products f where f.tenant_id = p_tenant_id;

  insert into public.featured_products (tenant_id, product_id, active, order_index)
  select p_tenant_id, ranked.id, true, (row_number() over (order by ranked.first_position) - 1)::integer
    from (
      select requested.id, min(requested.position) as first_position
        from unnest(coalesce(p_product_ids, '{}'::uuid[])) with ordinality as requested(id, position)
       where requested.id is not null
       group by requested.id
    ) ranked
    join public.products p on p.id = ranked.id and p.tenant_id = p_tenant_id
   where not (coalesce(p.product_type, 'product') <> 'service'
              and p.purchase_treatment = 'workshop_consumable');
  get diagnostics v_count = row_count;

  return jsonb_build_object('featured', v_count);
end;
$$;

revoke all on function public.catalog_apply_brand_from_name_v1(uuid, uuid[]) from public, anon;
grant execute on function public.catalog_apply_brand_from_name_v1(uuid, uuid[]) to authenticated;
revoke all on function public.catalog_restore_brands_v1(uuid, jsonb) from public, anon;
grant execute on function public.catalog_restore_brands_v1(uuid, jsonb) to authenticated;
revoke all on function public.catalog_replace_featured_v1(uuid, uuid[]) from public, anon;
grant execute on function public.catalog_replace_featured_v1(uuid, uuid[]) to authenticated;
