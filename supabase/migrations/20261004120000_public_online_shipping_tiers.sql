-- The shipping tiers the checkout charges, readable by the public store.
--
-- `online_shipping_rate_tiers` is the one owner of what an order pays for
-- shipping: `quote_online_shipping_internal` prices every checkout from it.
-- Staff read and write it; nobody else can, not even the deploy's service
-- role. The «Información de Envíos» page states the same tiers as text, and
-- since 2026-10-04 the store build declares them to Google as the business's
-- shipping service (`hasShippingService`). Both are public facts, so they get
-- a narrow public read of the active tiers instead of a grant on the table:
-- only the columns a customer sees, only active rows, only the tenant asked.
create or replace function public.get_public_online_shipping_tiers(
  p_tenant_id uuid
)
returns table (
  country_code text,
  min_order_gross numeric,
  max_order_gross numeric,
  shipping_gross numeric,
  estimated_min_business_days integer,
  estimated_max_business_days integer
)
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select tier.country_code,
         tier.min_order_gross,
         tier.max_order_gross,
         tier.shipping_gross,
         tier.estimated_min_business_days,
         tier.estimated_max_business_days
    from public.online_shipping_rate_tiers tier
   where tier.tenant_id = p_tenant_id
     and tier.is_active
   order by tier.country_code, tier.min_order_gross;
$$;

comment on function public.get_public_online_shipping_tiers(uuid) is
  'Active shipping tiers of one tenant, as the checkout charges them (quote_online_shipping_internal). Public facts: the shipping page and the store''s structured data read them.';

revoke all on function public.get_public_online_shipping_tiers(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_online_shipping_tiers(uuid)
  to anon, authenticated, service_role;
