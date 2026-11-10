-- A Meta channel is swept on a schedule (2026-11-10), so nothing waits for a
-- new message: the names of contacts that already existed, which kept
-- «Instagram • 1B5849» until somebody wrote again, and the files of messages
-- that kept «Imagen recibida». The database posts a single-use ticket per
-- channel; the function redeems it.
begin;

select no_plan();

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Other channels of the local database must not post while this one is judged.
update public.meta_channels set is_active = false;
delete from public.meta_channel_sweep_tickets;
delete from net.http_request_queue;

insert into public.tenants (id, shop_name) values
  ('c0a75eeb-0000-4000-8000-000000000001', 'Meta Profile Sweep Tenant');

insert into public.meta_channels (
  id, tenant_id, provider, external_account_id, display_name, is_active
) values (
  'c0a75eeb-0001-4000-8000-000000000001',
  'c0a75eeb-0000-4000-8000-000000000001',
  'instagram', 'ig-sweep-account', 'Instagram Sweep', true
);

create temporary table sweep_queue as
select 0::bigint as last_id;

create or replace function pg_temp.posted()
returns table (url text, body jsonb, headers jsonb)
language sql
as $$
  select request.url, convert_from(request.body, 'utf8')::jsonb, request.headers
  from net.http_request_queue request
  order by request.id;
$$;

-- 1. A channel with nobody to name posts nothing.
select is(
  public.dispatch_meta_channel_sweeps(),
  0,
  'a channel without contacts due dispatches nothing'
);
select is(
  (select count(*)::integer from pg_temp.posted()),
  0,
  'and posts nothing'
);

-- 2. A conversation that already exists is due without a new message.
select public.ingest_meta_message(
  'instagram', 'ig-sweep-account',
  'meta:instagram:message:ig-sweep-account:mid-1', 'mid-1',
  'ig-sweep-user-1', null, null, 'text', 'Hola, ¿arreglan frenos?',
  now() - interval '3 days', '{}'::jsonb
);

select is(
  public.dispatch_meta_channel_sweeps(),
  1,
  'an existing contact without a name gets its channel swept'
);
select is(
  (select count(*)::integer from pg_temp.posted()),
  1,
  'one request per channel'
);
select is(
  (select url from pg_temp.posted()),
  'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/meta-channel-sweep',
  'to the function that asks Meta'
);
select is(
  (select body->>'channel_id' from pg_temp.posted()),
  'c0a75eeb-0001-4000-8000-000000000001',
  'the request names the channel'
);
select matches(
  (select body->>'token' from pg_temp.posted()),
  '^[0-9a-f]{64}$',
  'and carries a ticket'
);
select is(
  (
    select array_agg(key order by key)
    from pg_temp.posted() posted, jsonb_object_keys(posted.body) key
  ),
  array['channel_id', 'token'],
  'nothing else travels: no contact, no account, no credential'
);
select is(
  (
    select sweep.token_hash
      = encode(extensions.digest((select body->>'token' from pg_temp.posted()), 'sha256'), 'hex')
    from public.meta_channel_sweep_tickets sweep
    where sweep.channel_id = 'c0a75eeb-0001-4000-8000-000000000001'
  ),
  true,
  'the database keeps the hash of the ticket'
);
select is(
  (
    select count(*)::integer
    from public.meta_channel_sweep_tickets sweep
    where sweep.token_hash = (select body->>'token' from pg_temp.posted())
  ),
  0,
  'never the ticket itself'
);
select is(
  (
    select binding.profile_checked_at is null
    from public.meta_conversation_bindings binding
    where binding.external_user_id = 'ig-sweep-user-1'
  ),
  true,
  'dispatching claims nobody: the contact is stamped when Meta is asked'
);

-- 3. A ticket still out is not issued twice.
select is(
  public.dispatch_meta_channel_sweeps(),
  0,
  'a channel with a ticket out is not dispatched again'
);

