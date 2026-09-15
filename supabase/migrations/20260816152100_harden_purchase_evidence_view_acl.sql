-- Deployment status: DEPLOYED and registered on production
-- xzdvtzdqjeyqxnkqprtf on 2026-08-16; exact ACL read-back passed.
--
-- Purpose:
--   Remove bootstrap/default privileges inherited by the purchase-evidence
--   views. These operational read models are tenant-scoped through
--   security_invoker RLS and are available only to authenticated staff.
--
-- Forward behavior:
--   Revoke every view privilege from PUBLIC and the Supabase client roles,
--   then grant authenticated SELECT only.
-- Recovery behavior:
--   Re-grant a deliberately reviewed privilege to the exact role and view;
--   no business rows or view definitions are changed.
-- Lock risk:
--   ACL-only catalog changes with bounded lock and statement timeouts.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

revoke all on public.purchase_invoice_freight_components_v1
  from public, anon, authenticated, service_role;
revoke all on public.purchase_line_landed_cost_observations_v1
  from public, anon, authenticated, service_role;
revoke all on public.purchase_candidate_metrics_v1
  from public, anon, authenticated, service_role;

grant select on public.purchase_invoice_freight_components_v1
  to authenticated;
grant select on public.purchase_line_landed_cost_observations_v1
  to authenticated;
grant select on public.purchase_candidate_metrics_v1
  to authenticated;

notify pgrst, 'reload schema';

commit;
