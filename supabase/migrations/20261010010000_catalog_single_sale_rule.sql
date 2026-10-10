-- Una sola regla decide qué se vende en vinabike.cl.
--
-- El 2026-10-09 la tienda vendía 100 consumibles del taller con «En stock»,
-- carrito y `InStock` para Google. La política de stock dejaba pasar todo lo
-- que no lleva stock (`track_stock = false`), una excepción escrita para los
-- servicios; un consumible (`purchase_treatment = 'workshop_consumable'`)
-- tampoco lleva stock (`sync_product_service_flags` lo fuerza) y calzaba en
-- ella. Además, cada lectura pública preguntaba a su manera: el listado, la
-- ficha por alias, la ficha técnica, la clasificación tributaria y el checkout
-- tenían cada uno su propio filtro. Propuesta aprobada por el dueño el
-- 2026-10-10 («dale nomás»): https://claude.ai/artifact/7huMcza8uyxaEeVzu94oVZ
--
-- Desde aquí:
--   * `catalog_product_web_block_v1(producto, política)` dice, en el orden de
--     la escalera, por qué un ítem NO puede venderse en la web (null = puede,
--     y sólo falta mirar el stock): consumible del taller, inactivo, «Vender
--     en la web» apagado, sin clasificación de IVA (el checkout lo
--     rechazaría), sin precio, bajo el costo con IVA (salvo una liquidación
--     vigente), y lo que pidan los ajustes del sitio (foto, nombre para la
--     tienda, descripción, marca, categoría visible). Un servicio «a
--     cotizar» se publica a $0 en /servicios sin carrito (la ficha sólo
--     ofrece carrito con precio).
--   * La usan la lectura pública de productos (listado, buscador, filtros,
--     destacados, ficha, Merchant, sitemap), el alias de URL, la
--     clasificación tributaria pública y el checkout. La ficha técnica se pide
--     sólo para una ficha que ya resolvió. La pantalla del ERP lee los
--     estados de `catalog_web_items_v1`, que llama a la misma.
--   * Un consumible no puede marcarse para la web: el disparador
--     `zz_guard_consumable_off_web` lo rechaza, y al convertir un producto en
--     consumible lo desmarca de la web, de Merchant y de WhatsApp.
--   * Funciones del ERP para la pantalla nueva: estados con su motivo,
--     marcar y desmarcar, copiar el código de barras del SKU al GTIN,
--     liquidación, precio «desde» o «a cotizar», clasificar IVA, convertir
--     entre producto y consumible, descartar un aviso, archivar fichas
--     vacías, conteos por categoría con sus subcategorías y destacados por
--     ventas.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------------------
-- 1. Datos nuevos del producto
-- ---------------------------------------------------------------------------

-- Una liquidación permite vender bajo el costo hasta esa fecha (inclusive).
alter table public.products
  add column if not exists web_clearance_until date;

-- Cómo se muestra el precio de un servicio: exacto, «desde» o «a cotizar».
alter table public.products
  add column if not exists website_price_mode text not null default 'exact';

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.products'::regclass
       and conname = 'products_website_price_mode_check'
  ) then
    alter table public.products
      add constraint products_website_price_mode_check
      check (website_price_mode in ('exact', 'from', 'quote'));
  end if;
end;
$$;

comment on column public.products.web_clearance_until is
  'Liquidación: hasta esta fecha (inclusive) el producto puede venderse en la web bajo el costo con IVA.';
comment on column public.products.website_price_mode is
  'Cómo se muestra el precio en la tienda: exact, from («desde») o quote («a cotizar», sólo servicios).';

-- Avisos de «Por resolver» que el operador decidió dejar como están.
create table if not exists public.catalog_issue_dismissals (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  product_id uuid not null,
  issue text not null,
  dismissed_by uuid,
  dismissed_at timestamptz not null default now(),
  primary key (tenant_id, product_id, issue),
  foreign key (tenant_id, product_id)
    references public.products (tenant_id, id) on delete cascade
);

alter table public.catalog_issue_dismissals enable row level security;

drop policy if exists catalog_issue_dismissals_tenant_read
  on public.catalog_issue_dismissals;
create policy catalog_issue_dismissals_tenant_read
  on public.catalog_issue_dismissals
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.catalog_issue_dismissals from public, anon;
grant select on public.catalog_issue_dismissals to authenticated;

-- ---------------------------------------------------------------------------
-- 2. La regla
-- ---------------------------------------------------------------------------

-- Los ajustes del sitio que la regla lee, una vez por consulta. Sin la fila,
-- cada ajuste vale lo mismo que valía antes de esta migración.
create or replace function public.catalog_web_policy_v1(p_tenant_id uuid)
returns jsonb
language sql
stable
as $$
  with s as (
    select setting.key, lower(btrim(coalesce(setting.value, ''))) as v
      from public.website_settings setting
     where setting.tenant_id = p_tenant_id
       and setting.key in (
         'product_visibility_require_image',
         'product_visibility_require_visible_category',
         'product_visibility_include_uncategorized',
         'product_visibility_require_web_name',
         'product_visibility_require_description',
         'product_visibility_require_brand'
       )
  )
  select jsonb_build_object(
    'require_image', coalesce((select s.v in ('true', '1', 'yes', 'si', 'sí') from s where s.key = 'product_visibility_require_image' limit 1), false),
    'require_visible_category', coalesce((select s.v in ('true', '1', 'yes', 'si', 'sí') from s where s.key = 'product_visibility_require_visible_category' limit 1), false),
    'include_uncategorized', coalesce((select s.v in ('true', '1', 'yes', 'si', 'sí') from s where s.key = 'product_visibility_include_uncategorized' limit 1), true),
    'require_web_name', coalesce((select s.v in ('true', '1', 'yes', 'si', 'sí') from s where s.key = 'product_visibility_require_web_name' limit 1), false),
    'require_description', coalesce((select s.v in ('true', '1', 'yes', 'si', 'sí') from s where s.key = 'product_visibility_require_description' limit 1), false),
    'require_brand', coalesce((select s.v in ('true', '1', 'yes', 'si', 'sí') from s where s.key = 'product_visibility_require_brand' limit 1), false)
  );
$$;

comment on function public.catalog_web_policy_v1(uuid) is
  'Ajustes del sitio que lee la regla única de venta online (catalog_product_web_block_v1).';

-- El factor de IVA de un producto: 19 % salvo que esté clasificado exento.
create or replace function public.catalog_tax_factor_v1(p_tax_rate numeric)
returns numeric
language sql
immutable
as $$
  select 1 + case
    when p_tax_rate is null then 0.19
    when p_tax_rate > 1 then p_tax_rate / 100.0
    else p_tax_rate
  end;
$$;

-- Por qué un ítem no puede venderse en la web, en el orden de la escalera.
-- Null: puede venderse; sólo falta el stock (eso lo mira quien lista).
-- Sin `set search_path` ni `security definer` para que el planificador la
-- pueda incrustar en las consultas que la usan.
create or replace function public.catalog_product_web_block_v1(
  p public.products,
  p_policy jsonb
)
returns text
language sql
stable
as $$
  select case
    when coalesce(p.product_type, 'product') <> 'service'
         and coalesce(p.purchase_treatment, 'inventory') = 'workshop_consumable'
      then 'workshop_consumable'
    when not coalesce(p.is_active, false)
      then 'inactive'
    when not (coalesce(p.is_published, false) and coalesce(p.show_on_website, false))
      then 'web_off'
    -- Sin clasificación de IVA el checkout lo rechaza y Merchant no lo
    -- recibe: no se ofrece. Un servicio no pasa por el carrito.
    when coalesce(p.product_type, 'product') <> 'service'
         and (p.tax_rate is null or p.tax_rate not in (0, 0.19, 19))
      then 'missing_tax'
    when coalesce(p.website_price, p.price, 0) <= 0
         and not (
           coalesce(p.product_type, 'product') = 'service'
           and p.website_price_mode = 'quote'
         )
      then 'missing_price'
    when coalesce(p.product_type, 'product') <> 'service'
         and coalesce(p.cost, 0) > 0
         and coalesce(p.website_price, p.price)
             < p.cost * public.catalog_tax_factor_v1(p.tax_rate)
         and coalesce(p.web_clearance_until, date '1900-01-01') < current_date
      then 'below_cost'
    when coalesce((p_policy ->> 'require_image')::boolean, false)
         and nullif(btrim(coalesce(p.website_image_url, '')), '') is null
         and nullif(btrim(coalesce(p.website_image_url_optimized, '')), '') is null
         and cardinality(coalesce(p.website_image_urls, array[]::text[])) = 0
         and nullif(btrim(coalesce(p.image_url, '')), '') is null
         and nullif(btrim(coalesce(p.image_url_optimized, '')), '') is null
         and cardinality(coalesce(p.image_urls, array[]::text[])) = 0
      then 'missing_image'
    when coalesce(p.product_type, 'product') <> 'service'
         and coalesce((p_policy ->> 'require_web_name')::boolean, false)
         and nullif(btrim(coalesce(p.website_name, '')), '') is null
      then 'missing_web_name'
    when coalesce((p_policy ->> 'require_description')::boolean, false)
         and nullif(btrim(coalesce(p.website_description, '')), '') is null
      then 'missing_description'
    when coalesce(p.product_type, 'product') <> 'service'
         and coalesce((p_policy ->> 'require_brand')::boolean, false)
         and p.brand_id is null
      then 'missing_brand'
    when coalesce((p_policy ->> 'require_visible_category')::boolean, false)
         and not (
           (p.category_id is null
             and coalesce((p_policy ->> 'include_uncategorized')::boolean, true))
           or exists (
             select 1
               from public.product_categories pc
              where pc.id = p.category_id
                and pc.tenant_id = p.tenant_id
                and pc.is_active = true
                and coalesce(pc.show_on_website, false) = true
           )
         )
      then 'category_hidden'
  end;
