-- Seed payment methods for your current tenant
-- This will create the 4 default payment methods you need for the dropdown

SELECT public.seed_payment_methods_for_tenant(public.user_tenant_id());
