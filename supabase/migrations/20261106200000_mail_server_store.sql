-- Correo que trabaja, etapas 1 y 2 (2026-11-06).
--
-- Hasta hoy el ERP mostraba el correo en vivo desde Gmail y Zoho, una conexión
-- por persona, y no guardaba nada: no podía ligar un correo a un trabajo, a un
-- proveedor o a una factura, ni saber que tu compañero ya lo había atendido.
-- Esta migración guarda el correo de las casillas de la empresa en el servidor
-- (una sola copia para todo el equipo), lo entiende con reglas seguras
-- (remitente, números, documentos) y lo liga a sus registros.
--
-- Regla del dueño: el estado de un botón nunca se guarda en el correo; se
-- calcula del registro cada vez (`mail_message_state_internal`). Si alguien ya
-- registró la factura, el pago o el gasto por otro lado, el correo lo muestra
-- hecho.
--
-- Sólo el personal lee el correo: las políticas usan
-- `messaging_is_staff_in_tenant`, nunca la sola pertenencia al tenant (los
-- clientes del portal también tienen usuario).

begin;

-- ---------------------------------------------------------------------------
-- 1. Casillas de la empresa
-- ---------------------------------------------------------------------------

create table if not exists public.mail_mailboxes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  provider text not null check (provider in ('gmail', 'zoho')),
  address text not null check (address = lower(btrim(address)) and address like '%@%'),
  display_name text,
  is_active boolean not null default true,
  sync_state jsonb not null default '{}'::jsonb,
  last_synced_at timestamptz,
  last_sync_error text check (last_sync_error is null or length(last_sync_error) <= 500),
  backfilled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, provider, address)
);

-- ---------------------------------------------------------------------------
-- 2. Mensajes
-- ---------------------------------------------------------------------------

create table if not exists public.mail_messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  mailbox_id uuid not null references public.mail_mailboxes(id) on delete cascade,
  provider_message_id text not null,
  provider_thread_id text,
  provider_folder_id text,
  rfc_message_id text,
  in_reply_to text,
  reference_ids text[] not null default '{}',
  direction text not null default 'in' check (direction in ('in', 'out')),
  from_address text not null default '',
  from_name text,
  to_addresses text[] not null default '{}',
  cc_addresses text[] not null default '{}',
  subject text not null default '',
  snippet text,
  body_text text,
  has_attachments boolean not null default false,
  attachments jsonb not null default '[]'::jsonb check (jsonb_typeof(attachments) = 'array'),
  labels text[] not null default '{}',
  provider_read boolean not null default false,
  in_inbox boolean not null default true,
  -- Envío masivo (List-Unsubscribe, Precedence: bulk o la pestaña Promociones
  -- de Gmail): sin señales de pedido, es una promoción.
  is_bulk boolean not null default false,
  received_at timestamptz not null,
  sender_party_type text check (sender_party_type is null or sender_party_type in (
    'customer', 'supplier', 'bank', 'courier', 'platform', 'own', 'person', 'noise', 'promo', 'unknown')),
  sender_party_id uuid,
  sender_label text,
  kind text not null default 'other' check (kind in (
    'customer', 'web_order', 'supplier_order', 'claim', 'supplier_invoice', 'freight_invoice',
    'service_invoice', 'transfer', 'statement', 'bank', 'shipment', 'review', 'site', 'platform',
    'security', 'promo', 'noise', 'own', 'other')),
  kind_source text not null default 'rule' check (kind_source in ('rule', 'person', 'ai')),
  facts jsonb not null default '{}'::jsonb check (jsonb_typeof(facts) = 'object'),
  case_key text,
  read_at timestamptz,
  read_by uuid,
  done_at timestamptz,
  done_by uuid,
  archived_at timestamptz,
  archived_by uuid,
  archive_reason text check (archive_reason is null or archive_reason in ('person', 'noise', 'closed')),
  classified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  search tsvector generated always as (
    setweight(to_tsvector('spanish'::regconfig, coalesce(subject, '')), 'A') ||
    setweight(to_tsvector('simple'::regconfig, coalesce(from_name, '') || ' ' || coalesce(from_address, '')), 'A') ||
    setweight(to_tsvector('spanish'::regconfig, left(coalesce(body_text, ''), 20000)), 'C')
  ) stored,
  unique (mailbox_id, provider_message_id)
);

create index if not exists mail_messages_tenant_received_idx
  on public.mail_messages (tenant_id, received_at desc);
create index if not exists mail_messages_tenant_kind_idx
  on public.mail_messages (tenant_id, kind, received_at desc);
create index if not exists mail_messages_case_idx
  on public.mail_messages (tenant_id, case_key) where case_key is not null;
create index if not exists mail_messages_party_idx
  on public.mail_messages (tenant_id, sender_party_type, sender_party_id);
create index if not exists mail_messages_rfc_idx
  on public.mail_messages (tenant_id, rfc_message_id) where rfc_message_id is not null;
create index if not exists mail_messages_thread_idx
  on public.mail_messages (mailbox_id, provider_thread_id) where provider_thread_id is not null;
create index if not exists mail_messages_search_idx
  on public.mail_messages using gin (search);

-- ---------------------------------------------------------------------------
-- 3. Vínculos con los registros del ERP
-- ---------------------------------------------------------------------------

create table if not exists public.mail_message_links (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  message_id uuid not null references public.mail_messages(id) on delete cascade,
  record_type text not null check (record_type in (
    'job', 'customer', 'supplier', 'purchase_invoice', 'online_order', 'expense', 'sales_invoice')),
  record_id uuid not null,
  is_primary boolean not null default false,
  source text not null check (source in ('sender', 'number', 'document', 'thread', 'ai', 'person')),
  confidence numeric(3, 2) not null default 1 check (confidence > 0 and confidence <= 1),
  created_by uuid,
  created_at timestamptz not null default now(),
  unique (message_id, record_type, record_id)
);

create index if not exists mail_message_links_record_idx
  on public.mail_message_links (tenant_id, record_type, record_id);

-- ---------------------------------------------------------------------------
-- 4. Directorio de remitentes: quién es cada dirección o dominio
-- ---------------------------------------------------------------------------

create table if not exists public.mail_senders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  match_type text not null check (match_type in ('address', 'domain')),
  match_value text not null check (match_value = lower(btrim(match_value)) and length(match_value) between 3 and 200),
  party_type text not null check (party_type in (
    'customer', 'supplier', 'bank', 'courier', 'platform', 'own', 'noise', 'promo')),
  party_id uuid,
  label text,
  kind_hint text check (kind_hint is null or kind_hint in (
    'customer', 'web_order', 'supplier_order', 'claim', 'supplier_invoice', 'freight_invoice',
    'service_invoice', 'transfer', 'statement', 'bank', 'shipment', 'review', 'site', 'platform',
    'security', 'promo', 'noise', 'own', 'other')),
  source text not null default 'seed' check (source in ('seed', 'customer', 'supplier', 'person')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, match_type, match_value)
);

-- ---------------------------------------------------------------------------
-- 5. Despacho de la sincronización (cron → función, sin llaves en la base)
-- ---------------------------------------------------------------------------

