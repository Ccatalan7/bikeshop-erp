-- Online orders placed to test the store are marked as tests, so the
-- operational list and its counters show only real sales (dueño, 2026-10-13:
-- «sí marca las pruebas»). On that day the tenant had 78 orders and only
-- WEB-26-00021 — «nuestra primera venta oficial» — was a sale; 22 of the tests
-- sat «Confirmado + Pagado» forever and filled any «por atender» view.
--
-- The mark is data a person can change: `set_online_order_test_flag` marks or
-- unmarks one order through the same optimistic, idempotent and audited
-- command shape as the internal notes, and the list offers it in each order's
-- menu. It hides nothing in the database: sales, stock and accounting of a
-- test order are untouched.

alter table public.online_orders
  add column if not exists is_test boolean not null default false;

comment on column public.online_orders.is_test is
  'Order placed to test the store. The operational list hides it by default; '
  'set_online_order_test_flag changes it with an audited event.';

alter table public.online_order_events
  drop constraint if exists online_order_events_event_type_check;
alter table public.online_order_events
  add constraint online_order_events_event_type_check check (
    event_type = any (array[
      'order_created',
      'status_transition',
      'payment_transition',
      'internal_note_updated',
      'test_flag_changed'
    ])
  );

alter table public.online_order_events
  drop constraint if exists online_order_events_check;
alter table public.online_order_events
  add constraint online_order_events_check check (
    (event_type = 'status_transition' and to_status is not null)
    or (event_type = 'payment_transition' and to_payment_status is not null)
    or event_type = any (array[
      'order_created',
      'internal_note_updated',
      'test_flag_changed'
    ])
  );

create or replace function public.set_online_order_test_flag(
  p_order_id uuid,
  p_is_test boolean,
  p_expected_version bigint default null,
  p_operation_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := coalesce(
    nullif(btrim(coalesce(p_operation_key, '')), ''),
    'online-order-test-flag:' || gen_random_uuid()::text
  );
  v_order public.online_orders%rowtype;
  v_updated public.online_orders%rowtype;
  v_event public.online_order_events%rowtype;
  v_request jsonb;
  v_response jsonb;
  v_changed boolean;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = '42501';
  end if;
  if p_order_id is null or p_is_test is null then
    raise exception 'Order and test flag are required' using errcode = '22004';
  end if;
  if length(v_operation_key) > 160 then
    raise exception 'Operation key is too long' using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'source', 'set_online_order_test_flag',
    'order_id', p_order_id,
    'is_test', p_is_test,
    'expected_version', p_expected_version
  );

  select event.* into v_event
    from public.online_order_events event
   where event.tenant_id = v_tenant_id
     and event.operation_key = v_operation_key;
  if found then
    if v_event.order_id is distinct from p_order_id
       or v_event.event_type <> 'test_flag_changed'
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'Operation key already belongs to another order change'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event)
      || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select orders.* into v_order
    from public.online_orders orders
   where orders.id = p_order_id
     and orders.tenant_id = v_tenant_id
   for update;
  if not found then
    raise exception 'Order not found or access denied: %', p_order_id
      using errcode = '42501';
  end if;
  if p_expected_version is not null
     and v_order.version <> p_expected_version then
    raise exception 'Order changed concurrently; expected version %, current version %',
      p_expected_version,
      v_order.version
      using errcode = '40001';
  end if;

  v_changed := v_order.is_test is distinct from p_is_test;
  if v_changed then
    update public.online_orders orders
       set is_test = p_is_test
     where orders.id = v_order.id
       and orders.tenant_id = v_order.tenant_id
     returning orders.* into v_updated;
  else
    v_updated := v_order;
  end if;

  v_response := jsonb_build_object(
    'success', true,
    'order_id', v_updated.id,
    'is_test', v_updated.is_test,
    'status', v_updated.status,
    'payment_status', v_updated.payment_status,
    'version', v_updated.version,
    'changed', v_changed
  );

  insert into public.online_order_events (
    tenant_id,
    order_id,
    event_type,
    from_status,
    to_status,
    from_payment_status,
    to_payment_status,
    changed,
    expected_version,
    result_version,
    actor_id,
    operation_key,
    request_snapshot,
    response_snapshot
  ) values (
    v_order.tenant_id,
    v_order.id,
    'test_flag_changed',
    v_order.status,
    v_updated.status,
    v_order.payment_status,
    v_updated.payment_status,
    v_changed,
    p_expected_version,
    v_updated.version,
    v_actor_id,
    v_operation_key,
    v_request,
    v_response
  ) returning * into v_event;

  return to_jsonb(v_event)
    || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.set_online_order_test_flag(
  uuid, boolean, bigint, text
) from public, anon, authenticated, service_role;
grant execute on function public.set_online_order_test_flag(
  uuid, boolean, bigint, text
) to authenticated;

-- Every order of the Viñabike tenant before its first official sale
-- (WEB-26-00021) was a test. Pinned to that order's id: anywhere it does not
-- exist (local, another project) this changes nothing.
update public.online_orders orders
   set is_test = true
  from public.online_orders first_sale
 where first_sale.id = '24328d78-5af2-48c6-9366-94371fa0d90a'
   and first_sale.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and orders.tenant_id = first_sale.tenant_id
   and orders.created_at < first_sale.created_at
   and orders.is_test is false;