-- 4. A wrong ticket opens nothing and spends nothing.
select is(
  public.redeem_meta_channel_sweep_ticket(
    'c0a75eeb-0001-4000-8000-000000000001', repeat('0', 64)
  ),
  null,
  'a wrong ticket redeems nothing'
);
select is(
  public.redeem_meta_channel_sweep_ticket(
    'c0a75eeb-0001-4000-8000-000000000002',
    (select body->>'token' from pg_temp.posted())
  ),
  null,
  'nor does the right ticket for another channel'
);
select is(
  public.redeem_meta_channel_sweep_ticket(
    'c0a75eeb-0001-4000-8000-000000000001', null
  ),
  null,
  'nor a missing one'
);

-- 5. The right ticket opens the sweep once.
select is(
  public.redeem_meta_channel_sweep_ticket(
    'c0a75eeb-0001-4000-8000-000000000001',
    (select body->>'token' from pg_temp.posted())
  ),
  jsonb_build_object(
    'provider', 'instagram',
    'external_account_id', 'ig-sweep-account'
  ),
  'the ticket names the account to sweep'
);
select is(
  public.redeem_meta_channel_sweep_ticket(
    'c0a75eeb-0001-4000-8000-000000000001',
    (select body->>'token' from pg_temp.posted())
  ),
  null,
  'a ticket is spent by its first use'
);
select is(
  jsonb_array_length(
    public.claim_meta_contact_profiles_due('instagram', 'ig-sweep-account', 10)
      ->'contacts'
  ),
  1,
  'the sweep it opens claims the contact that was due'
);

-- 6. Asked today: nothing to do until tomorrow.
delete from net.http_request_queue;
select is(
  public.dispatch_meta_channel_sweeps(),
  0,
  'a contact asked today does not dispatch a sweep'
);

update public.meta_conversation_bindings
set profile_checked_at = clock_timestamp() - interval '25 hours',
    profile_error = 'graph_10'
where external_user_id = 'ig-sweep-user-1';

select is(
  public.dispatch_meta_channel_sweeps(),
  1,
  'a contact Meta refused is swept again a day later, with no message needed'
);

-- 7. An expired ticket opens nothing, and the next run issues a fresh one.
update public.meta_channel_sweep_tickets
set lease_until = clock_timestamp() - interval '1 second';

select is(
  public.redeem_meta_channel_sweep_ticket(
    'c0a75eeb-0001-4000-8000-000000000001',
    (select body->>'token' from pg_temp.posted() limit 1)
  ),
  null,
  'an expired ticket redeems nothing'
);
select is(
  public.dispatch_meta_channel_sweeps(),
  1,
  'and the next run dispatches again'
);
select is(
  (select count(*)::integer from public.meta_channel_sweep_tickets),
  1,
  'a channel keeps one ticket row, replaced'
);

-- 8. A named contact is never swept.
select public.record_meta_contact_profile(
  (
    select binding.id from public.meta_conversation_bindings binding
    where binding.external_user_id = 'ig-sweep-user-1'
  ),
  'Camila Rojas', 'camila.rojas'
);
delete from public.meta_channel_sweep_tickets;
delete from net.http_request_queue;

select is(
  public.dispatch_meta_channel_sweeps(),
  0,
  'a channel whose contacts are all named dispatches nothing'
);

-- 8b. A photo that already arrived is a reason to sweep, with every contact
-- named.
select public.ingest_meta_message(
  'instagram', 'ig-sweep-account',
  'meta:instagram:message:ig-sweep-account:mid-photo', 'mid-photo',
  'ig-sweep-user-1', null, null, 'image', 'Imagen recibida',
  now() - interval '2 days',
  '{"message_id":"mid-photo","message_type":"image","attachment_types":["image"]}'::jsonb
);
select is(
  public.dispatch_meta_channel_sweeps(),
  1,
  'a message whose file never arrived gets its channel swept'
);
select is(
  (
    select array_agg(key order by key)
    from pg_temp.posted() posted, jsonb_object_keys(posted.body) key
  ),
  array['channel_id', 'token'],
  'with the same request: no message, no id of Meta, no URL'
);
update public.meta_webhook_events
set media_attached_at = clock_timestamp()
where external_message_id = 'mid-photo';
delete from public.meta_channel_sweep_tickets;
delete from net.http_request_queue;
select is(
  public.dispatch_meta_channel_sweeps(),
  0,
  'once its file is attached there is nothing left to sweep'
);