create table if not exists public.mail_sync_runtime (
  singleton boolean primary key default true check (singleton),
  endpoint text,
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.mail_sync_runs (
  id uuid primary key default gen_random_uuid(),
  reason text not null,
  token_hash text not null,
  requested_at timestamptz not null default clock_timestamp(),
  claimed_at timestamptz,
  finished_at timestamptz,
  result jsonb,
  error text check (error is null or length(error) <= 1000)
);

create index if not exists mail_sync_runs_requested_idx on public.mail_sync_runs (requested_at desc);

-- ---------------------------------------------------------------------------
-- 6. Acceso: lectura del personal; escrituras sólo por funciones
-- ---------------------------------------------------------------------------

alter table public.mail_mailboxes enable row level security;
alter table public.mail_messages enable row level security;
alter table public.mail_message_links enable row level security;
alter table public.mail_senders enable row level security;
alter table public.mail_sync_runtime enable row level security;
alter table public.mail_sync_runs enable row level security;

revoke all on public.mail_mailboxes, public.mail_messages, public.mail_message_links,
  public.mail_senders, public.mail_sync_runtime, public.mail_sync_runs from anon, authenticated;
grant select on public.mail_mailboxes, public.mail_messages, public.mail_message_links,
  public.mail_senders to authenticated;
grant all on public.mail_mailboxes, public.mail_messages, public.mail_message_links,
  public.mail_senders, public.mail_sync_runtime, public.mail_sync_runs to service_role;

drop policy if exists mail_mailboxes_staff_read on public.mail_mailboxes;
create policy mail_mailboxes_staff_read on public.mail_mailboxes
  for select to authenticated using (public.messaging_is_staff_in_tenant(tenant_id));
drop policy if exists mail_messages_staff_read on public.mail_messages;
create policy mail_messages_staff_read on public.mail_messages
  for select to authenticated using (public.messaging_is_staff_in_tenant(tenant_id));
drop policy if exists mail_message_links_staff_read on public.mail_message_links;
create policy mail_message_links_staff_read on public.mail_message_links
  for select to authenticated using (public.messaging_is_staff_in_tenant(tenant_id));
drop policy if exists mail_senders_staff_read on public.mail_senders;
create policy mail_senders_staff_read on public.mail_senders
  for select to authenticated using (public.messaging_is_staff_in_tenant(tenant_id));

drop trigger if exists trg_mail_mailboxes_updated_at on public.mail_mailboxes;
create trigger trg_mail_mailboxes_updated_at before update on public.mail_mailboxes
  for each row execute function public.set_updated_at();
drop trigger if exists trg_mail_messages_updated_at on public.mail_messages;
create trigger trg_mail_messages_updated_at before update on public.mail_messages
  for each row execute function public.set_updated_at();
drop trigger if exists trg_mail_senders_updated_at on public.mail_senders;
create trigger trg_mail_senders_updated_at before update on public.mail_senders
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 7. Ayudas puras
-- ---------------------------------------------------------------------------

create or replace function public.mail_fold_internal(p_text text)
returns text language sql immutable parallel safe
set search_path = pg_catalog
as $$
  select lower(translate(coalesce(p_text, ''),
    'ÁÉÍÓÚÜÑáéíóúüñÀÈÌÒÙàèìòù', 'AEIOUUNaeiouunAEIOUaeiou'));
$$;

create or replace function public.mail_domain_internal(p_address text)
returns text language sql immutable parallel safe
set search_path = pg_catalog
as $$
  select nullif(lower(btrim(split_part(coalesce(p_address, ''), '@', 2))), '');
$$;

create or replace function public.mail_rut_key_internal(p_rut text)
returns text language sql immutable parallel safe
set search_path = pg_catalog
as $$
  select nullif(upper(regexp_replace(coalesce(p_rut, ''), '[^0-9kK]', '', 'g')), '');
$$;

create or replace function public.mail_amount_internal(p_text text)
returns numeric language sql immutable parallel safe
set search_path = pg_catalog
as $$
  select case
    when p_text ~ '^\s*\$?\s*\d{1,3}(\.\d{3})+(,\d{1,2})?\s*$'
      then replace(split_part(regexp_replace(p_text, '[\s$]', '', 'g'), ',', 1), '.', '')::numeric
    when p_text ~ '^\s*\$?\s*\d{1,9}\s*$'
      then regexp_replace(p_text, '[\s$]', '', 'g')::numeric
  end;
$$;

-- Lo que se lee del asunto y del texto: números de trabajo, pedidos, folios,
-- órdenes de flete, montos. Sólo patrones seguros; nada de adivinar.
create or replace function public.mail_extract_facts_internal(
  p_subject text, p_body text, p_from_address text
) returns jsonb language plpgsql immutable
set search_path = pg_catalog
as $$
declare
  v_subject text := coalesce(p_subject, '');
  v_text text := v_subject || E'\n' || left(coalesce(p_body, ''), 6000);
  v_local text := lower(split_part(coalesce(p_from_address, ''), '@', 1));
  v_facts jsonb := '{}'::jsonb;
  v_match text[];
  v_list jsonb;
  v_amount numeric;
begin
  select jsonb_agg(distinct upper(m[1])) into v_list
    from regexp_matches(v_text, '\m(PG-\d{5})\M', 'gi') as m;
  if v_list is not null then v_facts := v_facts || jsonb_build_object('job_numbers', v_list); end if;

  select jsonb_agg(distinct upper(m[1])) into v_list
    from regexp_matches(v_text, '\m(WEB-\d{2}-\d{5})\M', 'gi') as m;
  if v_list is not null then v_facts := v_facts || jsonb_build_object('web_orders', v_list); end if;

  v_match := regexp_match(v_subject, 'documento tributario electr.nico\s+n(?:ro|°|º)?\.?\s*(\d{2,12})', 'i');
  if v_match is null then
    v_match := regexp_match(v_subject, 'factura electr.nica\s*:?\s*(?:n(?:ro|°|º)?\.?\s*)?(\d{3,12})', 'i');
  end if;
  if v_match is null then
    v_match := regexp_match(v_subject, 'factura de la compra\s*#?\s*(\d{6,20})', 'i');
  end if;
  if v_match is not null then v_facts := v_facts || jsonb_build_object('folio', v_match[1]); end if;

  if v_local ~ '^\d{7,8}-[0-9k]$' then
    v_facts := v_facts || jsonb_build_object('rut', upper(v_local));
  else
    v_match := regexp_match(v_text, 'r\.?\s?u\.?\s?t\.?\s*(?:emisor)?\s*:?\s*(\d{1,2}\.?\d{3}\.?\d{3}-[0-9kK])', 'i');
    if v_match is not null then v_facts := v_facts || jsonb_build_object('rut', upper(v_match[1])); end if;
  end if;

  v_match := regexp_match(v_text, '\mOF\s*:?\s*(\d{6,12})\M');
  if v_match is null then
    v_match := regexp_match(v_text, 'orden de flete\D{0,25}(\d{6,12})', 'i');
  end if;
  if v_match is not null then v_facts := v_facts || jsonb_build_object('freight_order', v_match[1]); end if;

  v_match := regexp_match(v_text, 'pedido\s+n\s*[°º.]?\s*(\d{8,12})', 'i');
  if v_match is not null then v_facts := v_facts || jsonb_build_object('tracking', v_match[1]); end if;

  select jsonb_agg(distinct m[1]) into v_list
    from regexp_matches(v_subject, '(?:orden de pedido|pedido)\s*[:#]?\s*(?:n\s*[°º.]?\s*)?#?\s*([A-Z]{0,2}\d{4,10})', 'gi') as m;
  if v_list is not null then v_facts := v_facts || jsonb_build_object('order_refs', v_list); end if;

  v_match := regexp_match(v_subject, 'caso registrado\s*:?\s*([A-Z0-9][A-Z0-9-]{5,})', 'i');
  if v_match is not null then v_facts := v_facts || jsonb_build_object('case_ref', upper(v_match[1])); end if;

  v_match := regexp_match(v_text, 'monto[^0-9$\n]{0,40}\$?\s?(\d{1,3}(?:\.\d{3})+|\d{3,9})', 'i');
  if v_match is not null then
    v_amount := public.mail_amount_internal(v_match[1]);
  end if;
  if v_amount is null then
    v_match := regexp_match(v_text, '\$\s?(\d{1,3}(?:\.\d{3})+)');
    if v_match is not null then v_amount := public.mail_amount_internal(v_match[1]); end if;
  end if;
  if v_amount is not null and v_amount > 0 then
    v_facts := v_facts || jsonb_build_object('amount', v_amount);
  end if;

  v_match := regexp_match(v_subject, '(?:recibiste|te enviaron|te transfiri.)\s+(?:una\s+)?transferencia de\s+(.{3,80})$', 'i');
  if v_match is null then
    v_match := regexp_match(coalesce(p_body, ''), '(?:nombre (?:del )?(?:originante|ordenante|remitente|titular)|de parte de|originante|ordenante)\s*:?\s*([^\n\r]{3,80})', 'i');
  end if;
  if v_match is not null then
    v_facts := v_facts || jsonb_build_object('payer', btrim(v_match[1], E' \t.:'));
  end if;

  return v_facts;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Directorio: semillas fijas + clientes y proveedores del tenant
-- ---------------------------------------------------------------------------

create or replace function public.mail_refresh_senders_internal(p_tenant_id uuid)
returns integer language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_count integer := 0;
  v_rows integer;
begin
  insert into public.mail_senders (tenant_id, match_type, match_value, party_type, label, kind_hint, source)
  select p_tenant_id, 'domain', d.domain, d.party_type, d.label, d.kind_hint, 'seed'
    from (values
      ('bancochile.cl', 'bank', 'Banco de Chile', null),
      ('bancofalabella.com', 'bank', 'Banco Falabella', null),
      ('bancofalabella.cl', 'bank', 'Banco Falabella', null),
      ('santander.cl', 'bank', 'Santander', null),
      ('bancoconsorcio.cl', 'bank', 'Banco Consorcio', null),
      ('somosmach.com', 'bank', 'MACH', null),
      ('bancoestado.cl', 'bank', 'BancoEstado', null),
      ('bci.cl', 'bank', 'BCI', null),
      ('scotiabank.cl', 'bank', 'Scotiabank', null),
      ('itau.cl', 'bank', 'Itaú', null),
      ('bancoripley.cl', 'bank', 'Banco Ripley', null),
      ('tenpo.cl', 'bank', 'Tenpo', null),
      ('mercadopago.cl', 'bank', 'Mercado Pago', null),
      ('mercadopago.com', 'bank', 'Mercado Pago', null),
      ('starken.cl', 'courier', 'Starken', null),
      ('blue.cl', 'courier', 'Blue Express', null),
      ('correos.cl', 'courier', 'Correos de Chile', null),
      ('chilexpress.cl', 'courier', 'Chilexpress', null),
      ('pullmancargo.cl', 'courier', 'Pullman Cargo', null),
      ('google.com', 'platform', 'Google', null),
      ('facebookmail.com', 'platform', 'Meta', null),
      ('metamail.com', 'platform', 'Meta', null),
      ('facebook.com', 'platform', 'Meta', null),
      ('whatsapp.com', 'platform', 'WhatsApp', null),
      ('openai.com', 'platform', 'OpenAI', null),
      ('supabase.com', 'platform', 'Supabase', null),
      ('supabase.io', 'platform', 'Supabase', null),
      ('cloudflare.com', 'platform', 'Cloudflare', null),
      ('resend.com', 'platform', 'Resend', null),
      ('postman.com', 'platform', 'Postman', null),
      ('slack.com', 'platform', 'Slack', null),
      ('github.com', 'platform', 'GitHub', null),
      ('apple.com', 'platform', 'Apple', null),
      ('zoho.com', 'platform', 'Zoho', null),
      ('zohoaccounts.com', 'platform', 'Zoho', null),
      ('zohocorp.com', 'platform', 'Zoho', null),
      ('zohocreator.com', 'platform', 'Zoho', null),
      ('zohodesk.com', 'platform', 'Zoho', null),
      ('zohocliq.com', 'platform', 'Zoho', null),
      ('sii.cl', 'platform', 'SII', null),
      ('previred.com', 'platform', 'Previred', null),
      ('qemailserver.com', 'promo', 'Encuestas', 'promo'),
      ('zohobooks.com', 'noise', 'Zoho Books', 'noise'),
      ('vinabike.cl', 'own', 'Viñabike', 'own')
    ) as d(domain, party_type, label, kind_hint)
  on conflict (tenant_id, match_type, match_value) do update
    set party_type = excluded.party_type, label = excluded.label, kind_hint = excluded.kind_hint
    where public.mail_senders.source = 'seed';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;

  -- Proveedores por dominio de su sitio y de su correo, y por las direcciones
  -- de su correo, su vendedor y sus contactos.
  insert into public.mail_senders (tenant_id, match_type, match_value, party_type, party_id, label, source)
  select distinct on (x.match_type, x.match_value)
         p_tenant_id, x.match_type, x.match_value,
         case when x.match_value in (
           'starken.cl', 'blue.cl', 'correos.cl', 'chilexpress.cl', 'pullmancargo.cl') then 'courier'
           else 'supplier' end,
         x.supplier_id, x.name, 'supplier'
    from (
      select 'domain'::text as match_type,
             lower(regexp_replace(regexp_replace(regexp_replace(s.website, '^\s*https?://', '', 'i'), '^www\.', '', 'i'), '[/:?#].*$', '')) as match_value,
             s.id as supplier_id, s.name, s.updated_at
        from public.suppliers s
       where s.tenant_id = p_tenant_id and coalesce(s.is_active, true) and nullif(btrim(s.website), '') is not null
      union all
      select 'domain', public.mail_domain_internal(s.email), s.id, s.name, s.updated_at
        from public.suppliers s
       where s.tenant_id = p_tenant_id and coalesce(s.is_active, true) and s.email like '%@%'
      union all
      select 'address', lower(btrim(s.email)), s.id, s.name, s.updated_at
        from public.suppliers s
       where s.tenant_id = p_tenant_id and coalesce(s.is_active, true) and s.email like '%@%'
      union all
      select 'address', lower(btrim(s.sales_rep_email)), s.id, s.name, s.updated_at
        from public.suppliers s
       where s.tenant_id = p_tenant_id and coalesce(s.is_active, true) and s.sales_rep_email like '%@%'
      union all
      select 'address', lower(btrim(c.email)), s.id, s.name, c.updated_at
        from public.supplier_contacts c
        join public.suppliers s on s.id = c.supplier_id and s.tenant_id = c.tenant_id
       where c.tenant_id = p_tenant_id and coalesce(c.is_active, true) and c.email like '%@%'
    ) x
   where x.match_value is not null
     and length(x.match_value) between 3 and 200
     and x.match_value like '%.%'
     -- un dominio de correo personal no identifica a un proveedor
     and not (x.match_type = 'domain' and x.match_value in (
       'gmail.com', 'hotmail.com', 'outlook.com', 'yahoo.com', 'icloud.com', 'live.cl', 'hotmail.cl',
       'yahoo.es', 'live.com', 'msn.com', 'outlook.cl', 'about.google', 'google.com', 'instagram.com',
       'facebook.com', 'aliexpress.com', 'mercadolibre.cl'))
   order by x.match_type, x.match_value, x.updated_at desc nulls last
  on conflict (tenant_id, match_type, match_value) do update
    set party_type = excluded.party_type, party_id = excluded.party_id, label = excluded.label
    where public.mail_senders.source in ('supplier', 'seed')
      and (public.mail_senders.party_type in ('supplier', 'courier') or public.mail_senders.source = 'supplier');
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;

  -- AliExpress y Mercado Libre escriben desde muchos subdominios: se ligan por
  -- su dominio raíz al proveedor que ya existe.
  insert into public.mail_senders (tenant_id, match_type, match_value, party_type, party_id, label, source)
  select p_tenant_id, 'domain', d.domain, 'supplier', s.id, s.name, 'supplier'
    from (values ('aliexpress.com', 'aliexpress'), ('mercadolibre.cl', 'mercado libre'),
                 ('mercadolibre.com', 'mercado libre')) as d(domain, key)
    join lateral (
      select s.id, s.name from public.suppliers s
       where s.tenant_id = p_tenant_id and public.mail_fold_internal(s.name) = d.key
       order by s.updated_at desc nulls last limit 1
    ) s on true
  on conflict (tenant_id, match_type, match_value) do update
    set party_id = excluded.party_id, label = excluded.label, party_type = 'supplier'
    where public.mail_senders.source <> 'person';
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;

  -- Los couriers que también son proveedores (para ligar sus fletes a Gastos).
  update public.mail_senders ms
     set party_id = s.id
    from public.suppliers s
   where ms.tenant_id = p_tenant_id and ms.party_type = 'courier' and ms.party_id is null
     and s.tenant_id = p_tenant_id
     and public.mail_fold_internal(s.name) = public.mail_fold_internal(ms.label);

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Quién lo manda
-- ---------------------------------------------------------------------------

create or replace function public.mail_resolve_sender_internal(p_tenant_id uuid, p_address text)
returns table (party_type text, party_id uuid, label text, kind_hint text)
language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_address text := lower(btrim(coalesce(p_address, '')));
  v_local text := split_part(v_address, '@', 1);
  v_domain text := public.mail_domain_internal(v_address);
  v_try text;
  v_row record;
begin
  if v_address = '' or v_domain is null then
    return query select 'unknown'::text, null::uuid, null::text, null::text;
    return;
  end if;

  select ms.party_type, ms.party_id, ms.label, ms.kind_hint into v_row
    from public.mail_senders ms
   where ms.tenant_id = p_tenant_id and ms.match_type = 'address' and ms.match_value = v_address
   limit 1;
  if found then
    return query select v_row.party_type, v_row.party_id, v_row.label, v_row.kind_hint;
    return;
  end if;

  -- Casilla de intercambio de facturas electrónicas: el RUT del emisor va en la
  -- dirección (76442832-3@intercambio.skilldte.cl).
  if v_local ~ '^\d{7,8}-[0-9k]$' then
    select 'supplier'::text as party_type, s.id as party_id, s.name as label into v_row
      from public.suppliers s
     where s.tenant_id = p_tenant_id
       and public.mail_rut_key_internal(s.rut) = public.mail_rut_key_internal(v_local)
     order by s.updated_at desc nulls last limit 1;
    if found then
      return query select v_row.party_type, v_row.party_id, v_row.label, 'supplier_invoice'::text;
      return;
    end if;
  end if;

  -- Proveedores que mandan sus facturas por un servicio de facturación con el
  -- nombre en la dirección (dteteknobike@desis.cl).
  if v_domain in ('desis.cl', 'skilldte.cl', 'facturacion.cl', 'bsale.cl', 'dte.cl', 'openfactura.cl', 'libredte.cl')
     or v_domain like '%.desis.cl' or v_domain like '%.skilldte.cl' then
    select 'supplier'::text as party_type, s.id as party_id, s.name as label into v_row
      from public.suppliers s
     where s.tenant_id = p_tenant_id and coalesce(s.is_active, true)
       and length(regexp_replace(public.mail_fold_internal(s.name), '[^a-z0-9]', '', 'g')) >= 5
       and position(regexp_replace(public.mail_fold_internal(s.name), '[^a-z0-9]', '', 'g')
                    in regexp_replace(v_local, '[^a-z0-9]', '', 'g')) > 0
     order by length(s.name) desc limit 1;
    if found then
      return query select v_row.party_type, v_row.party_id, v_row.label, 'supplier_invoice'::text;
      return;
    end if;
  end if;

  v_try := v_domain;
  while v_try is not null and v_try like '%.%' loop
    select ms.party_type, ms.party_id, ms.label, ms.kind_hint into v_row
      from public.mail_senders ms
     where ms.tenant_id = p_tenant_id and ms.match_type = 'domain' and ms.match_value = v_try
     limit 1;
    if found then
      return query select v_row.party_type, v_row.party_id, v_row.label, v_row.kind_hint;
      return;
    end if;
    v_try := nullif(substring(v_try from position('.' in v_try) + 1), '');
    if v_try is not null and v_try not like '%.%' then v_try := null; end if;
  end loop;

  select 'customer'::text as party_type, c.id as party_id, c.name as label into v_row
    from public.customers c
   where c.tenant_id = p_tenant_id and lower(btrim(c.email)) = v_address
   order by c.updated_at desc nulls last limit 1;
  if found then
    return query select v_row.party_type, v_row.party_id, v_row.label, 'customer'::text;
    return;
  end if;

  if v_domain in ('gmail.com', 'hotmail.com', 'outlook.com', 'yahoo.com', 'icloud.com', 'live.cl',
                  'hotmail.cl', 'yahoo.es', 'live.com', 'msn.com', 'outlook.cl', 'me.com') then
    return query select 'person'::text, null::uuid, null::text, null::text;
    return;
  end if;

  return query select 'unknown'::text, null::uuid, null::text, null::text;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Qué es y a qué se liga
-- ---------------------------------------------------------------------------

create or replace function public.mail_classify_message_internal(p_message_id uuid)
returns text language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  m public.mail_messages%rowtype;
  v_sender record;
  v_facts jsonb;
  v_subject text;
  v_kind text;
  v_case text;
  v_attach_xml boolean;
  v_job uuid;
  v_order uuid;
  v_invoice uuid;
  v_expense uuid;
  v_customer uuid;
  v_value text;
  v_has_primary boolean := false;
begin
  select * into m from public.mail_messages where id = p_message_id for update;
  if not found then return null; end if;

  select * into v_sender from public.mail_resolve_sender_internal(m.tenant_id, m.from_address);
  v_facts := public.mail_extract_facts_internal(m.subject, m.body_text, m.from_address);
  v_subject := public.mail_fold_internal(m.subject);
  v_attach_xml := exists (
    select 1 from jsonb_array_elements(m.attachments) a
     where lower(coalesce(a->>'filename', '')) like '%.xml'
        or lower(coalesce(a->>'mime_type', '')) in ('text/xml', 'application/xml'));

  if m.kind_source = 'person' then
    v_kind := m.kind;
  elsif v_sender.party_type = 'own' then
    v_kind := case when v_facts ? 'web_orders' then 'web_order' else 'own' end;
  elsif v_sender.kind_hint = 'noise' or v_sender.party_type = 'noise' then
    v_kind := 'noise';
  elsif v_subject ~ '(alerta de seguridad|security alert|inicio de sesion|nuevo inicio|was recovered|contrasena|verifica tu|codigo de verificacion|new sign-in|sign-in attempt)' then
    v_kind := 'security';
  elsif v_sender.party_type = 'bank' then
    v_kind := case
      when v_subject like '%cartola%' then 'statement'
      when v_subject ~ '(transferencia|deposito|abono|pago recibido|recibiste)' then 'transfer'
      else 'bank' end;
  elsif v_facts ? 'folio' and (v_attach_xml or v_subject ~ '(documento tributario|factura electronica|documento electronico|factura de la compra)') then
    v_kind := case
      when v_sender.party_type = 'courier' then 'freight_invoice'
      when v_sender.party_type = 'platform' then 'service_invoice'
      else 'supplier_invoice' end;
  elsif v_subject ~ '(envio de documento electronico|documento tributario electronico)' then
    v_kind := 'supplier_invoice';
  elsif v_sender.party_type = 'courier' then
    v_kind := case
      when v_facts ? 'case_ref' or v_subject ~ '(reclamo|cobro indebido)' then 'claim'
      when v_subject ~ '(entregad|en camino|despacho|orden de flete|tu pedido|tu envio|retira|sucursal|recibimos)' then 'shipment'
      else 'shipment' end;
  elsif v_sender.party_type = 'platform' then
    v_kind := case
      when m.from_address ilike 'businessprofile-noreply@%' and v_subject ~ '(review|resena|opinion)' then 'review'
      when m.from_address ~* '^(sc-noreply|googlebase-noreply|merchant|search-console)' or v_subject ~ '(indexed|indexad|search console|merchant center|conversiones|performance report|search performance)' then 'site'
      when v_subject ~ '(recibo|receipt|factura|invoice)' then 'service_invoice'
      when m.is_bulk then 'promo'
      else 'platform' end;
  elsif v_sender.party_type = 'supplier' then
    v_kind := case
      when v_subject ~ '(reclamo|fallo|problema|cobro indebido|garantia|devolucion)' then 'claim'
      when v_subject ~ '(pedido|orden|order|compra|compraste|factur|despach|envio|cotiz|messages from sellers|mensajes de|tu paquete|llego|en camino)' or v_subject ~ '^(re|rv|fw|fwd)\s*:' then 'supplier_order'
      else 'promo' end;
  elsif v_sender.party_type = 'promo' then
    v_kind := 'promo';
  elsif v_sender.party_type = 'customer' then
    v_kind := 'customer';
  elsif v_sender.party_type = 'person' then
    v_kind := case when m.is_bulk then 'promo' else 'customer' end;
  elsif m.is_bulk then
    v_kind := 'promo';
  elsif v_subject ~ '(oferta|descuento|promo|webinar|newsletter|prueba gratis|gratis|credito pre|aprovecha|una idea para|automatiza|introduction|optimiza)' then
    v_kind := 'noise';
  else
    v_kind := 'other';
  end if;

  v_case := case
    when v_facts ? 'freight_order' then 'flete:' || (v_facts->>'freight_order')
    when v_facts ? 'tracking' and v_sender.party_type = 'courier' then 'envio:' || (v_facts->>'tracking')
    when v_facts ? 'case_ref' then 'caso:' || (v_facts->>'case_ref')
    when v_kind = 'supplier_order' and v_facts ? 'order_refs' and v_sender.party_id is not null
      then 'pedido:' || v_sender.party_id::text || ':' || (v_facts->'order_refs'->>0)
    when m.provider_thread_id is not null then 'hilo:' || m.mailbox_id::text || ':' || m.provider_thread_id
  end;

  update public.mail_messages
     set sender_party_type = coalesce(v_sender.party_type, 'unknown'),
         sender_party_id = v_sender.party_id,
         sender_label = v_sender.label,
         kind = v_kind,
         facts = v_facts,
         case_key = v_case,
         archived_at = case when v_kind = 'noise' and archived_at is null then m.received_at else archived_at end,
         archive_reason = case when v_kind = 'noise' and archived_at is null then 'noise' else archive_reason end,
         classified_at = clock_timestamp()
   where id = m.id;

  -- Vínculos: se rehacen los de reglas; los de una persona o de la IA quedan.
  delete from public.mail_message_links
   where message_id = m.id and source in ('sender', 'number', 'document', 'thread');

  if v_sender.party_type in ('customer', 'supplier', 'courier') and v_sender.party_id is not null then
    insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, source)
    values (m.tenant_id, m.id, case when v_sender.party_type = 'customer' then 'customer' else 'supplier' end,
            v_sender.party_id, 'sender')
    on conflict (message_id, record_type, record_id) do nothing;
  end if;

  for v_value in select jsonb_array_elements_text(coalesce(v_facts->'job_numbers', '[]'::jsonb)) loop
    select j.id, j.customer_id into v_job, v_customer from public.mechanic_jobs j
     where j.tenant_id = m.tenant_id and upper(j.job_number) = v_value and j.deleted_at is null
     limit 1;
    if v_job is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
      values (m.tenant_id, m.id, 'job', v_job, not v_has_primary, 'number')
      on conflict (message_id, record_type, record_id) do nothing;
      v_has_primary := true;
    end if;
  end loop;

  for v_value in select jsonb_array_elements_text(coalesce(v_facts->'web_orders', '[]'::jsonb)) loop
    select o.id into v_order from public.online_orders o
     where o.tenant_id = m.tenant_id and upper(o.order_number) = v_value
     limit 1;
    if v_order is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
      values (m.tenant_id, m.id, 'online_order', v_order, not v_has_primary, 'number')
      on conflict (message_id, record_type, record_id) do nothing;
      v_has_primary := true;
    end if;
  end loop;

  if v_facts ? 'folio' then
    select pi.id into v_invoice from public.purchase_invoices pi
     where pi.tenant_id = m.tenant_id
       and regexp_replace(coalesce(pi.invoice_number, ''), '\D', '', 'g') = (v_facts->>'folio')
       and (pi.supplier_id = v_sender.party_id
            or (v_facts ? 'rut' and exists (
              select 1 from public.suppliers s
               where s.id = pi.supplier_id and s.tenant_id = pi.tenant_id
                 and public.mail_rut_key_internal(s.rut) = public.mail_rut_key_internal(v_facts->>'rut'))))
     order by pi.created_at desc limit 1;
    if v_invoice is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
      values (m.tenant_id, m.id, 'purchase_invoice', v_invoice, not v_has_primary, 'document')
      on conflict (message_id, record_type, record_id) do nothing;
      v_has_primary := true;
    end if;
    select e.id into v_expense from public.expenses e
     where e.tenant_id = m.tenant_id
       and regexp_replace(coalesce(e.document_number, ''), '\D', '', 'g') = (v_facts->>'folio')
       and (e.supplier_id = v_sender.party_id or v_sender.party_id is null
            or public.mail_fold_internal(e.supplier_name) = public.mail_fold_internal(v_sender.label))
     order by e.created_at desc limit 1;
    if v_expense is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
      values (m.tenant_id, m.id, 'expense', v_expense, not v_has_primary, 'document')
      on conflict (message_id, record_type, record_id) do nothing;
      v_has_primary := true;
    end if;
  end if;

  -- Una respuesta hereda los registros del correo al que responde.
  if m.in_reply_to is not null or cardinality(m.reference_ids) > 0 or m.provider_thread_id is not null then
    insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
    select distinct on (l.record_type, l.record_id)
           m.tenant_id, m.id, l.record_type, l.record_id, false, 'thread'
      from public.mail_messages other
      join public.mail_message_links l on l.message_id = other.id
     where other.tenant_id = m.tenant_id and other.id <> m.id
       and l.record_type in ('job', 'online_order', 'purchase_invoice', 'customer', 'supplier')
       and ((other.rfc_message_id is not null
             and (other.rfc_message_id = m.in_reply_to or other.rfc_message_id = any (m.reference_ids)))
         or (m.provider_thread_id is not null and other.mailbox_id = m.mailbox_id
             and other.provider_thread_id = m.provider_thread_id))
    on conflict (message_id, record_type, record_id) do nothing;
  end if;

  -- El cliente con un solo trabajo abierto: su correo es de ese trabajo.
  if v_kind = 'customer' and v_sender.party_type = 'customer' and not exists (
    select 1 from public.mail_message_links l where l.message_id = m.id and l.record_type = 'job') then
    select case when count(*) = 1 then (array_agg(j.id))[1] end into v_job
      from public.mechanic_jobs j
     where j.tenant_id = m.tenant_id and j.customer_id = v_sender.party_id and j.deleted_at is null
       and j.delivered_at is null and j.created_at > m.received_at - interval '90 days';
    if v_job is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source, confidence)
      values (m.tenant_id, m.id, 'job', v_job, not v_has_primary, 'sender', 0.7)
      on conflict (message_id, record_type, record_id) do nothing;
    end if;
  end if;

  if not exists (select 1 from public.mail_message_links where message_id = m.id and is_primary) then
    update public.mail_message_links set is_primary = true
     where id = (select id from public.mail_message_links where message_id = m.id
                  order by case record_type when 'job' then 1 when 'online_order' then 2
                    when 'purchase_invoice' then 3 when 'expense' then 4 when 'supplier' then 5
                    when 'customer' then 6 else 7 end, created_at limit 1);
  end if;

  return v_kind;
