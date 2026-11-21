-- Modelos con tallas y colores (2026-11-20).
--
-- El dueño, al ver que las tallas de un mismo producto salían como productos
-- sueltos: «¿no deberíamos generar variantes en una sola publicación?», y con
-- la ficha del lienzo aprobada, «sí, constrúyela en el ERP y la tienda».
--
-- Un modelo junta productos que son tallas o colores de lo mismo. Cada
-- variante sigue siendo su producto, con su stock, SKU, precio, plazo y
-- página. El modelo dice qué cambia entre ellas (ejes: «Color», «Talla», con
-- sus valores en orden) y cada variante dice cuál es (opciones). Lo arma el
-- equipo en Inventario › ficha del producto › «Modelo y variantes»
-- (product_model_save_v1).
--
-- La tienda lo pide con p_group_models y, sin el parámetro, todo responde lo
-- mismo que antes (la tienda publicada no cambia hasta su despliegue):
-- * la ficha recibe el modelo con sus variantes, cada una con la forma de un
--   producto de la tienda, para que la regla de stock, plazo y precio de la
--   tienda las juzgue igual que a la ficha misma
--   (get_public_product_page_v2 › model); en «relacionados» no salen las
--   otras tallas y de otro modelo va una sola;
-- * el listado junta cada modelo en una tarjeta (la representa la variante
--   que mejor se vende en esa búsqueda) con su resumen («2 colores · 3
--   tallas», precio menor y mayor), y los filtros y los conteos de la
--   búsqueda cuentan modelos;
-- * Google Merchant recibe el mismo item_group_id para las variantes de un
--   modelo (get_merchant_product_models_v1).

begin;

set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 1. Las tablas. Privadas: sólo se leen y escriben por las funciones de abajo.
-- ---------------------------------------------------------------------------

create table if not exists public.product_models (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  axes jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid,
  updated_by uuid,
  constraint product_models_tenant_id_id_key unique (tenant_id, id),
  constraint product_models_name_check
    check (length(btrim(name)) between 1 and 160),
  constraint product_models_axes_check
    check (jsonb_typeof(axes) = 'array' and jsonb_array_length(axes) between 1 and 3)
);

comment on table public.product_models is
  'Un modelo que junta productos que son tallas o colores de lo mismo (20261120230000). axes: [{"name":"Color","values":["Blanco/Negro","Negra"]},{"name":"Talla","values":["S/M","L/XL","XXL"]}], en el orden en que se muestran.';

create table if not exists public.product_model_members (
  product_id uuid primary key,
  tenant_id uuid not null,
  model_id uuid not null,
  options jsonb not null,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  -- El producto y el modelo son de la misma tienda que la variante.
  constraint product_model_members_product_fkey
    foreign key (tenant_id, product_id)
    references public.products (tenant_id, id) on delete cascade,
  constraint product_model_members_model_fkey
    foreign key (tenant_id, model_id)
    references public.product_models (tenant_id, id) on delete cascade,
  constraint product_model_members_options_check
    check (jsonb_typeof(options) = 'object')
);

comment on table public.product_model_members is
  'Cada variante de un modelo: su producto y cuál es (options: {"Color":"Negra","Talla":"XXL"}). Un producto está en un modelo a lo más (20261120230000).';

create index if not exists product_model_members_model_idx
  on public.product_model_members (tenant_id, model_id);
-- Dos variantes de un modelo no pueden ser la misma combinación.
create unique index if not exists product_model_members_options_uidx
  on public.product_model_members (model_id, options);

alter table public.product_models enable row level security;
alter table public.product_model_members enable row level security;
revoke all on public.product_models from public, anon, authenticated, service_role;
revoke all on public.product_model_members from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Lo que la tienda lee de un modelo.
-- ---------------------------------------------------------------------------

-- El resumen de cada modelo pedido: cuántas variantes se ven en la tienda,
-- cuántos valores de cada eje tienen, el precio menor y mayor (el de la
-- tienda: website_price o price) y cuáles se ven. Privada.
--
-- Ojo: get_public_products con una lista vacía de ids lee el catálogo entero
-- (491 productos el 2026-11-20); por eso cada lectura de acá vuelve antes si
-- no hay ids.
create or replace function public.product_model_summaries_internal_v1(
  p_tenant_id uuid,
  p_model_ids uuid[]
)
returns table (
  model_id uuid,
  name text,
  variant_count integer,
  axes jsonb,
  price_min numeric,
  price_max numeric,
  visible_ids uuid[]
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
#variable_conflict use_column
declare
  v_members uuid[];
begin
  select coalesce(array_agg(mm.product_id), '{}'::uuid[])
    into v_members
    from public.product_model_members mm
   where mm.tenant_id = p_tenant_id
     and mm.model_id = any(coalesce(p_model_ids, '{}'::uuid[]));
  if cardinality(v_members) = 0 then
    return;
  end if;

  return query
  with members as (
    select mm.model_id, mm.product_id, mm.options
      from public.product_model_members mm
     where mm.tenant_id = p_tenant_id
       and mm.product_id = any(v_members)
  ), visible as (
    -- La regla única de venta online decide qué variante se ve; la ficha
    -- puntual no filtra por stock (una talla agotada se ve tachada).
    select product.id, coalesce(p.website_price, product.price) as price
      from public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := v_members,
             p_only_in_stock := false,
             p_limit := 2147483647
           ) product
      join public.products p
        on p.tenant_id = p_tenant_id
       and p.id = product.id
  ), per_model as (
    select m.model_id,
           count(*)::integer as variant_count,
           min(v.price) as price_min,
           max(v.price) as price_max,
           array_agg(m.product_id) as visible_ids
      from members m
      join visible v on v.id = m.product_id
     group by m.model_id
  ), axis_values as (
    select m.model_id, a.key as axis, count(distinct a.value)::integer as value_count
      from members m
      join visible v on v.id = m.product_id
      cross join lateral jsonb_each_text(m.options) a
     group by m.model_id, a.key
  )
  select pm.id,
         pm.name,
         per_model.variant_count,
         coalesce((
           select jsonb_agg(
                    jsonb_build_object(
                      'name', ax.value ->> 'name',
                      'count', coalesce(av.value_count, 0))
                    order by ax.ordinality)
             from jsonb_array_elements(pm.axes) with ordinality ax(value, ordinality)
             left join axis_values av
               on av.model_id = pm.id
              and av.axis = ax.value ->> 'name'
         ), '[]'::jsonb),
         per_model.price_min,
         per_model.price_max,
         per_model.visible_ids
    from public.product_models pm
    join per_model on per_model.model_id = pm.id
   where pm.tenant_id = p_tenant_id;
end;
$function$;

revoke all on function public.product_model_summaries_internal_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;

