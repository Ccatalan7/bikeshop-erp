-- Confirmar disponibilidad en el portal del proveedor.
--
-- El historial contesta A QUIÉN le compramos esto; no contesta si HOY lo tiene.
-- Son dos preguntas distintas y conviven: `supplierAvailability` es
-- `unverified` en todo el módulo justamente porque esa segunda respuesta no
-- existía. Acá empieza a existir, sin pisar la primera.
--
-- **La configuración es dato, no código.** El precedente de la casa es
-- `aliexpress_invoice_content.js`: 5.863 líneas para UN proveedor. Ese camino
-- no escala a siete y convierte cada cambio de HTML del proveedor en un
-- despliegue. Acá la sonda de cada portal vive en una fila —cómo se busca, cómo
-- se ve una sesión caída, cómo se lee precio y stock— y ajustar un proveedor es
-- editar un registro.
--
-- **Una sesión caída NO es «sin stock».** Es el único error que de verdad
-- importa: un portal deslogueado responde «sin resultados» y, contado como
-- cero, haría comprar de más. Tiene su propio estado y nunca se mezcla.
--
-- La evidencia cruda se guarda a propósito: es lo que permite afinar la lectura
-- de un portal sin mirar la pantalla, leyendo lo que el propio chequeo trajo.

begin;

create table if not exists public.supplier_portal_probes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  -- `{code}` se reemplaza por el código del proveedor del producto. Es un
  -- template y no una URL fija porque cada portal busca a su manera.
  search_url_template text not null,
  -- Cómo se ve, en el texto de la página, que la sesión ya no está. Sin esto
  -- un portal deslogueado se leería como «no hay stock».
  logged_out_pattern text,
  not_found_pattern text,
  -- Expresiones con UN grupo de captura. Nulas mientras el portal no se haya
  -- reconocido: el primer chequeo trae la evidencia para escribirlas.
  price_pattern text,
  stock_pattern text,
  in_stock_pattern text,
  out_of_stock_pattern text,
  notes text,
  is_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint supplier_portal_probes_unique unique (tenant_id, supplier_id),
  constraint supplier_portal_probes_template_check
    check (position('{code}' in search_url_template) > 0),
  constraint supplier_portal_probes_https_check
    check (search_url_template like 'https://%')
);

create index if not exists supplier_portal_probes_tenant_idx
  on public.supplier_portal_probes (tenant_id, supplier_id);

comment on table public.supplier_portal_probes is
  'Cómo consultar el portal de cada proveedor. Configuración, no código: un cambio de HTML del proveedor se corrige editando una fila.';

create table if not exists public.supplier_availability_checks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  supplier_code text,
  checked_at timestamptz not null default now(),
  -- `session_expired` y `unreadable` existen para no disfrazarse de
  -- `out_of_stock`: informar cero cuando la causa fue otra hace comprar de más.
  status text not null,
  price_net numeric(14,4),
  stock_quantity numeric(14,3),
  source_url text,
  -- Lo que el chequeo vio, tal cual. Permite afinar la lectura del portal sin
  -- volver a entrar, y deja auditable de dónde salió cada número.
  evidence jsonb not null default '{}'::jsonb,
  created_by uuid,
  constraint supplier_availability_checks_status_check check (
    status in (
      'available', 'out_of_stock', 'not_found',
      'session_expired', 'unreadable', 'probe_missing'
    )
  ),
  constraint supplier_availability_checks_price_check
    check (price_net is null or price_net >= 0),
  constraint supplier_availability_checks_stock_check
    check (stock_quantity is null or stock_quantity >= 0)
);

create index if not exists supplier_availability_checks_lookup_idx
  on public.supplier_availability_checks
     (tenant_id, product_id, checked_at desc);
create index if not exists supplier_availability_checks_supplier_idx
  on public.supplier_availability_checks
     (tenant_id, supplier_id, checked_at desc);

comment on table public.supplier_availability_checks is
  'Qué dijo el portal del proveedor y cuándo. Nunca reemplaza el historial de compras: son dos preguntas distintas.';

alter table public.supplier_portal_probes enable row level security;
alter table public.supplier_availability_checks enable row level security;

drop policy if exists supplier_portal_probes_tenant
  on public.supplier_portal_probes;
create policy supplier_portal_probes_tenant
  on public.supplier_portal_probes
  for all
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());

drop policy if exists supplier_availability_checks_tenant
  on public.supplier_availability_checks;
create policy supplier_availability_checks_tenant
  on public.supplier_availability_checks
  for all
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());

commit;