end;
$$;

create or replace function public.mail_messages_classify_trigger()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  perform public.mail_classify_message_internal(new.id);
  return null;
end;
$$;

drop trigger if exists trg_mail_messages_classify on public.mail_messages;
create trigger trg_mail_messages_classify
  after insert on public.mail_messages
  for each row execute function public.mail_messages_classify_trigger();
drop trigger if exists trg_mail_messages_reclassify on public.mail_messages;
create trigger trg_mail_messages_reclassify
  after update of subject, body_text, from_address, attachments, in_reply_to, provider_thread_id, is_bulk
  on public.mail_messages
  for each row
  when (old.subject is distinct from new.subject
     or old.body_text is distinct from new.body_text
     or old.from_address is distinct from new.from_address
     or old.attachments is distinct from new.attachments
     or old.in_reply_to is distinct from new.in_reply_to
     or old.provider_thread_id is distinct from new.provider_thread_id
     or old.is_bulk is distinct from new.is_bulk)
  execute function public.mail_messages_classify_trigger();

-- ---------------------------------------------------------------------------
-- 11. El estado del botón, calculado del registro (nunca guardado)
-- ---------------------------------------------------------------------------

create or replace function public.mail_space_internal(p_kind text, p_party text)
returns text language sql immutable parallel safe
set search_path = pg_catalog
as $$
  select case
    when p_kind = 'customer' then 'clientes'
    when p_kind = 'web_order' then 'pedidos_web'
    when p_kind in ('supplier_order', 'claim') then 'proveedores'
    when p_kind = 'shipment' then 'envios'
    when p_kind in ('transfer', 'statement', 'bank') then 'banco'
    when p_kind in ('supplier_invoice', 'freight_invoice', 'service_invoice') then 'facturas'
    when p_kind = 'review' then 'resenas'
    when p_kind = 'site' then 'google'
    when p_kind = 'platform' then 'servicios'
    when p_kind = 'security' then 'seguridad'
    when p_kind = 'promo' then 'promociones'
    when p_kind = 'noise' then 'ruido'
    else 'otros'
  end;
