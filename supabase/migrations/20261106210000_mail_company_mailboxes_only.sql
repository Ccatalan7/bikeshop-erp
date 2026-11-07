-- Correo que trabaja: sólo las casillas de la empresa (2026-11-06).
--
-- 20261106200000 convertía en casilla de la empresa cualquier correo que una
-- persona del equipo conectara en el ERP. Si alguien conectaba su correo
-- personal, ese correo quedaba guardado para que todo el equipo lo leyera.
-- Desde aquí una casilla nace apagada y la enciende el dueño o un
-- administrador (`mail_set_mailbox_active_v1`); la sincronización sólo lee
-- las encendidas.
--
-- También «lo nuestro» deja de ser un dominio fijo: el directorio marca como
-- propios la dirección de cada casilla encendida y su dominio cuando no es de
-- correo personal.

begin;

alter table public.mail_mailboxes alter column is_active set default false;

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
      ('zohobooks.com', 'noise', 'Zoho Books', 'noise')
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

create or replace function public.mail_set_mailbox_active_v1(p_mailbox_id uuid, p_active boolean)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_row public.mail_mailboxes%rowtype;
begin
  if not exists (
    select 1 from public.user_profiles up
     where up.user_id = auth.uid() and up.tenant_id = v_tenant
       and coalesce(up.is_active, true) and up.role in ('owner', 'admin')
  ) then
    raise exception 'mail_forbidden' using errcode = '42501';
  end if;

  update public.mail_mailboxes
     set is_active = coalesce(p_active, false)
   where id = p_mailbox_id and tenant_id = v_tenant
  returning * into v_row;
  if not found then
    raise exception 'mail_mailbox_not_found' using errcode = 'P0002';
  end if;

  perform public.mail_refresh_senders_internal(v_tenant);
  return jsonb_build_object('id', v_row.id, 'provider', v_row.provider,
    'address', v_row.address, 'is_active', v_row.is_active);
end;
$$;

revoke all on function public.mail_refresh_senders_internal(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mail_set_mailbox_active_v1(uuid, boolean) from public, anon;
grant execute on function public.mail_set_mailbox_active_v1(uuid, boolean) to authenticated;

comment on column public.mail_mailboxes.is_active is
  'Encendida por el dueño o un administrador. Una casilla conectada nace apagada: el correo personal de alguien del equipo nunca se guarda para todos.';

commit;
