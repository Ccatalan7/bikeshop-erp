-- Presencia en internet: lo que Google dice de la tienda, guardado día a día.
--
-- El 2026-10-14 el dueño pidió seguir «todas esas métricas» en el ERP y un
-- análisis periódico de cómo cambian con lo que hacemos en el sitio. Hasta
-- ese día se leían a mano en las consolas (Search Console, Analytics) y se
-- archivaban en el wiki; ninguna cifra quedaba en la base.
--
-- La función `web-presence-collect` lee con la cuenta de servicio de
-- Viñabike (ya tiene acceso a Search Console) y guarda aquí. La app sólo lee;
-- nadie más que la función escribe las cifras. Los cambios que hicimos salen
-- del registro del wiki del sitio (docs/wiki/sitio-web/log.md), que ya es su
-- dueño, y el análisis periódico deja su nota en `web_presence_notes`.

create table public.web_presence_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  enabled boolean not null default true,
  -- Propiedad de Search Console, «sc-domain:vinabike.cl»; vacía = del
  -- dominio de la tienda.
  gsc_site text,
  sitemap_url text,
  -- Propiedad de Google Analytics 4 (número), no el ID de medición «G-…».
  ga4_property_id text check (ga4_property_id is null or ga4_property_id ~ '^[0-9]{6,12}$'),
  updated_at timestamptz not null default now(),
  updated_by uuid
);

-- Totales del sitio en la Búsqueda de Google, por día (tipo «web»).
create table public.web_presence_search_daily (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  day date not null,
  clicks integer not null default 0,
  impressions integer not null default 0,
  position numeric,
  primary key (tenant_id, day)
);

-- Consultas y páginas por día. Google omite las consultas anónimas, así que
-- su suma es menor que el total del día.
create table public.web_presence_search_terms (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('query', 'page')),
  term text not null,
  clicks integer not null default 0,
  impressions integer not null default 0,
  position numeric,
  primary key (tenant_id, kind, day, term)
);

-- Cada dirección del sitemap y lo último que dijo la inspección de Google.
create table public.web_presence_urls (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  url text not null,
  in_sitemap boolean not null default true,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  inspected_at timestamptz,
  verdict text,
  coverage_state text,
  indexing_state text,
  page_fetch_state text,
  robots_state text,
  last_crawl_at timestamptz,
  google_canonical text,
  user_canonical text,
  inspect_error text,
  primary key (tenant_id, url)
);
create index web_presence_urls_due_idx
  on public.web_presence_urls (tenant_id, in_sitemap, inspected_at nulls first);

-- Foto diaria de la indexación de lo que está en el sitemap.
create table public.web_presence_index_daily (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  day date not null,
  sitemap_urls integer not null default 0,
  inspected integer not null default 0,
  indexed integer not null default 0,
  by_state jsonb not null default '{}'::jsonb,
  sitemap_submitted integer,
  sitemap_last_read timestamptz,
  primary key (tenant_id, day)
);

-- Visitas por canal (Google Analytics 4). «sitio» = sólo el dominio de la
-- tienda; «chile» = además sólo desde Chile (sin el Mac del dueño, que GA4
-- ubica en Seattle).
create table public.web_presence_traffic_daily (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  day date not null,
  scope text not null check (scope in ('sitio', 'chile')),
  channel text not null,
  sessions integer not null default 0,
  engaged_sessions integer not null default 0,
  users integer not null default 0,
  key_events numeric not null default 0,
  primary key (tenant_id, scope, day, channel)
);

create table public.web_presence_events_daily (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  day date not null,
  scope text not null check (scope in ('sitio', 'chile')),
  event_name text not null,
  event_count integer not null default 0,
  primary key (tenant_id, scope, day, event_name)
);

-- Lo que hicimos («cambio», del registro del wiki) y lo que concluyó cada
-- análisis periódico («analisis»).
create table public.web_presence_notes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  kind text not null check (kind in ('cambio', 'analisis')),
  day date not null,
  title text not null,
  body text,
  source text,
  source_key text not null,
  created_at timestamptz not null default now(),
  unique (tenant_id, source_key)
);
create index web_presence_notes_day_idx on public.web_presence_notes (tenant_id, day desc);

-- Cada recolección: qué pidió, qué guardó y qué falló, para que la pantalla
-- diga con fecha de cuándo es cada cifra.
create table public.web_presence_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade,
  task text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'running' check (status in ('running', 'ok', 'partial', 'error')),
  detail jsonb not null default '{}'::jsonb
);
create index web_presence_runs_recent_idx on public.web_presence_runs (tenant_id, started_at desc);

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'web_presence_settings', 'web_presence_search_daily', 'web_presence_search_terms',
    'web_presence_urls', 'web_presence_index_daily', 'web_presence_traffic_daily',
    'web_presence_events_daily', 'web_presence_notes', 'web_presence_runs'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on public.%I from public, anon, authenticated', v_table);
    execute format('grant select on public.%I to authenticated', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (tenant_id = (select public.user_tenant_id()))',
      v_table || '_tenant_read', v_table);
  end loop;
end;
$$;