$$;

create or replace function public.mail_message_state_internal(p_message_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  m public.mail_messages%rowtype;
  v_folio text;
  v_row record;
  v_done boolean := false;
  v_text text;
  v_at timestamptz;
  v_who uuid;
  v_action text;
  v_actionable boolean := false;
begin
  select * into m from public.mail_messages where id = p_message_id;
  if not found then return null; end if;
  v_folio := m.facts->>'folio';

  if m.kind in ('supplier_invoice', 'freight_invoice', 'service_invoice') then
    v_actionable := true;
    v_action := case when m.kind = 'supplier_invoice' then 'register_purchase' else 'register_expense' end;
    if v_folio is not null then
      select pi.id, pi.created_at, pi.created_by, pi.invoice_number into v_row
        from public.purchase_invoices pi
       where pi.tenant_id = m.tenant_id
         and regexp_replace(coalesce(pi.invoice_number, ''), '\D', '', 'g') = v_folio
         and (m.sender_party_id is null or pi.supplier_id = m.sender_party_id
              or (m.facts ? 'rut' and exists (select 1 from public.suppliers s
                    where s.id = pi.supplier_id and s.tenant_id = pi.tenant_id
                      and public.mail_rut_key_internal(s.rut) = public.mail_rut_key_internal(m.facts->>'rut'))))
       order by pi.created_at desc limit 1;
      if found then
        v_done := true; v_at := v_row.created_at; v_who := v_row.created_by;
        v_text := 'Ya registrada en Compras';
      else
        select e.id, e.created_at, e.created_by into v_row
          from public.expenses e
         where e.tenant_id = m.tenant_id
           and regexp_replace(coalesce(e.document_number, ''), '\D', '', 'g') = v_folio
         order by e.created_at desc limit 1;
        if found then
          v_done := true; v_at := v_row.created_at; v_who := v_row.created_by;
          v_text := 'Ya está en Gastos';
        end if;
      end if;
    end if;
  elsif m.kind = 'statement' then
    v_actionable := true;
    v_action := 'import_statement';
    select i.created_at, i.created_by into v_row
      from public.bank_statement_imports i
     where i.tenant_id = m.tenant_id and i.created_at >= m.received_at
     order by i.created_at limit 1;
    if found then
      v_done := true; v_at := v_row.created_at; v_who := v_row.created_by;
      v_text := 'Ya importada en Conciliación';
    end if;
  elsif m.kind = 'transfer' then
    v_actionable := true;
    v_action := 'register_payment';
    if (m.facts->>'amount') is not null then
      select sp.created_at, sp.invoice_id into v_row
        from public.sales_payments sp
       where sp.tenant_id = m.tenant_id and sp.deleted_at is null
         and sp.amount = (m.facts->>'amount')::numeric
         and sp.date between (m.received_at - interval '3 days')::date and (m.received_at + interval '10 days')::date
       order by abs(extract(epoch from (sp.created_at - m.received_at))) limit 1;
      if found then
        v_done := true; v_at := v_row.created_at;
        v_text := 'Ya registrado un pago por este monto';
      else
        select o.paid_at, o.order_number into v_row
          from public.online_orders o
         where o.tenant_id = m.tenant_id and coalesce(o.is_test, false) = false
           and o.total = (m.facts->>'amount')::numeric and o.paid_at is not null
           and o.paid_at between m.received_at - interval '3 days' and m.received_at + interval '10 days'
         order by o.paid_at limit 1;
        if found then
          v_done := true; v_at := v_row.paid_at;
          v_text := 'Ya pagado: ' || v_row.order_number;
        end if;
      end if;
    end if;
  elsif m.kind = 'customer' and m.direction = 'in' then
    v_actionable := true;
    v_action := 'reply';
    select x.received_at into v_at from public.mail_messages x
     where x.mailbox_id = m.mailbox_id and x.provider_thread_id = m.provider_thread_id
       and x.direction = 'out' and x.received_at > m.received_at
     order by x.received_at limit 1;
    if v_at is not null then
      v_done := true; v_text := 'Ya respondido';
    end if;
  elsif m.kind in ('review', 'claim', 'shipment', 'security', 'supplier_order', 'web_order') then
    v_actionable := m.kind in ('review', 'claim', 'security');
    v_action := case m.kind when 'review' then 'reply_review' when 'claim' then 'follow_up' when 'security' then 'review' else null end;
  end if;

  if not v_done and m.done_at is not null then
    v_done := true; v_at := m.done_at; v_who := m.done_by; v_text := 'Marcado como hecho';
  end if;

  return jsonb_build_object(
    'actionable', v_actionable,
    'action', v_action,
    'done', v_done,
    'done_text', v_text,
    'done_at', v_at,
    'done_by', case when v_who is not null then public.erp_actor_display_name(v_who, m.tenant_id) end
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Lo que lee la app
-- ---------------------------------------------------------------------------

create or replace function public.mail_require_staff_internal()
returns uuid language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.user_tenant_id();
begin
  if v_tenant is null or not public.messaging_is_staff_in_tenant(v_tenant) then
    raise exception 'mail_forbidden' using errcode = '42501';
  end if;
  return v_tenant;
end;
$$;

create or replace function public.mail_links_json_internal(p_message_id uuid)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public
as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'type', l.record_type,
    'id', l.record_id,
    'primary', l.is_primary,
    'source', l.source,
    'confidence', l.confidence,
    'label', case l.record_type
      when 'job' then (select j.job_number from public.mechanic_jobs j where j.id = l.record_id and j.tenant_id = l.tenant_id)
      when 'customer' then (select c.name from public.customers c where c.id = l.record_id and c.tenant_id = l.tenant_id)
      when 'supplier' then (select s.name from public.suppliers s where s.id = l.record_id and s.tenant_id = l.tenant_id)
      when 'purchase_invoice' then (select 'Factura ' || pi.invoice_number from public.purchase_invoices pi where pi.id = l.record_id and pi.tenant_id = l.tenant_id)
      when 'online_order' then (select o.order_number from public.online_orders o where o.id = l.record_id and o.tenant_id = l.tenant_id)
      when 'expense' then (select 'Gasto ' || coalesce(e.document_number, e.expense_number) from public.expenses e where e.id = l.record_id and e.tenant_id = l.tenant_id)
    end,
    'detail', case l.record_type
      when 'job' then (select concat_ws(' · ', c.name, j.status)
                         from public.mechanic_jobs j left join public.customers c on c.id = j.customer_id and c.tenant_id = j.tenant_id
                        where j.id = l.record_id and j.tenant_id = l.tenant_id)
      when 'online_order' then (select concat_ws(' · ', o.customer_name, o.status) from public.online_orders o where o.id = l.record_id and o.tenant_id = l.tenant_id)
      when 'purchase_invoice' then (select concat_ws(' · ', s.name, pi.status) from public.purchase_invoices pi left join public.suppliers s on s.id = pi.supplier_id and s.tenant_id = pi.tenant_id where pi.id = l.record_id and pi.tenant_id = l.tenant_id)
    end,
    'image_url', case l.record_type
      when 'supplier' then (select s.image_url from public.suppliers s where s.id = l.record_id and s.tenant_id = l.tenant_id)
      when 'customer' then (select c.image_url from public.customers c where c.id = l.record_id and c.tenant_id = l.tenant_id)
    end
  )) order by l.is_primary desc, l.created_at), '[]'::jsonb)
    from public.mail_message_links l
   where l.message_id = p_message_id;
