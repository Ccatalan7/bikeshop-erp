-- Views inherit broad default privileges in the production role setup. Keep
-- the document-aware purchase list strictly read-only for application roles.
begin;

revoke all on public.purchase_invoice_list_read_model_v2
  from public, anon, authenticated, service_role;
grant select on public.purchase_invoice_list_read_model_v2
  to authenticated, service_role;

commit;
