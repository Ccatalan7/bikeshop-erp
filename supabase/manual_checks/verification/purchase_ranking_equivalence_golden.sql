-- Arnés golden de equivalencia de `rank_purchase_candidates_v1`.
--
-- **Para qué.** El corte 1 de la Fase B2 extrae el cuerpo de scoring del
-- ranking a un dueño único y deja `rank_purchase_candidates_v1` delegando. Es
-- la función caliente del módulo: la única forma honesta de aprobar esa
-- extracción es demostrar que su salida no cambia **en ningún camino**.
--
-- **Cómo se usa.** Se corre antes del cambio y después, y se comparan los dos
-- archivos:
--
--   bash scripts/db/query.sh local \
--     --file supabase/manual_checks/verification/purchase_ranking_equivalence_golden.sql \
--     > antes.txt
--   …se aplica el cambio…
--   bash scripts/db/query.sh local --file …golden.sql > despues.txt
--   diff antes.txt despues.txt        # tiene que estar vacío
--
-- `asOf` es `clock_timestamp()` y se quita de la comparación: es lo único que
-- debe variar entre dos corridas.
--
-- **La fixture es propia y se revierte.** La base local no tiene ninguna fila
-- en `purchase_candidate_metrics_v1`, así que el arnés siembra su propia cadena
-- de compra —factura, líneas, productos, proveedores, marcas— y hace `rollback`
-- al final. Los identificadores son fijos para que la salida sea reproducible.
--
-- **Los siete caminos que cubre**, cada uno × 3 perfiles × 4 valores de gama ×
-- 3 cortes (`p_limit` 10/2/1) = 252 casos:
--   1. producto exacto                       (`p_product_id`)
--   2. categoría con descendientes           (`p_category_id`)
--   3. texto que coincide por producto       (`p_query`)
--   4. texto que coincide SÓLO por proveedor (`p_query`)  ← el que rompe
--      cualquier diseño que colapse el universo a `product_ids`
--   5. texto sin coincidencias               (`verifiedEmpty`)
--   6. categoría sin candidatos históricos   (`verifiedEmpty`)
--   7. categoría hija, contada aparte de su raíz
--
-- Los tres cortes existen porque con `p_limit 10` sobre tres candidatos una
-- implementación que recorte ANTES de puntuar daría la misma salida por
-- accidente. Con `limit 1` no.

begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants(id, shop_name, currency, timezone) values (
  '99e50000-0000-4000-8000-000000000001',
  'Ranking Equivalence Tenant', 'CLP', 'America/Santiago'
);
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '99e50000-0000-4000-8000-000000000099',
  'authenticated', 'authenticated', 'ranking-equivalence@example.invalid', '',
  now(), '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles(
  user_id, tenant_id, role, permissions, is_active
) values (
  '99e50000-0000-4000-8000-000000000099',
  '99e50000-0000-4000-8000-000000000001',
  'admin', '{}'::jsonb, true
);

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', '99e50000-0000-4000-8000-000000000099',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  '99e50000-0000-4000-8000-000000000099',
  true
);

insert into public.product_categories(
  id, tenant_id, name, full_path, level, is_active
) values
  (
    '99e50000-0000-4000-8000-000000000011',
    '99e50000-0000-4000-8000-000000000001',
    'Cadenas', 'Transmisión / Cadenas', 1, true
  ),
  (
    '99e50000-0000-4000-8000-000000000012',
    '99e50000-0000-4000-8000-000000000001',
    'Cadenas MTB', 'Transmisión / Cadenas / MTB', 2, true
  ),
  (
    '99e50000-0000-4000-8000-000000000013',
    '99e50000-0000-4000-8000-000000000001',
    'Sin Compras', 'Transmisión / Sin Compras', 1, true
  );
update public.product_categories
set parent_id = '99e50000-0000-4000-8000-000000000011'
where id = '99e50000-0000-4000-8000-000000000012';

insert into public.product_brands(id, tenant_id, name, is_active) values
  (
    '99e50000-0000-4000-8000-000000000021',
    '99e50000-0000-4000-8000-000000000001', 'KMC', true
  ),
  (
    '99e50000-0000-4000-8000-000000000022',
    '99e50000-0000-4000-8000-000000000001', 'Shimano', true
  );

-- Tres productos: uno con `brand_id`, uno sólo con el texto legado y uno sin
-- marca. Es el reparto real del catálogo, en miniatura.
insert into public.products(
  id, tenant_id, name, sku, category_id, brand_id, brand, is_active, price,
  tax_rate, track_stock, stock_quantity
) values
  (
    '99e50000-0000-4000-8000-000000000031',
    '99e50000-0000-4000-8000-000000000001',
    'Cadena KMC X10 116L', 'KMC-X10',
    '99e50000-0000-4000-8000-000000000011',
    '99e50000-0000-4000-8000-000000000021', null, true, 24990, 19, true, 5
  ),
  (
    '99e50000-0000-4000-8000-000000000032',
    '99e50000-0000-4000-8000-000000000001',
    'Cadena Shimano HG54', 'SHI-HG54',
    '99e50000-0000-4000-8000-000000000012',
    null, 'Shimano', true, 29990, 19, true, 2
  ),
  (
    '99e50000-0000-4000-8000-000000000033',
    '99e50000-0000-4000-8000-000000000001',
    'Cadena genérica 10v', 'GEN-10',
    '99e50000-0000-4000-8000-000000000011',
    null, null, true, 9990, 19, true, 0
  );