-- El modelo de cada producto pedido que se ve en la tienda, si de su modelo
-- se ven dos o más: para la tarjeta de un relacionado o de una sugerencia
-- («2 colores · 3 tallas», «Desde $X»). Hasta 200 ids.
create or replace function public.get_public_product_models_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns table (
  product_id uuid,
  model_id uuid,
  model_name text,
  variant_count integer,
  axes jsonb,
  price_min numeric,
  price_max numeric
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
#variable_conflict use_column
declare
  v_ids uuid[] := (coalesce(p_product_ids, '{}'::uuid[]))[1:200];
  v_models uuid[];
begin
  if p_tenant_id is null or coalesce(cardinality(v_ids), 0) = 0 then
    return;
  end if;
  select coalesce(array_agg(distinct mm.model_id), '{}'::uuid[])
    into v_models
    from public.product_model_members mm
   where mm.tenant_id = p_tenant_id
     and mm.product_id = any(v_ids);
  if cardinality(v_models) = 0 then
    return;
  end if;

  return query
  select mm.product_id,
         summary.model_id,
         summary.name,
         summary.variant_count,
         summary.axes,
         summary.price_min,
         summary.price_max
    from public.product_model_members mm
    join public.product_model_summaries_internal_v1(p_tenant_id, v_models) summary
      on summary.model_id = mm.model_id
   where mm.tenant_id = p_tenant_id
     and mm.product_id = any(v_ids)
     -- Un producto que la tienda no muestra no dice de qué modelo es.
     and mm.product_id = any(summary.visible_ids)
     and summary.variant_count > 1;
end;
$function$;

revoke all on function public.get_public_product_models_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_models_v1(uuid, uuid[])
  to anon, authenticated, service_role;

-- La ficha: el modelo del producto y sus variantes que se ven en la tienda,
-- cada una con la forma de un producto de la tienda (la fila de
-- get_public_products sin el costo, con los campos web que la ficha también
-- lee) más sus opciones. La tienda las juzga (stock, plazo, precio) con su
-- misma regla. Null si el producto no está en un modelo, si no se ve, o si de
-- su modelo se ve uno solo.
create or replace function public.get_public_product_model_v1(
  p_tenant_id uuid,
  p_product_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_model_id uuid;
  v_name text;
  v_axes jsonb;
  v_ids uuid[];
  v_doc jsonb;
begin
  select pm.id, pm.name, pm.axes
    into v_model_id, v_name, v_axes
    from public.product_model_members mm
    join public.product_models pm
      on pm.tenant_id = mm.tenant_id
     and pm.id = mm.model_id
   where mm.tenant_id = p_tenant_id
     and mm.product_id = p_product_id;
  if v_model_id is null then
    return null;
  end if;

  select array_agg(mm.product_id)
    into v_ids
    from public.product_model_members mm
   where mm.tenant_id = p_tenant_id
     and mm.model_id = v_model_id;

  with visible as (
    select to_jsonb(product) - 'cost' - 'total_count' as row,
           product.id,
           product.name
      from public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := v_ids,
             p_only_in_stock := false,
             p_limit := 200
           ) product
  )
  select case
           when count(*) > 1 and bool_or(visible.id = p_product_id) then
             jsonb_build_object(
               'id', v_model_id,
               'name', v_name,
               'axes', v_axes,
               'variants', jsonb_agg(
                 visible.row
                   || to_jsonb(fields)
                   || jsonb_build_object(
                        'options', mm.options,
                        'position', mm.position)
                 order by mm.position, visible.name))
         end
    into v_doc
    from visible
    join public.product_model_members mm
      on mm.tenant_id = p_tenant_id
     and mm.product_id = visible.id
    join public.products p
      on p.tenant_id = p_tenant_id
     and p.id = visible.id
    cross join lateral (
      select p.website_name, p.website_price, p.website_price_mode,
             p.website_image_url, p.website_image_url_optimized,
             p.website_image_urls, p.price_currency
    ) fields;

  return v_doc;
end;
$function$;

revoke all on function public.get_public_product_model_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_model_v1(uuid, uuid)
  to anon, authenticated, service_role;

-- Google Merchant: el modelo de cada producto del feed (item_group_id), sus
-- ejes y sus opciones (g:size, g:color). La función del feed corre como
-- servicio y decide: un grupo con un solo producto en el feed no es grupo.
create or replace function public.get_merchant_product_models_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns table (
  product_id uuid,
  model_id uuid,
  model_name text,
  axes jsonb,
  options jsonb
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select mm.product_id, pm.id, pm.name, pm.axes, mm.options
    from public.product_model_members mm
    join public.product_models pm
      on pm.tenant_id = mm.tenant_id
     and pm.id = mm.model_id
   where mm.tenant_id = p_tenant_id
     and mm.product_id = any(coalesce(p_product_ids, '{}'::uuid[]));
$function$;

revoke all on function public.get_merchant_product_models_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_merchant_product_models_v1(uuid, uuid[])
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. Lo que hace el equipo en el ERP.
-- ---------------------------------------------------------------------------

-- Un modelo con todas sus variantes (también las que la tienda no muestra) y
-- lo que el equipo necesita ver de cada una. updated_at vuelve en el guardado
-- para que dos personas no se pisen.
create or replace function public.product_model_detail_internal_v1(
  p_tenant_id uuid,
  p_model_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select jsonb_build_object(
           'id', pm.id,
           'name', pm.name,
           'axes', pm.axes,
           'updated_at', pm.updated_at,
           'members', coalesce((
             select jsonb_agg(
                      jsonb_build_object(
                        'product_id', p.id,
                        'name', p.name,
                        'sku', p.sku,
                        'options', mm.options,
                        'position', mm.position,
                        'price', coalesce(p.website_price, p.price),
                        'stock', coalesce(p.stock_quantity, p.inventory_qty, 0),
                        'track_stock', coalesce(p.track_stock, true),
                        'is_active', coalesce(p.is_active, true),
                        'on_website', coalesce(p.is_published, false)
                          and coalesce(p.show_on_website, false),
                        'image', coalesce(
                          nullif(btrim(p.website_image_url_optimized), ''),
                          nullif(btrim(p.image_url_optimized), ''),
                          nullif(btrim(p.website_image_url), ''),
                          nullif(btrim(p.image_url), '')))
                      order by mm.position, p.name)
               from public.product_model_members mm
               join public.products p
                 on p.tenant_id = mm.tenant_id
                and p.id = mm.product_id
              where mm.tenant_id = p_tenant_id
                and mm.model_id = pm.id
           ), '[]'::jsonb)
         )
    from public.product_models pm
   where pm.tenant_id = p_tenant_id
     and pm.id = p_model_id;
$function$;

revoke all on function public.product_model_detail_internal_v1(uuid, uuid)
  from public, anon, authenticated, service_role;

-- El modelo de un producto, o null si está suelto.
create or replace function public.product_model_for_product_v1(
  p_tenant_id uuid,
  p_product_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_model uuid;
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);
  select mm.model_id
    into v_model
    from public.product_model_members mm
   where mm.tenant_id = p_tenant_id
     and mm.product_id = p_product_id;
  if v_model is null then
    return null;
  end if;
  return public.product_model_detail_internal_v1(p_tenant_id, v_model);
end;
$function$;

revoke all on function public.product_model_for_product_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.product_model_for_product_v1(uuid, uuid)
  to authenticated;

-- Los productos que se pueden sumar a un modelo. Sin texto, los que más se
-- parecen por nombre al producto (las otras tallas y colores de lo mismo:
-- «Rodillera Leatt 3DF 5.0 Negra XXL» junto a «… Blanco/Negro S/M»); con
-- texto, los que lo contienen en el nombre o el SKU. Un servicio no es
-- variante; los que ya están en otro modelo vienen marcados.
create or replace function public.product_model_candidates_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_query text default null,
  p_limit integer default 12
)
returns table (
  product_id uuid,
  name text,
  sku text,
  price numeric,
  stock integer,
  on_website boolean,
  image text,
  model_id uuid,
  model_name text,
  score real
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
#variable_conflict use_column
declare
  v_name text;
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
  v_limit integer := least(greatest(coalesce(p_limit, 12), 1), 40);
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);
  select p.name
    into v_name
    from public.products p
   where p.tenant_id = p_tenant_id
     and p.id = p_product_id;

  return query
  select p.id,
         p.name,
         p.sku,
         coalesce(p.website_price, p.price),
         coalesce(p.stock_quantity, p.inventory_qty, 0)::integer,
         coalesce(p.is_published, false) and coalesce(p.show_on_website, false),
         coalesce(
           nullif(btrim(p.website_image_url_optimized), ''),
           nullif(btrim(p.image_url_optimized), ''),
           nullif(btrim(p.website_image_url), ''),
           nullif(btrim(p.image_url), '')),
         mm.model_id,
         pm.name,
         case
           when v_query is not null then 1::real
           else similarity(p.name, coalesce(v_name, ''))
         end
    from public.products p
    left join public.product_model_members mm
      on mm.tenant_id = p.tenant_id
     and mm.product_id = p.id
    left join public.product_models pm
      on pm.tenant_id = mm.tenant_id
     and pm.id = mm.model_id
   where p.tenant_id = p_tenant_id
     and p.id is distinct from p_product_id
     and coalesce(p.product_type, 'product') <> 'service'
     and coalesce(p.is_active, true)
     and (
       (v_query is null
         and v_name is not null
         and similarity(p.name, v_name) >= 0.45)
       or (v_query is not null
         and (p.name ilike '%' || v_query || '%'
              or p.sku ilike '%' || v_query || '%'))
     )
   order by 10 desc, p.name
   limit v_limit;
end;
$function$;

revoke all on function public.product_model_candidates_v1(uuid, uuid, text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.product_model_candidates_v1(uuid, uuid, text, integer)
  to authenticated;

-- Guarda un modelo entero: nombre, ejes y variantes. Sin id lo crea. Las
-- variantes que se dejan fuera salen del modelo (su producto queda suelto);
-- un modelo sin variantes se borra. Con updated_at, se niega si otra persona
-- lo guardó después. Errores con código para la app:
-- product_model_invalid (detail: name | axes | members),
-- product_model_member_invalid (detail: el producto),
-- product_model_member_taken (detail: el producto, ya en otro modelo),
-- product_model_duplicate_options, product_model_not_found,
-- product_model_stale.
create or replace function public.product_model_save_v1(
  p_tenant_id uuid,
  p_model jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_actor uuid := auth.uid();
  v_id uuid := nullif(btrim(coalesce(p_model ->> 'id', '')), '')::uuid;
  v_expected timestamptz :=
    nullif(btrim(coalesce(p_model ->> 'updated_at', '')), '')::timestamptz;
  v_current timestamptz;
  v_name text := btrim(coalesce(p_model ->> 'name', ''));
  v_axes_in jsonb := coalesce(p_model -> 'axes', '[]'::jsonb);
  v_members_in jsonb := coalesce(p_model -> 'members', '[]'::jsonb);
  v_axes jsonb := '[]'::jsonb;
  v_axis jsonb;
  v_axis_name text;
  v_values jsonb;
  v_axis_names text[] := '{}';
  v_member jsonb;
  v_product uuid;
  v_options_in jsonb;
  v_options jsonb;
  v_members jsonb := '[]'::jsonb;
  v_seen uuid[] := '{}';
  v_taken uuid;
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);

  if length(v_name) not between 1 and 160 then
    raise exception 'product_model_invalid' using errcode = '22023',
      detail = 'name';
  end if;

  -- Los ejes: uno a tres, cada uno con nombre y sus valores en orden, sin
  -- repetir. Se guardan sin espacios de sobra.
  if jsonb_typeof(v_axes_in) is distinct from 'array'
     or jsonb_array_length(v_axes_in) not between 1 and 3 then
    raise exception 'product_model_invalid' using errcode = '22023',
      detail = 'axes';
  end if;
  for v_axis in select value from jsonb_array_elements(v_axes_in) loop
    if jsonb_typeof(v_axis) is distinct from 'object'
       or jsonb_typeof(v_axis -> 'values') is distinct from 'array' then
      raise exception 'product_model_invalid' using errcode = '22023',
        detail = 'axes';
    end if;
    v_axis_name := btrim(coalesce(v_axis ->> 'name', ''));
    if length(v_axis_name) not between 1 and 40
       or v_axis_name = any(v_axis_names)
       or jsonb_array_length(v_axis -> 'values') not between 1 and 40
       or exists (
         select 1
           from jsonb_array_elements(v_axis -> 'values') val
          where jsonb_typeof(val) is distinct from 'string'
             or length(btrim(val #>> '{}')) not between 1 and 60) then
      raise exception 'product_model_invalid' using errcode = '22023',
        detail = 'axes';
    end if;
    select jsonb_agg(btrim(val #>> '{}') order by ord)
      into v_values
      from jsonb_array_elements(v_axis -> 'values') with ordinality e(val, ord);
    if (select count(distinct val) from jsonb_array_elements_text(v_values) val)
       <> jsonb_array_length(v_values) then
      raise exception 'product_model_invalid' using errcode = '22023',
        detail = 'axes';
    end if;
    v_axes := v_axes || jsonb_build_array(
      jsonb_build_object('name', v_axis_name, 'values', v_values));
    v_axis_names := v_axis_names || v_axis_name;
  end loop;

  -- Las variantes: un producto de esta tienda (no un servicio), una vez, con
  -- un valor de cada eje que esté en su lista.
  if jsonb_typeof(v_members_in) is distinct from 'array'
     or jsonb_array_length(v_members_in) > 60 then
    raise exception 'product_model_invalid' using errcode = '22023',
      detail = 'members';
  end if;
  for v_member in select value from jsonb_array_elements(v_members_in) loop
    v_product := nullif(btrim(coalesce(v_member ->> 'product_id', '')), '')::uuid;
    v_options_in := v_member -> 'options';
    if v_product is null
       or v_product = any(v_seen)
       or jsonb_typeof(v_options_in) is distinct from 'object'
       or not exists (
         select 1
           from public.products p
          where p.tenant_id = p_tenant_id
            and p.id = v_product
            and coalesce(p.product_type, 'product') <> 'service')
       or exists (
         select 1
           from jsonb_each(v_options_in) o
          where jsonb_typeof(o.value) is distinct from 'string') then
      raise exception 'product_model_member_invalid' using errcode = '22023',
        detail = coalesce(v_product::text, '');
    end if;
    select coalesce(jsonb_object_agg(btrim(o.key), btrim(o.value)), '{}'::jsonb)
      into v_options
      from jsonb_each_text(v_options_in) o;
    if (select count(*) from jsonb_object_keys(v_options)) <> cardinality(v_axis_names) then
      raise exception 'product_model_member_invalid' using errcode = '22023',
        detail = v_product::text;
    end if;
    foreach v_axis_name in array v_axis_names loop
      if not exists (
        select 1
          from jsonb_array_elements(v_axes) ax
          cross join lateral jsonb_array_elements_text(ax -> 'values') val
         where ax ->> 'name' = v_axis_name
           and val = v_options ->> v_axis_name) then
        raise exception 'product_model_member_invalid' using errcode = '22023',
          detail = v_product::text;
      end if;
    end loop;
    select mm.model_id
      into v_taken
      from public.product_model_members mm
     where mm.tenant_id = p_tenant_id
       and mm.product_id = v_product;
    if v_taken is not null and v_taken is distinct from v_id then
      raise exception 'product_model_member_taken' using errcode = '23505',
        detail = v_product::text;
    end if;
    v_seen := v_seen || v_product;
    v_members := v_members || jsonb_build_array(
      jsonb_build_object('product_id', v_product, 'options', v_options));
  end loop;

  if (select count(distinct m.value -> 'options') from jsonb_array_elements(v_members) m)
     <> jsonb_array_length(v_members) then
    raise exception 'product_model_duplicate_options' using errcode = '23505';
  end if;

  if v_id is null then
    if jsonb_array_length(v_members) = 0 then
      raise exception 'product_model_invalid' using errcode = '22023',
        detail = 'members';
    end if;
    insert into public.product_models (tenant_id, name, axes, created_by, updated_by)
    values (p_tenant_id, v_name, v_axes, v_actor, v_actor)
    returning id into v_id;
  else
    select pm.updated_at
      into v_current
      from public.product_models pm
     where pm.tenant_id = p_tenant_id
       and pm.id = v_id
       for update;
    if not found then
      raise exception 'product_model_not_found' using errcode = 'P0002';
    end if;
    if v_expected is not null and v_current is distinct from v_expected then
      raise exception 'product_model_stale' using errcode = '40001';
    end if;
    update public.product_models pm
       set name = v_name,
           axes = v_axes,
           updated_at = clock_timestamp(),
           updated_by = v_actor
     where pm.tenant_id = p_tenant_id
       and pm.id = v_id;
  end if;

  -- Las variantes se reemplazan enteras (borrar y escribir, para que la llave
  -- única de las opciones no choque al intercambiar dos).
  delete from public.product_model_members mm
   where mm.tenant_id = p_tenant_id
     and mm.model_id = v_id;
  insert into public.product_model_members (product_id, tenant_id, model_id, options, position)
  select (m.value ->> 'product_id')::uuid,
         p_tenant_id,
         v_id,
         m.value -> 'options',
         (m.ordinality - 1)::integer
    from jsonb_array_elements(v_members) with ordinality m(value, ordinality);

  if jsonb_array_length(v_members) = 0 then
    delete from public.product_models pm
     where pm.tenant_id = p_tenant_id
       and pm.id = v_id;
    return null;
  end if;

  return public.product_model_detail_internal_v1(p_tenant_id, v_id);
end;
$function$;

revoke all on function public.product_model_save_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.product_model_save_v1(uuid, jsonb)
  to authenticated;

-- Desarma un modelo: sus productos quedan sueltos, como antes.
create or replace function public.product_model_delete_v1(
  p_tenant_id uuid,
  p_model_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  delete from public.product_models pm
   where pm.tenant_id = p_tenant_id
     and pm.id = p_model_id;
  if not found then
    raise exception 'product_model_not_found' using errcode = 'P0002';
  end if;
end;
$function$;

revoke all on function public.product_model_delete_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.product_model_delete_v1(uuid, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. El listado: una tarjeta por modelo cuando la tienda lo pide.
-- ---------------------------------------------------------------------------

-- Con un parámetro nuevo la firma cambia: se borra la vieja para no dejar dos
-- funciones con el mismo nombre (AGENT_DATABASE_CONTRACT, «Agregar un
-- parámetro con default NO reemplaza la función: la duplica»). Sin
-- p_group_models responde lo mismo que antes, más tres columnas en null.
drop function if exists public.get_public_products_faceted_v2(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text,
  integer, integer, boolean);

create function public.get_public_products_faceted_v2(
  p_tenant_id uuid,
  p_category_ids uuid[] default null::uuid[],
  p_search_term text default null::text,
  p_product_type text default null::text,
  p_only_in_stock boolean default true,
  p_brand_ids uuid[] default null::uuid[],
  p_min_price numeric default null::numeric,
  p_max_price numeric default null::numeric,
  p_spec_filters jsonb default null::jsonb,
  p_sort_by text default 'name'::text,
  p_limit integer default 20,
  p_offset integer default 0,
  p_include_out_of_stock boolean default false,
  p_group_models boolean default false
)
returns table (
  id uuid, tenant_id uuid, name text, sku text, barcode text, price numeric,
  cost numeric, inventory_qty integer, stock_quantity integer, image_url text,
  image_url_optimized text, image_urls text[], description text,
  website_description text, category text, category_id uuid,
  category_name text, brand_id uuid, brand text, model text,
  manufacturer text, manufacturer_sku text, gtin text, product_type text,
  track_stock boolean, is_active boolean, is_published boolean,
  show_on_website boolean, created_at timestamp with time zone,
  updated_at timestamp with time zone, total_count bigint,
  model_id uuid, model_name text, model_summary jsonb
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with args as (
    select
      case
        when p_min_price is null then null
        when p_min_price >= 0 then p_min_price
        else null
      end as min_price,
      case
        when p_max_price is null then null
        when p_max_price >= 0 then p_max_price
        else null
      end as max_price,
      (
        (p_min_price is null or p_min_price >= 0)
        and (p_max_price is null or p_max_price >= 0)
        and (
          p_min_price is null
          or p_max_price is null
          or p_min_price <= p_max_price
        )
      ) as is_valid
  ), spec_scope as (
    -- Technical-spec filters narrow the universe to the products that carry
    -- every requested value. Null means «no spec filter».
    select case
      when p_spec_filters is null or jsonb_typeof(p_spec_filters) <> 'object'
        or not exists (select 1 from jsonb_each(p_spec_filters) e where jsonb_typeof(e.value) = 'array' and jsonb_array_length(e.value) > 0)
      then null::uuid[]
      else coalesce((select array_agg(m.product_id) from public.spec_public_facet_matches_internal_v1(p_tenant_id, p_spec_filters) m), '{}'::uuid[])
    end as ids
  ), listed_rows as materialized (
    select product.*
    from public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := p_category_ids,
      p_search_term := p_search_term,
      p_product_type := p_product_type,
      -- The canonical RPC applies the site's publication stock policy first.
      -- Request its rule-allowed universe here, then apply the visitor's
      -- optional availability facet to the reservation-aware quantities it
      -- returns. A visitor can narrow a rule, never widen it, except a search
      -- the store lets them widen to what is out of stock
      -- (p_include_out_of_stock; the rule decides in get_public_products).
      p_only_in_stock := not coalesce(p_include_out_of_stock, false),
      p_sort_by := p_sort_by,
      p_limit := 2147483647,
      p_offset := 0
    ) with ordinality as product
  ), on_order as materialized (
    -- Lo que se vende a pedido (Inventario › ficha › «Se vende a pedido»,
    -- product_on_order_terms activo) entra al listado aunque esté en cero,
    -- después de lo que hay (20261120140000). Sin productos a pedido no hay
    -- fila acá y la lectura de abajo no corre.
    select found.ids
    from (
      select public.catalog_on_order_product_ids_internal_v1(p_tenant_id) as ids
    ) found
    where cardinality(found.ids) > 0
  ), on_order_rows as (
    -- La misma lectura canónica, pedida por id: la ficha puntual no filtra
    -- por stock, y la regla única de venta online sigue decidiendo.
    select product.*
    from on_order
    cross join lateral public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := p_category_ids,
      p_product_ids := on_order.ids,
      p_search_term := p_search_term,
      p_product_type := p_product_type,
      p_only_in_stock := false,
      p_sort_by := p_sort_by,
      p_limit := 2147483647,
      p_offset := 0
    ) with ordinality as product
    where not exists (
      select 1 from listed_rows listed where listed.id = product.id
    )
  ), base_rows as (
    select listed.* from listed_rows listed
    union all
    select on_order_row.* from on_order_rows on_order_row
  ), available_rows as (
    select base.*
    from base_rows base
    where not coalesce(p_only_in_stock, true)
      or base.product_type = 'service'
      or not coalesce(base.track_stock, true)
      or coalesce(base.stock_quantity, base.inventory_qty, 0) > 0
  ), filtered as (
    select base.*
    from available_rows base
    cross join args
    cross join spec_scope
    where args.is_valid
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
  ), ranked as (
    -- A search widened to what is out of stock lists what can be bought now
    -- first and what is out of stock after it, each by relevance, as the big
    -- stores do: «Incluir agotados» must not push the three tubes in stock
    -- below the 38 at zero (2026-10-24).
    select filtered.*,
      -- Lo que se compra ahora, después lo que llega a pedido y al final lo
      -- agotado de una búsqueda ampliada (20261120140000).
      case
        when filtered.product_type = 'service'
          or not coalesce(filtered.track_stock, true)
          or coalesce(filtered.stock_quantity, filtered.inventory_qty, 0) > 0
          then 0
        when exists (
          select 1 from on_order where filtered.id = any(on_order.ids)
        )
          then 1
        when coalesce(p_include_out_of_stock, false)
          then 2
        else 0
      end as out_last
    from filtered
  ), grouped as (
    -- Con p_group_models, un modelo es una tarjeta: la representa la variante
    -- que mejor se vende en esta búsqueda (lo que hay antes que lo que llega,
    -- y después el orden de la búsqueda). Sin el parámetro, cada producto es
    -- su propio grupo y nada cambia (20261120230000).
    select ranked.*,
      member.model_id as variant_model_id,
      row_number() over (
        partition by case
          when coalesce(p_group_models, false) and member.model_id is not null
            then member.model_id
          else ranked.id
        end
        order by ranked.out_last, ranked.ordinality
      ) as model_rank
    from ranked
    left join public.product_model_members member
      on member.product_id = ranked.id
     and member.tenant_id = p_tenant_id
  ), kept as (
    select grouped.* from grouped where grouped.model_rank = 1
  ), page_contract as (
    select
      least(greatest(coalesce(p_limit, 20), 1), 100)::bigint as page_limit,
      greatest(coalesce(p_offset, 0), 0)::bigint as requested_offset,
      count(*)::bigint as total_count
    from kept
  ), page_window as (
    -- The row contract carries total_count, so a non-empty result can never
    -- disappear solely because limit is zero or the requested offset is stale.
    -- Clamp to at least one row and to the start of the final valid page.
    select
      contract.page_limit,
      contract.total_count,
      case
        when contract.total_count = 0 then 0::bigint
        else least(
          contract.requested_offset,
          (
            (contract.total_count - 1) / contract.page_limit
          ) * contract.page_limit
        )
      end as page_offset
    from page_contract contract
  ), paged as (
    select kept.*, page.total_count as filtered_total
    from kept
    cross join page_window page
    order by kept.out_last, kept.ordinality
    limit (select page_limit from page_window)
    offset (select page_offset from page_window)
  ), summaries as (
    -- El resumen de cada modelo de la página, si de él se ven dos o más.
    -- Sin p_group_models no se lee nada y las tres columnas van en null.
    select s.*
    from public.product_model_summaries_internal_v1(
      p_tenant_id,
      case when coalesce(p_group_models, false) then (
        select coalesce(array_agg(distinct paged.variant_model_id), '{}'::uuid[])
          from paged
         where paged.variant_model_id is not null)
      else '{}'::uuid[] end
    ) s
    where s.variant_count > 1
  )
  select
    paged.id,
    paged.tenant_id,
    paged.name,
    paged.sku,
    paged.barcode,
    paged.price,
    paged.cost,
    paged.inventory_qty,
    paged.stock_quantity,
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
    paged.filtered_total,
    summary.model_id,
    summary.name,
    case when summary.model_id is not null then jsonb_build_object(
      'variants', summary.variant_count,
      'axes', summary.axes,
      'priceMin', summary.price_min,
      'priceMax', summary.price_max)
    end
  from paged
  left join summaries summary on summary.model_id = paged.variant_model_id
  order by paged.out_last, paged.ordinality
$function$;

revoke all on function public.get_public_products_faceted_v2(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text,
  integer, integer, boolean, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_products_faceted_v2(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, text,
  integer, integer, boolean, boolean)
  to anon, authenticated;

-- Los filtros cuentan lo que el listado muestra: con p_group_models, modelos.
drop function if exists public.get_public_product_facets_v2(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean);

create function public.get_public_product_facets_v2(
  p_tenant_id uuid,
  p_category_ids uuid[] default null::uuid[],
  p_search_term text default null::text,
  p_product_type text default null::text,
  p_only_in_stock boolean default true,
  p_brand_ids uuid[] default null::uuid[],
  p_min_price numeric default null::numeric,
  p_max_price numeric default null::numeric,
  p_spec_filters jsonb default null::jsonb,
  p_include_out_of_stock boolean default false,
  p_group_models boolean default false
)
returns table (
  facet_key text, value_id text, value_label text, item_count bigint,
  range_min numeric, range_max numeric
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with args as (
    select
      case
        when p_min_price is null then null
        when p_min_price >= 0 then p_min_price
        else null
      end as min_price,
      case
        when p_max_price is null then null
        when p_max_price >= 0 then p_max_price
        else null
      end as max_price,
      (
        (p_min_price is null or p_min_price >= 0)
        and (p_max_price is null or p_max_price >= 0)
        and (
          p_min_price is null
          or p_max_price is null
          or p_min_price <= p_max_price
        )
      ) as is_valid
  ), spec_filters as materialized (
    select e.key
    from jsonb_each(coalesce(p_spec_filters, '{}'::jsonb)) e
    where jsonb_typeof(e.value) = 'array' and jsonb_array_length(e.value) > 0
  ), spec_scope as materialized (
    -- Products satisfying every spec filter; null when there is none.
    select case when exists (select 1 from spec_filters)
      then coalesce((select array_agg(m.product_id) from public.spec_public_facet_matches_internal_v1(p_tenant_id, p_spec_filters) m), '{}'::uuid[])
      else null::uuid[] end as ids
  ), listed_universe as materialized (
    -- Load the canonical search/type/publication/site-stock universe exactly
    -- once. Every facet projection below is derived from this same
    -- reservation-aware snapshot, preventing duplicate full catalog scans.
    select product.*
    from public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := null,
      p_search_term := p_search_term,
      p_product_type := p_product_type,
      -- A search the store lets the visitor widen to what is out of stock.
      p_only_in_stock := not coalesce(p_include_out_of_stock, false),
      p_sort_by := 'name',
      p_limit := 2147483647,
      p_offset := 0
    ) product
  ), on_order as materialized (
    -- Lo que se vende a pedido (Inventario › ficha › «Se vende a pedido»,
    -- product_on_order_terms activo) entra al listado aunque esté en cero,
    -- después de lo que hay (20261120140000). Sin productos a pedido no hay
    -- fila acá y la lectura de abajo no corre.
    select found.ids
    from (
      select public.catalog_on_order_product_ids_internal_v1(p_tenant_id) as ids
    ) found
    where cardinality(found.ids) > 0
  ), on_order_universe as materialized (
    -- Los filtros cuentan lo mismo que lista el catálogo, a pedido incluido.
    select product.*
    from on_order
    cross join lateral public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := null,
      p_product_ids := on_order.ids,
      p_search_term := p_search_term,
      p_product_type := p_product_type,
      p_only_in_stock := false,
      p_sort_by := 'name',
      p_limit := 2147483647,
      p_offset := 0
    ) product
    where not exists (
      select 1 from listed_universe listed where listed.id = product.id
    )
  ), canonical_universe as materialized (
    -- group_key: el modelo con p_group_models (20261120230000); si no, el
    -- producto, y cada cifra queda como antes.
    select united.*,
      case
        when coalesce(p_group_models, false)
          then coalesce(member.model_id, united.id)
        else united.id
      end as group_key
    from (
      select listed.* from listed_universe listed
      union all
      select on_order_row.* from on_order_universe on_order_row
    ) united
    left join public.product_model_members member
      on member.product_id = united.id
     and member.tenant_id = p_tenant_id
  ), available_universe as materialized (
    select base.*
    from canonical_universe base
    where not coalesce(p_only_in_stock, true)
      or base.product_type = 'service'
      or not coalesce(base.track_stock, true)
      or coalesce(base.stock_quantity, base.inventory_qty, 0) > 0
  ), selected_category_rows as materialized (
    -- Brand and price metadata respect the active category selection. This is
    -- the exact direct-ID predicate owned by the canonical product RPC, now
    -- applied after its single unselected-universe call.
    select base.*
    from available_universe base
    where p_category_ids is null
      or cardinality(p_category_ids) = 0
      or base.category_id = any(p_category_ids)
  ), spec_values as materialized (
    -- The technical values of the products these facets describe, not of
    -- the whole store: a category page computes its own few.
    select *
    from public.spec_public_facet_values_compute_internal_v1(
      p_tenant_id,
      (select coalesce(array_agg(s.id), '{}'::uuid[]) from selected_category_rows s)
    )
  ), category_filtered_rows as materialized (
    -- Category options and the summary deliberately exclude the current
    -- category selection while respecting every other active facet.
    select base.*
    from available_universe base
    cross join args
    cross join spec_scope
    where args.is_valid
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
  ), category_rows as (
    -- Keep direct counts for every active canonical category. The category
    -- publication owner decides which IDs become visible filter options, so a
    -- hidden descendant can still roll up into its visible published ancestor.
    select
      'category'::text as facet_key,
      base.category_id::text as value_id,
      nullif(btrim(canonical_category.name), '') as value_label,
      count(distinct base.group_key)::bigint as item_count,
      null::numeric as range_min,
      null::numeric as range_max
    from category_filtered_rows base
    join public.product_categories canonical_category
      on canonical_category.id = base.category_id
     and canonical_category.tenant_id = p_tenant_id
     and canonical_category.is_active = true
    group by base.category_id, canonical_category.name
  ), summary_rows as (
    -- This is the exact total for the category-option universe. It includes
    -- uncategorized products, so consumers must not derive "Todas" by summing
    -- only the category rows.
    select
      'summary'::text as facet_key,
      null::text as value_id,
      null::text as value_label,
      count(distinct category_filtered_rows.group_key)::bigint as item_count,
      null::numeric as range_min,
      null::numeric as range_max
    from category_filtered_rows
  ), brand_rows as (
    -- Brand counts exclude the current brand selection, but respect every
    -- other active facet so alternatives remain useful and truthful.
    select
      'brand'::text as facet_key,
      base.brand_id::text as value_id,
      coalesce(nullif(btrim(canonical_brand.name), ''), nullif(btrim(base.brand), ''))
        as value_label,
      count(distinct base.group_key)::bigint as item_count,
      null::numeric as range_min,
      null::numeric as range_max
    from selected_category_rows base
    cross join args
    cross join spec_scope
    left join public.product_brands canonical_brand
      on canonical_brand.id = base.brand_id
     and (
       canonical_brand.tenant_id is null
       or canonical_brand.tenant_id = p_tenant_id
     )
    where args.is_valid
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
      and base.brand_id is not null
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
    group by
      base.brand_id,
      coalesce(nullif(btrim(canonical_brand.name), ''), nullif(btrim(base.brand), ''))
  ), price_rows as (
    -- Price bounds exclude the current price range, but respect the selected
    -- brands and every route/publication/availability filter.
    select
      'price'::text as facet_key,
      null::text as value_id,
      null::text as value_label,
      count(distinct base.group_key)::bigint as item_count,
      min(base.price)::numeric as range_min,
      max(base.price)::numeric as range_max
    from selected_category_rows base
    cross join args
    cross join spec_scope
    where args.is_valid
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
  ), spec_matches_by_key as materialized (
    -- For a key the visitor already filters on, its alternatives are counted
    -- against the other keys only (as brands do with the brand selection).
    select k.key as excluded_key, m.product_id
    from spec_filters k
    cross join lateral public.spec_public_facet_matches_internal_v1(p_tenant_id, p_spec_filters, k.key) m
  ), spec_scope_rows as materialized (
    -- The products the visitor is looking at once every non-spec facet and
    -- the spec filters apply: the denominator that says whether a spec facet
    -- describes this collection or only a corner of it.
    select base.id, base.group_key
    from selected_category_rows base
    cross join args
    cross join spec_scope
    where args.is_valid
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
      and (spec_scope.ids is null or base.id = any(spec_scope.ids))
  ), spec_coverage as materialized (
    select v.spec_key, count(distinct s.group_key)::numeric as covered
    from spec_scope_rows s
    join spec_values v on v.product_id = s.id
    group by v.spec_key
  ), spec_rows as (
    -- One row per value. range_min carries how many products of the scope
    -- have this key at all, range_max how many products the scope holds, so
    -- the client can hide a facet that describes a small corner only.
    select
      ('spec:' || v.spec_key || ':' || v.data_type || ':' || coalesce(v.unit, ''))::text as facet_key,
      v.value_text as value_id,
      v.spec_label as value_label,
      count(distinct base.group_key)::bigint as item_count,
      (select c.covered from spec_coverage c where c.spec_key = v.spec_key) as range_min,
      (select count(distinct s.group_key)::numeric from spec_scope_rows s) as range_max
    from selected_category_rows base
    cross join args
    cross join spec_scope
    join spec_values v on v.product_id = base.id
    where args.is_valid
      and (
        p_brand_ids is null
        or cardinality(p_brand_ids) = 0
        or base.brand_id = any(p_brand_ids)
      )
      and (args.min_price is null or base.price >= args.min_price)
      and (args.max_price is null or base.price <= args.max_price)
      and (
        case when exists (select 1 from spec_filters k where k.key = v.spec_key)
          then exists (select 1 from spec_matches_by_key m where m.excluded_key = v.spec_key and m.product_id = base.id)
          else spec_scope.ids is null or base.id = any(spec_scope.ids)
        end
      )
    group by v.spec_key, v.data_type, v.unit, v.value_text, v.spec_label
  )
  select * from category_rows
  where value_label is not null
  union all
  select * from brand_rows
  where value_label is not null
  union all
  select * from price_rows
  union all
  select * from summary_rows
  union all
  select * from spec_rows
  order by facet_key, value_label nulls first, value_id nulls first;
$function$;

revoke all on function public.get_public_product_facets_v2(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_facets_v2(
  uuid, uuid[], text, text, boolean, uuid[], numeric, numeric, jsonb, boolean, boolean)
  to anon, authenticated;

-- Las cifras por categoría de una búsqueda, con la misma regla.
drop function if exists public.get_public_search_category_counts_v1(uuid, text, boolean);

create function public.get_public_search_category_counts_v1(
  p_tenant_id uuid,
  p_search_term text,
  p_include_out_of_stock boolean default false,
  p_group_models boolean default false
)
returns table (category_id uuid, item_count bigint)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with listed as materialized (
    select found.id, found.category_id
    from public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := null,
      p_search_term := p_search_term,
      p_product_type := 'product',
      p_only_in_stock := not coalesce(p_include_out_of_stock, false),
      p_sort_by := 'name',
      p_limit := 2147483647,
      p_offset := 0
    ) found
  ), on_order as materialized (
    -- Lo que se vende a pedido (Inventario › ficha › «Se vende a pedido»,
    -- product_on_order_terms activo) entra al listado aunque esté en cero,
    -- después de lo que hay (20261120140000). Sin productos a pedido no hay
    -- fila acá y la lectura de abajo no corre.
    select found.ids
    from (
      select public.catalog_on_order_product_ids_internal_v1(p_tenant_id) as ids
    ) found
    where cardinality(found.ids) > 0
  ), universe as (
    select listed.id, listed.category_id from listed
    union all
    -- Las mismas cifras que el listado de la búsqueda, a pedido incluido.
    select found.id, found.category_id
    from on_order
    cross join lateral public.get_public_products(
      p_tenant_id := p_tenant_id,
      p_category_ids := null,
      p_product_ids := on_order.ids,
      p_search_term := p_search_term,
      p_product_type := 'product',
      p_only_in_stock := false,
      p_sort_by := 'name',
      p_limit := 2147483647,
      p_offset := 0
    ) found
    where not exists (select 1 from listed where listed.id = found.id)
  )
  -- Con p_group_models un modelo cuenta una vez (20261120230000).
  select found.category_id,
         count(distinct case
           when coalesce(p_group_models, false)
             then coalesce(member.model_id, found.id)
           else found.id
         end)::bigint as item_count
  from universe found
  join public.product_categories category
    on category.id = found.category_id
   and category.tenant_id = p_tenant_id
   and category.is_active = true
  left join public.product_model_members member
    on member.product_id = found.id
   and member.tenant_id = p_tenant_id
  group by found.category_id
$function$;

revoke all on function public.get_public_search_category_counts_v1(uuid, text, boolean, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_search_category_counts_v1(uuid, text, boolean, boolean)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. La ficha: con p_group_models, el modelo; en relacionados, sin las otras
--    tallas y una sola de cada modelo. Sin el parámetro, lo de antes.
-- ---------------------------------------------------------------------------

drop function if exists public.get_public_product_page_v2(uuid, text, uuid);

create function public.get_public_product_page_v2(
  p_tenant_id uuid,
  p_sku text default null::text,
  p_product_id uuid default null::uuid,
  p_group_models boolean default false
)
returns jsonb
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  with base as (
    select to_jsonb(product) - 'cost' - 'total_count' as row,
           product.id,
           product.category_id,
           product.brand_id
      from public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := case
               when p_product_id is not null then array[p_product_id]
             end,
             p_sku := case when p_product_id is null then p_sku end,
             p_only_in_stock := false,
             p_limit := 1
           ) product
     -- Without a SKU or an id the listing would return any product.
     where p_product_id is not null or nullif(btrim(p_sku), '') is not null
     limit 1
  ),
  pool as (
    -- Up to 48 of the category in stock, in the catalog's order; the fit
    -- ranks them below.
    select to_jsonb(other) - 'cost' - 'total_count' - 'ordinality' as row,
           other.id,
           other.brand_id,
           other.ordinality as position
      from base
      cross join lateral public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_category_ids := array[base.category_id],
             p_only_in_stock := true,
             p_limit := 49
           ) with ordinality other
     where base.category_id is not null
       and other.id <> base.id
  ),
  pool_models as (
    -- 20261120230000: con p_group_models, el modelo de la ficha y de cada
    -- candidato. Sin el parámetro no se lee nada y no hay modelos.
    select found.product_id, found.model_id, found.model_name,
           found.variant_count, found.axes, found.price_min, found.price_max
      from public.get_public_product_models_v1(
             p_tenant_id,
             case when coalesce(p_group_models, false) then
               array(select pool.id from pool) || array(select base.id from base)
             else '{}'::uuid[] end
           ) found
  ),
  candidates as (
    -- Las otras tallas del mismo modelo no son «relacionados» (están en el
    -- selector de la ficha) y de otro modelo va uno solo.
    select ranked.row, ranked.id, ranked.brand_id, ranked.position
      from (
        select pool.row, pool.id, pool.brand_id, pool.position,
               model.model_id,
               row_number() over (
                 partition by coalesce(model.model_id, pool.id)
                 order by pool.position
               ) as model_rank
          from pool
          left join pool_models model on model.product_id = pool.id
      ) ranked
     where ranked.model_rank = 1
       and (
         ranked.model_id is null
         or ranked.model_id is distinct from (
           select own.model_id
             from pool_models own
             join base on base.id = own.product_id)
       )
  ),
  fit as (
    select score.product_id, score.shared
      from base
      cross join lateral public.get_public_related_fit_v1(
             p_tenant_id,
             base.id,
             (select array_agg(candidates.id) from candidates)
           ) score
  ),
  scored as (
    select candidates.row, candidates.id, candidates.brand_id,
           candidates.position as catalog_position,
           coalesce(fit.shared, 0) as shared,
           max(coalesce(fit.shared, 0)) over () as best
      from candidates
      left join fit on fit.product_id = candidates.id
  ),
  related as (
    -- The ones that share more of the product's filterable spec values
    -- first (a 700 x 23C road tyre: other 700c road tyres), then the
    -- catalog's order. When some share a value, the ones that share none
    -- are left out (no 20-inch tyre under a road tyre); when none do, the
    -- category in the catalog's order, as before.
    select scored.row, scored.id, scored.brand_id,
           row_number() over (
             order by scored.shared desc, scored.catalog_position
           ) as position
      from scored
     where scored.best = 0 or scored.shared > 0
     order by 4
     limit 9
  ),
  fits as (
    -- What goes with the product: the tubes that fit a tyre, the tyres a
    -- tube fits (20261024020000), cheapest first.
    select to_jsonb(item) - 'cost' - 'total_count' as row,
           item.id,
           item.brand_id,
           fit.kind,
           fit.fit_position as position
      from base
      cross join lateral public.get_public_product_fits_v1(
             p_tenant_id, base.id, 6) fit
      join lateral public.get_public_products(
             p_tenant_id := p_tenant_id,
             p_product_ids := array[fit.product_id],
             p_only_in_stock := true,
             p_limit := 1
           ) item on true
  ),
  website as (
    select p.id, to_jsonb(fields) as fields
      from public.products p
      cross join lateral (
        select p.is_set, p.set_type, p.parent_set_id, p.component_label,
               p.component_position, p.website_name, p.website_price,
               p.website_price_mode, p.website_description, p.website_seo_title,
               p.website_seo_description, p.website_search_terms,
               p.website_merchant_title, p.website_merchant_description,
               p.website_merchant_brand, p.website_merchant_gtin,
               p.website_merchant_mpn, p.website_google_product_category,
               p.website_image_url, p.website_image_url_optimized,
               p.website_image_urls, p.price_currency
      ) fields
     where p.tenant_id = p_tenant_id
       and p.id in (
         select id from base
         union all select id from related
         union all select id from fits
       )
  )
  select jsonb_build_object(
    'product', base.row || coalesce(
      (select website.fields from website where website.id = base.id),
      '{}'::jsonb),
    -- Raw rows of this store's or global brands: the client decides with
    -- canonicalPublicProductBrandNames, the rule the Flutter store applies.
    'brand_rows', coalesce((
      select jsonb_agg(to_jsonb(brand))
        from (
          select b.id, b.name, b.tenant_id, b.is_active
            from public.product_brands b
           where b.is_active
             and (b.tenant_id = p_tenant_id or b.tenant_id is null)
             and b.id in (
               select base.brand_id
               union
               select related.brand_id from related
               union
               select fits.brand_id from fits
             )
        ) brand
    ), '[]'::jsonb),
    'specs', coalesce((
      select jsonb_agg(to_jsonb(spec))
        from public.get_public_product_technical_specs(p_tenant_id, base.id) spec
    ), '[]'::jsonb),
    'related', coalesce((
      select jsonb_agg(
               related.row
                 || coalesce(website.fields, '{}'::jsonb)
                 -- Con p_group_models, el modelo del relacionado para su
                 -- tarjeta («2 colores · 3 tallas», «Desde $X»).
                 || coalesce((
                      select jsonb_build_object(
                               'model_id', model.model_id,
                               'model_name', model.model_name,
                               'model_summary', jsonb_build_object(
                                 'variants', model.variant_count,
                                 'axes', model.axes,
                                 'priceMin', model.price_min,
                                 'priceMax', model.price_max))
                        from pool_models model
                       where model.product_id = related.id), '{}'::jsonb)
               order by related.position)
        from related
        left join website on website.id = related.id
    ), '[]'::jsonb),
    'fits', coalesce((
      select jsonb_build_object(
               'kind', min(fits.kind),
               'items', jsonb_agg(
                 fits.row || coalesce(website.fields, '{}'::jsonb)
                 order by fits.position))
        from fits
        left join website on website.id = fits.id
    ), '{}'::jsonb)
  )
  -- El modelo de la ficha con sus variantes, sólo si la tienda lo pide.
  || case
       when coalesce(p_group_models, false) then jsonb_build_object(
         'model', public.get_public_product_model_v1(p_tenant_id, base.id))
       else '{}'::jsonb
     end
    from base;
$function$;

revoke all on function public.get_public_product_page_v2(uuid, text, uuid, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_product_page_v2(uuid, text, uuid, boolean)
  to anon, authenticated, service_role;

commit;