$$;

comment on function public.catalog_product_web_block_v1(public.products, jsonb) is
  'Regla única de venta online: el primer motivo, en orden, por el que el ítem no se vende en la web; null si puede (falta mirar el stock).';

revoke all on function public.catalog_web_policy_v1(uuid) from public, anon;
revoke all on function public.catalog_product_web_block_v1(public.products, jsonb) from public, anon;
grant execute on function public.catalog_web_policy_v1(uuid) to authenticated;
grant execute on function public.catalog_product_web_block_v1(public.products, jsonb) to authenticated;
revoke all on function public.catalog_tax_factor_v1(numeric) from public, anon;
grant execute on function public.catalog_tax_factor_v1(numeric) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Un consumible no se marca para la web
-- ---------------------------------------------------------------------------

create or replace function public.guard_consumable_off_web()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(new.product_type, 'product') <> 'service'
     and coalesce(new.purchase_treatment, 'inventory') = 'workshop_consumable' then
    if tg_op = 'UPDATE'
       and coalesce(old.product_type, 'product') <> 'service'
       and coalesce(old.purchase_treatment, 'inventory') = 'workshop_consumable'
       and (
         (coalesce(new.is_published, false) and not coalesce(old.is_published, false))
         or (coalesce(new.show_on_website, false) and not coalesce(old.show_on_website, false))
       ) then
      raise exception 'Es consumible del taller: conviértelo en producto de venta antes de venderlo en la web.'
        using errcode = 'check_violation',
              hint = 'catalog_consumable_not_for_web';
    end if;
    -- Recién convertido en consumible, o una fila antigua: sale de la web.
    new.is_published := false;
    new.show_on_website := false;
    new.is_google_merchant := false;
    new.is_whatsapp_catalog := false;
  end if;
  return new;
end;
$$;

drop trigger if exists zz_guard_consumable_off_web on public.products;
create trigger zz_guard_consumable_off_web
  before insert or update of purchase_treatment, product_type, is_published,
    show_on_website, is_google_merchant, is_whatsapp_catalog
  on public.products
  for each row
  execute function public.guard_consumable_off_web();

-- ---------------------------------------------------------------------------
-- 4. Las lecturas públicas preguntan a la regla
-- ---------------------------------------------------------------------------

create or replace function public.get_public_products_without_inventory_reservations(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_product_ids uuid[] DEFAULT NULL::uuid[], p_sku text DEFAULT NULL::text, p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_sort_by text DEFAULT 'name'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric, cost numeric, inventory_qty integer, stock_quantity integer, image_url text, image_url_optimized text, image_urls text[], description text, website_description text, category text, category_id uuid, category_name text, brand_id uuid, brand text, model text, manufacturer text, manufacturer_sku text, gtin text, product_type text, track_stock boolean, is_active boolean, is_published boolean, show_on_website boolean, created_at timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with args as (
    select
      s.term,
      coalesce(t.tokens, array[]::text[]) as tokens,
      greatest(coalesce(p_limit, 20), 0) as page_limit,
      greatest(coalesce(p_offset, 0), 0) as page_offset,
      lower(coalesce(nullif(trim(p_sort_by), ''), 'name')) as sort_by,
      nullif(trim(coalesce(p_sku, '')), '') as wanted_sku,
      nullif(trim(coalesce(p_product_type, '')), '') as wanted_product_type,
      -- The outer reservation-aware wrapper is the sole stock-policy owner.
      'all'::text as stock_policy,
      -- La regla única de venta online (catalog_product_web_block_v1) lee
      -- los ajustes del sitio una vez por consulta.
      public.catalog_web_policy_v1(p_tenant_id) as policy
    from (
      select trim(
        regexp_replace(
          unaccent(lower(trim(coalesce(p_search_term, '')))),
          '[^a-z0-9]+',
          ' ',
          'g'
        )
      ) as term
    ) s
    cross join lateral (
      select array_agg(token) as tokens
      from regexp_split_to_table(s.term, '\s+') as token_parts(token)
      where token <> ''
    ) t
  ),
  normalized as (
    -- The normalized texts only matter to a search: without a term every
    -- product passes and the order reads the raw name, price and date, so
    -- they are not computed (nor scored, below).
    select
      p.*,
      a.term,
      a.tokens,
      a.page_limit,
      a.page_offset,
      a.sort_by,
      (
        a.term ~ '(^| )(servicio|servicios|mantencion|mantenciones|reparacion|reparaciones|ajuste|ajustes|instalacion|instalaciones|limpieza|lavado|engrase|sangrado|purga|centrado|enrayado|diagnostico|revision)( |$)'
      ) as service_intent,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_name, p.name))), '[^a-z0-9]+', ' ', 'g')) end as name_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.sku, ''))), '[^a-z0-9]+', ' ', 'g')) end as sku_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.barcode, ''))), '[^a-z0-9]+', ' ', 'g')) end as barcode_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.gtin, ''))), '[^a-z0-9]+', ' ', 'g')) end as gtin_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.category_name, p.category, ''))), '[^a-z0-9]+', ' ', 'g')) end as category_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.brand, ''))), '[^a-z0-9]+', ' ', 'g')) end as brand_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.model, ''))), '[^a-z0-9]+', ' ', 'g')) end as model_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer, ''))), '[^a-z0-9]+', ' ', 'g')) end as manufacturer_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(coalesce(p.manufacturer_sku, ''))), '[^a-z0-9]+', ' ', 'g')) end as manufacturer_sku_n,
      case when a.term = '' then '' else trim(regexp_replace(unaccent(lower(concat_ws(' ', p.website_description, p.description))), '[^a-z0-9]+', ' ', 'g')) end as description_n
    from public.products p
    cross join args a
    where p.tenant_id = p_tenant_id
      and p.is_active = true
      and coalesce(p.is_published, false) = true
      and coalesce(p.show_on_website, false) = true
      and (
        p_product_ids is null
        or cardinality(p_product_ids) = 0
        or p.id = any(p_product_ids)
      )
      and (
        p_category_ids is null
        or cardinality(p_category_ids) = 0
        or p.category_id = any(p_category_ids)
      )
      and (
        a.wanted_sku is null
        or lower(p.sku) = lower(a.wanted_sku)
      )
      and (
        a.wanted_product_type is null
        or p.product_type = a.wanted_product_type
      )
      -- Consumible, precio, costo, foto, nombre, categoría: lo decide la
      -- regla única, la misma que usan la ficha, el checkout y el ERP.
      and public.catalog_product_web_block_v1(p, a.policy) is null
      and (
        a.stock_policy = 'all'
        or coalesce(p.is_service, false)
        or p.product_type = 'service'
        or (
          a.stock_policy = 'available_only'
          and (
            coalesce(p.track_stock, true) = false
            or coalesce(p.stock_quantity, p.inventory_qty, 0) > 0
          )
        )
        or (
          a.stock_policy = 'out_of_stock_only'
          and coalesce(p.track_stock, true) = true
          and coalesce(p.stock_quantity, p.inventory_qty, 0) <= 0
        )
      )
  ),
  enriched as (
    select
      n.*,
      trim(concat_ws(
        ' ',
        case
          when n.name_n like '%pinon%'
            or n.category_n in ('pinones', 'cassette')
            then 'pinon pinones cassette freewheel rueda libre coronas'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%cadena%'
            then 'cadena chain transmision'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%camara%'
            then 'camara tubo tube valvula neumatico'
          else null
        end,
        case
          when concat_ws(' ', n.name_n, n.category_n) like '%cubierta%'
            or concat_ws(' ', n.name_n, n.category_n) like '%neumatico%'
            then 'cubierta neumatico tire goma'
          else null
        end
      )) as alias_n
    from normalized n
  ),
  matched as (
    select
      e.*,
      (
        case when e.term <> '' and e.sku_n = e.term then 1000 else 0 end +
        case when e.term <> '' and e.barcode_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.gtin_n = e.term then 980 else 0 end +
        case when e.term <> '' and e.name_n = e.term then 850 else 0 end +
        case when e.term <> '' and e.name_n like e.term || '%' then 760 else 0 end +
        case when e.term <> '' and e.name_n like '%' || e.term || '%' then 650 else 0 end +
        case when e.term <> '' and e.category_n = e.term then 620 else 0 end +
        case when e.term <> '' and e.category_n like '%' || e.term || '%' then 560 else 0 end +
        case when e.term <> '' and e.alias_n like '%' || e.term || '%' then 500 else 0 end +
        case when e.term <> '' and e.sku_n like '%' || e.term || '%' then 460 else 0 end +
        case when e.term <> '' and e.manufacturer_sku_n like '%' || e.term || '%' then 420 else 0 end +
        case when e.term <> '' and e.brand_n like '%' || e.term || '%' then 360 else 0 end +
        case when e.term <> '' and e.model_n like '%' || e.term || '%' then 320 else 0 end +
        case when e.term <> '' and e.manufacturer_n like '%' || e.term || '%' then 300 else 0 end
      ) as phrase_strong_score,
      case when e.term = '' then 0 else coalesce((
        select sum(
          case
            when token ~ '^[0-9]+$' and e.sku_n = token then 120
            when token ~ '^[0-9]+$' and e.barcode_n = token then 120
            when token ~ '^[0-9]+$' and e.gtin_n = token then 120
            when token ~ '^[0-9]+$' and e.name_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 70
            when token ~ '^[0-9]+$' and e.category_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 58
            when token ~ '^[0-9]+$' then 0
            when e.name_n like token || '%' then 95
            when e.name_n like '%' || token || '%' then 76
            when e.category_n like '%' || token || '%' then 66
            when e.alias_n like '%' || token || '%' then 56
            when e.sku_n like '%' || token || '%' then 54
            when e.manufacturer_sku_n like '%' || token || '%' then 48
            when e.brand_n like '%' || token || '%' then 42
            when e.model_n like '%' || token || '%' then 38
            when e.manufacturer_n like '%' || token || '%' then 34
            when length(token) >= 4 and greatest(
              word_similarity(token, e.name_n),
              word_similarity(token, e.category_n),
              word_similarity(token, e.brand_n),
              word_similarity(token, e.model_n),
              word_similarity(token, e.manufacturer_n),
              word_similarity(token, e.alias_n)
            ) >= case when length(token) >= 5 then 0.56 else 0.72 end then 28
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
      ), 0) end as token_strong_score,
      case when e.term = '' then 0 else coalesce((
        select sum(
          case
            when token ~ '^[0-9]+$' and e.description_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)') then 8
            when token !~ '^[0-9]+$' and e.description_n like '%' || token || '%' then 8
            when token !~ '^[0-9]+$' and length(token) >= 5 and word_similarity(token, e.description_n) >= 0.86 then 5
            else 0
          end
        )
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
      ), 0) end as weak_description_score
    from enriched e
    where e.term = ''
      or not exists (
        select 1
        from unnest(e.tokens) as token_parts(token)
        where token <> ''
          and not (
            (
              token ~ '^[0-9]+$'
              and (
                e.sku_n = token
                or e.barcode_n = token
                or e.gtin_n = token
                or e.name_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
                or e.category_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
                or e.description_n ~ ('(^|[^0-9])' || token || '([^0-9]|$)')
              )
            )
            or (
              token !~ '^[0-9]+$'
              and (
                e.name_n like '%' || token || '%'
                or e.category_n like '%' || token || '%'
                or e.alias_n like '%' || token || '%'
                or e.sku_n like '%' || token || '%'
                or e.barcode_n like '%' || token || '%'
                or e.gtin_n like '%' || token || '%'
                or e.brand_n like '%' || token || '%'
                or e.model_n like '%' || token || '%'
                or e.manufacturer_n like '%' || token || '%'
                or e.manufacturer_sku_n like '%' || token || '%'
                or e.description_n like '%' || token || '%'
                or (
                  length(token) >= 4
                  and greatest(
                    word_similarity(token, e.name_n),
                    word_similarity(token, e.category_n),
                    word_similarity(token, e.brand_n),
                    word_similarity(token, e.model_n),
                    word_similarity(token, e.manufacturer_n),
                    word_similarity(token, e.alias_n)
                  ) >= case when length(token) >= 5 then 0.56 else 0.72 end
                )
                or (
                  length(token) >= 5
                  and word_similarity(token, e.description_n) >= 0.86
                )
              )
            )
          )
      )
  ),
  scored as (
    select
      m.*,
      (m.phrase_strong_score + m.token_strong_score) as strong_score,
      (
        m.phrase_strong_score +
        m.token_strong_score +
        m.weak_description_score +
        case when m.product_type = 'service' and not m.service_intent
          then -260 else 0 end
      ) as search_score
    from matched m
  ),
  ranked as (
    select s.*
    from scored s
    where s.term = ''
      or s.product_type <> 'service'
      or s.service_intent
      or s.strong_score > 0
      or not exists (
        select 1
        from scored product_match
        where product_match.product_type <> 'service'
          and product_match.strong_score > 0
      )
  ),
  counted as (
    select p.*, count(*) over() as row_total
    from ranked p
  )
  select
    p.id,
    p.tenant_id,
    coalesce(nullif(btrim(p.website_name), ''), p.name) as name,
    p.sku,
    p.barcode,
    coalesce(p.website_price, p.price) as price,
    0::numeric as cost,
    p.inventory_qty,
    p.stock_quantity,
    coalesce(nullif(btrim(p.website_image_url), ''), p.image_url) as image_url,
    coalesce(nullif(btrim(p.website_image_url_optimized), ''), p.image_url_optimized) as image_url_optimized,
    case
      when cardinality(coalesce(p.website_image_urls, array[]::text[])) > 0
        then p.website_image_urls
      else p.image_urls
    end as image_urls,
    p.description,
    p.website_description,
    p.category,
    p.category_id,
    p.category_name,
    p.brand_id,
    p.brand,
    p.model,
    p.manufacturer,
    p.manufacturer_sku,
    p.gtin,
    p.product_type,
    p.track_stock,
    p.is_active,
    p.is_published,
    p.show_on_website,
    p.created_at,
    p.updated_at,
    p.row_total as total_count
  from counted p
  order by
    case when p.term <> '' then p.search_score end desc nulls last,
    case when p.term = '' and p.sort_by = 'price_asc'
      then coalesce(p.website_price, p.price) end asc nulls last,
    case when p.term = '' and p.sort_by = 'price_desc'
      then coalesce(p.website_price, p.price) end desc nulls last,
    case when p.term = '' and p.sort_by = 'newest'
      then p.created_at end desc nulls last,
    coalesce(nullif(btrim(p.website_name), ''), p.name) asc,
    p.id asc
  limit (select page_limit from args)
  offset (select page_offset from args);