-- 9. The switch and a disconnected channel stop it.
select public.ingest_meta_message(
  'instagram', 'ig-sweep-account',
  'meta:instagram:message:ig-sweep-account:mid-2', 'mid-2',
  'ig-sweep-user-2', null, null, 'text', 'Buenas',
  now(), '{}'::jsonb
);

update public.meta_channel_sweep_runtime set enabled = false;
select is(
  public.dispatch_meta_channel_sweeps(),
  0,
  'the switch off dispatches nothing'
);
update public.meta_channel_sweep_runtime set enabled = true;

update public.meta_channels set is_active = false
where id = 'c0a75eeb-0001-4000-8000-000000000001';
select is(
  public.dispatch_meta_channel_sweeps(),
  0,
  'a disconnected channel dispatches nothing'
);
select is(
  (select count(*)::integer from pg_temp.posted()),
  0,
  'and nothing was posted meanwhile'
);

update public.meta_channels set is_active = true
where id = 'c0a75eeb-0001-4000-8000-000000000001';
select is(
  public.dispatch_meta_channel_sweeps(),
  1,
  'reconnected, it is swept'
);
update public.meta_channels set is_active = false
where id = 'c0a75eeb-0001-4000-8000-000000000001';
select is(
  public.redeem_meta_channel_sweep_ticket(
    'c0a75eeb-0001-4000-8000-000000000001',
    (select body->>'token' from pg_temp.posted() limit 1)
  ),
  null,
  'a ticket of a channel disconnected meanwhile opens nothing'
);

-- 10. The endpoint cannot be pointed elsewhere.
select throws_ok(
  $$update public.meta_channel_sweep_runtime
    set endpoint = 'https://example.invalid/functions/v1/other'$$,
  '23514',
  null,
  'the endpoint is the contact-profile function or nothing'
);

-- 11. It runs on a schedule.
select is(
  (
    select job.schedule || ' / ' || job.active::text
    from cron.job job
    where job.jobname = 'vinabike_meta_channel_sweep'
      and job.command = 'select public.dispatch_meta_channel_sweeps();'
  ),
  '7,22,37,52 * * * * / true',
  'the sweep is scheduled four times an hour'
);

-- 12. Only the server reaches any of it.
select is(
  has_function_privilege(
    'authenticated', 'public.dispatch_meta_channel_sweeps()', 'execute'
  )
  or has_function_privilege(
    'anon', 'public.dispatch_meta_channel_sweeps()', 'execute'
  )
  or has_function_privilege(
    'authenticated', 'public.redeem_meta_channel_sweep_ticket(uuid,text)', 'execute'
  )
  or has_function_privilege(
    'anon', 'public.redeem_meta_channel_sweep_ticket(uuid,text)', 'execute'
  )
  or has_table_privilege('authenticated', 'public.meta_channel_sweep_tickets', 'select')
  or has_table_privilege('anon', 'public.meta_channel_sweep_tickets', 'select')
  or has_table_privilege('authenticated', 'public.meta_channel_sweep_runtime', 'update')
  or has_table_privilege('anon', 'public.meta_channel_sweep_runtime', 'select'),
  false,
  'no signed-in or anonymous user can dispatch, redeem, read a ticket or move the endpoint'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(
  $$select public.redeem_meta_channel_sweep_ticket(
      'c0a75eeb-0001-4000-8000-000000000001', repeat('0', 64)
    )$$,
  '42501',
  null,
  'a signed-in user cannot redeem a ticket'
);
select throws_ok(
  $$select public.dispatch_meta_channel_sweeps()$$,
  '42501',
  null,
  'nor start a sweep'
);
reset role;

select * from finish();
rollback;