$$;

create or replace function public.mail_message_json_internal(m public.mail_messages, p_with_body boolean)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', m.id,
    'mailbox', (select mb.address from public.mail_mailboxes mb where mb.id = m.mailbox_id),
    'provider', (select mb.provider from public.mail_mailboxes mb where mb.id = m.mailbox_id),
    'provider_message_id', m.provider_message_id,
    'provider_folder_id', m.provider_folder_id,
    'thread', m.provider_thread_id,
    'direction', m.direction,
    'from_address', m.from_address,
    'from_name', m.from_name,
    'to', to_jsonb(m.to_addresses),
    'subject', m.subject,
    'snippet', m.snippet,
    'body_text', case when p_with_body then m.body_text end,
    'has_attachments', m.has_attachments,
    'attachments', m.attachments,
    'received_at', m.received_at,
    'read', (m.read_at is not null or m.provider_read),
    'archived', (m.archived_at is not null or (m.kind = 'promo' and m.received_at < now() - interval '7 days')),
    'archive_reason', m.archive_reason,
    'kind', m.kind,
    'kind_source', m.kind_source,
    'space', public.mail_space_internal(m.kind, m.sender_party_type),
    'party_type', m.sender_party_type,
    'party_id', m.sender_party_id,
    'party_label', m.sender_label,
    'facts', m.facts,
    'case_key', m.case_key,
    'links', public.mail_links_json_internal(m.id),
    'state', public.mail_message_state_internal(m.id)
  ));
