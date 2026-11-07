-- Correo que trabaja: afinar con el correo real (2026-11-06).
--
-- Etapa 5 de la propuesta aprobada («medir y afinar»), con lo que el correo
-- guardado mostró:
--
-- * Derman escribe desde dermanalmayor.cl, distinto del dominio de su ficha, y
--   sus 4 correos quedaban «sin clasificar» y fuera de su historia. Un dominio
--   que empieza con el nombre completo de un proveedor (6 letras o más) es de
--   ese proveedor.
-- * Veryfi y Meta (email.meta.com) faltaban como plataformas.
-- * El resumen de la mañana contaba como «cliente» un reclamo al que nos toca
--   responder, y su línea de seguimientos no calzaba con el grupo de «Para
--   hoy». Ahora cuenta lo mismo que los grupos, y cada línea dice desde cuándo
--   espera lo más antiguo: en «Para hoy» había cosas de hace 10 a 28 días.
--
-- Lo demás de la etapa no tiene datos todavía y no se inventa: 0 respuestas a
-- clientes por correo (el taller responde por WhatsApp), 6 pedidos con un solo
-- correo cada uno y 0 correcciones. Las reglas que aprenden de una corrección
-- ya existen (`mail_set_kind_v1`).

begin;

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
      -- Vistos en el correo real como «sin clasificar» (2026-11-06).
      ('veryfi.com', 'platform', 'Veryfi', null),
      ('meta.com', 'platform', 'Meta', null)
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


  -- Lo nuestro sale de las casillas activas del tenant: su dirección, y su
  -- dominio cuando no es de correo personal. Nada fijo por empresa.
  delete from public.mail_senders ms
   where ms.tenant_id = p_tenant_id and ms.source = 'seed' and ms.party_type = 'own'
     and not exists (
       select 1 from public.mail_mailboxes mb
        where mb.tenant_id = p_tenant_id and mb.is_active
          and (mb.address = ms.match_value or public.mail_domain_internal(mb.address) = ms.match_value));

  insert into public.mail_senders (tenant_id, match_type, match_value, party_type, label, kind_hint, source)
  select distinct on (o.match_type, o.match_value)
         p_tenant_id, o.match_type, o.match_value, 'own', o.label, 'own', 'seed'
    from (
      select 'address'::text as match_type, mb.address as match_value,
             coalesce(nullif(btrim(t.shop_name), ''), 'Nosotros') as label
        from public.mail_mailboxes mb
        join public.tenants t on t.id = mb.tenant_id
       where mb.tenant_id = p_tenant_id and mb.is_active
      union all
      select 'domain', public.mail_domain_internal(mb.address),
             coalesce(nullif(btrim(t.shop_name), ''), 'Nosotros')
        from public.mail_mailboxes mb
        join public.tenants t on t.id = mb.tenant_id
       where mb.tenant_id = p_tenant_id and mb.is_active
         and public.mail_domain_internal(mb.address) not in (
           'gmail.com', 'googlemail.com', 'hotmail.com', 'outlook.com', 'yahoo.com', 'icloud.com',
           'live.cl', 'hotmail.cl', 'yahoo.es', 'live.com', 'msn.com', 'outlook.cl', 'me.com',
           'zoho.com', 'zohomail.com', 'proton.me', 'protonmail.com')
    ) o
   where o.match_value is not null
   order by o.match_type, o.match_value
  on conflict (tenant_id, match_type, match_value) do update
    set party_type = 'own', party_id = null, label = excluded.label, kind_hint = 'own'
    where public.mail_senders.source in ('seed', 'supplier');
  get diagnostics v_rows = row_count;
  v_count := v_count + v_rows;

  return v_count;
end;
$$;

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

  -- Un proveedor que escribe desde un dominio con su nombre, distinto del de
  -- su ficha (dermanalmayor.cl → «Derman»): el dominio empieza con el nombre
  -- completo del proveedor, de 6 letras o más, para no confundir palabras
  -- comunes. El más largo gana.
  select 'supplier'::text as party_type, s.id as party_id, s.name as label into v_row
    from public.suppliers s
   cross join lateral (select regexp_replace(public.mail_fold_internal(s.name), '[^a-z0-9]', '', 'g') as key) k
   where s.tenant_id = p_tenant_id and coalesce(s.is_active, true)
     and length(k.key) >= 6
     and split_part(v_domain, '.', 1) like k.key || '%'
   order by length(k.key) desc limit 1;
  if found then
    return query select v_row.party_type, v_row.party_id, v_row.label, null::text;
    return;
  end if;

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