$function$;

create or replace function public.get_public_products(p_tenant_id uuid, p_category_ids uuid[] DEFAULT NULL::uuid[], p_product_ids uuid[] DEFAULT NULL::uuid[], p_sku text DEFAULT NULL::text, p_search_term text DEFAULT NULL::text, p_product_type text DEFAULT NULL::text, p_only_in_stock boolean DEFAULT true, p_sort_by text DEFAULT 'name'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric, cost numeric, inventory_qty integer, stock_quantity integer, image_url text, image_url_optimized text, image_urls text[], description text, website_description text, category text, category_id uuid, category_name text, brand_id uuid, brand text, model text, manufacturer text, manufacturer_sku text, gtin text, product_type text, track_stock boolean, is_active boolean, is_published boolean, show_on_website boolean, created_at timestamp with time zone, updated_at timestamp with time zone, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with policy as (
    select case
      -- Una ficha pide productos puntuales sin filtrar por stock: un agotado
      -- conserva su ficha (con «Agotado» y sin compra) aunque el sitio oculte
      -- los agotados de los listados. Destacados, carrito y listados piden
      -- con p_only_in_stock y siguen el ajuste del sitio.
      when not coalesce(p_only_in_stock, true)
        and (
          coalesce(cardinality(p_product_ids), 0) > 0
          or nullif(btrim(coalesce(p_sku, '')), '') is not null
        )
        then 'all'
      else case lower(coalesce(
        nullif(btrim(coalesce((
          select setting.value
            from public.website_settings setting
           where setting.tenant_id = p_tenant_id
             and setting.key = 'product_visibility_stock_policy'
           limit 1
        ), '')), ''),
        case when p_only_in_stock then 'available_only' else 'all' end
      ))
        when 'all' then 'all'
        when 'both' then 'all'
        when 'out_of_stock_only' then 'out_of_stock_only'
        when 'out_of_stock' then 'out_of_stock_only'
        when 'sin_stock' then 'out_of_stock_only'
        else 'available_only'
      end
    end as stock_policy
  ), raw_rows as (
    select raw.*
      from public.get_public_products_without_inventory_reservations(
        p_tenant_id,
        p_category_ids,
        p_product_ids,
        p_sku,
        p_search_term,
        p_product_type,
        false,
        p_sort_by,
        2147483647,
        0
      ) with ordinality as raw
  ), candidate as (
    -- One join instead of one function call per row. `is_set` and `is_service`
    -- are the only facts the inner catalog query does not already return.
    select r.id,
           r.tenant_id,
           r.stock_quantity,
           r.inventory_qty,
           coalesce(product.is_set, false) as is_set,
           coalesce(product.is_service, false) as is_service
      from raw_rows r
      join public.products product
        on product.id = r.id
       and product.tenant_id = r.tenant_id
     where r.product_type is distinct from 'service'
       and coalesce(r.track_stock, true)
  ), reserved as (
    -- Aggregated once for the whole tenant, then joined. Covers both the
    -- products themselves and the components of any set among them.
    select reservation.product_id,
           sum(reservation.quantity)::integer as quantity
      from public.online_order_inventory_reservations reservation
     where reservation.tenant_id = p_tenant_id
       and reservation.state = 'active'
       and reservation.expires_at > clock_timestamp()
     group by reservation.product_id
  ), simple_availability as (
    select candidate.id,
           greatest(
             coalesce(candidate.stock_quantity, candidate.inventory_qty, 0)
               - coalesce(reserved.quantity, 0),
             0
           ) as available_quantity
      from candidate
      left join reserved on reserved.product_id = candidate.id
     where not candidate.is_set
       and not candidate.is_service
  ), set_availability as (
    -- A set is limited by its scarcest component. An inner join means a set
    -- with no components produces no row here and resolves to zero below,
    -- which is what the per-row function returned for that case.
    select candidate.id,
           min(greatest(floor(
             (
               coalesce(component.stock_quantity, component.inventory_qty, 0)
               - coalesce(component_reserved.quantity, 0)
             )::numeric / set_component.quantity_in_set
           ), 0))::integer as available_quantity
      from candidate
      join public.product_set_components set_component
        on set_component.tenant_id = candidate.tenant_id
       and set_component.set_product_id = candidate.id
      join public.products component
        on component.id = set_component.component_product_id
       and component.tenant_id = set_component.tenant_id
      left join reserved component_reserved
        on component_reserved.product_id = component.id
     where candidate.is_set
       and not candidate.is_service
     group by candidate.id
  ), availability as (
    select id, available_quantity from simple_availability
    union all
    select id, available_quantity from set_availability
  ), base_rows as (
    select r.*,
           case
             when r.product_type = 'service'
               or not coalesce(r.track_stock, true)
               or coalesce(service_like.is_service, false)
               then greatest(coalesce(r.stock_quantity, r.inventory_qty, 0), 0)
             else coalesce(availability.available_quantity, 0)
           end as available_quantity
      from raw_rows r
      left join availability on availability.id = r.id
      left join candidate service_like on service_like.id = r.id
  ), filtered as (
    select base.*
      from base_rows base
      cross join policy
     where policy.stock_policy = 'all'
        or base.product_type = 'service'
        -- Un producto de venta que no controla stock pasa como antes; un
        -- consumible del taller (que tampoco lleva) ya no llega hasta aquí:
        -- lo saca la regla única en la lectura interna.
        or not coalesce(base.track_stock, true)
        or (
          policy.stock_policy = 'available_only'
          and base.available_quantity > 0
        )
        or (
          policy.stock_policy = 'out_of_stock_only'
          and base.available_quantity <= 0
        )
  ), paged as (
    select filtered.*,
           count(*) over() as filtered_total
      from filtered
     order by filtered.ordinality
     limit greatest(coalesce(p_limit, 20), 0)
     offset greatest(coalesce(p_offset, 0), 0)
  )
  select
    paged.id,
    paged.tenant_id,
    paged.name,
    paged.sku,
    paged.barcode,
    paged.price,
    paged.cost,
    case
      when paged.product_type = 'service'
        or not coalesce(paged.track_stock, true)
        then paged.inventory_qty
      else paged.available_quantity
    end as inventory_qty,
    case
      when paged.product_type = 'service'
        or not coalesce(paged.track_stock, true)
        then paged.stock_quantity
      else paged.available_quantity
    end as stock_quantity,
    paged.image_url,
    paged.image_url_optimized,
    paged.image_urls,
    paged.description,
    paged.website_description,
    paged.category,
    paged.category_id,
    paged.category_name,
    paged.brand_id,
    paged.brand,
    paged.model,
    paged.manufacturer,
    paged.manufacturer_sku,
    paged.gtin,
    paged.product_type,
    paged.track_stock,
    paged.is_active,
    paged.is_published,
    paged.show_on_website,
    paged.created_at,
    paged.updated_at,
    paged.filtered_total as total_count
  from paged
  order by paged.ordinality;
$function$;

create or replace function public.resolve_public_product_url_alias(p_tenant_id uuid, p_alias_path text)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select a.product_id
  from public.product_url_aliases a
  join public.products p
    on p.id = a.product_id
   and p.tenant_id = a.tenant_id
  where a.tenant_id = p_tenant_id
    and a.alias_path = p_alias_path
    and p.is_active = true
    and p.is_published = true
    and p.show_on_website = true
    and p.product_type = 'product'
    and public.catalog_product_web_block_v1(
          p,
          public.catalog_web_policy_v1(p_tenant_id)
        ) is null
  limit 1;
$function$;

create or replace function public.get_public_product_tax_classifications(p_tenant_id uuid, p_product_ids uuid[])
 RETURNS TABLE(id uuid, tax_rate numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select product.id, product.tax_rate
    from public.products product
   where p_tenant_id is not null
     and p_product_ids is not null
     and cardinality(p_product_ids) between 1 and 100
     and product.tenant_id = p_tenant_id
     and product.id = any(p_product_ids)
     and product.is_active = true
     and coalesce(product.is_published, false) = true
     and coalesce(product.show_on_website, false) = true
     and public.catalog_product_web_block_v1(
           product,
           public.catalog_web_policy_v1(p_tenant_id)
         ) is null
   order by product.id;
$function$;



create or replace function public.create_public_online_order_unkeyed(p_order_data jsonb, p_order_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_customer_id uuid;
  v_auth_uid uuid := auth.uid();
  v_customer_name text;
  v_customer_email text;
  v_customer_phone text;
  v_customer_address text;
  v_delivery_type text;
  v_payment_method text;
  v_order_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_quantity integer;
  v_product record;
  v_unit_price numeric(12,2);
  v_line_total numeric(12,2);
  v_customer_id_text text;
  v_checkout_key text;
  v_created_response jsonb;
  v_item_tax_snapshot jsonb;
  v_shipping_quote jsonb;
  v_expected_shipping_gross numeric(12,2);
  v_shipping_gross numeric(12,2);
  v_shipping_net numeric(12,2);
  v_shipping_tax numeric(12,2);
  v_shipping_tax_rate numeric(5,2);
  v_shipping_tier_id uuid;
  v_shipping_country text;
begin
  if p_order_data is null or jsonb_typeof(p_order_data) <> 'object' then
    raise exception 'Invalid order payload';
  end if;

  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array'
     or jsonb_array_length(p_order_items) = 0 then
    raise exception 'Order must include at least one item';
  end if;
  if jsonb_array_length(p_order_items) > 50 then
    raise exception 'Order item limit exceeded';
  end if;

  v_tenant_id := nullif(p_order_data->>'tenant_id', '')::uuid;
  if v_tenant_id is null or not exists (
    select 1 from public.tenants tenant where tenant.id = v_tenant_id
  ) then
    raise exception 'Invalid tenant_id';
  end if;

  v_customer_name := btrim(coalesce(p_order_data->>'customer_name', ''));
  v_customer_email := lower(btrim(coalesce(p_order_data->>'customer_email', '')));
  v_customer_phone := nullif(btrim(coalesce(p_order_data->>'customer_phone', '')), '');
  v_customer_address := nullif(btrim(coalesce(p_order_data->>'customer_address', '')), '');
  v_delivery_type := lower(btrim(coalesce(
    nullif(p_order_data->>'delivery_type', ''),
    'shipping'
  )));
  v_payment_method := lower(btrim(coalesce(
    nullif(p_order_data->>'payment_method', ''),
    'transfer'
  )));
  v_checkout_key := nullif(
    btrim(coalesce(p_order_data->>'checkout_idempotency_key', '')),
    ''
  );
  v_shipping_country := btrim(coalesce(
    nullif(p_order_data->>'shipping_country', ''),
    'Chile'
  ));

  if length(v_customer_name) < 2 or length(v_customer_name) > 160 then
    raise exception 'Invalid customer name';
  end if;
  if v_customer_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Invalid customer email';
  end if;
  if v_customer_phone is not null and length(v_customer_phone) > 40 then
    raise exception 'Invalid customer phone';
  end if;
  if v_delivery_type not in ('shipping', 'pickup') then
    raise exception 'Invalid delivery type: %', v_delivery_type;
  end if;
  if v_delivery_type = 'shipping'
     and lower(v_shipping_country) not in ('chile', 'cl') then
    raise exception 'Online shipping is currently available only in Chile';
  end if;
  if v_payment_method not in (
    'mercadopago', 'mercado_pago', 'transfer', 'bank_transfer'
  ) then
    raise exception 'Invalid payment method: %', v_payment_method;
  end if;

  if v_payment_method = 'mercado_pago' then
    v_payment_method := 'mercadopago';
  elsif v_payment_method = 'bank_transfer' then
    v_payment_method := 'transfer';
  end if;

  if v_delivery_type = 'shipping'
     and coalesce(
       nullif(p_order_data->>'shipping_address_line1', ''),
       v_customer_address
     ) is null then
    raise exception 'Shipping address is required';
  end if;

  if p_order_data ? 'shipping_quote_cost' then
    begin
      v_expected_shipping_gross :=
        (p_order_data->>'shipping_quote_cost')::numeric;
    exception when others then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end;
    if v_expected_shipping_gross is null
       or v_expected_shipping_gross < 0
       or v_expected_shipping_gross
            <> public.clp_round(v_expected_shipping_gross) then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end if;
  end if;

  v_customer_id_text := nullif(p_order_data->>'customer_id', '');
  if v_customer_id_text is not null then
    v_customer_id := v_customer_id_text::uuid;
    if v_auth_uid is null or not exists (
      select 1
        from public.customers customer
       where customer.id = v_customer_id
         and customer.tenant_id = v_tenant_id
         and customer.auth_user_id = v_auth_uid
    ) then
      raise exception 'Invalid customer reference';
    end if;
  end if;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', 'true', true);

  insert into public.online_orders (
    tenant_id,
    order_number,
    customer_id,
    customer_email,
    customer_name,
    customer_phone,
    customer_address,
    delivery_type,
    shipping_address_line1,
    shipping_address_line2,
    shipping_city,
    shipping_state,
    shipping_postal_code,
    shipping_country,
    subtotal,
    tax_amount,
    shipping_cost,
    shipping_net_amount,
    shipping_tax_amount,
    shipping_tax_rate,
    shipping_rate_snapshot,
    discount_amount,
    total,
    status,
    payment_status,
    payment_method,
    customer_notes
  ) values (
    v_tenant_id,
    public.generate_online_order_number(v_tenant_id, clock_timestamp()),
    v_customer_id,
    v_customer_email,
    v_customer_name,
    v_customer_phone,
    v_customer_address,
    v_delivery_type,
    nullif(btrim(coalesce(p_order_data->>'shipping_address_line1', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_address_line2', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_city', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_state', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_postal_code', '')), ''),
    case when v_delivery_type = 'pickup' then null else 'Chile' end,
    0,
    0,
    0,
    0,
    0,
    0,
    '{}'::jsonb,
    0,
    0,
    'pending',
    'pending',
    v_payment_method,
    nullif(left(btrim(coalesce(p_order_data->>'customer_notes', '')), 1000), '')
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_order_items)
  loop
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_quantity := coalesce((v_item->>'quantity')::integer, 0);

    if v_product_id is null then
      raise exception 'Order item is missing product_id';
    end if;
    if v_quantity < 1 or v_quantity > 99 then
      raise exception 'Invalid quantity for product %', v_product_id;
    end if;

    select
      product.id,
      product.name,
      product.sku,
      coalesce(product.website_price, product.price) as public_price,
      product.cost,
      product.tax_rate,
      product.product_type,
      product.is_service,
      product.purchase_treatment,
      product.track_stock,
      product.is_set,
      product.inventory_qty,
      product.stock_quantity
      into v_product
      from public.products product
     where product.id = v_product_id
       and product.tenant_id = v_tenant_id
       and product.is_active = true
       and coalesce(product.is_published, false) = true
       and coalesce(product.show_on_website, false) = true
     for update;

    if not found then
      raise exception 'Product is unavailable: %', v_product_id;
    end if;
    if v_product.tax_rate is null
       or v_product.tax_rate not in (0, 0.19, 19) then
      raise exception 'Product % has missing or unsupported tax classification',
        v_product.name
        using errcode = '23514';
    end if;

    if not (
      coalesce(v_product.is_service, false)
      or v_product.product_type = 'service'
    )
       and coalesce(v_product.track_stock, true) then
      if coalesce(v_product.is_set, false) then
        -- Canonical set headers are virtual. Validate their component map and
        -- availability after active reservations; the item-insert trigger then
        -- locks and reserves every physical component atomically.
        perform public.assert_valid_product_set_maps(
          v_tenant_id,
          jsonb_build_array(jsonb_build_object(
            'product_id', v_product.id,
            'quantity', v_quantity
          ))
        );
        if public.online_product_available_quantity(
          v_tenant_id,
          v_product.id
        ) < v_quantity then
          raise exception 'Insufficient stock for product %', v_product.name;
        end if;
      else
        if v_product.stock_quantity is not null
           and v_product.inventory_qty is not null
           and v_product.stock_quantity <> v_product.inventory_qty then
          raise exception 'Product stock columns disagree; checkout blocked for %',
            v_product.name;
        end if;
        if coalesce(v_product.stock_quantity, v_product.inventory_qty, 0)
           < v_quantity then
          raise exception 'Insufficient stock for product %', v_product.name;
        end if;
      end if;
    end if;

    if v_product.public_price is null
       or v_product.public_price <= 0
       or v_product.public_price <> public.clp_round(v_product.public_price) then
      raise exception 'Product % requires a positive whole-CLP website price',
        v_product.name
        using errcode = '23514';
    end if;
    -- Después de los rechazos con su propio mensaje (IVA, stock, precio),
    -- la misma regla que decide qué se lista: un consumible del taller, un
    -- producto bajo el costo o sin foto no se compra aunque llegue su id.
    if exists (
      select 1
        from public.products rule_product
       where rule_product.id = v_product_id
         and rule_product.tenant_id = v_tenant_id
         and public.catalog_product_web_block_v1(
               rule_product,
               public.catalog_web_policy_v1(v_tenant_id)
             ) is not null
    ) then
      raise exception 'Product is unavailable: %', v_product_id;
    end if;
    v_unit_price := public.clp_round(v_product.public_price);
    v_line_total := public.clp_round(v_unit_price * v_quantity);

    insert into public.online_order_items (
      tenant_id,
      order_id,
      product_id,
      product_name,
      product_sku,
      quantity,
      unit_price,
      subtotal,
      unit_cost,
      tax_rate,
      is_service,
      purchase_treatment,
      product_type
    ) values (
      v_tenant_id,
      v_order_id,
      v_product.id,
      v_product.name,
      v_product.sku,
      v_quantity,
      v_unit_price,
      v_line_total,
      v_product.cost,
      case when v_product.tax_rate = 0.19 then 19 else v_product.tax_rate end,
      (
        coalesce(v_product.is_service, false)
        or v_product.product_type = 'service'
      ),
      coalesce(v_product.purchase_treatment, 'inventory'),
      coalesce(v_product.product_type, 'product')
    );
  end loop;

  v_item_tax_snapshot := public.calculate_online_order_tax_snapshot(
    v_order_id,
    v_tenant_id
  );
  v_shipping_quote := public.quote_online_shipping_internal(
    v_tenant_id,
    v_delivery_type,
    (v_item_tax_snapshot->>'gross_amount')::numeric,
    'CL'
  );
  v_shipping_gross := (v_shipping_quote->>'shipping_gross')::numeric;
  v_shipping_net := (v_shipping_quote->>'shipping_net')::numeric;
  v_shipping_tax := (v_shipping_quote->>'shipping_tax')::numeric;
  v_shipping_tax_rate := (v_shipping_quote->>'tax_rate')::numeric;
  v_shipping_tier_id := nullif(v_shipping_quote->>'tier_id', '')::uuid;

  if v_expected_shipping_gross is null then
    if v_shipping_gross > 0 then
      raise exception 'A current shipping quote is required before checkout'
        using errcode = '23514';
    end if;
    v_expected_shipping_gross := 0;
  end if;

  if v_expected_shipping_gross <> v_shipping_gross then
    raise exception 'Shipping quote changed; refresh checkout before paying'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config(
    'app.online_order_shipping_quote_in_progress',
    'true',
    true
  );
  update public.online_orders
     set subtotal = (v_item_tax_snapshot->>'net_amount')::numeric,
         tax_amount = (v_item_tax_snapshot->>'tax_amount')::numeric,
         shipping_cost = v_shipping_gross,
         shipping_net_amount = v_shipping_net,
         shipping_tax_amount = v_shipping_tax,
         shipping_tax_rate = v_shipping_tax_rate,
         shipping_rate_tier_id = v_shipping_tier_id,
         shipping_rate_snapshot = v_shipping_quote,
         discount_amount = 0,
         total = (v_item_tax_snapshot->>'gross_amount')::numeric
           + v_shipping_gross
   where id = v_order_id
     and tenant_id = v_tenant_id;
  perform pg_catalog.set_config(
    'app.online_order_shipping_quote_in_progress',
    '',
    true
  );

  select jsonb_build_object(
    'success', true,
    'order_id', orders.id,
    'status', orders.status,
    'payment_status', orders.payment_status,
    'version', orders.version,
    'invoice_id', orders.sales_invoice_id,
    'total', orders.total,
    'shipping_cost', orders.shipping_cost,
    'changed', true
  )
    into v_created_response
    from public.online_orders orders
   where orders.id = v_order_id
     and orders.tenant_id = v_tenant_id;

  insert into public.online_order_events (
    tenant_id,
    order_id,
    event_type,
    from_status,
    to_status,
    from_payment_status,
    to_payment_status,
    changed,
    expected_version,
    result_version,
    actor_id,
    operation_key,
    request_snapshot,
    response_snapshot
  )
  select
    orders.tenant_id,
    orders.id,
    'order_created',
    null,
    orders.status,
    null,
    orders.payment_status,
    true,
    null,
    orders.version,
    v_auth_uid,
    'checkout-created:' || orders.id::text,
    jsonb_build_object(
      'source', 'public_checkout',
      'checkout_idempotency_key', v_checkout_key,
      'delivery_type', orders.delivery_type,
      'payment_method', orders.payment_method,
      'item_count', jsonb_array_length(p_order_items),
      'tax_source', 'product_line_snapshot',
      'shipping_quote', orders.shipping_rate_snapshot,
      'accepted_shipping_cost', v_expected_shipping_gross
    ),
    v_created_response
  from public.online_orders orders
  where orders.id = v_order_id
    and orders.tenant_id = v_tenant_id;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);

  if v_payment_method <> 'mercadopago' then
    perform public.process_public_checkout_order(v_order_id, v_tenant_id);
  end if;

  return v_order_id;
exception
  when others then
    perform pg_catalog.set_config(
      'app.online_order_shipping_quote_in_progress',
      '',
      true
    );
    perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);
    raise;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. La pantalla del ERP: estados, motivos y avisos
-- ---------------------------------------------------------------------------

-- Un código de barras real guardado como SKU: 12, 13 o 14 dígitos, dígito
-- verificador correcto y sin el prefijo 2 de los códigos internos. El EAN-8
-- queda fuera a propósito: un SKU interno de 8 dígitos acierta el dígito una
-- vez de cada diez.
create or replace function public.catalog_gtin_is_valid_v1(p_code text)
returns boolean
language sql
immutable
as $$
  select case
    when p_code is null or p_code !~ '^([0-9]{12}|[0-9]{13}|[0-9]{14})$' or p_code ~ '^2'
      then false
    else (
      10 - (
        select sum(
          substr(reverse(left(p_code, length(p_code) - 1)), i, 1)::integer
          * case when i % 2 = 1 then 3 else 1 end
        )
        from generate_series(1, length(p_code) - 1) as i
      ) % 10
    ) % 10 = right(p_code, 1)::integer
  end;
$$;

revoke all on function public.catalog_gtin_is_valid_v1(text) from public, anon;
grant execute on function public.catalog_gtin_is_valid_v1(text) to authenticated;

create or replace function public.catalog_assert_reader_v1(p_tenant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if auth.uid() is null
     or p_tenant_id is null
     or public.user_tenant_id() is distinct from p_tenant_id then
    raise exception 'catalog_tenant_forbidden' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.catalog_assert_editor_v1(p_tenant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);
  if not public.can_edit_tenant_settings(p_tenant_id) then
    raise exception 'catalog_edit_forbidden' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.catalog_assert_reader_v1(uuid) from public, anon;
revoke all on function public.catalog_assert_editor_v1(uuid) from public, anon;
grant execute on function public.catalog_assert_reader_v1(uuid) to authenticated;
grant execute on function public.catalog_assert_editor_v1(uuid) to authenticated;

-- Todo el catálogo con su estado en la tienda, el motivo y los avisos de
-- «Por resolver». Estado: venta, agotado, falta, oculto o taller.
create or replace function public.catalog_web_items_v1(p_tenant_id uuid)
returns table (
  id uuid,
  name text,
  website_name text,
  sku text,
  gtin text,
  product_type text,
  kind text,
  category_id uuid,
  category_name text,
  brand_id uuid,
  brand text,
  price numeric,
  web_price numeric,
  cost numeric,
  tax_rate numeric,
  min_web_price numeric,
  image_url text,
  has_description boolean,
  web_on boolean,
  is_active boolean,
  clearance_until date,
  price_mode text,
  stock integer,
  available integer,
  block text,
  state text,
  sold_counter_12m integer,
  used_jobs_12m integer,
  sold_total_12m integer,
  issues text[],
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);

  return query
  with policy as (
    select public.catalog_web_policy_v1(p_tenant_id) as v
  ), reserved as (
    select reservation.product_id,
           sum(reservation.quantity)::integer as quantity
      from public.online_order_inventory_reservations reservation
     where reservation.tenant_id = p_tenant_id
       and reservation.state = 'active'
       and reservation.expires_at > clock_timestamp()
     group by reservation.product_id
  ), base as (
    select p.*,
           public.catalog_product_web_block_v1(p, (select policy.v from policy)) as blk
      from public.products p
     where p.tenant_id = p_tenant_id
  ), set_avail as (
    select b.id,
           min(greatest(floor(
             (coalesce(component.stock_quantity, component.inventory_qty, 0)
               - coalesce(component_reserved.quantity, 0))::numeric
             / nullif(set_component.quantity_in_set, 0)
           ), 0))::integer as available_quantity
      from base b
      join public.product_set_components set_component
        on set_component.tenant_id = b.tenant_id
       and set_component.set_product_id = b.id
      join public.products component
        on component.id = set_component.component_product_id
       and component.tenant_id = set_component.tenant_id
      left join reserved component_reserved
        on component_reserved.product_id = component.id
     where coalesce(b.is_set, false)
     group by b.id
  ), lines as (
    select (line ->> 'product_id')::uuid as product_id,
           coalesce((line ->> 'quantity')::numeric, 0) as quantity,
           (line ? 'job_bike_id' and line ->> 'job_bike_id' is not null) as in_job,
           invoice.created_at > now() - interval '12 months' as recent
      from public.sales_invoices invoice
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(invoice.items) = 'array' then invoice.items else '[]'::jsonb end
      ) line
     where invoice.tenant_id = p_tenant_id
       and coalesce(invoice.status, '') not in ('cancelled', 'void', 'anulada', 'draft')
       and (line ->> 'product_id') ~ '^[0-9a-f-]{36}$'
  ), sales as (
    select lines.product_id,
           coalesce(sum(lines.quantity) filter (where lines.recent and not lines.in_job), 0)::integer as counter_12m,
           coalesce(sum(lines.quantity) filter (where lines.recent and lines.in_job), 0)::integer as jobs_12m,
           coalesce(sum(lines.quantity) filter (where lines.recent), 0)::integer as total_12m,
           count(*) as ever
      from lines
     group by lines.product_id
  ), bought as (
    select distinct purchase_line.product_id
      from public.purchase_invoice_lines purchase_line
     where purchase_line.tenant_id = p_tenant_id
       and purchase_line.product_id is not null
  ), ordered as (
    select distinct order_item.product_id
      from public.online_order_items order_item
      join public.online_orders online_order
        on online_order.id = order_item.order_id
     where online_order.tenant_id = p_tenant_id
  ), shaped as (
    select b.*,
           case
             when coalesce(b.product_type, 'product') = 'service' then 'service'
             when coalesce(b.purchase_treatment, 'inventory') = 'workshop_consumable' then 'consumable'
             when coalesce(b.is_set, false) then 'kit'
             else 'product'
           end as item_kind,
           greatest(coalesce(b.stock_quantity, 0), coalesce(b.inventory_qty, 0)) as raw_stock,
           case
             when coalesce(b.product_type, 'product') = 'service' then null::integer
             when coalesce(b.purchase_treatment, 'inventory') = 'workshop_consumable' then null::integer
             when not coalesce(b.track_stock, true) then null::integer
             when coalesce(b.is_set, false) then coalesce(sa.available_quantity, 0)
             else greatest(coalesce(b.stock_quantity, b.inventory_qty, 0) - coalesce(r.quantity, 0), 0)
           end as available_quantity,
           coalesce(s.counter_12m, 0) as counter_12m,
           coalesce(s.jobs_12m, 0) as jobs_12m,
           coalesce(s.total_12m, 0) as total_12m,
           (s.product_id is null and bo.product_id is null and o.product_id is null) as never_used,
           coalesce(
             nullif(btrim(b.website_image_url_optimized), ''),
             nullif(btrim(b.website_image_url), ''),
             (b.website_image_urls)[1],
             nullif(btrim(b.image_url_optimized), ''),
             nullif(btrim(b.image_url), ''),
             (b.image_urls)[1]
           ) as thumb
      from base b
      left join set_avail sa on sa.id = b.id
      left join reserved r on r.product_id = b.id
      left join sales s on s.product_id = b.id
      left join bought bo on bo.product_id = b.id
      left join ordered o on o.product_id = b.id
  ), stated as (
    select sh.*,
           case
             when sh.blk = 'workshop_consumable' then 'taller'
             when sh.blk in ('inactive', 'web_off') then 'oculto'
             when sh.blk is not null then 'falta'
             when sh.item_kind = 'service' then 'venta'
             when not coalesce(sh.track_stock, true) then 'venta'
             when coalesce(sh.available_quantity, 0) <= 0 then 'agotado'
             else 'venta'
           end as item_state
      from shaped sh
  ), flagged as (
    select st.*,
           array_remove(array[
             case when st.item_state = 'falta' then st.blk end,
             case
               when st.item_kind in ('product', 'kit')
                    and nullif(btrim(coalesce(st.gtin, '')), '') is null
                    and nullif(btrim(coalesce(st.barcode, '')), '') is null
                    and public.catalog_gtin_is_valid_v1(btrim(st.sku))
                 then 'gtin_in_sku'
             end,
             case
               when st.item_state in ('venta', 'agotado')
                    and st.item_kind <> 'service'
                    and nullif(btrim(coalesce(st.website_name, '')), '') is null
                 then 'no_web_name'
             end,
             case
               when st.item_state in ('venta', 'agotado')
                    and st.item_kind in ('product', 'kit')
                    and st.brand_id is null
                 then 'no_brand'
             end,
             case
               when st.item_kind = 'consumable' and st.counter_12m > 0
                 then 'counter_consumable'
             end,
             case
               when st.item_kind in ('product', 'kit')
                    and st.item_state in ('venta', 'agotado')
                    and coalesce(nullif(btrim(st.website_name), ''), st.name)
                        ~* '(rollo\s+(de\s+)?[0-9]|gruesa|caja de [0-9]|pack de [0-9]|\([0-9]+ ?(un|pcs|unid|u)\.?\))'
                 then 'bulk_pack'
             end,
             case
               when st.item_kind = 'product'
                    and st.is_active
                    and coalesce(st.price, 0) <= 0
                    and coalesce(st.cost, 0) <= 0
                    and st.raw_stock <= 0
                    and st.never_used
                 then 'empty_record'
             end
           ], null) as raw_issues
      from stated st
  )
  select f.id,
         f.name,
         f.website_name,
         f.sku,
         f.gtin,
         f.product_type,
         f.item_kind,
         f.category_id,
         f.category_name,
         f.brand_id,
         f.brand,
         f.price,
         coalesce(f.website_price, f.price),
         f.cost,
         f.tax_rate,
         case
           when f.item_kind in ('product', 'kit') and coalesce(f.cost, 0) > 0
             then ceil(f.cost * public.catalog_tax_factor_v1(f.tax_rate))
         end,
         f.thumb,
         nullif(btrim(coalesce(f.website_description, '')), '') is not null,
         coalesce(f.is_published, false) and coalesce(f.show_on_website, false),
         coalesce(f.is_active, false),
         f.web_clearance_until,
         f.website_price_mode,
         f.raw_stock,
         f.available_quantity,
         f.blk,
         f.item_state,
         f.counter_12m,
         f.jobs_12m,
         f.total_12m,
         array(
           select candidate.issue_code
             from unnest(f.raw_issues) as candidate(issue_code)
            where not exists (
              select 1
                from public.catalog_issue_dismissals dismissal
               where dismissal.tenant_id = p_tenant_id
                 and dismissal.product_id = f.id
                 and dismissal.issue = candidate.issue_code
            )
         ),
         f.updated_at
    from flagged f
   order by coalesce(nullif(btrim(f.website_name), ''), f.name), f.id;
end;
$$;

revoke all on function public.catalog_web_items_v1(uuid) from public, anon;
grant execute on function public.catalog_web_items_v1(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Lo que cambia la pantalla
-- ---------------------------------------------------------------------------

-- Un solo interruptor: «Vender en la web» escribe las dos marcas juntas.
-- Al encender se saltan los consumibles, los inactivos y lo que no tiene
-- clasificación de IVA (el checkout lo rechazaría), y se dice cuántos.
create or replace function public.catalog_set_web_sale_v1(
  p_tenant_id uuid,
  p_product_ids uuid[],
  p_on boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_ids uuid[];
  v_changed integer := 0;
  v_consumables integer := 0;
  v_inactive integer := 0;
  v_untaxed integer := 0;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  if p_on is null then
    raise exception 'catalog_web_sale_missing_value' using errcode = '22023';
  end if;

  select coalesce(array_agg(distinct requested.id), '{}'::uuid[])
    into v_ids
    from unnest(coalesce(p_product_ids, '{}'::uuid[])) as requested(id)
   where requested.id is not null;

  if p_on then
    select count(*) filter (where coalesce(p.product_type, 'product') <> 'service'
                              and p.purchase_treatment = 'workshop_consumable'),
           count(*) filter (where not coalesce(p.is_active, false)),
           count(*) filter (where (p.tax_rate is null or p.tax_rate not in (0, 0.19, 19))
                              and coalesce(p.is_active, false)
                              and not (coalesce(p.product_type, 'product') <> 'service'
                                       and p.purchase_treatment = 'workshop_consumable'))
      into v_consumables, v_inactive, v_untaxed
      from public.products p
     where p.tenant_id = p_tenant_id
       and p.id = any(v_ids);

    update public.products p
       set is_published = true,
           show_on_website = true,
           updated_at = now()
     where p.tenant_id = p_tenant_id
       and p.id = any(v_ids)
       and coalesce(p.is_active, false)
       and not (coalesce(p.product_type, 'product') <> 'service'
                and p.purchase_treatment = 'workshop_consumable')
       and p.tax_rate in (0, 0.19, 19)
       and not (coalesce(p.is_published, false) and coalesce(p.show_on_website, false));
    get diagnostics v_changed = row_count;
  else
    update public.products p
       set is_published = false,
           show_on_website = false,
           updated_at = now()
     where p.tenant_id = p_tenant_id
       and p.id = any(v_ids)
       and (coalesce(p.is_published, false) or coalesce(p.show_on_website, false));
    get diagnostics v_changed = row_count;
  end if;

  return jsonb_build_object(
    'changed', v_changed,
    'skipped_consumables', v_consumables,
    'skipped_inactive', v_inactive,
    'skipped_untaxed', v_untaxed
  );
end;
$$;

-- Copia al GTIN el código de barras real que está en el SKU (todos los
-- candidatos si p_product_ids es null). No toca el SKU; se deshace con
-- catalog_undo_sku_to_gtin_v1.
create or replace function public.catalog_copy_sku_to_gtin_v1(
  p_tenant_id uuid,
  p_product_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_ids uuid[];
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);

  with changed as (
    update public.products p
       set gtin = btrim(p.sku),
           updated_at = now()
     where p.tenant_id = p_tenant_id
       and (p_product_ids is null or p.id = any(p_product_ids))
       and coalesce(p.product_type, 'product') <> 'service'
       and nullif(btrim(coalesce(p.gtin, '')), '') is null
       and nullif(btrim(coalesce(p.barcode, '')), '') is null
       and public.catalog_gtin_is_valid_v1(btrim(p.sku))
    returning p.id
  )
  select coalesce(array_agg(changed.id), '{}'::uuid[]) into v_ids from changed;

  return jsonb_build_object('copied', cardinality(v_ids), 'product_ids', to_jsonb(v_ids));
end;
$$;

create or replace function public.catalog_undo_sku_to_gtin_v1(
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
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);

  update public.products p
     set gtin = null,
         updated_at = now()
   where p.tenant_id = p_tenant_id
     and p.id = any(coalesce(p_product_ids, '{}'::uuid[]))
     and p.gtin = btrim(p.sku);
  get diagnostics v_count = row_count;

  return jsonb_build_object('cleared', v_count);
end;
$$;

-- Liquidación: hasta esa fecha se puede vender bajo el costo. Null la quita.
create or replace function public.catalog_set_clearance_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_until date
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  if p_until is not null and p_until < current_date then
    raise exception 'catalog_clearance_in_the_past' using errcode = '22023';
  end if;

  update public.products p
     set web_clearance_until = p_until,
         updated_at = now()
   where p.tenant_id = p_tenant_id
     and p.id = p_product_id
     and coalesce(p.product_type, 'product') <> 'service';
  if not found then
    raise exception 'catalog_product_not_found' using errcode = 'P0002';
  end if;

  return jsonb_build_object('product_id', p_product_id, 'clearance_until', p_until);
end;
$$;

-- Cómo se muestra el precio: exacto, «desde» o «a cotizar» (sólo servicios).
create or replace function public.catalog_set_price_mode_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_mode text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  if p_mode is null or p_mode not in ('exact', 'from', 'quote') then
    raise exception 'catalog_price_mode_invalid' using errcode = '22023';
  end if;

  update public.products p
     set website_price_mode = p_mode,
         updated_at = now()
   where p.tenant_id = p_tenant_id
     and p.id = p_product_id
     and (p_mode <> 'quote' or coalesce(p.product_type, 'product') = 'service');
  if not found then
    raise exception 'catalog_product_not_found' using errcode = 'P0002';
  end if;

  return jsonb_build_object('product_id', p_product_id, 'price_mode', p_mode);
end;
$$;

-- Clasifica el IVA de productos que no lo tienen (19 o 0 = exento). Deja el
-- evento en product_tax_classification_events, como cualquier clasificación.
create or replace function public.catalog_classify_tax_v1(
  p_tenant_id uuid,
  p_product_ids uuid[],
  p_rate numeric
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_count integer;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  if p_rate is null or p_rate not in (0, 19) then
    raise exception 'catalog_tax_rate_invalid' using errcode = '22023';
  end if;

  perform set_config('app.product_tax_classification_source', 'website_catalog', true);
  perform set_config('app.product_tax_classification_reason', 'Clasificado desde Catálogo web › Por resolver', true);

  update public.products p
     set tax_rate = p_rate,
         updated_at = now()
   where p.tenant_id = p_tenant_id
     and p.id = any(coalesce(p_product_ids, '{}'::uuid[]))
     and (p.tax_rate is null or p.tax_rate not in (0, 0.19, 19));
  get diagnostics v_count = row_count;

  return jsonb_build_object('classified', v_count);
end;
$$;

-- Convierte entre producto de venta y consumible del taller.
--   * a consumible: con stock pasa por convert_product_inventory_to_non_stock
--     (asiento de inventario a 5101 y registro reversible); sin stock basta
--     cambiar el tratamiento. En los dos casos sale de la web (disparador).
--   * a producto de venta: empieza a llevar stock desde 0; lo comprado antes
--     ya fue gasto y no se toca.
create or replace function public.catalog_convert_item_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_target text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_product public.products;
  v_stock integer;
  v_reason text;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  if p_target is null or p_target not in ('inventory', 'workshop_consumable') then
    raise exception 'catalog_convert_target_invalid' using errcode = '22023';
  end if;

  select * into v_product
    from public.products p
   where p.tenant_id = p_tenant_id
     and p.id = p_product_id
   for update;
  if not found then
    raise exception 'catalog_product_not_found' using errcode = 'P0002';
  end if;
  if coalesce(v_product.product_type, 'product') = 'service' then
    raise exception 'catalog_convert_service' using errcode = '22023';
  end if;
  if coalesce(v_product.purchase_treatment, 'inventory') = p_target then
    return jsonb_build_object('product_id', p_product_id, 'purchase_treatment', p_target, 'changed', false);
  end if;

  v_reason := coalesce(nullif(btrim(p_reason), ''), case
    when p_target = 'workshop_consumable' then 'Catálogo web: es insumo del taller'
    else 'Catálogo web: se vende al público'
  end);
  v_stock := greatest(coalesce(v_product.inventory_qty, 0), coalesce(v_product.stock_quantity, 0));

  if p_target = 'workshop_consumable' and v_stock > 0 then
    perform public.convert_product_inventory_to_non_stock(
      p_product_id, 'workshop_consumable', 'product', v_reason
    );
  elsif p_target = 'workshop_consumable' then
    update public.products p
       set purchase_treatment = 'workshop_consumable',
           updated_at = now()
     where p.id = p_product_id;
  else
    update public.products p
       set purchase_treatment = 'inventory',
           track_stock = true,
           updated_at = now()
     where p.id = p_product_id;
    insert into public.user_activity_log (tenant_id, user_id, action, details, performed_by, created_at)
    values (
      p_tenant_id, auth.uid(), 'product_conversion_to_inventory',
      jsonb_build_object('product_id', p_product_id, 'product_name', v_product.name, 'reason', v_reason),
      auth.uid(), now()
    );
  end if;

  return jsonb_build_object('product_id', p_product_id, 'purchase_treatment', p_target, 'changed', true);
end;
$$;

-- «Dejar como está»: el aviso deja de salir en «Por resolver» (o vuelve).
create or replace function public.catalog_dismiss_issue_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_issue text,
  p_dismissed boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  if p_issue is null or p_issue not in (
    'missing_tax', 'gtin_in_sku', 'no_web_name', 'no_brand',
    'counter_consumable', 'bulk_pack', 'empty_record'
  ) then
    raise exception 'catalog_issue_invalid' using errcode = '22023';
  end if;

  if coalesce(p_dismissed, true) then
    insert into public.catalog_issue_dismissals (tenant_id, product_id, issue, dismissed_by)
    select p_tenant_id, p.id, p_issue, auth.uid()
      from public.products p
     where p.tenant_id = p_tenant_id and p.id = p_product_id
    on conflict (tenant_id, product_id, issue) do nothing;
  else
    delete from public.catalog_issue_dismissals d
     where d.tenant_id = p_tenant_id and d.product_id = p_product_id and d.issue = p_issue;
  end if;

  return jsonb_build_object('product_id', p_product_id, 'issue', p_issue, 'dismissed', coalesce(p_dismissed, true));
end;
$$;

-- Archiva fichas que no son productos: activas, a $0, sin costo, sin stock y
-- nunca vendidas, compradas ni pedidas. Lo vuelve a comprobar aquí.
create or replace function public.catalog_archive_empty_records_v1(
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
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);

  update public.products p
     set is_active = false,
         is_published = false,
         show_on_website = false,
         updated_at = now()
   where p.tenant_id = p_tenant_id
     and p.id = any(coalesce(p_product_ids, '{}'::uuid[]))
     and coalesce(p.product_type, 'product') = 'product'
     and coalesce(p.price, 0) <= 0
     and coalesce(p.cost, 0) <= 0
     and greatest(coalesce(p.stock_quantity, 0), coalesce(p.inventory_qty, 0)) <= 0
     and not exists (
       select 1
         from public.sales_invoices invoice
         cross join lateral jsonb_array_elements(
           case when jsonb_typeof(invoice.items) = 'array' then invoice.items else '[]'::jsonb end
         ) line
        where invoice.tenant_id = p_tenant_id
          and line ->> 'product_id' = p.id::text
     )
     and not exists (
       select 1 from public.purchase_invoice_lines purchase_line
        where purchase_line.tenant_id = p_tenant_id and purchase_line.product_id = p.id
     )
     and not exists (
       select 1 from public.online_order_items order_item where order_item.product_id = p.id
     );
  get diagnostics v_count = row_count;

  return jsonb_build_object('archived', v_count);
end;
$$;

-- Categorías con lo que tienen a la venta, sumando sus subcategorías.
create or replace function public.catalog_category_counts_v1(p_tenant_id uuid)
returns table (
  category_id uuid,
  name text,
  parent_id uuid,
  full_path text,
  level integer,
  sort_order integer,
  show_on_website boolean,
  subcategories integer,
  selling integer,
  out_of_stock integer,
  needs_attention integer,
  selling_direct integer
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);

  return query
  with recursive cat as (
    select c.id, c.name, c.parent_id, c.full_path, c.level, c.sort_order, c.show_on_website
      from public.product_categories c
     where c.tenant_id = p_tenant_id
       and c.is_active = true
  ), tree(root, id, depth) as (
    select cat.id, cat.id, 0 from cat
    union all
    select tree.root, child.id, tree.depth + 1
      from tree
      join cat child on child.parent_id = tree.id
     where tree.depth < 12
  ), items as (
    select i.id, i.category_id, i.state
      from public.catalog_web_items_v1(p_tenant_id) i
     where i.kind in ('product', 'kit')
  )
  select cat.id,
         cat.name,
         cat.parent_id,
         cat.full_path,
         cat.level,
         cat.sort_order,
         coalesce(cat.show_on_website, false),
         (select count(*)::integer from tree t where t.root = cat.id and t.depth > 0),
         (select count(*)::integer from tree t join items i on i.category_id = t.id where t.root = cat.id and i.state = 'venta'),
         (select count(*)::integer from tree t join items i on i.category_id = t.id where t.root = cat.id and i.state = 'agotado'),
         (select count(*)::integer from tree t join items i on i.category_id = t.id where t.root = cat.id and i.state = 'falta'),
         (select count(*)::integer from items i where i.category_id = cat.id and i.state = 'venta')
    from cat
   order by cat.full_path nulls last, cat.name;
end;
$$;

-- Los más vendidos en 12 meses que están en venta con al menos p_min_stock
-- disponibles, para proponerlos como destacados de la portada.
create or replace function public.catalog_featured_suggestions_v1(
  p_tenant_id uuid,
  p_limit integer default 16,
  p_min_stock integer default 2
)
returns table (
  product_id uuid,
  name text,
  web_price numeric,
  available integer,
  sold_total_12m integer,
  margin_pct numeric,
  image_url text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
#variable_conflict use_column
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);

  return query
  select i.id,
         coalesce(nullif(btrim(i.website_name), ''), i.name),
         i.web_price,
         i.available,
         i.sold_total_12m,
         case
           when coalesce(i.cost, 0) > 0 and i.web_price > 0
             then round(((i.web_price / public.catalog_tax_factor_v1(i.tax_rate)) - i.cost)
                        / (i.web_price / public.catalog_tax_factor_v1(i.tax_rate)) * 100, 0)
         end,
         i.image_url
    from public.catalog_web_items_v1(p_tenant_id) i
   where i.state = 'venta'
     and i.kind in ('product', 'kit')
     and coalesce(i.available, 0) >= greatest(coalesce(p_min_stock, 1), 1)
     and i.image_url is not null
   order by i.sold_total_12m desc, i.web_price desc, i.id
   limit least(greatest(coalesce(p_limit, 16), 1), 48);
end;
$$;

-- Reemplaza los destacados de la portada por la lista dada, en ese orden. La
-- tienda muestra los primeros que estén en venta: si uno se agota, entra el
-- siguiente (get_public_featured_products ya lee así).
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
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  perform pg_advisory_xact_lock(hashtextextended('catalog_featured:' || p_tenant_id::text, 0));

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

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.catalog_set_web_sale_v1(uuid, uuid[], boolean)',
    'public.catalog_copy_sku_to_gtin_v1(uuid, uuid[])',
    'public.catalog_undo_sku_to_gtin_v1(uuid, uuid[])',
    'public.catalog_set_clearance_v1(uuid, uuid, date)',
    'public.catalog_set_price_mode_v1(uuid, uuid, text)',
    'public.catalog_classify_tax_v1(uuid, uuid[], numeric)',
    'public.catalog_convert_item_v1(uuid, uuid, text, text)',
    'public.catalog_dismiss_issue_v1(uuid, uuid, text, boolean)',
    'public.catalog_archive_empty_records_v1(uuid, uuid[])',
    'public.catalog_category_counts_v1(uuid)',
    'public.catalog_featured_suggestions_v1(uuid, integer, integer)',
    'public.catalog_replace_featured_v1(uuid, uuid[])'
  ] loop
    execute format('revoke all on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated', v_signature);
  end loop;
end;
$$;

commit;