$$;

create or replace function public.mail_inbox_v1(
  p_view text default 'today',
  p_space text default null,
  p_query text default null,
  p_limit integer default 120,
  p_before timestamptz default null
) returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_limit integer := least(greatest(coalesce(p_limit, 120), 1), 300);
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
  v_digits text := nullif(regexp_replace(coalesce(p_query, ''), '\D', '', 'g'), '');
  v_result jsonb;
begin
  with base as (
    select m.*, public.mail_message_state_internal(m.id) as st
      from public.mail_messages m
     where m.tenant_id = v_tenant
       and (p_before is null or m.received_at < p_before)
       and (p_space is null or public.mail_space_internal(m.kind, m.sender_party_type) = p_space)
       and (v_query is null
            or m.search @@ websearch_to_tsquery('spanish'::regconfig, v_query)
            or m.subject ilike '%' || v_query || '%'
            or m.from_address ilike '%' || v_query || '%'
            or coalesce(m.sender_label, '') ilike '%' || v_query || '%'
            or (length(v_digits) >= 4 and (m.facts::text like '%' || v_digits || '%'
                  or regexp_replace(m.subject, '\D', '', 'g') like '%' || v_digits || '%'))
            or exists (select 1 from jsonb_array_elements(public.mail_links_json_internal(m.id)) lk
                        where lk->>'label' ilike '%' || v_query || '%'))
     order by m.received_at desc
     limit case when p_view = 'today' then 400 else v_limit end
  ), picked as (
    select b.* from base b
     where case p_view
       when 'today' then b.archived_at is null and b.direction = 'in'
         and coalesce((b.st->>'actionable')::boolean, false)
         and not coalesce((b.st->>'done')::boolean, false)
         and b.received_at > now() - interval '45 days'
       when 'waiting' then b.kind = 'claim' and b.done_at is null and b.archived_at is null
       when 'archived' then b.archived_at is not null or (b.kind = 'promo' and b.received_at < now() - interval '7 days')
       else b.archived_at is null and not (b.kind = 'promo' and b.received_at < now() - interval '7 days')
     end
     order by b.received_at desc
     limit v_limit
  )
  select coalesce(jsonb_agg(public.mail_message_json_internal(
           (select x from public.mail_messages x where x.id = p.id), false) order by p.received_at desc), '[]'::jsonb)
    into v_result
    from picked p;
  return v_result;
end;
$$;

create or replace function public.mail_message_v1(p_message_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  m public.mail_messages%rowtype;
begin
  select * into m from public.mail_messages where id = p_message_id and tenant_id = v_tenant;
  if not found then raise exception 'mail_not_found' using errcode = 'P0002'; end if;
  return public.mail_message_json_internal(m, true)
    || jsonb_build_object('case', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', x.id, 'subject', x.subject, 'received_at', x.received_at, 'kind', x.kind,
        'direction', x.direction, 'from_name', x.from_name) order by x.received_at), '[]'::jsonb)
        from public.mail_messages x
       where x.tenant_id = v_tenant and m.case_key is not null and x.case_key = m.case_key and x.id <> m.id));
end;
$$;

create or replace function public.mail_counts_v1()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_today integer;
  v_waiting integer;
  v_spaces jsonb;
  v_unread integer;
  v_archived integer;