create or replace function public.mail_morning_summary_v1()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_result jsonb;
begin
  with base as (
    select m as msg, m.received_at, m.kind, m.direction, m.facts,
           public.mail_message_state_internal(m.id) as st
      from public.mail_messages m
      join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
     where m.tenant_id = v_tenant and m.received_at > now() - interval '45 days'
  ), today as (
    select b.* from base b where public.mail_in_view_internal('today', b.msg, b.st)
  ), amounts as (
    select b.*, case when coalesce(b.facts->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$'
                     then (b.facts->>'amount')::numeric end as amount
      from base b
     where b.kind = 'transfer'
  )
  select jsonb_build_object(
    'today', (select count(*) from today),
    'payments', (select count(*) from today where st->>'action' = 'register_payment'),
    'payments_since', (select min(received_at) from today where st->>'action' = 'register_payment'),
    'payments_amount', (select coalesce(sum(a.amount), 0) from amounts a
                         where public.mail_in_view_internal('today', a.msg, a.st)),
    'invoices', (select count(*) from today where st->>'action' in ('register_purchase', 'register_expense')),
    'invoices_since', (select min(received_at) from today where st->>'action' in ('register_purchase', 'register_expense')),
    'statements', (select count(*) from today where st->>'action' = 'import_statement'),
    'statements_since', (select min(received_at) from today where st->>'action' = 'import_statement'),
    -- Un reclamo al que nos toca responder es un seguimiento, no un cliente:
    -- las líneas cuentan lo mismo que los grupos de «Para hoy».
    'customers', (select count(*) from today where st->>'action' = 'reply' and kind <> 'claim'),
    'customers_since', (select min(received_at) from today where st->>'action' = 'reply' and kind <> 'claim'),
    'follow_ups', (select count(*) from today where st->>'action' = 'remind' or kind = 'claim'),
    'follow_ups_since', (select min(received_at) from today where st->>'action' = 'remind' or kind = 'claim'),
    'reviews', (select count(*) from today where st->>'action' = 'reply_review'),
    'reviews_since', (select min(received_at) from today where st->>'action' = 'reply_review'),
    'security', (select count(*) from today where st->>'action' = 'review'),
    'security_since', (select min(received_at) from today where st->>'action' = 'review'),
    'transfers_24h', (select count(*) from amounts where received_at > now() - interval '24 hours'),
    'transfers_24h_amount', (select coalesce(sum(amount), 0) from amounts
                              where received_at > now() - interval '24 hours'),
    'transfers_24h_done', (select count(*) from amounts where received_at > now() - interval '24 hours'
                            and coalesce((st->>'done')::boolean, false)),
    'arrived_24h', (select count(*) from base where direction = 'in'
                     and received_at > now() - interval '24 hours' and kind not in ('promo', 'noise')),
    'archived_week', (select count(*) from base where direction = 'in'
                       and received_at > now() - interval '7 days' and kind in ('promo', 'noise'))
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.mail_refresh_senders_internal(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mail_resolve_sender_internal(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.mail_morning_summary_v1() from public, anon;
grant execute on function public.mail_morning_summary_v1() to authenticated;

-- Las reglas nuevas se aplican a lo guardado: el directorio de cada tenant con
-- casillas, y los correos de remitentes sin identificar.
do $$
declare
  v_tenant uuid;
  v_id uuid;
begin
  for v_tenant in select distinct tenant_id from public.mail_mailboxes loop
    perform public.mail_refresh_senders_internal(v_tenant);
  end loop;
  for v_id in select id from public.mail_messages
               where coalesce(sender_party_type, 'unknown') = 'unknown' loop
    perform public.mail_classify_message_internal(v_id);
  end loop;
end;
$$;

commit;
