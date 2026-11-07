-- Correo que trabaja: una casilla o todas (2026-11-06).
--
-- El dueño, al ver la pantalla nueva: «we lost the controls to manage
-- different accounts, like the merged inbox and the possibility to toggle
-- between different accounts». La bandeja unida sigue siendo lo normal; estas
-- versiones reciben además la casilla (su dirección) para ver sólo la de Gmail
-- o sólo la de Zoho, con sus conteos. Las v1 quedan para las apps que aún no
-- se actualizan.

begin;

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
     where mb.tenant_id = v_tenant and mb.address = lower(btrim(p_mailbox));
    if v_mailbox is null then return '[]'::jsonb; end if;
  end if;
  with base as (
    select m.*, public.mail_message_state_internal(m.id) as st
      from public.mail_messages m
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
  v_today integer;
  v_waiting integer;
  v_spaces jsonb;
  v_unread integer;
  v_archived integer;
  v_mailbox uuid;
begin
  if nullif(btrim(coalesce(p_mailbox, '')), '') is not null then
    select mb.id into v_mailbox from public.mail_mailboxes mb
     where mb.tenant_id = v_tenant and mb.address = lower(btrim(p_mailbox));
  end if;
  select count(*) filter (where m.archived_at is null and m.direction = 'in'
           and m.received_at > now() - interval '45 days'
           and coalesce((st->>'actionable')::boolean, false) and not coalesce((st->>'done')::boolean, false)),
         count(*) filter (where m.kind = 'claim' and m.done_at is null and m.archived_at is null),
         count(*) filter (where m.read_at is null and not m.provider_read and m.archived_at is null and m.kind not in ('promo', 'noise')),
         count(*) filter (where m.archived_at is not null or (m.kind = 'promo' and m.received_at < now() - interval '7 days'))
    into v_today, v_waiting, v_unread, v_archived
    from public.mail_messages m
    cross join lateral (select public.mail_message_state_internal(m.id) as st) s
   where m.tenant_id = v_tenant and m.received_at > now() - interval '120 days'
     and (v_mailbox is null or m.mailbox_id = v_mailbox);

  select coalesce(jsonb_object_agg(space, n), '{}'::jsonb) into v_spaces
    from (
      select public.mail_space_internal(m.kind, m.sender_party_type) as space, count(*) as n
        from public.mail_messages m
       where m.tenant_id = v_tenant and m.archived_at is null
         and (v_mailbox is null or m.mailbox_id = v_mailbox)
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

revoke all on function public.mail_inbox_v2(text, text, text, integer, timestamptz, text) from public, anon;
revoke all on function public.mail_counts_v2(text) from public, anon;
grant execute on function public.mail_inbox_v2(text, text, text, integer, timestamptz, text) to authenticated;
grant execute on function public.mail_counts_v2(text) to authenticated;

commit;