begin
  select count(*) filter (where m.archived_at is null and m.direction = 'in'
           and m.received_at > now() - interval '45 days'
           and coalesce((st->>'actionable')::boolean, false) and not coalesce((st->>'done')::boolean, false)),
         count(*) filter (where m.kind = 'claim' and m.done_at is null and m.archived_at is null),
         count(*) filter (where m.read_at is null and not m.provider_read and m.archived_at is null and m.kind not in ('promo', 'noise')),
         count(*) filter (where m.archived_at is not null or (m.kind = 'promo' and m.received_at < now() - interval '7 days'))
    into v_today, v_waiting, v_unread, v_archived
    from public.mail_messages m
    cross join lateral (select public.mail_message_state_internal(m.id) as st) s
   where m.tenant_id = v_tenant and m.received_at > now() - interval '120 days';

  select coalesce(jsonb_object_agg(space, n), '{}'::jsonb) into v_spaces
    from (
      select public.mail_space_internal(m.kind, m.sender_party_type) as space, count(*) as n
        from public.mail_messages m
       where m.tenant_id = v_tenant and m.archived_at is null
         and not (m.kind = 'promo' and m.received_at < now() - interval '7 days')
         and m.received_at > now() - interval '60 days'
       group by 1
    ) s;

  return jsonb_build_object('today', v_today, 'waiting', v_waiting, 'unread', v_unread,
    'archived', v_archived, 'spaces', v_spaces,
    'mailboxes', (select coalesce(jsonb_agg(jsonb_build_object(
        'address', mb.address, 'provider', mb.provider, 'last_synced_at', mb.last_synced_at,
        'error', mb.last_sync_error is not null) order by mb.address), '[]'::jsonb)
      from public.mail_mailboxes mb where mb.tenant_id = v_tenant and mb.is_active));
end;
$$;

