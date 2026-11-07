-- Correo que trabaja: una casilla apagada no se ve (2026-11-06).
--
-- Apagar una casilla (`mail_set_mailbox_active_v1`) dejaba de traer correo
-- nuevo, pero lo ya guardado de esa casilla seguía a la vista de todo el
-- equipo: si alguien encendía por error el correo personal de una persona y
-- lo apagaba, ese correo quedaba para todos. Desde aquí cada lectura y cada
-- acción del equipo mira sólo las casillas encendidas. Nada se borra: si la
-- casilla se vuelve a encender, su correo vuelve a verse.
--
-- Además el selector de casillas muestra lo «Para hoy» de cada una, así que
-- los conteos se calculan por casilla en una sola pasada; una dirección que
-- no es una casilla encendida cuenta cero (antes contaba todo).
--
-- Las v1 de la bandeja y los conteos pasan a ser la v2 sin casilla: una sola
-- regla, y ninguna puerta lateral al correo de una casilla apagada.

begin;

-- ---------------------------------------------------------------------------
-- 1. La bandeja y los conteos
-- ---------------------------------------------------------------------------

create or replace function public.mail_inbox_v2(
  p_view text default 'today',
  p_space text default null,
  p_query text default null,
  p_limit integer default 120,
  p_before timestamptz default null,
  p_mailbox text default null
) returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_limit integer := least(greatest(coalesce(p_limit, 120), 1), 300);
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
  v_digits text := nullif(regexp_replace(coalesce(p_query, ''), '\D', '', 'g'), '');
  v_result jsonb;
  v_mailbox uuid;
begin
  if nullif(btrim(coalesce(p_mailbox, '')), '') is not null then
    select mb.id into v_mailbox from public.mail_mailboxes mb
     where mb.tenant_id = v_tenant and mb.address = lower(btrim(p_mailbox)) and mb.is_active;
    if v_mailbox is null then return '[]'::jsonb; end if;
  end if;
  with base as (
    select m.*, public.mail_message_state_internal(m.id) as st
      from public.mail_messages m
      join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
     where m.tenant_id = v_tenant
       and (v_mailbox is null or m.mailbox_id = v_mailbox)
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

create or replace function public.mail_counts_v2(p_mailbox text default null)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_wanted text := nullif(lower(btrim(coalesce(p_mailbox, ''))), '');
  v_mailbox uuid;
  v_today integer;
  v_waiting integer;
  v_unread integer;
  v_archived integer;
  v_per jsonb;
  v_spaces jsonb;
begin
  if v_wanted is not null then
    select mb.id into v_mailbox from public.mail_mailboxes mb
     where mb.tenant_id = v_tenant and mb.address = v_wanted and mb.is_active;
  end if;

  -- Una pasada por casilla encendida: lo de cada una para el selector y, para
  -- las pestañas, la suma (o sólo la elegida).
  with per as (
    select m.mailbox_id,
           count(*) filter (where m.archived_at is null and m.direction = 'in'
             and m.received_at > now() - interval '45 days'
             and coalesce((s.st->>'actionable')::boolean, false)
             and not coalesce((s.st->>'done')::boolean, false)) as today,
           count(*) filter (where m.kind = 'claim' and m.done_at is null and m.archived_at is null) as waiting,
           count(*) filter (where m.read_at is null and not m.provider_read and m.archived_at is null
             and m.kind not in ('promo', 'noise')) as unread,
           count(*) filter (where m.archived_at is not null
             or (m.kind = 'promo' and m.received_at < now() - interval '7 days')) as archived
      from public.mail_messages m
      join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
     cross join lateral (select public.mail_message_state_internal(m.id) as st) s
     where m.tenant_id = v_tenant and m.received_at > now() - interval '120 days'
     group by m.mailbox_id
  )
  select coalesce(sum(p.today) filter (where v_wanted is null or p.mailbox_id = v_mailbox), 0),
         coalesce(sum(p.waiting) filter (where v_wanted is null or p.mailbox_id = v_mailbox), 0),
         coalesce(sum(p.unread) filter (where v_wanted is null or p.mailbox_id = v_mailbox), 0),
         coalesce(sum(p.archived) filter (where v_wanted is null or p.mailbox_id = v_mailbox), 0),
         coalesce(jsonb_object_agg(p.mailbox_id::text, p.today), '{}'::jsonb)
    into v_today, v_waiting, v_unread, v_archived, v_per
    from per p;

  select coalesce(jsonb_object_agg(space, n), '{}'::jsonb) into v_spaces
    from (
      select public.mail_space_internal(m.kind, m.sender_party_type) as space, count(*) as n
        from public.mail_messages m
        join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
       where m.tenant_id = v_tenant and m.archived_at is null
         and (v_wanted is null or m.mailbox_id = v_mailbox)
         and not (m.kind = 'promo' and m.received_at < now() - interval '7 days')
         and m.received_at > now() - interval '60 days'
       group by 1
    ) s;

  return jsonb_build_object('today', v_today, 'waiting', v_waiting, 'unread', v_unread,
    'archived', v_archived, 'spaces', v_spaces,
    'mailboxes', (select coalesce(jsonb_agg(jsonb_build_object(
        'address', mb.address, 'provider', mb.provider, 'last_synced_at', mb.last_synced_at,
        'error', mb.last_sync_error is not null,
        'today', coalesce((v_per->>mb.id::text)::integer, 0)) order by mb.address), '[]'::jsonb)
      from public.mail_mailboxes mb where mb.tenant_id = v_tenant and mb.is_active));
end;
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
begin
  return public.mail_inbox_v2(p_view, p_space, p_query, p_limit, p_before, null);
end;
$$;

create or replace function public.mail_counts_v1()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
begin
  return public.mail_counts_v2(null);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Un correo, y los correos de un registro
-- ---------------------------------------------------------------------------

create or replace function public.mail_message_v1(p_message_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  m public.mail_messages%rowtype;
begin
  select msg.* into m from public.mail_messages msg
    join public.mail_mailboxes mb on mb.id = msg.mailbox_id and mb.is_active
   where msg.id = p_message_id and msg.tenant_id = v_tenant;
  if not found then raise exception 'mail_not_found' using errcode = 'P0002'; end if;
  return public.mail_message_json_internal(m, true)
    || jsonb_build_object('case', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', x.id, 'subject', x.subject, 'received_at', x.received_at, 'kind', x.kind,
        'direction', x.direction, 'from_name', x.from_name) order by x.received_at), '[]'::jsonb)
        from public.mail_messages x
        join public.mail_mailboxes xb on xb.id = x.mailbox_id and xb.is_active
       where x.tenant_id = v_tenant and m.case_key is not null and x.case_key = m.case_key and x.id <> m.id));
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
      join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
     where m.tenant_id = v_tenant
       and exists (select 1 from public.mail_message_links l
                    where l.message_id = m.id and l.record_type = p_record_type and l.record_id = p_record_id)
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Lo que hace el equipo, sólo sobre correo de casillas encendidas
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
   where m.tenant_id = v_tenant and m.id = any (p_message_ids)
     and exists (select 1 from public.mail_mailboxes mb where mb.id = m.mailbox_id and mb.is_active);
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
  if not exists (select 1 from public.mail_messages m
                   join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
                  where m.id = p_message_id and m.tenant_id = v_tenant) then
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
  update public.mail_messages m
     set kind = p_kind, kind_source = 'person',
         archived_at = case when p_kind = 'noise' then coalesce(m.archived_at, now()) else m.archived_at end,
         archive_reason = case when p_kind = 'noise' then coalesce(m.archive_reason, 'person') else m.archive_reason end
   where m.id = p_message_id and m.tenant_id = v_tenant
     and exists (select 1 from public.mail_mailboxes mb where mb.id = m.mailbox_id and mb.is_active)
  returning m.from_address into v_from;
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
-- 4. La lectura directa de las tablas sigue la misma regla
-- ---------------------------------------------------------------------------