-- Consultas o páginas de un período, con el período anterior del mismo largo
-- para comparar. La posición es el promedio ponderado por impresiones.
create or replace function public.web_presence_terms_v1(
  p_tenant_id uuid,
  p_kind text,
  p_from date,
  p_to date,
  p_limit integer default 50
)
returns table (
  term text,
  clicks integer,
  impressions integer,
  avg_position numeric,
  previous_clicks integer,
  previous_impressions integer,
  previous_avg_position numeric
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_days integer;
begin
  perform public.catalog_assert_reader_v1(p_tenant_id);
  if p_kind not in ('query', 'page') or p_from is null or p_to is null or p_to < p_from then
    raise exception 'web_presence_terms_invalid' using errcode = '22023';
  end if;
  v_days := p_to - p_from + 1;

  return query
  with current_period as (
    select t.term,
           sum(t.clicks)::integer as clicks,
           sum(t.impressions)::integer as impressions,
           round(sum(t.position * t.impressions) / nullif(sum(t.impressions), 0), 1) as avg_pos
      from public.web_presence_search_terms t
     where t.tenant_id = p_tenant_id
       and t.kind = p_kind
       and t.day between p_from and p_to
     group by t.term
  ), previous_period as (
    select t.term,
           sum(t.clicks)::integer as clicks,
           sum(t.impressions)::integer as impressions,
           round(sum(t.position * t.impressions) / nullif(sum(t.impressions), 0), 1) as avg_pos
      from public.web_presence_search_terms t
     where t.tenant_id = p_tenant_id
       and t.kind = p_kind
       and t.day between p_from - v_days and p_from - 1
     group by t.term
  )
  select c.term, c.clicks, c.impressions, c.avg_pos,
         coalesce(p.clicks, 0), coalesce(p.impressions, 0), p.avg_pos
    from current_period c
    left join previous_period p on p.term = c.term
   order by c.clicks desc, c.impressions desc, c.term
   limit least(greatest(coalesce(p_limit, 50), 1), 500);
end;
$$;

-- Lo configurable desde la pantalla: la propiedad de Analytics y si se
-- recolecta. Search Console y el sitemap salen del dominio de la tienda.
create or replace function public.web_presence_save_settings_v1(
  p_tenant_id uuid,
  p_ga4_property_id text,
  p_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_property text := nullif(regexp_replace(coalesce(p_ga4_property_id, ''), '[^0-9]', '', 'g'), '');
begin
  perform public.catalog_assert_editor_v1(p_tenant_id);
  insert into public.web_presence_settings (tenant_id, enabled, ga4_property_id, updated_at, updated_by)
  values (p_tenant_id, coalesce(p_enabled, true), v_property, now(), auth.uid())
  on conflict (tenant_id) do update
     set enabled = excluded.enabled,
         ga4_property_id = excluded.ga4_property_id,
         updated_at = excluded.updated_at,
         updated_by = excluded.updated_by;
  return jsonb_build_object('ga4_property_id', v_property, 'enabled', coalesce(p_enabled, true));
end;
$$;

-- pg_cron llama a la función con su secreto, que vive en Vault y nunca en el
-- texto del job (el de google-public-data-refresh va escrito en el comando:
-- `select command from cron.job` lo imprime).
create or replace function public.invoke_web_presence_collect(p_action text)
returns bigint
language plpgsql
security definer
set search_path = public, vault, net, pg_catalog
as $$
declare
  v_secret text;
  v_request_id bigint;
begin
  if p_action not in ('collect', 'inspect') then
    raise exception 'web_presence_action_invalid' using errcode = '22023';
  end if;

  select secret.decrypted_secret into v_secret
    from vault.decrypted_secrets secret
   where secret.name = 'web_presence_collect_secret'
   order by secret.created_at desc
   limit 1;

  if nullif(v_secret, '') is null then
    insert into public.web_presence_runs (task, status, finished_at, detail)
    values (p_action, 'error', now(), jsonb_build_object('error', 'Falta el secreto web_presence_collect_secret en Vault'));
    return null;
  end if;

  select net.http_post(
    url := 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/web-presence-collect',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-web-presence-secret', v_secret
    ),
    body := jsonb_build_object('action', p_action),
    timeout_milliseconds := 5000
  ) into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function public.web_presence_terms_v1(uuid, text, date, date, integer) from public, anon;
grant execute on function public.web_presence_terms_v1(uuid, text, date, date, integer) to authenticated;
revoke all on function public.web_presence_save_settings_v1(uuid, text, boolean) from public, anon;
grant execute on function public.web_presence_save_settings_v1(uuid, text, boolean) to authenticated;
revoke all on function public.invoke_web_presence_collect(text) from public, anon, authenticated;

-- Todos los días a las 06:23 de Chile (09:23 UTC) la recolección completa;
-- cada dos horas un lote de inspecciones (≈1.200 al día, bajo el tope de
-- 2.000 de Google).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job
     where jobname in ('web-presence-collect-daily', 'web-presence-inspect');
    perform cron.schedule('web-presence-collect-daily', '23 9 * * *',
      $job$select public.invoke_web_presence_collect('collect')$job$);
    perform cron.schedule('web-presence-inspect', '41 */2 * * *',
      $job$select public.invoke_web_presence_collect('inspect')$job$);
  end if;
end;
$$;