create or replace function public.mail_record_messages_v1(p_record_type text, p_record_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
begin
  return coalesce((
    select jsonb_agg(public.mail_message_json_internal(m, false) order by m.received_at desc)
      from public.mail_messages m
     where m.tenant_id = v_tenant
       and exists (select 1 from public.mail_message_links l
                    where l.message_id = m.id and l.record_type = p_record_type and l.record_id = p_record_id)
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 13. Lo que hace el equipo: leído, hecho, archivado, ligar, corregir el tipo
-- ---------------------------------------------------------------------------

create or replace function public.mail_mark_v1(p_message_ids uuid[], p_op text)
returns integer language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_actor uuid := auth.uid();
  v_count integer;
begin
  if p_op not in ('read', 'unread', 'done', 'undone', 'archive', 'unarchive') then
    raise exception 'mail_bad_operation' using errcode = '22023';
  end if;
  update public.mail_messages m
     set read_at = case p_op when 'read' then coalesce(m.read_at, now()) when 'unread' then null else m.read_at end,
         read_by = case p_op when 'read' then coalesce(m.read_by, v_actor) when 'unread' then null else m.read_by end,
         provider_read = case when p_op = 'unread' then false else m.provider_read end,
         done_at = case p_op when 'done' then coalesce(m.done_at, now()) when 'undone' then null else m.done_at end,
         done_by = case p_op when 'done' then coalesce(m.done_by, v_actor) when 'undone' then null else m.done_by end,
         archived_at = case p_op when 'archive' then coalesce(m.archived_at, now()) when 'unarchive' then null else m.archived_at end,
         archived_by = case p_op when 'archive' then v_actor when 'unarchive' then null else m.archived_by end,
         archive_reason = case p_op when 'archive' then 'person' when 'unarchive' then null else m.archive_reason end
   where m.tenant_id = v_tenant and m.id = any (p_message_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.mail_link_v1(
  p_message_id uuid, p_record_type text, p_record_id uuid, p_remove boolean default false
) returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_ok boolean;
begin
  if not exists (select 1 from public.mail_messages where id = p_message_id and tenant_id = v_tenant) then
    raise exception 'mail_not_found' using errcode = 'P0002';
  end if;
  v_ok := case p_record_type
    when 'job' then exists (select 1 from public.mechanic_jobs where id = p_record_id and tenant_id = v_tenant)
    when 'customer' then exists (select 1 from public.customers where id = p_record_id and tenant_id = v_tenant)
    when 'supplier' then exists (select 1 from public.suppliers where id = p_record_id and tenant_id = v_tenant)
    when 'purchase_invoice' then exists (select 1 from public.purchase_invoices where id = p_record_id and tenant_id = v_tenant)
    when 'online_order' then exists (select 1 from public.online_orders where id = p_record_id and tenant_id = v_tenant)
    when 'expense' then exists (select 1 from public.expenses where id = p_record_id and tenant_id = v_tenant)
    when 'sales_invoice' then exists (select 1 from public.sales_invoices where id = p_record_id and tenant_id = v_tenant)
    else false end;
  if not v_ok then raise exception 'mail_record_not_found' using errcode = 'P0002'; end if;

  if p_remove then
    delete from public.mail_message_links
     where message_id = p_message_id and record_type = p_record_type and record_id = p_record_id;
  else
    insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source, created_by)
    values (v_tenant, p_message_id, p_record_type, p_record_id,
            not exists (select 1 from public.mail_message_links where message_id = p_message_id and is_primary),
            'person', auth.uid())
    on conflict (message_id, record_type, record_id) do update set source = 'person', confidence = 1;
    -- Aprender: una dirección ligada a mano a un cliente o proveedor queda en
    -- el directorio para los próximos correos.
    if p_record_type in ('customer', 'supplier') then
      insert into public.mail_senders (tenant_id, match_type, match_value, party_type, party_id, label, source)
      select v_tenant, 'address', lower(m.from_address), p_record_type, p_record_id,
             case p_record_type
               when 'customer' then (select c.name from public.customers c where c.id = p_record_id)
               else (select s.name from public.suppliers s where s.id = p_record_id) end,
             'person'
        from public.mail_messages m
       where m.id = p_message_id and m.from_address like '%@%'
      on conflict (tenant_id, match_type, match_value) do update
        set party_type = excluded.party_type, party_id = excluded.party_id, label = excluded.label, source = 'person';
    end if;
  end if;
  return public.mail_links_json_internal(p_message_id);
end;
$$;

create or replace function public.mail_set_kind_v1(p_message_id uuid, p_kind text, p_remember boolean default true)
returns text language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_from text;
begin
  update public.mail_messages
     set kind = p_kind, kind_source = 'person',
         archived_at = case when p_kind = 'noise' then coalesce(archived_at, now()) else archived_at end,
         archive_reason = case when p_kind = 'noise' then coalesce(archive_reason, 'person') else archive_reason end
   where id = p_message_id and tenant_id = v_tenant
  returning from_address into v_from;
  if v_from is null then raise exception 'mail_not_found' using errcode = 'P0002'; end if;
  if p_remember and p_kind in ('promo', 'noise') and v_from like '%@%' then
    insert into public.mail_senders (tenant_id, match_type, match_value, party_type, label, kind_hint, source)
    values (v_tenant, 'address', lower(v_from), p_kind, null, p_kind, 'person')
    on conflict (tenant_id, match_type, match_value) do update
      set party_type = excluded.party_type, kind_hint = excluded.kind_hint, source = 'person';
  end if;
  return p_kind;
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. Lo que usa la función de sincronización (service role)
-- ---------------------------------------------------------------------------

create or replace function public.mail_upsert_messages_v1(p_mailbox_id uuid, p_messages jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_mailbox public.mail_mailboxes%rowtype;
  v_item jsonb;
  v_new integer := 0;
  v_updated integer := 0;
  v_id uuid;
  v_inserted boolean;
begin
  select * into v_mailbox from public.mail_mailboxes where id = p_mailbox_id;
  if not found then raise exception 'mail_mailbox_not_found' using errcode = 'P0002'; end if;
  if jsonb_typeof(p_messages) <> 'array' then raise exception 'mail_bad_payload' using errcode = '22023'; end if;

  for v_item in select * from jsonb_array_elements(p_messages) loop
    insert into public.mail_messages as mm (
      tenant_id, mailbox_id, provider_message_id, provider_thread_id, provider_folder_id,
      rfc_message_id, in_reply_to, reference_ids, direction, from_address, from_name,
      to_addresses, cc_addresses, subject, snippet, body_text, has_attachments, attachments,
      labels, provider_read, in_inbox, is_bulk, received_at
    ) values (
      v_mailbox.tenant_id, v_mailbox.id,
      v_item->>'provider_message_id',
      nullif(v_item->>'provider_thread_id', ''),
      nullif(v_item->>'provider_folder_id', ''),
      nullif(v_item->>'rfc_message_id', ''),
      nullif(v_item->>'in_reply_to', ''),
      coalesce(array(select jsonb_array_elements_text(coalesce(v_item->'reference_ids', '[]'::jsonb))), '{}'),
      coalesce(nullif(v_item->>'direction', ''), 'in'),
      lower(coalesce(v_item->>'from_address', '')),
      nullif(v_item->>'from_name', ''),
      coalesce(array(select lower(jsonb_array_elements_text(coalesce(v_item->'to_addresses', '[]'::jsonb)))), '{}'),
      coalesce(array(select lower(jsonb_array_elements_text(coalesce(v_item->'cc_addresses', '[]'::jsonb)))), '{}'),
      left(coalesce(v_item->>'subject', ''), 998),
      left(nullif(v_item->>'snippet', ''), 600),
      left(nullif(v_item->>'body_text', ''), 60000),
      coalesce((v_item->>'has_attachments')::boolean, false),
      coalesce(v_item->'attachments', '[]'::jsonb),
      coalesce(array(select jsonb_array_elements_text(coalesce(v_item->'labels', '[]'::jsonb))), '{}'),
      coalesce((v_item->>'provider_read')::boolean, false),
      coalesce((v_item->>'in_inbox')::boolean, true),
      coalesce((v_item->>'is_bulk')::boolean, false),
      coalesce((v_item->>'received_at')::timestamptz, now())
    )
    on conflict (mailbox_id, provider_message_id) do update
      set labels = excluded.labels,
          provider_read = excluded.provider_read,
          in_inbox = excluded.in_inbox,
          is_bulk = mm.is_bulk or excluded.is_bulk,
          provider_thread_id = coalesce(excluded.provider_thread_id, mm.provider_thread_id),
          body_text = coalesce(mm.body_text, excluded.body_text),
          attachments = case when jsonb_array_length(mm.attachments) = 0 then excluded.attachments else mm.attachments end,
          has_attachments = mm.has_attachments or excluded.has_attachments
    returning id, (xmax = 0) into v_id, v_inserted;
    if v_inserted then v_new := v_new + 1; else v_updated := v_updated + 1; end if;
  end loop;

  return jsonb_build_object('new', v_new, 'updated', v_updated);
end;
$$;

create or replace function public.mail_prepare_tenant_v1(p_tenant_id uuid)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_mailboxes integer;
  v_senders integer;
begin
  insert into public.mail_mailboxes (tenant_id, provider, address)
  select distinct a.tenant_id, a.provider, lower(btrim(a.account_email))
    from public.email_accounts a
   where a.tenant_id = p_tenant_id and a.is_active and a.account_email like '%@%'
  on conflict (tenant_id, provider, address) do nothing;
  get diagnostics v_mailboxes = row_count;
  v_senders := public.mail_refresh_senders_internal(p_tenant_id);
  return jsonb_build_object('new_mailboxes', v_mailboxes, 'senders', v_senders);
end;
$$;

-- Reclasifica todo el correo de un tenant: después de cambiar reglas o
-- directorio, o cuando aparece un proveedor nuevo.
create or replace function public.mail_reclassify_v1(p_tenant_id uuid, p_since timestamptz default null)
returns integer language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  perform public.mail_refresh_senders_internal(p_tenant_id);
  for v_id in select id from public.mail_messages
               where tenant_id = p_tenant_id and (p_since is null or received_at >= p_since)
               order by received_at loop
    perform public.mail_classify_message_internal(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.dispatch_mail_sync_v1(p_reason text default 'cron')
returns uuid language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_endpoint text;
  v_token text;
  v_run uuid;
begin
  select endpoint into v_endpoint from public.mail_sync_runtime where singleton and enabled;
  if v_endpoint is null then return null; end if;
  -- Una corrida a la vez: si hay una reclamada hace menos de 5 minutos, no se
  -- despacha otra.
  if exists (select 1 from public.mail_sync_runs
              where claimed_at is not null and finished_at is null
                and claimed_at > clock_timestamp() - interval '5 minutes') then
    return null;
  end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.mail_sync_runs (reason, token_hash)
  values (left(coalesce(p_reason, 'cron'), 40), encode(extensions.digest(v_token, 'sha256'), 'hex'))
  returning id into v_run;
  perform net.http_post(
    url := v_endpoint,
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('run_id', v_run, 'token', v_token),
    timeout_milliseconds := 5000
  );
  delete from public.mail_sync_runs where requested_at < clock_timestamp() - interval '7 days';
  return v_run;
end;
$$;

create or replace function public.claim_mail_sync_run_v1(p_run_id uuid, p_token text)
returns boolean language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_count integer;
begin
  update public.mail_sync_runs
     set claimed_at = clock_timestamp()
   where id = p_run_id and claimed_at is null
     and requested_at > clock_timestamp() - interval '10 minutes'
     and token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  get diagnostics v_count = row_count;
  return v_count = 1;
end;
$$;

create or replace function public.finish_mail_sync_run_v1(p_run_id uuid, p_result jsonb, p_error text)
returns void language sql security definer
set search_path = pg_catalog, public
as $$
  update public.mail_sync_runs
     set finished_at = clock_timestamp(), result = p_result, error = left(p_error, 1000)
   where id = p_run_id;
$$;

-- ---------------------------------------------------------------------------
-- 15. Permisos de las funciones
-- ---------------------------------------------------------------------------

revoke all on function public.mail_fold_internal(text) from public, anon, authenticated;
revoke all on function public.mail_domain_internal(text) from public, anon, authenticated;
revoke all on function public.mail_rut_key_internal(text) from public, anon, authenticated;
revoke all on function public.mail_amount_internal(text) from public, anon, authenticated;
revoke all on function public.mail_extract_facts_internal(text, text, text) from public, anon, authenticated;
revoke all on function public.mail_refresh_senders_internal(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mail_resolve_sender_internal(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.mail_classify_message_internal(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mail_messages_classify_trigger() from public, anon, authenticated, service_role;
revoke all on function public.mail_space_internal(text, text) from public, anon, authenticated;
revoke all on function public.mail_message_state_internal(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mail_require_staff_internal() from public, anon, authenticated, service_role;
revoke all on function public.mail_links_json_internal(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mail_message_json_internal(public.mail_messages, boolean) from public, anon, authenticated, service_role;

revoke all on function public.mail_inbox_v1(text, text, text, integer, timestamptz) from public, anon;
revoke all on function public.mail_message_v1(uuid) from public, anon;
revoke all on function public.mail_counts_v1() from public, anon;
revoke all on function public.mail_record_messages_v1(text, uuid) from public, anon;
revoke all on function public.mail_mark_v1(uuid[], text) from public, anon;
revoke all on function public.mail_link_v1(uuid, text, uuid, boolean) from public, anon;
revoke all on function public.mail_set_kind_v1(uuid, text, boolean) from public, anon;
grant execute on function public.mail_inbox_v1(text, text, text, integer, timestamptz) to authenticated;
grant execute on function public.mail_message_v1(uuid) to authenticated;
grant execute on function public.mail_counts_v1() to authenticated;
grant execute on function public.mail_record_messages_v1(text, uuid) to authenticated;
grant execute on function public.mail_mark_v1(uuid[], text) to authenticated;
grant execute on function public.mail_link_v1(uuid, text, uuid, boolean) to authenticated;
grant execute on function public.mail_set_kind_v1(uuid, text, boolean) to authenticated;

revoke all on function public.mail_upsert_messages_v1(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.mail_prepare_tenant_v1(uuid) from public, anon, authenticated;
revoke all on function public.mail_reclassify_v1(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.dispatch_mail_sync_v1(text) from public, anon, authenticated, service_role;
revoke all on function public.claim_mail_sync_run_v1(uuid, text) from public, anon, authenticated;
revoke all on function public.finish_mail_sync_run_v1(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function public.mail_upsert_messages_v1(uuid, jsonb) to service_role;
grant execute on function public.mail_prepare_tenant_v1(uuid) to service_role;
grant execute on function public.mail_reclassify_v1(uuid, timestamptz) to service_role;
grant execute on function public.claim_mail_sync_run_v1(uuid, text) to service_role;
grant execute on function public.finish_mail_sync_run_v1(uuid, jsonb, text) to service_role;

-- La sincronización corre cada 2 minutos cuando la función está habilitada en
-- `mail_sync_runtime` (además de los avisos push de Gmail y Zoho).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select cron.unschedule(jobid) from cron.job where jobname = 'vinabike_mail_sync'$q$;
    execute $q$select cron.schedule('vinabike_mail_sync', '*/2 * * * *', 'select public.dispatch_mail_sync_v1(''cron'');')$q$;
  end if;
end;
$$;

comment on table public.mail_messages is
  'Correo de las casillas de la empresa, una copia para todo el equipo. El estado de cada botón se calcula del registro (mail_message_state_internal), nunca se guarda aquí.';
comment on table public.mail_message_links is
  'Vínculos de un correo con sus registros del ERP. source dice de dónde salió: remitente, número, documento, hilo, IA o una persona.';
comment on table public.mail_senders is
  'Directorio de remitentes: dirección o dominio → cliente, proveedor, banco, courier o plataforma. Se siembra de clientes y proveedores y aprende de cada corrección.';

commit;