drop policy if exists mail_messages_staff_read on public.mail_messages;
create policy mail_messages_staff_read on public.mail_messages
  for select to authenticated using (
    public.messaging_is_staff_in_tenant(tenant_id)
    and exists (select 1 from public.mail_mailboxes mb where mb.id = mailbox_id and mb.is_active));

drop policy if exists mail_message_links_staff_read on public.mail_message_links;
create policy mail_message_links_staff_read on public.mail_message_links
  for select to authenticated using (
    public.messaging_is_staff_in_tenant(tenant_id)
    and exists (select 1 from public.mail_messages m
                  join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
                 where m.id = message_id));

-- Las firmas no cambian; los permisos se repiten por claridad.
revoke all on function public.mail_inbox_v2(text, text, text, integer, timestamptz, text) from public, anon;
revoke all on function public.mail_counts_v2(text) from public, anon;
revoke all on function public.mail_inbox_v1(text, text, text, integer, timestamptz) from public, anon;
revoke all on function public.mail_counts_v1() from public, anon;
revoke all on function public.mail_message_v1(uuid) from public, anon;
revoke all on function public.mail_record_messages_v1(text, uuid) from public, anon;
revoke all on function public.mail_mark_v1(uuid[], text) from public, anon;
revoke all on function public.mail_link_v1(uuid, text, uuid, boolean) from public, anon;
revoke all on function public.mail_set_kind_v1(uuid, text, boolean) from public, anon;
grant execute on function public.mail_inbox_v2(text, text, text, integer, timestamptz, text) to authenticated;
grant execute on function public.mail_counts_v2(text) to authenticated;
grant execute on function public.mail_inbox_v1(text, text, text, integer, timestamptz) to authenticated;
grant execute on function public.mail_counts_v1() to authenticated;
grant execute on function public.mail_message_v1(uuid) to authenticated;
grant execute on function public.mail_record_messages_v1(text, uuid) to authenticated;
grant execute on function public.mail_mark_v1(uuid[], text) to authenticated;
grant execute on function public.mail_link_v1(uuid, text, uuid, boolean) to authenticated;
grant execute on function public.mail_set_kind_v1(uuid, text, boolean) to authenticated;

commit;
