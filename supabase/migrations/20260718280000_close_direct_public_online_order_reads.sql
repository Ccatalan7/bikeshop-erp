-- Close the remaining direct PostgREST surface on ecommerce order tables.
--
-- The tokenized RPC introduced by 20260718170000 removed UUID-only function
-- access, but two legacy anon SELECT policies still used USING (true), and old
-- table ACLs retained destructive privileges such as TRUNCATE. Public checkout
-- and order confirmation are SECURITY DEFINER RPCs and need no direct table
-- grant. ERP/customer sessions retain tenant/customer-scoped SELECT only;
-- every mutation continues through the audited lifecycle RPCs.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

do $$
begin
  if to_regclass('public.online_orders') is null
     or to_regclass('public.online_order_items') is null then
    raise exception 'Online order tables must exist before closing public access';
  end if;
end;
$$;

drop policy if exists public_online_orders_anon_select
  on public.online_orders;
drop policy if exists public_online_order_items_anon_select
  on public.online_order_items;

-- Revoke the complete legacy ACL, not only SELECT. TRUNCATE bypasses RLS and
-- therefore cannot safely remain available to any client-facing API role.
revoke all on table public.online_orders
  from public, anon, authenticated;
revoke all on table public.online_order_items
  from public, anon, authenticated;

-- Authenticated ERP/customer reads remain governed by the existing
-- tenant/customer RLS policies. Inserts, transitions, cancellations, payments
-- and corrections must use their dedicated RPCs.
grant select on table public.online_orders to authenticated;
grant select on table public.online_order_items to authenticated;

comment on table public.online_orders is
  'Canonical ecommerce order aggregate. No anonymous direct table access; public reads require a hashed access-token RPC and mutations require audited commands.';
comment on table public.online_order_items is
  'Immutable-at-checkout order lines. No anonymous direct table access; public projection is available only through the access-token RPC.';

commit;
