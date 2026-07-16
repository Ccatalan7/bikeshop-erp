-- Deployment status: DEPLOYED AND VERIFIED IN PRODUCTION 2026-07-16.
--
-- Purpose:
--   Preserve the authenticated-only dashboard expense drill-down contract on
--   hosted/local Supabase installations whose default function privileges
--   grant EXECUTE directly to PUBLIC, anon and service_role. This migration
--   changes ACLs only; it performs no business DML or backfill.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

revoke all on function public.get_expense_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) from public, anon, service_role;

grant execute on function public.get_expense_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) to authenticated;

comment on function public.get_expense_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) is
  'Authenticated tenant-scoped dashboard expense drill-down; unavailable to PUBLIC, anon and service_role.';

commit;