-- Dos proveedores. El segundo se llama de forma que ningún producto contiene
-- su nombre: es el que hace posible el camino 4.
insert into public.suppliers(id, tenant_id, name, comuna, city) values
  (
    '99e50000-0000-4000-8000-000000000041',
    '99e50000-0000-4000-8000-000000000001',
    'Distribuidora Andes', 'Providencia', 'Santiago'
  ),
  (
    '99e50000-0000-4000-8000-000000000042',
    '99e50000-0000-4000-8000-000000000001',
    'Importadora Zafiro', 'Ñuñoa', 'Santiago'
  );

insert into public.purchase_invoices(
  id, tenant_id, supplier_id, supplier_name, invoice_number, date, status,
  tax_treatment
) values
  (
    '99e50000-0000-4000-8000-000000000051',
    '99e50000-0000-4000-8000-000000000001',
    '99e50000-0000-4000-8000-000000000041', 'Distribuidora Andes',
    'EQ-0001', current_date - 30, 'paid', 'no_tax'
  ),
  (
    '99e50000-0000-4000-8000-000000000052',
    '99e50000-0000-4000-8000-000000000001',
    '99e50000-0000-4000-8000-000000000042', 'Importadora Zafiro',
    'EQ-0002', current_date - 200, 'received', 'no_tax'
  );

insert into public.purchase_invoice_lines(
  id, tenant_id, purchase_invoice_id, line_number, product_id, description,
  quantity, net_amount, line_kind, line_nature, classification_status,
  currency_code
) values
  (
    '99e50000-0000-4000-8000-000000000061',
    '99e50000-0000-4000-8000-000000000001',
    '99e50000-0000-4000-8000-000000000051', 1,
    '99e50000-0000-4000-8000-000000000031',
    'Cadena KMC X10 116L', 4, 40000,
    'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99e50000-0000-4000-8000-000000000062',
    '99e50000-0000-4000-8000-000000000001',
    '99e50000-0000-4000-8000-000000000051', 2,
    '99e50000-0000-4000-8000-000000000032',
    'Cadena Shimano HG54', 2, 30000,
    'item', 'inventory', 'classified', 'CLP'
  ),
  (
    '99e50000-0000-4000-8000-000000000063',
    '99e50000-0000-4000-8000-000000000001',
    '99e50000-0000-4000-8000-000000000052', 1,
    '99e50000-0000-4000-8000-000000000033',
    'Cadena genérica 10v', 10, 50000,
    'item', 'inventory', 'classified', 'CLP'
  ),
  -- El mismo producto en dos proveedores: dos `candidate_id` distintos para el
  -- mismo `product_id`. Colapsar a producto los fundiría.
  (
    '99e50000-0000-4000-8000-000000000064',
    '99e50000-0000-4000-8000-000000000001',
    '99e50000-0000-4000-8000-000000000052', 2,
    '99e50000-0000-4000-8000-000000000031',
    'Cadena KMC X10 116L', 3, 33000,
    'item', 'inventory', 'classified', 'CLP'
  );

-- ───────────────────────────── la captura ──────────────────────────────────
--
-- Una fila por caso, ordenada, con la salida sin `asOf`. `\pset` fija el
-- formato para que el diff no dependa de la configuración del cliente.
\pset format unaligned
\pset tuples_only on
\pset pager off

with cases as (
  select * from (values
    ('01-exact',          null::text, '99e50000-0000-4000-8000-000000000031'::uuid, null::uuid),
    ('02-category-root',  null,       null, '99e50000-0000-4000-8000-000000000011'::uuid),
    ('03-category-child', null,       null, '99e50000-0000-4000-8000-000000000012'::uuid),
    ('04-query-product',  'cadena kmc', null, null),
    -- Sólo casa por `supplier_name`: ningún producto contiene «zafiro».
    ('05-query-supplier', 'zafiro',   null, null),
    ('06-query-empty',    'inexistente xyz', null, null),
    ('07-category-empty', null,       null, '99e50000-0000-4000-8000-000000000013'::uuid)
  ) as t(case_name, query, product_id, category_id)
), profiles as (
  select unnest(array['balanced', 'profitability', 'urgent_local']) as profile
), gamas as (
  select unnest(array[null, 'economica', 'media', 'alta']) as gama
), limits as (
  -- Cortes por debajo del tamaño del universo. Sin ellos, una implementación
  -- que recorte ANTES de puntuar daría la misma salida por accidente: con
  -- `limit 10` sobre tres candidatos no se cae nada. Con `limit 1` sobrevive
  -- el que la fórmula eligió, no el que la base devolvió primero.
  select unnest(array[10, 2, 1]) as row_limit
)
select cases.case_name || ' | ' || profiles.profile || ' | '
  || coalesce(gamas.gama, 'sin-gama') || ' | limit=' || limits.row_limit || ' | '
  || (
    public.rank_purchase_candidates_v1(
      cases.query, cases.product_id, cases.category_id,
      profiles.profile, limits.row_limit, gamas.gama
    ) - 'asOf'
  )::text
from cases
cross join profiles
cross join gamas
cross join limits
order by cases.case_name, profiles.profile, coalesce(gamas.gama, ''),
  limits.row_limit;

rollback;
